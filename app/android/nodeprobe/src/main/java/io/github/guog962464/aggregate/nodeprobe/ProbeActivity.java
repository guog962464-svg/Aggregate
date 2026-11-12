package io.github.guog962464.aggregate.nodeprobe;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;
import android.util.Base64;
import android.util.Log;
import android.widget.TextView;

import java.nio.charset.StandardCharsets;

public final class ProbeActivity extends Activity {
    private static final String TAG = "A3NodeProbe";
    private TextView status;
    private Messenger nodeService;
    private boolean cancelOnReady;
    private boolean cancelSent;
    private boolean npmRequestSent;
    private boolean boundaryRequestSent;
    private final Messenger incoming = new Messenger(new Handler(Looper.getMainLooper(), this::handle));
    private boolean bound;
    private final ServiceConnection connection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder binder) {
            if (cancelSent) return;
            String probe = getIntent().getStringExtra("probe");
            if ("a4-npm".equals(probe)) {
                if (npmRequestSent) return;
                npmRequestSent = true;
            }
            if ("a4-boundary".equals(probe)) {
                if (boundaryRequestSent) return;
                boundaryRequestSent = true;
            }
            nodeService = new Messenger(binder);
            try {
                sendRun(nodeService, 1, probe,
                        getCliArgs("cliArgsJson", "cliArgsBase64"));
                String secondCliArgs = getCliArgs("secondCliArgsJson", "secondCliArgsBase64");
                if (secondCliArgs != null) sendRun(nodeService, 2, probe, secondCliArgs);
            } catch (RemoteException failure) {
                status.setText(failure.toString());
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            status.setText("Node service disconnected");
            Log.e(TAG, "SERVICE_DISCONNECTED");
        }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        status = new TextView(this);
        status.setText("Binding Node probe service…");
        status.setTextSize(18);
        status.setPadding(32, 64, 32, 32);
        setContentView(status);
        if ("a4-profile".equals(getIntent().getStringExtra("probe"))) {
            A4ProfileProbe.run(this, getIntent());
            finish();
            return;
        }
        cancelOnReady = getIntent().getBooleanExtra("cancelOnReady", false);
        bound = bindService(new Intent(this, NodeProbeService.class), connection, Context.BIND_AUTO_CREATE);
        if (!bound) status.setText("Node service bind failed");
    }

    private void sendRun(Messenger service, int requestId, String probe, String cliArgsJson)
            throws RemoteException {
        Message request = Message.obtain(null, NodeProbeService.RUN);
        request.arg1 = requestId;
        request.replyTo = incoming;
        if ("a4-json5".equals(probe) || "a4-json5-cli".equals(probe)
                || "a4-npm".equals(probe) || "a4-boundary".equals(probe)) {
            Bundle arguments = new Bundle();
            arguments.putString("entrypoint", probe);
            if ("a4-json5-cli".equals(probe)) {
                arguments.putString("cliArgsJson",
                        cliArgsJson == null ? "[\"--version\"]" : cliArgsJson);
            } else if ("a4-npm".equals(probe)) {
                arguments.putString("npmAction", getIntent().getStringExtra("npmAction"));
                arguments.putBoolean("autoClose", true);
            } else if ("a4-boundary".equals(probe)) {
                arguments.putString("boundaryAction", getIntent().getStringExtra("boundaryAction"));
                arguments.putBoolean("autoClose", true);
            }
            request.setData(arguments);
        }
        service.send(request);
    }

    private String getCliArgs(String jsonExtra, String base64Extra) {
        String encoded = getIntent().getStringExtra(base64Extra);
        if (encoded != null) {
            return new String(Base64.decode(encoded, Base64.DEFAULT), StandardCharsets.UTF_8);
        }
        return getIntent().getStringExtra(jsonExtra);
    }

    private boolean handle(Message event) {
        Bundle data = event.getData();
        String detail = data.getString("detail", "");
        String line = "kind=" + event.what + " requestId=" + event.arg1 + " generation=" + data.getString("generation")
                + " exit=" + data.getInt("exitCode") + " elapsedMs=" + data.getLong("elapsedMs")
                + " detail=" + detail;
        status.setText(line);
        Log.i(TAG, line);
        if (cancelOnReady && !cancelSent && event.what == NodeProbeService.EVENT
                && detail.contains("\"type\":\"ready\"")) {
            cancelSent = true;
            Message cancel = Message.obtain(null, NodeProbeService.CANCEL);
            cancel.arg1 = 1;
            try {
                if (nodeService != null) nodeService.send(cancel);
            } catch (RemoteException failure) {
                Log.e(TAG, "Unable to send cancellation", failure);
            }
        }
        return true;
    }

    @Override
    protected void onDestroy() {
        if (bound) unbindService(connection);
        super.onDestroy();
    }
}
