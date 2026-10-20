#!/bin/sh
# 1. 엔타이틀먼트를 붙이고(또는 떼고) 시뮬레이터 debug 빌드 → 재설치 → 실행 → 로그를 본다.
#   ./ios-entitlement-check.sh 'applinks:fan.example'
#   ./ios-entitlement-check.sh 'applinks:fan.example?mode=developer'
#   ./ios-entitlement-check.sh off
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BUNDLE=example.fan.exp.dle
if [ "$1" = off ]; then "$HERE/entitlement.sh" off; else "$HERE/entitlement.sh" on "$1"; fi
cd "$HERE/app"
flutter build ios --simulator --debug 2>&1 | tail -3
echo "build exit=$?"
echo "--- 앱 바이너리에 들어간 엔타이틀먼트(시뮬레이터용 __TEXT,__entitlements)"
strings build/ios/iphonesimulator/Runner.app/Runner | grep -E 'applinks|FAKETEAMID' | sort -u
xcrun simctl uninstall booted "$BUNDLE"
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
echo "install exit=$?"
xcrun simctl launch booted "$BUNDLE"
echo "launch exit=$?"
sleep 8
echo "--- 8초 뒤 프로세스"
xcrun simctl spawn booted launchctl list | grep "$BUNDLE" || echo "(실행 중 아님)"
echo "--- 로그(swcd의 fan.example, 앱의 DLE)"
xcrun simctl spawn booted log show --last 20s --style compact \
  --predicate '(process == "swcd" AND eventMessage CONTAINS "fan.example") OR (process == "Runner" AND eventMessage CONTAINS "DLE")' \
  2>/dev/null | grep -v '^Timestamp' | cut -c1-330
