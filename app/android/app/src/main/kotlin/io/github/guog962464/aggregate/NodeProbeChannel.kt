package io.github.guog962464.aggregate

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Debug-only transport to the isolated, one-shot Node experiment. */
internal class NodeProbeChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, ServiceConnection {
    private val channel = MethodChannel(messenger, "aggregate/node_probe")
    private val handler = Handler(Looper.getMainLooper()) { event -> onEvent(event) }
    private val incoming = Messenger(handler)
    private var pending: MethodChannel.Result? = null
    private var terminal: Map<String, Any?>? = null
    private var requestId = 0
    private var generation: String? = null
    private var bound = false
    private var remote: Messenger? = null
    private var delayMs = 0

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            result.error("unavailable", "Node probe is debug-only", null)
            return
        }
        if (call.method == "crash") {
            val service = remote
            if (pending == null || service == null) {
                result.error("unavailable", "No active Node probe", null)
                return
            }
            try {
                service.send(Message.obtain(null, 6))
                result.success(null)
            } catch (failure: RemoteException) {
                result.error("transport", failure.message, null)
            }
            return
        }
        if (call.method != "run") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("busy", "Node probe already running", null)
            return
        }
        val requestedDelay = call.argument<Int>("delayMs") ?: 0
        if (requestedDelay !in 0..5000) {
            result.error("invalidArgument", "delayMs must be 0..5000", null)
            return
        }
        delayMs = requestedDelay
        pending = result
        terminal = null
        generation = null
        requestId++
        val id = requestId
        val intent = Intent().setClassName(
            context,
            "io.github.guog962464.aggregate.nodeprobe.NodeProbeService",
        )
        bound = context.bindService(intent, this, Context.BIND_AUTO_CREATE)
        if (!bound) {
            finishError("unavailable", "Node probe library is not in this APK")
            return
        }
        handler.postDelayed({
            if (pending != null && requestId == id) {
                finishError("timeout", "Node probe did not finish in 15 seconds")
            }
        }, 15_000)
    }

    override fun onServiceConnected(name: ComponentName, binder: IBinder) {
        if (pending == null) return
        remote = Messenger(binder)
        val request = Message.obtain(null, 1, requestId, 0)
        request.replyTo = incoming
        request.data = Bundle().apply {
            putBoolean("autoClose", true)
            putInt("delayMs", delayMs)
        }
        try {
            remote?.send(request)
        } catch (failure: RemoteException) {
            finishError("transport", failure.message ?: "Node service disconnected")
        }
    }

    override fun onServiceDisconnected(name: ComponentName) {
        remote = null
        val completed = terminal
        if (completed == null) {
            finishError("outcomeUnknown", "Node process exited before returning a result")
        } else if (completed["kind"] == 3) {
            pending?.success(completed)
            clear()
        } else {
            finishError("nodeFailure", completed["detail"] as? String ?: "Node failed")
        }
    }

    private fun onEvent(event: Message): Boolean {
        if (pending == null || event.arg1 != requestId) return true
        val data = event.data
        val eventGeneration = data.getString("generation") ?: return true
        if (generation == null && (event.what == 2 || event.what == 4)) {
            generation = eventGeneration
        }
        if (eventGeneration != generation) return true
        val payload: Map<String, Any?> = mapOf(
            "kind" to event.what,
            "requestId" to event.arg1,
            "generation" to eventGeneration,
            "detail" to data.getString("detail"),
            "exitCode" to data.getInt("exitCode"),
            "elapsedMs" to data.getLong("elapsedMs"),
        )
        channel.invokeMethod("event", payload)
        if (event.what == 3 || event.what == 4) terminal = payload
        return true
    }

    private fun finishError(code: String, message: String) {
        pending?.error(code, message, null)
        clear()
    }

    private fun clear() {
        pending = null
        terminal = null
        generation = null
        remote = null
        delayMs = 0
        if (bound) {
            context.unbindService(this)
            bound = false
        }
    }

    fun close() {
        if (pending != null) finishError("cancelled", "Flutter engine closed")
        channel.setMethodCallHandler(null)
    }
}
