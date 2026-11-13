package io.github.guog962464.aggregate

import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.Executors

/** Keeps the Android Host identity private key inside Android Keystore. */
internal class HostDeviceKeyStoreChannel(messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler,
    AutoCloseable {
    private val channel = MethodChannel(messenger, "aggregate/host_identity")
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadOrCreate" -> execute(result) { loadOrCreate() }
            "sign" -> {
                val encoded = call.argument<String>("message")
                if (encoded == null) {
                    result.error("invalid_args", "Missing signing message", null)
                } else {
                    execute(result) { sign(encoded) }
                }
            }
            "delete" -> execute(result) {
                keyStore().deleteEntry(KEY_ALIAS)
                true
            }
            else -> result.notImplemented()
        }
    }

    private fun execute(result: MethodChannel.Result, action: () -> Any?) {
        executor.execute {
            try {
                val value = action()
                mainHandler.post { result.success(value) }
            } catch (_: Exception) {
                mainHandler.post {
                    result.error("keystore_failure", "Device identity operation failed", null)
                }
            }
        }
    }

    private fun loadOrCreate(): Map<String, String> {
        val store = keyStore()
        if (!store.containsAlias(KEY_ALIAS)) {
            val generator = KeyPairGenerator.getInstance("EC", "AndroidKeyStore")
            generator.initialize(
                android.security.keystore.KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    android.security.keystore.KeyProperties.PURPOSE_SIGN,
                )
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(android.security.keystore.KeyProperties.DIGEST_SHA256)
                    .build(),
            )
            generator.generateKeyPair()
        }

        val publicKey = store.getCertificate(KEY_ALIAS)?.publicKey
            ?: error("Missing device identity certificate")
        val encoded = publicKey.encoded
        val deviceSuffix = MessageDigest.getInstance("SHA-256")
            .digest(encoded)
            .take(16)
            .joinToString("") { "%02x".format(it) }
        return mapOf(
            "deviceId" to "device-$deviceSuffix",
            "publicKeySpki" to Base64.encodeToString(encoded, Base64.NO_WRAP),
        )
    }

    private fun sign(encodedMessage: String): String {
        val message = Base64.decode(encodedMessage, Base64.NO_WRAP)
        require(message.isNotEmpty() && message.size <= MAX_SIGNING_BYTES)
        val privateKey = keyStore().getKey(KEY_ALIAS, null) as? PrivateKey
            ?: error("Missing device identity key")
        val signature = Signature.getInstance("SHA256withECDSA").run {
            initSign(privateKey)
            update(message)
            sign()
        }
        return Base64.encodeToString(signature, Base64.NO_WRAP)
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply {
        load(null)
    }

    override fun close() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private companion object {
        const val KEY_ALIAS = "aggregate.host.device.p256.v1"
        const val MAX_SIGNING_BYTES = 1024 * 1024
    }
}
