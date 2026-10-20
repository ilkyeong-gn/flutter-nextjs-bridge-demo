#!/usr/bin/env python3
"""실측용 서버: 출처가 다른 iframe과 로그 수집기, Host에 보낼 명령 대기열.

  :3001  frame/  -> 출처가 다른 iframe(Web 화면은 :3000의 Next.js가 낸다)
  :8090  POST /log    -> logs/events.jsonl에 한 줄씩 추가하고 표준 출력에도 찍는다
         GET  /log    -> 지금까지 모은 로그
         DELETE /log  -> 로그 비우기
         POST /cmd    -> Host 앱에 보낼 명령 하나(JSON)를 대기열에 넣는다
         GET  /cmd    -> 쌓인 명령을 모두 꺼낸다(Host 앱이 0.3초마다 가져간다)
         POST/GET /gesture -> 같은 방식의 대기열. iOS XCUITest(ios-uitests/)가 가져가 탭·스와이프를 한다
"""

import json
import socket
import sys
import threading
import time
from functools import partial
from http.server import BaseHTTPRequestHandler, SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LOG = ROOT / "logs" / "events.jsonl"
LOCK = threading.Lock()
QUEUES: dict = {"/cmd": [], "/gesture": []}


class DualStackServer(ThreadingHTTPServer):
    address_family = socket.AF_INET6
    daemon_threads = True

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


class Static(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[static:{self.server.server_port}] {fmt % args}\n")


class Collector(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "content-type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")

    def _send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self._cors()
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self._send(204)

    def do_POST(self):
        length = int(self.headers.get("content-length", 0))
        body = self.rfile.read(length).decode("utf-8", "replace")
        try:
            record = json.loads(body)
        except ValueError:
            record = {"raw": body}
        if self.path in QUEUES:
            with LOCK:
                QUEUES[self.path].append(record)
            return self._send(204)
        record["recvTs"] = round(time.time() * 1000)
        line = json.dumps(record, ensure_ascii=False)
        with LOCK:
            with LOG.open("a", encoding="utf-8") as f:
                f.write(line + "\n")
        print(line, flush=True)
        self._send(204)

    def do_GET(self):
        if self.path in QUEUES:
            with LOCK:
                out = list(QUEUES[self.path])
                QUEUES[self.path].clear()
            return self._send(200, json.dumps(out).encode())
        data = LOG.read_bytes() if LOG.exists() else b""
        self._send(200, data, "application/x-ndjson; charset=utf-8")

    def do_DELETE(self):
        with LOCK:
            LOG.write_text("", encoding="utf-8")
            for q in QUEUES.values():
                q.clear()
        self._send(204)

    def log_message(self, *args):
        pass


def serve(port, handler):
    DualStackServer(("::", port), handler).serve_forever()


if __name__ == "__main__":
    LOG.parent.mkdir(exist_ok=True)
    static = partial(Static, directory=str(ROOT / "frame"))
    for port, handler in [(3001, static), (8090, Collector)]:
        threading.Thread(target=serve, args=(port, handler), daemon=True).start()
    print("serving :3001 (frame/), collecting :8090 -> logs/events.jsonl, commands :8090/cmd", flush=True)
    threading.Event().wait()
