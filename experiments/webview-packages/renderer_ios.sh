#!/usr/bin/env bash
# iOS(선택 항목): wf_ext MODE=renderer를 시뮬레이터에서 띄우고, 첫 로드 뒤 시뮬레이터의 WebContent
# 프로세스를 Mac에서 kill -9로 끝낸다. 앱은 webContentProcessTerminated를 받으면 다시 로드한다.
#   (cd wf_ext && flutter build ios --simulator --debug --dart-define=MODE=renderer)
#   ./renderer_ios.sh
# 미리 할 것: python3 server.py 실행, iOS 시뮬레이터 부팅.
set -euo pipefail
cd "$(dirname "$0")"
SIM=${SIM:-booted}
bundle=dev.wayfinder.exp.wfExt
out=results/wf_ext-ios-renderer
mkdir -p results
curl -s -X DELETE -o /dev/null http://127.0.0.1:8090/log
xcrun simctl terminate "$SIM" "$bundle" 2>/dev/null || true
xcrun simctl install "$SIM" wf_ext/build/ios/iphonesimulator/Runner.app
xcrun simctl launch "$SIM" "$bundle" >/dev/null
for _ in $(seq 1 40); do
  sleep 1
  curl -s http://127.0.0.1:8090/log | grep -q '"ios-kill"' && break
done
# 시뮬레이터 런타임 안의 WebContent만 고른다(Mac의 Safari 것은 건드리지 않는다).
pids=$(ps -axo pid,command | grep -E 'simruntime.*WebContent' | grep -v grep | awk '{print $1}' | tr '\n' ' ')
ps -axo pid,command | grep -E 'simruntime.*WebContent' | grep -v grep | sed -E 's#/private/var/.*/RuntimeRoot#RuntimeRoot#' > "$out-pid.txt" || true
echo "kill -9 $pids" | tee -a "$out-pid.txt"
kill -9 $pids
sleep 15
xcrun simctl io "$SIM" screenshot "$out-end.png" >/dev/null 2>&1
xcrun simctl terminate "$SIM" "$bundle" 2>/dev/null || true
sleep 1
curl -s http://127.0.0.1:8090/log > "$out.jsonl"
echo "saved $out.jsonl ($(wc -l < "$out.jsonl") events)"
