package com.xzm.launcher;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.ViewGroup;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.Collections;
import java.util.Enumeration;

/**
 * xzm 管理器 · 独立 WebUI 容器
 * 加载模块自建的本地服务（busybox httpd，绑定 0.0.0.0），彻底不经过 SukiSU。
 * 注意：root 命名空间的 127.0.0.1 应用无法访问，必须用设备的实际 IP。
 */
public class WebUIActivity extends Activity {

    public static final int PORT = 7690;
    private WebView web;
    private String base;   // http://<ip>:PORT

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // App 处于前台，此时拉起前台服务（常驻通知）是系统允许的
        NotifyHelper.ensureService(this);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.WHITE);

        web = new WebView(this);
        WebSettings ws = web.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setDatabaseEnabled(true);
        ws.setLoadWithOverviewMode(true);
        ws.setUseWideViewPort(true);
        ws.setAllowFileAccess(false);
        ws.setAllowContentAccess(false);
        ws.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        if (Build.VERSION.SDK_INT >= 19) WebView.setWebContentsDebuggingEnabled(true);

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, String url) {
                if (url != null && url.contains(":" + PORT + "/")) return false;       // 本服务
                if (url != null && url.contains(":7681")) return false;               // ttyd 终端
                try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url))); } catch (Exception ignored) {}
                return true;
            }
        });
        web.setWebChromeClient(new WebChromeClient());

        root.addView(web, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        setContentView(root);

        String ip = findLocalIp();
        base = "http://" + ip + ":" + PORT;
        load(hashFromIntent(getIntent()));
    }

    private String hashFromIntent(Intent it) {
        if (it == null) return "";
        String p = it.getStringExtra("page");
        return (p == null || p.isEmpty()) ? "" : ("#" + p);
    }

    private void load(String hash) {
        web.loadUrl(base + "/" + hash);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String h = hashFromIntent(intent);
        if (!h.isEmpty()) web.loadUrl(base + "/" + h);
        else web.loadUrl(base + "/");
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    /** 取设备第一个非回环 IPv4 地址 */
    static String findLocalIp() {
        try {
            Enumeration<NetworkInterface> ifs = NetworkInterface.getNetworkInterfaces();
            for (NetworkInterface ni : Collections.list(ifs)) {
                if (!ni.isUp() || ni.isLoopback()) continue;
                String nm = ni.getName();
                if (nm == null) continue;
                // 优先 wlan / 其他非 rmnet
                for (InetAddress a : Collections.list(ni.getInetAddresses())) {
                    if (a instanceof Inet4Address && !a.isLoopbackAddress()) {
                        String ip = a.getHostAddress();
                        if (ip != null && !ip.startsWith("127.")) {
                            if (nm.startsWith("wlan")) return ip;   // 优先无线
                        }
                    }
                }
            }
            // 次选：任意非回环 IPv4
            for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                for (InetAddress a : Collections.list(ni.getInetAddresses())) {
                    if (a instanceof Inet4Address && !a.isLoopbackAddress()) {
                        String ip = a.getHostAddress();
                        if (ip != null && !ip.startsWith("127.")) return ip;
                    }
                }
            }
        } catch (Exception ignored) {}
        return "127.0.0.1"; // 兜底
    }
}
