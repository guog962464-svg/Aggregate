package io.github.guog962464.aggregate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var nodeProbeChannel: NodeProbeChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nodeProbeChannel = NodeProbeChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        nodeProbeChannel?.close()
        nodeProbeChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
