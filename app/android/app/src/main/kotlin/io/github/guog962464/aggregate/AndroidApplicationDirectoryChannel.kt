package io.github.guog962464.aggregate

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class AndroidApplicationDirectoryChannel(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, AutoCloseable {
    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != METHOD_APPLICATION_SUPPORT_DIRECTORY) {
            result.notImplemented()
            return
        }
        result.success(appContext.filesDir.absolutePath)
    }

    override fun close() {
        channel.setMethodCallHandler(null)
    }

    private companion object {
        const val CHANNEL_NAME = "aggregate/application_directory"
        const val METHOD_APPLICATION_SUPPORT_DIRECTORY = "applicationSupportDirectory"
    }
}
