#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════
#  xzm 管理器 · 独立 WebUI 本地服务
#  用 busybox httpd 托管 webroot 静态页 + cgi-bin/shell（root 执行桥接）
#  不依赖 SukiSU 的 WebUI，通知栏按钮直接用浏览器打开本服务。
# ═══════════════════════════════════════════════════════════════

MODDIR="${0%/*}/.."
[ -f "$MODDIR/module.prop" ] || MODDIR="/data/adb/modules/xzm_manager"
DATA_DIR="${XZM_DATA_DIR:-/data/adb/xzm_manager}"

PORT="${XZM_WEBUI_PORT:-7690}"
HOST="0.0.0.0"
PIDFILE="$DATA_DIR/state/webui.pid"
LOGFILE="$DATA_DIR/logs/webui.log"
RUNROOT="$DATA_DIR/run/webui"

BB="/data/adb/ksu/bin/busybox"
[ -x "$BB" ] || BB="$(command -v busybox 2>/dev/null)"
[ -n "$BB" ] || BB="/data/adb/magisk/busybox"

mkdir -p "$DATA_DIR/state" "$DATA_DIR/logs" "$RUNROOT/cgi-bin" 2>/dev/null

# ── stop ──
if [ "$1" = "stop" ]; then
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
  fi
  pkill -f "httpd -p $HOST:$PORT" 2>/dev/null
  exit 0
fi

# ── stop existing then start ──
if [ -f "$PIDFILE" ]; then
  kill "$(cat "$PIDFILE")" 2>/dev/null
  rm -f "$PIDFILE"
fi
pkill -f "httpd -p $HOST:$PORT" 2>/dev/null
sleep 0.3

# 准备运行根：软链/拷贝静态资源 + CGI
rm -rf "$RUNROOT" 2>/dev/null
mkdir -p "$RUNROOT/cgi-bin" 2>/dev/null
# 静态页：用模块 webroot 里的内联 index.html
cp -f "$MODDIR/webroot/index.html" "$RUNROOT/index.html" 2>/dev/null
# CGI 执行桥接
if [ -f "$MODDIR/webroot-cgi/shell" ]; then
  cp -f "$MODDIR/webroot-cgi/shell" "$RUNROOT/cgi-bin/shell" 2>/dev/null
fi
chmod 0755 "$RUNROOT/cgi-bin/shell" 2>/dev/null
chown 0:0 "$RUNROOT/cgi-bin/shell" 2>/dev/null
chmod 0644 "$RUNROOT/index.html" 2>/dev/null

# 启动 busybox httpd（前台后台化）
"$BB" httpd -p "$HOST:$PORT" -h "$RUNROOT" >>"$LOGFILE" 2>&1 &
PID=$!
echo "$PID" > "$PIDFILE"
sleep 0.6

# 验证
if pgrep -f "httpd -p $HOST:$PORT" >/dev/null 2>&1; then
  echo "webui: listening on http://$HOST:$PORT/ (pid=$PID)"
else
  echo "webui: FAILED to start (see $LOGFILE)"
fi
