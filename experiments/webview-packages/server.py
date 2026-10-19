#!/usr/bin/env python3
"""실측용 서버: 출처 두 개와 로그 수집기.

  :8080  주 출처 (web/)            -> Web 화면 본문
  :8081  다른 출처 (web/, 같은 파일) -> 출처가 다른 iframe
  :8090  POST /log  -> logs/events.jsonl에 한 줄씩 추가하고 표준 출력에도 찍는다
         GET  /log  -> 지금까지 모은 로그
         DELETE /log -> 로그 비우기

HTML 안의 __HOST__는 요청한 Host 헤더의 호스트 이름으로 바꿔 보낸다. 그래서 같은 페이지를
iOS 시뮬레이터(localhost)와 Android 에뮬레이터(10.0.2.2) 양쪽에서 쓴다.
"""

import json
import os
import socket
import sys
import threading
import time
from functools import partial
from http.server import BaseHTTPRequestHandler, SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WEB = ROOT / "web"
LOG = ROOT / "logs" / "events.jsonl"
LOCK = threading.Lock()


class DualStackServer(ThreadingHTTPServer):
    """localhost가 ::1로 풀려도 받도록 IPv4·IPv6를 함께 연다."""

    address_family = socket.AF_INET6
    daemon_threads = True

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


class Static(SimpleHTTPRequestHandler):
    def do_GET(self):
        path = WEB / self.path.split("?", 1)[0].lstrip("/")
        if path.suffix != ".html" or not path.is_file():
            return super().do_GET()
        host = (self.headers.get("Host") or "localhost").rsplit(":", 1)[0]
        body = path.read_text(encoding="utf-8").replace("__HOST__", host).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

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

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("content-length", 0))
        body = self.rfile.read(length).decode("utf-8", "replace")
        try:
            record = json.loads(body)
        except ValueError:
            record = {"raw": body}
        record["recvTs"] = round(time.time(), 3)
        line = json.dumps(record, ensure_ascii=False)
        with LOCK:
            with LOG.open("a", encoding="utf-8") as f:
                f.write(line + "\n")
        print(line, flush=True)
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        data = LOG.read_bytes() if LOG.exists() else b""
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
        self.end_headers()
        self.wfile.write(data)

    def do_DELETE(self):
        with LOCK:
            LOG.write_text("", encoding="utf-8")
        self.send_response(204)
        self._cors()
        self.end_headers()

    def log_message(self, *args):
        pass


def serve(port, handler):
    DualStackServer(("::", port), handler).serve_forever()


if __name__ == "__main__":
    LOG.parent.mkdir(exist_ok=True)
    static = partial(Static, directory=str(WEB))
    # EXTRA_PORT=80처럼 주면 같은 web/을 기본 포트에서도 연다(포트를 생략한 출처 규칙 확인용).
    extra = [(int(p), static) for p in os.environ.get("EXTRA_PORT", "").split(",") if p]
    for port, handler in [(8080, static), (8081, static), (8090, Collector), *extra]:
        threading.Thread(target=serve, args=(port, handler), daemon=True).start()
    print(f"serving :8080 :8081 {[p for p, _ in extra]} (web/), collecting :8090 -> logs/events.jsonl", flush=True)
    threading.Event().wait()
