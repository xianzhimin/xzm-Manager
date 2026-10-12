package com.xzm.launcher;

import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;

/** 前台服务：维持常驻通知 */
public class NotifyService extends Service {

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // 若被通知按钮点了"terminal"等动作
        if (intent != null && intent.hasExtra("xzm_action")) {
            String a = intent.getStringExtra("xzm_action");
            if (a != null && !"open".equals(a)) {
                NotifyHelper.openAction(this, a);
            }
        }

        android.app.Notification n = NotifyHelper.buildNotification(this);
        if (Build.VERSION.SDK_INT >= 26) {
            startForeground(NotifyHelper.NOTIF_ID, n);
        } else {
            startForeground(NotifyHelper.NOTIF_ID, n);
        }
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}
