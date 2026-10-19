#!/usr/bin/env bash
# flutter_inappwebview #2843 확인: release 빌드를 콜드 스타트로 N번 띄워 onWebViewCreated가 불리는지 센다.
#   (cd iaw_beta && flutter build apk --release --dart-define=MODE=coldstart)
#   ./coldstart.sh [횟수=30] [결과 이름=iaw_beta-android-coldstart]
# 미리 할 것: python3 server.py 실행, Android 에뮬레이터 또는 기기 연결.
set -euo pipefail
cd "$(dirname "$0")"
runs=${1:-30} name=${2:-iaw_beta-android-coldstart}
ADB=${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}
pkg=dev.wayfinder.exp.iaw_beta
mkdir -p results
"$ADB" shell input keyevent KEYCODE_WAKEUP
"$ADB" shell svc power stayon true
"$ADB" shell dumpsys deviceidle disable >/dev/null
"$ADB" shell wm dismiss-keyguard
"$ADB" install -r iaw_beta/build/app/outputs/flutter-apk/app-release.apk >/dev/null
curl -s -X DELETE -o /dev/null http://127.0.0.1:8090/log
for i in $(seq 1 "$runs"); do
  "$ADB" shell am force-stop "$pkg"
  sleep 1
  "$ADB" shell am start -W -n "$pkg/.MainActivity" | grep -E 'TotalTime' | tr -d '\r' | sed "s/^/launch $i: /"
  sleep 4.5  # 앱이 3초 뒤 판정(verdict)을 보낸다
done
"$ADB" shell am force-stop "$pkg"
sleep 1
curl -s http://127.0.0.1:8090/log > "results/$name.jsonl"
python3 - "results/$name.jsonl" <<'PY'
import json, sys
runs = {}
for line in open(sys.argv[1], encoding="utf-8"):
    r = json.loads(line)
    if r.get("src") != "dart":
        continue
    run = runs.setdefault(r["runId"], {"buildMode": r.get("buildMode")})
    if r["event"] == "onWebViewCreated":
        run["createdMs"] = r["sinceStartMs"]
    if r["event"] == "verdict":
        run["verdict"] = r["data"]["created"]
order = sorted(runs)
pattern = "".join("O" if runs[k].get("verdict") else ("X" if runs[k].get("verdict") is False else "?") for k in order)
created = [runs[k]["createdMs"] for k in order if "createdMs" in runs[k]]
print(f"launches={len(order)} buildModes={sorted({runs[k]['buildMode'] for k in order})}")
print(f"onWebViewCreated fired={pattern.count('O')} stuck={pattern.count('X')} unknown={pattern.count('?')}")
print(f"pattern={pattern}")
if created:
    print(f"onWebViewCreated ms since main(): min={min(created)} max={max(created)} median={sorted(created)[len(created)//2]}")
PY
