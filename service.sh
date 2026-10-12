#!/system/bin/sh
# xzm 管理器 · 开机服务脚本
MODDIR=${0%/*}
DATA_DIR=/data/adb/xzm_manager

mkdir -p "$DATA_DIR/scripts" "$DATA_DIR/logs" "$DATA_DIR/state" "$DATA_DIR/bin" "$DATA_DIR/run" "$DATA_DIR/prefs" 2>/dev/null
chmod 0700 "$DATA_DIR/prefs" 2>/dev/null || :

chmod 0755 "$MODDIR/service.sh" "$MODDIR/action.sh" "$MODDIR/uninstall.sh" \
  "$MODDIR/bin/xzmctl.sh" "$MODDIR/bin/xzm-shell.sh" "$MODDIR/bin/xzm-notify.sh" "$MODDIR/bin/xzm-webui.sh" "$MODDIR/bin/ttyd" "$MODDIR/bin/bash" 2>/dev/null

# 准备终端运行时二进制（若存在）
for b in ttyd dtach bash; do
  if [ -f "$MODDIR/bin/$b" ]; then
    cp -f "$MODDIR/bin/$b" "$DATA_DIR/bin/$b" 2>/dev/null
    chown 0:0 "$DATA_DIR/bin/$b" 2>/dev/null
    chmod 0755 "$DATA_DIR/bin/$b" 2>/dev/null
  fi
done
if [ -f "$MODDIR/bin/xzm-shell.sh" ]; then
  cp -f "$MODDIR/bin/xzm-shell.sh" "$DATA_DIR/bin/xzm-shell.sh" 2>/dev/null
  chown 0:0 "$DATA_DIR/bin/xzm-shell.sh" 2>/dev/null
  chmod 0755 "$DATA_DIR/bin/xzm-shell.sh" 2>/dev/null
fi

# 清理上一次遗留的终端状态
stale_sock="$(cat "$DATA_DIR/state/terminal.socket.path" 2>/dev/null)"
case "$stale_sock" in
  "$DATA_DIR/state"/*|/data/local/tmp/.xzm-*) rm -f "$stale_sock" 2>/dev/null ;;
esac
rm -f "$DATA_DIR/state/terminal.pid" "$DATA_DIR/state/terminal.socket.path" \
      "$DATA_DIR/state/terminal.mode" 2>/dev/null

echo "[$(date '+%Y-%m-%d %H:%M:%S')] xzm 管理器已随系统启动" >> "$DATA_DIR/logs/module.log"

# 复制通知脚本到数据目录
if [ -f "$MODDIR/bin/xzm-notify.sh" ]; then
  cp -f "$MODDIR/bin/xzm-notify.sh" "$DATA_DIR/bin/xzm-notify.sh" 2>/dev/null
  chmod 0755 "$DATA_DIR/bin/xzm-notify.sh" 2>/dev/null
fi

# 后台延迟：提取 intent_token（APK 部署交给 /data/adb/boot-completed.d/xzm_manager.sh）
(
  sleep 20

  LOG="$DATA_DIR/logs/notify.log"
  TOKENFILE=/data/local/tmp/.xzm_ksu_token

  # 提取 SukiSU/KernelSU 的 intent_token（供 APK 拼 deeplink）
  TOKEN=""
  for p in \
      /data/data/com.sukisu.ultra/shared_prefs/settings.xml \
      /data/data/me.weishu.kernelsu/shared_prefs/settings.xml \
      /data/data/com.dergoogler.mmrl/shared_prefs/settings.xml ; do
    if [ -f "$p" ]; then
      TOKEN=$(sed -n 's/.*name="intent_token">\([^<]*\)<.*/\1/p' "$p" 2>/dev/null | head -1)
      [ -n "$TOKEN" ] && break
    fi
  done
  if [ -n "$TOKEN" ]; then
    echo "$TOKEN" > "$TOKENFILE"
    chmod 0644 "$TOKENFILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] token captured (len=${#TOKEN})" >> "$LOG"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] no intent_token found (will retry via hook)" >> "$LOG"
  fi
) &

# ── 启动独立 WebUI 本地服务（busybox httpd，通知栏按钮直达）──
(
  sleep 8
  sh "$MODDIR/bin/xzm-webui.sh" >> "$DATA_DIR/logs/webui.log" 2>&1
) &
