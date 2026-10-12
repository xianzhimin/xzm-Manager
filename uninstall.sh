#!/system/bin/sh
# xzm 管理器 · 卸载清理（保留用户数据目录）
DATA_DIR=/data/adb/xzm_manager

# 停止终端进程
pid="$(cat "$DATA_DIR/state/terminal.pid" 2>/dev/null)"
[ -z "$pid" ] || kill "$pid" 2>/dev/null
sock="$(cat "$DATA_DIR/state/terminal.socket.path" 2>/dev/null)"
case "$sock" in
  "$DATA_DIR/state"/*|/data/local/tmp/.xzm-*) rm -f "$sock" 2>/dev/null ;;
esac
rm -f "$DATA_DIR/state/terminal.pid" "$DATA_DIR/state/terminal.socket.path" \
      "$DATA_DIR/state/terminal.mode" 2>/dev/null

echo "[$(date '+%Y-%m-%d %H:%M:%S')] xzm 管理器模块已卸载，用户数据保留" >> "$DATA_DIR/logs/module.log" 2>/dev/null
