---
status: partially superseded by ADR-0020
---

# 가짜 Host는 코어 하나로 Host 역할을 실제 API로 하고, 출처 판정은 흉내 내지 않는다

브라우저 개발용 가짜 Host와 Playwright용 가짜 Host는 코어 하나를 함께 쓴다. 코어는 봉투, 핸드셰이크, iOS의 `listen` 대기 응답과 Android의 reply proxy를 흉내 낸다. 껍데기는 둘이다. 개발 껍데기는 조작 패널을 붙인다. 테스트 껍데기는 IIFE 번들로 `addInitScript`에 심는다. 흉내 내는 코드가 둘이면 둘이 서로 다르게 틀어지기 때문에 하나로 만든다. 개발 껍데기는 Host가 할 일을 실제 API로 한다. 로그인 API로 토큰을 받고, `fetch`로 `POST /auth/handoff`를 보내 HttpOnly 쿠키를 만든다. 첨부도 Bearer로 `POST /api/media`에 실제로 올린다. 그래서 개발 전용 인증 경로를 만들지 않고, 핸드오프 서버 코드가 브라우저에서도 매번 돈다. 출처·메인 프레임 판정은 흉내 내지 않는다. 대신 허용 출처의 최상위 문서에만 통로 객체를 넣는다. 다른 출처 iframe은 브라우저의 동일 출처 정책 때문에 그 객체에 닿지 못한다.

## Considered Options

- **개발용과 테스트용을 따로 만든다**: 테스트용은 얇은 기록기로 충분하다. 하지만 봉투와 `listen` 흐름을 흉내 내는 코드가 둘이 된다.
- **개발 전용 로그인 경로(`/api/dev/login`)로 쿠키를 바로 받는다**: 가짜 Host가 단순해진다. 대신 운영 코드 옆에 인증을 건너뛰는 경로가 생기고, 브라우저에서는 핸드오프가 돌지 않는다.
- **가짜 Host가 출처·메인 프레임 판정을 흉내 낸다**: 브라우저의 메시지는 같은 창의 객체 호출이라 판정할 재료가 없다. 흉내를 내도 플랫폼 코드를 검증하는 것이 아니다.

## Consequences

- 핸드오프 코드가 JS를 지난다. [ADR 0006](0006-web-session-by-offscreen-handoff.md)이 막으려던 경로다. 하지만 가짜 Host는 `next dev`와 Playwright에만 있으므로 받아들인다. 개발 껍데기는 `NODE_ENV === 'development'` 분기 안의 동적 import로만 불러온다. 서버의 안내 페이지 판정은 개발 모드에서만 `fakeHost` 쿠키를 본다. PR 검사는 운영 빌드 결과물에 가짜 Host 표식이 없는지 확인한다.
- 테스트 껍데기는 기본으로 모든 Call에 공유 픽스처로 답하고 네트워크를 쓰지 않는다. 실제 동작은 테스트가 Call마다 켠다.
- Playwright에서 공격 모드 임베드가 막히는 이유는 동일 출처 정책이고, 실제 앱에서는 Host의 판정이다. 판정 자체는 플랫폼 코드 통합 테스트가 맡는다([ADR 0011](0011-e2e-by-patrol-and-accessible-names.md)).
- 첨부 검증 규칙(사진 10장 또는 영상 하나, 100MB)을 가짜 Host도 검사한다. 그래서 계약 원천에 `constants` 칸을 두고 Dart·TypeScript 상수로 생성한다. [ADR 0004](0004-contract-source-with-own-generator.md)의 원천 범위가 payload와 메타데이터에 상수까지로 넓어진다.
- 브라우저 창은 문서 하나다. 자기 WebView를 가지는 route(글쓰기 등)는 같은 창 이동으로 흉내 내고, 커뮤니티의 상태는 잃는다. 문서가 바뀌어도 이어져야 하는 가짜 Host 상태(토큰, 설정, 대기 중인 일회 Event)는 가짜 Host 자신의 `sessionStorage`에 둔다. Web이 브라우저 저장소를 쓰지 않는다는 규칙은 Web의 규칙이다.

결정의 자세한 내용: [개발용 가짜 Host 설계](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/51)
