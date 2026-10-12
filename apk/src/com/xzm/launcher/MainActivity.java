package com.xzm.launcher;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/**
 * xzm 管理器 · 伴随启动器
 * 作为 Launcher 图标入口 + 被通知点击/按钮唤起时执行动作。
 *   - 点击图标 / 通知本体 → 打开 WebUI
 *   - 通知「打开管理界面」→ 打开 WebUI
 *   - 通知「终端」→ 打开 WebUI 并直达终端页
 */
public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        dispatch(getIntent());
        finish();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        dispatch(intent);
        finish();
    }

    private void dispatch(Intent intent) {
        String action = null;
        if (intent != null) {
            action = intent.getStringExtra("xzm_action");
            if (action == null && intent.getAction() != null
                    && intent.getAction().startsWith("com.xzm.launcher.ACTION_")) {
                action = intent.getAction().substring("com.xzm.launcher.ACTION_".length());
            }
        }
        if ("terminal".equals(action)) {
            NotifyHelper.openAction(this, "terminal");
        } else {
            // 默认：确保清除"跳终端"标记后打开管理界面
            NotifyHelper.openAction(this, "open");
        }
    }
}
