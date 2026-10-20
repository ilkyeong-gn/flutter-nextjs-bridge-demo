# 브라우저 테스트는 운영 빌드에 테스트 껍데기를 심어 돌리고, CSP 위반을 실패로 본다

실제 Host 없이 기반을 확인하는 층은 셋이다. 계약 테스트, 모듈 테스트(Vitest), 브라우저 테스트(Playwright)다. 브라우저 테스트는 `next dev`가 아니라 운영 빌드(`next build && next start`)에서 돌린다. 가짜 Host 테스트 껍데기는 `addInitScript`로 `window.BridgeHost`를 설치한다([ADR 0017](0017-bridge-finds-transport-on-window.md)). 운영 CSP는 강제 모드이고 보고를 받지 않으므로([ADR 0019](0019-nonce-csp-and-only-our-bundle-in-main-frame.md)), CSP 위반은 테스트에서 드러나야 한다. 그래서 테스트 껍데기는 `securitypolicyviolation` 이벤트를 모아 두고, 테스트가 끝날 때 하나라도 있으면 실패시킨다. 잡히지 않은 페이지 예외(`pageerror`)도 실패로 본다. `bypassCSP`는 쓰지 않는다. Web 요소는 역할과 접근성 이름으로만 찾는다. 나중에 실제 Host E2E가 WebView 안을 같은 이름으로 찾게 하기 위해서다.

이 ADR은 [ADR 0011](0011-e2e-by-patrol-and-accessible-names.md)에서 Web 층과 접근성 이름 규칙만 이어받는다. Patrol, 플랫폼 코드 통합 테스트, Host 테스트는 이 지도의 범위 밖이다.

## Considered Options

- **`next dev`에서 돌린다**: 빌드가 없어 빠르다. 하지만 개발 껍데기 분기와 개발용 CSP(`'unsafe-eval'`)가 들어 있어 운영과 다른 페이지를 시험하게 된다.
- **`bypassCSP: true`로 껍데기를 심는다**: init script가 CSP를 적용받는지 걱정하지 않아도 된다. 하지만 페이지의 CSP 위반까지 함께 가려진다. init script는 엔진 프로토콜로 주입되어 CSP를 적용받지 않는다고 보고, 첫 smoke 테스트(두 브라우저에서 핸드셰이크가 `ready`가 된다)로 확인한다.
- **콘솔 에러를 모두 실패로 본다**: 위반 문구가 엔진마다 달라 파싱해야 하고, 관계없는 경고까지 실패가 된다.
- **`data-testid`로 찾는다**: 찾기는 쉽다. 하지만 나중 E2E는 OS 접근성 트리만 볼 수 있으므로 이름이 두 벌이 된다.

## Consequences

- Chromium과 WebKit 둘 다 돌린다. 지금은 두 브라우저 모두 중립 어댑터 하나를 지나므로, 둘로 돌리는 이유는 통로 모양이 아니라 엔진 차이다. 통로 모양 차이는 WebView 패키지가 정해진 뒤 어댑터 통합 테스트가 맡는다.
- 테스트 껍데기의 기본 응답은 첫 valid 픽스처이고 지연은 0ms다. Call 응답과 Event는 테스트 도중 바로 바꿀 수 있다. `hello` 모드, 버전, 기능 목록은 테스트를 시작할 때의 설정으로만 받는다([ADR 0020](0020-fake-host-answers-from-contract-fixtures.md)의 "다음 문서부터"와 같은 규칙).
- 접근성 이름이 불안정한 요소에는 `aria-label`을 붙인다. 문구를 바꾸면 테스트도 함께 바뀐다. 이 규칙은 lint로 막지 않는다.

결정의 자세한 내용: [기반 테스트 층 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/68)
