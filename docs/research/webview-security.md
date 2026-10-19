# WebView Bridge 보안 지침 조사

- **질문**: [#36 WebView Bridge 보안 지침 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/36). WebView Bridge를 허용된 출처에서만 열고, 이동 가능한 URL을 제한하고, 들어온 Message를 검증하려면 무엇을 해야 하는가?
- **조사일**: 2026-10-19
- **확인한 버전**: OWASP MASVS v2.1.0 · MASWE v1.0.0 · MASTG v2.0.0 / Android 레퍼런스(WebView 2026-10-09, WebViewClient·WebSettings 2026-08-03 갱신본), androidx.webkit 1.17.1(안정판) / Apple WebKit 문서(2026-10-19 조회) / webview_flutter 4.14.1 · webview_flutter_android 4.14.1 · webview_flutter_wkwebview 3.27.0(flutter/packages `0259ad7`) / flutter_inappwebview 6.1.5(안정판)·6.2.0-beta.3 / W3C CSP Level 3 WD(2026-09-16) / Next.js CSP 가이드(2026-03-20 갱신)

## 요약

- 공식 지침의 뼈대는 세 가지다. Bridge는 신뢰하는 출처에만 최소 기능으로 노출하고 [1][2], WebView에서는 허용 목록의 출처만 열고 나머지는 시스템 브라우저로 보내며 [3][27], 들어온 Message는 구조·타입·값·권한·앱 상태까지 검증한다 [1][2].
- Android `addJavascriptInterface`는 iframe을 포함한 모든 프레임에 주입되고 호출한 프레임의 출처를 알 수 없다. 그래서 Android는 허용 출처 규칙과 `sourceOrigin`·`isMainFrame`을 주는 `addWebMessageListener`를 권장한다 [26][30][33]. iOS 핸들러도 모든 프레임에 정의되지만, `frameInfo`로 보낸 프레임의 출처를 확인할 수 있다 [12][41][42].
- Demo가 쓰는 webview_flutter 4.14.1은 Android에서 `addJavascriptInterface`를 쓰고, 두 플랫폼 모두 Dart에 문자열 본문만 넘긴다. 그래서 Host가 Message를 보낸 출처와 프레임을 확인할 수 없다 [51][52][53]. 출처를 검증하려면 플랫폼 코드(Kotlin·Swift)를 붙이거나, 출처 정보를 주는 패키지(flutter_inappwebview `WebMessageListener`)를 써야 한다 [57].
- 내비게이션 허용 목록은 URL을 파싱해 scheme과 host를 정확히 비교한다. 부분 비교는 금지다 [28]. webview_flutter의 `onNavigationRequest`는 Android에서 서브프레임을 막지 못하고, Host가 직접 연 URL과 POST에는 호출되지 않는다. 따라서 iframe 차단과 딥 링크·알림 URL 검증은 따로 해야 한다 [31][52].
- 허용 목록 밖의 http(s) 링크는 시스템 브라우저로 넘긴다 [27][58]. `intent:` URL을 그대로 실행하면 Intent-Scheme Hijacking 위험이 있고 [38], 커스텀 스킴은 다른 앱도 같은 이름으로 등록할 수 있다 [5].
- 플랫폼 기본값은 대체로 안전하다(Android 파일 접근 차단·혼합 콘텐츠 차단·Safe Browsing, iOS 웹 검사 꺼짐). 예외는 Android content 접근으로, 기본으로 켜져 있어 꺼야 한다 [18][32]. Demo의 `usesCleartextTraffic="true"`(Android main 매니페스트)와 iOS `NSAllowsLocalNetworking`은 릴리스 빌드까지 평문을 허용한다 [20][21][36]. WebView 디버깅은 디버그 빌드에서만 켠다 [6][30][47].
- CSP는 Web 쪽 방어선(`frame-src`, `script-src`)이지만 최상위 내비게이션은 제한하지 못해서 Host의 허용 목록을 대신하지 못한다 [59]. Next.js에서 nonce 기반 CSP를 쓰면 모든 페이지가 동적 렌더링된다 [60].
- WebView는 쿠키·localStorage·IndexedDB·HTTP 캐시를 기기에 남긴다 [8][49]. 서버는 `no-store`를 붙이고 로그아웃 때 삭제하는 것이 기본인데, Flutter 공용 API는 IndexedDB를 지우지 못한다 [52][53][61].
- Demo의 Call 응답과 Event는 page world의 전역 함수와 `CustomEvent`를 쓴다. 그래서 같은 페이지의 다른 스크립트가 응답을 가로채거나 Event를 위조할 수 있다 [14][62]. 기본선은 민감 데이터를 Bridge로 Web에 넘기지 않는 것이다 [2].

## 상세

### 1. 출처·프레임별 Bridge 노출 제한과 `addJavascriptInterface`

**위협 모델.** MASVS-PLATFORM-2는 WebView를 통한 민감 데이터 유출과, JavaScript bridge를 통한 민감 기능 노출을 막으라는 통제다 [1]. MASWE-0033은 이 약점이 생기는 경로로 다음 여섯 가지를 든다 [2].

- 신뢰하지 않는 출처·프레임에 열린 Bridge
- 검증하지 않는 Message
- `addJavascriptInterface` 같은 전역 노출 방식
- page world에 둔 Bridge 스크립트
- 다른 스크립트가 읽을 수 있는 응답
- 필요 이상으로 넓은 Bridge

MASTG는 Bridge가 있다는 것만으로 실패를 판정하지 않는다. 민감 기능·데이터에 신뢰하지 않는 콘텐츠가 닿을 때 실패로 본다 [13].

**Android.**

- `addJavascriptInterface`는 iframe을 포함한 모든 프레임에 객체를 주입하고, 앱 쪽에서는 호출한 프레임의 출처를 알 수 없다. 레퍼런스는 iframe까지 서드파티 콘텐츠가 들어오지 않는다고 보장할 수 없으면 호출자를 신뢰하지 말라고 한다 [30]. `getUrl()`로도 호출 프레임을 판단할 수 없다. Android는 아주 오래된 버전을 지원해야 하는 경우가 아니면 이 방식을 권장하지 않는다 [26].
- Android 위험 문서가 드는 완화책은 다음과 같다 [27][39].
  - 필요 없는 JavaScript는 끈다.
  - 신뢰하지 않는 콘텐츠를 열기 전에 `removeJavascriptInterface`를 호출한다.
  - HTTPS 콘텐츠만 로드한다.
  - scheme·host를 허용 목록으로 검증하고, 목록 밖은 기본 브라우저로 연다.
  - 민감 기능을 노출하지 않는다.
  - API 21 이상을 타깃으로 한다.
- `WebViewCompat.addWebMessageListener`는 Android의 비교표에서 보안 "Highest (Allowlist-based)", 권장 "Yes"로 표시된 방식이다. WebView 82와 Jetpack Webkit 1.3.0 이상이 필요하다 [26].
  - 규칙 형식은 `SCHEME://HOST[:PORT]`이고 경로는 보지 않는다. `https://*.example.com`은 서브도메인만 맞고 루트 도메인은 맞지 않는다. `*`는 모든 프레임에 객체를 주입한다. HTTP 출처를 허용하면 네트워크 공격자에게 객체가 노출된다 [26][33].
  - 객체는 규칙에 맞는 모든 프레임(같은 출처의 iframe 포함)에 주입된다. 콜백은 `sourceOrigin`·`isMainFrame`·`JavaScriptReplyProxy`를 받는다.
  - `loadUrl` 전에 등록해야 하고, `WEB_MESSAGE_LISTENER` 기능 지원 여부를 먼저 확인한다 [26][33].
- `postWebMessage`는 main frame에만 보내는, 출처를 인지하는 방식(보안 High)이다. 대상 출처에 `*`를 쓰지 않는다 [26][27].
- androidx.webkit 1.16.0(2026-05-06)부터는 `JavaScriptExecutionWorld`로 리스너를 격리된 world에 둘 수 있다 [33][35]. MASWE는 이 격리를 앱이 주입한 스크립트만 Bridge를 부를 때 쓰라고 한다. 격리는 출처에 대한 권한 부여가 아니므로 출처·프레임·Message 검증은 그대로 유지해야 한다 [2]. Web 코드가 직접 Bridge를 부르는 구조에는 해당하지 않는다(추론).

**iOS.**

- 핸들러는 지정한 content world의 모든 프레임에 `window.webkit.messageHandlers.<name>`을 정의한다. `add(_:name:)`는 `.page` world를 쓴다 [10][42]. WKWebView에는 출처 기반 접근 제어가 없으므로, 민감한 처리를 하는 핸들러는 `frameInfo.securityOrigin`을 확인하라고 MASTG가 권한다 [12][40]. `WKFrameInfo`는 `isMainFrame`·`request`·`securityOrigin`(protocol·host·port)을 제공한다 [41].
- `WKContentWorld`는 JavaScript 전역과 프로토타입을 world마다 분리하지만 DOM은 공유한다 [10][43]. Host가 주입한 DOM 읽기 스크립트를 page 스크립트로부터 보호하는 용도이고 [15], 페이지가 부르는 Bridge의 출처를 제한하는 수단은 아니다.
- App-Bound Domains(iOS 14 이상)는 다음과 같이 동작한다 [46].
  - Info.plist의 `WKAppBoundDomains`에 도메인을 최대 10개 적으면, 앱의 모든 WKWebView가 JavaScript 주입·쿠키 조작·메시지 핸들러 사용이 거부되는 모드가 된다.
  - `limitsNavigationsToAppBoundDomains`를 켠 WebView만 이 API를 다시 쓸 수 있다. 대신 그 WebView는 app-bound 도메인 밖으로 이동하면 실패한다.
  - 검사는 최상위 프레임에만 적용된다. 다른 도메인의 iframe은 계속 표시된다.

  webview_flutter_wkwebview는 이 플래그를 생성 파라미터로 노출한다 [53]. 근거는 2020년 WebKit 블로그다.

**Flutter 계층.**

- webview_flutter의 `JavaScriptMessage`에는 문자열 `message`만 있다 [51].
  - Android 구현은 채널을 `addJavascriptInterface`로 등록한다 [52].
  - iOS 구현은 `.page` world 핸들러와, 모든 프레임에 적용되는 user script(`isForMainFrameOnly: false`)를 쓴다. Dart 쪽 `WKScriptMessage`에는 `name`·`body`만 있어서 `frameInfo`가 전달되지 않는다 [53].
  - `addJavaScriptChannel` 문서에는 프레임이나 출처에 대한 언급이 없다 [54].
- 두 플랫폼 구현은 다른 플러그인이 내부 WebView를 얻을 수 있는 외부 API를 제공한다(`webViewIdentifier`, Android `WebViewFlutterAndroidExternalApi`, iOS `FWFWebViewFlutterWKWebViewExternalAPI`). Android 외부 API는 Dart API와 같은 호환성 규칙을 따른다고 명시되어 있다 [52][53]. iOS 조회 메서드는 2026-10 현재 새 시그니처로 교체되는 중이다 [55].
- flutter_inappwebview `WebMessageListener`는 `allowedOriginRules`를 받고 Dart에 `sourceOrigin`·`isMainFrame`을 넘긴다.
  - 6.1.5 기준 Android는 `addWebMessageListener`를 그대로 쓴다. 기기가 기능을 지원하지 않으면 등록을 건너뛴다.
  - iOS는 주입 스크립트가 `window.location`을 검사하고, 플랫폼 코드가 `frameInfo.securityOrigin`으로 한 번 더 확인한다 [57].
  - 기본 Bridge(`callHandler`)는 Android에서 여전히 `addJavascriptInterface`를 쓴다. 이를 출처·main frame으로 좁히는 설정은 6.2.0 베타에만 있다. 마지막 안정판은 6.1.5(2024-10-08)다 [56][57].

### 2. 내비게이션 허용 목록, 외부 링크, 커스텀 스킴·intent URL

**원칙.** WebView에서는 허용 목록의 출처만 열고 나머지는 시스템 브라우저로 보낸다. 인텐트나 딥 링크로 받은 URL도 검증한다 [3]. iOS에 대해서도 같은 지침이 있다. URL을 파싱해 scheme·host·path를 엄격한 허용 목록과 비교하고, 딥 링크 파라미터를 그대로 `load(_:)`에 넘기지 않는다 [17]. 신뢰하는 도메인 안이라도 다른 사용자가 올린 링크는 신뢰할 수 없다 [8].

**비교 방법.** 문자열을 URI로 파싱한 뒤 scheme과 host를 모두 검증하고, host는 전체가 일치해야 한다 [28].

- host만 보고 scheme을 보지 않으면 `javascript:`·`content://` 같은 scheme으로 우회된다.
- `startsWith`·`endsWith`·`contains`는 악성 호스트를 통과시킬 수 있다. `endsWith`를 써야 한다면 도메인 앞의 `.`까지 포함해 비교한다.
- 정규식 매칭도 권하지 않는다.

**가로채기 지점과 한계.**

- Android `shouldOverrideUrlLoading`은 페이지나 사용자, HTTP 리다이렉트가 시작한 내비게이션에 호출된다. 앱이 `loadUrl()`로 시작한 내비게이션과 POST에는 호출되지 않고, 서브프레임과 비 HTTP(S) 스킴에도 호출될 수 있다 [31]. MASTG는 XHR·iframe·`src`·`<script>`는 이 콜백으로 잡히지 않는다고 적는다. 리소스 요청은 `shouldInterceptRequest`가 받는다(단 `javascript:`·`blob:`·`file:///android_asset/` 제외) [16][31].
- webview_flutter_android는 main frame만 Dart `onNavigationRequest`로 넘긴다 [52].
  - 서브프레임은 `loadUrl`로 다시 열 수 없다는 이유로 항상 허용한다(`return request.isForMainFrame() && ...`).
  - 승인된 main frame 내비게이션은 원래 로드를 취소한 뒤 `loadUrl`로 다시 연다.
  - `window.open`·`target="_blank"`도 같은 판단을 거쳐 같은 WebView에서 열린다.
  - 공용 API에는 `shouldInterceptRequest`가 없다.
- webview_flutter_wkwebview는 `decidePolicyForNavigationAction`을 Dart로 넘기고, `isMainFrame`을 `targetFrame`에서 구한다. 새 창 요청은 `targetFrame`이 `nil`이라 `false`로 오고, 같은 WebView에서 열린다 [45][53]. 두 플랫폼의 이런 차이는 2019년부터 열린 이슈로 남아 있다 [55].
- 위 사실을 합치면(추론), 허용 목록 검사는 세 곳에 필요하다.
  - 내비게이션 콜백
  - Host의 `loadRequest` 직전(초기 URL, 딥 링크·알림으로 받은 URL)
  - Web의 CSP `frame-src`

**외부 링크.** Android는 허용 목록 밖 도메인을 기본 브라우저로 열라고 한다 [27]. url_launcher에서는 네 가지 모드를 고를 수 있다 [58].

- `externalApplication`: OS가 다른 앱으로 처리한다.
- `externalNonBrowserApplication`: 브라우저가 아닌 앱만 쓴다.
- `inAppBrowserView`: Custom Tabs·SFSafariViewController로 연다.
- `inAppWebView`: 앱 안의 WebView로 연다.

MASTG는 외부 콘텐츠를 보여주기만 한다면 Custom Tabs가 렌더링을 앱 WebView 밖으로 옮겨 위험을 줄인다고 정리한다. Android가 로그인에 Custom Tabs를 권하는 이유도 호스트 앱이 그 내용을 볼 수 없기 때문이라고 적는다 [18].

**비 HTTP(S) 스킴과 `intent:`.**

- WebViewClient가 설정된 Android WebView에서는 비 HTTP(S) URL도 `shouldOverrideUrlLoading`으로 오고, 그 URL은 `loadUrl`로 열 수 없다 [31]. 차단할지 외부 앱으로 넘길지는 Host가 정해야 한다.
- 신뢰하지 않는 콘텐츠를 여는 WebView가 `intent://` URL을 `Intent.parseUri`로 파싱해 `startActivity`로 실행하면 Intent-Scheme Hijacking에 취약하다. 앱의 비공개 컴포넌트로 임의의 인텐트가 보내질 수 있다. Google이 제시하는 해결책은 두 가지다 [38].
  - `addCategory(BROWSABLE)`, `setComponent(null)`, `setSelector(null)`을 적용한 뒤 실행한다.
  - HTTP를 막아 신뢰하지 않는 콘텐츠를 아예 로드하지 않는다.
- 커스텀 스킴은 다른 앱도 등록할 수 있어서 민감한 흐름에 쓰면 안 된다 [5]. `canLaunchUrl`을 쓰려면 iOS `LSApplicationQueriesSchemes`와 Android `<queries>`에 해당 스킴을 선언해야 한다 [58].

### 3. 들어온 Message의 스키마 검증과 권한이 필요한 Host 기능 호출 제한

**근거.** MASVS-CODE-4는 IPC를 포함한 모든 입력을 검증·정제하라고 한다 [1]. MASWE-0033은 Message의 이름·인자·페이로드를 검증하지 않는 것을 약점으로 든다. 검증 대상에는 구조·타입·값뿐 아니라 권한과 앱 상태도 포함된다 [2]. MASTG의 Bridge 설계 지침은 다음과 같다.

- 필요한 동작만 노출하고, 범용 디스패처는 피한다 [11].
- 정해진 형식만 받고, 예상하지 못한 입력과 동작은 거부한다 [11].
- 콜백에서 보낸 쪽 정보를 확인한 뒤 처리한다 [11].
- 핸들러는 좁은 목적으로 만들고, 필요 없어지면 제거한다. 민감한 동작이면 출처를 확인한다 [12].
- 허용 출처에 와일드카드를 쓰면 받은 Message를 신뢰하지 않는다 [33].

**응답 경로.** iOS 핸들러가 `evaluateJavaScript`로 `window.receiveData(...)` 같은 전역 콜백을 부르면, 페이지의 다른 스크립트가 그 함수를 덮어써서 응답을 가로챌 수 있다. MASTG-TEST-0377은 이 응답에 민감 데이터가 담기면 실패로 본다. 대안으로는 호출한 world의 Promise로 응답을 바로 돌려주는 `WKScriptMessageHandlerWithReply`를 든다 [14][44]. Android의 `JavaScriptReplyProxy`도 메시지를 보낸 프레임의 객체로만 응답한다 [34]. Demo의 Call 응답이 바로 MASTG가 지적하는 형태다. `runJavaScript`로 `window.__onFlutterResponse(...)`를 호출한다(`app/lib/bridge/stage_c_bridge.dart`).

**Event의 위조 가능성.** `dispatchEvent()`로 만든 이벤트는 `isTrusted`가 항상 `false`다 [62]. 그래서 Host가 `runJavaScript`로 보낸 `CustomEvent`와 다른 스크립트가 만든 같은 이름의 이벤트를 Web이 구분할 수 없다. Event를 권한 판단의 근거로 쓰면 안 되고, 멤버 전용 글 같은 권한은 서버가 다시 확인해야 한다(추론).

**Reference App에 옮기면(추론).**

- Host가 Call 봉투(`id`, `method`, `params`)와 method별 `params` 스키마를 검증하고, 모르는 method는 거부한다.
- method마다 허용 출처, main frame 전용 여부, 로그인 필요 여부 같은 전제 조건을 검사한다.
- 응답과 Event에는 Web 화면에 꼭 필요한 값만 담는다. 사진 선택 결과나 세션 정보 같은 Host 기능의 결과가 여기에 해당한다.

### 4. 파일 접근, 혼합 콘텐츠, 평문 통신, 릴리스 빌드 디버깅, CSP

**파일·content 접근.**

- Android `setAllowFileAccess`는 targetSdk 30 이상에서 기본 `false`다. 레퍼런스는 외부에서 받은 `file://` URL을 열지 말고, `WebViewAssetLoader`로 http(s)를 통해 파일을 제공하라고 한다. file URL 교차 접근 설정 두 개는 API 30에서 deprecated되었고 기본값은 `false`다 [32].
- `setAllowContentAccess`는 기본으로 켜져 있다 [32]. 필요 없으면 끄라고 MASTG와 Android 문서가 권한다 [18][29]. 이런 설정을 켠 채 신뢰하지 않는 콘텐츠를 여는 것이 MASWE-0034의 약점이다 [4].
- webview_flutter_android의 `loadFile()`은 내부에서 `setAllowFileAccess(true)`를 켠다 [52].
- iOS에서는 `loadFileURL(_:allowingReadAccessTo:)`의 읽기 범위를 최소로 두고, 비공개 file URL 설정을 KVC로 켜지 않는다 [9][19].
- Reference App은 원격 Web만 열므로 로컬 파일을 로드할 필요가 없다.

**혼합 콘텐츠.** Android는 LOLLIPOP 이상을 타깃으로 하면 `MIXED_CONTENT_NEVER_ALLOW`가 기본이고, `ALWAYS_ALLOW`는 강하게 비권장한다 [32]. iOS WebKit은 ATS를 완화해도 능동 혼합 콘텐츠를 차단한다 [9].

**평문 통신.**

- **Android**:
  - API 28 이상 타깃의 기본 NSC는 평문을 막는다 [36].
  - `usesCleartextTraffic`은 API 24 이상에서 NSC가 있으면 무시된다. WebView는 API 26 이상 타깃에서 이 속성을 따른다. 이 속성은 API 38 이상 타깃부터 무시될 예정이라 NSC로 제어하라고 한다 [37].
  - `<debug-overrides>`는 debuggable 빌드에서 신뢰 앵커를 추가하는 용도로 설명된다 [36].
  - MASTG는 NSC 없이 `usesCleartextTraffic="true"`이거나, NSC가 평문을 허용하면 실패로 본다 [20].
- **iOS**:
  - ATS는 HTTPS를 요구한다 [48].
  - `NSAllowsArbitraryLoadsInWebContent`는 WKWebView를 ATS에서 통째로 면제하며, App Store 심사 때 사유가 필요하다 [48].
  - `NSAllowsLocalNetworking`은 비정규 도메인·`.local`·IP 주소로의 연결을 허용한다. iOS 17부터 IP 주소 연결은 기본 차단이다 [48].
  - MASTG는 두 키를 모두 평문 허용으로 판정하되, 정당한 사유가 있는지 추가로 확인하라고 한다 [21].
- **Demo 현황**: Android main 매니페스트에 `usesCleartextTraffic="true"`, iOS에 `NSAllowsLocalNetworking=true`가 들어 있다(`app/` 기준). 개발용 예외가 릴리스 빌드에도 그대로 들어간다.

**TLS 오류.** Android `onReceivedSslError`에서는 항상 `cancel()`을 호출한다. `proceed()`를 호출하거나 사용자에게 묻지 않는다 [22][31]. iOS는 서버 신뢰 평가를 직접 구현하지 않는 것이 가장 안전하다 [22]. webview_flutter는 `onSslAuthError`를 등록하지 않으면 Android에서는 취소하고 iOS에서는 기본 처리를 한다. 등록하면 진행 여부를 Host 코드가 정하게 된다 [52][53].

**릴리스 빌드 디버깅.**

- Android `setWebContentsDebuggingEnabled`는 WebView 113.0.5656.0 이상에서 debuggable 앱에 자동으로 켜지고, 그 밖에는 기본 `false`다. 레퍼런스는 운영 빌드에서 켜는 것을 보안상 부채라고 적는다 [30]. MASTG는 `FLAG_DEBUGGABLE`을 확인하지 않고 켜면 실패로 본다 [23].
- iOS `isInspectable`은 기본 `false`다(iOS 16.4 이상). 16.4 이전 SDK로 링크하면 디버그 빌드는 항상 검사할 수 있다 [47].
- MASWE-0063은 두 설정을 모두 릴리스 빌드에서 끄라고 한다 [6]. Flutter에서는 `enableDebugging`과 `setInspectable`로 제어한다 [52][53].

**악성 사이트 경고.** Android Safe Browsing은 기본으로 켜져 있고, 코드 설정이 매니페스트 설정보다 우선한다. MASTG는 어느 쪽에서든 끄면 실패로 본다 [24][32]. iOS `isFraudulentWebsiteWarningEnabled`도 기본값이 `true`다 [50].

**CSP.**

- CSP3(WD 2026-09-16)의 `frame-src`는 iframe 등에 로드할 수 있는 URL을 제한한다. 이 지시어가 없으면 `child-src`, 그다음 `default-src`를 따른다 [59].
- 내비게이션 관련 지시어는 `form-action`과 `frame-ancestors`뿐이라서 최상위 문서의 이동은 막지 못한다. `<meta>`로 전달한 CSP는 `frame-ancestors`·`report-uri`·`sandbox`를 지원하지 않는다 [59].
- Next.js의 `proxy.ts` nonce CSP를 쓰면 모든 페이지가 동적 렌더링된다. 정적 최적화·ISR·CDN 캐시를 포기해야 하고, PPR과 함께 쓸 수 없다 [60].
- 대안은 `next.config`의 정적 헤더(`'unsafe-inline'` 포함)나 실험적 SRI다. 개발 모드에서는 `'unsafe-eval'`이 필요하다 [60].
- CSP는 Web 서버가 보내는 것이라서 Host가 강제할 수 없다. MASTG도 Bridge 설계만으로는 신뢰한 페이지에서 공격자 JavaScript가 실행되는 것 자체를 막지 못한다고 적는다 [11]. CSP는 그런 실행을 줄이는 Web 쪽 방어선이다.

### 5. WebView에 남는 민감 정보

- **Android의 저장 위치**: WebView는 `app_webview` 아래 Chromium 프로필에 HTTP 캐시, localStorage·sessionStorage, IndexedDB, 쿠키, OPFS를 남긴다. DOM storage와 네트워크 캐시는 기본으로 켜져 있다 [8]. webview_flutter_android도 DOM storage를 켠다 [52].
- **Android의 삭제 API와 한계** [8][30]:
  - `clearCache(true)`는 앱의 모든 WebView 캐시를 지우지만 쿠키·DOM storage·IndexedDB는 남긴다.
  - `WebStorage.deleteAllData()`는 DOM storage와 WebSQL만 지운다.
  - `removeAllCookies()`는 쿠키를 지운다.
  - IndexedDB·OPFS를 지우려면 프로필 전체를 지워야 하는데 그런 API는 없다. 앱 데이터 전체를 지우는 `clearApplicationUserData()`뿐이고, 디렉터리를 직접 지워서는 안 된다.
- **정리 시점**: 프로세스가 갑자기 종료되면 정리 코드가 실행되지 않을 수 있으니, 다음 실행 때 정리하는 것도 고려하라고 한다. MASTG-TEST-0320은 앱을 닫은 뒤 민감 데이터가 남아 있으면 실패로 본다 [25].
- **iOS**: 기본 `WKWebsiteDataStore`는 디스크에 영속 저장하고, `nonPersistent()`는 메모리에만 둔다. `removeData(ofTypes:...)`로 종류별로 지울 수 있다 [49].
- **Flutter 공용 API**:
  - Android의 `clearCache`·`clearLocalStorage`·`clearCookies`는 각각 `clearCache(true)`·`deleteAllData()`·`removeAllCookies()`를 호출한다 [52].
  - iOS는 캐시(메모리·디스크·오프라인), localStorage, 쿠키만 지운다 [53].
  - 공용 API로는 IndexedDB를 지울 수 없다(iOS 래퍼에는 `indexedDBDatabases` 종류가 있다). iOS에서는 비영속 저장소를 고를 수도 없다 [53].
- **서버 쪽**: MASTG는 민감한 응답에 `Cache-Control: no-cache`를 권한다 [25]. 하지만 RFC 9111에서 `no-cache`는 저장을 허용하고 재사용 전 검증만 요구한다. 저장 자체를 막는 것은 `no-store`다. 다만 RFC는 `no-store`도 확실한 프라이버시 수단은 아니라고 명시한다 [61].
- **약점 분류**: MASWE-0001은 캐시나 WebView 상태에 데이터를 필요 이상 남기는 것을 약점으로 본다 [7]. Android 위험 문서는 Bridge를 쓰기 전에 `clearCache`로 로컬 파일을 지우라고까지 적는다 [27].

## Reference App에 주는 시사점

### 지침 체크리스트

어느 선택지를 고르든 공통으로 적용되는 기본선이다. Flutter 계층 열은 webview_flutter 4.14.1을 기준으로 했다.

| 통제 | iOS | Android | Flutter 계층 |
|---|---|---|---|
| Bridge 노출 범위 | 핸들러가 모든 프레임에 정의됨 → `frameInfo` 확인 [12][41] | `addWebMessageListener` + HTTPS 출처만 허용 [26][33] | 공용 API에 출처 정보 없음 → 플랫폼 코드나 다른 패키지 필요 [51][52][53] |
| 내비게이션 허용 목록 | `decidePolicyFor`에서 scheme·host 정확히 비교 [17] | `shouldOverrideUrlLoading`(POST·`loadUrl`은 거치지 않음) [28][31] | `onNavigationRequest`에 더해 `loadRequest` 직전에도 검증 [52] |
| iframe·서드파티 | App-Bound Domains도 iframe은 막지 않음 [46] | 콜백으로 iframe을 모두 잡지는 못함 [16] | Web CSP `frame-src`·`script-src`가 실질적인 차단선 [59][60] |
| 외부 링크·스킴 | 허용 목록 밖은 시스템 브라우저로 [3] | `intent:`는 차단하거나 정제 후 실행 [38] | url_launcher `externalApplication` [58] |
| Message 검증 | 본문 타입·구조 확인 [12] | 범용 디스패처 금지, 형식 고정 [11] | Host에서 봉투·method별 스키마·전제 조건 검증 [2] |
| 응답 경로 | `WKScriptMessageHandlerWithReply` [44] | `JavaScriptReplyProxy` [34] | `runJavaScript`뿐 → 민감 데이터는 넘기지 않음 [14] |
| 파일·content 접근 | `allowingReadAccessTo` 최소화 [19] | `allowContentAccess(false)`, 파일 접근은 기본값 유지 [18][32] | `loadFile()` 쓰지 않음 [52] |
| 평문 통신 | 로컬 네트워킹 예외는 릴리스에서 제외 검토 [21][48] | NSC로 차단, 예외는 디버그 빌드만 [20][36] | 플랫폼 설정 파일에서 처리 |
| TLS 오류 | 신뢰 평가를 직접 구현하지 않음 [22] | `cancel()`만 [31] | `onSslAuthError`에서 진행시키지 않음 [52][53] |
| 디버깅 | `isInspectable`은 디버그 빌드에서만 [47] | 디버깅 활성화는 디버그 빌드에서만 [23][30] | `setInspectable`·`enableDebugging`은 디버그 빌드에서만 |
| 저장 데이터 | 로그아웃 때 `removeData` [49] | 로그아웃 때 캐시·저장소·쿠키 삭제 [8] | 공용 API는 IndexedDB 제외, 서버는 `no-store` [52][53][61] |

혼합 콘텐츠와 악성 사이트 경고는 두 플랫폼 모두 기본값을 유지하면 된다 [9][24][32][50].

### 「보안 모델 결정」이 고를 선택지

1. **Bridge 출처 검증을 어디서 할 것인가.** 가장 큰 갈림길이다.
   - **A. 콘텐츠 통제만 한다.** webview_flutter를 그대로 쓰고 Bridge는 모든 프레임에 열어 둔다. 대신 "WebView에는 Reference App의 Web만 들어오고 iframe·서드파티 스크립트는 없다"는 것을 허용 목록과 CSP로 보장한다.
     - 장점: 플랫폼 코드가 필요 없고 Demo 구조를 그대로 잇는다.
     - 단점: XSS가 한 번 나거나 허용한 서드파티 스크립트가 하나만 있어도 Bridge 전체가 열린다. Android에서는 Host가 iframe을 막을 수 없어 CSP에 기대야 한다. MASTG 기준을 통과하려면 "신뢰하지 않는 콘텐츠는 들어올 수 없다"를 계속 입증해야 한다 [13].
   - **B. webview_flutter에 플랫폼 코드를 붙인다.** 외부 API로 얻은 WebView에 Android는 `addWebMessageListener`를, iOS는 `frameInfo`를 검사하는 자체 핸들러를 단다.
     - 장점: 공식 권장 방식이고, Host가 출처와 main frame 여부를 보고 Message를 거부할 수 있다.
     - 단점: Kotlin·Swift 코드와 테스트가 생긴다. `addJavaScriptChannel`과 Bridge 경로가 둘로 나뉜다. 패키지 쪽 외부 API 변경도 따라가야 한다 [52][53][55].
   - **C. 출처 정보를 주는 패키지를 쓴다**(flutter_inappwebview `WebMessageListener`).
     - 장점: 두 플랫폼에서 `sourceOrigin`·`isMainFrame`을 Dart로 받을 수 있다.
     - 단점: 2024-10 이후 안정판이 나오지 않았다. 기본 `callHandler` Bridge는 Android에서 여전히 모든 프레임에 노출된다 [56][57]. WebView 패키지 결정과 함께 정해야 한다.
   - 셋 중 무엇을 고르든 iOS App-Bound Domains를 더할 수 있다. WebKit이 최상위 이동을 직접 막아 준다. 하지만 도메인은 최대 10개이고, iframe은 막지 않으며, 키를 넣으면 앱의 모든 WKWebView가 제한 모드가 된다 [46].
2. **응답·Event 경로.** 두 가지 중 하나를 고른다 [14][34][62].
   - 지금처럼 page world 전역 함수와 `CustomEvent`를 쓰되, "민감 데이터는 Bridge로 Web에 보내지 않는다, Event로 권한을 판단하지 않는다"를 규칙으로 둔다.
   - B나 C를 고를 경우, 플랫폼 응답 채널로 바꾼다.
3. **허용 목록의 형태.** 정확한 출처(scheme+host+port) 목록을 개발·스테이징·운영 환경별(에뮬레이터 주소 포함)로 둘지, 와일드카드 서브도메인을 허용할지 정한다. 와일드카드 규칙은 플랫폼마다 다르다 [26][28].
4. **허용 목록 밖 링크와 스킴.**
   - http(s): `externalApplication`으로 넘길지, `inAppBrowserView`(앱 안의 브라우저 탭으로, Host가 내용을 볼 수 없음)로 열지 [18][58].
   - 비 HTTP(S) 스킴: `tel:`·`mailto:`처럼 최소한만 허용하고 나머지를 차단할지.
   - `intent:`: 차단할지, Google 방식으로 정제해 실행할지 [38].
5. **빌드별 설정 분리.** 평문 예외를 어떻게 둘지 정한다 [20][21][36].
   - Demo처럼 고정해 둔다.
   - 디버그 빌드에만 둔다.
   - 개발 서버도 HTTPS로 띄운다.

   WebView 디버깅은 어느 경우든 디버그 빌드로 한정한다 [6].
6. **CSP 수준.** Web 배포 방식 결정과 연결된다. 세 가지 중 하나를 고른다 [59][60].
   - nonce 기반 strict CSP: 가장 엄격하지만 모든 페이지가 동적 렌더링된다.
   - `next.config` 정적 헤더: 정적 최적화를 유지하지만 `'unsafe-inline'`이 필요하다.
   - 실험적 SRI.

   `frame-src`로 iframe 출처를 좁히는 것은 어느 방식에서든 할 수 있다.
7. **WebView 저장 데이터.** 로그아웃·세션 만료 때 무엇을 지울지(IndexedDB 포함 여부), 민감한 API 응답에 `no-store`를 붙일지 정한다 [8][53][61]. iOS 비영속 저장소는 webview_flutter 공용 API로는 고를 수 없다. 또 앱을 다시 켜면 세션과 Web 상태가 사라지므로 S5의 상태 유지와 충돌할 수 있다(추론) [49][53].

## 확인하지 못한 것과 새로 생긴 질문

**확인하지 못한 것**

- **Android iframe 초기 로드**: iframe 초기 로드가 `shouldOverrideUrlLoading`을 거치는지 문서가 엇갈린다. 레퍼런스는 "서브프레임에도 호출될 수 있다", MASTG는 "iframe에는 호출되지 않는다"고 적는다 [16][31]. webview_flutter_android는 어느 쪽이든 서브프레임을 막지 않으므로 결론은 같다. 플랫폼 코드로 직접 막으려면 실측이 필요하다.
- **iOS iframe 초기 로드**: iframe 초기 로드가 `decidePolicyFor`를 거치는지 Apple 문서로 확인하지 못했다. 서브프레임 여부가 Dart로 전달된다는 것만 코드로 확인했다 [53].
- **App-Bound Domains**: Apple 레퍼런스(`WKAppBoundDomains` 키 문서)를 찾지 못해 2020년 WebKit 블로그에 기댔다. app-bound 페이지 안의 다른 도메인 iframe이 메시지 핸들러를 쓸 수 있는지, 개발용 `localhost`·IP를 등록할 수 있는지는 확인하지 못했다 [46].
- **선택지 B의 공존 여부**: 외부 API로 얻은 WebView에 `addWebMessageListener`나 별도 핸들러를 붙였을 때 webview_flutter와 충돌하지 않는지 코드로 검증하지 않았다.
- **빌드별 설정 방법**: Flutter 프로젝트에서 Android 디버그 전용 NSC와 iOS 빌드 구성별 ATS 키를 두는 구체적인 방법은 공식 문서로 확인하지 않았다.
- **심사 영향**: `NSAllowsLocalNetworking`을 릴리스에 남겼을 때 심사에 영향이 있는지 확인하지 못했다. Apple은 `NSAllowsArbitraryLoadsInWebContent`에만 심사 사유가 필요하다고 명시한다 [48].

**새로 생긴 질문**

1. Web 화면에 서드파티 콘텐츠(외부 동영상 임베드, 분석 스크립트 등)를 허용할 것인가? 허용한다면 출처 검증(선택지 B·C)과 CSP 예외가 사실상 필수가 된다.
2. 게시글·댓글 같은 사용자 생성 콘텐츠를 어떤 형식(일반 텍스트, 제한된 마크업, HTML)으로 렌더링할 것인가? XSS는 곧 Bridge 노출로 이어진다 [2][3].
3. 환경별 허용 출처 목록(개발·스테이징·운영, 에뮬레이터 주소)을 어디에 정의하고, Host와 Web이 어떻게 공유할 것인가? (⑥ Web 배포 방식과 환경 분리)
4. 로그아웃·세션 만료 때 WebView 저장소를 어디까지 지울 것인가? S5의 Web 상태 유지와는 어떻게 양립시킬 것인가? (③ 인증 세션)
5. Bridge 계약에 method별 권한(허용 출처, main frame 전용, 로그인 필요)을 표현하고, 생성된 검증기로 강제할 것인가? (① Bridge 계약)

## 출처

**OWASP**

1. OWASP MASVS v2.1.0, Controls(MASVS-PLATFORM-1·2, MASVS-CODE-4, MASVS-NETWORK-1, MASVS-STORAGE-2, MASVS-RESILIENCE-4). https://github.com/OWASP/masvs/tree/v2.1.0/controls
2. OWASP MASWE v1.0.0, MASWE-0033 Sensitive Native Functionality Exposed in WebViews. https://github.com/OWASP/maswe/blob/v1.0.0/weaknesses/MASVS-PLATFORM/MASWE-0033.md
3. OWASP MASWE v1.0.0, MASWE-0035 WebViews Loading Untrusted Content. https://github.com/OWASP/maswe/blob/v1.0.0/weaknesses/MASVS-PLATFORM/MASWE-0035.md
4. OWASP MASWE v1.0.0, MASWE-0034 WebViews Allow Access to Local Resources with Untrusted Content. https://github.com/OWASP/maswe/blob/v1.0.0/weaknesses/MASVS-PLATFORM/MASWE-0034.md
5. OWASP MASWE v1.0.0, MASWE-0029 Insecure Deep Links. https://github.com/OWASP/maswe/blob/v1.0.0/weaknesses/MASVS-PLATFORM/MASWE-0029.md
6. OWASP MASWE v1.0.0, MASWE-0063 Debug Mechanisms Not Disabled. https://github.com/OWASP/maswe/blob/v1.0.0/weaknesses/MASVS-RESILIENCE/MASWE-0063.md
7. OWASP MASWE v1.0.0, MASWE-0001 Sensitive Data Stored Unencrypted in Private Storage. https://github.com/OWASP/maswe/blob/v1.0.0/weaknesses/MASVS-STORAGE/MASWE-0001.md
8. OWASP MASTG v2.0.0, MASTG-KNOW-0018 WebViews (Android). https://github.com/OWASP/mastg/blob/v2.0.0/knowledge/android/MASVS-PLATFORM/MASTG-KNOW-0018.md
9. OWASP MASTG v2.0.0, MASTG-KNOW-0076 WebViews (iOS). https://github.com/OWASP/mastg/blob/v2.0.0/knowledge/ios/MASVS-PLATFORM/MASTG-KNOW-0076.md
10. OWASP MASTG v2.0.0, MASTG-KNOW-0139 WKContentWorld. https://github.com/OWASP/mastg/blob/v2.0.0/knowledge/ios/MASVS-PLATFORM/MASTG-KNOW-0139.md
11. OWASP MASTG v2.0.0, MASTG-BEST-0035 Prefer Origin Scoped Messaging Over Legacy JavaScript Bridges. https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0035.md
12. OWASP MASTG v2.0.0, MASTG-BEST-0058 Restrict Native Functionality Exposed Through WebView Bridges. https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0058.md
13. OWASP MASTG v2.0.0, MASTG-TEST-0334 Native Code Exposed Through WebViews (Android) · MASTG-TEST-0376 References to Native Bridge APIs in WebViews (iOS). https://github.com/OWASP/mastg/blob/v2.0.0/tests-beta/android/MASVS-PLATFORM/MASTG-TEST-0334.md · https://github.com/OWASP/mastg/blob/v2.0.0/tests-beta/ios/MASVS-PLATFORM/MASTG-TEST-0376.md
14. OWASP MASTG v2.0.0, MASTG-TEST-0377 References to `evaluateJavaScript` Used as Bridge Reply · MASTG-BEST-0062 Use WKScriptMessageHandlerWithReply to Return Data to JavaScript. https://github.com/OWASP/mastg/blob/v2.0.0/tests-beta/ios/MASVS-PLATFORM/MASTG-TEST-0377.md · https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0062.md
15. OWASP MASTG v2.0.0, MASTG-BEST-0061 Use WKContentWorld Isolation for DOM Inspection Scripts. https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0061.md
16. OWASP MASTG v2.0.0, MASTG-TEST-0398 References to WebViewClient URL Loading Handlers. https://github.com/OWASP/mastg/blob/v2.0.0/tests-beta/android/MASVS-CODE/MASTG-TEST-0398.md
17. OWASP MASTG v2.0.0, MASTG-BEST-0034 Validate WebView Input. https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0034.md
18. OWASP MASTG v2.0.0, MASTG-BEST-0011 Securely Load File Content in a WebView · MASTG-BEST-0012 Disable JavaScript in WebViews · MASTG-BEST-0013 Disable Content Provider Access in WebViews. https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0011.md · https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0012.md · https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0013.md
19. OWASP MASTG v2.0.0, MASTG-BEST-0033 Securely Load File Content in a WebView (iOS). https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0033.md
20. OWASP MASTG v2.0.0, MASTG-TEST-0235 Android App Configurations Allowing Cleartext Traffic. https://github.com/OWASP/mastg/blob/v2.0.0/tests-beta/android/MASVS-NETWORK/MASTG-TEST-0235.md
21. OWASP MASTG v2.0.0, MASTG-TEST-0322 App Transport Security Configurations Allowing Cleartext Traffic. https://github.com/OWASP/mastg/blob/v2.0.0/tests-beta/ios/MASVS-NETWORK/MASTG-TEST-0322.md
22. OWASP MASTG v2.0.0, MASTG-TEST-0284 Incorrect SSL Error Handling in WebViews · MASTG-BEST-0073 Properly Validate Server Trust in URLSessionDelegate and WKNavigationDelegate. https://github.com/OWASP/mastg/blob/v2.0.0/tests-beta/android/MASVS-NETWORK/MASTG-TEST-0284.md · https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0073.md
23. OWASP MASTG v2.0.0, MASTG-TEST-0227 Debugging Enabled for WebViews · MASTG-BEST-0008 Debugging Disabled for WebViews. https://github.com/OWASP/mastg/blob/v2.0.0/tests-beta/android/MASVS-RESILIENCE/MASTG-TEST-0227.md · https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0008.md
24. OWASP MASTG v2.0.0, MASTG-TEST-0399 SafeBrowsing Disabled. https://github.com/OWASP/mastg/blob/v2.0.0/tests-beta/android/MASVS-CODE/MASTG-TEST-0399.md
25. OWASP MASTG v2.0.0, MASTG-BEST-0028 WebViews Cache Cleanup · MASTG-TEST-0320 WebViews Not Cleaning Up Sensitive Data. https://github.com/OWASP/mastg/blob/v2.0.0/best-practices/MASTG-BEST-0028.md · https://github.com/OWASP/mastg/blob/v2.0.0/tests-beta/android/MASVS-PLATFORM/MASTG-TEST-0320.md

**Android**

26. Android Developers, Access native APIs with JavaScript bridge(2026-09-16 갱신). https://developer.android.com/develop/ui/views/layout/webapps/native-api-access-jsbridge
27. Android Developers, WebView – Native bridges(2024-10-15 갱신). https://developer.android.com/privacy-and-security/risks/insecure-webview-native-bridges
28. Android Developers, Webviews – Unsafe URI Loading(2024-09-24 갱신). https://developer.android.com/privacy-and-security/risks/unsafe-uri-loading
29. Android Developers, Cross-app scripting(2024-10-14 갱신). https://developer.android.com/privacy-and-security/risks/cross-app-scripting
30. Android API reference, WebView(`addJavascriptInterface`, `setWebContentsDebuggingEnabled`, `clearCache`, 2026-10-09 갱신). https://developer.android.com/reference/android/webkit/WebView
31. Android API reference, WebViewClient(`shouldOverrideUrlLoading`, `shouldInterceptRequest`, `onReceivedSslError`, 2026-08-03 갱신). https://developer.android.com/reference/android/webkit/WebViewClient
32. Android API reference, WebSettings(파일·content 접근, 혼합 콘텐츠, Safe Browsing, 2026-08-03 갱신). https://developer.android.com/reference/android/webkit/WebSettings
33. AndroidX WebKit 소스, `WebViewCompat.java`(`addWebMessageListener`·`addDocumentStartJavaScript`·`JavaScriptExecutionWorld` Javadoc, androidx-main `0e2330e`). https://github.com/androidx/androidx/blob/0e2330e89a086173c5841cadb6604cc6b6b6c176/webkit/webkit/src/main/java/androidx/webkit/WebViewCompat.java
34. AndroidX WebKit 소스, `JavaScriptReplyProxy.java`(androidx-main `0e2330e`). https://github.com/androidx/androidx/blob/0e2330e89a086173c5841cadb6604cc6b6b6c176/webkit/webkit/src/main/java/androidx/webkit/JavaScriptReplyProxy.java
35. Android Developers, AndroidX WebKit release notes(1.16.0 2026-05-06, 1.17.1 2026-09-23). https://developer.android.com/jetpack/androidx/releases/webkit
36. Android Developers, Network security configuration(2026-08-28 갱신). https://developer.android.com/privacy-and-security/security-config
37. Android Developers, `<application>` manifest element(`usesCleartextTraffic`, `debuggable`, 2026-08-21 갱신). https://developer.android.com/guide/topics/manifest/application-element
38. Google Play Console Help, Remediation for Intent Scheme Hijacking Vulnerability. https://support.google.com/faqs/answer/9101196
39. Google Play Console Help, Remediation for JavaScript Interface Injection Vulnerability. https://support.google.com/faqs/answer/9095419

**Apple·WebKit**

40. Apple Developer Documentation, WKScriptMessage. https://developer.apple.com/documentation/webkit/wkscriptmessage
41. Apple Developer Documentation, WKFrameInfo · WKSecurityOrigin. https://developer.apple.com/documentation/webkit/wkframeinfo · https://developer.apple.com/documentation/webkit/wksecurityorigin
42. Apple Developer Documentation, WKUserContentController `add(_:name:)` · `add(_:contentWorld:name:)`. https://developer.apple.com/documentation/webkit/wkusercontentcontroller/add(_:name:) · https://developer.apple.com/documentation/webkit/wkusercontentcontroller/add(_:contentworld:name:)
43. Apple Developer Documentation, WKContentWorld. https://developer.apple.com/documentation/webkit/wkcontentworld
44. Apple Developer Documentation, WKScriptMessageHandlerWithReply. https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply
45. Apple Developer Documentation, WKNavigationAction `targetFrame`. https://developer.apple.com/documentation/webkit/wknavigationaction/targetframe
46. WebKit Blog, App-Bound Domains(2020-06-26) · Apple Developer Documentation, `limitsNavigationsToAppBoundDomains`. https://webkit.org/blog/10882/app-bound-domains/ · https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/limitsnavigationstoappbounddomains
47. Apple Developer Documentation, WKWebView `isInspectable` · Enabling inspecting content in your apps. https://developer.apple.com/documentation/webkit/wkwebview/isinspectable · https://developer.apple.com/documentation/safari-developer-tools/enabling-inspecting-content-in-your-apps
48. Apple Developer Documentation, NSAppTransportSecurity · NSAllowsArbitraryLoadsInWebContent · NSAllowsLocalNetworking. https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity · https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent · https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking
49. Apple Developer Documentation, WKWebsiteDataStore(`nonPersistent()`, `removeData(ofTypes:)`). https://developer.apple.com/documentation/webkit/wkwebsitedatastore
50. Apple Developer Documentation, WKPreferences `isFraudulentWebsiteWarningEnabled`. https://developer.apple.com/documentation/webkit/wkpreferences/isfraudulentwebsitewarningenabled

**Flutter**

51. flutter/packages, webview_flutter_platform_interface `JavaScriptMessage` · `NavigationRequest`(`0259ad7`). https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_platform_interface/lib/src/types/javascript_message.dart · https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_platform_interface/lib/src/types/navigation_request.dart
52. flutter/packages, webview_flutter_android 4.14.1 소스: `android_webview_controller.dart`(기본 설정, `loadFile`, `clearLocalStorage`, `_handleNavigation`), `WebViewClientProxyApi.java`(서브프레임 허용), `WebViewProxyApi.java`(`addJavascriptInterface`), `WebChromeClientProxyApi.java`(`onCreateWindow`), `WebViewFlutterAndroidExternalApi.java`, `android_webview_cookie_manager.dart`. https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_android/lib/src/android_webview_controller.dart · https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/WebViewClientProxyApi.java#L71-L79 · https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/WebViewProxyApi.java#L247-L250 · https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/WebChromeClientProxyApi.java · https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/WebViewFlutterAndroidExternalApi.java
53. flutter/packages, webview_flutter_wkwebview 3.27.0 소스: `webkit_webview_controller.dart`(`addJavaScriptChannel`, `decidePolicyForNavigationAction`, `onCreateWebView`, `clearCache`·`clearLocalStorage`, 생성 파라미터, `setInspectable`, 인증 챌린지), `web_kit.g.dart`(`WKScriptMessage`·`WebsiteDataType`), `webkit_webview_cookie_manager.dart`. https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_wkwebview/lib/src/webkit_webview_controller.dart · https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_wkwebview/lib/src/common/web_kit.g.dart · https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_wkwebview/lib/src/webkit_webview_cookie_manager.dart
54. flutter/packages, webview_flutter 4.14.1 `WebViewController.addJavaScriptChannel`. https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter/lib/src/webview_controller.dart
55. flutter/flutter#47218 [webview_flutter] Navigation delegate does not have the same behavior on Android and iOS · flutter/flutter#194585 webview_flutter_wkwebview `webView(forIdentifier:withPluginRegistry:)` deprecation warnings. https://github.com/flutter/flutter/issues/47218 · https://github.com/flutter/flutter/issues/194585
56. pub.dev, webview_flutter · flutter_inappwebview 버전 목록(6.1.5 2024-10-08, 6.2.0-beta.3 2026-02-04). https://pub.dev/packages/webview_flutter · https://pub.dev/packages/flutter_inappwebview/versions
57. flutter_inappwebview v6.1.5 소스와 CHANGELOG: Android `InAppWebView.java`(`addWebMessageListener`, `addJavascriptInterface`), iOS `InAppWebView.swift`·`WebMessageListener.swift`(`frameInfo` 검사), 6.2.0-beta.1 변경 내역. https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/in_app_webview/InAppWebView.java · https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_ios/ios/Classes/InAppWebView/InAppWebView.swift · https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_ios/ios/Classes/InAppWebView/WebMessage/WebMessageListener.swift · https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview/CHANGELOG.md
58. flutter/packages, url_launcher `PreferredLaunchMode` · README(`LSApplicationQueriesSchemes`, `<queries>`). https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/url_launcher/url_launcher_platform_interface/lib/src/types.dart · https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/url_launcher/url_launcher/README.md

**웹 표준·Next.js**

59. W3C, Content Security Policy Level 3(Working Draft, 2026-09-16). https://www.w3.org/TR/CSP3/
60. Next.js Docs, How to set a Content Security Policy (CSP) for your Next.js application(2026-03-20 갱신). https://nextjs.org/docs/app/guides/content-security-policy
61. IETF RFC 9111, HTTP Caching(§5.2.2.4 no-cache, §5.2.2.5 no-store). https://www.rfc-editor.org/rfc/rfc9111.html#section-5.2.2.5
62. WHATWG DOM Standard, `Event.isTrusted`(2026-10-16 갱신). https://dom.spec.whatwg.org/#dom-event-istrusted
