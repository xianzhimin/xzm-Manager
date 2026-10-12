#!/system/bin/sh
# xzm 管理器 · 终端启动包装
# 被 ttyd 调用：  xzm-shell.sh [target] [mode]
#   target : 要运行的脚本/可执行文件（可选）——运行完进入 root shell
#   mode   : normal | private（过检：不落痕）
export TERM=xterm-256color
export COLORTERM=truecolor
export PATH=/data/adb/xzm_manager/bin:/data/adb/magisk:/data/adb/ksu/bin:/system/bin:/system/xbin:/vendor/bin:$PATH

TARGET="$1"
MODE="${2:-normal}"
[ "$MODE" = "private" ] || MODE="normal"

if [ "$MODE" = "private" ]; then
  DIR="/data/local/tmp/.xzm-$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-')"
  mkdir -p "$DIR" 2>/dev/null; chmod 0700 "$DIR" 2>/dev/null
  export HOME="$DIR" TMPDIR="$DIR" HISTFILE=/dev/null ENV=/dev/null
  PS1='# '
else
  mkdir -p /data/adb/xzm_manager/home /data/adb/xzm_manager/tmp 2>/dev/null
  export HOME=/data/adb/xzm_manager/home
  export TMPDIR=/data/adb/xzm_manager/tmp
  PS1='xzm:\w # '
fi
export SHELL=/system/bin/sh
cd /sdcard 2>/dev/null || cd /data/adb 2>/dev/null || cd /

BASH=/data/adb/xzm_manager/bin/bash

# 运行目标文件（若给出）
if [ -n "$TARGET" ] && [ -e "$TARGET" ]; then
  echo "▶ 运行：$TARGET"
  echo
  case "$TARGET" in
    *.sh)
      if [ -x "$BASH" ]; then "$BASH" "$TARGET"; else sh "$TARGET"; fi
      code=$? ;;
    *)
      # 判断是否 ELF（可执行）
      magic="$(od -An -tx1 -N4 "$TARGET" 2>/dev/null | tr -d ' \r\n')"
      if [ "$magic" = "7f454c46" ]; then
        cp -f "$TARGET" "$TMPDIR/$(basename "$TARGET")" 2>/dev/null
        chmod 0755 "$TMPDIR/$(basename "$TARGET")" 2>/dev/null
        ( cd "$(dirname "$TARGET")" && "$TMPDIR/$(basename "$TARGET")" )
      else
        sh "$TARGET"
      fi
      code=$? ;;
  esac
  echo
  echo "[退出码 $code]"
  echo "已进入 root shell，可继续输入命令。"
  echo
fi
# 兼容旧的 pending_cmd 机制
PENDING="/data/adb/xzm_manager/state/pending_cmd.sh"
if [ -s "$PENDING" ]; then
  sh "$PENDING"
  rm -f "$PENDING" 2>/dev/null
fi

if [ "$MODE" = "private" ]; then
  exec /system/bin/sh -i
fi
exec /system/bin/sh
