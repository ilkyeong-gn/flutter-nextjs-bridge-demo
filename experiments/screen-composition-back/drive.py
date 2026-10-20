#!/usr/bin/env python3
"""실측 시나리오를 돌린다.  python3 drive.py <android|ios> <nav|iframe|cover|swipe|back>

앱을 새로 설치·실행하고 명령을 수집기(:8090/cmd)로 보낸다. 실제 탭은 Android는 adb input,
iOS는 ios-uitests의 XCUITest(:8090/gesture)로 보낸다. 끝나면 results/<platform>-<scenario>.jsonl을 남기고
요약(1초 tick 제외)을 출력한다.
"""

import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BASE = "http://127.0.0.1:8090"
ADB = os.environ.get("ADB", str(Path.home() / "Library/Android/sdk/platform-tools/adb"))
SIM = os.environ.get("SIM", "booted")
PKG = "dev.wayfinder.exp.scb"
platform, scenario = sys.argv[1], sys.argv[2]
_seq = 0


def http(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    with urllib.request.urlopen(req, timeout=5) as r:
        return r.read()


def logs():
    return [json.loads(line) for line in http("GET", "/log").decode().splitlines() if line.strip()]


def mark(name):
    http("POST", "/log", {"src": "drive", "event": "mark", "data": name, "t": int(time.time() * 1000)})
    print(f"--- {name}", flush=True)


def wait_for(pred, timeout=10):
    end = time.time() + timeout
    while time.time() < end:
        for r in logs():
            if pred(r):
                return r
        time.sleep(0.2)
    return None


def cmd(name, **kw):
    http("POST", "/cmd", {"cmd": name, **kw})


def tagged(name, **kw):
    global _seq
    _seq += 1
    tag = f"{name}-{_seq}"
    cmd(name, tag=tag, **kw)
    return wait_for(lambda r: r.get("src") == "dart" and isinstance(r.get("data"), dict) and r["data"].get("tag") == tag and r["event"] != "cmd")


def state(label, id="root"):
    r = tagged("state", id=id)
    d = (r or {}).get("data") or {}
    print(f"    state[{label}] {id}: canGoBack={d.get('canGoBack')} url={d.get('currentUrl')}", flush=True)
    http("POST", "/log", {"src": "drive", "event": "state.label", "data": {"label": label, **d}, "t": int(time.time() * 1000)})


def gesture(**g):
    global _seq
    _seq += 1
    g["n"] = _seq
    http("POST", "/gesture", g)
    time.sleep(0.5)
    wait_for(lambda r: r.get("src") == "xcuitest" and r.get("event") == "driver.done" and r.get("cmd") == g, 20)


def tap(selector, id="root", in_frame=False):
    r = tagged("rect", id=id, selector=selector, inFrame=in_frame)
    if not r:
        print(f"    tap {selector}: rect 없음", flush=True)
        return
    d = r["data"]
    mark(f"tap {selector}{' (iframe 안)' if in_frame else ''}")
    if platform == "android":
        subprocess.run([ADB, "shell", "input", "tap", str(d["px"]), str(d["py"])], check=True)
    else:
        gesture(g="tap", x=float(d["x"]), y=float(d["y"]))


def js_click(selector, id="root"):
    mark(f"js click {selector}")
    cmd("js", id=id, code=f"document.querySelector('{selector}').click()")


def edge_swipe(y=450.0, to=300.0, x0=1.0, dur=0.05, vel=0.0):
    mark(f"edge swipe x0={x0} to={to} dur={dur} vel={vel or 'default'}")
    gesture(g="edge", y=y, to=to, x0=x0, dur=dur, vel=vel)


def go_background():
    mark("background")
    if platform == "android":
        subprocess.run([ADB, "shell", "input", "keyevent", "KEYCODE_HOME"], check=True)
    else:
        subprocess.run(["xcrun", "simctl", "launch", SIM, "com.apple.Preferences"], check=True, capture_output=True)


def go_foreground():
    mark("foreground")
    if platform == "android":
        subprocess.run([ADB, "shell", "am", "start", "-n", f"{PKG}/.MainActivity"], check=True, capture_output=True)
    else:
        subprocess.run(["xcrun", "simctl", "launch", SIM, PKG], check=True, capture_output=True)


def launch():
    http("DELETE", "/log")
    app = ROOT / "app"
    if platform == "android":
        for a in (["input", "keyevent", "KEYCODE_WAKEUP"], ["svc", "power", "stayon", "true"], ["dumpsys", "deviceidle", "disable"], ["wm", "dismiss-keyguard"]):
            subprocess.run([ADB, "shell", *a], capture_output=True)
        subprocess.run([ADB, "install", "-r", str(app / "build/app/outputs/flutter-apk/app-debug.apk")], check=True, capture_output=True)
        subprocess.run([ADB, "shell", "am", "force-stop", PKG], check=True)
        subprocess.run([ADB, "shell", "am", "start", "-W", "-n", f"{PKG}/.MainActivity"], check=True, capture_output=True)
        return None
    subprocess.run(["xcrun", "simctl", "terminate", SIM, PKG], capture_output=True)
    subprocess.run(["xcrun", "simctl", "install", SIM, str(app / "build/ios/iphonesimulator/Runner.app")], check=True)
    subprocess.run(["xcrun", "simctl", "launch", SIM, PKG], check=True, capture_output=True)
    time.sleep(2)
    driver = subprocess.Popen(
        ["xcodebuild", "test-without-building", "-project", "ios-uitests/GestureDriver.xcodeproj", "-scheme", "GestureDriver",
         "-destination", f"platform=iOS Simulator,id={sim_udid()}", "-derivedDataPath", "ios-uitests/build", "-test-timeouts-enabled", "NO"],
        cwd=ROOT, stdout=open(ROOT / "logs" / "xcuitest.log", "w"), stderr=subprocess.STDOUT)
    if not wait_for(lambda r: r.get("event") == "driver.ready", 120):
        sys.exit("XCUITest driver가 뜨지 않음(logs/xcuitest.log)")
    return driver


def sim_udid():
    out = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "booted", "-j"], capture_output=True, text=True).stdout)
    return next(d["udid"] for ds in out["devices"].values() for d in ds if d["state"] == "Booted")


# ---- 시나리오 ----

def nav():
    time.sleep(4)
    state("처음")
    tap("#to-a"); time.sleep(2); state("<Link> 탭 뒤")
    tap("#push-b"); time.sleep(2); state("router.push 탭 뒤")
    tap("#back"); time.sleep(2); state("router.back 탭 뒤")
    mark("goBack()"); cmd("goBack"); time.sleep(2); state("goBack() 뒤")
    mark("reset (사용자 활성화 없는 경우)"); cmd("reset", path="/"); time.sleep(4); state("reset 뒤")
    js_click("#to-a"); time.sleep(2); js_click("#push-b"); time.sleep(2); state("JS로 두 번 누른 뒤")
    mark("goBack()"); cmd("goBack"); time.sleep(2); state("goBack() 뒤")


def iframe():
    cases = [
        ("iframe 안 링크 실제 탭", lambda: tap("#frame", in_frame=True)),
        ("부모 단추 실제 탭으로 src 변경", lambda: tap("#iframe-src")),
        ("iframe 안 링크 JS click", lambda: js_click("#iframe-click")),
        ("부모 JS로 src 변경(사용자 활성화 없음)", lambda: js_click("#iframe-src")),
    ]
    for label, act in cases:
        mark(f"case: {label}")
        cmd("reset", path="/iframe"); time.sleep(5)
        state(f"{label} / 처음")
        act(); time.sleep(3)
        state(f"{label} / 뒤")
        mark("goBack()"); cmd("goBack"); time.sleep(3)
        state(f"{label} / goBack() 뒤")


def cover():
    time.sleep(4)
    mark("cover push"); cmd("cover"); time.sleep(2)
    mark("hostMsg 1 (가린 중)"); cmd("hostMsg", n=1); time.sleep(8)
    mark("hostMsg 2 (가린 중)"); cmd("hostMsg", n=2); time.sleep(1)
    mark("cover pop"); cmd("pop"); time.sleep(3)
    mark("hostMsg 3 (드러난 뒤)"); cmd("hostMsg", n=3); time.sleep(2)
    go_background(); time.sleep(3)
    mark("hostMsg 4 (백그라운드)"); cmd("hostMsg", n=4); time.sleep(7)
    go_foreground(); time.sleep(4)
    mark("hostMsg 5 (포그라운드 복귀 뒤)"); cmd("hostMsg", n=5); time.sleep(3)


def swipe():
    mark("case 5c: CupertinoPageRoute, WebView 기록 없음")
    time.sleep(4)
    cmd("pushWeb", id="p0", path="/"); time.sleep(4)
    state("5c 처음", id="p0")
    edge_swipe(); time.sleep(3)
    state("5c 스와이프 뒤", id="p0")

    mark("case 5a: CupertinoPageRoute, WebView 기록 2단")
    cmd("reset", path="/"); time.sleep(3)
    cmd("pushWeb", id="p1", path="/"); time.sleep(4)
    tap("#to-a", id="p1"); time.sleep(2)
    tap("#push-b", id="p1"); time.sleep(2)
    state("5a 스와이프 전", id="p1")
    edge_swipe(); time.sleep(3)
    state("5a 스와이프 1 뒤", id="p1")
    edge_swipe(); time.sleep(3)
    state("5a 스와이프 2 뒤", id="p1")
    edge_swipe(); time.sleep(3)
    state("5a 스와이프 3 뒤", id="p1")

    mark("case 5b: 루트 WebView(Flutter 스와이프 없음), Next.js 기록 2단")
    cmd("reset", path="/"); time.sleep(4)
    tap("#to-a"); time.sleep(2)
    tap("#push-b"); time.sleep(2)
    state("5b 스와이프 전")
    edge_swipe(); time.sleep(3)
    state("5b 스와이프 1 뒤")
    edge_swipe(); time.sleep(3)
    state("5b 스와이프 2 뒤")


def swipe_root():
    """5b 다시: 루트 WebView에서 끌기 방식을 바꿔 본다."""
    variants = [dict(x0=0.0), dict(x0=3.0, dur=0.0, vel=400.0), dict(x0=8.0, dur=0.0, vel=1500.0), dict(x0=2.0, dur=0.3, to=380.0, vel=800.0)]
    time.sleep(4)
    tap("#to-a"); time.sleep(2)
    tap("#push-b"); time.sleep(2)
    for v in variants:
        state("스와이프 전")
        edge_swipe(**v); time.sleep(3)
        state("스와이프 뒤")


def safari_control():
    """대조군: 같은 Next.js 화면을 시뮬레이터 Safari에서 열고 같은 방식으로 가장자리를 끈다."""
    subprocess.run(["xcrun", "simctl", "openurl", SIM, "http://localhost:3000/"], check=True)
    time.sleep(5)
    gesture(g="activate", bundle="com.apple.mobilesafari"); time.sleep(2)
    mark("Safari tap Link → /a"); gesture(g="tapLabel", label="Link → /a"); time.sleep(2)
    mark("Safari tap router.push"); gesture(g="tapLabel", label="router.push('/b')"); time.sleep(2)
    edge_swipe(); time.sleep(3)
    edge_swipe(x0=0.0, dur=0.0, vel=800.0); time.sleep(3)
    subprocess.run(["xcrun", "simctl", "io", SIM, "screenshot", str(ROOT / "results" / "ios-safari-control-end.png")], capture_output=True)


def back():
    time.sleep(4)
    tap("#to-a"); time.sleep(2)
    state("뒤로 가기 전")
    mark("KEYCODE_BACK"); subprocess.run([ADB, "shell", "input", "keyevent", "KEYCODE_BACK"], check=True); time.sleep(2)
    state("KEYCODE_BACK 뒤")
    mark("왼쪽 가장자리 뒤로 가기 제스처"); subprocess.run([ADB, "shell", "input", "swipe", "2", "1200", "600", "1200", "250"], check=True); time.sleep(2)
    state("제스처 뒤")
    mark("cover push 뒤 KEYCODE_BACK"); cmd("cover"); time.sleep(2)
    subprocess.run([ADB, "shell", "input", "keyevent", "KEYCODE_BACK"], check=True); time.sleep(2)
    state("cover 위 BACK 뒤")


SKIP = {"tick", "probe.start"}


def summarize(records):
    t0 = records[0]["t"] if records else 0
    for r in records:
        src, ev, d = r.get("src"), r.get("event"), r.get("data")
        if src == "dart" and ev == "js.channel":
            if d.get("event") in SKIP:
                continue
            line = f"js(channel) {d.get('event')} {json.dumps(d.get('data'), ensure_ascii=False) if d.get('data') else ''} vis={d.get('vis')} path={d.get('path')} tick={d.get('tick')} jsT={d.get('t') - t0} recvT={d.get('recvT') - t0}"
        elif src == "js":
            if ev in SKIP:
                continue
            line = f"js(fetch) {ev} {json.dumps(d, ensure_ascii=False) if d else ''} vis={r.get('vis')} path={r.get('path')} tick={r.get('tick')}"
        elif src == "dart" and ev in ("cmd", "rect"):
            continue
        else:
            line = f"{src} {ev} {json.dumps(d, ensure_ascii=False) if d is not None else ''}"
        print(f"{r.get('t', 0) - t0:>7} {line}")


if __name__ == "__main__":
    (ROOT / "logs").mkdir(exist_ok=True)
    (ROOT / "results").mkdir(exist_ok=True)
    driver = launch()
    try:
        globals()[scenario]()
    finally:
        if driver:
            http("POST", "/gesture", {"g": "quit"})
            try:
                driver.wait(30)
            except subprocess.TimeoutExpired:
                driver.kill()
        time.sleep(1)
        records = logs()
        out = ROOT / "results" / f"{platform}-{scenario}.jsonl"
        out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records))
        if platform == "android":
            subprocess.run([ADB, "shell", "am", "force-stop", PKG])
        else:
            subprocess.run(["xcrun", "simctl", "terminate", SIM, PKG], capture_output=True)
        print(f"saved {out} ({len(records)} records)")
        summarize(records)
