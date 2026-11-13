package io.github.guog962464.aggregate

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var nodeProbeChannel: NodeProbeChannel? = null
    private var hostDeviceKeyStoreChannel: HostDeviceKeyStoreChannel? = null
    private var hostDiscoveryChannel: HostDiscoveryChannel? = null
    private var documentContentChannel: AndroidDocumentContentChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nodeProbeChannel = NodeProbeChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        hostDeviceKeyStoreChannel = HostDeviceKeyStoreChannel(flutterEngine.dartExecutor.binaryMessenger)
        hostDiscoveryChannel = HostDiscoveryChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        documentContentChannel = AndroidDocumentContentChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documentContentChannel?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        nodeProbeChannel?.close()
        nodeProbeChannel = null
        hostDeviceKeyStoreChannel?.close()
        hostDeviceKeyStoreChannel = null
        hostDiscoveryChannel?.close()
        hostDiscoveryChannel = null
        documentContentChannel?.close()
        documentContentChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
