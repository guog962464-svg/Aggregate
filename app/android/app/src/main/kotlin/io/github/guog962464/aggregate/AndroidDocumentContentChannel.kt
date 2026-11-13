package io.github.guog962464.aggregate

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Reads a selected small text file directly into memory without retaining its URI or a cache copy. */
internal class AndroidDocumentContentChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, AutoCloseable {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPick: PendingPick? = null
    private var closed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != METHOD_PICK_TEXT) {
            result.notImplemented()
            return
        }
        if (closed) {
            result.error("picker_unavailable", "文档选择暂不可用。", null)
            return
        }
        if (pendingPick != null) {
            result.error("picker_busy", "已有文档选择正在进行。", null)
            return
        }

        val pick = PendingPick(result)
        pendingPick = pick
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
            }
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (_: Exception) {
            finish(pick) {
                it.error("picker_unavailable", "无法打开系统文档选择器。", null)
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val pick = pendingPick ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            finish(pick) { it.success(null) }
            return true
        }

        try {
            worker.execute {
                try {
                    val bytes = readBoundedText(uri)
                    finish(pick) { it.success(bytes) }
                } catch (_: FileTooLargeException) {
                    finish(pick) {
                        it.error("file_too_large", "所选文件不能超过 32 KiB。", null)
                    }
                } catch (_: Exception) {
                    finish(pick) {
                        it.error("file_read_failed", "无法读取所选文件，请重新选择。", null)
                    }
                }
            }
        } catch (_: Exception) {
            finish(pick) { it.error("picker_unavailable", "文档读取暂不可用。", null) }
        }
        return true
    }

    private fun readBoundedText(uri: Uri): ByteArray {
        val input = activity.contentResolver.openInputStream(uri)
            ?: throw IOException("The selected document is unavailable")
        input.use { stream ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(BUFFER_BYTES)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                if (output.size() > MAX_BYTES - count) throw FileTooLargeException()
                output.write(buffer, 0, count)
            }
            return output.toByteArray()
        }
    }

    private fun finish(pick: PendingPick, complete: (MethodChannel.Result) -> Unit) {
        mainHandler.post {
            if (!pick.completed.compareAndSet(false, true)) return@post
            if (pendingPick === pick) pendingPick = null
            complete(pick.result)
        }
    }

    override fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        pendingPick?.let { pick ->
            finish(pick) { it.error("picker_cancelled", "文档选择已中断。", null) }
        }
        worker.shutdownNow()
    }

    private class PendingPick(val result: MethodChannel.Result) {
        val completed = AtomicBoolean(false)
    }

    private class FileTooLargeException : Exception()

    private companion object {
        const val CHANNEL_NAME = "aggregate/document_content"
        const val METHOD_PICK_TEXT = "pickSmallText"
        const val REQUEST_CODE = 0x583F
        const val MAX_BYTES = 32 * 1024
        const val BUFFER_BYTES = 4096
    }
}
