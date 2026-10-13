#!/system/bin/sh
# xzm 管理器 · 通知栏常驻入口
# 常驻通知 + 一键打开 WebUI（KernelSU / SukiSU / APatch / MMRL 自适应）
#
# 用法:
#   xzm-notify.sh on      发布常驻通知
#   xzm-notify.sh off     取消通知
#   xzm-notify.sh open    仅打开 WebUI（供通知点击时调用）
#   xzm-notify.sh probe   打印探测结果（管理器包名 / 深链）

MODDIR=${0%/*}
DATA_DIR=/data/adb/xzm_manager
LOG=$DATA_DIR/logs/notify.log
TAG=xzm_manager
CH_ID=xzm_manager

log(){ echo "[$(date '+%H:%M:%S')] $*" >> "$LOG" 2>/dev/null; }

# ── 找管理器包名 + 主 Activity ──
# SukiSU Ultra=com.sukisu.ultra；KernelSU=me.weishu.kernelsu；MMRL=com.dergoogler.mmrl；APatch=me.bmax.apatch
detect_manager(){
  PM=$(command -v pm || echo /system/bin/pm)
  for p in com.sukisu.ultra com.sukisu.ultra.susfs com.sukisu.ultra.superkey \
           me.weishu.kernelsu com.dergoogler.mmrl \
           me.bmax.apatch com.apatch com.apatch.next ; do
    if "$PM" path "$p" >/dev/null 2>&1; then echo "$p"; return; fi
  done
  echo ""
}

# ── 打开 WebUI ──
open_webui(){
  # 0) 首选伴随 APK 的深链（最稳，直接进 WebUIActivity）
  if pm path com.xzm.launcher >/dev/null 2>&1; then
    am start -a android.intent.action.VIEW -d "xzmlaunch://open" -n com.xzm.launcher/.MainActivity >/dev/null 2>&1 && { log "opened via apk deeplink"; return 0; }
    am start -n com.xzm.launcher/.MainActivity >/dev/null 2>&1 && { log "opened apk main"; return 0; }
  fi
  M=$(detect_manager)
  log "open_webui manager=$M"
  # 1) ksu://webui 深链（KernelSU / SukiSU 系）
  if [ -n "$M" ]; then
    am start -a android.intent.action.VIEW -d "ksu://webui/xzm_manager" \
      -n "$M/.ui.MainActivity" >/dev/null 2>&1 && { log "opened via ksu://webui"; return 0; }
    am start -a android.intent.action.VIEW -d "ksu://webui/xzm_manager" >/dev/null 2>&1 && { log "opened via ksu://webui(implicit)"; return 0; }
    # 2) 退而求其次：打开管理器主界面
    am start -n "$M/.ui.MainActivity" >/dev/null 2>&1 && { log "opened manager main"; return 0; }
    monkey -p "$M" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 && { log "opened via monkey"; return 0; }
  fi
  log "no entry; fallback open browser to local webui"
  am start -a android.intent.action.VIEW -d "http://127.0.0.1:7690/" >/dev/null 2>&1 && { log "opened in browser"; return 0; }
  return 1
}

# ── 发布通知 ──
post_notify(){
  DT=$(date '+%m-%d %H:%M')
  MSG="点击打开管理界面 · 更新于 $DT"
  # Android 11+ 的 cmd notification（需要 root）
  if cmd notification post -S bigtext -t "xzm 管理器" "$TAG" "$MSG" >/dev/null 2>&1; then
    log "posted via cmd notification"
    return 0
  fi
  # 某些系统用 -o 常驻
  if cmd notification post -o -S bigtext -t "xzm 管理器" "$TAG" "$MSG" >/dev/null 2>&1; then
    log "posted via cmd notification -o"
    return 0
  fi
  log "post failed"
  return 1
}

cancel_notify(){
  cmd notification cancel "$TAG" >/dev/null 2>&1
  log "cancelled"
}

case "$1" in
  on)    post_notify ;;
  off)   cancel_notify ;;
  open)  open_webui ;;
  probe)
    M=$(detect_manager)
    [ -n "$M" ] && echo "manager=$M" || echo "manager=none"
    C=$(command -v cmd); [ -n "$C" ] && echo "cmd=$C" || echo "cmd=none"
    A=$(command -v am); [ -n "$A" ] && echo "am=$A" || echo "am=none"
    echo "--- cmd notification help ---"
    cmd notification help 2>&1 | head -40
    echo "--- am 能力 ---"
    am 2>&1 | head -5
    ;;
  *) echo "usage: $0 {on|off|open|probe}" ;;
esac
