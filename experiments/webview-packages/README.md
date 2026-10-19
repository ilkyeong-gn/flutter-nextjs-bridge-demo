# WebView 패키지 후보 실측

[WebView 패키지 후보 빌드·동작 실측](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/48)의 실험 코드와 결과다. [WebView 패키지 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/38)에 필요한 사실을 직접 확인하려고 만들었다. 이 브랜치(`experiment/webview-package-candidates`)는 머지하지 않는다.

- 실측일: 2026-10-19
- 맨 아래 [후보 B: Android 렌더러 종료 처리](#후보-b-android-렌더러-종료-처리)는 같은 날 이어서 실측했다.
- 근거 조사: [Flutter WebView 패키지 기능 비교 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/28), [WebView Bridge 보안 지침 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/36)

## 환경

| 항목 | 값 |
|---|---|
| Flutter | 3.47.7 stable(Dart 3.13.5). SwiftPM·UIScene 마이그레이션 플래그를 켬 |
| Android 빌드 | AGP 9.1.0, Kotlin 2.4.0, Gradle 9.3.1, JDK 25(Android Studio JBR), targetSdk 36(Flutter 기본값). `flutter create` 템플릿 그대로이며 Demo 앱과 같은 구성 |
| Android 실행 | 에뮬레이터 Pixel 10a AVD, Android 17(API 37), 16KB 페이지 이미지, Android System WebView 149.0.7827.5 |
| iOS 빌드 | Xcode 27.0(27A266a), Swift Package Manager |
| iOS 실행 | iPhone 18 Pro 시뮬레이터, iOS 27.0, UIScene 생명주기(Flutter 3.47 템플릿의 `SceneDelegate`) |
| 패키지 | `webview_flutter` 4.14.1(android 4.14.1, wkwebview 3.27.0), `androidx.webkit` 1.15.0, `flutter_inappwebview` 6.2.0-beta.3(android·ios 1.2.0-beta.3) |

## 구성

| 경로 | 내용 |
|---|---|
| `server.py` | 출처 두 개(:8080 본문, :8081 출처가 다른 iframe)와 로그 수집기(:8090). `EXTRA_PORT=80`을 주면 기본 포트도 연다 |
| `web/` | `index.html`은 메인 프레임으로, 출처가 다른 iframe과 출처가 같은 iframe을 품는다. `probe.js`는 프레임마다 보이는 Bridge 통로를 확인하고 통로마다 Message를 보낸 뒤 결과를 수집기로 보낸다. iframe은 본문에 주 출처를 사칭하는 값을 넣고, 1.2초 뒤 JS로 자기 주소를 한 번 바꾼다 |
| `wf_ext/` | 후보 B. `webview_flutter` + 플랫폼 코드. Android `OriginBridgePlugin.kt`(`addWebMessageListener`·`addDocumentStartJavaScript`), iOS `AppDelegate.swift`의 `OriginBridge`(`WKScriptMessageHandlerWithReply`·`frameInfo`·`WKUserScript`). 기존 JavaScript 채널(`Legacy`)과 함께 둔다. `--dart-define=MODE=renderer`로 빌드하면 렌더러 종료 실측 화면(`lib/renderer.dart`, Android `RendererGuardPlugin.kt`)이 뜬다 |
| `iaw_beta/` | 후보 C. `flutter_inappwebview` 6.2.0-beta.3. `--dart-define=MODE=full`(기본)·`hardened`·`coldstart`, `MAIN_PORT`, `HOST` |
| `run.sh`, `coldstart.sh` | 한 조합을 설치·실행해 `results/`에 로그와 화면을 남긴다. `coldstart.sh`는 release 콜드 스타트를 반복한다 |
| `renderer.sh`, `renderer_ios.sh` | 렌더러 종료 실측. `renderer.sh`는 scenario 하나를 돌려 로그·걸러 낸 logcat·Host pid 변화·화면을 남긴다. `renderer_ios.sh`는 시뮬레이터의 WebContent 프로세스를 끝낸다 |
| `summarize.py`, `show_log.py` | 로그를 단계별로 요약한다. 응답이 보낸 프레임이 아닌 다른 프레임에 도착하면 표시한다 |
| `results/` | 이번 실측의 로그(jsonl)와 화면 |

## 다시 해 보기

```sh
cd experiments/webview-packages
python3 server.py            # 다른 터미널에서 계속 실행. 기본 포트 확인 때는 EXTRA_PORT=80 python3 server.py
# Android 에뮬레이터와 iOS 시뮬레이터를 미리 부팅한다.

(cd wf_ext && flutter build apk --debug && flutter build ios --simulator --debug)
./run.sh wf_ext android 27 && ./run.sh wf_ext ios 27

(cd iaw_beta && flutter build apk --debug && flutter build ios --simulator --debug)
./run.sh iaw_beta android 20 && ./run.sh iaw_beta ios 44 2

(cd iaw_beta && flutter build apk --debug --dart-define=MODE=hardened && flutter build ios --simulator --debug --dart-define=MODE=hardened)
TAG=hardened ./run.sh iaw_beta android 26 && TAG=hardened ./run.sh iaw_beta ios 16

(cd iaw_beta && flutter build ios --simulator --debug --dart-define=MODE=hardened --dart-define=MAIN_PORT=80)
TAG=port80 ./run.sh iaw_beta ios 14

(cd iaw_beta && flutter build apk --release --dart-define=MODE=coldstart)
./coldstart.sh 30

python3 summarize.py results/*.jsonl
```

- Android 에뮬레이터는 `10.0.2.2`로 Mac에 닿는다. 화면이 꺼져 Light Doze에 들어가면 앱 UID의 네트워크가 막히므로(셸 UID는 예외), `run.sh`·`coldstart.sh`가 화면을 켜 두고 Doze를 끈다.
- Android 실기기에서는 `adb reverse tcp:8090 tcp:8090` 뒤에 `--dart-define=HOST=127.0.0.1`을 붙여 `MODE=coldstart`로 빌드하고 `./coldstart.sh`를 쓴다.

## 결과

### 빌드

| | Android debug | Android release | iOS 시뮬레이터 debug | iOS 기기 release(서명 없음) |
|---|---|---|---|---|
| B. `webview_flutter` + 플랫폼 코드 | ○ | ○ | ○ | ○ |
| C. `flutter_inappwebview` 6.2.0-beta.3 | ○ | ○ | ○ | ○ |

- C를 AGP 9.1로 빌드할 때 6.1.5에서 보고된 proguard 실패([flutter_inappwebview #2765](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2765))가 나지 않았다.
- 두 후보 모두 iOS 플러그인이 SwiftPM으로 해석됐다. 생성 패키지에 플러그인이 들어가고 Podfile이 생기지 않았으므로 CocoaPods 대체 경로를 타지 않았다.
- B는 Runner 타깃에서 `import webview_flutter_wkwebview`로 External API(`webView(forIdentifier:withPluginRegistrar:)`)를 썼다. 레지스트라는 UIScene 템플릿의 `didInitializeImplicitFlutterEngine`에서 `pluginRegistry.registrar(forPlugin:)`으로 얻었다.

### 후보 B: `webview_flutter` + 플랫폼 코드

| 확인 | Android | iOS |
|---|---|---|
| 출처를 아는 통로를 붙일 수 있나 | ○ External API로 얻은 WebView에 `addWebMessageListener`. 에뮬레이터 WebView 149는 `WEB_MESSAGE_LISTENER`·`DOCUMENT_START_SCRIPT`·`GET_COOKIE_INFO`를 모두 지원 | ○ External API로 얻은 WKWebView에 `WKScriptMessageHandlerWithReply` 등록 |
| 플랫폼이 알려 준 출처·메인 프레임 | ○ `sourceOrigin`·`isMainFrame`이 정확함. iframe이 본문에 주 출처를 사칭해도 실제 출처(:8081)로 보고됨 | ○ `frameInfo.securityOrigin`·`isMainFrame`이 정확함 |
| 허용 출처 밖 프레임에도 보이나 | 안 보임. 허용 규칙과 맞는 프레임에만 주입됨. 단 출처가 같은 iframe에는 주입되므로 `isMainFrame` 검사가 필요 | 보임(모든 프레임). 받을 때 `frameInfo`로 거른다 |
| 응답(Call 결과) | Message마다 오는 reply proxy로 돌려준다. 24건 모두 보낸 프레임에 도착 | `postMessage`가 Promise를 돌려준다. 15건 모두 보낸 프레임에 도착 |
| 문서 시작 스크립트 | `addDocumentStartJavaScript` + 허용 규칙: 메인 프레임과 출처가 같은 iframe에만 들어감 | `WKUserScript(forMainFrameOnly: true)`: 메인 프레임에만 들어감 |
| 기존 JavaScript 채널과 공존 | ○ 함께 동작한다. `removeJavaScriptChannel` 뒤에도 플랫폼 코드가 넣은 통로와 스크립트가 남는다 | △ Message 통로는 함께 동작한다. 하지만 `removeJavaScriptChannel` 뒤 다시 로드하면 플랫폼 코드가 넣은 문서 시작 스크립트가 사라진다. 패키지가 `removeAllUserScripts()`로 전부 지운 뒤 자기 채널만 다시 넣기 때문이다(`enableZoom(true)`도 같은 경로). 등록한 메시지 핸들러는 남는다 |
| 기존 JavaScript 채널(`Legacy`)의 노출 | 출처가 다른 iframe을 포함한 모든 프레임. Host는 본문 문자열만 받는다 | 같음 |
| 코드 양(실험 수준, 주석·빈 줄 제외) | Kotlin 약 81줄(진단용 기능 확인 포함), 등록 2줄, Gradle 의존성 1줄 | Swift 약 58줄, 등록 3줄 |

Dart 쪽은 WebView 식별자 얻기, 통로 붙이기 호출, 받은 Message 판정으로 약 25줄이다. 여러 WebView, 해제할 때 핸들러 제거, 오류 처리, 테스트는 실험에 넣지 않았다. `webview_flutter`에는 WebView 해제를 알려 주는 API가 없다.

### 후보 C: `flutter_inappwebview` 6.2.0-beta.3

| 확인 | Android | iOS |
|---|---|---|
| debug 실행·`onWebViewCreated` | ○ | ○ |
| `callHandler`가 주는 출처 정보(6.2 베타) | ○ origin·isMainFrame이 정확함 | ○ |
| 기본 설정에서 Bridge 노출 | `window.flutter_inappwebview`가 모든 프레임에 있고, iframe의 `callHandler`도 Dart 콜백까지 간다 | 같음 |
| `callHandler` 응답 | 출처가 다른 iframe의 Promise는 빈 값으로 끝난다. 출처가 같은 iframe이 출처가 다른 iframe 몫의 응답을 받았다(7건 중 2건) | 같음(1건). 호출 ID가 프레임마다 따로 매기는 타이머 ID이고 응답 대기열을 `window.top`에 두기 때문으로 보인다(소스) |
| `WebMessageListener` 주입 규칙 | ○ 허용 규칙대로 주입됨 | × 포트를 명시한 규칙(`http://localhost:8080`)으로는 메인 프레임에도 주입되지 않음. 주입 JS가 규칙의 포트(숫자)와 `location.port`(문자열)를 `===`로 비교한다. 포트를 생략한 출처(`http://localhost`, 80)에서는 주입됨 |
| `WebMessageListener` 응답 | × 리스너마다 reply proxy를 하나만 두고 새 Message가 올 때마다 덮어쓴다. 그래서 여러 프레임이 보내면 응답이 다른 프레임으로 간다(기본 설정 14건 중 4건, 제한 설정 8건 중 2건). 메인 프레임 몫의 응답이 출처가 다른 iframe에 도착한 경우도 있다 | × iframe 몫의 응답이 메인 프레임으로 간다(10건 중 8건) |
| Bridge 제한 설정(`javaScriptBridgeForMainFrameOnly`·`javaScriptBridgeOriginAllowList`·`javaScriptHandlersForMainFrameOnly`·`javaScriptHandlersOriginAllowList`) | △ iframe에서 `callHandler`가 사라져 Dart 콜백까지 가지 않는다. 하지만 `window.flutter_inappwebview` 객체는 남는다. 허용 목록은 `addWebMessageListener` 규칙으로 해석된다 | ○ iframe에서 Bridge가 사라진다. 허용 목록은 JS 정규식으로 해석된다(앵커가 없으면 부분 일치) |
| release 콜드 스타트 `onWebViewCreated`([flutter_inappwebview #2843](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2843)) | 30회 모두 불림. 3초 판정 기준으로는 9회가 늦었다(3.4–6.1초, 에뮬레이터 부하 평균 8). 보고된 교대 실패는 재현되지 않음 | 시뮬레이터는 release로 실행할 수 없음 |
| UIScene(iOS 27) | — | ○ 앱 실행, 내장 WebView, JS alert(자기 `window.rootViewController`로 표시), InAppBrowser 열고 닫기(닫은 뒤 메인 WebView 정상), ChromeSafariBrowser 열기·로드·닫기, HeadlessInAppWebView 로드와 JS 실행이 모두 동작했다. `keyWindow`·`delegate.window`를 쓰는 경로가 scene 하나인 앱에서는 깨지지 않았다 |

화면: [InAppBrowser](results/iaw_beta-ios-uiscene-inappbrowser.png), [ChromeSafariBrowser](results/iaw_beta-ios-uiscene-safari.png), [JS alert](results/iaw_beta-ios-uiscene-alert.png)

### 두 후보 공통: 내비게이션 콜백

| | Android | iOS |
|---|---|---|
| iframe 첫 로드 | × 두 패키지 모두 콜백이 오지 않음 | ○ 두 패키지 모두 `isMainFrame=false`로 옴 |
| iframe 안의 JS 탐색 | × | ○ |
| 메인 프레임 JS 탐색(대조군) | ○ | ○ |
| Host가 시작한 로드(`loadRequest`·`loadUrl`) | × | ○ |

`webview_flutter_android`는 소스에서도 서브프레임 탐색을 Dart에 넘기지 않고 항상 허용한다(`return request.isForMainFrame() && …`). Android에서 iframe을 막으려면 내비게이션 콜백 말고 다른 수단이 필요하다.

## 확인하지 못한 것

- Android 실기기 release 콜드 스타트([flutter_inappwebview #2843](https://github.com/pichillilorenzo/flutter_inappwebview/issues/2843) 보고 환경). 연결된 Android 기기가 없어 에뮬레이터로만 봤다. 보고자도 에뮬레이터에서는 재현되지 않았다고 적었다.
- iOS 실기기. UIScene 필수 요건은 iOS 27 SDK로 빌드해 iOS 27에서 실행할 때 걸리므로 시뮬레이터로 확인했다.
- 다른 Android WebView 버전과 낮은 API에서의 기능 지원. 지원 여부는 기기의 WebView 버전에 따라 런타임에 정해진다.
- `flutter_inappwebview` 6.1.5(선택지 D), `regexToCancelSubFramesLoading`, iPad 다중 scene.

## 실측 중 겪은 환경 문제

- Android 에뮬레이터가 Light Doze에 들어가자 앱 UID의 연결이 모두 시간 초과됐다. 셸 UID는 예외라 `nc`로는 연결됐다. 처음에는 `adb reverse` 문제로 보였지만 원인은 Doze였다.
- Dart `HttpClient`는 본문 길이를 지정하지 않으면 chunked로 보낸다. 그래서 `Content-Length`만 읽는 수집기에는 본문이 비어 도착했다. 지금은 길이를 지정해 보낸다.

## 후보 B: Android 렌더러 종료 처리

`webview_flutter_android`는 `WebViewClient.onRenderProcessGone`을 구현하지 않는다([flutter/flutter#130297](https://github.com/flutter/flutter/issues/130297)). 그래서 기본값(false)대로 렌더러가 죽으면 Host 앱도 같이 죽는다. 패키지를 포크하지 않고 플랫폼 코드만으로 막을 수 있는지 봤다.

방법은 이렇다. Dart가 내비게이션 대리자를 붙인 뒤, External API로 꺼낸 WebView의 현재 WebViewClient(패키지 것)를 위임 클라이언트(`RendererGuardClient`)로 감싼다. 위임 클라이언트는 모든 콜백을 패키지 클라이언트에 그대로 넘기고, `onRenderProcessGone`만 직접 처리해 true를 돌려준 뒤 Dart에 알린다. Dart는 죽은 WebView(위젯과 컨트롤러)를 버리고 새로 만든다.

- 실측일: 2026-10-19. 환경은 위와 같다(Pixel 10a AVD, Android 17, WebView 149.0.7827.5. iOS는 iPhone 18 Pro 시뮬레이터, iOS 27.0).
- 기본 모드(위의 #48 실측)는 바뀌지 않는다. 렌더러 실측은 `--dart-define=MODE=renderer`로 빌드한 같은 앱에서 돈다.

### 다시 해 보기

```sh
cd experiments/webview-packages
python3 server.py            # 다른 터미널에서 계속 실행
(cd wf_ext && flutter build apk --debug --dart-define=MODE=renderer)
./renderer.sh control-crash 40 && ./renderer.sh control-kill 30
./renderer.sh guard 95 13 16
./renderer.sh two 50 8 14 && ./renderer.sh two-a-only 25 && ./renderer.sh two-b-only 25
./renderer.sh popup 25 && ./renderer.sh popup-gc 28 && ./renderer.sh popup-nomulti 28

(cd wf_ext && flutter build ios --simulator --debug --dart-define=MODE=renderer)
./renderer_ios.sh

python3 show_log.py results/wf_ext-android-renderer-guard.jsonl
```

- scenario는 실행 Intent의 extra(`am start --es scenario …`)로 넘긴다. APK 하나로 모든 경우를 돈다. 각 scenario가 하는 일은 `wf_ext/lib/renderer.dart` 맨 위에 적었다.
- 렌더러는 `loadRequest`로 `chrome://crash`(충돌)나 `chrome://kill`(시스템 종료 흉내)를 열어 끝낸다. 둘 다 루트 없이 된다.
- `renderer.sh`는 1초마다 Host·렌더러 pid를 적는다(`-pid.txt`). 끝나면 Host·렌더러 pid의 logcat만 걸러 남긴다(`-logcat.txt`). Host가 살아 있으면 `dumpsys meminfo`의 WebView 수도 적는다.

### 패키지 소스에서 확인한 것(4.14.1)

| 확인 | 결과 |
|---|---|
| WebViewClient를 넣는 곳 | Java: `WebViewPlatformView` 생성자가 기본 `new WebViewClient()`를 넣고, `WebViewProxyApi.setWebViewClient`가 Dart 요청을 그대로 넘긴다. Dart: `AndroidWebViewController.setPlatformNavigationDelegate` 한 곳이다(`setNavigationDelegate`를 부를 때마다). 그 밖에 `SecureWebChromeClient.onCreateWindow`가 `window.open`용 임시 WebView에 자기 WebViewClient를 넣는다 |
| 패키지 클라이언트의 타입 | `WebViewClientProxyApi.WebViewClientImpl`. `android.webkit.WebViewClient`를 바로 상속한다(`WebViewClientCompat` 아님). 실행 중에 꺼낸 객체도 같았다. 그래서 위임 클라이언트도 `WebViewClient`를 상속하면 된다. Dart에 있는 `onReceivedRequestErrorCompat`·`urlLoading` 콜백은 Java가 부르지 않는다 |
| 클라이언트 타입 검사 | `setSynchronousReturnValueForShouldOverrideUrlLoading`의 `instanceof WebViewClientImpl` 하나뿐이다. Dart가 쥔 패키지 클라이언트 객체를 검사하므로, WebView에 꽂힌 것이 위임 클라이언트여도 상관없다 |
| `setWebViewClient` 재정의 | `WebViewPlatformView.setWebViewClient`는 받은 클라이언트를 `SecureWebChromeClient`에도 전한다. 감싸면 `onCreateWindow`가 위임 클라이언트의 `shouldOverrideUrlLoading`을 부르고, 그 호출이 패키지 클라이언트로 넘어간다 |
| 콜백이 Dart에 닿는 길 | 패키지 클라이언트는 `api.onPageStarted(this, view, …)`처럼 자기 자신과 WebView를 Dart로 보낸다. 위임 클라이언트가 같은 `view`를 넘기므로 Dart가 객체를 찾는 데 문제가 없다 |
| 바꾸면 깨지는 것 | `setNavigationDelegate`를 다시 부르면 패키지가 새 클라이언트를 넣으므로 감싼 것이 조용히 빠진다(실측에서도 확인). 위임 클라이언트가 넘기지 않는 콜백은 사라진다. 패키지가 나중에 콜백을 더 구현하면 위임 클라이언트도 고쳐야 한다 |
| WebView 해제 | Dart 쪽 WebView 객체가 GC되면 Finalizer가 `removeStrongReference`를 보내고, Java `InstanceManager.remove`가 `WebViewPlatformView`에 `destroy()`를 부른다. `PlatformView.dispose()`는 비어 있다. `webview_flutter`에는 WebView를 바로 해제하는 공개 API가 없다 |

### 결과

| 확인 | 결과 |
|---|---|
| 대조군: 감싸지 않고 `chrome://crash` | × Host가 죽는다. `Render process (…)'s crash wasn't handled by all associated webviews, triggering application crash.` 뒤 SIGTRAP |
| 대조군: 감싸지 않고 `chrome://kill` | × Host가 죽는다. `Render process (…) kill (OOM or update) wasn't handed by all associated webviews, killing application.` |
| 감싼 뒤 crash·kill | ○ Host pid가 그대로다(crash, kill, crash를 이어서 해도 21690 하나). 렌더러는 새 pid로 다시 뜬다 |
| Dart가 받는 알림 | ○ `didCrash`는 crash에서 true, kill에서 false. `rendererPriorityAtExit`는 둘 다 2(`RENDERER_PRIORITY_IMPORTANT`) |
| 버리고 다시 만들기 | ○ 위젯과 컨트롤러를 버린 뒤 새로 만든 WebView가 로드된다. 4세대(A1–A4)까지 반복했다 |
| 다시 만든 WebView의 출처 확인 통로(#48) | ○ 세대마다 `attach`를 다시 부르면 된다. 메인 프레임 Message가 플랫폼이 알려 준 출처(:8080)·`isMainFrame=true`로 와서 받아들였고, 응답은 모두 보낸 프레임에 도착했다. 출처가 다른 iframe에는 `SecureBridge`가 주입되지 않았다 |
| `setNavigationDelegate`를 다시 부른 뒤 | × 감싼 것이 빠진다(현재 클라이언트가 `WebViewClientImpl`로 돌아감). 다시 감싸면 ○ 다음 crash도 처리됐다 |
| 두 WebView(보이는 A, `Offstage` 안의 B) | 두 WebView가 렌더러 프로세스 하나를 같이 썼다(`getWebViewRenderProcess()`가 같은 객체). A에서 crash하면 ○ A·B 모두 `onRenderProcessGone`을 받는다. 둘 다 감쌌을 때 Host가 살았고, 둘 다 다시 만들어 로드했다 |
| 한쪽만 감쌈 | × A만 감싸도, B만 감싸도 Host가 죽는다. WebView마다 부르는 순서가 실행마다 달랐다(A 먼저, B 먼저 모두 봄). 처리하지 않은 WebView를 만나면 그 자리에서 앱을 끝내므로, A만 감쌌을 때는 A의 콜백이 불리기도 전에 죽었다 |
| `window.open` 뒤 crash | × 하나뿐인 WebView를 감쌌는데도 Host가 죽는다. 패키지 기본값이 `setSupportMultipleWindows(true)`라서, `SecureWebChromeClient.onCreateWindow`가 URL을 가로채려고 만든 임시 `new WebView`가 같은 렌더러에 붙어 남는다. 그 임시 WebView는 감쌀 수 없다 |
| ↳ Java GC 뒤 crash | ○ 임시 WebView가 수거된 뒤에는 살았다 |
| ↳ 플랫폼 코드로 `setSupportMultipleWindows(false)` | ○ 살았다. `window.open`은 같은 WebView에서 열렸고 `onNavigationRequest`도 그대로 왔다 |
| 죽은 WebView 해제 | ○ 버린 직후에는 패키지 InstanceManager에 남아 있다(`attachedToWindow=false`). 버린 지 4–5초 뒤 확인했을 때는 Dart GC를 따로 재촉하기 전인데도 이미 풀려 있었다(Java GC 뒤 `getWebView`가 null). 끝날 때 `dumpsys meminfo`의 WebView 수는 살아 있는 수와 같았다(하나일 때 1, 둘일 때 2) |
| 직접 `destroy()` | ○ 위젯을 뺀 뒤 플랫폼 코드에서 불러도 경고·예외가 없었다. 패키지가 해제하면서 같은 WebView에 다시 부르는 `destroy()`(소스상 `InstanceManager.remove`)에도 로그가 없었다. 패키지가 결국 부르므로 꼭 부를 필요는 없다. 네이티브 자원을 빨리 놓고 싶을 때만 의미가 있다 |
| Host 쪽 오류 로그 | 없음. `missing-instance-error`, 해제된 WebView 호출 경고, 예외가 나오지 않았다 |

내비게이션 콜백이 Dart에 온 횟수. 세 WebView에 같은 동작 한 벌(로드, JS 탐색 허용, JS 탐색 막음, `pushState`, 404, 연결 실패)을 돌렸다.

| 콜백 | 감싸지 않음(대조군) | 감싼 원래 WebView(A1) | 감싸고 다시 만든 WebView(A2) |
|---|---|---|---|
| onPageStarted | 4 | 4 | 4 |
| onPageFinished | 4 | 4 | 4 |
| onNavigationRequest 허용 / 막음 | 1 / 1 | 1 / 1 | 1 / 1 |
| onUrlChange(`pushState` 포함) | 5 | 5 | 5 |
| onWebResourceError(`:1` 연결 실패) | 1 | 1 | 1 |
| onHttpError(404, favicon 포함) | 2 | 2 | 2 |

막은 탐색 뒤 `currentUrl()`은 직전 주소 그대로였다.

화면: [대조군 crash 뒤(앱이 사라짐)](results/wf_ext-android-renderer-control-crash-end.png), [감싼 WebView crash 직후(A2를 만드는 중)](results/wf_ext-android-renderer-guard-13s.png), [다시 만든 A2](results/wf_ext-android-renderer-guard-16s.png), [두 WebView를 다시 만든 뒤](results/wf_ext-android-renderer-two-14s.png), [iOS reload 뒤](results/wf_ext-ios-renderer-end.png)

### iOS(선택 항목)

| 확인 | 결과 |
|---|---|
| WebContent 프로세스 종료 알림 | ○ 시뮬레이터의 `WebContentExtension.appex/com.apple.WebKit.WebContent`를 Mac에서 `kill -9`로 끝내자 `onWebResourceError`가 `webContentProcessTerminated`(code 2, url 없음)로 왔다. Host는 그대로였다 |
| `reload()` 뒤 플랫폼 코드의 메시지 핸들러 | ○ 메인 프레임에 `webkit.messageHandlers.SecureBridge`가 있고, 응답이 `frameInfo` 기준 출처로 왔다 |
| `reload()` 뒤 `WKUserScript` | ○ 메인 프레임에 `window.__docStartMarker`가 다시 들어갔다. 새 주소로 로드해도 같았다 |

### 코드 양(주석·빈 줄 제외)

- Kotlin `RendererGuardPlugin.kt` 146줄: 위임 클라이언트 47줄, 감싸기·알림·채널 약 43줄, import 24줄, 실측용(`inspect`·`destroy`·`disableMultipleWindows`·GC 재촉·scenario) 약 32줄. `MainActivity` 등록 1줄.
- Dart `renderer.dart` 369줄. 대부분 scenario 진행, 콜백 기록, 화면, iOS 확인이다. 실제 앱에 들어갈 부분(대리자를 붙인 뒤 감싸기 호출, 알림 받기, 버리고 다시 만들기)은 약 20줄이다. `main.dart` 2줄.

### 패치로 고친다면

플랫폼 코드로 동작하므로 이번에는 포크가 필요 없었다. 패키지에 직접 넣는다면 손으로 쓸 부분은 대략 이렇다.

- `pigeons/android_webkit.dart`: `WebViewClient`에 `onRenderProcessGone(WebView, didCrash, rendererPriorityAtExit)` 콜백과, 동기 반환값을 정하는 host 메서드(`shouldOverrideUrlLoading`과 같은 방식)를 더한다. 약 15줄. 생성 코드(`android_webkit.g.dart`, `AndroidWebkitLibrary.g.kt`)는 다시 생성한다.
- `WebViewClientProxyApi.java`: `WebViewClientImpl.onRenderProcessGone`(API 26 이상) 재정의와 반환값 설정. 약 20줄.
- `WebChromeClientProxyApi.java`: `onCreateWindow`의 임시 WebView 클라이언트도 `onRenderProcessGone`에서 true를 돌려주게 한다. 약 5줄.
- `android_webview_controller.dart`: `AndroidNavigationDelegate.setOnRenderProcessGone`. 약 20줄.
- 테스트(Java·Dart) 약 50줄.
- 여러 플랫폼 공통 API로 올리려면 `webview_flutter_platform_interface`와 `webview_flutter`도 고쳐야 한다.

### 확인하지 못한 것

- 메모리 부족으로 시스템이 렌더러를 실제로 죽이는 경우. `chrome://kill`은 렌더러가 스스로 끝나는 흉내다. `didCrash=false` 경로는 같지만, 백그라운드 상태에서의 우선순위 값은 보지 않았다.
- `target="_blank"` 링크를 눌렀을 때. 소스로는 `window.open`과 같은 `onCreateWindow` 경로다.
- `setSupportMultipleWindows(false)`가 `window.open`의 다른 동작(창 이름, `opener`, `window.close`)에 주는 영향.
- 렌더러가 죽은 뒤 쿠키·`localStorage`가 새 WebView에 남는지.
- 렌더러가 죽은 뒤 Dart가 위젯을 뺄 때까지 화면에 보이는 것. 이번에는 0.5초 안에 뺐다.
- 낮은 API(26–28), 다른 WebView 버전, 실기기, release 빌드.
- iOS에서 시스템(jetsam)이 WebContent를 끝내는 경우와 iOS 실기기.
