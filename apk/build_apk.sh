#!/usr/bin/env bash
# xzm 管理器 · 伴随 APK 构建脚本（无 Gradle，手撸 aapt2 + javac + d8 + apksigner）
set -e
cd "$(dirname "$0")"

SDK="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
BT="$SDK/build-tools"
# 取最高版本 build-tools
BTVER=$(ls "$BT" 2>/dev/null | sort -V | tail -1)
BT="$BT/$BTVER"
PLATFORM=$(ls "$SDK/platforms" 2>/dev/null | sort -V | tail -1)
AJAR="$SDK/platforms/$PLATFORM/android.jar"

echo "SDK      = $SDK"
echo "build-tools = $BTVER"
echo "platform = $PLATFORM"
[ -f "$AJAR" ] || { echo "❌ 找不到 android.jar: $AJAR"; exit 1; }

OUT=build
rm -rf "$OUT"; mkdir -p "$OUT/res" "$OUT/gen" "$OUT/classes" "$OUT/dex"

# 1) 编译资源
"$BT/aapt2" compile --dir res -o "$OUT/res.zip"
"$BT/aapt2" link \
  -o "$OUT/app-unsigned.apk" \
  -I "$AJAR" \
  --manifest AndroidManifest.xml \
  --java "$OUT/gen" \
  --min-sdk-version 21 --target-sdk-version 34 \
  "$OUT/res.zip"

# 2) 编译 Java
find src "$OUT/gen" -name '*.java' > "$OUT/sources.txt"
javac -source 8 -target 8 -bootclasspath "$AJAR" \
  -d "$OUT/classes" @"$OUT/sources.txt" 2>&1 | grep -v "bootstrap class path" || true

# 3) dex
"$BT/d8" --release --lib "$AJAR" --output "$OUT/dex" \
  $(find "$OUT/classes" -name '*.class')

# 4) 打包
cp "$OUT/app-unsigned.apk" "$OUT/app.apk"
(cd "$OUT/dex" && zip -q "$OLDPWD/$OUT/app.apk" classes.dex) 2>/dev/null || \
  (cd "$OUT" && zip -q app.apk dex/classes.dex)

# 5) 签名（用 debug keystore）
KS="$HOME/.android/debug.keystore"
if [ ! -f "$KS" ]; then
  mkdir -p "$HOME/.android"
  keytool -genkeypair -keystore "$KS" -storepass android -keypass android \
    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" 2>/dev/null
fi
"$BT/zipalign" -f 4 "$OUT/app.apk" "$OUT/app-aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$OUT/xzm-launcher.apk" "$OUT/app-aligned.apk"

echo "✅ 已生成: $OUT/xzm-launcher.apk"
"$BT/apksigner" verify --print-certs "$OUT/xzm-launcher.apk" | head -3
