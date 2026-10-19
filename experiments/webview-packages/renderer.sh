#!/usr/bin/env bash
# Android 렌더러 종료 처리 실측(wf_ext MODE=renderer). scenario 하나를 실행하고 results/에
# 수집기 로그(jsonl), 걸러 낸 logcat, Host pid 변화, 화면을 남긴다.
#   (cd wf_ext && flutter build apk --debug --dart-define=MODE=renderer)
#   ./renderer.sh <scenario> <대기 초> [화면을 찍을 초 ...]
# scenario: control-crash control-kill guard two two-a-only two-b-only popup popup-gc popup-nomulti (wf_ext/lib/renderer.dart)
# 미리 할 것: python3 server.py 실행, Android 에뮬레이터 부팅.
set -euo pipefail
cd "$(dirname "$0")"
scenario=$1 wait=$2
shift 2
shots=" $* "
out="results/wf_ext-android-renderer-$scenario"
ADB=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}
pkg=dev.wayfinder.exp.wf_ext
mkdir -p results
curl -s -X DELETE -o /dev/null http://127.0.0.1:8090/log

# run.sh와 같은 이유로 화면을 켜 두고 Doze를 끈다.
"$ADB" shell input keyevent KEYCODE_WAKEUP
"$ADB" shell svc power stayon true
"$ADB" shell dumpsys deviceidle disable >/dev/null
"$ADB" shell wm dismiss-keyguard
"$ADB" install -r wf_ext/build/app/outputs/flutter-apk/app-debug.apk >/dev/null
"$ADB" shell am force-stop "$pkg"
"$ADB" logcat -c
"$ADB" shell am start -W -n "$pkg/.MainActivity" --es scenario "$scenario" >/dev/null

: > "$out-pid.txt"
last=unset seen=""
for elapsed in $(seq 1 "$wait"); do
  sleep 1
  pid=$("$ADB" shell pidof "$pkg" | tr -d '\r' || true)
  renderers=$("$ADB" shell ps -A -o PID,NAME | grep 'wf_ext:' | awk '{print $1}' | tr '\n' ' ' || true)
  seen="$seen $pid $renderers"
  if [ "$pid $renderers" != "$last" ]; then
    echo "${elapsed}s host=${pid:-없음} renderer=${renderers:-없음}" | tee -a "$out-pid.txt"
    last="$pid $renderers"
  fi
  case "$shots" in *" $elapsed "*) "$ADB" exec-out screencap -p > "$out-${elapsed}s.png" ;; esac
done
"$ADB" exec-out screencap -p > "$out-end.png"
if [ -n "$pid" ]; then
  "$ADB" shell dumpsys meminfo "$pkg" | grep -E 'WebViews|Activities' | tr -s ' ' | tee -a "$out-pid.txt"
fi
# Host와 렌더러 pid의 줄, 그리고 시스템이 이 앱에 대해 남긴 줄만 남긴다(에뮬레이터 HAL 잡음 제외).
"$ADB" logcat -d -v threadtime | python3 -c '
import re, sys
pids = set(sys.argv[1:])
noise = re.compile(r"EXP \{.*\"event\":\"(secure\.received|page\.|url\.|nav\.|http\.|resource\.|phase|check\.)|adbd|InputDispatcher|WindowManager|ImeTracker|Transition|AppsFilter| crashpad: ")
for line in sys.stdin:
    cols = line.split()
    mine = len(cols) > 2 and cols[2] in pids
    about = "wf_ext" in line or ("Abort message" in line and "webview" in line)
    if (mine or about) and not noise.search(line):
        sys.stdout.write(line)
' $seen > "$out-logcat.txt" || true
"$ADB" shell am force-stop "$pkg"
sleep 1
curl -s http://127.0.0.1:8090/log > "$out.jsonl"
echo "saved $out.jsonl ($(wc -l < "$out.jsonl") events), $out-logcat.txt ($(wc -l < "$out-logcat.txt") lines)"
