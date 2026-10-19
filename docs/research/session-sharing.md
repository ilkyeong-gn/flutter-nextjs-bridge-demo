# Host–Web 로그인 세션 공유 패턴 조사

- **질문**: [#31 Host–Web 로그인 세션 공유 패턴 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/31)
- **조사일**: 2026-10-19
- **확인한 버전**: webview_flutter 4.14.1(platform_interface 2.15.1, android 4.14.1, wkwebview 3.27.0), flutter_inappwebview 6.1.5(마지막 안정판, 2024-10), flutter_secure_storage 11.2.0, flutter_web_auth_2 5.1.0, flutter_appauth 12.1.0, Next.js 16 문서(저장소는 next 16.4.0), @tanstack/react-query 5.104.4, Chromium `main`(2026-10 기준), Apple·Android·Chrome 개발자 문서(2026-10 열람), RFC 10017(2026-08), draft-ietf-httpbis-rfc6265bis-22

## 요약

- 네 방식은 두 질문의 조합이다. ① 로그인 화면을 누가 띄우나(Host 화면, Web 화면, 시스템 브라우저), ② Web이 세션을 무엇으로 받나(WebView 쿠키, Bridge로 받은 토큰). 시스템 브라우저 로그인은 브라우저 쪽 쿠키 저장소에 남고[1][2] WebView로 이어진다는 근거가 없으므로, ②를 따로 정해야 한다.
- **쿠키 주입**: 플랫폼 API는 HttpOnly·Secure·만료를 지원하지만[3][4], webview_flutter 4.14.1의 `WebViewCookie`는 name·value·domain·path만 받는다[5]. 주입한 쿠키는 JS가 읽을 수 있고 만료도 없다. flutter_inappwebview 6.1.5는 속성을 받지만 iOS HttpOnly는 Apple 문서에 없는 키로 만든다[6][7].
- **서버 핸드오프**: WebView가 Host에게 받은 일회용 코드를 서버에 내면 서버가 `Set-Cookie`로 HttpOnly 세션을 만든다. 플랫폼 쿠키 API를 거치지 않으며, WebKit도 같은 결의 방법을 안내한다[8].
- **Bridge 토큰**: URL·웹 저장소에 두면 안 되는 근거는 분명하고[9][10], 메모리에 둬도 XSS에는 열려 있다[11]. Android에서 webview_flutter의 `JavaScriptChannel`은 `addJavascriptInterface` 위에 있어 호출 출처를 확인할 수 없다[12][13]. Next.js 서버는 요청 쿠키로 세션을 읽으므로[14], 토큰만 쓰면 서버 렌더링 단계는 로그인을 알 수 없다.
- **Web 로그인 → Host**: Host는 WebView 쿠키를 읽을 수 있지만(Android는 HttpOnly 포함)[15][16] 사본이 생겨 갱신이 어긋난다. Web이 Message로 일회용 코드를 넘기고 Host가 교환하면 HttpOnly를 지킨다.
- **갱신**: OAuth 공개 클라이언트(public client)인 Host의 refresh token은 회전 또는 송신자 제약이 필수이고, 회전 중 무효 토큰이 다시 오면 서버가 활성 토큰까지 폐기한다[17]. Host와 Web이 각자 갱신하면 스스로 로그아웃을 부르므로 갱신 주체는 하나여야 한다.
- **강제 종료**: 신호는 401 `invalid_token`이다[9]. 먼저 본 쪽이 Bridge로 알리는 계약(Web→Host Message, Host→Web Event)과, 서버에서 두 자격을 함께 폐기하는 연결이 필요하다[18].
- **로그아웃**: 서버 무효화가 먼저다(쿠키 삭제만으로는 탈취된 사본을 못 막음)[19]. 그다음 WebView 쿠키·저장소·캐시[20][21], Host 보안 저장소, Web 메모리 캐시를 지운다. webview_flutter의 iOS `clearLocalStorage`는 localStorage만 지운다[22].
- **재시작 후**: Android WebView는 만료 없는 세션 쿠키까지 저장했다가 복원한다[23]. iOS 기본 데이터 저장소도 영속적이지만[21] 만료 없는 쿠키가 남는지는 공식 문서로 확인하지 못했다. Keychain 항목은 앱을 지워도 남을 수 있다[24].
- **쿠키 정책**: Web과 가짜 API가 같은 Next.js 오리진이면 `SameSite=Lax` 1st-party 쿠키로 충분하다[25]. Web을 로컬 번들로 띄우면 API 쿠키가 3rd-party가 되어 WKWebView(ITP 기본)와 Android(기본 거부)에서 막힐 수 있다[26][8][3]. 개발용 `http://10.0.2.2`에서는 Secure 쿠키를 쓸 수 없다[3][27][28].

## 상세

### 1. 세션이 머무는 곳과 방식 비교

- **WebView 쿠키 저장소**: Android는 앱의 모든 WebView가 함께 쓰는 싱글턴 `CookieManager`다[3]. iOS는 WebView 설정의 `WKWebsiteDataStore`이고, 기본값 `default()`는 디스크에 영속 저장한다[21].
- **시스템 브라우저 저장소**: Custom Tabs는 브라우저와 쿠키 저장소를 공유하고, WebView는 브라우저와 상태를 공유하지 않는다[1]. `ASWebAuthenticationSession`은 ephemeral이 아니면 세션 쿠키를 뺀 쿠키를 브라우저와 공유한다[2].
- **Host 저장소**: flutter_secure_storage는 iOS에서 Keychain을, Android에서 자체 암호 구성(기본값은 RSA OAEP로 감싼 AES-GCM 키)을 쓴다. 10.0.0부터 Jetpack Security의 `EncryptedSharedPreferences`는 권장하지 않는다[29].

결국 "하나의 로그인 상태"는 서버가 발급한 두 자격(Host의 토큰, Web의 쿠키나 토큰)을 같은 사용자 세션으로 묶는 문제다.

| 방식 | Web이 받는 것 | Web JS 노출 | Next.js 서버 렌더링의 로그인 인식 | 재시작 후 | 주요 함정 |
|---|---|---|---|---|---|
| A1 쿠키 주입(webview_flutter) | 쿠키 | 노출(HttpOnly 불가) | 가능 | Android 유지, iOS 미확인 | 속성 지정 불가, iOS 미적용 보고 |
| A2 쿠키 주입(flutter_inappwebview) | HttpOnly 쿠키 | 비노출 | 가능 | `Max-Age`로 유지 | iOS HttpOnly가 문서에 없는 키에 의존 |
| A3 서버 핸드오프 | 서버가 만든 HttpOnly 쿠키 | 비노출 | 가능 | `Max-Age`로 유지 | 경로 추가, 코드 유출 관리 |
| B Bridge 토큰 | 메모리 토큰 | 노출 | 불가 | Web이 Call로 다시 받음 | webview_flutter Android `JavaScriptChannel`의 출처 확인 불가, XSS |
| C Web 로그인 → Host | 서버가 만든 쿠키 | 비노출 | 가능 | 쿠키 설정을 따름 | Host 쪽 자격 확보 경로 필요 |
| D 시스템 브라우저 | A·B 중 하나로 이어 붙임 | A·B에 따름 | A·B에 따름 | A·B에 따름 | 브라우저 쿠키와 WebView 쿠키가 따로 놂 |

### 2. Host 로그인 후 WebView에 쿠키 주입

**플랫폼 API.** Apple은 `WKHTTPCookieStore`를 웹 페이지의 초기 쿠키를 지정하고, 로그아웃 때 세션 쿠키를 지우는 데 쓰라고 설명한다. 웹 페이지가 쿠키를 바꾸면 관찰자(`add(_:)`)로 감지한다[4]. `HTTPCookie` 속성 사전의 문서화된 키에 `secure`, `expires`, `maximumAge`, `sameSitePolicy`는 있지만 HttpOnly는 없다[7]. Android `setCookie`의 값은 `Set-Cookie` 헤더 형식이라 `HttpOnly`, `Max-Age` 같은 속성을 그대로 쓴다. `Secure`를 넣으려면 URL이 `https://`여야 하고, 콜백을 받는 판은 비동기다[3]. 인자 두 개짜리 판은 Chromium 구현상 동기다[30].

**webview_flutter 4.14.1.** `WebViewCookie`의 필드는 `name`, `value`, `domain`, `path` 넷뿐이다[5]. Android 구현은 `이름=값; path=...` 문자열을 만들고 이름과 값을 퍼센트 인코딩한다[31]. iOS 구현은 같은 네 속성으로 `HTTPCookie`를 만든다[32]. 그래서 주입한 쿠키에는 HttpOnly, Secure, 만료, SameSite가 없다. 만료 지원은 P2 기능 요청으로 열려 있다[33].

- **첫 로드 전 타이밍**: Android는 동기판 `setCookie`를 부르고[34][30], iOS는 `WKHTTPCookieStore`의 완료 핸들러에서 Future를 끝낸다[35]. 따라서 `await setCookie()` 다음에 `loadRequest()`를 부르면 된다. 4.14.0부터는 `getCookies`로 다시 읽어 확인할 수도 있다[36]. 그래도 iOS에서 쿠키가 적용되지 않는다는 이슈가 2022년부터 열려 있고(P2, 2025-03까지 같은 보고)[37], 원인은 밝혀지지 않았다.
- **헤더 주입은 대안이 못 된다**: `loadRequest(headers:)`는 Android에서 `loadUrl(url, additionalHttpHeaders)`, 즉 한 번의 로드 호출에 붙는 헤더다[38][39]. 이후 이동과 하위 요청에도 붙는다는 문서는 없고, 헤더 인증이 첫 URL에만 통했다는 사용자 보고가 있다[40]. POST는 `postUrl(url, body)`로 가서 헤더가 아예 빠진다[38].

**flutter_inappwebview 6.1.5.** `setCookie`가 `expiresDate`, `maxAge`, `isSecure`, `isHttpOnly`, `sameSite`를 받는다. Android 구현은 `Set-Cookie` 문자열을 만들고 `flush()`까지 부른다[41]. iOS 구현은 HttpOnly를 `HTTPCookiePropertyKey("HttpOnly")`로 넣는데[6], 이 키는 Apple 문서에 없다[7]. 6.1.5 뒤로는 6.2.0 베타(2026-02 beta.3)만 나왔다[42].

**서버 핸드오프(변형).** ① Host가 자기 액세스 토큰으로 서버에서 Web 세션용 일회용 코드를 받는다. ② WebView가 그 코드를 들고 핸드오프 경로를 연다. ③ 서버는 코드를 검증해 새 세션 ID를 만들고, `Set-Cookie: ...; HttpOnly; Secure; SameSite=Lax; Max-Age=...`를 내린 뒤 원래 화면으로 리다이렉트한다.

- 근거: WebKit은 3rd-party 쿠키에 기대는 대신, 토큰을 받아 서버가 Secure·HttpOnly 쿠키로 1st-party 로그인 세션을 만드는 방법을 안내한다[8]. Next.js의 Route Handler와 Server Function은 쿠키를 설정할 수 있다[14]. 인가 서버를 두는 구조라면 RFC 8693 토큰 교환으로 표현할 수도 있다[43].
- 위험: URL에 실린 자격은 브라우저 기록과 서버 로그로 샌다[9][17]. 그래서 인가 코드처럼 짧은 수명(최대 10분 권장)과 1회 사용을 지켜야 한다[44]. POST 본문으로 보낼 수도 있다(Android에서는 본문만 가고 헤더는 빠짐[38]). OWASP는 URL로 들어온 세션 ID를 받지 말라고 한다[19]. 그러니 코드는 세션 ID가 아니어야 하고, 서버는 새 세션을 발급해야 한다.

### 3. Host가 토큰을 보관하고 Bridge로 전달

Host가 refresh token을 보안 저장소에 둔다[29]. Web은 시작할 때와 401을 받았을 때 Call로 액세스 토큰을 받아 메모리에만 두고, `Authorization: Bearer` 헤더로 쓴다.

- **URL 금지**: RFC 6750은 bearer 토큰을 페이지 URL에 넣지 말라고 한다(SHOULD NOT)[9]. RFC 9700 §4.3도 브라우저 기록을 통한 유출을 공격으로 다룬다[17].
- **웹 저장소 금지**: OWASP는 세션 식별자를 localStorage에 두지 말라고 한다[10]. RFC 10017 §8.5는 localStorage, sessionStorage, IndexedDB 모두 악성 JS의 탈취를 막지 못한다고 정리한다[11]. Safari의 ITP는 Safari를 7일 쓰는 동안 그 사이트와 상호작용이 없으면 스크립트가 쓴 저장소를 지운다. WKWebView 앱에서의 계산 방식은 확인하지 못했다[8].
- **메모리도 XSS에는 열려 있다**: RFC 10017 §8.4는 클로저로 감춰도 프로토타입 오염으로 빼낼 수 있다고 본다. §5.1.3은 저장소를 완전히 격리해도 악성 코드가 앱과 같은 경로로 새 토큰을 받아낼 수 있다고 지적한다[11]. Bridge의 "토큰 주기" Call이 바로 그 경로가 된다(유추). 반대로 HttpOnly 쿠키만 쓰는 같은 도메인 구조는 사용자 브라우저를 통해 요청을 대리하는 공격에만 노출된다(§7.1.1)[11].
- **Android 함정**: webview_flutter의 `JavaScriptChannel`은 Android에서 `addJavascriptInterface`로 구현되고[12], 받은 Message에는 문자열만 담긴다[45]. Android는 이 API가 iframe을 포함한 모든 프레임에 객체를 노출하며 호출 프레임의 출처를 확인할 수단이 없다고 설명하고, 민감한 작업이나 사용자 데이터에 쓰지 말라고 권한다[13]. flutter_inappwebview 6.1.5에는 허용 출처 규칙을 받는 `WebMessageListener`가 있다[46]. 출처 제한의 세부는 #36, #28에서 다룬다.
- **Next.js 영향**: 서버 컴포넌트는 `cookies()`로 요청 쿠키를 읽고[14], 인증 가이드의 Proxy 검사도 쿠키에서 세션을 읽는다[25]. 토큰만 쓰면 로그인에 따라 달라지는 데이터는 Web에서 헤더를 붙여 조회하는 쪽(TanStack Query)으로 몰리고, 첫 화면은 토큰 Call을 기다린다(유추).

### 4. Web에서 로그인한 뒤 Host로 넘기기

Web 로그인은 Next.js 가이드대로 서버가 HttpOnly·Secure·SameSite 쿠키를 만드는 모양이 된다[25]. 이 쿠키는 WebView 저장소에만 있다.

- **Host가 알아채기**: iOS는 쿠키 관찰자로 변경을 감지할 수 있다[4]. Android `CookieManager`에는 변경 리스너가 없고[3], webview_flutter는 어느 쪽도 노출하지 않는다[31][32]. 실제로는 Web이 로그인 뒤 Message를 보내게 된다.
- **Host가 자격을 얻는 길**:
  1. WebView 쿠키 읽기: webview_flutter 4.14.0부터 `getCookies`가 있다[36]. Android `getCookie`는 Chromium 구현상 HttpOnly 쿠키도 돌려주지만[15][16] `이름=값`만 준다[3]. webview_flutter의 Android 구현은 `=`로 나눈 마지막 조각을 값으로 쓰므로, 값에 `=`가 있으면 값이 잘린다(소스 관찰)[31]. 읽은 쿠키를 Host 요청에 붙이면 사본이 둘이 되어 갱신과 만료가 어긋난다.
  2. 일회용 코드: 로그인 응답이 짧은 수명 코드를 함께 주고, Web이 Message로 넘기면 Host가 서버에서 자기 토큰으로 바꾼다. 핸드오프의 역방향이며 같은 코드 규칙을 따른다[44].
  3. 토큰 자체를 넘기기: Web JS가 토큰을 읽어야 하므로 HttpOnly의 이점이 사라진다[11].
- **WebView 안 로그인 폼**: RFC 8252는 OAuth 인가 요청에 WebView 같은 임베디드 사용자 에이전트를 쓰지 말라고 한다(MUST NOT). Host가 입력과 쿠키를 가로챌 수 있고, 같은 회사 앱이라도 최소 권한 원칙에 어긋난다는 이유다[47]. 자기 서버의 1st-party 로그인 폼은 OAuth 인가 요청이 아니어서 이 조항의 직접 대상은 아니다. RFC 10017 §7.1도 같은 도메인 앱이라면 OAuth 없이 서버 쿠키 세션으로 충분한 경우가 많다고 설명한다[11].

### 5. 시스템 브라우저 기반 OAuth와 앱 복귀

- **규약**: RFC 8252는 외부 사용자 에이전트, PKCE 필수, 세 가지 리디렉트 URI(전용 스킴, 소유를 증명한 https, 루프백)를 정한다[47].
- **iOS**: `ASWebAuthenticationSession`(iOS 12+)은 시작할 때 어느 도메인으로 인증하는지 묻는 시스템 모달을 띄우고, 콜백은 호출한 앱의 세션에만 전달한다[48]. ephemeral이 아니면 세션 쿠키를 뺀 쿠키를 브라우저와 공유한다. ephemeral(iOS 13+)은 이전 인증을 재사용하지 못해 다시 입력하게 할 수 있다[2]. iOS 17.4부터 https 콜백(`.https(host:path:)`)을 쓸 수 있다[49].
- **Android**: Custom Tabs는 브라우저와 쿠키 저장소를 공유한다[1]. Auth Tab은 Chrome 137부터 Custom Tabs 인증을 대체할 수 있고, 지원하지 않는 기기에서는 Custom Tabs로 자동 대체된다. https 리디렉트는 Digital Asset Links로 소유를 확인하고, http 리디렉트는 받지 않는다(androidx.browser 1.9.0)[50].
- **Flutter**: flutter_web_auth_2 5.x는 iOS에서 `ASWebAuthenticationSession`을, Android에서 Auth Tab(필요하면 Custom Tabs)을 쓰며, https 콜백에는 `httpsHost`·`httpsPath`가 필요하다[51]. flutter_appauth는 AppAuth를 감싸 PKCE, 토큰 갱신, `endSession`을 제공한다[52].
- **핵심**: 브라우저 쪽 쿠키가 WebView로 이어진다는 근거는 없다. Android는 WebView가 브라우저와 상태를 공유하지 않는다고 명시하고[1], Apple 문서는 브라우저와의 공유만 말한다[2]. 앱으로 돌아온 Host가 코드를 토큰으로 바꾼 뒤, Web 세션은 2절이나 3절 방식으로 따로 만들어야 한다. 브라우저 쪽 인가 서버 세션이 남아 있으면 로그아웃 뒤 다음 로그인이 입력 없이 통과될 수 있으므로, `endSession`이나 ephemeral 세션을 함께 검토한다[2][52].
- **Host 화면 로그인과의 관계**: Host 화면이 비밀번호를 받아 OAuth 토큰 엔드포인트로 보내는 ROPC grant는 금지다(MUST NOT)[17]. 브라우저 없이 인가를 받는 표준은 아직 초안이다[53]. 가짜 API를 OAuth가 아닌 1st-party 세션 API로 두면 이 제약은 직접 걸리지 않는다[11].

### 6. 만료와 갱신

- OAuth 공개 클라이언트(public client)인 Host의 refresh token은 송신자 제약이나 회전 중 하나가 필수다(RFC 9700 §2.2.2). 회전 방식에서는 무효화된 토큰이 다시 오면 서버가 누가 보냈는지 모른 채 활성 토큰을 폐기한다(§4.14.2)[17].
- 따라서 Host와 Web이 같은 grant로 각자 갱신하면 동시 갱신 하나가 폐기를 부른다. 갱신 주체를 하나(Host)로 두고, 여러 401을 한 번의 갱신으로 모아야 한다(유추).
- 쿠키 세션은 Server Function이나 Route Handler에서 쿠키를 다시 써서 연장한다. 서버 컴포넌트 렌더링 중에는 쿠키를 쓸 수 없다[14]. Next.js 16에서 middleware는 proxy로 이름이 바뀌었다[54]. Proxy는 프리페치를 포함한 모든 경로에서 돌므로 쿠키만 보는 낙관적 검사에 그쳐야 한다[25].
- webview_flutter로 주입한 쿠키는 만료가 없으므로, 만료는 서버의 세션 기록으로만 강제할 수 있다[5][19].

### 7. 서버가 세션을 끊었을 때: 감지와 Host·Web 동시 로그아웃

- **신호**: 만료·폐기된 토큰에는 401과 `invalid_token`으로 응답하고, 받은 쪽은 새 토큰으로 재시도할 수 있다[9]. Web 세션이 쿠키라면 fetch에서는 401로, 페이지 이동에서는 Proxy나 서버 컴포넌트의 로그인 리다이렉트로 드러난다[25].
- **Bridge 계약**: 감지 지점이 셋(Web의 fetch, Web의 페이지 이동, Host의 API 호출)이다. 그래서 Web→Host Message("세션 종료"와 이유)와 Host→Web Event(열린 모든 Web 화면에)가 필요하다. WebView 쿠키와 자기 저장소를 모두 지울 수 있는 Host가 모으는 자리가 되기 쉽다.
- **서버 쪽 연결**: 토큰 폐기는 같은 grant에서 나온 다른 토큰도 무효화할 수 있다[18]. Web 쿠키 세션을 Host grant에 묶어 두면 한쪽 폐기로 양쪽이 끊긴다(설계 선택).
- **원래 화면 복귀**: 로그인 뒤 돌아갈 경로는 허용 목록으로 검증한다. RFC 9700 §4.11.1은 오픈 리다이렉터를 금지한다[17].
- **CSRF**: 쿠키 세션에는 CSRF 방어가 필요하다(RFC 10017 §6.1.3.3)[11]. Next.js Server Action은 Origin과 Host 헤더를 비교하지만[55], Route Handler는 직접 막아야 한다.

### 8. 로그아웃 때 정리

- **순서**: 서버 세션 무효화가 먼저다. OWASP는 쿠키 삭제만으로는 탈취된 세션 ID 사본을 무효화하지 못한다고 한다[19].
- **Android**: MASTG는 `CookieManager.removeAllCookies`, `WebStorage.deleteAllData()`, `WebView.clearCache(true)` 호출을 점검한다[20]. webview_flutter는 이를 `clearCookies`, `clearLocalStorage`, `clearCache`로 노출하지만[31][38], `flush()`와 `removeSessionCookies`는 노출하지 않는다[34].
- **iOS**: `WKHTTPCookieStore.delete`[4], `WKWebsiteDataStore.removeData(ofTypes:modifiedSince:)`와 `allWebsiteDataTypes()`를 쓴다. iOS 17부터는 식별자별 영속 저장소를 만들고, WebView를 해제한 뒤 저장소째 지울 수 있다[21]. webview_flutter의 iOS `clearLocalStorage`는 localStorage 타입만, `clearCache`는 캐시 타입만 지우므로 IndexedDB 같은 다른 저장소는 남는다[22].
- **응답 헤더**: OWASP는 로그아웃 응답에 `Clear-Site-Data: "cache", "cookies", "storage"`를 권한다[19]. WebKit은 Safari 17.0부터 이 헤더로 1st-party 쿠키를 지운다[56]. WKWebView와 Android WebView의 처리는 확인하지 못했다.
- **Web 메모리**: TanStack Query의 `clear()`는 쿼리 캐시와 뮤테이션 캐시를 모두 비운다[57].
- **Host**: 보안 저장소의 토큰을 지운다. 앱을 지워도 Keychain 항목이 남는 동작은 문서화되지 않은 구현 세부다. Apple DTS는 디스크에 둔 무작위 키와 엮어 앱 삭제와 함께 무효화하는 방법을 제시했다[24].

### 9. 앱 재시작 후 유지

- **Android**: WebView는 세션 쿠키를 포함한 쿠키를 앱 세션 사이에 저장하고 복원하도록 설정돼 있다(`persist_session_cookies`, `restore_old_session_cookies`)[23]. 앱을 종료해도 로그아웃되지 않는다. OWASP도 브라우저 종료로 세션이 끝난다고 기대하지 말라고 한다[19].
- **iOS**: 기본 데이터 저장소는 디스크에 영속 저장한다[21]. 만료 없는 쿠키가 앱 종료 뒤 남는지는 공식 문서로 확인하지 못했다.
- **정리**: 서버가 만드는 쿠키에는 `Max-Age`나 `Expires`를 명시한다(Next.js 가이드도 권장)[25]. webview_flutter 주입 쿠키처럼 만료를 못 넣으면, Host가 콜드 스타트마다 Web 세션을 다시 세우는 쪽이 플랫폼 차이를 덮는다(유추). Bridge 토큰 방식에서는 Web이 다시 로드될 때마다 Call로 토큰을 받는다.
- **Host 저장소**: Android 자동 백업은 flutter_secure_storage의 키 복호화 오류를 일으킬 수 있어 README가 백업 제외를 안내한다[29].

### 10. 쿠키 정책(SameSite·ITP)의 영향

- **같은 오리진**: Web과 가짜 API(Route Handlers)가 한 Next.js 오리진이면 세션 쿠키는 1st-party이고, Next.js 예시의 `sameSite: 'lax'`로 충분하다[25].
- **Android 12 이상 타깃**: SameSite가 없으면 Lax로 보고, `SameSite=None`에는 Secure가 필수이며, http와 https 사이를 cross-site로 본다[58]. Chromium은 targetSdk 31 이상일 때 이 동작을 켠다[59][23].
- **3rd-party 쿠키**: Android는 API 21 이상을 타깃으로 하면 3rd-party 쿠키를 기본으로 거부하고, WebView마다 허용할 수 있다[3]. webview_flutter_android도 이 설정을 노출한다[31]. WebKit의 ITP는 iOS 13.4부터 3rd-party 쿠키를 전면 차단하고[8], iOS 14부터는 모든 WKWebView 앱에서 ITP가 기본으로 켜진다. 사용자가 끌 수 있게 하려면 `NSCrossWebsiteTrackingUsageDescription`이 필요하고, 이 설정은 API로 읽거나 바꿀 수 없다[26].
- **App-Bound Domains**: `WKAppBoundDomains`를 채택하면 `limitsNavigationsToAppBoundDomains`를 켠 WebView에서만 JS 주입·쿠키 조작·message handler를 쓸 수 있다[26].
- **Web 전달 방식과의 연결**: Web을 로컬 번들이나 커스텀 스킴으로 띄우면 API 쿠키가 cross-site가 되어 위 차단에 걸린다(유추). 그러면 Bridge 토큰이나 같은 오리진 프록시가 필요하다. #35, #46과 맞물린다.
- **개발 환경**: 현재 Demo는 Android 에뮬레이터에서 `http://10.0.2.2:3000`, iOS 시뮬레이터에서 `http://localhost:3000`을 연다[60]. Android는 `Secure` 쿠키를 `https://` URL에만 설정한다[3]. rfc6265bis는 비보안 오리진이 Secure 쿠키를 설정하지 못하게 하되, 잠재적으로 신뢰할 수 있는 오리진은 보안으로 본다[27]. W3C 기준으로 127.0.0.0/8과 localhost는 여기에 들지만 10.0.2.2는 들지 않는다[28]. 따라서 Android 개발 환경에서는 `Secure`나 `__Host-` 쿠키가 실패할 것으로 보인다(유추, 프로토타입 확인 필요).

## Reference App에 주는 시사점

「로그인과 세션 설계 (S1)」(#42)가 저울질할 축은 넷이다. ① 로그인 화면의 위치(Host 화면, Web 화면, 시스템 브라우저와 가짜 인가 서버), ② Web 세션의 형태(쿠키 또는 Bridge 토큰), ③ 세션의 원본과 갱신 주체, ④ 재시작 정책(WebView 쿠키를 믿을지, 콜드 스타트마다 다시 세울지). 대표 조합과 트레이드오프는 다음과 같다. 여기서는 고르지 않는다.

| 후보 | 구성 | 얻는 것 | 치르는 것 |
|---|---|---|---|
| ① Host 화면 로그인 + 서버 핸드오프 쿠키 | Host는 토큰, Web은 서버가 만든 HttpOnly 쿠키 | Next.js 가이드 그대로(서버 컴포넌트·Proxy가 세션을 앎), XSS가 쿠키를 못 빼감, WebView 패키지의 쿠키 API에 덜 의존 | 핸드오프 경로와 코드 수명 관리, 두 세션의 동시 폐기 연결, 콜드 스타트 재수립 |
| ② Host 화면 로그인 + 플랫폼 쿠키 주입 | ①과 같지만 Host가 쿠키를 직접 설정 | 서버 경로 추가 없음 | webview_flutter는 HttpOnly·만료 불가와 iOS 미적용 보고, flutter_inappwebview는 iOS HttpOnly가 문서에 없는 키에 의존. WebView 패키지 결정(#38)과 묶임 |
| ③ Host 화면 로그인 + Bridge 토큰 | Web은 Call로 받은 토큰을 메모리에 | 세션 원본이 Host 하나, 쿠키 정책·Web 전달 방식과 무관 | XSS 때 Bridge가 토큰 발급 통로가 됨, webview_flutter Android(`addJavascriptInterface`)는 출처 확인 불가, 서버 렌더링은 비로그인, 첫 화면이 Call을 기다림 |
| ④ Web 화면 로그인 + 일회용 코드로 Host 토큰 | Web은 쿠키, Host는 코드를 교환해 받은 토큰 | 로그인 UI를 Next.js로 만들고 Web 단독 개발이 쉬움 | Host 화면용 자격 발급 경로 추가, WebView 안 로그인 폼(자동 완성·패스키 지원 미확인) |
| ⑤ 시스템 브라우저(가짜 인가 서버) + ① 또는 ③ | RFC 8252 흐름, Host가 PKCE로 토큰 획득 | 실제 소셜 로그인·SSO로 옮기기 쉬움 | 외부 연동이 없는 Reference App에서는 비용이 큼(스킴이나 Universal Links·App Links, Auth Tab), 브라우저 쪽 세션의 로그아웃 처리 |

어느 조합이든 함께 정할 것:

- 갱신 주체를 하나로 두고 동시 401을 한 번의 갱신으로 모으는 규칙.
- 세션 종료를 알리는 Bridge 계약(Web→Host Message, Host→Web Event, 이유 코드).
- 로그아웃 순서(서버 무효화 → Host 저장소 → WebView 쿠키·저장소·캐시 → Web 메모리 캐시).
- 가짜 API가 흉내 낼 범위. refresh 회전, 재사용 탐지, 서버 쪽 강제 종료가 있어야 S1의 "서버에서 세션이 끊기면 함께 로그아웃"을 검증할 수 있다.
- 개발 환경(`http://10.0.2.2`)에서 Secure 쿠키를 어떻게 다룰지.

## 확인하지 못한 것과 새로 생긴 질문

확인하지 못한 것:

- iOS WKWebView에서 만료 없는 쿠키가 앱 종료나 백그라운드 정리 뒤에도 남는지(공식 문서 없음).
- flutter/flutter#115460의 원인, 그리고 webview_flutter_wkwebview 3.27.0과 iOS 26·27에서도 재현되는지.
- `HTTPCookie.cookies(withResponseHeaderFields:for:)`가 HttpOnly 속성을 보존하는지. 문서에 명시가 없다[61].
- 개발용 http 환경에서의 동작: WKWebView가 `http://localhost`에서 Secure 쿠키를 받는지, Android 에뮬레이터에서 localhost로 붙을 때의 쿠키, `ASWebAuthenticationSession`과 Auth Tab이 http 인증 페이지를 여는지.
- ITP의 7일 상한이 WKWebView 앱에서 어떻게 계산되는지, 플랫폼 API로 넣은 쿠키에도 적용되는지.
- WKWebView와 Android WebView가 `Clear-Site-Data`를 처리하는지.
- WebView 안 로그인 폼에서 Password AutoFill, 자동 완성, 패스키가 동작하는 조건.

새로 생긴 질문:

- 핸드오프 경로의 계약: GET과 POST 중 무엇을 쓸지, 코드 수명, 실패했을 때의 화면.
- 세션 관련 Message·Event를 Bridge 계약 형태(#39)에 어떻게 넣을지.
- 여러 Web 화면이 동시에 열려 있을 때 세션 Event를 어떻게 전달하고 맞출지.
- 백그라운드에서 돌아왔을 때 만료된 토큰을 미리 갱신할지.
- 개발 환경의 Secure 쿠키 정책(환경별 플래그, HTTPS 개발 서버 등).

## 출처

1. [Chrome for Developers — Overview of Android Custom Tabs](https://developer.chrome.com/docs/android/custom-tabs)
2. [Apple Developer Documentation — Authenticating a User Through a Web Service](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service)
3. [Android Developers — CookieManager (API reference)](https://developer.android.com/reference/android/webkit/CookieManager)
4. [Apple Developer Documentation — WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)
5. [flutter/packages — webview_flutter_platform_interface 2.15.1, webview_cookie.dart](https://github.com/flutter/packages/blob/webview_flutter_platform_interface-v2.15.1/packages/webview_flutter/webview_flutter_platform_interface/lib/src/types/webview_cookie.dart)
6. [flutter_inappwebview v6.1.5 — iOS MyCookieManager.swift](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_ios/ios/Classes/MyCookieManager.swift)
7. [Apple Developer Documentation — HTTPCookiePropertyKey](https://developer.apple.com/documentation/foundation/httpcookiepropertykey)
8. [WebKit Blog — Full Third-Party Cookie Blocking and More (2020-03-24)](https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/)
9. [RFC 6750 — The OAuth 2.0 Authorization Framework: Bearer Token Usage](https://www.rfc-editor.org/rfc/rfc6750)
10. [OWASP Cheat Sheet Series — HTML5 Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/HTML5_Security_Cheat_Sheet.html)
11. [RFC 10017 (BCP 212, 2026-08) — OAuth 2.0 for Browser-Based Applications](https://www.rfc-editor.org/rfc/rfc10017)
12. [flutter/packages — webview_flutter_android 4.14.1, WebViewProxyApi.java](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/WebViewProxyApi.java)
13. [Android Developers — WebView – Native bridges](https://developer.android.com/privacy-and-security/risks/insecure-webview-native-bridges)
14. [Next.js Docs — Functions: cookies](https://nextjs.org/docs/app/api-reference/functions/cookies)
15. [Chromium — android_webview/browser/cookie_manager.cc](https://github.com/chromium/chromium/blob/a8941e727ba6a63551d09998c8a23486b94a55fe/android_webview/browser/cookie_manager.cc)
16. [Chromium — net/cookies/cookie_options.cc (MakeAllInclusive)](https://github.com/chromium/chromium/blob/8033912954e37739a7e27187a9f033dc20c85940/net/cookies/cookie_options.cc)
17. [RFC 9700 — Best Current Practice for OAuth 2.0 Security](https://www.rfc-editor.org/rfc/rfc9700)
18. [RFC 7009 — OAuth 2.0 Token Revocation](https://www.rfc-editor.org/rfc/rfc7009)
19. [OWASP Cheat Sheet Series — Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)
20. [OWASP MASTG — MASTG-TEST-0320: WebViews Not Cleaning Up Sensitive Data](https://github.com/OWASP/mastg/blob/master/tests-beta/android/MASVS-PLATFORM/MASTG-TEST-0320.md)
21. [Apple Developer Documentation — WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore)
22. [flutter/packages — webview_flutter_wkwebview 3.27.0, webkit_webview_controller.dart](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/lib/src/webkit_webview_controller.dart)
23. [Chromium — android_webview/browser/aw_browser_context.cc](https://github.com/chromium/chromium/blob/632f7b09695f6ec23a473a404b9ebfdbd2e7fa07/android_webview/browser/aw_browser_context.cc)
24. [Apple Developer Forums — iOS autodelete Keychain items after uninstall? (Apple DTS 답변)](https://developer.apple.com/forums/thread/36442)
25. [Next.js Docs — Guides: Authentication](https://nextjs.org/docs/app/guides/authentication)
26. [WebKit Blog — App-Bound Domains (2020-06-26)](https://webkit.org/blog/10882/app-bound-domains/)
27. [draft-ietf-httpbis-rfc6265bis-22 — Cookies: HTTP State Management Mechanism (RFC Editor 대기열)](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-rfc6265bis-22)
28. [W3C — Secure Contexts (Editor's Draft)](https://w3c.github.io/webappsec-secure-contexts/)
29. [flutter_secure_storage README](https://github.com/mogol/flutter_secure_storage/blob/develop/flutter_secure_storage/README.md)
30. [Chromium — android_webview AwCookieManager.java](https://github.com/chromium/chromium/blob/b1a4f4802448a816b169dcf03ef43cb8ec849d8e/android_webview/java/src/org/chromium/android_webview/AwCookieManager.java)
31. [flutter/packages — webview_flutter_android 4.14.1, android_webview_cookie_manager.dart](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/lib/src/android_webview_cookie_manager.dart)
32. [flutter/packages — webview_flutter_wkwebview 3.27.0, webkit_webview_cookie_manager.dart](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/lib/src/webkit_webview_cookie_manager.dart)
33. [flutter/flutter#152660 — webview_flutter: setCookie does not support maximumAge (열림)](https://github.com/flutter/flutter/issues/152660)
34. [flutter/packages — webview_flutter_android 4.14.1, CookieManagerProxyApi.java](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/CookieManagerProxyApi.java)
35. [flutter/packages — webview_flutter_wkwebview 3.27.0, HTTPCookieStoreProxyAPIDelegate.swift](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/darwin/webview_flutter_wkwebview/Sources/webview_flutter_wkwebview/HTTPCookieStoreProxyAPIDelegate.swift)
36. [flutter/packages — webview_flutter 4.14.1 CHANGELOG](https://github.com/flutter/packages/blob/webview_flutter-v4.14.1/packages/webview_flutter/webview_flutter/CHANGELOG.md)
37. [flutter/flutter#115460 — webview_flutter: Flutter 3 iOS WebView initialCookies are not being set (열림)](https://github.com/flutter/flutter/issues/115460)
38. [flutter/packages — webview_flutter_android 4.14.1, android_webview_controller.dart](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/lib/src/android_webview_controller.dart)
39. [Android Developers — WebView (API reference)](https://developer.android.com/reference/android/webkit/WebView)
40. [flutter/flutter#123179 — Flutter Webview 4.0.2 WebViewCookieManager.setCookie does not work for iOS apps (닫힘)](https://github.com/flutter/flutter/issues/123179)
41. [flutter_inappwebview v6.1.5 — Android MyCookieManager.java](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/MyCookieManager.java)
42. [pub.dev — flutter_inappwebview versions](https://pub.dev/packages/flutter_inappwebview/versions)
43. [RFC 8693 — OAuth 2.0 Token Exchange](https://www.rfc-editor.org/rfc/rfc8693)
44. [RFC 6749 — The OAuth 2.0 Authorization Framework](https://www.rfc-editor.org/rfc/rfc6749)
45. [flutter/packages — webview_flutter_platform_interface 2.15.1, javascript_message.dart](https://github.com/flutter/packages/blob/webview_flutter_platform_interface-v2.15.1/packages/webview_flutter/webview_flutter_platform_interface/lib/src/types/javascript_message.dart)
46. [flutter_inappwebview v6.1.5 — platform_web_message_listener.dart](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/web_message/platform_web_message_listener.dart)
47. [RFC 8252 (BCP 212) — OAuth 2.0 for Native Apps](https://www.rfc-editor.org/rfc/rfc8252)
48. [Apple Developer Documentation — ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
49. [Apple Developer Documentation — ASWebAuthenticationSession.Callback](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback)
50. [Chrome for Developers — Simplify authentication using Auth Tab](https://developer.chrome.com/docs/android/custom-tabs/guide-auth-tab)
51. [flutter_web_auth_2 README (5.x)](https://github.com/ThexXTURBOXx/flutter_web_auth_2/blob/master/flutter_web_auth_2/README.md)
52. [flutter_appauth README](https://github.com/MaikuB/flutter_appauth/blob/master/flutter_appauth/README.md)
53. [draft-ietf-oauth-first-party-apps-04 — OAuth 2.0 for First-Party Applications](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-first-party-apps-04)
54. [Next.js Docs — File-system conventions: proxy.js](https://nextjs.org/docs/app/api-reference/file-conventions/proxy)
55. [Next.js Docs — Guides: Data Security](https://nextjs.org/docs/app/guides/data-security)
56. [WebKit Blog — WebKit Features in Safari 18.4](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/)
57. [TanStack Query — QueryClient reference (React)](https://tanstack.com/query/latest/docs/framework/react/reference/classes/QueryClient)
58. [Android Developers — Behavior changes: Apps targeting Android 12 (Modern SameSite cookies in WebView)](https://developer.android.com/about/versions/12/behavior-changes-12)
59. [Chromium — WebViewChromiumFactoryProvider.java](https://github.com/chromium/chromium/blob/32f2910914147528cc05eba273ddd403dfe8d1e4/android_webview/glue/java/src/com/android/webview/chromium/WebViewChromiumFactoryProvider.java)
60. [이 저장소 — app/lib/config.dart (explore/real-world-example)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/explore/real-world-example/app/lib/config.dart)
61. [Apple Developer Documentation — HTTPCookie.cookies(withResponseHeaderFields:for:)](https://developer.apple.com/documentation/foundation/httpcookie/cookies(withresponseheaderfields:for:))
