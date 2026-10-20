#!/bin/sh
# 2. 이미 설치된 앱에 `xcrun simctl openurl`로 커스텀 스킴을 연다. Flutter 도구 없이 실행된다.
#   ./ios-openurl.sh cold 5    # 앱을 끝낸 뒤 openurl, 5회
#   ./ios-openurl.sh warm 5    # 앱을 띄우고 Safari로 백그라운드에 보낸 뒤 openurl, 5회
set -u
BUNDLE=example.fan.exp.dle
MODE=$1
N=${2:-5}
i=1
while [ "$i" -le "$N" ]; do
  URL="fanapp://app/posts/3?run=$MODE-$i"
  if [ "$MODE" = cold ]; then
    xcrun simctl terminate booted "$BUNDLE" 2>/dev/null
    sleep 2
  else
    xcrun simctl launch booted "$BUNDLE" >/dev/null
    sleep 5
    xcrun simctl launch booted com.apple.mobilesafari >/dev/null
    sleep 3
  fi
  BEFORE=$(xcrun simctl spawn booted launchctl list | grep "$BUNDLE" | cut -f1)
  START=$(date '+%Y-%m-%d %H:%M:%S')
  xcrun simctl openurl booted "$URL"
  echo "== $MODE #$i openurl exit=$? url=$URL pid(before)=${BEFORE:-none}"
  sleep 8
  AFTER=$(xcrun simctl spawn booted launchctl list | grep "$BUNDLE" | cut -f1)
  echo "pid(after)=${AFTER:-none}"
  xcrun simctl spawn booted log show --start "$START" --style compact \
    --predicate 'process == "Runner" AND (eventMessage CONTAINS "DLE" OR eventMessage CONTAINS "Flutter tooling" OR eventMessage CONTAINS "Dart VM service")' \
    2>/dev/null | grep -v '^Timestamp' | sed 's/^.*flutter: //'
  i=$((i + 1))
done
