# Host 화면·Web 화면 혼합 구성과 뒤로가기 처리 조사

- 질문: [#33 Host 화면·Web 화면 혼합 구성과 뒤로가기 처리 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/33)
- 조사일: 2026-10-19
- 확인한 버전: Flutter 3.47.7 stable(Dart 3.13.5) · webview_flutter 4.14.1(webview_flutter_android 4.14.1, webview_flutter_wkwebview 3.27.0) · go_router 18.1.0 · cupertino_ui 1.1.3 · flutter_inappwebview 6.1.5(마지막 안정판, 2024-10)와 6.2.0-beta.3 · Next.js 16.4.2(저장소는 16.4.0) · React 19.3.1 · TanStack Query 5.104.4 · Android 16(API 36)·iOS 26 기준 공식 문서

## 요약

- **Host 화면을 다녀와도 Web 화면 상태는 기본으로 남는다.** Flutter page route는 기본값이 `maintainState: true`라서 Host 화면을 위에 push해도 아래 Web 화면 route가 메모리에 남는다 [1]. webview_flutter 4의 WebView는 widget이 아니라 controller에 묶여 있다 [2][3]. 상태를 잃는 것은 route를 바꿔치기하면서 controller까지 버릴 때다.
- **WebView 개수는 메모리, 첫 로드, 전환 애니메이션, 장애 격리 사이의 선택이다.** WebView마다 문서와 JS 런타임이 따로 생겨 Next.js도 WebView마다 부팅된다. Android에서는 같은 Profile의 WebView들이 렌더러 프로세스 하나를 함께 쓴다 [4]. WebView 하나를 공유하면 Web 안 이동이 client-side 전환이라 빠르지만, 전환 애니메이션과 뒤로가기는 Web이 책임진다 [5][6].
- **Android 뒤로가기는 미리 선언해야 한다.** Flutter 3.47.7의 기본 targetSdk는 36이다. 그래서 Android 16 기기에서는 predictive back이 기본으로 켜지고 `onBackPressed`와 `KEYCODE_BACK`이 오지 않는다 [7][8]. Flutter에서는 `PopScope.canPop`을 미리 정해야 하고, `canPop: false`인 동안에는 back-to-home 애니메이션이 사라진다 [9][10].
- **WebView 기록은 시스템 뒤로가기에 자동으로 연결되지 않는다.** Host가 `canGoBack()`과 `goBack()`으로 직접 처리한다 [11][12]. Android codelab은 기록이 바뀔 때마다 뒤로가기 콜백의 활성 여부를 `canGoBack()`에 맞추라고 한다 [13].
- **Web 안의 팝업·바텀시트·작성 화면을 먼저 닫는 방법은 두 가지다.** (1) 닫을 수 있는 층을 모두 history 항목으로 만든다. 인터셉트·병렬 라우트 모달은 뒤로가기로 닫힌다 [14]. (2) Host가 뒤로가기를 Web에 넘기고 Web이 처리 여부를 정한다. Capacitor `backButton`과 Ionic 우선순위 핸들러가 이 방식이다 [15][16]. Web은 브라우저 뒤로가기(popstate)를 취소할 수 없고, Next.js `onNavigate`는 Link 이동만 막는다 [17].
- **"Host가 Web에 처리했는지 묻기"는 GLOSSARY에 없는 방향이다.** Call은 Web→Host만 정의돼 있다. Host→Web 응답 쌍을 새로 정의하거나, Web이 상태 변화를 Message로 미리 알려 Host가 `canPop`을 유지하는 방식 중 하나를 골라야 한다.
- **iOS 스와이프 뒤로가기는 Flutter가 직접 인식한다.** 왼쪽 가장자리의 좁은 띠(20pt와 왼쪽 safe area 여백 중 넓은 쪽)에서만 시작하고, `canPop: false`이거나 `fullscreenDialog` route면 제스처가 아예 없다 [9][18]. WKWebView 자체 스와이프는 기본으로 꺼져 있다 [19]. iOS 26의 화면 전체 스와이프는 Flutter route에 아직 없다 [20][21].
- **Host가 Web 경로 변화를 아는 길은 두 가지다.** 하나는 WebView 신호(`onUrlChange`, iOS 전용 `setOnCanGoBackChange`)다 [2][22]. 다른 하나는 Web Message(`usePathname` 기반 감지, `onRouterTransitionStart`의 `push`·`replace`·`traverse`)다 [23][24]. "모달이 열려 있다" 같은 의미는 Web Message로만 전할 수 있다.
- **탭 재선택 관례.** UIKit은 이미 선택된 탭을 다시 눌러도 그 탭의 루트를 보여주고 [25], Material(M1)은 뷰의 맨 위로 보낸다 [26]. go_router 공식 예제도 같은 탭을 다시 누르면 초기 위치로 보낸다 [27]. 탭 바가 Host에 있으면 Web 탭에는 Event로 알려야 한다.
- **2026-10 현재 열린 버그가 많다.** go_router `StatefulShellRoute`와 predictive back을 함께 쓸 때 Host가 종료되거나 뒤로가기가 멈추는 이슈가 있다 [28][29][30]. Android의 다중 platform view 표시 오류 [31]와 렌더러 종료 처리 미지원 [32]도 열려 있다.

## 상세

### 1. WebView를 하나 공유할지, 탭·화면마다 둘지

**수명.** webview_flutter_android 4.14.1의 `AndroidWebViewController`는 생성될 때 Android `WebView`를 만들고, `WebViewWidget`은 그 인스턴스를 platform view로 붙이기만 한다 [2]. iOS 구현도 controller가 `WKWebView`를 갖는다 [22]. 관리자는 v4부터 WebView가 widget이 아니라 controller에 묶여 있어서 widget tree에 없어도 쓸 수 있다고 답했다 [3]. 반대로 controller를 직접 dispose하는 API는 없다. widget을 없앤 뒤에도 Android WebView의 JS가 계속 실행된다는 이슈가 열려 있다 [33].

flutter_inappwebview는 `InAppWebViewKeepAlive`로 같은 일을 명시적으로 하지만, keepAlive 하나에 활성 widget은 하나뿐이고 둘에 쓰면 crash한다 [34]. `HeadlessInAppWebView`로 widget 없이 미리 로드할 수도 있다 [35]. 이 패키지의 마지막 안정판은 2024-10의 6.1.5다 [36].

**메모리.** WebView 메모리(그래픽, DOM, JS 런타임)는 대부분 native 메모리에 잡힌다 [37]. Android 8 이상의 WebView는(일부 저메모리 32비트 기기 제외) 앱마다 out-of-process 렌더러 하나를 쓰고, Profile을 여러 개 만들 때만 Profile마다 렌더러가 따로 생긴다 [4]. 따라서 WebView를 나눠도 렌더러 장애는 격리되지 않는다. 앱이 `onRenderProcessGone`을 구현하지 않으면 렌더러 crash가 앱 프로세스 crash로 이어진다 [4]. webview_flutter_android는 이 콜백을 노출하지 않는다 [32]. WebView 1개당 메모리를 제시하는 공식 수치는 찾지 못했다.

**첫 로드.** WebView마다 별도 문서이므로 Next.js 번들 로드와 hydration이 WebView마다 일어난다. 한 WebView 안에서는 `<Link>`와 `router.push`가 client-side 전환이라 공유 layout이 유지된다. 반면 전체 페이지 로드는 상태를 지우고 스크롤을 초기화한다 [5]. 미리 로드하려면 controller에 `loadRequest`를 먼저 걸면 된다 [3]. 하지만 iOS에서 보이지 않는 `IndexedStack` 자식의 WebView가 화면에 나오기 전까지 내용을 그리지 않았다는 사용자 보고가 있다 [38]. go_router의 `StatefulShellBranch.preload` 문서는 자원 비용이 있으니 아껴 쓰라고 적는다 [39].

**탭 상태.** go_router `StatefulShellRoute.indexedStack`은 branch마다 Navigator를 두고, `IndexedStack`으로 한 branch만 보이면서 나머지의 상태를 유지한다 [39][40]. 탭마다 WebView를 두면 각 탭의 Web 상태가 그대로 남는다.

WebView 하나를 탭들이 공유하면 탭 전환이 Web 경로 이동이 된다. Next.js 16에서 `cacheComponents`를 켜면 떠난 경로를 unmount하지 않고 React `<Activity>`로 숨긴다(`display: none`). 그래서 상태, DOM, 스크롤이 보존된다. 보존은 최근 3개 경로까지다. 숨겨질 때 effect는 cleanup되고, 다시 보이면 재실행된다 [41][42].

**전환 애니메이션.** Host route 전환은 Flutter가 그린다. 3.47.7의 Android 기본은 `PredictiveBackPageTransitionsBuilder`다. 뒤로가기 제스처 중에는 predictive back 전환을, 그 밖에는 FadeForwards 전환을 쓴다. iOS 기본은 Cupertino 슬라이드다 [43][44]. `StatefulShellRoute.indexedStack`의 탭 전환에는 애니메이션이 없다 [39].

platform view가 낀 애니메이션은 비용이 크다 [45][46].

- Android 기본 모드인 Texture Layer Hybrid Composition은 빠른 스크롤에서 jank가 생긴다.
- Hybrid Composition은 raster 스레드와 platform 스레드를 합쳐서 FPS가 떨어질 수 있다.
- HCPP는 API 34 이상과 Vulkan이 필요한 실험 기능이다.

Flutter 문서는 애니메이션 동안 platform view 대신 스크린샷 텍스처를 쓰라고 권한다 [45][47].

WebView 하나 안의 전환은 React `<ViewTransition>`으로 한다. Next.js 16.4와 React 19.3에서는 설정이 필요 없고, Chromium 125 이상과 최근 Safari에서 동작한다. 단, 브라우저 back/forward에는 transition type이 없어서 방향 슬라이드가 재생되지 않는다 [6].

Android에서는 platform view 두 개를 보이고 숨길 때 한쪽이 다른 쪽 위에 잠시 그려지는 버그가 열려 있다 [31].

### 2. Host 화면을 다녀온 뒤 Web 화면 상태 유지

- **기본 동작.** Web 화면 route 위에 Host 화면을 push하면 아래 route는 `maintainState`에 따라 메모리에 남는다 [1]. `MaterialPageRoute`와 `CupertinoPageRoute`의 기본값은 `true`다 [18][48]. WebView 인스턴스와 문서가 그대로이므로 스크롤, 입력, JS 상태가 유지된다. S5의 "Web 아티스트 프로필 → Host 메시지 화면 → 복귀"는 이 구조에서 별도 작업 없이 상태가 남는다.
- **상태를 잃는 경우.** Web 화면 widget과 controller가 함께 버려질 때다(예: route를 replace할 때). controller를 상위 객체에 두면 widget을 다시 만들어도 같은 WebView가 붙는다 [2][3]. 한 WebView를 동시에 두 widget에 붙일 수 없다는 제약은 flutter_inappwebview 문서에만 명시돼 있다 [34].
- **프로세스 종료 뒤 복원.** Android `WebView.saveState`는 기록과 PageState(폼 입력, iframe 스크롤 등)를 저장하지만, 앱 전체 Bundle에 1MB 한도가 있다 [12][49]. webview_flutter_android 4.14.1에는 이 API가 노출되어 있지 않다 [2].
- **iOS에서 가려진 WebView.** iOS 엔진은 현재 프레임에 합성되지 않은 platform view를 superview에서 떼어낸다 [50]. 즉 Host 화면이 Web 화면을 완전히 덮으면 WKWebView가 view hierarchy에서 빠진다. 이때 `document.visibilityState`와 JS 타이머가 어떻게 되는지는 확인하지 못했다.
- **복귀 시 갱신(안 읽은 수).** Host는 `RouteObserver`와 `RouteAware.didPopNext`로 복귀 시점을 안다. `didPopNext`는 위 route가 pop되어 현재 route가 다시 보일 때 불린다 [1]. 이때 Event를 보내면 Web이 데이터를 갱신할 수 있다. TanStack Query의 기본 focus refetch는 `visibilitychange`를 듣는데, `focusManager.setEventListener`와 `setFocused`로 다른 신호를 쓰게 바꿀 수 있다 [51]. 안 읽은 수처럼 Host가 원천인 값은 Event에 값 자체를 실어 보낼 수도 있다.
- **Web 경로 사이의 이동.** `cacheComponents`의 Activity는 경로가 다시 보일 때 effect를 재실행한다. 그래서 Web 경로 사이를 오갈 때는 Web 안에서 "다시 보임"을 처리할 수 있다 [41]. 하지만 Host 화면 왕복은 Web 경로를 바꾸지 않으므로 이 재실행이 일어나지 않는다.

### 3. Android 뒤로가기와 WebView 기록, Web 안 층 닫기

**플랫폼 규칙.**

- Android 16(API 36)을 대상으로 하고 Android 16 이상에서 실행되면, predictive back 시스템 애니메이션(back-to-home, cross-activity, cross-task)이 기본으로 켜진다. 이때 `onBackPressed`는 호출되지 않고 `KEYCODE_BACK`도 전달되지 않는다. 임시 opt-out은 `android:enableOnBackInvokedCallback="false"`다 [8].
- Android 15에서는 opt-in한 앱에만 시스템 애니메이션이 보이고, Android 13·14에서는 개발자 옵션이 필요하다 [52].
- `OnBackPressedCallback`이나 `PRIORITY_DEFAULT`·`PRIORITY_OVERLAY`의 `OnBackInvokedCallback`이 활성화돼 있으면 predictive back 애니메이션이 실행되지 않고, 앱이 뒤로가기를 처리해야 한다. 그래서 콜백의 활성 여부를 UI 상태에 맞춰 미리 바꿔 두라고 한다 [52].
- WebView라면 `doUpdateVisitedHistory`에서 `isEnabled = webView.canGoBack()`으로 맞추는 것이 공식 codelab의 예다 [13].
- 이 저장소의 Host는 `targetSdk = flutter.targetSdkVersion`(3.47.7 기본값 36)을 쓰고, manifest에 이 속성이 없다 [7][53][54].

**Flutter의 연결 구조(3.47.7 소스).** `PopScope(canPop: false)`를 두면 아래 순서로 이어진다.

1. route의 `popDisposition`이 `doNotPop`이 되고, route가 `NavigationNotification(canHandlePop: true)`를 보낸다 [1].
2. `WidgetsApp`이 이를 받아 `SystemNavigator.setFrameworkHandlesBack(true)`를 호출한다 [55][56].
3. `FlutterActivity`가 `OnBackInvokedCallback`을 등록한다(API 34 이상은 `OnBackAnimationCallback`). 반대로 Flutter가 `canHandlePop: false`를 알리면 콜백을 해제해서 시스템이 back-to-home을 맡게 한다 [10].

`PopScope` 문서도 `canPop: false`이면 predictive back이 애니메이션되지 않는다고 적는다 [9].

- **`canPop`은 미리 정하는 값이다.** `onPopInvokedWithResult`는 pop이 일어나거나 취소된 뒤에 불리므로 그 자리에서 막을 수 없다 [9]. 비동기 확인은 `canPop: false`로 두고, 콜백에서 확인한 뒤 직접 `pop()`하는 것이 공식 마이그레이션 예다 [57]. 탭별 중첩 Navigator는 `NavigatorPopHandler`로 뒤로가기를 넘긴다 [58].
- **WebView 기록 상태.** webview_flutter의 `canGoBack()`은 비동기라서 [11] `canPop`에 바로 쓸 수 없고, 값을 캐시해 둬야 한다.
  - Android에서는 `onUrlChange`가 `doUpdateVisitedHistory`에서 오므로 [2], 그때 `canGoBack()`을 다시 읽는다. Android에는 canGoBack 변화 리스너가 따로 없다.
  - iOS에서는 `WebKitWebViewController.setOnCanGoBackChange`(KVO, wkwebview 3.17.0 이상)로 변화를 직접 받는다 [22][59].

**Web 쪽 규칙.**

- `router.push`는 history 항목을 추가하고 `replace`는 추가하지 않는다 [23]. `router.back()`의 구현은 `window.history.back()`이다 [60]. 그래서 Host의 `goBack()`과 Web의 `router.back()`은 같은 기록을 움직인다.
- 인터셉트·병렬 라우트 모달은 뒤로가기로 닫히고 앞으로가기로 다시 열린다. 새로고침이나 공유 링크(hard navigation)로 들어오면 모달 대신 전체 페이지가 그려진다 [14][61].
- `useState`로만 연 팝업은 기록에 없다. 그래서 Host가 `goBack()`하면 팝업은 그대로 두고 그 아래 페이지가 뒤로 간다. Next.js 가이드는 다이얼로그가 열렸는지를 search param에서 파생하는 예를 보여준다 [41].
- Web은 브라우저 뒤로가기(popstate)를 취소할 수 없다. `<Link onNavigate>`의 `preventDefault()`는 Link를 통한 client-side 이동에만 적용된다(15.3 이상) [17]. 따라서 S2의 "작성 중 이탈 확인"을 시스템 뒤로가기에 걸려면 Host의 협조가 필요하다.

**선례.**

- **Capacitor `App.addListener('backButton')`(Android 전용).** 리스너를 달면 기본 뒤로가기가 꺼진다. 그래서 필요하면 `window.history.back()`을 직접 부르고, 끝낼 때는 `App.exitApp()`을 쓴다. 이벤트에는 `canGoBack`이 실린다 [15].
- **Ionic `ionBackButton`.** 우선순위 핸들러 중 가장 높은 하나만 실행하고, `processNextHandler()`로 다음 핸들러에 넘긴다. 내장 우선순위는 오버레이 100, 메뉴 99, 내비게이션 0이다 [16].
- **웹 표준 `CloseWatcher`.** Chromium은 Android 뒤로가기를 close request로 보내며, Android WebView도 대상으로 출시했다고 밝혔다 [62]. Safari는 아직 preview 단계라서 [63] iOS에서는 쓸 수 없다. Host가 뒤로가기를 가로채는 구조에서 close request가 WebView 콘텐츠까지 가는지는 확인하지 못했다.

**GLOSSARY와의 간극.** "Host가 Web에 처리했는지 묻기"는 Host→Web 방향의 응답 쌍이지만, GLOSSARY의 Call은 Web→Host만 정의한다. 가능한 형태는 세 가지다.

- (a) Event로 묻고, 상관 ID를 담은 Message로 답을 받는다.
- (b) `runJavaScriptReturningResult`로 동기 함수의 반환값을 받는다. Promise는 기다리지 않고, iOS 14 이상에서는 `undefined`와 `null`이 오류가 된다 [11].
- (c) Web이 상태 변화를 Message로 미리 알려서, Host가 물을 필요가 없게 한다.

**열린 이슈(2026-10 기준).**

- 중첩 Navigator와 predictive back의 충돌 [64]
- 스택이 남아 있는데 predictive back이 Host를 종료함 [65]
- `StatefulShellRoute`에서 뒤로가기를 누르면 Host가 종료됨 [28]
- branch마다 한 화면씩 pop됨(수정 PR 대기) [29]
- branch를 떠난 뒤 뒤로가기 전체가 멈춤 [30]
- `PopScope`와 go_router의 호환 문제는 16.0.0에서 branch route 쪽이 고쳐졌지만, 이후에도 재현 보고가 있다 [66][67].

### 4. iOS 스와이프 뒤로가기와 WebView 제스처

- **Flutter 스와이프의 정체.** Host(Flutter)의 iOS 스와이프 뒤로가기는 시스템 제스처가 아니라 Flutter의 `CupertinoRouteTransitionMixin`이 인식한다 [9]. 시작 영역은 왼쪽 가장자리(leading edge)에서 `max(왼쪽 safe area 여백, 20)` 폭의 띠다 [18].
- **스와이프가 꺼지는 조건.** `popGestureEnabled`는 첫 route일 때, 내부 pop을 처리 중일 때, `doNotPop`(곧 `canPop: false`)일 때, 전환 중일 때 false다 [1]. `fullscreenDialog` route는 아래에서 올라오는 전환을 쓰고 스와이프 감지기가 없다 [18]. `canPop: false`면 제스처 자체가 감지되지 않아 `onPopInvokedWithResult`도 불리지 않는다 [9][68].
- **UIKit 제스처와의 관계.** `interactivePopGestureRecognizer`는 `UINavigationController`의 것이라 [69] Flutter route에는 해당하지 않는다. iOS 26은 콘텐츠 영역 어디서든 시작하는 `interactiveContentPopGestureRecognizer`를 추가했다 [20]. 하지만 Flutter Cupertino route는 여전히 가장자리 20pt만 쓴다. #180309가 열려 있고, cupertino_ui 1.1.3도 같다 [21][70]. Flutter 화면을 UIKit 내비게이션 안에 넣는 구조에서는 이 새 제스처가 Flutter 가로 스크롤과 충돌한다는 이슈도 있다 [71].
- **WKWebView 자체 스와이프와의 겹침.** WKWebView의 `allowsBackForwardNavigationGestures`는 기본 false이고 [19], webview_flutter에서는 `WebKitWebViewController.setAllowsBackForwardNavigationGestures`로 켠다 [22]. 두 스와이프 모두 왼쪽 가장자리에서 시작하므로 함께 켜면 겹친다. platform view에 `gestureRecognizers`를 주지 않으면, Flutter 제스처 경합에서 다른 인식기가 차지하지 않은 포인터만 WebView로 간다 [72]. Flutter 뒤로가기 감지기는 페이지 위 Stack의 가장자리에 있어서 구조상 경합에 먼저 참여한다. 그러나 실제로 어느 쪽이 이기는지는 확인하지 않았다.
- **팝업·작성 화면이 열렸을 때 막는 방법.**
  - (a) Web이 팝업 열림을 Message로 알리고 Host가 `canPop: false`로 바꾸면 스와이프가 사라진다 [1][9].
  - (b) 작성 화면을 Host의 `fullscreenDialog` route로 띄우면 스와이프가 없다 [18].
  - (c) 스와이프를 열어 두면 Web 화면 route 전체가 pop되어 작성 중인 내용을 잃는다.
- **iOS 26 터치 문제.** iOS 26 초기의 WebView 탭 무반응은 WebKit이 iOS 26.4에서 고쳤다. Host 오버레이를 누른 터치가 아래 WebView로 새는 문제는 Flutter가 hitTest 방식으로 고쳤고, 이 수정은 3.47.7 태그에 들어 있다 [73][74]. wkwebview 3.27.0은 `uiKitGestureBlockingPolicy`를 추가했다 [59].

### 5. Next.js App Router 이동과 Host가 경로 변화를 아는 방법

- **이동 API.** `useRouter`의 `push`는 history 항목을 추가하고 `replace`는 추가하지 않으며, `back`·`forward`는 브라우저 history를 움직인다. `refresh`는 서버에 다시 요청하되 client state와 스크롤을 유지하고, `bfcacheId`는 push·replace 때 바뀌고 back·forward 때는 유지된다 [23]. `<Link>`는 `replace`, `scroll`, `onNavigate`, `transitionTypes`(16.2 이상)를 받는다. `scroll`의 기본값은 true로, Page가 보이면 위치를 유지하고 보이지 않으면 첫 Page 요소로 스크롤한다 [17]. `window.history.pushState`와 `replaceState`도 router와 통합돼 `usePathname`·`useSearchParams`가 따라간다 [5].
- **모달 라우트.** 인터셉트 라우트(`(.)`, `(..)`, `(..)(..)`, `(...)`)는 client-side 이동에서만 가로채고, 공유 링크나 새로고침에서는 전체 페이지를 그린다 [61]. 병렬 라우트 슬롯은 soft 이동에서는 활성 상태를 유지하고, hard 이동에서는 `default.js`(없으면 404)를 그린다. 모달은 `router.back()`이나 Link로 닫는다. Link로 닫을 때는 슬롯이 `null`을 반환하는 route에 맞아야 한다 [14]. Link의 기본 동작은 push이므로 [17], Link로 닫으면 기록이 하나 더 쌓인다.
- **Host가 경로를 아는 방법.**
  1. WebView 신호: `NavigationDelegate.onUrlChange`(Android는 `doUpdateVisitedHistory`, iOS는 `WKWebView.URL` KVO) [2][22][75]와 iOS `setOnCanGoBackChange` [22]가 있다. webview_flutter 문서는 "URL이 바뀔 때"라고만 적어서 pushState에서의 동작은 확인이 필요하다. 참고로 flutter_inappwebview는 `onUpdateVisitedHistory`가 pushState·replaceState·popstate에서도 불린다고 명시한다 [76].
  2. Web Message: root layout의 client component에서 `usePathname`·`useSearchParams` 변화를 감지하는 공식 예가 있다 [23]. `instrumentation-client`(15.3 도입)의 `onRouterTransitionStart(url, 'push' | 'replace' | 'traverse')`도 쓸 수 있다. 세 번째 인자인 세부 이벤트는 16.3의 실험 기능이다 [24]. 이 방식은 경로와 함께 "모달 열림", "작성 중" 같은 의미도 보낼 수 있다.
- **Host가 Web 경로를 바꾸는 방법.** Event로 경로를 보내 Web이 `router.push`하면 client-side 전환이다. 반면 `loadRequest`로 URL을 다시 읽으면 전체 로드라서 상태와 스크롤이 초기화된다 [5].

### 6. 같은 탭을 다시 누르면 맨 위로

- **UIKit.** `UITabBarController`는 탭을 누르면, 이미 선택된 탭이어도 그 탭의 루트 뷰를 보여준다 [25]. HIG는 탭 바가 섹션마다 현재 내비게이션 상태를 유지한 채 전환하게 해 준다고 설명한다 [77].
- **Material(M1 보관 문서).** 활성 항목을 다시 누르면 뷰의 맨 위로 가고, Android 뒤로가기는 하단 탭 사이를 이동하지 않는다 [26]. 현재 M3 가이드라인의 문구는 페이지가 스크립트로만 렌더링돼 확인하지 못했다.
- **go_router.** 공식 예제는 이미 활성인 탭을 누르면 `goBranch(index, initialLocation: index == currentIndex)`로 초기 위치로 보낸다 [27].
- **Web 탭.** 탭 바가 Host에 있으면 재선택은 Host만 안다. 그래서 Host가 Event로 알리고, Web이 "위로 스크롤하고, 이미 맨 위면 탭 루트로" 같은 규칙을 적용해야 한다.
- **iOS 상태 표시줄 탭.** Flutter 엔진은 화면 밖의 UIScrollView로 상태 표시줄 탭을 받아 프레임워크에 넘기고 [78], `Scaffold`는 primary scroll controller를 맨 위로 올린다 [79]. 그런데 Apple 문서에 따르면 iPhone에서는 `scrollsToTop`이 켜진 스크롤 뷰가 화면에 둘 이상이면 아무 일도 일어나지 않는다 [80]. WKWebView의 scroll view(기본 `true`)와 함께 있을 때의 실제 동작은 확인하지 못했다. 중첩 Navigator에서 상태 표시줄 탭이 동작하지 않는다는 이슈도 열려 있다 [81].

## Reference App에 주는 시사점

아래는 「화면 구성과 뒤로가기 설계 (S5)」가 정할 축과 선택지다. 공통 전제가 하나 있다. 어느 선택지든 Host 화면(메시지, 이미지 뷰어 등)을 루트 Navigator에 push하면 아래 Web 화면의 상태는 남는다(§2).

**A. WebView 배치**

| 선택지 | 얻는 것 | 치르는 것 |
|---|---|---|
| A1. WebView 1개를 모든 탭이 공유, 탭 전환은 Web 경로 이동 | Next.js 부팅 1회, 메모리 최소, Web의 메모리 상태(TanStack Query 캐시 등) 공유 | 탭별 상태 보존을 Web이 책임짐(`cacheComponents`는 최근 3개 경로까지), 탭 전환을 history에 남기지 않는 규칙 필요(Material 관례상 뒤로가기는 탭 사이를 이동하지 않음), 탭 전환 애니메이션도 Web 몫 |
| A2. 탭마다 WebView(`StatefulShellRoute.indexedStack` 등) | 탭별 Web 상태가 자연히 유지, 탭별 뒤로가기 기록 분리 | 탭 수만큼 문서·JS 런타임, 탭 사이 Web 메모리 상태 비공유(동기화는 Event로), Android 다중 platform view 버그, go_router와 predictive back의 열린 버그 |
| A3. Web 화면마다 WebView(Web 상세도 Host route) | Host 전환, iOS 스와이프, predictive back이 화면마다 자연스럽게 동작 | 화면마다 로드 공백과 메모리, GC 전까지 WebView가 남음 [33], Web 안 이동과 Host route 이동의 경계를 따로 설계해야 함 |

**B. 뒤로가기 협조**

| 방식 | 동작 | 얻는 것 | 치르는 것 |
|---|---|---|---|
| B1. 기록 위임 | 닫을 수 있는 Web 층은 모두 history로 만든다(인터셉트 라우트, search param). Host는 `canPop = !webCanGoBack`을 유지하고 뒤로가기에 `goBack()` | predictive back이 정확함(기록이 없으면 back-to-home), Bridge 추가 없음 | Web 설계 제약(상태로만 여는 팝업 금지), 작성 이탈 확인을 뒤로가기에 걸 수 없음, Android에 canGoBack 리스너가 없어 `onUrlChange`에 의존 |
| B2. Web 위임(Capacitor·Ionic형) | Web 화면에서는 항상 `canPop: false`. 뒤로가기를 Event로 넘기면 Web의 우선순위 핸들러가 처리하거나 "처리 안 함"을 알리고, 그러면 Host가 pop하거나 종료 | 바텀시트 닫기, 작성 확인 등 모든 경우를 Web 한곳에서 처리 | Web 화면에서 predictive back 애니메이션과 iOS 스와이프가 사라짐 [9], Host→Web 응답 쌍 필요(GLOSSARY 공백), Web이 응답하지 않을 때의 기본 동작(타임아웃) 필요 |
| B3. 상태 동기 | Web이 "뒤로가기로 닫을 층이 있다/없다"를 바뀔 때마다 Message로 보내고 Host가 `canPop`에 반영. 뒤로가기 때 Host는 Event로 닫기를 지시하거나 `goBack()` | 애니메이션이 정확하고 작성 확인도 가능 | 상태가 늦게 도착하면 잘못 동작, 구현량이 가장 많음 |

**C. iOS 스와이프**

- C1. Flutter 가장자리 스와이프만 쓴다(WKWebView 제스처는 끔).
- C2. Web 기록이 남은 동안 Flutter 스와이프를 끄고 WKWebView 스와이프를 쓴다. 두 제스처의 겹침을 검증해야 한다.
- C3. 팝업·작성 중에는 스와이프를 없앤다(`canPop: false`, 또는 작성 화면을 Host `fullscreenDialog`로).

**D. 경로 신호**

- D1. WebView 신호만 쓴다. Web을 고칠 필요는 없지만 의미 정보가 없고 플랫폼 차이가 있다.
- D2. Web Message(`onRouterTransitionStart`, `usePathname`)를 쓴다. 의미를 전할 수 있지만 계약 항목이 늘어난다.
- D3. 둘 다 써서 교차 확인한다.

**E. 복귀 시 갱신(S5 안 읽은 수)**

- E1. `didPopNext`에서 Event를 보내고, Web이 `focusManager`로 refetch한다.
- E2. Host가 값 자체를 Event로 보낸다.
- E3. `visibilitychange`에 기댄다(동작 미확인).

**F. 탭 재선택**

- F1. "탭 재선택" Event 하나를 보내고 Web이 "맨 위로, 이미 위면 루트로" 규칙을 적용한다.
- F2. Host가 `runJavaScript`로 직접 스크롤한다.

**G. Android manifest**

- `enableOnBackInvokedCallback`을 명시할지 정한다. 명시하지 않으면 기기 OS 버전(13·14·15·16)에 따라 predictive back 동작이 달라진다 [8][52].

## 확인하지 못한 것과 새로 생긴 질문

**확인하지 못한 것**(시뮬레이터·에뮬레이터로 확인할 것)

- `onUrlChange`가 Next.js client-side 이동(pushState·replaceState·popstate)에서 플랫폼별로 불리는지.
- Host 화면이 Web 화면을 덮을 때 WebView의 `visibilitychange`, JS 타이머, TanStack Query focus refetch가 어떻게 동작하는지. iOS는 WKWebView가 view hierarchy에서 빠진다 [50].
- Flutter 가장자리 스와이프와 `allowsBackForwardNavigationGestures`를 함께 켰을 때 어느 쪽이 이기는지, 그리고 WKWebView 스와이프가 pushState 항목에도 동작하는지.
- WKWebView가 화면 밖(`IndexedStack`의 비선택 탭)에서도 로드·렌더링되는지 [38].
- WebView 1개당 메모리와 첫 로드 시간(공식 수치 없음).
- App Router의 back·forward 스크롤 복원이 WebView에서도 맞게 동작하는지.
- WKWebView가 함께 있을 때 iOS 상태 표시줄 탭이 어떻게 동작하는지 [80].
- webview_flutter에서 한 controller를 두 widget에 동시에 붙이면 어떻게 되는지(문서 없음).
- Host가 뒤로가기를 가로채는 구조에서 Android WebView의 `CloseWatcher`가 동작하는지 [62].
- Material 3 내비게이션 바 가이드라인의 재선택 문구.

**새로 생긴 질문**

- Host→Web 응답 쌍("Web이 뒤로가기를 처리했는가")을 Bridge 계약과 GLOSSARY에 넣을지. B2를 고르면 필요하다.
- Web에서 `cacheComponents`를 켤지. 켜면 경로 보존(최근 3개)과 effect의 cleanup·재실행 의미가 바뀌어 Bridge 구독 코드에도 영향이 있다 [42].
- Host 라우팅에 go_router를 쓸지. 쓴다면 `StatefulShellRoute`와 predictive back의 열린 버그를 어떻게 피할지.
- Android `enableOnBackInvokedCallback`을 명시할지(G).
- WebView 렌더러가 종료됐을 때 어떻게 복구할지. Android에서는 패키지가 콜백을 노출하지 않고 모든 WebView가 렌더러를 공유한다 [4][32]. 로딩·오프라인·에러 화면 정책과 함께 다룰 문제다.

## 출처

1. [Flutter 3.47.7 소스 `widgets/routes.dart` (ModalRoute.maintainState·popGestureEnabled·RouteAware)](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/widgets/routes.dart)
2. [webview_flutter_android 4.14.1 소스 `android_webview_controller.dart`](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/lib/src/android_webview_controller.dart)
3. [flutter/flutter#51875 [webview_flutter] Allow to preload content into an off-screen webview (관리자 답변 2023-01-22)](https://github.com/flutter/flutter/issues/51875)
4. [Chromium `android_webview/renderer/README.md` (WebView 렌더러 프로세스 모델)](https://chromium.googlesource.com/chromium/src/+/main/android_webview/renderer/README.md)
5. [Next.js 문서: Linking and Navigating (2026-09-09 갱신)](https://nextjs.org/docs/app/getting-started/linking-and-navigating)
6. [Next.js 문서: Designing view transitions (2026-10-15 갱신)](https://nextjs.org/docs/app/guides/view-transitions)
7. [Flutter 3.47.7 `flutter_tools` `FlutterExtension.kt` (기본 targetSdkVersion 36)](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt#L34)
8. [Android 문서: Behavior changes: Apps targeting Android 16 or higher (2026-10-16 갱신)](https://developer.android.com/about/versions/16/behavior-changes-16)
9. [Flutter 3.47.7 소스 `widgets/pop_scope.dart` (PopScope)](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/widgets/pop_scope.dart)
10. [Flutter 3.47.7 엔진 `FlutterActivity.java` (OnBackInvokedCallback 등록·해제)](https://github.com/flutter/flutter/blob/3.47.7/engine/src/flutter/shell/platform/android/io/flutter/embedding/android/FlutterActivity.java#L657-L736)
11. [webview_flutter 4.14.1 소스 `webview_controller.dart`](https://github.com/flutter/packages/blob/webview_flutter-v4.14.1/packages/webview_flutter/webview_flutter/lib/src/webview_controller.dart#L181-L248)
12. [Android 문서: Build web apps in WebView — Navigate web page history (2026-10-16 갱신)](https://developer.android.com/develop/ui/views/layout/webapps/webview)
13. [Android codelab: Update your app to support future predictive back gesture](https://codelabs.developers.google.com/handling-gesture-back-navigation)
14. [Next.js 문서: Parallel Routes (2026-10-15 갱신)](https://nextjs.org/docs/app/api-reference/file-conventions/parallel-routes)
15. [Capacitor 문서: App API (`backButton`, v8)](https://capacitorjs.com/docs/apis/app)
16. [Ionic 문서: Hardware Back Button (v9)](https://ionicframework.com/docs/developing/hardware-back-button)
17. [Next.js 문서: Link Component (2026-08-25 갱신)](https://nextjs.org/docs/app/api-reference/components/link)
18. [Flutter 3.47.7 소스 `cupertino/route.dart` (뒤로가기 제스처 영역·fullscreenDialog)](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/cupertino/route.dart)
19. [Apple 문서: WKWebView.allowsBackForwardNavigationGestures](https://developer.apple.com/documentation/webkit/wkwebview/allowsbackforwardnavigationgestures)
20. [Apple 문서: UINavigationController.interactiveContentPopGestureRecognizer (iOS 26.0+)](https://developer.apple.com/documentation/uikit/uinavigationcontroller/interactivecontentpopgesturerecognizer)
21. [flutter/flutter#180309 iOS 26 Back Gesture area](https://github.com/flutter/flutter/issues/180309)
22. [webview_flutter_wkwebview 3.27.0 소스 `webkit_webview_controller.dart`](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/lib/src/webkit_webview_controller.dart#L159-L364)
23. [Next.js 문서: useRouter (2026-07-01 갱신)](https://nextjs.org/docs/app/api-reference/functions/use-router)
24. [Next.js 문서: instrumentation-client.js (2026-07-28 갱신)](https://nextjs.org/docs/app/api-reference/file-conventions/instrumentation-client)
25. [Apple 문서: UITabBarController](https://developer.apple.com/documentation/uikit/uitabbarcontroller)
26. [Material Design (보관된 M1 가이드라인): Bottom navigation](https://m1.material.io/components/bottom-navigation.html)
27. [go_router 18.1.0 예제 `stateful_shell_route.dart`](https://github.com/flutter/packages/blob/go_router-v18.1.0/packages/go_router/example/lib/stateful_shell_route.dart#L175-L182)
28. [flutter/flutter#153672 [go_router] App Exits Instead of Navigating Back with StatefullShellRoute (Android)](https://github.com/flutter/flutter/issues/153672)
29. [flutter/flutter#188018 [go_router] Android predictive back pops one screen from each StatefulShellBranch](https://github.com/flutter/flutter/issues/188018)
30. [flutter/flutter#193098 [go_router] Back button stops working app-wide after leaving a StatefulShellRoute branch](https://github.com/flutter/flutter/issues/193098)
31. [flutter/flutter#194048 Multiple PlatformViews display incorrectly when showing and hiding](https://github.com/flutter/flutter/issues/194048)
32. [flutter/flutter#130297 [webview_flutter] Add support for detecting process termination on Android](https://github.com/flutter/flutter/issues/130297)
33. [flutter/flutter#119616 Support to manually dispose a WebViewController](https://github.com/flutter/flutter/issues/119616)
34. [flutter_inappwebview 문서: Keep Alive (6.x)](https://inappwebview.dev/docs/webview/keep-alive)
35. [flutter_inappwebview 문서: HeadlessInAppWebView (6.x)](https://inappwebview.dev/docs/webview/headless-in-app-webview/)
36. [pub.dev: flutter_inappwebview 버전 목록](https://pub.dev/packages/flutter_inappwebview/versions)
37. [Android 문서: Manage and diagnose WebView memory (2026-10-16 갱신)](https://developer.android.com/develop/ui/views/layout/webapps/manage-webview-memory)
38. [flutter/flutter#162249 [webview_flutter] WebView inside IndexedStack on iOS does not load content until the tab becomes visible](https://github.com/flutter/flutter/issues/162249)
39. [go_router 18.1.0 소스 `route.dart` (StatefulShellRoute·StatefulShellBranch)](https://github.com/flutter/packages/blob/go_router-v18.1.0/packages/go_router/lib/src/route.dart#L842-L1203)
40. [Flutter 3.47.7 소스 `widgets/indexed_stack.dart`](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/widgets/indexed_stack.dart#L21-L41)
41. [Next.js 문서: How Next.js preserves UI state with Activity (2026-10-15 갱신)](https://nextjs.org/docs/app/guides/preserving-ui-state)
42. [Next.js 문서: cacheComponents (2026-10-15 갱신)](https://nextjs.org/docs/app/api-reference/config/next-config-js/cacheComponents)
43. [Flutter 3.47.7 소스 `material/page_transitions_theme.dart` (플랫폼별 기본 전환)](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/material/page_transitions_theme.dart#L764-L771)
44. [Flutter 3.47.7 소스 `material/predictive_back_page_transitions_builder.dart`](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/material/predictive_back_page_transitions_builder.dart#L17-L101)
45. [Flutter 문서: Hosting native Android views (2026-09-29 갱신)](https://docs.flutter.dev/platform-integration/android/platform-views)
46. [webview_flutter_android 4.14.1 README (Display Mode)](https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/README.md)
47. [Flutter 문서: Hosting native iOS views (2026-08-13 갱신)](https://docs.flutter.dev/platform-integration/ios/platform-views)
48. [Flutter 3.47.7 소스 `material/page.dart` (`MaterialPageRoute.maintainState` 기본값)](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/material/page.dart#L41)
49. [Android 문서: Manage WebView state efficiently (2026-08-13 갱신)](https://developer.android.com/develop/ui/views/layout/webapps/manage-state)
50. [Flutter 3.47.7 엔진 `FlutterPlatformViewsController.mm` (합성되지 않은 platform view 제거)](https://github.com/flutter/flutter/blob/3.47.7/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm#L1085-L1102)
51. [TanStack Query 문서: Window Focus Refetching](https://tanstack.com/query/latest/docs/framework/react/guides/window-focus-refetching)
52. [Android 문서: Add support for the predictive back gesture (2026-10-16 갱신)](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture)
53. [이 저장소 `app/android/app/build.gradle.kts` (`explore/real-world-example`)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/explore/real-world-example/app/android/app/build.gradle.kts#L23)
54. [이 저장소 `app/android/app/src/main/AndroidManifest.xml` (`explore/real-world-example`)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/explore/real-world-example/app/android/app/src/main/AndroidManifest.xml)
55. [Flutter 3.47.7 소스 `widgets/app.dart` (`_defaultOnNavigationNotification`)](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/widgets/app.dart#L1437-L1455)
56. [Flutter 3.47.7 소스 `services/system_navigator.dart`](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/services/system_navigator.dart#L14-L44)
57. [Flutter 문서: Android predictive back (breaking change, 2026-08-01 갱신)](https://docs.flutter.dev/release/breaking-changes/android-predictive-back)
58. [Flutter 3.47.7 소스 `widgets/navigator_pop_handler.dart`](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/widgets/navigator_pop_handler.dart#L10-L70)
59. [webview_flutter_wkwebview CHANGELOG (3.17.0 canGoBack 리스너, 3.27.0 uiKitGestureBlockingPolicy)](https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/CHANGELOG.md)
60. [Next.js v16.4.2 소스 `app-router-instance.ts` (`back`·`forward`)](https://github.com/vercel/next.js/blob/v16.4.2/packages/next/src/client/components/app-router-instance.ts#L325-L326)
61. [Next.js 문서: Intercepting Routes (2026-10-15 갱신)](https://nextjs.org/docs/app/api-reference/file-conventions/intercepting-routes)
62. [blink-dev: Intent to Ship: Close requests for CloseWatcher, `<dialog>`, and `popover=""`](https://groups.google.com/a/chromium.org/g/blink-dev/c/jM5au7yYzHM/m/5SWuXPMdAgAJ)
63. [MDN browser-compat-data `api/CloseWatcher.json`](https://github.com/mdn/browser-compat-data/blob/main/api/CloseWatcher.json)
64. [flutter/flutter#152323 Interleaved nested Navigators and Predictive Back](https://github.com/flutter/flutter/issues/152323)
65. [flutter/flutter#145290 Predictive back can close app when navigation stack is not empty](https://github.com/flutter/flutter/issues/145290)
66. [go_router CHANGELOG (18.1.0 기준)](https://github.com/flutter/packages/blob/go_router-v18.1.0/packages/go_router/CHANGELOG.md)
67. [flutter/flutter#138737 [go_router] PopScope seems to be incompatible with GoRouter](https://github.com/flutter/flutter/issues/138737)
68. [flutter/flutter#138624 PopScope does not invoke onPopInvoked for iOS back gesture when canPop set to false](https://github.com/flutter/flutter/issues/138624)
69. [Apple 문서: UINavigationController.interactivePopGestureRecognizer](https://developer.apple.com/documentation/uikit/uinavigationcontroller/interactivepopgesturerecognizer)
70. [cupertino_ui 1.1.3 소스 `route.dart`](https://github.com/flutter/packages/blob/cupertino_ui-v1.1.3/packages/cupertino_ui/lib/src/route.dart#L31)
71. [flutter/flutter#184507 [iOS Hybrid][iOS 26] interactiveContentPopGestureRecognizer conflicts with Flutter horizontal scroll](https://github.com/flutter/flutter/issues/184507)
72. [Flutter 3.47.7 소스 `widgets/platform_view.dart` (gestureRecognizers)](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/widgets/platform_view.dart#L121-L129)
73. [flutter/flutter#175099 [iOS] Tap interactions not working on iOS 26 for webview_flutter](https://github.com/flutter/flutter/issues/175099)
74. [flutter/flutter#185126 [ios][pv] Reland platform view hitTest approach (again)](https://github.com/flutter/flutter/pull/185126)
75. [Apple 문서: WKWebView.url (KVO 지원)](https://developer.apple.com/documentation/webkit/wkwebview/url)
76. [flutter_inappwebview 문서: InAppWebView (`onUpdateVisitedHistory`, 6.x)](https://inappwebview.dev/docs/webview/in-app-webview/)
77. [Apple Human Interface Guidelines: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
78. [Flutter 3.47.7 엔진 `FlutterViewController.mm` (상태 표시줄 탭)](https://github.com/flutter/flutter/blob/3.47.7/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm#L537-L572)
79. [Flutter 3.47.7 소스 `material/scaffold.dart` (`handleStatusBarTap`)](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter/lib/src/material/scaffold.dart#L2748-L2775)
80. [Apple 문서: UIScrollView.scrollsToTop](https://developer.apple.com/documentation/uikit/uiscrollview/scrollstotop)
81. [flutter/flutter#85603 [iOS] Statusbar tap to scroll top doesn't work in nested navigation](https://github.com/flutter/flutter/issues/85603)
