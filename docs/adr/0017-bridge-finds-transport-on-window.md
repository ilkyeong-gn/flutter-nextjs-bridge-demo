# Bridge는 Transport를 `window`에서 찾고, 지금은 중립 객체 하나만 안다

Web의 Bridge 모듈은 Transport를 밖에서 주입받지 않는다. `start()`가 `window`에서 찾는다. `connect()`는 어댑터 목록을 순서대로 시도하고, 아무것도 없으면 `null`을 돌려 Bridge 없음이 된다. WebView 패키지가 정해지지 않았으므로 지금 목록에 있는 어댑터는 중립 어댑터 하나다. 이 어댑터는 `window.BridgeHost`에 Android `addWebMessageListener`가 주입하는 객체와 같은 모양(`postMessage(text)`, `message` 이벤트의 문자열 `data`)이 있는지 `connect()` 때 한 번만 동기로 확인한다. 가짜 Host는 개발 껍데기와 테스트 껍데기 모두 이 객체를 설치한다. 그래서 개발, Playwright, 운영이 같은 `start()` 경로를 지나고, 테스트 껍데기는 `addInitScript`로 운영 빌드에도 그대로 들어간다([ADR 0012](0012-fake-host-plays-host-with-real-api.md)).

## Considered Options

- **`bridge.start(connect)`로 주입하고 `BridgeBoot`가 고른다**: 의존성이 명시적이다. 하지만 테스트 껍데기도 `BridgeBoot`의 분기를 거쳐야 해서 운영 빌드를 그대로 시험할 수 없고, Web 코드에 테스트용 분기가 생긴다.
- **가짜 Host가 특정 패키지의 객체 모양을 흉내 낸다**: 패키지가 정해지지 않았으므로 고를 모양이 없다.
- **중립 객체 모양을 새로 짓는다**: 어느 후보와도 같지 않은 모양이 하나 더 생긴다. `addWebMessageListener`의 모양은 후보 하나가 이미 주입하는 모양이고, Host가 문서 시작 스크립트로 흉내 내기도 쉽다.

## Consequences

- 운영 코드에 지금은 가짜 Host만 쓰는 어댑터가 하나 있다. 이름 `BridgeHost`는 가짜 Host 표식이 아니므로 운영 빌드의 표식 검사에 걸리지 않는다.
- 패키지가 정해지면 실제 어댑터를 목록 앞에 추가한다. Host가 같은 중립 모양을 주입하기로 하면 어댑터를 추가하지 않아도 된다.
- 중립 어댑터는 객체를 다시 찾지 않는다. 가짜 Host는 `start()` 전에 설치를 마쳐야 한다. 패키지가 객체를 늦게 넣는다면 그 기다림은 실제 어댑터 안에서 처리한다.
- Bridge 모듈의 테스트는 `window`를 거치지 않는다. 내부 팩토리 `createBridge`에 가짜 Host 코어의 메모리 Transport를 직접 넣는다. 어댑터는 따로 테스트한다.

결정의 자세한 내용: [shared/bridge 모듈 인터페이스와 React 연결 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/64)
