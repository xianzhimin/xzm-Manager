package com.xzm.launcher;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/** 开机自启 / 模块触发：拉起前台服务（模块 service.sh 也会兜底调用） */
public class BootReceiver extends BroadcastReceiver {
    public static final String ACTION_START = "com.xzm.launcher.START_NOTIFY";

    @Override
    public void onReceive(Context ctx, Intent intent) {
        Intent i = new Intent(ctx, NotifyService.class);
        if (Build.VERSION.SDK_INT >= 26) {
            ctx.startForegroundService(i);
        } else {
            ctx.startService(i);
        }
    }
}
