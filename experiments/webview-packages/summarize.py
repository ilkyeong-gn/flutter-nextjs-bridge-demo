#!/usr/bin/env python3
"""results/<app>-<platform>.jsonl을 단계별로 요약한다.

  python3 summarize.py results/wf_ext-android.jsonl [...]

- 프레임별로 보인 Bridge 통로와 문서 시작 스크립트 흔적
- Host(Dart)가 받은 Message: 통로, 보낸 프레임(본문의 role), 플랫폼이 알려 준 출처·메인 프레임 여부
- Web이 받은 응답: 응답에 적힌 출처·메인 프레임이 받은 프레임과 맞는지(다른 프레임 응답이 섞이는지)
- 내비게이션 콜백이 불린 URL
"""

import json
import sys


def role_of(record):
    data = record.get("data") or {}
    body = data.get("message", data.get("args"))
    if isinstance(body, list):
        body = body[0] if body else None
    if isinstance(body, str):
        try:
            body = json.loads(body)
        except ValueError:
            return "?"
    return (body or {}).get("role", "?") + "@step" + str((body or {}).get("step", "?"))


def main(path):
    rows = [json.loads(line) for line in open(path, encoding="utf-8")]
    rows.sort(key=lambda r: r.get("recvTs", 0))
    phase = "0"
    print(f"\n######## {path}")
    for r in rows:
        if r.get("src") == "dart" and r["event"] == "phase":
            phase = str(r["data"]["n"])
            print(f"\n== phase {phase}: {r['data']['what']}")
            continue
        r["phase"] = phase
        ev, data = r["event"], r.get("data")
        if r.get("src") == "dart":
            if ev in ("features", "attach", "webMessageListener.supported", "onWebViewCreated"):
                print(f"  [host] {ev}: {json.dumps(data, ensure_ascii=False)}")
            elif ev == "nav.request":
                frame = data.get("isMainFrame", data.get("isForMainFrame"))
                print(f"  [host] nav.request  mainFrame={frame}  {data['url']}")
            elif ev == "Legacy.received":
                print(f"  [host] Legacy.received from {role_of(r):<18} (출처 정보 없음, 본문만)")
            elif ev in ("secure.received", "callHandler.received"):
                via = data.get("name", "callHandler")
                origin = data.get("sourceOrigin", data.get("origin"))
                print(f"  [host] {via:<15} from {role_of(r):<18} origin={origin:<22} isMainFrame={data['isMainFrame']!s:<5} → {data['hostDecision']}")
            elif ev.startswith(("inAppBrowser", "safari", "headless", "mainWebView", "alert")):
                print(f"  [host] {ev}: {json.dumps(data, ensure_ascii=False)}")
            elif ev in ("resource.error",):
                print(f"  [host] {ev}: {json.dumps(data, ensure_ascii=False)}")
        elif r.get("src") == "web":
            who = f"{r['role']}@step{r['step']}"
            if ev == "probe.seen":
                seen = {k: v for k, v in data.items() if v not in ("undefined", False, None)}
                print(f"  [web ] {who:<18} {r['origin']:<22} 보이는 것: {json.dumps(seen, ensure_ascii=False)}")
            elif ev.endswith(".reply") or ev.endswith(".error"):
                payload = data.get("data", data.get("r", data.get("e")))
                if isinstance(payload, str):
                    try:
                        payload = json.loads(payload)
                    except ValueError:
                        pass
                note = ""
                if isinstance(payload, dict) and "isMainFrame" in payload:
                    mine = r["role"] == "main"
                    origin = payload.get("verifiedOrigin", payload.get("origin"))
                    if payload["isMainFrame"] != mine or origin != r["origin"]:
                        note = "  ← 다른 프레임에 보낸 응답"
                print(f"  [web ] {who:<18} {ev:<26} {json.dumps(payload, ensure_ascii=False)}{note}")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
