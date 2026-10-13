package com.xzm.launcher;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;

/** 通知 + 启动独立 WebUI 工具 */
public class NotifyHelper {

    public static final String CH_ID = "xzm_launcher";
    public static final int NOTIF_ID = 0x584D01; // "XM" 01

    public static final int WEBUI_PORT = 7690;

    /** 确保前台服务在运行（在 App 处于前台时调用才会被系统允许） */
    public static void ensureService(Context ctx) {
        try {
            Intent i = new Intent(ctx, NotifyService.class);
            if (Build.VERSION.SDK_INT >= 26) {
                ctx.startForegroundService(i);
            } else {
                ctx.startService(i);
            }
        } catch (Exception ignored) {}
    }

    /** 打开独立 WebUI（我们自己的 WebView 容器，不含 SukiSU） */
    public static void openWebUI(Context ctx) {
        openWebUI(ctx, null);
    }

    public static void openWebUI(Context ctx, String page) {
        Intent i = new Intent(ctx, WebUIActivity.class);
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (page != null && !page.isEmpty()) i.putExtra("page", page);
        try {
            ctx.startActivity(i);
        } catch (Exception e) {
            // 退化：用浏览器打开本地服务
            try {
                Intent b = new Intent(Intent.ACTION_VIEW,
                        Uri.parse("http://127.0.0.1:" + WEBUI_PORT + "/"));
                b.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                ctx.startActivity(b);
            } catch (Exception ignored) {}
        }
    }

    /** 打开某个动作 */
    public static void openAction(Context ctx, String action) {
        if ("terminal".equals(action)) {
            openWebUI(ctx, "term");
        } else {
            openWebUI(ctx, null);
        }
    }

    static PendingIntent pi(Context ctx, String action, int reqCode) {
        Intent i = new Intent(ctx, MainActivity.class);
        i.setAction("com.xzm.launcher.ACTION_" + action);
        i.putExtra("xzm_action", action);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
        return PendingIntent.getActivity(ctx, reqCode, i, flags);
    }

    public static Notification buildNotification(Context ctx) {
        ensureChannel(ctx);

        PendingIntent openPend = pi(ctx, "open", 101);
        PendingIntent termPend = pi(ctx, "terminal", 102);

        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= 26) {
            b = new Notification.Builder(ctx, CH_ID);
        } else {
            b = new Notification.Builder(ctx);
        }

        b.setContentTitle("xzm 管理器")
         .setContentText(ctx.getString(R.string.notif_text))
         .setSmallIcon(android.R.drawable.ic_menu_manage)
         .setOngoing(true)
         .setContentIntent(openPend)
         .setShowWhen(false);

        b.addAction(new Notification.Action.Builder(
                android.R.drawable.ic_menu_manage, ctx.getString(R.string.act_open), openPend).build());
        b.addAction(new Notification.Action.Builder(
                android.R.drawable.ic_menu_view, ctx.getString(R.string.act_term), termPend).build());

        b.setPriority(Notification.PRIORITY_DEFAULT);
        return b.build();
    }

    static void ensureChannel(Context ctx) {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager nm = ctx.getSystemService(NotificationManager.class);
            if (nm == null) return;
            NotificationChannel existing = nm.getNotificationChannel(CH_ID);
            if (existing == null) {
                NotificationChannel ch = new NotificationChannel(
                        CH_ID, "xzm 管理器", NotificationManager.IMPORTANCE_DEFAULT);
                ch.setShowBadge(false);
                ch.setSound(null, null);
                ch.enableVibration(false);
                nm.createNotificationChannel(ch);
            } else if (existing.getImportance() < NotificationManager.IMPORTANCE_DEFAULT) {
                // 老版本建的是 LOW 渠道，升级后提升可见性（渠道 importance 创建即锁定，只能删重建）
                nm.deleteNotificationChannel(CH_ID);
                NotificationChannel ch = new NotificationChannel(
                        CH_ID, "xzm 管理器", NotificationManager.IMPORTANCE_DEFAULT);
                ch.setShowBadge(false);
                ch.setSound(null, null);
                ch.enableVibration(false);
                nm.createNotificationChannel(ch);
            }
        }
    }
}
