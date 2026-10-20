import XCTest

// `simctl openurl`로 커스텀 스킴을 열면 SpringBoard가 "Open in "Dle"?"를 묻는다.
// 이 테스트는 정해진 시간 동안 그 알림의 Open 단추를 찾아 누르기만 한다(앱은 건드리지 않는다).
final class AlertTapperUITests: XCTestCase {
  func testTapOpenAlerts() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let seconds = Double(ProcessInfo.processInfo.environment["TAPPER_SECONDS"] ?? "") ?? 240
    let deadline = Date().addingTimeInterval(seconds)
    var taps = 0
    while Date() < deadline {
      let open = springboard.buttons["Open"]
      if open.waitForExistence(timeout: 1) {
        open.tap()
        taps += 1
        print("TAPPER tapped Open #\(taps) at \(Date())")
      }
    }
    print("TAPPER done taps=\(taps)")
  }
}
