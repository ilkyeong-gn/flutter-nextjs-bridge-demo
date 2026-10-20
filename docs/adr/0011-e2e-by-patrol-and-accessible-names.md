# E2E는 Patrol로 돌리고, WebView 안은 접근성 이름으로만 다룬다

Host와 Web을 함께 돌리는 E2E는 Patrol로 쓴다. Host 화면은 `ValueKey`(`<화면>.<요소>`)로, WebView 안은 OS 접근성 트리에 드러난 역할과 접근성 이름으로만 찾는다. 테스트가 `WebViewController`에 닿는 JS 주입 훅, `data-testid`, HTML id는 두지 않는다. 그 이유는 셋이다. 첫째, E2E가 확인해야 할 것은 아래 층에서 볼 수 없는 OS UI(권한, 사진 선택기, URL 열기, 알림)와 실제 터치 경로인데, 이를 Dart 하나로 다루는 도구는 Patrol뿐이다. 둘째, JS 주입 훅은 테스트만을 위한 Bridge 바깥의 통로를 Host에 만든다. 셋째, iOS 26에서는 HTML id가 접근성 트리에 드러나지 않는다. Web의 Playwright 테스트도 같은 접근성 이름을 쓰므로, 이름 하나로 두 층이 함께 요소를 찾는다.

## Considered Options

- **`integration_test`와 JS 주입**: 새 도구가 필요 없지만 실제 터치와 OS UI를 확인하지 못한다. 테스트가 컨트롤러에 닿는 훅도 있어야 한다.
- **Maestro**: 앱 코드를 거의 바꾸지 않아도 된다. 대신 WebView 매칭이 Chromium 148·150과 iOS 26의 변화에 흔들린 이력이 있고, 페이지 안의 상태를 읽지 못한다.
- **Appium `WEBVIEW` 컨텍스트**: CSS 선택자로 정확하게 찾는다. 대신 iOS에서 `isInspectable`을 켜야 하고, Chromedriver 버전을 맞춰야 하며, Host 화면은 `flutter_driver` 기반 드라이버로 따로 다뤄야 한다.

## Consequences

- Android WebView의 접근성 트리는 Patrol 기능표에서 ⚠️다. 열린 버그 #3178이 재현되면 uiautomator 2.2.0으로 고정한다. 에뮬레이터 시스템 이미지(API 35)와 iOS 시뮬레이터 런타임은 고정한다.
- 접근성 이름이 안정적이지 않은 Web 요소에는 `aria-label`을 붙인다. 문구를 바꾸면 테스트도 함께 바뀐다.
- 디버깅 프로토콜을 쓰지 않으므로 WebView 디버깅은 debug 빌드에서만 켠다는 결정([ADR 0005](0005-main-frame-stays-in-route-table.md))이 그대로 유지된다.
- 앱이 꺼진 상태에서의 진입(콜드 스타트)과 iOS 콘텐츠 프로세스 종료는 테스트가 앱 프로세스 안에서 돌기 때문에 자동화하지 못한다. 이 둘은 수동 체크리스트로 둔다.

결정의 자세한 내용: [테스트 전략 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/47)
