# Host는 webview_flutter에 플랫폼 코드를 붙여 Message의 출처와 프레임을 판정한다

Bridge는 Message를 보낸 출처와 메인 프레임 여부를 알아야 한다([ADR 0001](0001-web-screen-content-policy.md)). `webview_flutter`는 이 정보를 주지 않는다. 이 정보를 주는 `flutter_inappwebview`는 2024-10 이후 안정판이 없는 베타이고, 실측에서 응답이 다른 프레임으로 갔다. 그래서 Host는 1st-party인 `webview_flutter`를 쓰고, 출처 판정 통로(Android `addWebMessageListener`, iOS `WKScriptMessageHandlerWithReply` + `frameInfo`)와 Android 렌더러 종료 처리를 Kotlin·Swift 플랫폼 코드로 직접 붙인다. 패키지와 플랫폼 코드는 Host의 한 층에서만 다루므로, upstream이 기능을 더하거나 패키지를 바꿀 때 그 층만 고친다.

## Considered Options

- **`webview_flutter`만**: 출처·프레임 정보가 없어 ADR 0001의 전제를 지킬 수 없다.
- **`flutter_inappwebview` 6.2.0-beta.3**: 출처 판정, 렌더러 종료 처리, 커스텀 스킴, HttpOnly 쿠키가 모두 들어 있다. 하지만 2026-02 이후 커밋이 없는 1인 유지 베타다. `WebMessageListener` 응답이 다른 프레임으로 가고(Android 14건 중 4건, iOS 10건 중 8건), 기본 설정에서는 Bridge가 모든 프레임에 열린다. 이 구조를 가져다 쓴 앱이 그 결함까지 함께 가져간다.
- **`flutter_inappwebview` 6.1.5 패치·포크**: AGP 9 빌드 실패, App Store 거절 보고, SwiftPM 미지원을 직접 고쳐야 한다. `callHandler`에는 출처 정보도 없다.

## Consequences

- iOS에서는 커스텀 스킴을 붙일 수 없다(생성 시점 설정이라 External API로도 불가). 앱에 묶은 Web을 띄울 길은 `file://`이나 앱 안 localhost 서버뿐이다.
- Android 렌더러 종료는 패키지의 WebViewClient를 위임 클라이언트로 감싸 처리한다. 렌더러를 함께 쓰는 WebView를 모두 감싸야 하고, `setNavigationDelegate`를 다시 부르면 감싼 것이 풀린다. 패키지가 `window.open`용으로 만드는 임시 WebView는 감쌀 수 없어서 다중 창을 끈다. 그래서 WebView는 그 한 층에서만 만들고, `window.open`과 `target="_blank"`는 같은 WebView 안의 탐색이 된다.
- `webview_flutter`의 JavaScript 채널은 쓰지 않는다. 모든 프레임에 열리고 출처를 알려 주지 않는다. iOS에서는 `removeJavaScriptChannel`과 `enableZoom(true)`가 플랫폼 코드가 넣은 문서 시작 스크립트까지 지운다.
- Android System WebView가 `WEB_MESSAGE_LISTENER`를 지원하지 않는 기기에서는 Bridge를 열지 않는다. 출처를 모르는 통로로 대신하지 않는다.
- 플랫폼 코드는 External API 밖의 패키지 동작에도 기댄다. 구현 패키지를 올릴 때는 두 플랫폼에서 플랫폼 코드 통합 테스트를 통과해야 한다.

결정의 자세한 내용: [WebView 패키지 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/38)
