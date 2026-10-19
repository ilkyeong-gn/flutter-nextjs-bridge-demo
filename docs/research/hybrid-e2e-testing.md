# Host–Web 통합 테스트 자동화 조사

- **질문**: [#37 Host–Web 통합 테스트 자동화 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/37)
- **조사일**: 2026-10-19
- **확인한 버전**: Flutter 3.47.7 stable(공식 문서는 3.47 기준) · webview_flutter 4.14.1(webview_flutter_android 4.14.1, webview_flutter_wkwebview 3.27.0) · Patrol 4.10.0 / patrol_cli 4.8.0 · Maestro CLI 2.11.0 · Appium 3.8.0(UiAutomator2 드라이버 8.7.0, XCUITest 드라이버 12.19.0, appium-flutter-driver 4.0.0, appium-flutter-integration-driver 2.0.3) · Playwright 1.64.1 · Next.js 16.4.0 · Vitest 5.0 · Ajv 8.20.0 · json_schema(Dart) 5.2.2 · pact_dart 0.8.0 · GitHub Actions macOS 26 arm64 이미지 20260907

이 문서는 결정 티켓 [#47 테스트 전략 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/47)의 입력이다. 사실과 선택지만 정리하고 결정은 하지 않는다.

## 요약

- **WebView 안은 Flutter 테스트의 finder로 보이지 않는다.** `integration_test`는 Host 화면만 다루고, WebView 안을 다루게 해 달라는 요청은 2021년부터 열려 있다. 테스트가 `WebViewController`를 쥐면 `runJavaScript`로 Web을 조작하고 검사할 수는 있다(webview_flutter가 자기 통합 테스트에서 쓰는 방식). 하지만 실제 터치와 OS UI(권한 대화상자, OS 알림)는 이 방법으로 검증하지 못한다.
- **Flutter 밖에서 WebView 안을 다루는 도구는 두 계열이다.** OS 접근성 트리로 요소를 찾아 누르는 Patrol·Maestro(기본 모드)와, 디버깅 프로토콜로 DOM에 붙는 Appium `WEBVIEW` 컨텍스트·Playwright Android다. 접근성 계열은 앱 변경이 적지만, WebView나 OS 버전이 바뀌어 깨진 사례가 2026년에도 열려 있다. 디버깅 계열은 CSS 선택자로 정확하지만, Android는 디버깅 가능한 WebView가, iOS는 Host가 켜 주는 `isInspectable`이 필요하다.
- **iOS와 Android는 막히는 곳이 다르다.** Patrol 기능표는 WebView 조작을 iOS ✅, Android ⚠️로 적는다. Playwright는 Android WebView에만 실험적으로 붙는다. Appium은 둘 다 되지만 Android는 WebView 버전에 맞는 Chromedriver가 필요하다.
- **분할 전략의 씨앗은 이미 있다.** Vitest는 `window.FlutterBridge`를 `vi.fn`으로, Flutter 테스트는 원시 JSON 문자열과 가짜 `runJavaScript`로 상대를 흉내 낸다. 다음 단계는 Playwright의 `addInitScript`·`exposeBinding`으로 만든 가짜 Host, 그리고 webview_flutter의 테스트 시임(`WebViewPlatform.instance`, `WebViewController.fromPlatform`)에 끼운 가짜 Web이다. 실제 엔진 위의 전송(채널 이름, 전역 함수, 반환 타입)은 작은 HTML을 띄운 통합 테스트나 E2E만 확인할 수 있다.
- **지금 두 테스트 묶음은 계약을 공유하지 않는다.** 같은 봉투를 양쪽이 각자 리터럴로 적고 있어서, 한쪽이 바뀌어도 다른 쪽 테스트는 통과한다. 가장 가벼운 해법은 양쪽이 같은 JSON 픽스처 파일을 읽는 것이고, JSON Schema를 더하면 Ajv(TS)와 json_schema(Dart)로 같은 스키마를 검증할 수 있다. Pact는 Dart 구현의 메시지 계약 지원이 아직 작업 중이라 Host 쪽에 쓰기 어렵다.
- **CI 비용은 저장소 공개 여부와 iOS가 좌우한다.** 공개 저장소는 macOS를 포함한 표준 GitHub 호스트 러너가 무료다. 비공개 저장소라면 macOS는 분당 $0.062로 Linux 2코어($0.006)의 약 10배다. iOS 시뮬레이터는 macOS 러너에서만 돌고, Android 에뮬레이터는 KVM이 되는 Linux 러너가 맞으며 arm64 macOS 러너에서는 뜨지 않는다.
- **기기 클라우드는 유료이고, 하나는 종료 예정이다.** Maestro Cloud는 기기당 월 $250이다. Firebase Test Lab은 가상 기기 시간당 $1, 실기기 시간당 $5인데 2027-09-30에 종료될 예정(deprecated)이고 iOS는 실기기만 지원한다.
- **도구 제작자도 WebView E2E는 드물게 돌린다.** Patrol 저장소는 iOS WebView E2E를 월 1회, Android WebView E2E를 외부 에뮬레이터 클라우드에서 매일 돌린다. 에뮬레이터의 오래된 WebView 때문에 테스트 기기를 API 31에서 35로 올리기도 했다.

## 상세

### 1. `integration_test`의 한계와 도구별 WebView 지원

#### 1.1 Flutter `integration_test`

- Flutter 공식 문서(2026-09-29 갱신, Flutter 3.47 기준)는 iOS와 Android 모두 `flutter test integration_test/<이름>_test.dart`로 실행하라고 안내하지만, WebView나 platform view 안을 다루는 방법은 싣지 않는다 [1]. `integration_test`는 실기기와 에뮬레이터에서 Flutter 코드를 스스로 구동하고, 결과를 `flutter drive`와 Android instrumentation 형식으로 바꿔 준다 [2].
- finder는 Flutter 위젯 트리만 본다. "WebView 안의 요소를 찾을 수 없다"는 기능 요청 #86295가 2021-07부터 P3 제안으로 열려 있다 [3]. 2024년의 on-device 테스트 개선 제안 #148028도 "스크린숏 말고 플랫폼 위젯을 찾고 상호작용하기"를 지금은 못 하는 일로 꼽았다. 이 제안은 구체적인 작업 없이 2024-09에 닫혔다 [4].
- 우회로는 테스트가 `WebViewController`를 직접 쥐는 것이다. webview_flutter의 통합 테스트는 로컬 `HttpServer`와 `loadHtmlString`으로 페이지를 띄우고, `runJavaScriptReturningResult`로 DOM 값을 읽고, `addJavaScriptChannel`로 페이지가 보낸 메시지를 받는다 [5]. 이 방법은 실제 터치와 스크롤 경로를 거치지 않는다. iOS에서는 일부 비원시 타입과 (iOS 14 이상에서) `null`·`undefined`를 반환하면 오류가 난다 [6].
- Android에서 `IntegrationTestWidgetsFlutterBinding`으로 돌리면 WebView가 가끔 화면에 나타나지 않는 버그 #130872(P2)가 열려 있다 [7]. 2023년 Flutter 3.10과 3.13에서 재현된 보고라 3.47에서도 그런지는 확인하지 못했다.

#### 1.2 Patrol

- Patrol은 Flutter의 `integration_test` 플러그인을 바탕으로, OS 상호작용을 더해 그 한계를 넘으려는 Dart E2E 프레임워크다 [8]. 앱 옆에 별도 instrumentation을 띄워 Android는 UIAutomator, iOS는 XCTest로 실제 뷰 계층에 접근하고, Dart 테스트가 그 프로세스와 통신한다(제작자 설명) [9]. 공식 문서는 WebView나 OAuth로 로그인하기, 권한 허용, 알림 탭을 `integration_test`로는 할 수 없는 일로 든다 [10].
- WebView는 접근성 선택자로 조작한다. Patrol 자체 E2E는 `$.platform.mobile.tap(Selector(text: ...))`와 `MobileSelector(android: AndroidSelector(text: ...), ios: IOSSelector(label: ...))`로 WebView 속 문서 사이트를 조작한다 [11]. Web 요소를 텍스트와 접근성 이름으로 찾는다는 뜻이다.
- 기능표는 WebView 조작을 iOS ✅, Android ⚠️(#244)로 적는다. 권한 대화상자, URL 열기, 알림 열기와 탭, 카메라 촬영, 갤러리 선택은 두 플랫폼 모두 ✅다 [12].
- Android 쪽 문제는 둘이다. #244는 Android 접근성 트리에 WebView 내용이 나타나지 않던 문제로, Android 10(API 29)부터는 "꽤 안정적"이지만 그 아래 버전에서는 항상 실패한다고 정리돼 있다 [13]. #3178(P2, 열림)은 Patrol 4.x가 쓰는 uiautomator 2.3.0이 켜는 접근성 플래그 때문에 일부 앱에서 WebView 하위 노드가 사라진다는 보고다. 단순한 WebView에서는 재현되지 않았고, uiautomator 2.2.0으로 고정하는 우회책이 공유됐다 [14].
- `$.native`와 `$.native2`는 deprecated이고 `$.platform`으로 옮겨 가는 중이다. 2026-06에 Patrol은 불안정하던 WebView E2E 중복본을 지웠고, API 31 에뮬레이터의 오래된 WebView에서 페이지가 클라이언트 오류를 내서 테스트 기기를 API 35로 올렸다 [15].
- Patrol 자체 CI는 iOS WebView 테스트를 `macos-latest`에서 월 1회 돌린다(타임아웃 40분, iOS 26.2 시뮬레이터) [16]. Android WebView 테스트는 emulator.wtf에서 매일, 그리고 관련 PR마다 돌린다 [17]. 두 워크플로 모두 Flutter 3.38.x로 고정돼 있다.
- 4.10.0이 2026-09-15에 나왔고, 2026년에는 거의 매달 마이너 릴리스가 있었다 [18]. 최소 Flutter 버전은 3.32다 [19]. Apache-2.0 오픈소스이고, 유료는 도입과 교육 서비스뿐이다 [20].

#### 1.3 Maestro

- YAML 플로로 쓰는 블랙박스 도구다. iOS에서는 접근성 계층을 통해 Xcode 시뮬레이터를 조작한다 [21]. Flutter 앱은 `pubspec.yaml` 의존 없이 Semantics 트리로 다루고, 텍스트, `semanticLabel`, `Semantics` 위젯, `identifier`(Flutter 3.19 이상)로 요소를 찾는다 [22].
- WebView에 대해 공식 Known issues는, WebView 속 웹 콘텐츠가 Maestro가 의존하는 OS 접근성 API로 충분히 드러나지 않을 수 있다고 적는다. 우회책은 플로 맨 위에 `androidWebViewHierarchy: devtools`를 넣어 Chrome DevTools로 계층을 읽게 하는 것이고, Android 전용이다 [23]. 이 옵션은 1.40.0에 들어왔고 2.6.0부터 2.9.0까지 연이어 고쳐졌다. 2.1.0에는 "iOS 26에서 WebView 감지와 상호작용 수정"이 있다 [24]. 2026년에는 거의 매달 릴리스가 나왔다 [25].
- 2026년에 열려 있는 WebView 관련 이슈는 셋이다. Android System WebView 148 이상에서 `devtools` 모드가 실패한다 [26]. WebView 150 이상에서 텍스트 입력이 이름 없이 노출돼 매칭되지 않는다 [27]. iOS 26에서 HTML 요소 id가 노출되지 않는다(Safari로 재현된 보고) [28].
- Host 기능과 관련된 명령도 있다. `openLink`는 앱이나 시스템 브라우저로 URL과 딥 링크를 연다 [29]. `addMedia`는 갤러리에 사진과 영상을 넣는다 [30]. 실행할 때나 플로 중간에 권한을 설정할 수 있다 [31].
- CLI는 무료 오픈소스이고 Maestro Cloud는 기기당 월 $250이다 [32]. 플로 안의 JavaScript는 Maestro의 격리된 엔진(GraalJS)에서 돌기 때문에 WebView 페이지 안의 상태를 직접 읽지는 못한다 [33].

#### 1.4 Appium의 `WEBVIEW` 컨텍스트

- Appium은 세션을 `NATIVE_APP`과 `WEBVIEW_*` 컨텍스트로 나눈다. `WEBVIEW` 컨텍스트로 바꾸면 드라이버는 평소의 요소 찾기와 조작 대신 웹 콘텐츠를 상대한다 [34].
- **Android**(UiAutomator2 드라이버 8.7.0): `WEBVIEW` 컨텍스트로 바꾸면 Chromedriver를 띄워 명령을 넘긴다. WebView가 디버깅 가능하게 설정돼 있어야 컨텍스트 목록에 나타나고, Chromedriver 버전은 WebView 엔진 버전과 맞아야 한다 [35]. Android 문서에 따르면 WebView 113 이상에서는 `android:debuggable` 앱이면 WebView 디버깅이 자동으로 켜지고, 아니면 기본값이 false다. 운영 빌드에서 켜는 것은 보안 위험이라고 경고한다 [36]. webview_flutter에서는 `AndroidWebViewController.enableDebugging`으로 명시적으로 켤 수 있다 [37].
- **iOS**(XCUITest 드라이버 12.19.0): 원격 디버거로 WebKit 디버그 소켓에 붙고, 이 컨텍스트에서는 `findElement`가 WebView의 DOM을 찾는다. WKWebView의 `isInspectable`이 true여야 하고, 실기기는 Safari Web Inspector 설정도 켜야 한다. 문서는 이를 위해 "앱 소스에 접근할 수 있어야 한다"고 적는다 [38]. `isInspectable`은 iOS 16.4에 생겼고 기본값은 false다. 시뮬레이터에서는 Web Inspector가 늘 켜져 있다 [39]. webview_flutter에서는 `WebKitWebViewController.setInspectable`로 켠다 [40]. 이 컨텍스트의 명령은 기본적으로 Selenium atom 스크립트를 주입해 실행된다. 실제 W3C Actions는 시뮬레이터 전용 WebKit Automation 세션에서만 쓸 수 있는데, 지금은 불안정하다고 적혀 있다 [38].
- **Host 화면**은 별도 드라이버로 다룬다. appium-flutter-driver 4.0.0은 `FLUTTER` 컨텍스트로 Dart VM에 붙는데, 앱에 `flutter_driver`와 `enableFlutterDriverExtension`을 넣고 debug나 profile로 빌드해야 한다 [41]. `integration_test` 기반인 appium-flutter-integration-driver 2.0.3은 앱에 `appium_flutter_server`를 넣는 방식이고, 저장소의 마지막 push가 2025-10이다 [42].
- 테스트는 WebDriver 클라이언트가 있는 어떤 언어로든 쓸 수 있다 [35][42]. 그 대가로 Appium 서버, 플랫폼별 드라이버, Chromedriver 버전을 운영해야 한다 [35].

#### 1.5 Playwright를 기기에 붙이는 경우

- Playwright는 Chrome for Android와 Android WebView를 대상으로 하는 실험적 Android 자동화를 제공하며, ADB가 필요하다 [43]. `androidDevice.webView({ pkg })`로 WebView를 잡아 일반 Page처럼 다룬다 [44]. 구현은 기기의 `webview_devtools_remote` 소켓을 찾아 붙으므로 WebView 디버깅이 켜져 있어야 한다 [45][36]. Host 화면은 조작하지 못한다.
- iOS 실기기와 시뮬레이터는 지원하지 않는다. 2020년에 열린 이슈 #1122로 추적 중이다 [46].

#### 1.6 비교와 iOS·Android 차이

| 도구 (확인 버전) | Host 화면(Flutter) | WebView: Android | WebView: iOS | CI 비용·인프라 | 성숙도 |
|---|---|---|---|---|---|
| `integration_test` (Flutter 3.47) | finder ✅ | finder ✗ [3], JS 주입 ✅ [5], 표시 버그 #130872 열림 [7] | finder ✗, JS 주입 ✅, `null`·`undefined` 반환 불가 [6] | 시뮬레이터·에뮬레이터만 필요, 도구 비용 없음 | Flutter SDK 동봉 [2]. WebView 조작 요청은 2021년부터 열림 [3] |
| Patrol 4.10.0 | finder ✅ | 접근성 선택자 ⚠️ [12], 열린 버그 #3178 [14] | 접근성 선택자 ✅ [12] | 위와 같음, Patrol 러너 설정 추가. 도구 무료 [20] | 2022년부터 개발 [8]. 2026년 거의 매달 릴리스 [18]. `$.platform`으로 API 이행 중 [15] |
| Maestro CLI 2.11.0 | Semantics 라벨·`identifier` 필요 [22] | 접근성, `devtools` 모드 [23], WebView 148+·150+ 이슈 열림 [26][27] | 접근성, iOS 26 HTML id 미노출 보고 [28] | CLI 무료. Cloud는 기기당 월 $250 [32] | 앱 코드 의존 없음 [22]. 2026년 거의 매달 릴리스 [25] |
| Appium 3.8.0 (UiAutomator2 8.7.0, XCUITest 12.19.0) | appium-flutter-driver: `flutter_driver`, debug·profile 빌드 [41] | `WEBVIEW` 컨텍스트, Chromedriver 버전 일치 [35] | `WEBVIEW` 컨텍스트, `isInspectable` 필요 [38] | 도구 무료. 서버·드라이버·Chromedriver 운영 부담 [35] | W3C WebDriver 기반 [35]. Flutter용 integration 드라이버는 2025-10 이후 push 없음 [42] |
| Playwright 1.64.1 | ✗ | 실험적 `_android`로 연결 [43] | ✗ (#1122) [46] | 브라우저만 쓰면 Linux 러너로 충분 | Android 지원은 문서상 실험적 [43] |

iOS와 Android의 차이를 경로별로 정리하면 이렇다.

- **접근성 경로**(Patrol, Maestro 기본): Android는 UIAutomator 접근성 트리에 WebView 내용이 늦게 나오거나 아예 안 나오는 문제가 반복해서 보고됐다 [13][14][27]. iOS는 Patrol 기능표상 ✅이지만, iOS 26에서 HTML id가 접근성 트리에 안 보인다는 보고가 있다 [12][28].
- **디버깅 프로토콜 경로**(Appium, Maestro `devtools`, Playwright `_android`): Android는 Chrome DevTools 프로토콜이고, 디버그 빌드면 WebView 113 이상에서 자동으로 열린다 [36]. 대신 Chromedriver 버전을 맞춰야 하고 [35], WebView 148 이상에서 깨진 사례가 있다 [26]. iOS는 Web Inspector 원격 디버거이고, Host가 `isInspectable`을 켜야 하며 [38][39], 이 경로를 쓰는 도구는 Appium뿐이다.
- **JS 주입 경로**(`integration_test`, Patrol 안에서도 가능): 두 플랫폼 모두 되지만 iOS는 반환 타입 제약이 있고 [6], Android는 #130872가 열려 있다 [7].

### 2. 분할 전략: 가짜 Host로 Web을, 가짜 Web으로 Host를

#### 2.1 저장소의 현재 테스트

- **Web**(Vitest + jsdom, README 기준 35개): `window.FlutterBridge = { postMessage: vi.fn(...) }`로 Host를 흉내 낸다. Call 응답은 `window.__onFlutterResponse(...)`로, Event는 `window.dispatchEvent(new CustomEvent('flutter:event', ...))`로 넣는다(`web/src/lib/bridge/__tests__/stageC.test.ts`, `web/src/app/stage-c/__tests__/page.test.tsx`).
- **Host**(`flutter test`, README 기준 28개): 원시 JSON 문자열을 핸들러에 넣고, 가짜 `runJavaScript` 콜백으로 받은 JS 문자열을 비교한다. WebView 자리는 `HostApp(webViewWidget: SizedBox(...))`로 비워 둔다(`app/test/stage_c_bridge_test.dart`, `app/test/widget_test.dart`).
- 단위 수준의 분할은 이미 있다. 빠진 것은 실제 브라우저 엔진, 실제 `WebViewController` 배선, 그리고 양쪽이 같은 계약을 쓰는지 확인하는 장치(3장)다.

#### 2.2 Web: Playwright와 가짜 Host

- `page.addInitScript`는 문서가 만들어진 직후, 페이지 스크립트보다 먼저 실행된다. `page.exposeBinding`과 `exposeFunction`은 모든 프레임의 `window`에 Promise를 돌려주는 함수를 붙이고, 이 함수는 페이지를 이동해도 남는다 [47]. Playwright는 브라우저에 없는 API를 이렇게 흉내 내고 호출을 기록하는 방법을 공식 가이드로 안내한다 [48].
- Bridge에 대입하면 이렇다. init script로 `window.FlutterBridge.postMessage`를 심고, 노출 함수로 넘겨 Message와 Call 요청을 기록한다. Call 응답은 픽스처로 `window.__onFlutterResponse(...)`를 부른다. Event는 `page.evaluate`로 Host가 `runJavaScript`로 보내는 것과 같은 `CustomEvent`를 발생시킨다 [47].
- 엔진은 Chromium, WebKit, Firefox를 쓸 수 있다. 다만 Playwright의 WebKit은 WebKit main 브랜치로 만든 자체 빌드라 Safari와 같지 않고, mac에서 돌릴 때 Safari에 가장 가깝다 [49]. 기기 프로필은 UA, 뷰포트, 터치 같은 값을 흉내 낼 뿐이다 [50]. WKWebView와 Android WebView에만 있는 동작은 이 층에서 보장되지 않는다.
- Next.js는 async Server Component를 단위 테스트 도구가 아직 다 지원하지 못하니 E2E로 검증하라고 권하고 [51], E2E는 프로덕션 빌드(`next build` 후 `next start`)에 대고 돌리라고 권한다 [52]. Vitest가 덮지 못하는 부분을 이 층이 덮는다.

#### 2.3 Host: Flutter 테스트와 가짜 Web

- `flutter test`는 헤드리스 `flutter_tester`에서 돌고 platform channel 같은 확장 지점이 막혀 있어서 실제 WebView가 없다 [4]. webview_flutter는 이 상황을 위한 시임을 공식으로 열어 둔다. 플랫폼 구현이 없으면 "단위 테스트에서는 `WebViewPlatform.instance`에 직접 만든 테스트 구현을 넣으라"는 assert가 뜬다 [53]. 패키지 자체 단위 테스트는 `WebViewController.fromPlatform(mock)`으로 컨트롤러를 만든다 [54].
- 이 시임으로 세 층을 만들 수 있다.
  1. **핸들러 단위 테스트**: 지금 방식이다.
  2. **가짜 플랫폼 위젯 테스트**: 가짜 `PlatformWebViewController`가 등록된 JS 채널 콜백에 픽스처 문자열을 넣어 Web의 Message와 Call을 흉내 낸다. 그리고 `runJavaScript`로 나가는 Event와 Call 응답을 기록한다. platform view 없이 Host의 실제 컨트롤러 배선까지 검증한다.
  3. **실제 WebView와 작은 가짜 Web**: webview_flutter의 통합 테스트처럼 `loadHtmlString`이나 로컬 서버로 작은 HTML을 띄우고, 채널과 `runJavaScriptReturningResult`로 왕복을 확인한다 [5]. Next.js 없이 iOS와 Android의 실제 엔진에서 채널 이름, 전역 함수, 반환 타입 같은 전송 계층을 확인할 수 있다.

#### 2.4 E2E에만 남는 것

실제 Host, Web, 엔진이 만나야만 드러나는 것이 남는다. Bridge 주입 시점과 페이지 로드 순서, Web 화면과 Host 화면 사이의 이동과 복귀, OS UI(권한, 사진 선택기, OS 알림, 외부 브라우저), Host와 Web의 세션 공유다.

### 3. 공유 픽스처와 스키마로 양쪽 계약 맞추기

#### 3.1 현재 상태

- 같은 봉투가 양쪽 테스트에 따로 적혀 있다. Dart 테스트는 `window.__onFlutterResponse({"id":"call-100","result":{...}});` 문자열 전체를 비교하고, TS 테스트는 같은 모양의 객체를 `window.__onFlutterResponse`에 넣는다. 전송 이름도 Web은 `FLUTTER_EVENT_NAME` 상수로, Host는 `"flutter:event"` 리터럴로 따로 갖고 있다.
- Host → Web 방향은 JSON이 아니라 `runJavaScript`로 실행할 JS 코드다. 그래서 계약에는 payload 모양뿐 아니라 채널 이름(`FlutterBridge`), 이벤트 이름, 전역 함수 이름(`__onFlutterResponse`) 같은 전송 이름도 들어간다.

#### 3.2 선택지

- **A. 공유 픽스처 파일.** Message, Event, Call(요청, 성공 응답, 실패 응답)마다 JSON 예시와 거부돼야 할 예시를 한곳에 두고, Vitest와 `flutter test`가 같은 파일을 읽는다. 양쪽은 "이 픽스처를 해석할 수 있다"와 "내가 만든 출력이 픽스처와 같다"를 확인한다. `flutter test`는 호스트의 Dart VM에서 돌아서 `dart:io`를 쓸 수 있다(저장소의 Stage C 테스트가 이미 `dart:io`의 `Platform` 값을 쓴다). 같은 픽스처를 Playwright 가짜 Host의 응답과 Flutter 가짜 Web의 입력으로도 쓰면 가짜 상대들이 한 원천을 공유한다.
- **B. 픽스처와 JSON Schema.** 스키마로 픽스처와 실제 출력을 함께 검증한다. Ajv는 draft-06과 draft-07을 기본으로, 2019-09와 2020-12를 별도 export로 지원한다 [55]. Dart의 json_schema는 Flutter를 포함한 모든 Dart 환경에서 쓸 수 있고 [56], 4.0부터 2019-09와 2020-12를 지원하며 기본값은 draft7이다 [57]. 같은 스키마로 런타임 검증까지 할지는 보안 모델(#41)과 이어진다.
- **C. 스키마 단일 원천과 코드 생성.** 타입까지 생성하면 A와 B의 검사는 회귀 방지용으로 줄어든다. 이 선택지는 [#30](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/30)(조사)과 [#40](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/40)(결정)에서 다룬다.
- **D. Pact.** 소비자 주도 계약 도구다. JS는 비동기 메시지 계약과, HTTP를 거치지 않는 요청·응답인 동기 메시지 계약을 지원한다 [58]. 하지만 Dart 구현인 pact_dart는 커뮤니티 패키지이고, HTTP 계약만 지원하며 비동기 메시지 계약은 작업 중이다 [59]. Pact 공식 구현 목록에도 Dart는 없다 [60]. Host 쪽 검증을 Pact로 하기는 어렵다.
- **E. AsyncAPI.** 메시지 기반 API를 프로토콜과 무관하게 기계가 읽는 형식으로 기술하고, payload를 JSON Schema(draft-07의 상위집합)로 적는다 [61]. 최신은 3.1.0(2026-01)이다 [62]. Event와 Call 목록을 문서화하는 데 맞을 수 있지만, 이 용도로 쓸 Dart·TS 도구의 품질은 확인하지 못했다.

### 4. 시뮬레이터·에뮬레이터를 CI에서 돌리는 비용

#### 4.1 GitHub Actions

- 공개 저장소의 표준 GitHub 호스트 러너는 무료다 [63]. 이 저장소는 공개라서 macOS 러너를 써도 분 비용이 없다.
- 비공개 저장소는 플랜별 포함 분(Free 2,000분, Pro·Team 3,000분, Enterprise Cloud 50,000분)을 넘으면 분당 요금을 낸다. Linux 2코어는 $0.006, macOS 3·4코어는 $0.062, Linux 4코어(larger)는 $0.012다 [63][64].
- 공개 저장소에서는 표준 러너를 무제한으로 쓸 수 있고, `ubuntu-latest`는 4코어·16GB, `macos-latest`(macOS 26 arm64)는 M1 3코어·7GB다. 비공개 저장소의 Linux는 2코어·8GB다 [65]. macOS 26 arm64 이미지(20260907)에는 Xcode 26.x와 iOS 26.2·26.4·26.5 시뮬레이터가 들어 있다 [66].
- Android 에뮬레이터는 2024-04부터 2코어 표준 Linux 러너에서도 udev 규칙 한 단계로 KVM 하드웨어 가속을 쓸 수 있다 [67]. 2023년 발표에 따르면 가속을 쓴 4코어 Linux는 가속이 없을 때보다 2–3배, macOS보다 약 2배 빨랐다 [68]. android-emulator-runner도 macOS보다 빠르고 싼 Ubuntu 러너를 권한다 [69]. arm64 macOS 러너는 Apple Virtualization Framework 제약으로 중첩 가상화를 지원하지 않는다 [65]. 실제로 그 러너에서 에뮬레이터가 `HV_UNSUPPORTED`로 뜨지 않는다는 이슈가 열려 있고, Intel 러너(`macos-15-intel`)에서는 동작했다는 보고가 있다 [70].
- Patrol 문서는 기본 GitHub 러너의 Android 에뮬레이터가 느리고 불안정했으며 iOS 시뮬레이터는 안정적이었다고 적는다 [71]. 작성 시점이 불분명하고, 2024년 KVM 확대 이전의 경험일 수 있다.

#### 4.2 기기 클라우드

- Firebase Test Lab은 Spark 플랜에서 하루 가상 기기 10회·실기기 5회, Blaze 플랜에서 가상 기기 시간당 $1·실기기 시간당 $5다(분 단위 올림) [72]. iOS는 실기기만 지원한다 [73]. 2027-09-30에 완전히 종료될 예정(deprecated)이고, Google Cloud의 Developer Device Platform으로 옮기라고 안내한다 [74][75]. Flutter 공식 문서와 `integration_test` README는 아직 Test Lab 절차를 싣고 있다 [1][2].
- Maestro Cloud는 기기당 월 $250이다 [32]. Patrol 문서는 emulator.wtf(Android 에뮬레이터 전용), SauceLabs(에뮬레이터·시뮬레이터·실기기), AWS Device Farm을 소개한다 [71].

#### 4.3 예시 계산 (비공개 저장소 가정)

잡 길이는 가정이다. 이 저장소에서 빌드, 부팅, 실행 시간을 재지 않았다.

| 잡 | 1회 | 월 100회 |
|---|---|---|
| iOS 시뮬레이터 E2E 30분, macOS 러너 | 30 × $0.062 = $1.86 | $186 |
| Android 에뮬레이터 E2E 30분, Linux 2코어 | 30 × $0.006 = $0.18 | $18 |
| Android 가상 기기 30분, Firebase Test Lab | $0.50 | $50 |
| Web Playwright와 Host `flutter test` 10분, Linux 2코어 | $0.06 | $6 |

## Reference App에 주는 시사점

[#47 테스트 전략 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/47)이 저울질할 선택지와 그 대가를 정리한다. 여기서 고르지는 않는다.

**E2E 도구**

| 선택지 | 얻는 것 | 치르는 것 |
|---|---|---|
| `integration_test`와 JS 주입만 | 새 도구가 없다. Dart 하나로 두 플랫폼의 실제 엔진에서 Bridge 왕복을 확인한다 | 실제 터치와 OS UI를 검증하지 못한다(S2·S3 일부). 테스트가 컨트롤러에 닿는 훅이 필요하다. Android #130872 |
| Patrol | 위의 전부에 OS UI(권한, 사진, URL 열기, OS 알림)가 더해진다 [12]. Dart 하나 | Android WebView 조작의 불안정 이력과 열린 버그 [13][14]. Patrol 러너 설정과 API 이행을 따라가야 한다 [15] |
| Maestro | 앱 코드 변경이 가장 적고 YAML로 빨리 쓴다 [22] | Host 화면에 Semantics가 필요하다. WebView 매칭이 Chromium과 iOS 변화에 흔들린다 [26][27][28]. 페이지 안 상태를 직접 읽지 못한다 [33] |
| Appium | DOM 선택자로 정밀하게 다루고 언어를 고를 수 있다 | 구성이 가장 무겁다. Chromedriver 버전을 관리해야 한다. iOS는 Host가 inspectable을 켜야 한다. Host 화면은 `flutter_driver`에 의존하는 드라이버로 다룬다 |

Patrol 테스트도 `integration_test` 위에서 돌기 때문에 [8], 같은 테스트 안에서 JS 주입을 섞을 수 있다(구조상 가능하다고 보지만 직접 확인하지 않았다).

**E2E 범위와 빈도.** 시나리오마다 행복 경로 하나, Bridge 스모크만, 넓게 중에서 고른다. 넓을수록 불안정 요소와 macOS 시간이 늘어난다. Patrol 저장소도 iOS WebView E2E는 월 1회만 돌린다 [16].

**분할 층.** Web은 Playwright 가짜 Host를 지도의 "개발용 가짜 Host"와 같은 모듈로 쓸지, 테스트 전용으로 따로 둘지 정해야 한다. Host는 핸들러 단위 테스트만 둘지, 가짜 플랫폼 위젯 테스트까지 갈지, 실제 WebView 전송 테스트까지 둘지 정해야 한다.

**계약 장치.** 공유 픽스처만 둘지, 픽스처와 JSON Schema를 함께 둘지, 스키마 단일 원천과 코드 생성(#30·#40)으로 갈지 고른다. Pact는 Dart 쪽 한계가 있다.

**실행 장소.** GitHub 호스트 러너(이 저장소는 무료, iOS는 macOS, Android는 Linux와 KVM), 기기 클라우드(유료, Firebase Test Lab은 종료 예정), 로컬 수동 절차만 두기 중에서 고른다. 트리거도 PR마다, main 반영 후, 야간이나 수동 중에서 고른다.

**도구 선택이 Host와 Web에 요구하는 것**

- 디버깅 프로토콜 계열을 쓰면 테스트 빌드에서 Android WebView 디버깅과 iOS `isInspectable`을 켜고 운영 빌드에서는 꺼야 한다. Android 문서가 운영 빌드에서 켜는 것을 보안 위험으로 경고하므로 보안 모델(#41)과 함께 정해야 한다 [36][39].
- 접근성 계열을 쓰면 Web 요소에 안정적인 텍스트와 접근성 이름이 필요하다. iOS 26에서 HTML id가 안 보인다는 보고가 있다 [28]. Maestro를 쓰면 Host 화면에 Semantics `identifier`를 붙여야 한다 [22].
- JS 주입 계열을 쓰면 테스트가 `WebViewController`에 닿을 경로가 필요하다.
- CI에서 E2E를 돌리려면 Web과 가짜 API 서버를 함께 띄워야 한다. Next.js는 프로덕션 빌드에 대고 돌리기를 권하고 [52], Android 에뮬레이터는 `10.0.2.2`로 접속한다(현재 `app/lib/config.dart`).
- 에뮬레이터 이미지의 WebView 버전이 결과를 바꾼다(Patrol의 API 31→35 [15], Maestro의 WebView 148+·150+ 이슈 [26][27]). 시스템 이미지를 고정할지 정해야 한다.

**S1–S5가 요구하는 도구 능력**

| 시나리오 | 분할 테스트로 덮을 수 있는 부분 | E2E에서만 확인되는 부분 | 필요한 도구 능력 |
|---|---|---|---|
| S1 로그인과 세션 | 로그인 요구와 복귀 경로, 세션 만료 Event 처리 | Host와 Web의 세션 공유, 동시 로그아웃 | Host 화면과 WebView 조작 |
| S2 사진·영상 첨부 | Call 요청과 응답, 개수·용량 검증, 진행률 UI | 권한 거부, 사진 선택기, 이탈 확인 | OS 권한 대화상자와 갤러리 [12][30][31] |
| S3 공유 링크와 알림 | 링크와 화면의 대응, 허용 목록 판정 | 앱이 꺼져 있을 때와 켜져 있을 때의 진입, 시스템 브라우저 전환 | URL 열기 [12][29], OS 알림 [12] |
| S4 멤버 전용 글 | 멤버십 Event에 따른 잠금 갱신 | Host 이미지 뷰어(Host 화면) 왕복 | Host 화면과 WebView 조작 |
| S5 Web과 Host 화면 왕복 | 상태 보존 로직, 안 읽은 수 Event | 실제 이동 뒤 스크롤과 상태 유지 | Host 화면과 WebView 조작, 뒤로가기 |

## 확인하지 못한 것과 새로 생긴 질문

**확인하지 못한 것**

- 이 저장소의 Host에 어떤 E2E 도구도 실제로 붙여 보지 않았다. 특히 Flutter 3.47과 webview_flutter 4.14.1에서 Patrol의 Android WebView 조작 문제(#244, #3178)와 #130872가 재현되는지 모른다.
- Patrol의 WebView CI는 Flutter 3.38.x로 고정돼 있어서 [16][17], 3.47에서의 WebView 동작에 대해서는 Patrol 쪽 근거가 없다.
- Playwright `_android`를 Flutter Host의 WebView에 붙일 수 있는지, Host 화면 조작과 어떻게 함께 쓸지 확인하지 않았다. 문서의 요구사항은 Chrome 기준이다 [43].
- iOS 시뮬레이터에서 S2의 카메라 촬영 경로를 E2E로 다룰 수 있는지 확인하지 못했다.
- iOS 26에서 HTML id가 안 보이는 문제 [28]가 앱 안의 WKWebView에도 해당하는지, Patrol과 Appium에도 영향이 있는지 모른다.
- 이 저장소의 실제 CI 시간(Flutter iOS 빌드, 시뮬레이터 부팅, 실행)을 재지 않았다.
- Developer Device Platform의 가격과 iOS 시뮬레이터 지원 여부를 확인하지 못했다 [75].
- WebView 패키지([#38](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/38))를 flutter_inappwebview로 정할 경우의 테스트 시임을 보지 않았다. iOS 16.4 이상의 `isInspectable` 설정 [76]과 Android의 `setWebContentsDebuggingEnabled` [77]는 있지만, 가짜 플랫폼을 주입하는 방식은 확인하지 않았다. 이 패키지의 최신 릴리스는 2024-10의 6.1.5다 [78].

**새로 생긴 질문**

1. 테스트 빌드 구성: WebView 디버깅, `isInspectable`, 테스트 훅을 어떤 빌드(flavor, `--dart-define`)에서만 켤 것인가? 보안 모델(#41)과 함께 정해야 한다.
2. 공유 픽스처의 위치와 형식: 계약 단일 원천(#40)과 같은 곳에 둘 것인가? Playwright 가짜 Host와 Flutter 가짜 Web은 그것을 어떻게 읽을 것인가?
3. 개발용 가짜 Host와 Playwright 가짜 Host를 하나로 만들 것인가? (지도 "Not yet specified"의 개발용 가짜 Host 항목)
4. E2E에 쓸 Web과 가짜 API를 CI에서 어떻게 띄울 것인가? 프로덕션 빌드 여부, 시뮬레이터와 에뮬레이터에서의 주소, Web 전달 방식([#46](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/46))과 이어진다.
5. Web 화면 요소와 Host 화면 위젯의 테스트 식별 규칙(접근성 이름, `data-testid`, Semantics `identifier`)을 어떻게 정할 것인가?

## 출처

1. [Flutter 문서, "Integration testing" (2026-09-29 갱신, Flutter 3.47 기준)](https://docs.flutter.dev/testing/integration-tests)
2. [flutter/flutter, `packages/integration_test/README.md`](https://github.com/flutter/flutter/blob/master/packages/integration_test/README.md)
3. [flutter/flutter#86295, "[integration_test] Allow driving native UI interactions from Dart"](https://github.com/flutter/flutter/issues/86295)
4. [flutter/flutter#148028, "Proposal: Make on-device testing awesome"](https://github.com/flutter/flutter/issues/148028)
5. [flutter/packages, webview_flutter 예제 통합 테스트 `webview_flutter_test.dart`](https://github.com/flutter/packages/blob/main/packages/webview_flutter/webview_flutter/example/integration_test/webview_flutter_test.dart)
6. [webview_flutter API, `WebViewController.runJavaScriptReturningResult`](https://pub.dev/documentation/webview_flutter/latest/webview_flutter/WebViewController/runJavaScriptReturningResult.html)
7. [flutter/flutter#130872, "WebView sometimes isn't loaded when run with `IntegrationTestWidgetsFlutterBinding`"](https://github.com/flutter/flutter/issues/130872)
8. [Patrol 문서, 개요](https://patrol.leancode.co/)
9. [flutter/flutter#86295, Patrol 제작자의 동작 방식 설명 댓글 (2022-09-25)](https://github.com/flutter/flutter/issues/86295#issuecomment-1257174606)
10. [Patrol 문서, "Native automation: Overview"](https://patrol.leancode.co/documentation/native/overview)
11. [leancodepl/patrol, `dev/e2e_app/patrol_test/webview_patrol_docs_test.dart`](https://github.com/leancodepl/patrol/blob/master/dev/e2e_app/patrol_test/webview_patrol_docs_test.dart)
12. [Patrol 문서, "Feature parity"](https://patrol.leancode.co/documentation/native/feature-parity)
13. [leancodepl/patrol#244, "Interacting with WebView on Android is flaky"](https://github.com/leancodepl/patrol/issues/244)
14. [leancodepl/patrol#3178, "Android: native selectors can't find WebView content since 4.0"](https://github.com/leancodepl/patrol/issues/3178)
15. [leancodepl/patrol#3113, "Fix webview e2e tests"](https://github.com/leancodepl/patrol/pull/3113)
16. [leancodepl/patrol, `.github/workflows/test-ios-simulator-webview.yaml`](https://github.com/leancodepl/patrol/blob/master/.github/workflows/test-ios-simulator-webview.yaml)
17. [leancodepl/patrol, `.github/workflows/test-android-emulator-webview.yaml`](https://github.com/leancodepl/patrol/blob/master/.github/workflows/test-android-emulator-webview.yaml)
18. [pub.dev, patrol 버전 목록](https://pub.dev/packages/patrol/versions)
19. [Patrol 문서, "Compatibility table"](https://patrol.leancode.co/documentation/compatibility-table)
20. [Patrol, "Pricing"](https://patrol.leancode.co/pricing)
21. [Maestro 문서, "iOS"](https://docs.maestro.dev/get-started/supported-platform/ios)
22. [Maestro 문서, "Flutter"](https://docs.maestro.dev/get-started/supported-platform/flutter)
23. [Maestro 문서, "Known issues"](https://docs.maestro.dev/extra-materials/troubleshooting/known-issues)
24. [mobile-dev-inc/maestro, `CHANGELOG.md`](https://github.com/mobile-dev-inc/maestro/blob/main/CHANGELOG.md)
25. [mobile-dev-inc/maestro, Releases](https://github.com/mobile-dev-inc/maestro/releases)
26. [mobile-dev-inc/maestro#3646, "androidWebViewHierarchy: devtools fails on Android System WebView 148+"](https://github.com/mobile-dev-inc/maestro/issues/3646)
27. [mobile-dev-inc/maestro#3497, "Android: WebView 150+ text inputs are unmatchable"](https://github.com/mobile-dev-inc/maestro/issues/3497)
28. [mobile-dev-inc/maestro#2891, "iOS 26 doesn't expose HTML element IDs"](https://github.com/mobile-dev-inc/maestro/issues/2891)
29. [Maestro 문서, `openLink`](https://docs.maestro.dev/reference/commands-available/openlink)
30. [Maestro 문서, `addMedia`](https://docs.maestro.dev/reference/commands-available/addmedia)
31. [Maestro 문서, "Permissions"](https://docs.maestro.dev/maestro-flows/flow-control-and-logic/permissions)
32. [Maestro, "Pricing"](https://maestro.dev/pricing)
33. [Maestro 문서, "JavaScript overview"](https://docs.maestro.dev/maestro-flows/javascript/javascript-overview)
34. [Appium 문서, "Managing Contexts"](https://appium.io/docs/en/latest/guides/context/)
35. [appium/appium-uiautomator2-driver README, "Hybrid Mode"](https://github.com/appium/appium-uiautomator2-driver#hybrid-mode)
36. [Android Developers, `WebView.setWebContentsDebuggingEnabled`](https://developer.android.com/reference/android/webkit/WebView#setWebContentsDebuggingEnabled(boolean))
37. [webview_flutter_android API, `AndroidWebViewController.enableDebugging`](https://pub.dev/documentation/webview_flutter_android/latest/webview_flutter_android/AndroidWebViewController/enableDebugging.html)
38. [Appium XCUITest 드라이버 문서, "Hybrid Apps" (2026-09-02 갱신)](https://appium.github.io/appium-xcuitest-driver/latest/guides/hybrid/)
39. [WebKit 블로그, "Enabling the Inspection of Web Content in Apps"](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/)
40. [webview_flutter_wkwebview API, `WebKitWebViewController.setInspectable`](https://pub.dev/documentation/webview_flutter_wkwebview/latest/webview_flutter_wkwebview/WebKitWebViewController/setInspectable.html)
41. [appium/appium-flutter-driver README](https://github.com/appium/appium-flutter-driver)
42. [AppiumTestDistribution/appium-flutter-integration-driver README](https://github.com/AppiumTestDistribution/appium-flutter-integration-driver)
43. [Playwright 문서, `Android`](https://playwright.dev/docs/api/class-android)
44. [Playwright 문서, `AndroidDevice`](https://playwright.dev/docs/api/class-androiddevice)
45. [microsoft/playwright, `packages/playwright-core/src/server/android/android.ts`](https://github.com/microsoft/playwright/blob/main/packages/playwright-core/src/server/android/android.ts)
46. [microsoft/playwright#1122, "Run Playwright tests on real mobile device browsers?"](https://github.com/microsoft/playwright/issues/1122)
47. [Playwright 문서, `Page` (`addInitScript`, `exposeBinding`, `exposeFunction`, `evaluate`)](https://playwright.dev/docs/api/class-page)
48. [Playwright 문서, "Mock browser APIs"](https://playwright.dev/docs/mock-browser-apis)
49. [Playwright 문서, "Browsers"](https://playwright.dev/docs/browsers)
50. [Playwright 문서, "Emulation"](https://playwright.dev/docs/emulation)
51. [Next.js 문서, "Testing"](https://nextjs.org/docs/app/guides/testing)
52. [Next.js 문서, "How to set up Playwright with Next.js" (2026-10-15 갱신)](https://nextjs.org/docs/app/guides/testing/playwright)
53. [flutter/packages, `webview_flutter_platform_interface/lib/src/platform_webview_controller.dart`](https://github.com/flutter/packages/blob/main/packages/webview_flutter/webview_flutter_platform_interface/lib/src/platform_webview_controller.dart)
54. [flutter/packages, `webview_flutter/test/webview_controller_test.dart`](https://github.com/flutter/packages/blob/main/packages/webview_flutter/webview_flutter/test/webview_controller_test.dart)
55. [Ajv 문서, "Choosing schema language"](https://ajv.js.org/guide/schema-language.html)
56. [pub.dev, json_schema](https://pub.dev/packages/json_schema)
57. [json_schema (Dart), `CHANGELOG.md`](https://github.com/Workiva/json_schema/blob/master/CHANGELOG.md)
58. [Pact 문서, Pact JS의 메시지 계약 ("Event driven-systems")](https://docs.pact.io/implementation_guides/javascript/docs/messages)
59. [pact_dart README](https://github.com/matthewshirley/pact_dart)
60. [Pact 문서, "Other languages"](https://docs.pact.io/implementation_guides/other_languages)
61. [AsyncAPI Specification 3.0.0](https://www.asyncapi.com/docs/reference/specification/v3.0.0)
62. [asyncapi/spec, Release v3.1.0](https://github.com/asyncapi/spec/releases/tag/v3.1.0)
63. [GitHub Docs, "GitHub Actions billing"](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
64. [GitHub Docs, "Actions runner pricing"](https://docs.github.com/en/billing/reference/actions-runner-pricing)
65. [GitHub Docs, "GitHub-hosted runners reference"](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
66. [actions/runner-images, macOS 26 arm64 이미지 README](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
67. [GitHub Changelog, "Hardware accelerated Android virtualization now available" (2024-04-02)](https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/)
68. [GitHub Changelog, "Hardware accelerated Android virtualization on Actions Windows and Linux larger hosted runners" (2023-02-23)](https://github.blog/changelog/2023-02-23-hardware-accelerated-android-virtualization-on-actions-windows-and-linux-larger-hosted-runners)
69. [ReactiveCircus/android-emulator-runner README](https://github.com/ReactiveCircus/android-emulator-runner)
70. [ReactiveCircus/android-emulator-runner#350, "Support for M1 Silicon - HVF error: HV_UNSUPPORTED"](https://github.com/ReactiveCircus/android-emulator-runner/issues/350)
71. [Patrol 문서, "Patrol and CI: Platforms"](https://patrol.leancode.co/documentation/ci/platforms)
72. [Firebase 문서, "Test Lab usage, quotas, and pricing" (2026-10-16 갱신)](https://firebase.google.com/docs/test-lab/usage-quotas-pricing)
73. [Firebase 문서, "Get started with Firebase Test Lab for iOS"](https://firebase.google.com/docs/test-lab/ios/get-started)
74. [Firebase 문서, "Firebase Test Lab" (deprecated 공지)](https://firebase.google.com/docs/test-lab)
75. [Google Cloud 문서, Developer Device Platform 이전 가이드](https://docs.cloud.google.com/developer-device-platform/device-run/migrate)
76. [flutter_inappwebview API, `InAppWebViewSettings.isInspectable`](https://pub.dev/documentation/flutter_inappwebview_platform_interface/latest/flutter_inappwebview_platform_interface/InAppWebViewSettings/isInspectable.html)
77. [flutter_inappwebview API, `InAppWebViewController.setWebContentsDebuggingEnabled`](https://pub.dev/documentation/flutter_inappwebview/latest/flutter_inappwebview/InAppWebViewController/setWebContentsDebuggingEnabled.html)
78. [pub.dev, flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview)
