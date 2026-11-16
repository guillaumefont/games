#!/bin/bash
# Builds the Perigee Android app: a full-screen WebView around ../web (copied into the APK, so it
# plays offline). No Gradle: needs a JDK and the Ubuntu packages
#   android-sdk-platform-23 aapt dalvik-exchange zipalign apksigner
# Usage: [BUILD=<versionCode>] [VERSION_NAME=<name>] [KEYSTORE=<path>] ./build.sh [out.apk]
# Default output: build/perigee.apk. Signed with debug.keystore (test key, see README.md).
set -euo pipefail
unset JAVA_TOOL_OPTIONS
cd "$(dirname "$0")"
OUT="$(realpath -m "${1:-build/perigee.apk}")"
BUILD="${BUILD:-1}"
VERSION_NAME="${VERSION_NAME:-dev-b$BUILD}"
KEYSTORE="${KEYSTORE:-debug.keystore}"
SDK="${ANDROID_JAR:-/usr/lib/android-sdk/platforms/android-23/android.jar}"
rm -rf build/gen build/classes build/dex build/assets build/*.apk
mkdir -p build/gen build/classes build/dex build/assets "$(dirname "$OUT")"
# the game itself
cp -r ../web build/assets/www
# version from the build number (the manifest's own values are placeholders)
sed -e "s/android:versionCode=\"[^\"]*\"/android:versionCode=\"$BUILD\"/" \
    -e "s/android:versionName=\"[^\"]*\"/android:versionName=\"$VERSION_NAME\"/" AndroidManifest.xml > build/AndroidManifest.xml
aapt package -f -m -J build/gen -M build/AndroidManifest.xml -S res -I "$SDK"
javac --release 8 -nowarn -Xlint:-options -d build/classes -classpath "$SDK" $(find src build/gen -name '*.java')
dalvik-exchange --dex --output=build/dex/classes.dex build/classes
aapt package -f -M build/AndroidManifest.xml -S res -A build/assets -I "$SDK" -F build/unsigned.apk -0 woff2 -0 png
(cd build/dex && aapt add ../unsigned.apk classes.dex >/dev/null)
zipalign -f -p 4 build/unsigned.apk build/aligned.apk
apksigner sign --ks "$KEYSTORE" --ks-pass pass:android --key-pass pass:android --out "$OUT" build/aligned.apk
apksigner verify "$OUT"
aapt dump badging "$OUT" | head -1
ls -lh "$OUT"
