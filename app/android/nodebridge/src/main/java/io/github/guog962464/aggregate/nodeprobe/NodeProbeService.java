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
    public static final int CAPABILITIES = 9;
    public static final int CAPABILITIES_RESULT = 10;
    private static final String TAG = "A3NodeProbe";

    private static native int nativeStart(String entry, String output, int delayMs, String events, boolean fail);
    private static native String nativeHeaderVersion();

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
        if (request.what == CAPABILITIES && request.replyTo != null) {
            int id = request.arg1;
            try {
                System.loadLibrary("aggregate_node_probe");
                String detail = "{\"packaged\":true,\"protocol\":1,\"entrypoints\":[\"a3-fixed\"],"
                        + "\"headerVersion\":\"" + nativeHeaderVersion() + "\","
                        + "\"npm\":false,\"cli\":false,\"profiles\":false}";
                send(request.replyTo, CAPABILITIES_RESULT, detail, 0, 0, id);
            } catch (Throwable failure) {
                send(request.replyTo, ERROR, failure.toString(), -1, 0, id, "unavailable");
            }
            closeIfRequested(request.getData().getBoolean("autoClose", false), request.replyTo, id);
            return true;
        }
        if (request.what != RUN || request.replyTo == null) return false;
        final Messenger reply = request.replyTo;
        final int requestId = request.arg1;
        final boolean autoClose = request.getData().getBoolean("autoClose", false);
        final int delayMs = request.getData().getInt("delayMs", 0);
        final boolean fail = request.getData().getBoolean("fail", false);
        final String entrypoint = request.getData().getString("entrypoint", "a3-fixed");
        final String profileRef = request.getData().getString("profileRef");
        final String draftId = request.getData().getString("draftId");
        final String expectedGeneration = request.getData().getString("expectedGeneration");
        if (!"a3-fixed".equals(entrypoint)) {
            reject(reply, requestId, autoClose, "invalidEntrypoint", "entrypoint is not allowed");
            return true;
        }
        if (profileRef != null || draftId != null) {
            reject(reply, requestId, autoClose, "invalidReference", "profile and draft references are not supported");
            return true;
        }
        if (expectedGeneration != null && !generation.equals(expectedGeneration)) {
            reject(reply, requestId, autoClose, "staleGeneration", "Node process generation changed");
            return true;
        }
        if (delayMs < 0 || delayMs > 90000) {
            reject(reply, requestId, autoClose, "invalidArgument", "invalid delay");
            return true;
        }
        if (requestId <= 0) {
            reject(reply, requestId, autoClose, "invalidArgument", "request ID required");
            return true;
        }
        if (!started.compareAndSet(false, true)) {
            reject(reply, requestId, autoClose, "busy", "Node instance already started");
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
            closeIfRequested(autoClose, reply, requestId);
        }
    }

    private void reject(Messenger reply, int requestId, boolean autoClose, String code, String detail) {
        send(reply, ERROR, detail, -1, 0, requestId, code);
        closeIfRequested(autoClose, reply, requestId);
    }

    private void closeIfRequested(boolean autoClose, Messenger reply, int requestId) {
        if (!autoClose) return;
        send(reply, CLOSING, "Node process closing", 0, 0, requestId);
        new Handler(Looper.getMainLooper()).postDelayed(
                () -> android.os.Process.killProcess(android.os.Process.myPid()), 200);
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
        send(reply, kind, detail, exitCode, elapsed, requestId, null);
    }

    private void send(Messenger reply, int kind, String detail, int exitCode, long elapsed, int requestId, String errorCode) {
        Message event = Message.obtain(null, kind);
        event.arg1 = requestId;
        Bundle data = new Bundle();
        data.putString("generation", generation);
        data.putString("detail", detail);
        data.putInt("exitCode", exitCode);
        data.putLong("elapsedMs", elapsed);
        if (errorCode != null) data.putString("errorCode", errorCode);
        event.setData(data);
        try {
            reply.send(event);
        } catch (RemoteException failure) {
            Log.w(TAG, "Probe client disconnected", failure);
        }
    }
}
