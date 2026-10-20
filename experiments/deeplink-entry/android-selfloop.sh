#!/bin/sh
# 3. Android 자기 순환: 앱이 launchUrl(externalApplication)로 연 https://fan.example/... 이 앱으로 돌아오는가.
#   ./android-selfloop.sh host 3    # intent-filter: host=fan.example 전체
#   ./android-selfloop.sh posts 3   # intent-filter: host=fan.example, pathPrefix=/posts/
# 에뮬레이터 하나가 부팅돼 있어야 한다. adb는 Android SDK platform-tools.
set -u
PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG=example.fan.exp.dle
VARIANT=$1
N=${2:-3}
MANIFEST="$HERE/app/android/app/src/main/AndroidManifest.xml"

case "$VARIANT" in
  host)  DATA='<data android:scheme="https" android:host="fan.example" />' ;;
  posts) DATA='<data android:scheme="https" android:host="fan.example" android:pathPrefix="/posts/" />' ;;
  *) echo "host|posts"; exit 1 ;;
esac
sed -i '' "s|^\([[:space:]]*\)<data android:scheme=\"https\".*<!-- APPLINK_DATA -->|\1$DATA<!-- APPLINK_DATA -->|" "$MANIFEST"
grep 'APPLINK_DATA' "$MANIFEST"

(cd "$HERE/app" && flutter build apk --debug 2>&1 | tail -1)
adb uninstall "$PKG" >/dev/null 2>&1
adb install -r "$HERE/app/build/app/outputs/flutter-apk/app-debug.apk" | tail -1
# 도메인 검증은 실패하므로(fan.example은 응답하지 않는다) 수동으로 승인 상태(2=approved)로 만든다.
adb shell pm set-app-links --package "$PKG" 2 fan.example
echo "--- get-app-links"
adb shell pm get-app-links "$PKG"

tap_text() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null
  adb shell cat /sdcard/ui.xml | tr '>' '\n' | grep "content-desc=\"$1\"\|text=\"$1\"" | head -1 \
    | sed -E 's/.*bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]".*/\1 \2 \3 \4/' \
    | { read x1 y1 x2 y2; adb shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2)); }
}

for target in /not-in-table /posts/3; do
  i=1
  while [ "$i" -le "$N" ]; do
    adb shell am force-stop "$PKG"
    adb shell am force-stop com.android.chrome
    adb logcat -c
    adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
    sleep 4
    tap_text "$target"
    sleep 4
    echo "== $VARIANT $target #$i"
    adb shell dumpsys activity activities | grep -m1 -E 'topResumedActivity|mResumedActivity' | sed 's/^ *//'
    adb logcat -d -s flutter | grep 'DLE' | sed 's/^.*DLE /DLE /'
    i=$((i + 1))
  done
done
