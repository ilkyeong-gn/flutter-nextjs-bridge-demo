# 가짜 Host 개발 껍데기는 계약 픽스처로 답하고, 설정을 바로 적용할 것과 다음 문서부터 적용할 것으로 나눈다

인증 방식이 정해지지 않았고 데이터 API도 이 기반의 범위 밖이다. 그래서 가짜 Host 개발 껍데기는 Host가 할 일을 실제 API로 하지 않는다. Call마다 계약 원천의 픽스처(`contract/fixtures/<항목>/valid|invalid/*.json`)나 에러, 무응답 가운데 하나로 답한다. 기본은 첫 valid 픽스처로 자동 응답하는 것이고, 지연은 300ms다. 매번 사람이 고르는 "물어보기"는 Call마다 따로 켠다. 패널 설정은 둘로 나뉜다. Call 응답·지연과 Event 보내기는 바로 적용된다. `hello` 응답, Host 계약·앱 버전, 기능 목록은 다음 문서부터 적용된다. Bridge 없음은 문서를 다시 불러올 때까지 풀리지 않기 때문이다. 그래서 설정은 가짜 Host 자신의 `sessionStorage`에 두고, 핸드셰이크 설정이 바뀌면 패널이 "다시 불러오기"를 안내한다. 이 ADR은 [ADR 0012](0012-fake-host-plays-host-with-real-api.md)의 "개발 껍데기는 Host가 할 일을 실제 API로 한다" 부분을 대체한다. 코어 하나에 껍데기 둘, 출처 판정을 흉내 내지 않는 것, `next dev`와 쿼리·쿠키로만 켜는 것은 그대로다.

## Considered Options

- **ADR 0012처럼 실제 API로 한다**: 로그인 API와 핸드오프 경로는 인증 방식이 정해져야 생긴다. 지금은 부를 API가 없다.
- **"물어보기"를 기본으로 한다**: 응답을 하나하나 보며 고를 수 있다. 하지만 화면을 만드는 동안 Call마다 손이 가서, 개발의 대부분을 차지하는 정상 경로가 느려진다.
- **설정을 모두 바로 적용한다**: 기능 목록과 계약 버전은 핸드셰이크 때 한 번만 오간다. 문서가 사는 동안 바꾸면 이미 끝난 핸드셰이크와 어긋난 Host를 흉내 내게 된다. 실제 Host에는 그런 상태가 없다.

## Consequences

- 인증 방식이 정해지면 그때 개발 껍데기가 실제 API를 쓸지 다시 정한다. 그 전까지는 개발 전용 인증 경로를 만들 일이 없다.
- 패널이 고를 수 있는 에러는 메서드별 코드와 Host가 내는 공통 코드(`unavailable`, `permission_denied`, `not_allowed`, `cancelled`, `internal`)다. `unsupported`와 `timeout`은 Web이 스스로 만들고, `invalid_params`는 코어가 매개변수를 디코딩해서 직접 낸다.
- 옛 Host 흉내는 패널에서 "기능 목록에서 빼기" 하나로만 한다. 목록에는 있는데 Host가 `unknown_method`로 답하는 경우는 Host 버그이므로, 모듈 테스트가 코어를 직접 설정해서 확인한다.
- 패널 로그에는 페이로드 값까지 보인다. 가짜 Host는 Host 역할이고 Web의 개발 로그 규칙(값을 찍지 않는다)은 Bridge 모듈의 규칙이다. 그 대신 패널 로그는 메모리에만 두고 콘솔과 `sessionStorage`에 남기지 않는다.
- 패널은 Shadow DOM 안에 그린다. CSP([ADR 0019](0019-nonce-csp-and-only-our-bundle-in-main-frame.md))에 걸리지 않게 스타일은 `adoptedStyleSheets`로 붙인다. CSP가 이것을 막지 않는지는 구현할 때 확인한다.

결정의 자세한 내용: [가짜 Host 개발 껍데기 모양 프로토타입](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/67)
