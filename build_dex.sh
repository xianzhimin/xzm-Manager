#!/system/bin/sh
# build_dex.sh —— 编译 AppLister.java 为 app_process 可用的 classes.dex -> bin/applister.dex
# 需要: javac, Android SDK android.jar, d8
set -e
cd "$(dirname "$0")"

ANDROID_JAR="$(ls ~/android-sdk/platforms/android-*/android.jar 2>/dev/null | tail -1)"
D8="$(ls ~/android-sdk/build-tools/*/d8 2>/dev/null | tail -1)"
[ -z "$ANDROID_JAR" ] && { echo "找不到 android.jar"; exit 1; }
[ -z "$D8" ] && { echo "找不到 d8"; exit 1; }

echo "android.jar = $ANDROID_JAR"
echo "d8          = $D8"

mkdir -p apk_java/build
javac --release 8 -cp "$ANDROID_JAR" -d apk_java/build apk_java/AppLister.java
"$D8" --min-api 24 --output apk_java/build apk_java/build/AppLister.class
cp apk_java/build/classes.dex bin/applister.dex
echo "✅ 生成 bin/applister.dex ($(wc -c < bin/applister.dex) 字节)"
