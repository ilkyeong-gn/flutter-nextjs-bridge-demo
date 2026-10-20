# 앱 안 이동은 얇은 관문으로만 하고, Web은 허용 출처를 환경 변수로 받지 않는다

경로 표와 화면 구성이 정해지지 않았어도 이동 관문은 지금 둔다. 모든 이동은 `shared/nav`의 `<AppLink>`, `useAppNavigation()`, 서버용 `redirectTo(path)`를 거친다. 지금 관문이 하는 일은 `next/link`와 `useRouter`를 감싸고 push와 replace를 구분해 드러내는 것뿐이다. `redirectTo`는 언제나 replace로 이동한다. 깊이 세기와 경로 표 판정은 넣지 않고, 나중에 들어갈 자리로만 남긴다. 링크는 자기 출처(`location.origin`)이면 앱 안 이동이다. 그 밖의 링크는 외부 링크이고 `browser.open {url}` Call로만 연다. 이 Call이 기반 계약의 첫 메서드다. Bridge 없음이거나 Call이 `unsupported`로 실패하면 관문은 둘을 같은 "열 수 없음" 실패로 넘긴다. 관문을 나중에 끼우려면 모든 이동 코드를 고쳐야 하지만, 지금 두는 비용은 얇은 래퍼 몇 개뿐이다.

Web은 허용 출처를 환경 변수로 받지 않는다. Web이 출처를 쓰는 곳은 링크 분류 하나이고, 이 분류는 자기 출처를 실행 중에 알면 된다. 환경 변수는 `shared/config` 한 모듈만 읽고, 시작할 때 검사해서 값이 없으면 바로 실패시킨다. 로컬에서 Web의 출처는 `http://localhost:3000` 하나다. Android 에뮬레이터는 `adb reverse`로 닿게 하고, 실기기는 https로 배포된 개발 서버에서 확인한다.

이 ADR은 [ADR 0014](0014-web-reads-data-over-http-only.md)의 이동 부분과 [ADR 0015](0015-route-table-in-contract-origins-in-env.md)의 허용 출처 부분을 대체한다. 두 ADR의 나머지(데이터는 HTTP로만 읽는다, 경로 표는 계약 원천에 둔다)는 이 결정과 관계가 없다.

## Considered Options

- **관문 안에서 지금 깊이를 센다(ADR 0014)**: 깊이는 뒤로가기 프로토콜을 위한 것인데, 그 프로토콜은 화면 구성이 정해져야 모양이 나온다.
- **관문을 나중에 둔다**: 그때는 이동 코드를 모두 찾아 고쳐야 한다.
- **Bridge 없음이면 `window.open`이나 `<a target="_blank">`로 연다**: 외부 링크를 열 때 Host가 다시 검사할 수 없게 된다. 열린 창을 어떻게 처리할지도 WebView 패키지마다 다르다.
- **Web에 `APP_ORIGIN`을 둔다(ADR 0015)**: 이 값은 Host 설정과 일치하는지 검사하려고 둔 사본이었는데, Host 설정은 이 지도의 범위 밖이다. 게다가 Next.js의 `.env.<env>`는 `development`·`production`·`test`만 알아보고 `next build`는 늘 `production`이라, 개발 서버와 운영 서버를 환경 파일 이름으로 나눌 수 없다.
- **Android 에뮬레이터를 `10.0.2.2`로 닿게 한다**: iOS 시뮬레이터와 출처가 갈린다. 또 보안 컨텍스트가 아니어서 `crypto.randomUUID` 같은 API가 막히고, Next 개발 서버에 `allowedDevOrigins`를 따로 설정해야 한다.

## Consequences

- Biome `noRestrictedImports`가 `next/link`를 막고, `next/navigation`의 `useRouter`·`redirect`·`permanentRedirect`도 막는다. `shared/nav`만 overrides로 풀어 준다. `location`은 `noRestrictedGlobals`로 막지만, `window.location` 대입은 리뷰 규칙으로만 막는다. `proxy`의 HTTP 리디렉트는 문서 단위 이동이라 막지 않는다.
- 저장소에는 로컬 기본값을 담은 `.env.development`와 `.env.example`만 둔다. 개발 서버와 운영 서버의 값은 배포 환경 변수에 둔다. `NEXT_PUBLIC_` 값은 빌드할 때 박히므로 환경마다 따로 빌드한다.
- Call id의 무작위 접두어는 `crypto.getRandomValues`로 만든다. 그래서 보안 컨텍스트에 기대지 않는다.
- "열 수 없음"을 어떻게 보일지는 Bridge 시작 상태와 실패 화면 결정에서 정한다.

결정의 자세한 내용: [앱 안 이동 관문과 허용 출처·환경 설정 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/65)
