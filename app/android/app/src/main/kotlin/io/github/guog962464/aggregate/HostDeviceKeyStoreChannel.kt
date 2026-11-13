package io.github.guog962464.aggregate

import android.content.Context
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
import java.util.UUID

/** Keeps the Android Host identity private key inside Android Keystore. */
internal class HostDeviceKeyStoreChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) :
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
            "rotate" -> execute(result) { rotate() }
            "sign" -> {
                val encoded = call.argument<String>("message")
                if (encoded == null) {
                    result.error("invalid_args", "Missing signing message", null)
                } else {
                    execute(result) { sign(encoded) }
                }
            }
            "delete" -> execute(result) {
                val store = keyStore()
                store.aliases().toList()
                    .filter { it == KEY_ALIAS || it.startsWith(ROTATED_ALIAS_PREFIX) }
                    .forEach(store::deleteEntry)
                preferences().edit().remove(ACTIVE_ALIAS_KEY).commit()
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
        val alias = activeAlias()
        ensureKey(store, alias)
        if (preferences().getString(ACTIVE_ALIAS_KEY, null) == null) {
            preferences().edit().putString(ACTIVE_ALIAS_KEY, alias).commit()
        }
        return identityFor(store, alias)
    }

    /**
     * Generates a replacement before switching the active alias. If generation
     * or the preference commit fails, the current identity remains usable.
     */
    private fun rotate(): Map<String, String> {
        val store = keyStore()
        val previousAlias = activeAlias()
        val nextAlias = "$ROTATED_ALIAS_PREFIX${UUID.randomUUID()}"
        ensureKey(store, nextAlias)
        val nextIdentity = identityFor(store, nextAlias)
        if (!preferences().edit().putString(ACTIVE_ALIAS_KEY, nextAlias).commit()) {
            store.deleteEntry(nextAlias)
            error("Unable to activate the replacement device identity")
        }
        if (previousAlias != nextAlias) {
            try {
                store.deleteEntry(previousAlias)
            } catch (_: Exception) {
                // The new alias is active; an orphaned old key is never selected.
            }
        }
        return nextIdentity
    }

    private fun ensureKey(store: KeyStore, alias: String) {
        if (store.containsAlias(alias)) return
        val generator = KeyPairGenerator.getInstance("EC", "AndroidKeyStore")
        generator.initialize(
            android.security.keystore.KeyGenParameterSpec.Builder(
                alias,
                android.security.keystore.KeyProperties.PURPOSE_SIGN,
            )
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(android.security.keystore.KeyProperties.DIGEST_SHA256)
                .build(),
        )
        generator.generateKeyPair()
    }

    private fun identityFor(store: KeyStore, alias: String): Map<String, String> {
        val publicKey = store.getCertificate(alias)?.publicKey
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
        val privateKey = keyStore().getKey(activeAlias(), null) as? PrivateKey
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

    private fun activeAlias(): String =
        preferences().getString(ACTIVE_ALIAS_KEY, null) ?: KEY_ALIAS

    private fun preferences() = context.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    override fun close() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private companion object {
        const val KEY_ALIAS = "aggregate.host.device.p256.v1"
        const val ROTATED_ALIAS_PREFIX = "aggregate.host.device.p256.rotated."
        const val ACTIVE_ALIAS_KEY = "active_key_alias"
        const val PREFERENCES_NAME = "aggregate.host.identity"
        const val MAX_SIGNING_BYTES = 1024 * 1024
    }
}
