import XCTest

/// 시뮬레이터에 실제 터치를 보내는 도우미. 실측 앱(dev.wayfinder.exp.scb)을 다시 띄우지 않고 앞으로만 가져온다.
/// 수집기(:8090/gesture)를 0.2초마다 확인해 명령을 실행하고, 끝나면 :8090/log에 기록한다.
///   {"g":"tap","x":..,"y":..}            논리 좌표(pt) 탭
///   {"g":"edge","y":..,"x0":..,"to":..,"dur":..,"vel":..}  왼쪽 가장자리(x0, 기본 1pt)를 dur초 누른 뒤 to까지 vel(pt/s) 속도로 끌기
///   {"g":"activate","bundle":..}        다른 앱(대조용 Safari 등)으로 바꿔 앞으로 가져오기
///   {"g":"tapLabel","label":..}          접근성 이름으로 찾아 탭
///   {"g":"quit"}
final class GestureDriverUITests: XCTestCase {
  private let base = URL(string: "http://127.0.0.1:8090")!

  func testDrive() throws {
    executionTimeAllowance = 3600
    var app = XCUIApplication(bundleIdentifier: "dev.wayfinder.exp.scb")
    app.activate()
    log(["event": "driver.ready"])
    while true {
      for cmd in fetch() {
        let g = cmd["g"] as? String ?? ""
        if g == "quit" { log(["event": "driver.quit"]); return }
        if g == "activate" {
          if let b = cmd["bundle"] as? String { app = XCUIApplication(bundleIdentifier: b) }
          app.activate()
        }
        if g == "tapLabel", let label = cmd["label"] as? String {
          app.descendants(matching: .any)[label].firstMatch.tap()
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func at(_ x: Double, _ y: Double) -> XCUICoordinate { origin.withOffset(CGVector(dx: x, dy: y)) }
        switch g {
        case "tap":
          at(cmd["x"] as! Double, cmd["y"] as! Double).tap()
        case "edge":
          let y = cmd["y"] as? Double ?? 400
          let x0 = cmd["x0"] as? Double ?? 1
          let to = cmd["to"] as? Double ?? 300
          let dur = cmd["dur"] as? Double ?? 0.05
          let vel = cmd["vel"] as? Double ?? 0  // pt/s. 0이면 기본값
          at(x0, y).press(forDuration: dur, thenDragTo: at(to, y),
                          withVelocity: vel > 0 ? XCUIGestureVelocity(rawValue: vel) : .default, thenHoldForDuration: 0)
        default: break
        }
        log(["event": "driver.done", "cmd": cmd])
      }
      Thread.sleep(forTimeInterval: 0.2)
    }
  }

  private func fetch() -> [[String: Any]] {
    let done = DispatchSemaphore(value: 0)
    var out: [[String: Any]] = []
    URLSession.shared.dataTask(with: base.appendingPathComponent("gesture")) { data, _, _ in
      if let data, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { out = list }
      done.signal()
    }.resume()
    done.wait()
    return out
  }

  private func log(_ record: [String: Any]) {
    var r = record
    r["src"] = "xcuitest"
    r["t"] = Int(Date().timeIntervalSince1970 * 1000)
    var req = URLRequest(url: base.appendingPathComponent("log"))
    req.httpMethod = "POST"
    req.httpBody = try? JSONSerialization.data(withJSONObject: r)
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { _, _, _ in done.signal() }.resume()
    done.wait()
  }
}
