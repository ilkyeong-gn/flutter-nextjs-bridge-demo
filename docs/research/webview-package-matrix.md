# Flutter WebView 패키지 기능 비교 조사

- **질문**: [#28 Flutter WebView 패키지 기능 비교 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/28)
- **조사일**: 2026-10-19
- **확인한 버전**: `webview_flutter` 4.14.1(`webview_flutter_android` 4.14.1, `webview_flutter_wkwebview` 3.27.0, `webview_flutter_platform_interface` 2.15.1), `flutter_inappwebview` 6.1.5(최신 안정판: android 1.1.3, ios 1.1.2, platform_interface 1.3.0+1)와 6.2.0-beta.3(프리릴리스). 기준 환경은 Flutter 3.47.7 stable과 이 저장소 app의 Android 빌드 설정(AGP 9.1.0)이다.

## 요약

- **비교 대상은 두 패키지다.** 다른 범용 WebView 패키지는 2021년 이후 릴리스가 없거나(`flutter_webview_plugin`) `webview_flutter`의 확장·호환판이다 [5][6]. 최신 안정판은 `webview_flutter` 4.14.1과 `flutter_inappwebview` 6.1.5(2024-10-08)다. 후자는 그 뒤로 6.2.0-beta.3(2026-02-04)까지 베타만 나왔다 [1][4].
- **`flutter_inappwebview` 6.1.5는 고정 스택에서 막힌다.** AGP 9에서 Android 빌드가 실패한다는 보고가 있다(이 저장소 app은 AGP 9.1.0). iOS는 비공개 API 참조로 App Store 심사에서 거절됐다는 보고가 있고, Swift Package Manager를 지원하지 않는다. 세 문제 모두 6.2.0-beta.3에서만 고쳐졌다 [33][47][67][68][69][8][105]. 이 패키지를 쓰려면 프리릴리스를 쓰거나 직접 고쳐야 한다.
- **Bridge 기본기**: `webview_flutter`는 Web→Host 문자열 Message 채널과 Dart→JS 실행만 제공한다. Call 응답은 직접 만들어야 하고(현재 Demo 방식), 문서 시작 시점에 Host 스크립트를 넣는 API도 없다 [10][13][107]. `flutter_inappwebview`는 `callHandler`가 Dart 반환값을 Promise로 돌려주고(Call 내장), 문서 시작 user script와 `WebMessageListener`를 제공한다 [34][42].
- **출처(origin)·프레임**: `webview_flutter` 채널은 origin·프레임 정보를 주지 않는다. 두 플랫폼 모두 iframe을 포함한 모든 프레임에 채널이 보인다. Android 문서는 호출한 프레임의 origin을 Host 쪽에서 알 방법이 없다고 명시한다 [13][18][24][80]. `flutter_inappwebview`는 `WebMessageListener`로 플랫폼이 판정한 origin·메인 프레임 여부와 origin 허용 목록을 쓸 수 있다. `callHandler`의 origin 정보와 허용 목록은 6.2 베타에만 있다 [34][53][56][39][40].
- **쿠키·저장소**: `webview_flutter` 쿠키 API는 이름·값·도메인·경로만 다룬다. HttpOnly·Secure·만료를 설정할 수 없고 조회 결과에도 속성이 없다(조회는 4.14.0에서 추가). 저장소는 캐시·localStorage 일괄 삭제만 있다 [14][11][17][25][16][24]. `flutter_inappwebview`는 HttpOnly 등 속성 설정, iOS 속성 조회(Android는 WebView 기능 지원 시), 데이터 종류별 삭제를 지원한다 [41][44][45][55].
- **파일·카메라·권한**: iOS에서는 두 패키지 모두 WKWebView 자체 업로드 패널(사진·카메라·파일)이 동작한다 [100]. Android에서 `webview_flutter`는 Host가 파일 선택 콜백을 직접 구현해야 하고(없으면 요청 취소), `flutter_inappwebview`는 카메라 촬영을 포함한 선택기를 내장한다 [16][84][54]. `getUserMedia` 권한 콜백은 둘 다 있지만(iOS 15+), `webview_flutter`는 요청한 origin을 넘겨주지 않는다 [24][16][43].
- **내비게이션**: Android에서는 두 패키지 모두 메인 프레임만 가로챌 수 있고, POST와 `loadUrl`로 시작한 로드에는 콜백이 오지 않는다(플랫폼 제약). iOS는 iframe을 포함한 모든 탐색을 가로챈다. 기록 이동과 iOS 스와이프 제어는 둘 다 있고, 스와이프 기본값은 `webview_flutter`가 꺼짐, `flutter_inappwebview`가 켜짐이다 [82][19][24][35][90][36].
- **수명·장애·가로채기**: Android 렌더러 종료 처리는 `flutter_inappwebview`에만 있다. `webview_flutter`는 Android 기본 동작(Host 강제 종료)을 따른다. iOS 콘텐츠 프로세스 종료 알림은 둘 다 있다. 커스텀 스킴과 요청 가로채기는 `flutter_inappwebview`에만 있다. WebView를 위젯 트리 밖에서 유지하는 방법은 `webview_flutter`가 컨트롤러 보관(소스 기준 추론), `flutter_inappwebview`가 `InAppWebViewKeepAlive`다 [83][76][52][24][35][37][10].
- **유지보수·최소 OS**: 지난 12개월 동안 `webview_flutter` 계열은 Android 구현을 16번, iOS 구현을 19번 릴리스했다. `flutter_inappwebview`는 베타 1회를 내놓은 뒤 2026-02-10 이후 커밋이 없고, 커밋은 메인테이너 한 명이 했다 [2][3][4][63]. 패키지 최소 OS(Android API 24 대 19, iOS 13 대 12)는 Flutter 3.47.7 기본값(API 24, iOS 15.0)보다 낮으므로 결정 요인이 아니다 [103][104].

### 기능 매트릭스

범례: ○ 지원, △ 조건부·부분 지원, × 패키지 API 없음, — 해당 없음. `flutter_inappwebview` 열은 6.1.5 기준이고, β는 6.2.0-beta.3에만 있는 기능이다. 칸마다 근거는 상세의 해당 절에 있다.

| 기능 | webview_flutter iOS | webview_flutter Android | inappwebview iOS | inappwebview Android |
|---|---|---|---|---|
| Web→Host Message | ○ 문자열 | ○ 문자열 | ○ JSON 인자 | ○ JSON 인자 |
| Call 응답(Promise) 내장 | × | × | ○ | ○ |
| Dart→JS 실행·결과 받기 | ○ | ○ | ○ 비동기 함수 포함 | ○ 비동기 함수 포함 |
| 문서 시작 시점 스크립트 주입 | × | × | ○ | △ WebView 기능 지원 시 |
| 보낸 쪽 origin·메인 프레임 정보 | × | × | △ WebMessageListener, callHandler는 β | △ WebMessageListener(기능 지원 시), callHandler는 β |
| Bridge 노출을 origin으로 제한 | × 모든 프레임 | × 모든 프레임 | △ WebMessageListener, β 설정 | △ WebMessageListener, β 설정 |
| 쿠키 쓰기(HttpOnly·Secure·만료) | △ 이름·값·도메인·경로만 | △ 이름·값·도메인·경로만 | ○ | ○ |
| 쿠키 읽기(HttpOnly 쿠키 포함) | △ 속성 없음 | △ 이름=값만 | ○ 속성 포함 | △ 속성은 기능 지원 시 |
| 웹 저장소 정리 | △ 캐시·localStorage 일괄 | △ 캐시·Web Storage 일괄 | ○ 데이터 종류·시각 기준 | ○ 전체·origin별 |
| `<input type="file">`·카메라 캡처 | ○ WebKit 기본 패널 | △ Host가 콜백 구현 | ○ WebKit 기본 패널 | ○ 내장(FileProvider 등록 필요) |
| `getUserMedia` 권한 요청 | ○ iOS 15+, origin 없음 | ○ origin 없음, 미설정 시 거부 | ○ iOS 15+, origin·프레임 | ○ origin |
| 내비게이션 가로채기 | ○ 모든 프레임 | △ 메인 프레임만 | ○ 모든 프레임 | △ 메인 프레임만(iframe은 정규식 취소) |
| 뒤로·앞으로 기록 | ○ | ○ | ○ 기록 목록 조회 | ○ 기록 목록 조회 |
| iOS 스와이프 뒤로가기 제어 | ○ 기본 꺼짐 | — | ○ 기본 켜짐 | — |
| WebView를 위젯 트리 밖에서 유지 | △ 컨트롤러 보관 | △ 컨트롤러 보관 | ○ KeepAlive | ○ KeepAlive |
| 콘텐츠 프로세스 종료 대응 | ○ 오류 콜백 | × 미처리 시 Host 종료 | ○ | ○ API 26+ |
| 커스텀 스킴 | × | × | ○ | ○ |
| 요청 가로채기 | × | × | △ fetch·XHR(JS)만 | ○ |
| 웹 디버깅 | ○ 직접 켜야 함(16.4+) | ○ debuggable 빌드는 자동 | ○ | ○ |
| 패키지 최소 OS | iOS 13.0 | API 24 | iOS 12.0 | API 19 |
| 고정 스택에서 빌드 | ○ SwiftPM 지원 | ○ 현재 Demo 구성 | △ CocoaPods 대체 경로, 심사 거절 보고(β 수정) | × AGP 9 실패 보고(β 수정) |

## 상세

### 0. 비교 대상

- pub.dev에서 Android·iOS를 지원하는 "webview" 패키지를 좋아요순으로 보면, 범용 WebView는 `webview_flutter`, `flutter_inappwebview`, `flutter_webview_plugin` 셋이다 [5]. `flutter_webview_plugin`은 0.4.0(2021-05-24)이 마지막 릴리스다 [6]. `webview_flutter_plus`와 `webview_all`은 스스로 `webview_flutter`의 확장 또는 호환 API라고 소개한다 [5]. 그래서 두 패키지만 비교했다.
- `webview_flutter`는 flutter.dev가 게시하는 federated 플러그인이다. 공통 API에 없는 기능은 `controller.platform`을 `AndroidWebViewController`·`WebKitWebViewController`로 바꿔 쓴다 [9]. 아래에서 "패키지 Dart API"는 이 두 경로를 합친 것이다.
- 두 구현 패키지는 플랫폼 코드(Kotlin·Swift)에서 패키지 내부의 플랫폼 WebView 객체를 얻는 External API도 연다(Android 4.13.0, iOS 3.26.0) [20][28][22][27]. Android README는 이 API만 호환성을 보장하고, 그 밖의 플랫폼 코드는 보장하지 않는다고 적는다 [21].
- 현재 Demo는 `webview_flutter` 4.14.1을 AGP 9.1.0 빌드 설정에서 쓴다 [105][106].
- `flutter_inappwebview`는 inappwebview.dev가 게시한다. 최신 안정판 6.1.5는 2024-10-08에 나왔고, 그 뒤 릴리스는 6.2.0-beta.1(2024-11-05)부터 beta.3(2026-02-04)까지 베타뿐이다 [4][8].

### 1. JS→Dart 통로, 응답 방식, Dart→JS 실행, 문서 시작 시점 주입

**webview_flutter**

- `addJavaScriptChannel(name, onMessageReceived)`를 등록하면 Web이 `name.postMessage(...)`로 Message를 보낸다. 새 채널은 다음 페이지 로드부터 적용된다 [10]. Dart가 받는 `JavaScriptMessage`에는 `message` 문자열 하나만 있다 [13].
- Android는 `addJavascriptInterface`로 구현한다 [18]. iOS는 `window.<name> = webkit.messageHandlers.<name>`를 문서 시작 시점의 모든 프레임 user script로 넣고 script message handler를 등록한다. 받은 body는 `toString()`으로 문자열이 된다 [24].
- 채널은 응답을 돌려주지 않는다. 그래서 Demo Stage C는 Call id를 담은 Message를 받고 `runJavaScript('window.__onFlutterResponse(...)')`로 응답한다 [107]. Host→Web Event도 같은 Dart→JS 실행으로 보낸다.
- Dart→JS는 `runJavaScript`와 `runJavaScriptReturningResult`다. 후자는 iOS에서 일부 비원시 타입과 iOS 14+의 `undefined`·`null` 결과를 받지 못한다 [10].
- Host가 자기 스크립트를 문서 시작 시점에 넣는 패키지 Dart API는 없다 [10]. 관련 요청 #82682는 2021년부터 열려 있다 [77]. 플랫폼 코드로는 가능하다. Android는 `WebViewCompat.addDocumentStartJavaScript`로 origin 규칙을 붙여 주입한다(`DOCUMENT_START_SCRIPT` 기능 필요) [88]. iOS는 `WKUserContentController.addUserScript`를 쓴다 [97]. iOS 구현 패키지도 웹 뷰 생성 뒤에 이 방법으로 채널 스크립트를 넣는다 [24].

**flutter_inappwebview**

- `addJavaScriptHandler(handlerName, callback)`를 등록하면 Web의 `window.flutter_inappwebview.callHandler(name, ...args)`가 Promise를 돌려준다. Dart 콜백의 반환값은 JSON으로 인코딩돼 그 Promise를 resolve한다. 인자는 `JSON.stringify`로 넘어온다. 호출은 `flutterInAppWebViewPlatformReady` 이벤트 뒤에 해야 한다. 구현은 Android `addJavascriptInterface`, iOS `addScriptMessageHandler`다 [34][38].
- `addWebMessageListener`는 지정한 이름의 JS 객체를 주입한다. Web이 먼저 `postMessage`를 보내야 Dart가 `replyProxy.postMessage`로 응답이나 Event를 보낼 수 있다. Android는 `WEB_MESSAGE_LISTENER` 기능이 있을 때만 쓸 수 있고, iOS는 JavaScript로 구현돼 있다 [34].
- Dart→JS는 `evaluateJavascript`와 `callAsyncJavaScript`(인자 맵 전달, 비동기 함수 결과 대기)다 [34].
- 문서 시작 주입은 `UserScript(injectionTime: AT_DOCUMENT_START)`로 한다. Android는 `DOCUMENT_START_SCRIPT` 기능이 있으면 `addDocumentStartJavaScript`를 쓰고 [51], 없으면 `onPageStarted`에서 `evaluateJavascript`로 대신 넣는다 [52]. 패키지 문서도 Android의 스크립트 주입은 iOS처럼 즉시가 아니라 최대 100ms쯤 늦을 수 있다고 적는다(fetch 가로채기 설명) [35]. `forMainFrameOnly`는 iOS 전용, `allowedOriginRules`는 Android 전용이다 [42].
- Android WebView 기능의 지원 여부는 기기에 설치된 WebView APK 버전에 따라 런타임에 정해진다 [89].

### 2. 메시지 출처(origin)와 메인 프레임·iframe 구분

- 플랫폼 사실: Android `addJavascriptInterface` 객체는 iframe을 포함한 모든 프레임에 주입되고, Host 쪽에서는 호출한 프레임의 origin을 알 수 없다 [80]. 반면 androidx `addWebMessageListener`는 `allowedOriginRules`와 맞는 프레임에만 객체를 넣고, 콜백에 `sourceOrigin`과 `isMainFrame`을 준다 [87]. iOS의 `WKScriptMessage`에는 보낸 프레임(`frameInfo`)과 그 보안 origin이 있다 [93][94].
- `webview_flutter`: 메시지에 origin·프레임 정보가 없다 [13]. Android 채널은 위의 `addJavascriptInterface` 그대로이고 [18], iOS 채널 스크립트도 `isForMainFrameOnly: false`라서 iframe에서 보인다 [24]. 같은 문제를 다룬 #137575가 열려 있다 [78]. 프레임 구분 정보는 내비게이션 요청(`isMainFrame`)과 리소스 오류(`isForMainFrame`)에만 있다 [9][24].
- `flutter_inappwebview` 6.1.5:
  - `callHandler` 콜백은 인자 목록만 받는다 [38]. 브리지 스크립트는 Android에서 origin 규칙 없이 [50], iOS에서 모든 프레임에 [57] 주입된다. Android `_callHandler`와 iOS 처리부에는 origin 검사가 없다 [48][56].
  - `WebMessageListener`는 다르다. Android는 `WebViewCompat.addWebMessageListener`에 `allowedOriginRules`를 넘기고, 기능이 없으면 아무 오류 없이 등록을 건너뛴다 [53]. iOS는 `frameInfo.securityOrigin`을 허용 규칙과 대조한 뒤 `sourceOrigin`·`isMainFrame`을 넘긴다 [56].
- 6.2.0-beta: `JavaScriptHandlerFunctionData`(인자, origin, isMainFrame, requestUrl)와 `javaScriptHandlersOriginAllowList`·`javaScriptHandlersForMainFrameOnly`·`javaScriptBridgeOriginAllowList` 등이 추가됐다 [39][40]. 다만 Android 구현에서 origin·isMainFrame은 주입 스크립트가 JSON으로 보낸 값이고, 호출은 주입 스크립트에 넣은 비밀 토큰으로 확인한다 [49][108]. 브라우저가 판정하는 `WebMessageListener`의 origin과는 성격이 다르다.

### 3. 쿠키(HttpOnly 포함)와 웹 저장소 정리

**webview_flutter**: `WebViewCookie`는 name·value·domain·path 네 필드뿐이다 [14].

- 쓰기: Android는 `name=value; path=...` 문자열을 넣고 [17], iOS는 같은 네 속성만으로 `HTTPCookie`를 만든다 [25]. HttpOnly·Secure·만료·SameSite를 지정할 수 없다.
- 읽기: `getCookies`는 4.14.0에서 추가됐다 [11][12]. iOS는 `WKHTTPCookieStore` 전체에서 도메인이 맞는 쿠키를 네 필드로 돌려준다 [25]. Android는 `CookieManager.getCookie(url)` 문자열(Cookie 헤더 형식의 `key=value` 목록 [86])을 `; `와 `=`로 나눈다. 값에 `=`가 있으면 마지막 조각만 남고, domain에는 요청 URL이 들어간다 [17].
- 삭제: 쿠키는 `clearCookies`로 전부 지우는 것만 있다 [12]. 저장소는 `clearCache`와 `clearLocalStorage`다. Android는 `WebStorage.deleteAllData()`를 부르고 [16], iOS는 `WKWebsiteDataStore`에서 캐시 종류와 localStorage 종류를 지운다 [24].

**flutter_inappwebview** `CookieManager`:

- `setCookie`에 `isSecure`·`isHttpOnly`·`sameSite`·만료를 줄 수 있다. Android는 Set-Cookie 문자열에 `; HttpOnly` 등을 붙이고 [55], iOS는 `WKHTTPCookieStore`를 쓴다 [44].
- `getCookies`는 iOS `getAllCookies`, Android `getCookie` 기반이다 [44]. Android의 domain·path·HttpOnly·Secure·만료는 `GET_COOKIE_INFO` 기능이 있을 때만 채워진다 [41][55].
- `deleteCookie`·`deleteCookies`·`deleteAllCookies`가 있다 [44]. 저장소는 `WebStorageManager`로 지운다. Android는 `WebStorage`(전체·origin별), iOS는 `WKWebsiteDataStore`(데이터 종류·수정 시각 기준)를 쓴다 [45]. 캐시 전체 삭제는 `clearAllCache`다 [34].

### 4. `<input type="file">`, 카메라 캡처, `getUserMedia` 권한

- **iOS(두 패키지 공통)**: WebKit의 iOS 업로드 패널이 사진 보관함·카메라·문서 선택기를 띄우고, `capture` 속성도 처리한다 [100]. 카메라를 쓰려면 Info.plist에 `NSCameraUsageDescription`이 있어야 한다 [99].
- **Android `webview_flutter`**: `AndroidWebViewController.setOnShowFileSelector`로 Host가 선택 UI를 만들고 파일 URI 문자열 목록을 돌려준다. 콜백에는 모드, `acceptTypes`, `isCaptureEnabled`, 파일명 힌트가 온다 [16]. 콜백을 등록하지 않으면 Android 기본 동작대로 모든 파일 요청이 취소된다 [16][84]. 촬영도 Host가 구현해야 한다.
- **Android `flutter_inappwebview`**: 플러그인이 `onShowFileChooser`를 처리해 파일 선택 intent와 사진·영상 촬영 intent를 묶은 선택기를 띄운다 [54]. Host의 AndroidManifest에 `InAppWebViewFileProvider`를 등록하고 카메라 권한을 선언해야 한다 [61]. 6.2 베타는 이 처리를 Dart에서 바꿀 수 있는 `onShowFileChooser` 이벤트를 더했다 [33].
- **`getUserMedia`**:
  - `webview_flutter`는 `WebViewController(onPermissionRequest:)`로 받는다. 요청 객체에는 리소스 종류만 있고 origin은 없다 [10][16][24]. Android 플랫폼 API는 Host가 grant나 deny로 답하게 하고 [85], 구현 패키지는 콜백이 없으면 거부한다 [16]. iOS는 `WKUIDelegate`의 미디어 캡처 권한 메서드(iOS 15+)로 구현돼 있고, 콜백이 없으면 시스템이 사용자에게 묻는다 [24][98].
  - `flutter_inappwebview`의 `onPermissionRequest`는 origin·리소스·프레임을 준다. Android 21+, iOS 15+이고, iOS 기본 응답은 사용자에게 묻기다 [35][43].
  - 두 패키지 모두 OS 권한 선언과 런타임 권한 요청은 Host가 따로 해야 한다 [10][61].

### 5. 내비게이션 가로채기, 기록, iOS 스와이프 뒤로가기

- **Android 플랫폼 제약**: `shouldOverrideUrlLoading`은 `loadUrl`로 시작한 탐색과 POST 요청에는 불리지 않는다. iframe이나 http(s)가 아닌 스킴에도 불릴 수 있다. 문서는 true를 반환한 뒤 같은 URL을 `loadUrl`하는 방식을 피하라고 한다 [82].
- **`webview_flutter` Android**: `onNavigationRequest`를 설정하면 메인 프레임 탐색은 일단 취소된다. Dart가 `navigate`를 돌려주면 그 URL을 `loadUrl`로 다시 불러온다. iframe 탐색은 Dart에 묻지 않고 항상 통과한다 [19][16].
- **`webview_flutter` iOS**: `decidePolicyForNavigationAction`에서 iframe을 포함한 모든 탐색을 Dart에 묻는다 [24]. `target="_blank"`·`window.open` 새 창 요청은 같은 WebView에서 연다 [24].
- **`flutter_inappwebview`**: `shouldOverrideUrlLoading`(설정 `useShouldOverrideUrlLoading` 필요)도 Android에서는 메인 프레임만 막을 수 있고, POST와 첫 로드에는 불리지 않는다. iframe은 `regexToCancelSubFramesLoading` 정규식으로 취소할 수 있다 [35][36][52]. 새 창은 `onCreateWindow`로 받는다 [35].
- **외부 앱·브라우저로 넘기기**: 두 패키지 모두 전용 기능이 없다. 가로채기 콜백에서 막은 뒤 Host가 직접 연다.
- **기록**: 둘 다 `canGoBack`·`goBack`·`canGoForward`·`goForward`가 있다 [10][34]. `flutter_inappwebview`는 기록 목록 조회(`getCopyBackForwardList`)와 Android 기록 삭제도 지원한다 [34]. `webview_flutter` iOS에는 `canGoBack` 변경 리스너가 있다 [27].
- **iOS 스와이프**: WKWebView의 `allowsBackForwardNavigationGestures` 기본값은 false다 [90]. `webview_flutter`는 `setAllowsBackForwardNavigationGestures`로 켠다 [24]. `flutter_inappwebview`는 같은 설정의 기본값이 true다 [36].

### 6. 여러 WebView 유지, 프로세스 종료 복구, 커스텀 스킴·요청 가로채기

- **`webview_flutter` 수명**: `WebViewController`는 위젯 트리에 붙기 전에 만들고 쓸 수 있고, 한 번에 `WebViewWidget` 하나에만 붙는다 [9][10]. 플랫폼 뷰는 컨트롤러가 가진 기존 WebView를 꺼내 화면에 붙인다. Android 플랫폼 뷰의 `dispose`는 아무것도 하지 않고 [18], iOS 플랫폼 뷰는 WebView를 약한 참조로만 잡는다 [29]. 따라서 위젯을 트리에서 빼도 컨트롤러를 들고 있으면 같은 WebView가 남는다(소스로부터의 추론). 반대로 명시적으로 해제하는 API는 없고, 요청 #119616이 열려 있다 [75].
- **`flutter_inappwebview` 수명**: `keepAlive: InAppWebViewKeepAlive`를 주면 위젯이 사라져도 WebView가 유지되고, `disposeKeepAlive`로 해제한다 [37][34].
- **프로세스 종료**:
  - Android `onRenderProcessGone`이 false(기본값)를 돌려주면, 렌더러가 crash할 때 Host도 crash하고 시스템이 렌더러를 죽이면 Host도 종료된다 [83].
  - `webview_flutter_android`에는 이 콜백 구현이 없고 [19], 지원 요청 #130297이 열려 있다 [76]. 플랫폼 코드로 붙이려면 플러그인이 설정한 `WebViewClient`를 바꿔야 하는데, 이는 External API가 보장하는 범위 밖이다(추론) [21].
  - `flutter_inappwebview`는 `onRenderProcessGone`(API 26+)을 구현하면 true를 돌려주고 Dart에 알린다 [35][36][52].
  - iOS: `webViewWebContentProcessDidTerminate`가 불린다 [92]. `webview_flutter`는 이를 `onWebResourceError`의 `webContentProcessTerminated` 종류로 전달하고 [24], `flutter_inappwebview`는 `onWebContentProcessDidTerminate`로 전달한다 [35][56]. 다시 불러오기는 두 경우 모두 Host가 직접 한다.
- **커스텀 스킴·요청 가로채기**:
  - `webview_flutter`에는 둘 다 없다 [10]. iOS 커스텀 스킴은 `WKWebViewConfiguration`에 등록해야 하는데, 설정은 웹 뷰 생성 시점에만 반영된다 [95][96]. 구현 패키지의 생성 파라미터에는 미디어 재생 조건, 인라인 재생, App-Bound Domains, 창 열기 항목만 있다 [24]. 그래서 External API로도 나중에 붙일 수 없다.
  - `flutter_inappwebview`는 `resourceCustomSchemes`와 `onLoadResourceWithCustomScheme`을 제공한다. iOS는 `WKURLSchemeHandler`로 구현하고, http·https는 지정할 수 없다 [35][36]. Android 전용 `shouldInterceptRequest`도 있다 [35]. fetch·XHR 가로채기는 JS 주입 방식이다 [35].

### 7. 디버깅, 유지보수 상태, 최소 OS 버전

**디버깅**

- Android WebView 113 이상은 `android:debuggable="true"` 빌드에서 웹 디버깅이 자동으로 켜진다 [81]. 두 패키지 모두 직접 켜는 API도 있다 [16][34].
- iOS 16.4+는 `isInspectable` 기본값이 false다 [91]. `webview_flutter`는 `setInspectable`, `flutter_inappwebview`는 `isInspectable` 설정으로 켠다 [24][36].
- 콘솔 메시지 콜백은 둘 다 있다 [10][35].

**유지보수(2025-10-19~2026-10-19)**

- `webview_flutter` 계열: `webview_flutter` 본체 3번, Android 구현 16번, iOS 구현 19번 릴리스했다. 최신 iOS 구현 3.27.0은 2026-10-01에 나왔다 [1][2][3]. flutter/packages에서 `p: webview_flutter` 라벨 PR 74건이 병합됐다 [74]. flutter/flutter에 열린 `p: webview` 이슈는 208건이다(iOS 62, Android 67) [73]. 그중 P1은 1건으로, Android에서 키보드 애니메이션과 WebView 크기 조정이 맞지 않는 문제다(#191094, 3.47에서 발견) [79]. pub.dev 점수는 160/160이고 `is:swiftpm-plugin` 태그가 있다 [7].
- `flutter_inappwebview`: 안정판 릴리스 0번, 베타 1번이다 [4]. 같은 기간 커밋 216건은 2025-11~2026-02에 몰려 있고(215건이 2025-12~2026-02), 206건은 메인테이너, 10건은 봇이 작성했다. 2026-02-10 이후 커밋은 없다 [63]. 같은 기간 병합 PR은 10건이다(모두 2025-12-10) [66]. 열린 이슈는 129건, 열린 PR은 88건이다 [64][65]. 365일 동안 활동이 없는 이슈를 자동으로 닫는 워크플로가 있어 열린 이슈 수만으로는 상태를 판단하기 어렵다 [62]. pub.dev 점수는 130/160이고 `is:darwin-legacy-native-build` 태그가 붙어 있다 [8].
- 6.1.5 안정판의 문제(앞의 셋은 6.2.0-beta.3 CHANGELOG에 수정으로 올라 있다 [33]):
  - Android `build.gradle`의 `proguard-android.txt` 지정이 AGP 9에서 빌드를 실패시킨다(#2765) [47][68]. Flutter 3.47.2 + AGP 9.0.1 조합에서도 같은 실패가 열린 이슈로 보고돼 있다(#2887) [69].
  - iOS 코드의 `PGHostedWindow` 참조 때문에 App Store 심사 지침 2.5.1로 거절됐다는 보고가 있다(#2754) [56][67].
  - Swift Package Manager는 6.2.0-beta.3부터 지원한다 [58][33]. Flutter는 3.44부터 SwiftPM이 기본이고, 지원하지 않는 의존성이 있으면 CocoaPods로 돌아간다. CocoaPods 레지스트리는 2026-12-02부터 읽기 전용이다 [101].
  - Xcode 26.4.1에서 6.1.5의 iOS 코드가 컴파일되지 않는다는 열린 보고도 있다(#2830, 보고 환경 Flutter 3.24.4) [70]. 문제의 선언은 beta.3 소스에도 그대로 있다 [109].
- 6.2.0-beta.3의 위험:
  - Android release 빌드에서 cold start의 약 50%에 `onWebViewCreated`가 불리지 않는다는 열린 보고가 있다(#2843). 6.2 베타의 새 브리지 보안 경로와 관련 있다는 분석이 달려 있고, 보고자는 시험한 에뮬레이터에서는 재현되지 않았다고 적었다 [71].
  - Flutter 팀 명의의 UIScene 대응 요청(#2880)이 열려 있다 [72]. Flutter 문서에 따르면 iOS 26 다음 릴리스의 최신 SDK로 빌드하는 UIKit 앱은 UIScene 생명주기를 써야 실행된다 [102]. beta.3 iOS 코드에는 `keyWindow`·`delegate.window` 사용이 남아 있다 [59][60]. `webview_flutter_wkwebview` 3.27.0 Swift 소스에서는 같은 API를 찾지 못했다 [31].

**최소 OS**

- `webview_flutter`: Android SDK 24+, iOS 13.0+ [9][23][30].
- `flutter_inappwebview`: Android minSdk 19, iOS 12.0+ [32][47].
- Flutter 3.47.7의 기본값은 Android minSdk 24, 새 iOS 앱 템플릿 15.0이다 [103][104]. 패키지 하한 차이는 Reference App에 영향이 없다.

## Reference App에 주는 시사점

「WebView 패키지 결정」(#38)이 견줄 선택지와 트레이드오프다. 여기서는 하나를 고르지 않는다.

| 선택지 | 바로 얻는 것 | 직접 메우거나 감수할 것 |
|---|---|---|
| A. `webview_flutter`만 사용(현재 Demo의 연장) | 1st-party 패키지, 잦은 릴리스, SwiftPM 지원, 현재 Demo의 AGP 9 구성에서 동작, Demo 코드 재사용 | Call 응답을 Bridge 계약으로 직접 구현. Host가 origin을 검증할 수 없어 ② 보안은 탐색 제한과 로드 정책에 기댐. HttpOnly 쿠키 속성 제어 불가(③). Android 파일 선택·촬영 직접 구현(S2). Android 렌더러 종료 시 Host 종료(⑤). 커스텀 스킴·요청 가로채기 없음(⑥) |
| B. `webview_flutter` + 플랫폼 코드 확장 | A의 장점 유지. Android `addWebMessageListener`·`addDocumentStartJavaScript`, iOS user script·`frameInfo`로 origin을 아는 채널과 문서 시작 주입 구현 가능. 쿠키 속성도 플랫폼 API로 처리 가능 | Kotlin·Swift 코드와 Dart 연결을 Reference App이 직접 유지. iOS 커스텀 스킴은 생성 시점 설정이라 불가. Android 렌더러 종료 처리는 플러그인 내부 클라이언트를 건드려야 함(추론). ⑧ 테스트 대상이 플랫폼 코드까지 늘어남 |
| C. `flutter_inappwebview` 6.2.0-beta.3 | Call 내장, 플랫폼이 판정한 origin(`WebMessageListener`), 문서 시작 주입, HttpOnly 쿠키, 커스텀 스킴·요청 가로채기, 렌더러 종료 처리, KeepAlive, Android 파일 선택기 내장 | 6.2.0은 2024-11 첫 베타 뒤 안정판이 없고 마지막 베타도 8개월 전. 메인테이너 1인이고 2026-02 이후 커밋 없음. Android release 빌드 `onWebViewCreated` 누락 보고(#2843, 에뮬레이터에서는 재현 안 됐다는 보고). UIScene 대응 미완(#2880). Demo 코드를 옮겨야 함 |
| D. `flutter_inappwebview` 6.1.5 + 직접 패치(dependency_overrides 또는 포크) | 안정판 번호와 API | AGP 9 빌드, App Store 거절 보고, SwiftPM 미지원을 직접 고쳐야 함. 포크 유지 비용. `callHandler` origin 정보 없음 |

선택과 관계없이 남는 사실:

- Android 탐색 가로채기는 두 패키지 모두 메인 프레임만 막고, POST와 첫 로드에는 콜백이 없다 [82][19][35]. S3의 URL 허용 목록과 ② 보안은 이 제약을 전제로 설계해야 한다. iframe 탐색을 막는 옵션은 `flutter_inappwebview`의 정규식뿐이다 [36].
- 두 패키지의 기본 Bridge 통로는 문자열·JSON이다 [13][34]. S2에서 사진·영상 바이트를 Bridge로 넘기면 인코딩 비용이 생긴다. 다른 길은 Web의 `<input type="file">`, Host 기능 Call 뒤 Host가 직접 업로드, `flutter_inappwebview` 커스텀 스킴으로 Host 파일을 URL로 제공하는 방법이다.
- S5 Host 화면 왕복에서 Web 화면 상태를 지키는 수단은 두 패키지 모두 있다(컨트롤러 보관, KeepAlive) [10][37]. 언제 해제할지는 Reference App이 정해야 한다.
- iOS 프로세스 종료는 두 패키지 모두 알려 주므로 복구 화면 정책을 둘 수 있다 [24][35]. Android는 A를 고르면 Host 종료로 끝난다 [83][76].
- ⑧ 테스트: 두 패키지 모두 플랫폼 인터페이스의 `instance`를 바꿔 가짜 구현을 넣을 수 있다 [15][46].
- 최소 OS는 결정 요인이 아니다 [103][104].

## 확인하지 못한 것과 새로 생긴 질문

확인하지 못한 것:

- 이 저장소 구성(Flutter 3.47.7, AGP 9.1.0, Xcode)에서 `flutter_inappwebview` 6.1.5와 6.2.0-beta.3을 직접 빌드·실행하지 않았다. 6.1.5의 AGP 9 실패, #2830의 Xcode 컴파일 오류, #2843의 release 빌드 문제는 이슈와 소스로만 판단했다. 특히 #2843은 실기기 release 빌드에서 보고됐고 에뮬레이터에서는 재현되지 않았다고 하므로, 에뮬레이터 중심 검증으로는 드러나지 않을 수 있다 [71].
- 검증 환경(iOS 시뮬레이터, Android 에뮬레이터)의 WebView 버전에서 `WEB_MESSAGE_LISTENER`·`DOCUMENT_START_SCRIPT`·`GET_COOKIE_INFO`를 지원하는지 확인하지 않았다 [89].
- Android `webview_flutter`의 `getCookies` 파싱(값 속 `=` 처리)이 Reference App 세션 쿠키 형식에서 실제로 문제가 되는지 모른다.
- iOS에서 Flutter 라우트의 스와이프 뒤로가기와 WebView 스와이프·터치가 어떻게 맞물리는지 모른다. 3.27.0이 터치 무응답 우회 옵션을 추가한 배경과 함께 프로토타입으로 봐야 한다 [26][27].
- 선택지 B의 실제 비용을 재지 않았다. External API로 얻은 WebView에 붙인 플랫폼 코드를 Dart와 잇는 방식, 플러그인 내부 설정과 충돌하는지가 열려 있다.

새로 생긴 질문(티켓 후보):

1. Bridge 계약이 Message마다 origin·프레임을 검증해야 하는가, 아니면 "신뢰한 단일 origin만 로드 + 탐색 제한"으로 충분한가? (②, 계약 설계와 연결)
2. S2 사진·영상을 Web이 `<input type="file">`로 받을지, Host 기능 Call로 받을지, 업로드는 누가 할지? 패키지 선택과 맞물린다.
3. Android 렌더러 종료나 iOS 콘텐츠 프로세스 종료 뒤 Web 화면을 어떻게 복구하고 무엇을 보여 줄지? ("로딩·오프라인·에러 화면"과 연결)
4. WebView 인스턴스 수명 정책: S5 왕복과 여러 Web 화면에서 몇 개를 유지하고 언제 해제할지?
5. Host가 세션 쿠키를 직접 심거나 속성까지 읽어야 하는가(③)? 그렇다면 HttpOnly 속성 제어가 패키지 결정의 필수 조건이 된다.

## 출처

1. [webview_flutter 버전 목록 (pub.dev)](https://pub.dev/packages/webview_flutter/versions)
2. [webview_flutter_android 버전 목록 (pub.dev)](https://pub.dev/packages/webview_flutter_android/versions)
3. [webview_flutter_wkwebview 버전 목록 (pub.dev)](https://pub.dev/packages/webview_flutter_wkwebview/versions)
4. [flutter_inappwebview 버전 목록 (pub.dev)](https://pub.dev/packages/flutter_inappwebview/versions)
5. [pub.dev 검색: webview, Android·iOS, 좋아요순](https://pub.dev/packages?q=webview+platform%3Aandroid+platform%3Aios&sort=like)
6. [flutter_webview_plugin 버전 목록 (pub.dev)](https://pub.dev/packages/flutter_webview_plugin/versions)
7. [webview_flutter 점수·태그 (pub.dev)](https://pub.dev/packages/webview_flutter/score)
8. [flutter_inappwebview 점수·태그 (pub.dev)](https://pub.dev/packages/flutter_inappwebview/score)
9. [webview_flutter 4.14.1 README](https://github.com/flutter/packages/blob/webview_flutter-v4.14.1/packages/webview_flutter/webview_flutter/README.md)
10. [webview_flutter 4.14.1 `webview_controller.dart`](https://github.com/flutter/packages/blob/webview_flutter-v4.14.1/packages/webview_flutter/webview_flutter/lib/src/webview_controller.dart)
11. [webview_flutter 4.14.1 CHANGELOG](https://github.com/flutter/packages/blob/webview_flutter-v4.14.1/packages/webview_flutter/webview_flutter/CHANGELOG.md)
12. [webview_flutter 4.14.1 `webview_cookie_manager.dart`](https://github.com/flutter/packages/blob/webview_flutter-v4.14.1/packages/webview_flutter/webview_flutter/lib/src/webview_cookie_manager.dart)
13. [webview_flutter_platform_interface 2.15.1 `javascript_message.dart`](https://github.com/flutter/packages/blob/webview_flutter_platform_interface-v2.15.1/packages/webview_flutter/webview_flutter_platform_interface/lib/src/types/javascript_message.dart)
14. [webview_flutter_platform_interface 2.15.1 `webview_cookie.dart`](https://github.com/flutter/packages/blob/webview_flutter_platform_interface-v2.15.1/packages/webview_flutter/webview_flutter_platform_interface/lib/src/types/webview_cookie.dart)
15. [webview_flutter_platform_interface 2.15.1 `webview_platform.dart`](https://github.com/flutter/packages/blob/webview_flutter_platform_interface-v2.15.1/packages/webview_flutter/webview_flutter_platform_interface/lib/src/webview_platform.dart#L27-L31)
16. [webview_flutter_android 4.14.1 `android_webview_controller.dart`](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/lib/src/android_webview_controller.dart)
17. [webview_flutter_android 4.14.1 `android_webview_cookie_manager.dart`](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/lib/src/android_webview_cookie_manager.dart#L56-L102)
18. [webview_flutter_android 4.14.1 `WebViewProxyApi.java`](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/WebViewProxyApi.java)
19. [webview_flutter_android 4.14.1 `WebViewClientProxyApi.java`](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/WebViewClientProxyApi.java#L71-L79)
20. [webview_flutter_android 4.14.1 `WebViewFlutterAndroidExternalApi.java`](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/WebViewFlutterAndroidExternalApi.java)
21. [webview_flutter_android 4.14.1 README](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/README.md)
22. [webview_flutter_android 4.14.1 CHANGELOG](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/CHANGELOG.md)
23. [webview_flutter_android 4.14.1 `build.gradle.kts`](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/android/build.gradle.kts#L44)
24. [webview_flutter_wkwebview 3.27.0 `webkit_webview_controller.dart`](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/lib/src/webkit_webview_controller.dart)
25. [webview_flutter_wkwebview 3.27.0 `webkit_webview_cookie_manager.dart`](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/lib/src/webkit_webview_cookie_manager.dart)
26. [webview_flutter_wkwebview 3.27.0 README](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/README.md)
27. [webview_flutter_wkwebview 3.27.0 CHANGELOG](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/CHANGELOG.md)
28. [webview_flutter_wkwebview 3.27.0 `WebViewFlutterWKWebViewExternalAPI.swift`](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/darwin/webview_flutter_wkwebview/Sources/webview_flutter_wkwebview/WebViewFlutterWKWebViewExternalAPI.swift)
29. [webview_flutter_wkwebview 3.27.0 `FlutterViewFactory.swift`](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/darwin/webview_flutter_wkwebview/Sources/webview_flutter_wkwebview/FlutterViewFactory.swift)
30. [webview_flutter_wkwebview 3.27.0 `Package.swift`](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/darwin/webview_flutter_wkwebview/Package.swift#L12)
31. [webview_flutter_wkwebview 3.27.0 Swift 소스 디렉터리](https://github.com/flutter/packages/tree/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/darwin/webview_flutter_wkwebview/Sources/webview_flutter_wkwebview)
32. [flutter_inappwebview 6.1.5 README (Requirements)](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview/README.md#requirements)
33. [flutter_inappwebview 6.2.0-beta.3 CHANGELOG](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview/CHANGELOG.md)
34. [flutter_inappwebview 6.1.5 `platform_inappwebview_controller.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/in_app_webview/platform_inappwebview_controller.dart)
35. [flutter_inappwebview 6.1.5 `platform_webview.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/in_app_webview/platform_webview.dart)
36. [flutter_inappwebview 6.1.5 `in_app_webview_settings.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/in_app_webview/in_app_webview_settings.dart)
37. [flutter_inappwebview 6.1.5 `platform_inappwebview_widget.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/in_app_webview/platform_inappwebview_widget.dart#L172-L181)
38. [flutter_inappwebview 6.1.5 `javascript_handler_callback.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/types/javascript_handler_callback.dart)
39. [flutter_inappwebview 6.2.0-beta.3 `javascript_handler_callback.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_platform_interface/lib/src/types/javascript_handler_callback.dart)
40. [flutter_inappwebview_platform_interface 1.4.0-beta.3 CHANGELOG](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_platform_interface/CHANGELOG.md)
41. [flutter_inappwebview 6.1.5 `cookie.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/types/cookie.dart#L32-L90)
42. [flutter_inappwebview 6.1.5 `user_script.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/types/user_script.dart)
43. [flutter_inappwebview 6.1.5 `permission_request.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/types/permission_request.dart)
44. [flutter_inappwebview 6.1.5 `platform_cookie_manager.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/platform_cookie_manager.dart)
45. [flutter_inappwebview 6.1.5 `platform_web_storage_manager.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/web_storage/platform_web_storage_manager.dart)
46. [flutter_inappwebview 6.1.5 `inappwebview_platform.dart`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/inappwebview_platform.dart#L39-L43)
47. [flutter_inappwebview_android (6.1.5 태그) `build.gradle`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/build.gradle#L29-L48)
48. [flutter_inappwebview_android (6.1.5 태그) `JavaScriptBridgeInterface.java`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/JavaScriptBridgeInterface.java#L47)
49. [flutter_inappwebview_android (6.2.0-beta.3 태그) `JavaScriptBridgeInterface.java`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/JavaScriptBridgeInterface.java#L72-L105)
50. [flutter_inappwebview_android (6.1.5 태그) `JavaScriptBridgeJS.java`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/plugin_scripts_js/JavaScriptBridgeJS.java#L9-L16)
51. [flutter_inappwebview_android (6.1.5 태그) `UserContentController.java`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/types/UserContentController.java#L198-L214)
52. [flutter_inappwebview_android (6.1.5 태그) `InAppWebViewClient.java`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/in_app_webview/InAppWebViewClient.java)
53. [flutter_inappwebview_android (6.1.5 태그) `InAppWebView.java`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/in_app_webview/InAppWebView.java#L1888-L1893)
54. [flutter_inappwebview_android (6.1.5 태그) `InAppWebViewChromeClient.java`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/in_app_webview/InAppWebViewChromeClient.java#L836-L841)
55. [flutter_inappwebview_android (6.1.5 태그) `MyCookieManager.java`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/MyCookieManager.java#L173-L215)
56. [flutter_inappwebview_ios (6.1.5 태그) `InAppWebView.swift`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_ios/ios/Classes/InAppWebView/InAppWebView.swift)
57. [flutter_inappwebview_ios (6.1.5 태그) `JavaScriptBridgeJS.swift`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_ios/ios/Classes/PluginScriptsJS/JavaScriptBridgeJS.swift#L13-L19)
58. [flutter_inappwebview_ios (6.2.0-beta.3 태그) `Package.swift`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_ios/ios/flutter_inappwebview_ios/Package.swift)
59. [flutter_inappwebview_ios (6.2.0-beta.3 태그) `HeadlessInAppWebView.swift`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_ios/ios/flutter_inappwebview_ios/Sources/flutter_inappwebview_ios/HeadlessInAppWebView/HeadlessInAppWebView.swift#L41)
60. [flutter_inappwebview_ios (6.2.0-beta.3 태그) `InAppBrowserNavigationController.swift`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_ios/ios/flutter_inappwebview_ios/Sources/flutter_inappwebview_ios/InAppBrowser/InAppBrowserNavigationController.swift#L14)
61. [inappwebview.dev 설치 문서 (6.x)](https://inappwebview.dev/docs/intro/)
62. [flutter_inappwebview stale 워크플로](https://github.com/pichillilorenzo/flutter_inappwebview/blob/master/.github/workflows/stale.yaml)
63. [flutter_inappwebview 커밋 기록](https://github.com/pichillilorenzo/flutter_inappwebview/commits/master/)
64. [flutter_inappwebview 열린 이슈](https://github.com/pichillilorenzo/flutter_inappwebview/issues?q=is%3Aissue%20is%3Aopen)
65. [flutter_inappwebview 열린 PR](https://github.com/pichillilorenzo/flutter_inappwebview/pulls?q=is%3Apr%20is%3Aopen)
66. [flutter_inappwebview 병합 PR (2025-10-19 이후)](https://github.com/pichillilorenzo/flutter_inappwebview/pulls?q=is%3Apr%20is%3Amerged%20merged%3A%3E%3D2025-10-19)
67. [flutter_inappwebview #2754: iOS App rejected by apple for violating Guideline 2.5.1](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2754)
68. [flutter_inappwebview #2765: [Android] Upgrade to AGP 9](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2765)
69. [flutter_inappwebview #2887: Build crash with plugin version 6.1.5, flutter 3.47.2 and AGP 9+](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2887)
70. [flutter_inappwebview #2830: xcode26.4.1 Compilation error](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2830)
71. [flutter_inappwebview #2843: [Android] 6.2.0-beta.3: onWebViewCreated never fires on ~50% of release-build cold starts](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2843)
72. [flutter_inappwebview #2880: Request From Flutter Team: Migrate AppDelegate.window API usage](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2880)
73. [flutter/flutter 열린 `p: webview` 이슈](https://github.com/flutter/flutter/issues?q=is%3Aissue%20is%3Aopen%20label%3A%22p%3A%20webview%22)
74. [flutter/packages 병합 PR (`p: webview_flutter`, 2025-10-19 이후)](https://github.com/flutter/packages/pulls?q=is%3Apr%20is%3Amerged%20label%3A%22p%3A%20webview_flutter%22%20merged%3A%3E%3D2025-10-19)
75. [flutter/flutter #119616: Support to manually dispose a `WebViewController`](https://github.com/flutter/flutter/issues/119616)
76. [flutter/flutter #130297: [webview_flutter] Add support for detecting process termination on Android](https://github.com/flutter/flutter/issues/130297)
77. [flutter/flutter #82682: [webview_flutter] Expose a method to inject bridgeCodeJs template when WebView initial](https://github.com/flutter/flutter/issues/82682)
78. [flutter/flutter #137575: [flutter_webview] addJavascriptInterface applies to all frames](https://github.com/flutter/flutter/issues/137575)
79. [flutter/flutter #191094: [Android] View resize is not synchronized with the IME animation](https://github.com/flutter/flutter/issues/191094)
80. [Android Developers: `WebView.addJavascriptInterface`](https://developer.android.com/reference/android/webkit/WebView#addJavascriptInterface(java.lang.Object,%20java.lang.String))
81. [Android Developers: `WebView.setWebContentsDebuggingEnabled`](https://developer.android.com/reference/android/webkit/WebView#setWebContentsDebuggingEnabled(boolean))
82. [Android Developers: `WebViewClient.shouldOverrideUrlLoading`](https://developer.android.com/reference/android/webkit/WebViewClient#shouldOverrideUrlLoading(android.webkit.WebView,%20android.webkit.WebResourceRequest))
83. [Android Developers: `WebViewClient.onRenderProcessGone`](https://developer.android.com/reference/android/webkit/WebViewClient#onRenderProcessGone(android.webkit.WebView,%20android.webkit.RenderProcessGoneDetail))
84. [Android Developers: `WebChromeClient.onShowFileChooser`](https://developer.android.com/reference/android/webkit/WebChromeClient#onShowFileChooser(android.webkit.WebView,%20android.webkit.ValueCallback%3Candroid.net.Uri[]%3E,%20android.webkit.WebChromeClient.FileChooserParams))
85. [Android Developers: `WebChromeClient.onPermissionRequest`](https://developer.android.com/reference/android/webkit/WebChromeClient#onPermissionRequest(android.webkit.PermissionRequest))
86. [Android Developers: `CookieManager.getCookie`](https://developer.android.com/reference/android/webkit/CookieManager#getCookie(java.lang.String))
87. [Android Developers: androidx.webkit `WebViewCompat.addWebMessageListener`](https://developer.android.com/reference/androidx/webkit/WebViewCompat#addWebMessageListener(android.webkit.WebView,java.lang.String,java.util.Set%3Cjava.lang.String%3E,androidx.webkit.WebViewCompat.WebMessageListener))
88. [Android Developers: androidx.webkit `WebViewCompat.addDocumentStartJavaScript`](https://developer.android.com/reference/androidx/webkit/WebViewCompat#addDocumentStartJavaScript(android.webkit.WebView,java.lang.String,java.util.Set%3Cjava.lang.String%3E))
89. [Android Developers: androidx.webkit `WebViewFeature.isFeatureSupported`](https://developer.android.com/reference/androidx/webkit/WebViewFeature#isFeatureSupported(java.lang.String))
90. [Apple Developer: `WKWebView.allowsBackForwardNavigationGestures`](https://developer.apple.com/documentation/webkit/wkwebview/allowsbackforwardnavigationgestures)
91. [Apple Developer: `WKWebView.isInspectable`](https://developer.apple.com/documentation/webkit/wkwebview/isinspectable)
92. [Apple Developer: `WKNavigationDelegate.webViewWebContentProcessDidTerminate(_:)`](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webviewwebcontentprocessdidterminate%28_%3A%29)
93. [Apple Developer: `WKScriptMessage.frameInfo`](https://developer.apple.com/documentation/webkit/wkscriptmessage/frameinfo)
94. [Apple Developer: `WKFrameInfo.securityOrigin`](https://developer.apple.com/documentation/webkit/wkframeinfo/securityorigin)
95. [Apple Developer: `WKWebViewConfiguration`](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration)
96. [Apple Developer: `WKURLSchemeHandler`](https://developer.apple.com/documentation/webkit/wkurlschemehandler)
97. [Apple Developer: `WKUserContentController.addUserScript(_:)`](https://developer.apple.com/documentation/webkit/wkusercontentcontroller/adduserscript%28_%3A%29)
98. [Apple Developer: `WKUIDelegate.webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)`](https://developer.apple.com/documentation/webkit/wkuidelegate/webview%28_%3Arequestmediacapturepermissionfor%3Ainitiatedbyframe%3Atype%3Adecisionhandler%3A%29)
99. [Apple Developer: `NSCameraUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nscamerausagedescription)
100. [WebKit 소스: `WKFileUploadPanel.mm` (iOS 업로드 패널, main 브랜치)](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/ios/forms/WKFileUploadPanel.mm)
101. [Flutter 문서: Swift Package Manager for app developers](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)
102. [Flutter 문서: Migrate to UIScene (breaking change)](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)
103. [Flutter 3.47.7 `FlutterExtension.kt` (기본 minSdk)](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt#L23-L34)
104. [Flutter 3.47.7 iOS 앱 템플릿 `project.pbxproj.tmpl`](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_tools/templates/app/ios.tmpl/Runner.xcodeproj/project.pbxproj.tmpl#L383)
105. [이 저장소 `app/android/settings.gradle.kts` (AGP 9.1.0)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/explore/real-world-example/app/android/settings.gradle.kts#L22)
106. [이 저장소 `app/pubspec.lock` (webview_flutter 4.14.1)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/explore/real-world-example/app/pubspec.lock)
107. [이 저장소 `app/lib/bridge/stage_c_bridge.dart` (Demo Stage C의 Call 응답)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/explore/real-world-example/app/lib/bridge/stage_c_bridge.dart#L90-L92)
108. [flutter_inappwebview_android (6.2.0-beta.3 태그) `InAppWebView.java` (브리지 스크립트에 비밀 토큰 주입)](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/in_app_webview/InAppWebView.java#L596-L608)
109. [flutter_inappwebview_ios (6.2.0-beta.3 태그) `WebAuthenticationSession.swift`](https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_ios/ios/flutter_inappwebview_ios/Sources/flutter_inappwebview_ios/WebAuthenticationSession/WebAuthenticationSession.swift#L92-L95)
