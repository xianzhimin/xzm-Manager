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
# 关键：Android 14+/ColorOS 上 `cmd notification post` 只会发一条"shell 通知"，
# 不常驻也不在通知栏显示。正解是让伴随 APK 的前台服务(NotifyService)来发常驻通知。
post_notify(){
  DT=$(date '+%m-%d %H:%M')
  MSG="点击打开管理界面 · 更新于 $DT"

  # 0) 首选：拉起 APK 的前台服务（真正常驻、带图标、点击打开 WebUI）
  if pm path com.xzm.launcher >/dev/null 2>&1; then
    am start-foreground-service -n com.xzm.launcher/.NotifyService >/dev/null 2>&1
    local rc=$?
    sleep 1
    # 校验是否真的起来了（前台服务存在 = 通知在栏）
    if dumpsys activity services com.xzm.launcher 2>/dev/null | grep -q "NotifyService" \
       && dumpsys activity services com.xzm.launcher 2>/dev/null | grep -q "isForeground=true"; then
      log "posted via APK foreground service"
      return 0
    fi
    # 后台启动被拒时，退一步：用 APK 广播让 App 自己在前台态拉起
    am broadcast -a com.xzm.launcher.START_NOTIFY -n com.xzm.launcher/.BootReceiver >/dev/null 2>&1
    sleep 1
    if dumpsys activity services com.xzm.launcher 2>/dev/null | grep -q "isForeground=true"; then
      log "posted via APK bootreceiver"
      return 0
    fi
    log "apk service start blocked (rc=$rc), fallback to cmd notification"
  fi

  # 1) 兜底：Android 11+ 的 cmd notification（部分 ROM 上是 shell 通知，不常驻）
  if cmd notification post -S bigtext -t "xzm 管理器" "$TAG" "$MSG" >/dev/null 2>&1; then
    log "posted via cmd notification (fallback)"
    return 0
  fi
  log "post failed"
  return 1
}

cancel_notify(){
  # 停掉 APK 前台服务 + 清 shell 通知
  am stopservice -n com.xzm.launcher/.NotifyService >/dev/null 2>&1
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
