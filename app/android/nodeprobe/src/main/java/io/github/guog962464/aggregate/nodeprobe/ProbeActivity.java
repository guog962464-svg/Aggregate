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
import android.util.Log;
import android.widget.TextView;

public final class ProbeActivity extends Activity {
    private static final String TAG = "A3NodeProbe";
    private TextView status;
    private final Messenger incoming = new Messenger(new Handler(Looper.getMainLooper(), this::handle));
    private boolean bound;
    private final ServiceConnection connection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder binder) {
            Message request = Message.obtain(null, NodeProbeService.RUN);
            request.arg1 = 1;
            request.replyTo = incoming;
            if ("a4-json5".equals(getIntent().getStringExtra("probe"))) {
                Bundle arguments = new Bundle();
                arguments.putString("entrypoint", "a4-json5");
                request.setData(arguments);
            }
            try {
                new Messenger(binder).send(request);
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
        bound = bindService(new Intent(this, NodeProbeService.class), connection, Context.BIND_AUTO_CREATE);
        if (!bound) status.setText("Node service bind failed");
    }

    private boolean handle(Message event) {
        Bundle data = event.getData();
        String detail = data.getString("detail", "");
        String line = "kind=" + event.what + " requestId=" + event.arg1 + " generation=" + data.getString("generation")
                + " exit=" + data.getInt("exitCode") + " elapsedMs=" + data.getLong("elapsedMs")
                + " detail=" + detail;
        status.setText(line);
        Log.i(TAG, line);
        return true;
    }

    @Override
    protected void onDestroy() {
        if (bound) unbindService(connection);
        super.onDestroy();
    }
}
