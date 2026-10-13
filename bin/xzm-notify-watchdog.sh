#!/system/bin/sh
# xzm-notify-watchdog.sh —— 维持常驻通知存活
# 场景：用户从最近任务划掉 App、系统清后台、或前台服务被杀 → 自动重新拉起。
# 用法： sh xzm-notify-watchdog.sh start|stop|once
# 说明：单实例；用 pidfile 防重复；每 45 秒检查一次。

DATA_DIR="${XZM_DATA_DIR:-/data/adb/xzm_manager}"
PIDFILE="$DATA_DIR/run/notify-watchdog.pid"
LOGF="$DATA_DIR/logs/notify-watchdog.log"

alive() {
  # 是否已有 xzm 常驻 notify 在前台服务
  if dumpsys activity services com.xzm.launcher 2>/dev/null | grep -q "NotifyService" \
     && dumpsys activity services com.xzm.launcher 2>/dev/null | grep -q "isForeground=true"; then
    return 0
  fi
  return 1
}

start_service() {
  # 优先前台服务；失败用广播
  am start-foreground-service -n com.xzm.launcher/.NotifyService >/dev/null 2>&1
  sleep 1
  if ! alive; then
    am broadcast -a com.xzm.launcher.START_NOTIFY -n com.xzm.launcher/.BootReceiver >/dev/null 2>&1
  fi
}

run_loop() {
  echo "$$" > "$PIDFILE"
  while true; do
    if ! alive; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] notify dead → restart" >> "$LOGF"
      start_service
    fi
    sleep 45
  done
}

stop() {
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
  fi
}

case "$1" in
  start)
    # 用进程名去重（比 pidfile 更可靠：可能被调试方式拉起多个）
    cnt=0
    for p in /proc/*/cmdline; do
      tr '\0' ' ' < "$p" 2>/dev/null | grep -q "xzm-notify-watchdog.sh __loop" && cnt=$((cnt+1))
    done
    if [ "$cnt" -gt 0 ]; then
      exit 0   # 已在跑
    fi
    mkdir -p "$DATA_DIR/run" "$DATA_DIR/logs" 2>/dev/null
    # 用 setsid 完全脱离父进程（否则 adb/service.sh 退出后会被 SIGHUP 杀掉）
    if command -v setsid >/dev/null 2>&1; then
      setsid sh "$0" __loop </dev/null >>"$LOGF" 2>&1 &
    elif command -v nohup >/dev/null 2>&1; then
      nohup sh "$0" __loop </dev/null >>"$LOGF" 2>&1 &
    else
      ( sh "$0" __loop </dev/null >>"$LOGF" 2>&1 & )
    fi
    ;;
  __loop) run_loop ;;
  stop) stop ;;
  once) start_service ;;
  *) start_service ;;
esac
