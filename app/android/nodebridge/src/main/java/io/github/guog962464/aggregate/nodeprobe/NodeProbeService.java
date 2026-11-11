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
    public static final int EVENT = 7;
    public static final int CANCEL = 8;
    private static final String TAG = "A3NodeProbe";

    private static native int nativeStart(String entry, String output, int delayMs, String events, boolean fail);

    private final String generation = UUID.randomUUID().toString();
    private final AtomicBoolean started = new AtomicBoolean();
    private final Messenger incoming = new Messenger(new Handler(Looper.getMainLooper(), this::handle));
    private Messenger activeReply;
    private int activeRequestId;

    @Override
    public android.os.IBinder onBind(Intent intent) {
        return incoming.getBinder();
    }

    private boolean handle(Message request) {
        if (request.what == CRASH) {
            android.os.Process.killProcess(android.os.Process.myPid());
            return true;
        }
        if (request.what == CANCEL) {
            if (activeReply != null && request.arg1 == activeRequestId) {
                send(activeReply, EVENT, "{\"type\":\"cancelRequested\"}", 0, 0, activeRequestId);
                new Handler(Looper.getMainLooper()).postDelayed(
                        () -> android.os.Process.killProcess(android.os.Process.myPid()), 80);
            }
            return true;
        }
        if (request.what != RUN || request.replyTo == null) return false;
        final Messenger reply = request.replyTo;
        final int requestId = request.arg1;
        final boolean autoClose = request.getData().getBoolean("autoClose", false);
        final int delayMs = request.getData().getInt("delayMs", 0);
        final boolean fail = request.getData().getBoolean("fail", false);
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
        activeReply = reply;
        activeRequestId = requestId;
        send(reply, STARTED, "worker started", 0, 0, requestId);
        new Thread(() -> run(reply, requestId, autoClose, delayMs, fail), "a3-node-worker").start();
        return true;
    }

    private void run(Messenger reply, int requestId, boolean autoClose, int delayMs, boolean fail) {
        long startedAt = System.nanoTime();
        try {
            File entry = new File(getFilesDir(), "a3-probe.js");
            File output = new File(getFilesDir(), "a3-result.json");
            File events = new File(getFilesDir(), "a3-events.jsonl");
            try (InputStream source = getAssets().open("probe.js");
                 FileOutputStream destination = new FileOutputStream(entry, false)) {
                byte[] buffer = new byte[8192];
                int count;
                while ((count = source.read(buffer)) != -1) destination.write(buffer, 0, count);
            }
            if (output.exists() && !output.delete()) throw new IllegalStateException("old output not removed");
            if (events.exists() && !events.delete()) throw new IllegalStateException("old events not removed");
            System.loadLibrary("aggregate_node_probe");
            AtomicBoolean finished = new AtomicBoolean();
            Thread eventReader = new Thread(
                    () -> watchEvents(events, finished, reply, requestId), "a3-event-reader");
            eventReader.start();
            int exitCode;
            try {
                exitCode = nativeStart(entry.getAbsolutePath(), output.getAbsolutePath(), delayMs,
                        events.getAbsolutePath(), fail);
            } finally {
                finished.set(true);
                eventReader.join(1000);
            }
            long elapsed = (System.nanoTime() - startedAt) / 1_000_000;
            if (exitCode != 0 || !output.isFile()) {
                send(reply, ERROR, "Node exit=" + exitCode + ", output missing=" + !output.isFile(), exitCode, elapsed, requestId);
            } else {
                String payload = readFile(output);
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

    private void watchEvents(File file, AtomicBoolean finished, Messenger reply, int requestId) {
        int delivered = 0;
        while (true) {
            try {
                if (file.isFile()) {
                    if (file.length() > 65536) {
                        send(reply, EVENT, "{\"type\":\"truncated\"}", 0, 0, requestId);
                        return;
                    }
                    String[] lines = readFile(file).split("\\n", -1);
                    for (int index = delivered; index < lines.length - 1; index++) {
                        if (!lines[index].isEmpty()) send(reply, EVENT, lines[index], 0, 0, requestId);
                    }
                    delivered = lines.length - 1;
                }
                if (finished.get()) return;
                Thread.sleep(10);
            } catch (Exception failure) {
                Log.e(TAG, "Node event reader failed", failure);
                return;
            }
        }
    }

    private String readFile(File file) throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (InputStream source = new FileInputStream(file)) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = source.read(buffer)) != -1) bytes.write(buffer, 0, count);
        }
        return new String(bytes.toByteArray(), StandardCharsets.UTF_8);
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
