import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.util.Base64;
import java.io.ByteArrayOutputStream;
import java.lang.reflect.Method;
import java.util.List;

/**
 * AppLister —— 通过 app_process 运行，列出已安装应用的 中文名/包名/版本/图标(base64 png)
 * 用法: app_process -Djava.class.path=<dir> / <dir> AppLister [iconSize] [pkgFilter]
 * 输出: 每行一个 JSON: {"pkg":"...","label":"...","ver":"...","icon":"data:image/png;base64,..."}
 */
public class AppLister {
    public static void main(String[] args) {
        int iconPx = 96;
        if (args.length > 0) { try { iconPx = Integer.parseInt(args[0]); } catch (Exception e) {} }
        String filter = args.length > 1 ? args[1] : null;
        // 第三个参数 "noicon" → 不生成图标（体积小，弱设备兜底）
        boolean noIcon = args.length > 2 && "noicon".equals(args[2]);

        try {
            android.os.Looper.prepare();
            Class<?> atClass = Class.forName("android.app.ActivityThread");
            Method sysMain = atClass.getMethod("systemMain");
            Object thread = sysMain.invoke(null);
            Context ctx = (Context) atClass.getMethod("getSystemContext").invoke(thread);
            if (ctx == null) {
                Method getCtx = atClass.getMethod("getSystemContext");
                ctx = (Context) getCtx.invoke(thread);
            }
            PackageManager pm = ctx.getPackageManager();

            List<ApplicationInfo> apps = pm.getInstalledApplications(0);
            StringBuilder out = new StringBuilder();
            boolean first = true;
            out.append("{\"ok\":true,\"apps\":[");
            for (ApplicationInfo ai : apps) {
                if (filter != null && !ai.packageName.equals(filter)) continue;
                // 仅第三方
                if (filter == null && (ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0) continue;

                String label = "";
                try { label = String.valueOf(pm.getApplicationLabel(ai)); } catch (Throwable t) {}
                String ver = "";
                try { ver = String.valueOf(pm.getPackageInfo(ai.packageName, 0).versionName); } catch (Throwable t) {}
                String icon = "";
                if (!noIcon) {
                    try {
                        Drawable d = pm.getApplicationIcon(ai);
                        icon = drawableToDataUri(d, iconPx);
                    } catch (Throwable t) {}
                }
                if (!first) out.append(",");
                first = false;
                out.append("{\"pkg\":\"").append(esc(ai.packageName)).append("\"");
                out.append(",\"label\":\"").append(esc(label)).append("\"");
                out.append(",\"ver\":\"").append(esc(ver)).append("\"");
                out.append(",\"icon\":\"").append(icon).append("\"}");
            }
            out.append("]}");
            System.out.println(out.toString());
        } catch (Throwable t) {
            Throwable c = t;
            if (t instanceof java.lang.reflect.InvocationTargetException && t.getCause() != null) c = t.getCause();
            java.io.StringWriter sw = new java.io.StringWriter();
            c.printStackTrace(new java.io.PrintWriter(sw));
            String st = sw.toString().replace("\n", " | ").replace("\t", " ");
            System.out.println("{\"error\":\"" + esc(String.valueOf(c)) + " :: " + esc(st).substring(0, Math.min(300, esc(st).length())) + "\"}");
        }
    }

    static String drawableToDataUri(Drawable d, int px) {
        try {
            int w = d.getIntrinsicWidth(); if (w <= 0) w = px;
            int h = d.getIntrinsicHeight(); if (h <= 0) h = px;
            d.setBounds(0, 0, px, px);
            Bitmap bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888);
            Canvas c = new Canvas(bmp);
            d.draw(c);
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            bmp.compress(Bitmap.CompressFormat.PNG, 100, bo);
            byte[] bytes = bo.toByteArray();
            String b64 = Base64.encodeToString(bytes, Base64.NO_WRAP);
            return "data:image/png;base64," + b64;
        } catch (Throwable t) {
            return "";
        }
    }

    static String esc(String s) {
        if (s == null) return "";
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20) { b.append(String.format("\\u%04x", (int) c)); }
                    else b.append(c);
            }
        }
        return b.toString();
    }
}
