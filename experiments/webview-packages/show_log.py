#!/usr/bin/env python3
"""logs/events.jsonl을 사람이 읽기 좋게 한 줄씩 보여 준다. 인자로 다른 jsonl 경로를 줄 수 있다."""
import json
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "logs/events.jsonl"
for line in open(path, encoding="utf-8"):
    r = json.loads(line)
    data = json.dumps(r.get("data"), ensure_ascii=False)
    if r.get("src") == "dart":
        print(f"DART {r.get('app','')}/{r.get('platform','')} {r['event']:<26} {data[:260]}")
    elif r.get("src") == "web":
        print(f"WEB  {r.get('role',''):<11} step{r.get('step','')} {r.get('origin',''):<22} {r['event']:<26} {data[:220]}")
    else:
        print(f"RAW  {json.dumps(r, ensure_ascii=False)[:300]}")
