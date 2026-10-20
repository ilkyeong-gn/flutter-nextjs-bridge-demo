# 화면 구성·뒤로 가기 실측

Host(Flutter)가 Web(Next.js) 화면을 `webview_flutter`로 띄울 때, 화면 구성과 뒤로 가기 설계에 필요한 사실을 직접 확인한 실험 코드와 결과다. [WebView 패키지 후보 실측](../webview-packages/README.md) 하네스를 바탕으로 만들었다. 이 브랜치(`experiment/screen-composition-back`)는 머지하지 않는다.

- 실측일: 2026-10-20

## 환경

| 항목 | 값 |
|---|---|
| Flutter | 3.47.7 stable(Dart 3.13.5) |
| Android 빌드 | AGP 9.1.0, targetSdk 36(Flutter 기본값), `android:enableOnBackInvokedCallback="true"` |
| Android 실행 | 에뮬레이터 Pixel 10a AVD, Android 17(API 37), 제스처 탐색(`navigation_mode=2`), Android System WebView 149.0.7827.5 |
| iOS 빌드 | Xcode 27.0, Swift Package Manager |
| iOS 실행 | iPhone 18 Pro 시뮬레이터, iOS 27.0, UIScene 생명주기 |
| 패키지 | `webview_flutter` 4.14.1(android 4.14.1, wkwebview 3.27.1). 플랫폼 코드 없음. iOS는 `WebKitWebViewController`의 `setAllowsBackForwardNavigationGestures(true)`·`setOnCanGoBackChange`·`setInspectable`만 씀 |
| Web | Next.js 16.4.2 App Router, React 19.3.1. `next build && next start`(production) |

## 구성

| 경로 | 내용 |
|---|---|
| `web/` | Next.js 앱. 모든 화면에 `<Link href="/a">`(#to-a), `router.push('/b')`(#push-b), `router.back()`(#back), `<Link href="/iframe">` 단추가 있다. `/iframe`은 출처가 다른 iframe(:3001)과, 부모 JS로 iframe `src`를 바꾸는 단추(#iframe-src), iframe 안 링크를 JS로 누르게 하는 단추(#iframe-click)를 둔다. `app/probe.tsx`는 레이아웃에 한 번 올라가 `visibilitychange`·`pagehide`·`pageshow`·`popstate`·경로 변경, 1초 `setInterval` 횟수(tick), Host가 부른 `window.__hostMsg`를 기록한다. 기록은 JavaScript 채널(`Log`)과 수집기 fetch 두 길로 보낸다 |
| `frame/frame.html` | 출처가 다른 iframe. `?n=` 번호를 표시하고, 링크는 `n+1`로 간다. 로드될 때 수집기에 알린다 |
| `server.py` | :3001 iframe, :8090 로그 수집기와 명령 대기열(`/cmd`는 Host 앱, `/gesture`는 XCUITest가 가져감) |
| `app/` | Host 앱. 스스로 시나리오를 돌지 않고 0.3초마다 `/cmd`에서 명령(`reset`·`state`·`goBack`·`cover`·`pop`·`pushWeb`·`hostMsg`·`js`·`rect`)을 가져와 실행한다. 루트 WebView 화면은 `PopScope(canPop: false, onPopInvokedWithResult: …)`로 감쌌다. `onUrlChange`·`onNavigationRequest`·`onPageStarted/Finished`, 라우트 push/pop·사용자 제스처, 앱 생명주기를 기록한다 |
| `ios-uitests/` | 시뮬레이터에 실제 터치를 보내는 XCUITest(대상 앱 없는 UI 테스트 번들). `/gesture`를 읽어 실측 앱을 다시 띄우지 않고 탭·가장자리 끌기를 한다. `gen.rb`(xcodeproj gem)로 프로젝트를 만들었다 |
| `drive.py` | 시나리오 실행기. 앱을 설치·실행하고 명령을 보낸다. 실제 탭은 Android `adb shell input tap`, iOS XCUITest. 요소 좌표는 Host가 JS `getBoundingClientRect`와 WebView 위젯 위치로 계산해 준다 |
| `ticks.py` | 표시 구간마다 JS 타이머가 몇 번 돌았는지 센다 |
| `results/` | 시나리오별 로그(jsonl)와 화면 |

"실제 탭"은 기기 입력으로 넣은 탭이라 사용자 활성화가 생긴다. "JS click"은 Host의 `runJavaScript`로 `element.click()`을 부른 것이라 사용자 활성화가 없다. 이 차이가 결과를 가르므로 둘을 따로 적었다.

## 다시 해 보기

```sh
cd experiments/screen-composition-back
python3 server.py                                   # 다른 터미널에서 계속 실행
(cd web && npm install && npx next build && npx next start -p 3000)   # 다른 터미널에서 계속 실행
(cd app && flutter build apk --debug && flutter build ios --simulator --debug)
(cd ios-uitests && gem install --user-install xcodeproj && ruby gen.rb \
  && xcodebuild build-for-testing -project GestureDriver.xcodeproj -scheme GestureDriver \
     -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build)
# Android 에뮬레이터와 iOS 시뮬레이터를 미리 부팅한다.

python3 drive.py android nav    && python3 drive.py ios nav       # 1
python3 drive.py android iframe && python3 drive.py ios iframe    # 2
python3 drive.py android cover  && python3 drive.py ios cover     # 3, 4
python3 ticks.py results/ios-cover.jsonl
python3 drive.py ios swipe && python3 drive.py ios swipe_root && python3 drive.py ios safari_control   # 5
python3 drive.py android back                                     # 6
```

- 시나리오마다 앱을 새로 설치·실행하고 끝나면 요약(1초 tick 제외)을 출력한다. 각 시나리오가 하는 일은 `drive.py`의 같은 이름 함수에 있다.
- 시나리오 중간의 `reset`은 루트를 새 WebView로 바꿔 WebView 기록을 비운다.
- 시각은 기기 시계(Dart·JS `t`)와 Mac 시계(수집기 `recvTs`, `drive` 표시)가 섞여 있다. Android 에뮬레이터는 Mac보다 0.3초쯤 어긋났다.

## 결과

### 1. 클라이언트 탐색(`<Link>`·`router.push`·`router.back`)

| 확인 | Android | iOS |
|---|---|---|
| `<Link>`·`router.push`(pushState) 때 `onUrlChange` | ○ 매번 새 경로로 옴 | ○ 매번 옴 |
| `router.back()`·`goBack()`(popstate) 때 `onUrlChange` | ○ Web에 `popstate`가 오고, `onUrlChange`가 같은 주소로 두 번 옴(`onPageFinished`도 한 번) | ○ 한 번 옴 |
| 실제 탭 뒤 `canGoBack()` | ○ `/`→`/a`에서 true. `/b`에서 `router.back()`하면 `/a`·true, `goBack()`하면 `/`·false | ○ 같음 |
| `setOnCanGoBackChange` | — | ○ 값이 바뀔 때만 옴(`/`→`/a`에서 true, `/a`→`/`에서 false). `/a`→`/b`처럼 true가 유지되면 오지 않는다 |
| JS click(사용자 활성화 없음)으로 `/a`, `/b`를 쌓은 뒤 | × `canGoBack()`이 false. `goBack()`해도 그대로 `/b` | △ `canGoBack()`은 true. 하지만 `goBack()`은 `/a`를 건너뛰고 `/`로 갔다 |

사용자 활성화 없이 쌓인 기록은 두 엔진 모두 뒤로 가기에서 건너뛴다(Chromium·WebKit의 기록 조작 방지 동작으로 보인다). Android는 그 기록을 `canGoBack()`에서도 빼고, iOS는 `canGoBack()`에 넣지만 `goBack()`은 건너뛴다. 실제 사용자 탭으로 생긴 Next.js 탐색은 두 플랫폼 모두 정상적으로 쌓였다.

### 2. 출처가 다른 iframe의 기록 오염

`/iframe`을 새 WebView로 연 뒤(처음 `canGoBack()`은 두 플랫폼 모두 false) 아래 동작을 하고 `canGoBack()`과 `goBack()`을 봤다.

| 동작 | Android | iOS |
|---|---|---|
| iframe 안 링크 실제 탭 | ○ `canGoBack()` true. `goBack()`은 iframe을 n=2→n=1로 되돌리고 메인 프레임 주소·`onUrlChange`는 그대로 | ○ 같음. `setOnCanGoBackChange`가 true→false로 옴 |
| 부모 단추 실제 탭으로 iframe `src` 변경 | ○ 같음(n=101→n=1) | ○ 같음 |
| iframe 안 링크 JS click(사용자 활성화 없음) | × `canGoBack()` false. `goBack()`은 아무 일도 안 함 | ○ `canGoBack()` true, `goBack()`은 iframe을 되돌림 |
| 부모 JS로 `src` 변경(사용자 활성화 없음) | × false, `goBack()` 무동작 | ○ true, `goBack()`은 iframe을 되돌림 |

- iframe 탐색은 두 플랫폼 모두 메인 프레임 `onUrlChange`를 부르지 않는다. iOS는 `onNavigationRequest`가 `isMainFrame=false`로 온다. Android는 iframe 탐색 콜백이 없다(#48 결과와 같음).
- 그래서 `canGoBack()`만 보고 Host가 "WebView 안에서 뒤로 간다"고 정하면, 메인 프레임 기록이 없는데도 iframe만 되돌리는 뒤로 가기가 생긴다. iOS는 사용자 활성화가 없어도(광고·위젯 iframe이 스스로 바뀌어도) 생긴다.

### 3. 가려짐·백그라운드 때 Web이 받는 신호

루트 WebView 위에 불투명 `MaterialPageRoute`(Flutter 화면)를 올렸다가 내렸다. 그 뒤 앱을 백그라운드로 보냈다(Android `KEYCODE_HOME`, iOS 설정 앱 실행)가 돌아왔다.

| 확인 | Android | iOS |
|---|---|---|
| Flutter 화면으로 가릴 때 `visibilitychange` | × 오지 않음. 가린 동안 `visibilityState`는 계속 `visible` | ○ 가린 직후 `hidden`, 내린 직후 `visible` |
| 가릴 때 `pagehide` | × | × |
| 백그라운드 때 `visibilitychange` | ○ `hidden`(앱 `paused`와 같은 때), 돌아오면 `visible` | ○ 같음 |
| 백그라운드 때 `pagehide` | × | × |

- `pagehide`는 WebView를 버릴 때(`reset`으로 위젯 제거)나 문서를 바꿀 때만 봤다. 위젯을 버릴 때는 두 플랫폼 모두 `visibilitychange`(`hidden`)가 먼저 왔다.
- iOS에서 Cupertino 라우트를 WebView 위에 올릴 때도 아래 WebView가 `hidden`이 됐고, 스와이프로 내리기 시작하면 `visible`이 됐다(5번 로그).

### 4. 가린 동안의 타이머와 Host 메시지

| 확인 | Android | iOS |
|---|---|---|
| 가린 약 10초 동안 1초 `setInterval` | ○ 그대로 1초마다 돎(8초 구간에 8번) | △ 돌지만 약 2초 간격으로 느려짐(8초 구간에 4번, 간격 1.4–2.1초). 드러나면 바로 1초로 돌아옴 |
| 가린 동안 `runJavaScript` | ○ 바로 실행(한 번은 1.3초, 한 번은 9ms 만에 Future 완료) | ○ 바로 실행(약 25ms). Web은 `visibilityState=hidden` 상태로 받음 |
| 백그라운드 동안 `setInterval` | ○ 1초마다 돎. 단 JS 채널·fetch로 내보낸 기록은 일부가 포그라운드로 돌아온 뒤 몰려 도착함 | △ 약 2초 간격 |
| 백그라운드 동안 `runJavaScript` | ○ 바로 실행(19ms) | ○ 앱이 아직 `inactive`일 때 보낸 것은 바로 실행됨. 완전히 일시 정지된 앱에는 Dart가 명령을 가져오지 못하므로 보지 않음 |

### 5. iOS 가장자리 스와이프

방법: XCUITest(`ios-uitests/`)가 실측 앱을 다시 띄우지 않고 `XCUICoordinate.press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`로 x=0–8pt에서 오른쪽으로 끌었다. 탭도 같은 XCUITest로 실제 탭을 보냈다. Flutter `integration_test`의 drag는 Flutter 쪽으로만 가고 WKWebView의 네이티브 제스처에는 닿지 않으므로 쓰지 않았다. `idb`는 설치돼 있지 않아 쓰지 않았다.

| 경우 | 결과 |
|---|---|
| 5c. `CupertinoPageRoute` 안 WebView, WebView 기록 없음 | ○ Flutter 라우트가 pop됨(`didStartUserGesture` → `didPop`) |
| 5a. `CupertinoPageRoute` 안 WebView(`allowsBackForwardNavigationGestures`=true), 실제 탭으로 `/`→`/a`→`/b`(`canGoBack()` true) | Flutter 라우트 pop이 이김. WebView 기록은 움직이지 않고(`onUrlChange` 없음) 라우트와 함께 버려짐 |
| 5b. 루트 WebView(Flutter 스와이프 없음), 같은 기록 2단 | × 끌기 4가지(x0=0·1·3·8pt, 속도 기본·400·800·1500pt/s, 누름 0–0.3초) 모두 WK 기록 뒤로 가기가 일어나지 않음 |
| 대조군: 시뮬레이터 Safari에서 같은 Next.js 화면, 같은 끌기 | × Safari에서도 뒤로 가지 않음(`results/ios-safari-control-end.png`, `/b`에 그대로) |

- 대조군 Safari에서도 일어나지 않았으므로, 이 방법(XCUITest 합성 끌기)으로는 WKWebView의 뒤로 가기 스와이프 자체를 일으키지 못한다. 따라서 "5b에서 WK 스와이프가 동작하지 않는다"는 확인되지 않았다. 5a에서 "Flutter가 이긴다"도 WK 제스처가 같은 입력에 반응하지 않는 조건에서 본 것이다. 확인에는 실기기 손 조작이나 시뮬레이터 창에서의 수동 조작이 필요하다.
- 확인된 사실: 합성 끌기는 Flutter Cupertino 뒤로 가기 제스처를 WebView(플랫폼 뷰) 위에서도 일으킨다. Flutter의 제스처 영역(왼쪽 가장자리)은 WebView가 화면을 덮어도 살아 있다.

### 6. Android 예측 뒤로 가기

| 확인 | 결과 |
|---|---|
| `KEYCODE_BACK`(WebView `canGoBack()` true, `/a`) | ○ `onPopInvokedWithResult(didPop: false)`가 불림. WebView는 `/a` 그대로, `canGoBack()` true 그대로. WebView가 뒤로 가기를 먹지 않음 |
| 왼쪽 가장자리 뒤로 가기 제스처(`adb shell input swipe 2 1200 600 1200 250`, 제스처 탐색) | ○ 같음 |
| 불투명 Flutter 화면을 올린 뒤 `KEYCODE_BACK` | ○ 위 Flutter 화면이 pop됨. 루트 `PopScope` 콜백은 불리지 않고 WebView 기록도 그대로 |

WebView 기록을 되돌릴지는 `onPopInvokedWithResult`에서 Host가 `canGoBack()`·`goBack()`으로 직접 정해야 한다. 1·2번 결과처럼 `canGoBack()`에는 iframe 기록이 섞인다.

## 확인하지 못한 것

- iOS WKWebView 뒤로 가기 스와이프(5b)와, 그것과 Flutter Cupertino 스와이프의 경쟁(5a)의 실제 손 조작 결과. 위 대조군 설명대로 XCUITest 합성 끌기로는 Safari에서도 WK 스와이프가 일어나지 않았다(시도: 시작 x 0·1·3·8pt, 속도 4가지, 누름 0–0.3초).
- Android 예측 뒤로 가기 애니메이션(시스템 미리보기)의 모양. 콜백이 불리는지만 봤다.
- 실기기, release 빌드, 다른 WebView·iOS 버전.
- iOS에서 앱이 완전히 일시 정지된 동안 `runJavaScript`(Dart가 명령을 가져오지 못하는 상태라 이 하네스로는 보낼 수 없다).
- 투명(`opaque: false`) 라우트·다이얼로그로 가릴 때.
