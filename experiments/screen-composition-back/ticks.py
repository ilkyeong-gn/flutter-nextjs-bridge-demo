#!/usr/bin/env python3
"""표시(mark) 사이마다 JS 1초 타이머가 몇 번 돌았는지 센다.  python3 ticks.py results/ios-cover.jsonl

수집기가 받은 시각(recvTs, Mac 시계)으로 나눈다. JS 시각(t)으로도 센다(기기 시계라 표시와 조금 어긋날 수 있다).
"""

import json
import sys

records = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
marks = [r for r in records if r.get("src") == "drive" and r.get("event") == "mark"]
ticks_fetch = [r for r in records if r.get("src") == "js" and r.get("event") == "tick"]
ticks_channel = [r for r in records if r.get("src") == "dart" and r.get("event") == "js.channel" and r["data"].get("event") == "tick"]
bounds = [(m["data"], m["recvTs"]) for m in marks] + [("(끝)", records[-1]["recvTs"] + 1)]
print(f"{'구간':<28} {'길이s':>6} {'fetch 받음':>10} {'channel 받음':>12} {'JS t 기준 tick 범위':>20}")
for (name, start), (_, end) in zip(bounds, bounds[1:]):
    f = [r for r in ticks_fetch if start <= r["recvTs"] < end]
    c = [r for r in ticks_channel if start <= r["recvTs"] < end]
    in_js = [r["tick"] for r in ticks_fetch if start <= r["t"] < end]
    rng = f"{min(in_js)}–{max(in_js)}" if in_js else "-"
    print(f"{name:<28} {(end - start) / 1000:>6.1f} {len(f):>10} {len(c):>12} {rng:>20}")
