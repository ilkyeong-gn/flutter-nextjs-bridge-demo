# Web 세션은 Host가 화면 밖 WebView 핸드오프로 만들고, 토큰은 Web에 넘기지 않는다

로그인은 Host 화면에서 하고, 자격(access token과 회전하는 refresh token)은 Host만 가진다. Web 세션은 서버가 만든 HttpOnly 쿠키다. 로그인이 끝나면 Host가 서버에서 일회용 코드(60초, 1회)를 받는다. 그다음 화면에 붙이지 않은 WebView로 `POST /auth/handoff`를 열고 코드를 본문에 싣는다. 서버는 새 세션 id로 쿠키를 내리고 204로 답한다. 쿠키 저장소는 모든 WebView가 함께 쓴다(iOS `WKWebsiteDataStore.default()`, Android `CookieManager`). 그래서 열려 있던 Web 화면도 다시 로드하지 않고 바로 로그인 쿠키를 갖는다. 이렇게 하면 Web의 JS는 어떤 비밀 값도 보지 않고, Next.js 서버 렌더링도 세션을 안다.

## Considered Options

- **Host가 쿠키 API로 쿠키를 심는다**: `webview_flutter`는 HttpOnly·Secure·만료를 넣을 수 없고, iOS에서 첫 로드에 쿠키가 적용되지 않는다는 보고가 열려 있다. 플랫폼 코드로 넣으면 iOS HttpOnly가 문서에 없는 키에 기댄다.
- **Bridge Call로 토큰을 넘긴다**: XSS가 생기면 그 Call이 토큰 발급 통로가 된다. 서버 렌더링은 늘 비로그인으로 보인다.
- **보이는 WebView를 핸드오프 경로로 이동시킨다**: 페이지가 다시 로드되어 쓰던 글과 스크롤을 잃는다.
- **Web이 Call로 코드를 받아 fetch로 낸다**: 코드가 JS를 지나므로, 빼 간 코드로 다른 기기에서 세션을 만들 수 있다.
- **Host가 쿠키 저장소에서 익명 세션 id를 읽어 서버에 묶는다**: iOS 쿠키 동기화 지연과 Android 쿠키 값 파싱에 기대고, 세션 고정을 따로 막아야 한다.

## Consequences

- Web과 가짜 API가 같은 출처여야 1st-party 쿠키로 성립한다. Web을 앱에 묶어 출처가 갈리면 이 결정을 다시 본다.
- 화면에 붙이지 않은 WebView가 두 플랫폼에서 로드되는지, 다른 WebView에서 쿠키가 바로 보이는지는 실측하지 않았다. 둘 다 플랫폼 코드 통합 테스트에 넣는다.
- 핸드오프가 실패하면 한 번 다시 시도하고, 그래도 실패하면 로그인을 되돌린다. Host만 로그인된 상태는 남기지 않는다.
- Web 세션은 따로 갱신하지 않고, 로그인 세션이 살아 있는 동안만 유효하다. 갱신 주체는 Host 하나뿐이어서 refresh 회전과 부딪히지 않는다.
- Web이 쿠키를 잃었을 때는 `session.login` Call을 받은 Host가 로그인 세션을 확인하고 핸드오프만 다시 해서 복구한다.

결정의 자세한 내용: [로그인과 세션 설계 (S1)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/42)
