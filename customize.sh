#!/system/bin/sh
# xzm 管理器 · 安装脚本
# 兼容 Magisk / KernelSU / SukiSU / APatch
SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

print_modname() {
  ui_print "*******************************"
  ui_print "      xzm 管理器"
  ui_print "      作者：xzm"
  ui_print "      版本：1.0"
  ui_print "   双栏文件管理 · Root 终端"
  ui_print "*******************************"
}

on_install() {
  ui_print "- 正在安装模块文件"
  unzip -o "$ZIPFILE" 'module.prop'       -d "$MODPATH" >&2
  unzip -o "$ZIPFILE" 'service.sh'        -d "$MODPATH" >&2
  unzip -o "$ZIPFILE" 'boot-completed.sh' -d "$MODPATH" >&2
  unzip -o "$ZIPFILE" 'action.sh'         -d "$MODPATH" >&2
  unzip -o "$ZIPFILE" 'uninstall.sh'      -d "$MODPATH" >&2
  unzip -o "$ZIPFILE" 'bin/*'             -d "$MODPATH" >&2
  unzip -o "$ZIPFILE" 'webroot/*'         -d "$MODPATH" >&2
  unzip -o "$ZIPFILE" 'webroot-cgi/*'     -d "$MODPATH" >&2
  unzip -o "$ZIPFILE" 'third_party/*'     -d "$MODPATH" >&2
  unzip -o "$ZIPFILE" 'payload/*'         -d "$MODPATH" >&2

  # KernelSU 系不一定调用 set_permissions()，这里直接设一遍
  set_perm_recursive "$MODPATH" 0 0 0755 0644
  set_perm "$MODPATH/service.sh"        0 0 0755
  set_perm "$MODPATH/boot-completed.sh" 0 0 0755
  set_perm "$MODPATH/action.sh"         0 0 0755
  set_perm "$MODPATH/uninstall.sh"      0 0 0755
  set_perm "$MODPATH/bin/xzmctl.sh"     0 0 0755
  set_perm "$MODPATH/bin/xzm-shell.sh"  0 0 0755
  set_perm "$MODPATH/bin/xzm-webui.sh"  0 0 0755
  set_perm "$MODPATH/bin/ttyd"          0 0 0755
  set_perm "$MODPATH/bin/bash"          0 0 0755
  set_perm_recursive "$MODPATH/webroot"     0 0 0755 0644
  set_perm_recursive "$MODPATH/webroot-cgi" 0 0 0755 0755
  set_perm_recursive "$MODPATH/third_party" 0 0 0755 0644
  set_perm_recursive "$MODPATH/payload"     0 0 0755 0644

  # 安装伴随启动器 APK + 部署钩子
  if [ -f "$MODPATH/payload/xzm-launcher.apk" ]; then
    ui_print "- 准备伴随启动器（通知栏入口）"
    mkdir -p /data/adb/xzm_manager/payload
    cp -f "$MODPATH/payload/xzm-launcher.apk" /data/adb/xzm_manager/payload/xzm-launcher.apk
    chmod 0644 /data/adb/xzm_manager/payload/xzm-launcher.apk
    # 部署钩子放到 boot-completed.d：系统启动完成后自动装 APK + 授权 + 起通知
    mkdir -p /data/adb/boot-completed.d
    cp -f "$MODPATH/boot-completed.sh" /data/adb/boot-completed.d/xzm_manager.sh
    chown 0:0 /data/adb/boot-completed.d/xzm_manager.sh
    chmod 0755 /data/adb/boot-completed.d/xzm_manager.sh
    ui_print "- 已注册开机部署钩子（重启后自动就绪）"
  fi

  mkdir -p /data/adb/xzm_manager/scripts
  mkdir -p /data/adb/xzm_manager/logs
  mkdir -p /data/adb/xzm_manager/state
  mkdir -p /data/adb/xzm_manager/bin
  mkdir -p /data/adb/xzm_manager/run
  mkdir -p /data/adb/xzm_manager/prefs
  chmod 0700 /data/adb/xzm_manager/prefs 2>/dev/null || :
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] xzm 管理器安装完成" >> /data/adb/xzm_manager/logs/module.log
  ui_print "- WebUI 已写入 webroot/index.html"
  ui_print "- 数据目录：/data/adb/xzm_manager"
}

set_permissions() {
  set_perm_recursive "$MODPATH" 0 0 0755 0644
  set_perm "$MODPATH/service.sh"        0 0 0755
  set_perm "$MODPATH/boot-completed.sh" 0 0 0755
  set_perm "$MODPATH/action.sh"         0 0 0755
  set_perm "$MODPATH/uninstall.sh"      0 0 0755
  set_perm "$MODPATH/bin/xzmctl.sh"     0 0 0755
  set_perm "$MODPATH/bin/xzm-shell.sh"  0 0 0755
  set_perm "$MODPATH/bin/xzm-webui.sh"  0 0 0755
  set_perm "$MODPATH/bin/ttyd"          0 0 0755
  set_perm "$MODPATH/bin/bash"          0 0 0755
  set_perm_recursive "$MODPATH/webroot"     0 0 0755 0644
  set_perm_recursive "$MODPATH/webroot-cgi" 0 0 0755 0755
  set_perm_recursive "$MODPATH/third_party" 0 0 0755 0644
}
