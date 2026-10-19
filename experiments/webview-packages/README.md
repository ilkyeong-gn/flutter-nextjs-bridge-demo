# WebView 패키지 후보 실측

[WebView 패키지 후보 빌드·동작 실측](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/48)의 실험 코드와 결과다. [WebView 패키지 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/38)에 필요한 사실을 직접 확인하려고 만들었다. 이 브랜치(`experiment/webview-package-candidates`)는 머지하지 않는다.

- 실측일: 2026-10-19
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
| `wf_ext/` | 후보 B. `webview_flutter` + 플랫폼 코드. Android `OriginBridgePlugin.kt`(`addWebMessageListener`·`addDocumentStartJavaScript`), iOS `AppDelegate.swift`의 `OriginBridge`(`WKScriptMessageHandlerWithReply`·`frameInfo`·`WKUserScript`). 기존 JavaScript 채널(`Legacy`)과 함께 둔다 |
| `iaw_beta/` | 후보 C. `flutter_inappwebview` 6.2.0-beta.3. `--dart-define=MODE=full`(기본)·`hardened`·`coldstart`, `MAIN_PORT`, `HOST` |
| `run.sh`, `coldstart.sh` | 한 조합을 설치·실행해 `results/`에 로그와 화면을 남긴다. `coldstart.sh`는 release 콜드 스타트를 반복한다 |
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
