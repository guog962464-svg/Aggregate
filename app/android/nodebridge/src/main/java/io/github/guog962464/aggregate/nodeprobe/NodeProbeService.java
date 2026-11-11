package io.github.guog962464.aggregate.nodeprobe;

import android.app.Service;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;

public final class NodeProbeService extends Service {
    public static final int RUN = 1;
    public static final int STARTED = 2;
    public static final int RESULT = 3;
    public static final int ERROR = 4;
    public static final int CLOSING = 5;
    public static final int CRASH = 6;
    private static final String TAG = "A3NodeProbe";

    private static native int nativeStart(String entry, String output, int delayMs);

    private final String generation = UUID.randomUUID().toString();
    private final AtomicBoolean started = new AtomicBoolean();
    private final Messenger incoming = new Messenger(new Handler(Looper.getMainLooper(), this::handle));

    @Override
    public android.os.IBinder onBind(Intent intent) {
        return incoming.getBinder();
    }

    private boolean handle(Message request) {
        if (request.what == CRASH) {
            android.os.Process.killProcess(android.os.Process.myPid());
            return true;
        }
        if (request.what != RUN || request.replyTo == null) return false;
        final Messenger reply = request.replyTo;
        final int requestId = request.arg1;
        final boolean autoClose = request.getData().getBoolean("autoClose", false);
        final int delayMs = request.getData().getInt("delayMs", 0);
        if (delayMs < 0 || delayMs > 5000) {
            send(reply, ERROR, "invalid delay", -1, 0, requestId);
            return true;
        }
        if (requestId <= 0) {
            send(reply, ERROR, "request ID required", -1, 0, requestId);
            return true;
        }
        if (!started.compareAndSet(false, true)) {
            send(reply, ERROR, "Node instance already started", -1, 0, requestId);
            return true;
        }
        send(reply, STARTED, "worker started", 0, 0, requestId);
        new Thread(() -> run(reply, requestId, autoClose, delayMs), "a3-node-worker").start();
        return true;
    }

    private void run(Messenger reply, int requestId, boolean autoClose, int delayMs) {
        long startedAt = System.nanoTime();
        try {
            File entry = new File(getFilesDir(), "a3-probe.js");
            File output = new File(getFilesDir(), "a3-result.json");
            try (InputStream source = getAssets().open("probe.js");
                 FileOutputStream destination = new FileOutputStream(entry, false)) {
                byte[] buffer = new byte[8192];
                int count;
                while ((count = source.read(buffer)) != -1) destination.write(buffer, 0, count);
            }
            if (output.exists() && !output.delete()) throw new IllegalStateException("old output not removed");
            System.loadLibrary("aggregate_node_probe");
            int exitCode = nativeStart(entry.getAbsolutePath(), output.getAbsolutePath(), delayMs);
            long elapsed = (System.nanoTime() - startedAt) / 1_000_000;
            if (exitCode != 0 || !output.isFile()) {
                send(reply, ERROR, "Node exit=" + exitCode + ", output missing=" + !output.isFile(), exitCode, elapsed, requestId);
            } else {
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                try (InputStream source = new FileInputStream(output)) {
                    byte[] buffer = new byte[8192];
                    int count;
                    while ((count = source.read(buffer)) != -1) bytes.write(buffer, 0, count);
                }
                String payload = new String(bytes.toByteArray(), StandardCharsets.UTF_8);
                send(reply, RESULT, payload, exitCode, elapsed, requestId);
            }
        } catch (Throwable failure) {
            Log.e(TAG, "Node probe failed", failure);
            send(reply, ERROR, failure.toString(), -1, (System.nanoTime() - startedAt) / 1_000_000, requestId);
        } finally {
            if (autoClose) {
                send(reply, CLOSING, "Node process closing", 0, 0, requestId);
                new Handler(Looper.getMainLooper()).postDelayed(
                        () -> android.os.Process.killProcess(android.os.Process.myPid()), 200);
            }
        }
    }

    private void send(Messenger reply, int kind, String detail, int exitCode, long elapsed, int requestId) {
        Message event = Message.obtain(null, kind);
        event.arg1 = requestId;
        Bundle data = new Bundle();
        data.putString("generation", generation);
        data.putString("detail", detail);
        data.putInt("exitCode", exitCode);
        data.putLong("elapsedMs", elapsed);
        event.setData(data);
        try {
            reply.send(event);
        } catch (RemoteException failure) {
            Log.w(TAG, "Probe client disconnected", failure);
        }
    }
}
