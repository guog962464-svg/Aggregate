package io.github.guog962464.aggregate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var nodeProbeChannel: NodeProbeChannel? = null
    private var hostDeviceKeyStoreChannel: HostDeviceKeyStoreChannel? = null
    private var hostDiscoveryChannel: HostDiscoveryChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nodeProbeChannel = NodeProbeChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        hostDeviceKeyStoreChannel = HostDeviceKeyStoreChannel(flutterEngine.dartExecutor.binaryMessenger)
        hostDiscoveryChannel = HostDiscoveryChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        nodeProbeChannel?.close()
        nodeProbeChannel = null
        hostDeviceKeyStoreChannel?.close()
        hostDeviceKeyStoreChannel = null
        hostDiscoveryChannel?.close()
        hostDiscoveryChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
