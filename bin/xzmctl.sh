#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════
#  xzm 管理器 · 后端控制脚本 (xzmctl.sh)
#  运行于 Android (root)，被 WebUI 宿主通过 shell 调用
#  兼容 Magisk / KernelSU / SukiSU / APatch
# ═══════════════════════════════════════════════════════════════

MODDIR="${0%/*}/.."
MODULE_ID="xzm_manager"
DATA_DIR="${XZM_DATA_DIR:-/data/adb/$MODULE_ID}"
SCRIPTS_DIR="$DATA_DIR/scripts"
LOG_DIR="$DATA_DIR/logs"
STATE_DIR="$DATA_DIR/state"
PREFS_DIR="$DATA_DIR/prefs"
EXT_BIN="$DATA_DIR/bin"
RUN_DIR="$DATA_DIR/run"
ARCHIVE_DIR="$DATA_DIR/archive"
EDIT_DIR="$DATA_DIR/edit"

RUN_TIMEOUT="${XZM_RUN_TIMEOUT:-60}"
# 模块自带 bash（静态 aarch64），用于运行依赖 bash 语法的脚本
BASH_BIN=""
for _b in "$MODDIR/bin/bash" "$MODDIR/../bin/bash" "$EXT_BIN/bash"; do
  [ -x "$_b" ] && { BASH_BIN="$_b"; break; }
done

mkdir -p "$SCRIPTS_DIR" "$LOG_DIR" "$STATE_DIR" "$PREFS_DIR" "$EXT_BIN" "$RUN_DIR" "$ARCHIVE_DIR" "$EDIT_DIR" 2>/dev/null
chmod 0700 "$PREFS_DIR" 2>/dev/null || :

# ───────────────────────────────────────────────
# 工具函数
# ───────────────────────────────────────────────
json_escape() {
  # 单次转义 + 反斜杠/引号/制表/换行全部转义（JSON 合法）；UTF-8 安全
  # 注意：换行必须转成 \n，否则 JSON 字符串非法
  printf '%s' "$1" | awk '{ if (NR>1) printf "\\n"; gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/,"\\t"); gsub(/\r/,""); printf "%s", $0 }'
}

url_decode() {
  printf '%b' "$(printf '%s' "$1" | sed -e 's/+/ /g' -e 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

url_encode() {
  local s="$1" out="" c
  local i=0 len=${#s}
  while [ "$i" -lt "$len" ]; do
    c="${s:$i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out="$out$c" ;;
      *) out="$out$(printf '%%%02X' "'$c")" ;;
    esac
    i=$((i+1))
  done
  printf '%s' "$out"
}

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_DIR/module.log" 2>/dev/null
}

# 人类可读大小
human_size() {
  local bytes="$1"
  [ -z "$bytes" ] && { printf '0 B'; return; }
  case "$bytes" in
    *[!0-9]*) printf '%s B' "$bytes"; return ;;
  esac
  if [ "$bytes" -lt 1024 ]; then
    printf '%d B' "$bytes"
  elif [ "$bytes" -lt 1048576 ]; then
    printf '%d.%02d KB' $((bytes/1024)) $(( (bytes%1024)*100/1024 ))
  elif [ "$bytes" -lt 1073741824 ]; then
    printf '%d.%02d MB' $((bytes/1048576)) $(( (bytes%1048576)*100/1048576 ))
  else
    printf '%d.%02d GB' $((bytes/1073741824)) $(( (bytes%1073741824)*100/1073741824 ))
  fi
}

# 是否为受保护路径（禁止删除/危险操作）
is_protected() {
  case "$1" in
    /|/system|/system/*|/vendor|/vendor/*|/data|/data/adb|/data/adb/modules|\
    /sbin|/init|/init.*|/default.prop|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*)
      return 0 ;;
    *) return 1 ;;
  esac
}

# 从 URL 参数取 base64 编码的参数值
b64d() { printf '%s' "$1" | base64 -d 2>/dev/null; }
b64e() { printf '%s' "$1" | base64 2>/dev/null | tr -d '\n'; }

# ───────────────────────────────────────────────
# 列目录 (核心)
# ───────────────────────────────────────────────
cmd_list() {
  local dir="$1"
  [ -z "$dir" ] && dir="/sdcard"
  [ -d "$dir" ] || { printf '{"ok":false,"error":"目录不存在: %s"}\n' "$(json_escape "$dir")"; return; }

  local parent
  parent="$(dirname "$dir")"
  [ "$dir" = "/" ] && parent=""

  printf '{"ok":true,"path":"%s","parent":"%s","entries":[' \
    "$(json_escape "$dir")" "$(json_escape "$parent")"

  # 列条目：find -L 跟随符号链接（/sdcard 常是链接）；失败则退回 ls -A
  local listing
  listing="$(find -L "$dir/" -mindepth 1 -maxdepth 1 2>/dev/null)"
  if [ -z "$listing" ]; then
    listing="$(ls -A "$dir" 2>/dev/null | while IFS= read -r n; do printf '%s/%s\n' "${dir%/}" "$n"; done)"
  fi

  # 一次性 stat（单进程），交给单个 awk 组装整个 JSON —— 大目录也不卡
  local TAB
  TAB="$(printf '\t')"
  printf '%s' "$listing" | tr '\n' '\0' | xargs -0 -r stat -c "%n${TAB}%A${TAB}%u${TAB}%g${TAB}%s${TAB}%y" 2>/dev/null | \
  awk -F'\t' '
    function jesc(s,  o,i,c,l){
      o=""; l=length(s);
      for(i=1;i<=l;i++){ c=substr(s,i,1);
        if(c=="\\") o=o"\\\\";
        else if(c=="\"") o=o"\\\"";
        else if(c=="\t") o=o"\\t";
        else o=o c;
      }
      return o;
    }
    function hsize(b,  kb,mb,gb){
      b=b+0;
      if(b<1024) return b" B";
      kb=int(b/1024);
      if(kb<1024) return kb"."sprintf("%02d",int((b%1024)*100/1024))" KB";
      mb=int(b/1048576);
      if(mb<1024) return mb"."sprintf("%02d",int((b%1048576)*100/1048576))" MB";
      gb=int(b/1073741824);
      return gb"."sprintf("%02d",int((b%1073741824)*100/1073741824))" GB";
    }
    {
      full=$1; perms=$2; uid=$3; gid=$4; size=$5; mt=$6;
      n=split(full, parts, "/"); name=parts[n];
      if(name=="." || name=="..") next;
      # 类型
      p0=substr(perms,1,1);
      if(p0=="d") t="dir";
      else if(p0=="l") t="link";
      else t="file";
      if(t=="file"){
        low=tolower(name);
        if(low ~ /\.(zip|rar|7z|tar|gz|tgz|bz2|xz|apk|jar)$/) t="archive";
        else if(low ~ /\.(sh|py|js|lua|rb|pl)$/) t="script";
        else if(low ~ /\.(png|jpg|jpeg|gif|webp|bmp|svg|heic)$/) t="image";
        else if(low ~ /\.(mp4|mkv|avi|mov|webm|3gp)$/) t="video";
        else if(low ~ /\.(mp3|flac|wav|ogg|m4a|aac)$/) t="audio";
        else if(low ~ /\.(txt|md|json|xml|conf|ini|log|prop|yml|yaml|html|css)$/) t="text";
        # 有执行位的普通文件才算 exec；压缩包/APK 即使带 x 位仍归为 archive
        if(t!="archive" && perms ~ /x/) t="exec";
      }
      mts=substr(mt,1,16);
      if(count>0) printf ",";
      printf "{\"name\":\"%s\",\"type\":\"%s\",\"perms\":\"%s\",\"size\":%d,\"sizeText\":\"%s\",\"owner\":\"%s\",\"group\":\"%s\",\"mtime\":\"%s\"}",
        jesc(name), t, jesc(perms), size+0, hsize(size), jesc(uid), jesc(gid), jesc(mts);
      count++;
    }
  '

  printf ']}\n'
}

# ───────────────────────────────────────────────
# 通用文件操作
# ───────────────────────────────────────────────
cmd_mkdir() {
  local path="$1"
  if mkdir -p "$path" 2>/dev/null; then
    printf '{"ok":true}\n'; log_msg "新建目录 $path"
  else
    printf '{"ok":false,"error":"创建失败"}\n'
  fi
}

cmd_touch() {
  local path="$1"
  if touch "$path" 2>/dev/null; then
    printf '{"ok":true}\n'; log_msg "新建文件 $path"
  else
    printf '{"ok":false,"error":"创建失败"}\n'
  fi
}

cmd_rename() {
  local src="$1" dst="$2"
  if mv -f "$src" "$dst" 2>/dev/null; then
    printf '{"ok":true}\n'; log_msg "重命名 $src -> $dst"
  else
    printf '{"ok":false,"error":"重命名失败"}\n'
  fi
}

cmd_delete() {
  local path="$1" recursive="$2"
  if is_protected "$path"; then
    printf '{"ok":false,"error":"受保护路径，拒绝删除"}\n'; return
  fi
  local ok=false
  if [ -d "$path" ]; then
    [ "$recursive" = "1" ] && rm -rf "$path" 2>/dev/null && ok=true || rmdir "$path" 2>/dev/null && ok=true
  else
    rm -f "$path" 2>/dev/null && ok=true
  fi
  if [ "$ok" = "true" ] && [ ! -e "$path" ]; then
    printf '{"ok":true}\n'; log_msg "删除 $path"
  else
    printf '{"ok":false,"error":"删除失败"}\n'
  fi
}

cmd_copy() {
  local src="$1" dst="$2" overwrite="$3"
  local target="$dst/$(basename "$src")"
  [ -e "$target" ] && [ "$overwrite" != "1" ] && { printf '{"ok":false,"conflict":true,"target":"%s","error":"目标已存在"}\n' "$(json_escape "$target")"; return; }
  [ -e "$target" ] && rm -rf "$target" 2>/dev/null
  if cp -a "$src" "$target" 2>/dev/null; then
    printf '{"ok":true,"target":"%s"}\n' "$(json_escape "$target")"; log_msg "复制 $src -> $target"
  else
    printf '{"ok":false,"error":"复制失败"}\n'
  fi
}

cmd_move() {
  local src="$1" dst="$2" overwrite="$3"
  local target="$dst/$(basename "$src")"
  [ "$src" = "$target" ] && { printf '{"ok":false,"error":"源和目标是同一项"}\n'; return; }
  [ -e "$target" ] && [ "$overwrite" != "1" ] && { printf '{"ok":false,"conflict":true,"target":"%s","error":"目标已存在"}\n' "$(json_escape "$target")"; return; }
  [ -e "$target" ] && rm -rf "$target" 2>/dev/null
  if mv -f "$src" "$target" 2>/dev/null; then
    printf '{"ok":true,"target":"%s"}\n' "$(json_escape "$target")"; log_msg "移动 $src -> $target"
  else
    printf '{"ok":false,"error":"移动失败"}\n'
  fi
}

cmd_chmod() {
  local path="$1" mode="$2" recursive="$3"
  local ok=false
  if [ "$recursive" = "1" ] && [ -d "$path" ]; then
    chmod -R "$mode" "$path" 2>/dev/null && ok=true
  else
    chmod "$mode" "$path" 2>/dev/null && ok=true
  fi
  [ "$ok" = "true" ] && printf '{"ok":true}\n' || printf '{"ok":false,"error":"权限修改失败"}\n'
}

cmd_chown() {
  local path="$1" owner="$2" recursive="$3"
  local ok=false
  if [ "$recursive" = "1" ] && [ -d "$path" ]; then
    chown -R "$owner" "$path" 2>/dev/null && ok=true
  else
    chown "$owner" "$path" 2>/dev/null && ok=true
  fi
  [ "$ok" = "true" ] && printf '{"ok":true}\n' || printf '{"ok":false,"error":"属主修改失败"}\n'
}

cmd_stat() {
  local path="$1"
  [ -e "$path" ] || { printf '{"ok":false,"error":"不存在"}\n'; return; }
  local perms size mtime owner md5 links
  perms="$(ls -ld "$path" 2>/dev/null | awk '{print $1}')"
  size=""
  [ -f "$path" ] && size="$(stat -c '%s' "$path" 2>/dev/null)"
  mtime="$(date -r "$path" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  owner="$(ls -ld "$path" 2>/dev/null | awk '{print $3":"$4}')"
  md5=""
  [ -f "$path" ] && md5="$(md5sum "$path" 2>/dev/null | awk '{print $1}')"
  printf '{"ok":true,"path":"%s","perms":"%s","size":%s,"sizeText":"%s","mtime":"%s","owner":"%s","md5":"%s"}\n' \
    "$(json_escape "$path")" "$(json_escape "$perms")" "${size:-0}" "$(human_size "${size:-0}")" \
    "$(json_escape "$mtime")" "$(json_escape "$owner")" "$md5"
}

# ───────────────────────────────────────────────
# 文本读取 / 写入
# ───────────────────────────────────────────────
cmd_read() {
  local path="$1" max="${2:-524288}"  # 默认最多 512KB
  [ -f "$path" ] || { printf '{"ok":false,"error":"不是文件"}\n'; return; }
  local size
  size="$(stat -c '%s' "$path" 2>/dev/null || echo 0)"
  if [ "$size" -gt "$max" ]; then
    printf '{"ok":false,"error":"文件过大 (%s)，超过 %s 限制"}\n' "$(human_size "$size")" "$(human_size "$max")"
    return
  fi
  local content
  content="$(base64 < "$path" 2>/dev/null | tr -d '\n')"
  printf '{"ok":true,"size":%s,"base64":"%s"}\n' "$size" "$content"
}

cmd_write() {
  local path="$1" b64="$2"
  printf '%s' "$b64" | base64 -d > "$path" 2>/dev/null
  if [ $? -eq 0 ]; then
    printf '{"ok":true}\n'; log_msg "写入文件 $path"
  else
    printf '{"ok":false,"error":"写入失败"}\n'
  fi
}

# ───────────────────────────────────────────────
# 执行 shell 命令 / 脚本
# ───────────────────────────────────────────────
cmd_exec() {
  local cmd="$1"
  # 命令通过 base64 传入，避免转义问题
  local decoded
  decoded="$(b64d "$cmd")"
  [ -z "$decoded" ] && decoded="$cmd"
  log_msg "执行: $decoded"
  local out
  out="$(timeout "$RUN_TIMEOUT" sh -c "$decoded" 2>&1)"
  local code=$?
  printf '{"ok":true,"code":%s,"output":"%s"}\n' "$code" "$(json_escape "$out")"
}

# ───────────────────────────────────────────────
# 运行脚本 / 可执行文件（MT 管理器式）
#   参数: <path> [workdir] [extraArgsBase64]
#   以 root 运行（xzmctl.sh 本身即以 root 执行），自动识别解释器
# ───────────────────────────────────────────────
cmd_run() {
  local path="$1" wd="$2" argsb64="$3"
  local args
  if [ -n "$argsb64" ]; then args="$(b64d "$argsb64")"; fi
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    printf '{"ok":false,"output":"文件不存在: %s"}\n' "$(json_escape "$path")"; return
  fi
  [ -n "$wd" ] && [ -d "$wd" ] || wd="$(dirname "$path")"

  # 选解释器
  local interp=""
  case "$path" in
    *.sh)  interp="sh" ;;
    *.py)  interp="python3"; command -v python3 >/dev/null 2>&1 || interp="python" ;;
    *.js)  interp="node" ;;
    *.pl)  interp="perl" ;;
    *.rb)  interp="ruby" ;;
    *.lua) interp="lua" ;;
  esac
  # 无扩展名：看 shebang
  if [ -z "$interp" ]; then
    local sb
    sb="$(head -c 100 "$path" 2>/dev/null | sed -n '1s/^#! *//p')"
    if [ -n "$sb" ]; then interp="$sb"; fi
  fi

  # shell 脚本：优先 bash（很多"sh"脚本其实用了 bash 数组/local 等语法）
  local hinted=""
  if [ "$interp" = "sh" ] || echo "$interp" | grep -qE '(^|/)sh$'; then
    local bashbin=""
    # 优先模块自带 / 数据目录 / 系统 PATH 里的 bash
    for b in "$BASH_BIN" "$DATA_DIR/bin/bash" /data/adb/ksu/bin/bash /data/adb/magisk/bash; do
      [ -n "$b" ] && [ -x "$b" ] && { bashbin="$b"; break; }
    done
    [ -z "$bashbin" ] && command -v bash >/dev/null 2>&1 && bashbin="$(command -v bash)"
    if [ -n "$bashbin" ]; then
      interp="$bashbin"
    else
      # 检测 bash 专属语法（数组 / local / [[ ]] / function / $(( ) 之外的 ((
      if grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\(|[[:space:]]local[[:space:]]|\[\[|\$\(\(|function[[:space:]]+[A-Za-z_]|\)\)[[:space:]]*$' "$path" 2>/dev/null; then
        hinted="注意：该脚本使用了 bash 专属语法（数组/local/[[ ]] 等），但本机没有 bash。请安装 bash 或改用标准 sh 语法。"
      fi
    fi
  fi

  local cmd
  if [ -n "$interp" ]; then
    cmd="cd \"$wd\" && $interp \"$path\" $args"
  else
    # 无解释器：需可执行，直接跑
    if [ ! -x "$path" ]; then
      chmod +x "$path" 2>/dev/null
    fi
    cmd="cd \"$wd\" && \"$path\" $args"
  fi

  log_msg "运行: $cmd"
  local out code
  out="$(timeout "$RUN_TIMEOUT" sh -c "$cmd" 2>&1)"
  code=$?
  local prefix=""
  [ -n "$hinted" ] && prefix="⚠️ $hinted\n\n"
  printf '{"ok":true,"code":%s,"cmd":"%s","output":"%s"}\n' \
    "$code" "$(json_escape "$cmd")" "$(json_escape "$prefix$out")"
}

# ───────────────────────────────────────────────
# 解压 / 压缩
# ───────────────────────────────────────────────
# 选一个可用的 busybox（提供 unzip/tar/gzip/xz）
bb_bin() {
  local b
  for b in "$EXT_BIN/busybox" /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /system/xbin/busybox /system/bin/busybox; do
    [ -x "$b" ] && { printf '%s' "$b"; return; }
  done
  command -v busybox 2>/dev/null
}

# 压缩包类型：zip | targz | tarbz2 | tarxz | tar | gz | bz2 | xz | 7z | unknown
archive_kind() {
  local f="$1" m
  case "$f" in
    *.zip|*.jar|*.apk|*.xpi) printf 'zip'; return ;;
    *.tar.gz|*.tgz) printf 'targz'; return ;;
    *.tar.bz2|*.tbz2|*.tbz) printf 'tarbz2'; return ;;
    *.tar.xz|*.txz) printf 'tarxz'; return ;;
    *.tar) printf 'tar'; return ;;
    *.gz) printf 'gz'; return ;;
    *.bz2) printf 'bz2'; return ;;
    *.xz) printf 'xz'; return ;;
    *.7z) printf '7z'; return ;;
    *.rar) printf 'rar'; return ;;
  esac
  # 用魔数判断
  m="$(od -An -tx1 -N8 "$f" 2>/dev/null | tr -d ' \r\n')"
  case "$m" in
    504b0304*|504b0506*|504b0708*) printf 'zip'; return ;;
    1f8b*) printf 'gz'; return ;;
    425a68*) printf 'bz2'; return ;;
    fd377a585a00*) printf 'xz'; return ;;
    377abcaf271c*) printf '7z'; return ;;
    526172211a0700*|526172211a0701*) printf 'rar'; return ;;  # Rar! 4.x / 5.x
  esac
  printf 'unknown'
}

# extract <archive> <destDir>
cmd_extract() {
  local src="$1" dest="$2"
  [ -z "$src" ] || [ ! -f "$src" ] && { printf '{"ok":false,"error":"压缩包不存在: %s"}\n' "$(json_escape "$src")"; return; }
  [ -z "$dest" ] && dest="$(dirname "$src")"
  # 若是 key.enc.xxx 之类先不管；确保目标目录存在
  mkdir -p "$dest" 2>/dev/null
  [ -d "$dest" ] || { printf '{"ok":false,"error":"无法创建目标目录: %s"}\n' "$(json_escape "$dest")"; return; }

  local kind bb log out code
  kind="$(archive_kind "$src")"
  bb="$(bb_bin)"
  log="$LOG_DIR/extract.log"
  : > "$log"

  # 同名换行安全：cd 到目标目录后解压全部内容
  case "$kind" in
    zip)
      if [ -x "$bb" ]; then
        out="$("$bb" unzip -o "$src" -d "$dest" >>"$log" 2>&1)"; code=$?
      else
        out="$(unzip -o "$src" -d "$dest" >>"$log" 2>&1)"; code=$?
      fi ;;
    targz)   { [ -x "$bb" ] && "$bb" tar -xzf "$src" -C "$dest" || tar -xzf "$src" -C "$dest"; } >>"$log" 2>&1; code=$? ;;
    tarbz2)  { [ -x "$bb" ] && "$bb" tar -xjf "$src" -C "$dest" || tar -xjf "$src" -C "$dest"; } >>"$log" 2>&1; code=$? ;;
    tarxz)   { [ -x "$bb" ] && "$bb" tar -xJf "$src" -C "$dest" || tar -xJf "$src" -C "$dest"; } >>"$log" 2>&1; code=$? ;;
    tar)     { [ -x "$bb" ] && "$bb" tar -xf "$src" -C "$dest" || tar -xf "$src" -C "$dest"; } >>"$log" 2>&1; code=$? ;;
    gz)      { [ -x "$bb" ] && "$bb" gzip -dc "$src" > "$dest/$(basename "${src%.gz}")" || gzip -dc "$src" > "$dest/$(basename "${src%.gz}")"; } >>"$log" 2>&1; code=$? ;;
    bz2)     { [ -x "$bb" ] && "$bb" bzip2 -dc "$src" > "$dest/$(basename "${src%.bz2}")" || bzip2 -dc "$src" > "$dest/$(basename "${src%.bz2}")"; } >>"$log" 2>&1; code=$? ;;
    xz)      { [ -x "$bb" ] && "$bb" xz -dc "$src" > "$dest/$(basename "${src%.xz}")" || xz -dc "$src" > "$dest/$(basename "${src%.xz}")"; } >>"$log" 2>&1; code=$? ;;
    7z)
      local z7=""
      if command -v 7z >/dev/null 2>&1; then z7="$(command -v 7z)"
      elif command -v 7za >/dev/null 2>&1; then z7="$(command -v 7za)"
      elif command -v 7zz >/dev/null 2>&1; then z7="$(command -v 7zz)"
      elif [ -x "$EXT_BIN/7zz" ]; then z7="$EXT_BIN/7zz"
      elif [ -x "$DATA_DIR/bin/7zz" ]; then z7="$DATA_DIR/bin/7zz"; fi
      if [ -n "$z7" ]; then
        "$z7" x -y -o"$dest" "$src" >>"$log" 2>&1; code=$?
      elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$src" -C "$dest" >>"$log" 2>&1; code=$?
      else
        printf '{"ok":false,"error":"本机无 7z/bsdtar，无法解压 .7z（可安装 7z 或将包转成 zip）"}\n'; return
      fi ;;
    rar)
      local zr=""
      if command -v 7z >/dev/null 2>&1; then zr="$(command -v 7z)"
      elif command -v 7zz >/dev/null 2>&1; then zr="$(command -v 7zz)"
      elif [ -x "$EXT_BIN/7zz" ]; then zr="$EXT_BIN/7zz"
      elif [ -x "$DATA_DIR/bin/7zz" ]; then zr="$DATA_DIR/bin/7zz"; fi
      if [ -n "$zr" ]; then
        "$zr" x -y -o"$dest" "$src" >>"$log" 2>&1; code=$?
      elif command -v unrar >/dev/null 2>&1; then
        unrar x -o+ "$src" "$dest/" >>"$log" 2>&1; code=$?
      elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$src" -C "$dest" >>"$log" 2>&1; code=$?
      else
        printf '{"ok":false,"error":"本机无 7z/unrar，无法解压 .rar"}\n'; return
      fi ;;
    *)
      printf '{"ok":false,"error":"不支持的压缩格式: %s"}\n' "$(json_escape "$(basename "$src")")"; return ;;
  esac

  local tailtxt=""
  [ -f "$log" ] && tailtxt="$(tail -n 8 "$log" 2>/dev/null)"
  if [ "$code" = "0" ]; then
    log_msg "解压: $src -> $dest ($kind)"
    printf '{"ok":true,"code":0,"kind":"%s","dest":"%s","output":"%s"}\n' \
      "$kind" "$(json_escape "$dest")" "$(json_escape "$(cat "$log" 2>/dev/null | tail -n 6)")"
  else
    log_msg "解压失败($code): $src -> $dest"
    printf '{"ok":false,"code":%s,"error":"解压失败(退出码 %s)","output":"%s"}\n' \
      "$code" "$code" "$(json_escape "$tailtxt")"
  fi
}

# archive-list <archive>  —— 列出包内条目（JSON 数组，跨后端统一）
cmd_archive_list() {
  local src="$1" odd bb kind
  [ -z "$src" ] || [ ! -f "$src" ] && { printf '{"ok":false,"error":"压缩包不存在"}\n'; return; }
  kind="$(archive_kind "$src")"
  bb="$(bb_bin)"
  odd="$(mktemp "${TMPDIR:-/data/local/tmp}/xzmal.XXXXXX" 2>/dev/null || echo /data/local/tmp/xzmal.$$)" 
  case "$kind" in
    zip)
      if [ -x "$bb" ]; then "$bb" unzip -l "$src" > "$odd" 2>/dev/null
      else unzip -l "$src" > "$odd" 2>/dev/null; fi
      # 解析：  Length  Date Time  Name ；跳过表头到 ---- 行
      awk '
        BEGIN{dash=0}
        /---------/{dash=1;next}
        dash==1 && /Archive:/{next}
        dash==1 && NF>=4{
          len=$1; d=$2; t=$3; nm=$4;
          for(i=5;i<=NF;i++) nm=nm" "$i;
          if(nm=="") next;
          dir=(substr(nm,length(nm),1)=="/")?1:0;
          esc=nm; gsub(/\\/,"\\\\",esc); gsub(/"/,"\\\"",esc);
          if(cnt>0) printf ",";
          printf "{\"n\":\"%s\",\"s\":%d,\"d\":%d}", esc, len+0, dir;
          cnt++;
        }
        END{ if(cnt==0) printf "" }
      ' "$odd" > "$odd.j" 2>/dev/null
      ;;
    targz|tarbz2|tarxz|tar)
      local fl=""
      case "$kind" in targz) fl="-tzvf";; tarbz2) fl="-tjvf";; tarxz) fl="-tJvf";; tar) fl="-tvf";; esac
      if [ -x "$bb" ]; then "$bb" tar $fl "$src" > "$odd" 2>/dev/null
      else tar $fl "$src" > "$odd" 2>/dev/null; fi
      # 解析 tar -tvf:  -rw-r--r-- user/grp  1234 2026-01-01 12:00 name
      awk '
        {
          nm=$NF; sz=0;
          for(i=1;i<=NF-1;i++){ if($i ~ /^[0-9]+$/){ sz=$i; break } }
          if(nm=="") next;
          dir=(substr(nm,length(nm),1)=="/")?1:0;
          esc=nm; gsub(/\\/,"\\\\",esc); gsub(/"/,"\\\"",esc);
          if(cnt>0) printf ",";
          printf "{\"n\":\"%s\",\"s\":%d,\"d\":%d}", esc, sz+0, dir;
          cnt++;
        }
      ' "$odd" > "$odd.j" 2>/dev/null
      ;;
    gz|bz2|xz)
      printf '[{"n":"%s","s":0,"d":0}]' "$(basename "${src%.*}")" > "$odd.j"
      ;;
    7z)
      if command -v 7z >/dev/null 2>&1; then 7z l -slt "$src" 2>/dev/null | awk '/^Path = /{p=substr($0,8)} /^Size = /{s=$3; if(p!=""){esc=p; gsub(/\\/,"\\\\",esc); gsub(/"/,"\\\"",esc); if(c>0)printf ","; printf "{\"n\":\"%s\",\"s\":%d,\"d\":0}",esc,s+0; c++; p=""}}' > "$odd.j"
      else printf '{"ok":false,"error":"本机无 7z 无法预览"}\n'; rm -f "$odd"; return; fi
      ;;
    *) printf '{"ok":false,"error":"不支持的格式"}\n'; rm -f "$odd"; return ;;
  esac
  local items; items="$(cat "$odd.j" 2>/dev/null)"
  rm -f "$odd" "$odd.j" 2>/dev/null
  printf '{"ok":true,"kind":"%s","items":[%s]}\n' "$kind" "$items"
}

# archive-read <archive> <entryBase64>  —— 解出单个条目到 stdout（用于预览）
cmd_archive_read() {
  local src="$1" entryb64="$2" entry bb kind
  entry="$(b64d "$entryb64")"
  [ -z "$src" ] || [ ! -f "$src" ] && { printf '{"ok":false,"error":"压缩包不存在"}\n'; return; }
  [ -z "$entry" ] && { printf '{"ok":false,"error":"缺少条目名"}\n'; return; }
  kind="$(archive_kind "$src")"
  bb="$(bb_bin)"
  local tmpd out
  tmpd="$(mktemp -d "${TMPDIR:-/data/local/tmp}/xzmr.XXXXXX" 2>/dev/null || { tmpd="/data/local/tmp/xzmr.$$"; mkdir -p "$tmpd"; })"
  case "$kind" in
    zip)
      if [ -x "$bb" ]; then "$bb" unzip -o -j "$src" "$entry" -d "$tmpd" >/dev/null 2>&1
      else unzip -o -j "$src" "$entry" -d "$tmpd" >/dev/null 2>&1; fi
      out="$tmpd/$(basename "$entry")" ;;
    targz|tarbz2|tarxz|tar)
      local fl=""
      case "$kind" in targz) fl="-xzf";; tarbz2) fl="-xjf";; tarxz) fl="-xJf";; tar) fl="-xf";; esac
      if [ -x "$bb" ]; then "$bb" tar $fl "$src" -C "$tmpd" "$entry" >/dev/null 2>&1
      else tar $fl "$src" -C "$tmpd" "$entry" >/dev/null 2>&1; fi
      out="$tmpd/$entry" ;;
    gz|bz2|xz)
      out="$tmpd/$(basename "${src%.*}")"
      case "$kind" in
        gz) { [ -x "$bb" ] && "$bb" gzip -dc "$src" || gzip -dc "$src"; } > "$out" 2>/dev/null ;;
        bz2) { [ -x "$bb" ] && "$bb" bzip2 -dc "$src" || bzip2 -dc "$src"; } > "$out" 2>/dev/null ;;
        xz) { [ -x "$bb" ] && "$bb" xz -dc "$src" || xz -dc "$src"; } > "$out" 2>/dev/null ;;
      esac ;;
    *) rm -rf "$tmpd"; printf '{"ok":false,"error":"不支持预览此格式"}\n'; return ;;
  esac
  if [ -f "$out" ]; then
    local sz; sz="$(wc -c < "$out" 2>/dev/null | tr -d ' ')"
    local maxb=262144
    if [ "${sz:-0}" -gt "$maxb" ]; then
      rm -rf "$tmpd"
      printf '{"ok":false,"tooBig":true,"size":%s,"error":"文件过大(%s字节)，请直接解压后查看"}\n' "$sz" "$sz"
      return
    fi
    # base64 输出（避免二进制/特殊字符破坏 JSON）
    local b64; b64="$(base64 < "$out" 2>/dev/null | tr -d '\n')"
    rm -rf "$tmpd"
    printf '{"ok":true,"size":%s,"b64":"%s"}\n' "$sz" "$b64"
  else
    rm -rf "$tmpd"
    printf '{"ok":false,"error":"无法读取该条目"}\n'
  fi
}

# archive-extract-one <archive> <entryB64> <destDir>  —— 解出单个条目到目录（保留子路径）
cmd_archive_extract_one() {
  local src="$1" entryb64="$2" dest="$3" entry bb kind
  entry="$(b64d "$entryb64")"
  [ -z "$src" ] || [ ! -f "$src" ] && { printf '{"ok":false,"error":"压缩包不存在"}\n'; return; }
  [ -z "$entry" ] && { printf '{"ok":false,"error":"缺少条目名"}\n'; return; }
  [ -z "$dest" ] && dest="$(dirname "$src")"
  mkdir -p "$dest" 2>/dev/null
  kind="$(archive_kind "$src")"
  bb="$(bb_bin)"
  local log="$LOG_DIR/extract.log" code=1
  case "$kind" in
    zip)
      if [ -x "$bb" ]; then "$bb" unzip -o "$src" "$entry" -d "$dest" >>"$log" 2>&1; code=$?
      else unzip -o "$src" "$entry" -d "$dest" >>"$log" 2>&1; code=$?; fi ;;
    targz|tarbz2|tarxz|tar)
      local fl=""
      case "$kind" in targz) fl="-xzf";; tarbz2) fl="-xjf";; tarxz) fl="-xJf";; tar) fl="-xf";; esac
      if [ -x "$bb" ]; then "$bb" tar $fl "$src" -C "$dest" "$entry" >>"$log" 2>&1; code=$?
      else tar $fl "$src" -C "$dest" "$entry" >>"$log" 2>&1; code=$?; fi ;;
    gz|bz2|xz)
      local out="$dest/$(basename "${src%.*}")"
      case "$kind" in
        gz) { [ -x "$bb" ] && "$bb" gzip -dc "$src" || gzip -dc "$src"; } > "$out" 2>>"$log"; code=$? ;;
        bz2) { [ -x "$bb" ] && "$bb" bzip2 -dc "$src" || bzip2 -dc "$src"; } > "$out" 2>>"$log"; code=$? ;;
        xz) { [ -x "$bb" ] && "$bb" xz -dc "$src" || xz -dc "$src"; } > "$out" 2>>"$log"; code=$? ;;
      esac ;;
    *) printf '{"ok":false,"error":"不支持此格式"}\n'; return ;;
  esac
  if [ "$code" = "0" ]; then
    log_msg "单解: $src :: $entry -> $dest"
    printf '{"ok":true,"code":0,"dest":"%s","entry":"%s"}\n' "$(json_escape "$dest")" "$(json_escape "$entry")"
  else
    printf '{"ok":false,"code":%s,"error":"解出失败","output":"%s"}\n' "$code" "$(json_escape "$(tail -n 6 "$log" 2>/dev/null)")"
  fi
}

# ───────────────────────────────────────────────
# 安装 APK
# ───────────────────────────────────────────────
# install-apk <apkPath> [flagsB64]
#   flags: 逗号分隔，支持 replace(r) / downgrade(d) / grant(g) / testonly(t)
cmd_install_apk() {
  local apk="$1" flagsb64="$2" flags
  flags="$(b64d "$flagsb64")"
  [ -z "$apk" ] || [ ! -f "$apk" ] && { printf '{"ok":false,"error":"APK 不存在: %s"}\n' "$(json_escape "$apk")"; return; }
  case "$apk" in *.apk|*.apks|*.xapk) ;; *) printf '{"ok":false,"error":"不是 APK 文件"}\n'; return ;; esac

  # 组装 pm install 参数
  local opt="-r"  # 默认覆盖安装
  local IFS=','
  local f
  for f in $flags; do
    case "$f" in
      replace|r)   opt="$opt -r" ;;
      downgrade|d) opt="$opt -d" ;;
      grant|g)     opt="$opt -g" ;;
      testonly|t)  opt="$opt -t" ;;
      *) ;;
    esac
  done
  unset IFS

  local log="$LOG_DIR/install.log"
  : > "$log"
  local out code
  # pm install 需要文件可被 system 读取：先复制到 /data/local/tmp 并放开权限
  local stage="/data/local/tmp/.xzm_install.apk"
  if ! cp -f "$apk" "$stage" 2>>"$log"; then
    printf '{"ok":false,"error":"无法暂存 APK（权限不足）"}\n'; return
  fi
  chmod 0644 "$stage" 2>/dev/null
  # 挂载点下可能需要标记为有效但未挂载（针对部分设备）
  out="$(pm install $opt "$stage" 2>&1)"
  code=$?
  rm -f "$stage" 2>/dev/null
  printf '%s\n' "$out" >> "$log"

  if [ "$code" = "0" ] && ! printf '%s' "$out" | grep -qiE 'Failure|Error|Exception|denied'; then
    log_msg "安装APK: $apk"
    printf '{"ok":true,"code":0,"output":"%s"}\n' "$(json_escape "$out")"
  else
    log_msg "安装失败($code): $apk :: $out"
    printf '{"ok":false,"code":%s,"error":"安装失败","output":"%s"}\n' "$code" "$(json_escape "$out")"
  fi
}

# uninstall-apk <packageName>  —— 卸载应用
cmd_uninstall_apk() {
  local pkg="$1"
  [ -z "$pkg" ] && { printf '{"ok":false,"error":"缺少包名"}\n'; return; }
  local out code
  out="$(pm uninstall "$pkg" 2>&1)"; code=$?
  if [ "$code" = "0" ] && ! printf '%s' "$out" | grep -qiE 'Failure|Error|Exception'; then
    log_msg "卸载: $pkg"
    printf '{"ok":true,"code":0,"output":"%s"}\n' "$(json_escape "$out")"
  else
    printf '{"ok":false,"code":%s,"error":"卸载失败","output":"%s"}\n' "$code" "$(json_escape "$out")"
  fi
}

# apk-info <apkPath>  —— 读取未安装 APK 的包信息（纯 shell AXML 解析）
cmd_apk_info() {
  local apk="$1" here
  [ -z "$apk" ] || [ ! -f "$apk" ] && { printf '{"ok":false,"error":"APK 不存在"}\n'; return; }
  here="$(dirname "$0")"
  if [ -f "$here/axml-info.sh" ]; then
    sh "$here/axml-info.sh" "$apk"
  else
    printf '{"ok":false,"error":"缺少 axml-info.sh"}\n'
  fi
}

# list-apps-full  —— 列出已安装应用（含真实名称 + 图标 + 版本），通过 app_process 调 Android API
cmd_list_apps_full() {
  local here iconpx="${1:-64}" noicon="${2:-}"
  here="$(dirname "$0")"
  local dex="$here/applister.dex"
  [ -f "$dex" ] || { printf '{"ok":false,"error":"缺少 applister.dex"}\n'; return; }
  local dexdir="/data/local/tmp/.xzmlister.$$"
  mkdir -p "$dexdir" 2>/dev/null
  cp -f "$dex" "$dexdir/classes.dex" 2>/dev/null
  local out
  out="$(cd "$dexdir" && CLASSPATH=classes.dex app_process /system/bin AppLister "$iconpx" "" "$noicon" 2>/dev/null)"
  rm -rf "$dexdir"
  if [ -z "$out" ]; then
    printf '{"ok":false,"error":"app_process 无输出"}\n'
    return
  fi
  # 直接输出，不用 printf 传参（避免参数过长）
  echo "$out"
}

# list-apps  —— 列出已安装应用（第三方优先）
cmd_list_apps() {
  local tmp="/data/local/tmp/.xzmpkg.txt"
  local try rc
  for try in 1 2 3; do
    pm list packages -3 > "$tmp" 2>/dev/null; rc=$?
    [ "$rc" = "0" ] && [ "$(wc -l < "$tmp" 2>/dev/null)" -gt 0 ] && break
    sleep 0.3
  done
  if [ "$rc" != "0" ] || [ "$(wc -l < "$tmp" 2>/dev/null)" -eq 0 ]; then
    for try in 1 2 3; do
      pm list packages > "$tmp" 2>/dev/null; rc=$?
      [ "$rc" = "0" ] && [ "$(wc -l < "$tmp" 2>/dev/null)" -gt 0 ] && break
      sleep 0.3
    done
  fi
  printf '{"ok":true,"apps":['
  local first=1 line pkg apath
  while IFS= read -r line; do
    case "$line" in package:*) ;; *) continue ;; esac
    pkg="${line#package:}"; pkg="$(printf '%s' "$pkg" | tr -d '\r')"
    [ -z "$pkg" ] && continue
    [ "$first" = "1" ] || printf ','
    first=0
    printf '{"pkg":"%s"}' "$(json_escape "$pkg")"
  done < "$tmp"
  printf ']}\n'
  rm -f "$tmp"
}

# app-info <packageName>  —— 读取已安装应用的版本/大小
cmd_app_info() {
  local pkg="$1" dump apath size ver
  [ -z "$pkg" ] && { printf '{"ok":false,"error":"缺少包名"}\n'; return; }
  dump="$(dumpsys package "$pkg" 2>/dev/null)"
  ver="$(printf '%s' "$dump" | grep -m1 'versionName=' | sed 's/.*versionName=//' | tr -d '\r')"
  apath="$(pm path "$pkg" 2>/dev/null | head -1 | sed 's/^package://' | tr -d '\r')"
  size=0
  [ -n "$apath" ] && [ -f "$apath" ] && size="$(stat -c %s "$apath" 2>/dev/null || echo 0)"
  printf '{"ok":true,"pkg":"%s","ver":"%s","path":"%s","size":%s}\n' "$(json_escape "$pkg")" "$(json_escape "$ver")" "$(json_escape "$apath")" "${size:-0}"
}

# compress <outZip> <base64换行分隔的路径列表>   —— 生成 ZIP
cmd_compress() {
  local out="$1" listb64="$2" bb log code
  [ -z "$out" ] && { printf '{"ok":false,"error":"缺少输出路径"}\n'; return; }
  [ -z "$listb64" ] && { printf '{"ok":false,"error":"缺少要压缩的文件"}\n'; return; }
  local list; list="$(b64d "$listb64")"
  [ -z "$list" ] && { printf '{"ok":false,"error":"文件列表为空"}\n'; return; }
  bb="$(bb_bin)"
  log="$LOG_DIR/compress.log"; : > "$log"
  # 用 zip 需要相对路径；进入公共父目录打包
  local first parent
  first="$(printf '%s' "$list" | head -n1)"
  parent="$(dirname "$first")"
  # 收集相对名
  local rels="" p rel
  # 用换行分隔处理（IFS 保留空行）
  local oldIFS="$IFS"; IFS='
'
  for p in $list; do
    [ -e "$p" ] || continue
    case "$p" in
      "$parent"/*) rel="${p#$parent/}" ;;
      *) rel="$(basename "$p")" ;;
    esac
    rels="$rels$rel
"
  done
  IFS="$oldIFS"
  rels="$(printf '%s' "$rels" | sed '/^$/d')"
  [ -z "$rels" ] && { printf '{"ok":false,"error":"没有可压缩的文件"}\n'; return; }

  local havezip=""
  if command -v zip >/dev/null 2>&1; then havezip="zip"
  elif [ -x "$bb" ] && "$bb" --list 2>/dev/null | grep -qx 'zip'; then havezip="bbzip"
  fi

  if [ "$havezip" = "zip" ]; then
    ( cd "$parent" && printf '%s\n' "$rels" | zip -r -q "$out" -@ ) >>"$log" 2>&1
    code=$?
  elif [ "$havezip" = "bbzip" ]; then
    ( cd "$parent" && printf '%s\n' "$rels" | "$bb" zip -r -q "$out" -@ ) >>"$log" 2>&1
    code=$?
  else
    # 无 zip：退回 tar.gz
    case "$out" in *.zip) out="${out%.zip}.tar.gz" ;; esac
    if [ -x "$bb" ]; then
      ( cd "$parent" && printf '%s\n' "$rels" | "$bb" tar -czf "$out" -T - ) >>"$log" 2>&1
    else
      ( cd "$parent" && printf '%s\n' "$rels" | tar -czf "$out" -T - ) >>"$log" 2>&1
    fi
    code=$?
  fi

  if [ "$code" = "0" ] && [ -f "$out" ]; then
    log_msg "压缩: $out"
    printf '{"ok":true,"code":0,"out":"%s","output":"%s"}\n' \
      "$(json_escape "$out")" "$(json_escape "$(tail -n 6 "$log" 2>/dev/null)")"
  else
    printf '{"ok":false,"code":%s,"error":"压缩失败(退出码 %s)","output":"%s"}\n' \
      "$code" "$code" "$(json_escape "$(tail -n 10 "$log" 2>/dev/null)")"
  fi
}

# ───────────────────────────────────────────────
# 书签 / 偏好（持久保存在模块数据目录）
# ───────────────────────────────────────────────
pref_file() { printf '%s/%s' "$PREFS_DIR" "$1"; }

cmd_pref_get() {
  local key="$1" f
  f="$(pref_file "$key")"
  if [ -f "$f" ]; then
    printf '{"ok":true,"value":"%s"}\n' "$(json_escape "$(cat "$f" 2>/dev/null)")"
  else
    printf '{"ok":true,"value":null}\n'
  fi
}

cmd_pref_set() {
  local key="$1" value="$2"
  printf '%s' "$value" > "$(pref_file "$key")" 2>/dev/null
  printf '{"ok":true}\n'
}

# ───────────────────────────────────────────────
# 入口 / 参数分发
# ───────────────────────────────────────────────
ACTION="$1"
shift

case "$ACTION" in
  list)      cmd_list "$@" ;;
  mkdir)     cmd_mkdir "$@" ;;
  touch)     cmd_touch "$@" ;;
  rename)    cmd_rename "$@" ;;
  delete)    cmd_delete "$@" ;;
  copy)      cmd_copy "$@" ;;
  move)      cmd_move "$@" ;;
  chmod)     cmd_chmod "$@" ;;
  chown)     cmd_chown "$@" ;;
  stat)      cmd_stat "$@" ;;
  read)      cmd_read "$@" ;;
  write)     cmd_write "$@" ;;
  exec)      cmd_exec "$@" ;;
  run)       cmd_run "$@" ;;
  extract)   cmd_extract "$@" ;;
  compress)  cmd_compress "$@" ;;
  archive-list) cmd_archive_list "$@" ;;
  archive-read) cmd_archive_read "$@" ;;
  archive-extract-one) cmd_archive_extract_one "$@" ;;
  install-apk) cmd_install_apk "$@" ;;
  uninstall-apk) cmd_uninstall_apk "$@" ;;
  apk-info) cmd_apk_info "$@" ;;
  list-apps) cmd_list_apps "$@" ;;
  list-apps-full) cmd_list_apps_full "$@" ;;
  app-info) cmd_app_info "$@" ;;
  pref-get)  cmd_pref_get "$@" ;;
  pref-set)  cmd_pref_set "$@" ;;
  *)
    printf '{"ok":false,"error":"未知操作: %s"}\n' "$(json_escape "$ACTION")"
    ;;
esac
