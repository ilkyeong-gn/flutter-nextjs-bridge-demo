#!/usr/bin/env bash
# 한 조합을 설치·실행하고 로그와 화면을 results/에 남긴다.
#   [TAG=이름] ./run.sh <wf_ext|iaw_beta> <android|ios> <대기 초> [화면 캡처 간격 초]
# TAG를 주면 결과 파일 이름 끝에 붙는다(같은 앱을 다른 MODE로 빌드했을 때).
# 미리 할 것: python3 server.py 실행, Android는 에뮬레이터 부팅, iOS는 시뮬레이터 부팅.
set -euo pipefail
cd "$(dirname "$0")"
app=$1 platform=$2 wait=$3 every=${4:-0}
out="$app-$platform${TAG:+-$TAG}"
ADB=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}
SIM=${SIM:-booted}
mkdir -p results
curl -s -X DELETE -o /dev/null http://127.0.0.1:8090/log

if [ "$platform" = android ]; then
  # Android 에뮬레이터는 10.0.2.2로 Mac에 닿는다. 화면이 꺼져 Doze에 들어가면 앱 UID의 네트워크가
  # 막히므로(셸 UID는 예외) 화면을 켜 두고 Doze를 끈다.
  "$ADB" shell input keyevent KEYCODE_WAKEUP
  "$ADB" shell svc power stayon true
  "$ADB" shell dumpsys deviceidle disable >/dev/null
  "$ADB" shell wm dismiss-keyguard
  pkg="dev.wayfinder.exp.$app"
  "$ADB" install -r "$app/build/app/outputs/flutter-apk/app-debug.apk" >/dev/null
  "$ADB" shell am force-stop "$pkg"
  "$ADB" shell am start -W -n "$pkg/.MainActivity" >/dev/null
  shot() { "$ADB" exec-out screencap -p > "results/$out-$1.png"; }
  stop() { "$ADB" shell am force-stop "$pkg"; }
else
  case $app in wf_ext) bundle=dev.wayfinder.exp.wfExt ;; iaw_beta) bundle=dev.wayfinder.exp.iawBeta ;; esac
  xcrun simctl terminate "$SIM" "$bundle" 2>/dev/null || true
  xcrun simctl install "$SIM" "$app/build/ios/iphonesimulator/Runner.app"
  xcrun simctl launch "$SIM" "$bundle" >/dev/null
  shot() { xcrun simctl io "$SIM" screenshot "results/$out-$1.png" >/dev/null 2>&1; }
  stop() { xcrun simctl terminate "$SIM" "$bundle" 2>/dev/null || true; }
fi

elapsed=0
while [ "$elapsed" -lt "$wait" ]; do
  sleep 1; elapsed=$((elapsed + 1))
  if [ "$every" -gt 0 ] && [ $((elapsed % every)) -eq 0 ]; then shot "$(printf '%02d' "$elapsed")s"; fi
done
shot end
stop  # 늦게 오는 보고가 다음 실행 로그에 섞이지 않게
sleep 1
curl -s http://127.0.0.1:8090/log > "results/$out.jsonl"
echo "saved results/$out.jsonl ($(wc -l < "results/$out.jsonl") events)"
