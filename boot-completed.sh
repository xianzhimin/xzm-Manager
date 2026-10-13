#!/system/bin/sh
# xzm 管理器 · 开机完成后部署（boot-completed.d 钩子）
# 说明：pm/appops/am 需要系统服务就绪；boot-completed 阶段执行最稳。
# 安装时由 customize.sh 复制到 /data/adb/boot-completed.d/xzm_manager.sh
#
# ⚠️ 重要：日志必须写到 /data/local/tmp。若把 pm 的 stdout/stderr 重定向到
#    /data/adb/... 下的文件，cmd 会 "Failed transaction"（SELinux 限制）。

MODDIR=/data/adb/modules/xzm_manager
DATA_DIR=/data/adb/xzm_manager
PKG=com.xzm.launcher
APK="$DATA_DIR/payload/xzm-launcher.apk"
TOKENFILE=/data/local/tmp/.xzm_ksu_token
LOG=/data/local/tmp/.xzm_hook.log

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null; }

# 若模块已被卸载，清理自身
if [ ! -d "$MODDIR" ]; then
    rm -f /data/adb/boot-completed.d/xzm_manager.sh 2>/dev/null
    exit 0
fi

log "hook start (domain=$(cat /proc/self/attr/current 2>/dev/null))"

# 0) 提取 SukiSU/KernelSU 的 intent_token
#    token 在管理器 App 首次启动时才随机生成；未生成时重试等待。
extract_token() {
    for p in \
        /data/data/com.sukisu.ultra/shared_prefs/settings.xml \
        /data/data/me.weishu.kernelsu/shared_prefs/settings.xml \
        /data/data/com.dergoogler.mmrl/shared_prefs/settings.xml ; do
        if [ -f "$p" ]; then
            t=$(sed -n 's/.*name="intent_token">\([^<]*\)<.*/\1/p' "$p" 2>/dev/null | head -1)
            [ -n "$t" ] && { echo "$t"; return 0; }
        fi
    done
    return 1
}

TOKEN=$(extract_token)
if [ -z "$TOKEN" ]; then
    # 等最多 60s，期间若管理器被打开就能拿到 token
    i=1
    while [ "$i" -le 20 ]; do
        sleep 3
        TOKEN=$(extract_token)
        [ -n "$TOKEN" ] && break
        i=$((i + 1))
    done
fi
if [ -n "$TOKEN" ]; then
    echo "$TOKEN" > "$TOKENFILE"
    chmod 0644 "$TOKENFILE"
    log "token captured (len=${#TOKEN})"
else
    log "no intent_token yet (manager not launched); will be written on next boot or by APK"
fi

# 1) 安装 APK（未装时）
#    /data/adb 直接安装被 SELinux 拒；管道 cat|pm 不稳定；
#    复制到 /data/local/tmp 用路径安装最稳；且不重定向到 /data/adb。
if [ -f "$APK" ] && ! pm path "$PKG" >/dev/null 2>&1; then
    TMPAPK=/data/local/tmp/xzm-launcher-install.apk
    cp -f "$APK" "$TMPAPK" 2>/dev/null
    chmod 0644 "$TMPAPK" 2>/dev/null
    attempt=1
    while [ "$attempt" -le 8 ]; do
        RES=$(pm install -r -g "$TMPAPK" 2>&1)
        log "install attempt $attempt: $RES"
        if pm path "$PKG" >/dev/null 2>&1; then
            log "apk installed"
            rm -f "$TMPAPK" 2>/dev/null
            break
        fi
        sleep 5
        attempt=$((attempt + 1))
    done
else
    [ -f "$APK" ] || log "payload apk missing at $APK (will be redeployed by service.sh)"
fi

# 2) 通知权限（MIUI 需 pm grant + appops set 两者都做；且首次可能不生效，需验证重试）
if pm path "$PKG" >/dev/null 2>&1; then
    gtry=1
    while [ "$gtry" -le 5 ]; do
        pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
        appops set "$PKG" POST_NOTIFICATION allow >/dev/null 2>&1
        granted=$(dumpsys package "$PKG" 2>/dev/null | grep -m1 'POST_NOTIFICATIONS: granted' | grep -o 'granted=[a-z]*')
        if [ "$granted" = "granted=true" ]; then
            log "notif permission granted (attempt $gtry)"
            break
        fi
        log "grant attempt $gtry not effective yet, retry in 3s"
        sleep 3
        gtry=$((gtry + 1))
    done
fi

# 3) 拉起前台服务（常驻通知）
if pm path "$PKG" >/dev/null 2>&1; then
    ok=0
    stry=1
    while [ "$stry" -le 4 ]; do
        RES=$(am start-foreground-service -n "$PKG/.NotifyService" 2>&1)
        case "$RES" in
            *Error*|*"not exported"*|*"does not exist"*|*"Permission"*) : ;;
            *) ok=1 ;;
        esac
        # 前台服务起来后，通知即在列表里
        if cmd notification list 2>/dev/null | grep -q "$PKG"; then ok=1; break; fi
        [ $? -ne 0 ] && RES=$(am startservice -n "$PKG/.NotifyService" 2>&1)
        log "start service attempt $stry: $RES"
        sleep 3
        stry=$((stry + 1))
    done
    [ "$ok" = "1" ] && log "start service OK" || log "start service FAILED after retries"
    log "deployment done"
else
    # 兜底：老式 cmd notification
    if [ -f "$DATA_DIR/bin/xzm-notify.sh" ]; then
        sh "$DATA_DIR/bin/xzm-notify.sh" on >> "$LOG" 2>&1
        log "fallback: cmd notification"
    fi
fi
