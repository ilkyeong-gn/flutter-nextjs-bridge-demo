# WebView 통로별 JS 쪽 모양과 Transport 최소 인터페이스 조사

- **질문**: [#59 WebView 통로별 JS 쪽 모양과 Transport 최소 인터페이스 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/59). WebView 패키지가 정해지지 않은 상태에서 Web 쪽 `Transport`가 담아야 할 최소 모양은 무엇이고, 프로토콜 층이 응답 통로를 가정해도 되는가?
- **조사일**: 2026-10-20
- **확인한 버전**: `webview_flutter` 4.14.1(flutter/packages `0259ad7`), `flutter_inappwebview` 6.2.0-beta.3 태그, androidx.webkit 소스(androidx-main `0e2330e`), Chromium `components/js_injection`(main), WebKit 소스(main), Apple Developer 문서(2026-10-20 조회)
- **이미 있는 사실을 가져온 곳**: [#28 패키지 비교](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/research/webview-package-matrix/docs/research/webview-package-matrix.md)(이하 R28), [#36 보안 지침](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/research/webview-security/docs/research/webview-security.md)(R36), [#48 실측](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/48)(R48), [프로토콜 선행 사례](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/research/bridge-protocol-prior-art/docs/research/bridge-protocol-prior-art.md)(RP). 이 문서는 그 위에 빈 곳(주입 시점, JS 객체 모양, 문서가 바뀔 때, 응답 구현 방식)만 1차 출처로 채웠다.

## 요약

- **통로가 주는 기본기는 세 가지로 갈린다.**
  - 한 방향 보내기만 있는 통로: `webview_flutter` JavaScript 채널, iOS `WKScriptMessageHandler`. Host→Web은 JS 실행(`runJavaScript`·`evaluateJavaScript`)뿐이다 [R28][3][8].
  - 양방향 Message 통로(짝 없음): Android `addWebMessageListener`, `WebMessagePort`, `flutter_inappwebview` `WebMessageListener`. Web이 `postMessage`로 보내고 `onmessage`로 받는다. Host는 아무 때나 보낼 수 있지만, `addWebMessageListener`는 Web이 먼저 한 번 보내야 응답 통로(reply proxy)가 생긴다 [1].
  - 요청-응답 짝 통로(Host가 먼저 못 보냄): iOS `WKScriptMessageHandlerWithReply`, `flutter_inappwebview` `callHandler`. 보낼 때마다 Promise가 하나 돌아오고, 응답은 한 번뿐이다 [5][10][11].
- **모든 통로가 공통으로 실을 수 있는 값은 문자열 하나다.** `webview_flutter` Android 채널은 `postMessage(String)`만 받는다 [7]. Android Message 통로는 String·ArrayBuffer [1], iOS는 직렬화 가능한 값이다 [5].
- **모든 통로는 문서 하나에 묶인다.** 문서가 바뀌면 JS 쪽 상태(대기 중인 Promise, 리스너, 포트)는 문서와 함께 사라진다. Android reply proxy는 보낸 문서에 묶여 있어 문서가 사라지면 메시지를 버린다 [2][13]. iOS reply handler는 해제되면 Promise를 거부한다 [5]. `callHandler`는 `evaluateJavascript`로 이행하므로 문서가 바뀌면 대기 중인 Promise가 영원히 끝나지 않는다(소스로 확인, 실측은 안 함) [10][11].
- **결론: 최소 Transport는 "문서 하나 동안 열리는 문자열 양방향 통로"다.** `send(text)`와 `onMessage(listener)` 두 개, 그리고 "통로가 있으면 열고 없으면 `null`"을 돌려주는 비동기 `connect()`면 모든 후보를 덮는다. 요청-응답 짝 맞추기(`id`), 타임아웃, 핸드셰이크는 프로토콜 층이 한다.
- **프로토콜 층은 응답 통로를 가정하면 안 된다.** 응답 통로가 없는 통로(JavaScript 채널, `WKScriptMessageHandler`, `addWebMessageListener`, 포트)가 후보에 있다. 반대로 Host가 먼저 보낼 수 없는 통로(`WithReply`, `callHandler`)도 있다. 두 성질을 다 덮는 공통분모는 "짝 없는 Message 통로 + 프로토콜의 자체 id"이고, 응답 통로 쪽 통로는 어댑터가 이 모양으로 감싼다. 프로토콜 층이 가정해도 되는 것은 두 가지뿐이다. Web이 먼저 말한다(핸드셰이크), 그리고 응답이 안 올 수 있다(타임아웃).

## 통로별 JS 쪽 모양

| 통로 | 전역 객체 | 주입 시점 | 보내기 | Host→Web | 짝 | 문서가 바뀔 때 | 프레임 |
|---|---|---|---|---|---|---|---|
| `webview_flutter` JavaScript 채널 | `window.<이름>` | Android: 다음 로드부터. iOS: 문서 시작 user script | `<이름>.postMessage(string)` → `undefined` | `runJavaScript`(메인 프레임의 지금 문서) | × | 새 문서에 다시 주입. Host가 보낸 JS는 그때 떠 있는 문서에서 실행 | 모든 프레임 |
| `flutter_inappwebview` `callHandler` | `window.flutter_inappwebview` | 문서 시작 plugin script. `flutterInAppWebViewPlatformReady` 이벤트 뒤에 호출 | `callHandler(name, ...args)` → Promise | 응답: `evaluateJavascript`로 `window.flutter_inappwebview[id].resolve(...)`. Event: `evaluateJavascript` | ○ (내부는 id + JS 실행) | 대기 Promise는 끝나지 않음 | 기본은 모든 프레임, β 설정으로 제한 |
| `flutter_inappwebview` `WebMessageListener` | `window.<jsObjectName>` | 문서 시작(Android: 플랫폼 API, iOS: JS 폴리필 user script) | `obj.postMessage(msg)` | `replyProxy.postMessage`(Web이 먼저 보내야 함) → `obj.onmessage` | × | 플랫폼 동작 따름(Android) / JS 폴리필(iOS) | 허용 규칙. 응답이 다른 프레임으로 가는 결함 [R48] |
| Android `addWebMessageListener` | `window.<jsObjectName>` | 호출 뒤 시작하는 모든 탐색, 페이지가 로드를 시작할 때 바로 | `obj.postMessage(string \| ArrayBuffer[, ports])` → `undefined` | `replyProxy.postMessage` → `obj.onmessage`·`addEventListener('message')` | × | reply proxy는 보낸 문서에 묶임. 문서가 사라지면 버림 | 허용 출처 규칙에 맞는 프레임(같은 출처 iframe 포함) |
| Android `WebMessagePort` | 없음(전역 `message` 이벤트의 `event.ports`) | Host가 `postWebMessage`로 포트를 보낼 때 | `port.postMessage(...)` | `port.postMessage` → `port.onmessage` | × | 포트는 문서와 함께 사라짐(추론) | `postWebMessage`는 메인 프레임만 |
| iOS `WKScriptMessageHandler` | `window.webkit.messageHandlers.<이름>` | 등록 즉시, 이미 떠 있는 문서 포함 | `postMessage(body)` → `undefined` | `evaluateJavaScript(_:in:frame:in:world)` | × | 핸들러는 남음. Host가 보낸 JS는 대상 프레임의 지금 문서에서 실행 | 지정한 content world의 모든 프레임 |
| iOS `WKScriptMessageHandlerWithReply` | 위와 같음 | 위와 같음 | `postMessage(body)` → Promise | 그 Promise의 이행·거부뿐. 먼저 보내기는 JS 실행 | ○ (플랫폼이 짝지음, 한 번만) | handler가 해제되면 거부. 탐색 시 실측 안 함 | 위와 같음 |
| 플랫폼 코드로 붙인 통로 | 위 Android·iOS 기본기 중 하나 | 위와 같음. 필요하면 문서 시작 스크립트로 감쌈 | 감싼 모양 | 위와 같음 | 기본기에 따름 | 위와 같음 | 위와 같음 |

### 1. `webview_flutter` JavaScript 채널

- **모양**: Web은 `window.<이름>.postMessage(string)`을 부른다. 돌려받는 값은 없다. Dart는 `JavaScriptMessage.message` 문자열 하나만 받는다 [R28].
- **값 타입**: Android 구현은 `@JavascriptInterface public void postMessage(String)`이다 [7]. 그래서 객체를 넘기면 문자열로 바뀐다. 실을 수 있는 공통 타입은 문자열이다.
- **주입 시점**:
  - Android는 `addJavascriptInterface`라서 다음 페이지 로드부터 보인다 [R28][R36].
  - iOS는 `window.<이름> = webkit.messageHandlers.<이름>`을 문서 시작, 모든 프레임(`isForMainFrameOnly: false`) user script로 넣는다 [8].
- **Host→Web**: `runJavaScript`뿐이다. 실행 시점에 메인 프레임에 떠 있는 문서에서 돈다. Demo Stage C의 `window.__onFlutterResponse(...)`가 이 방식이다 [R28][R36].
- **문서가 바뀔 때**: 채널은 새 문서에 다시 붙는다. 하지만 Host는 어느 문서에 보내는지 고를 수 없다. 이전 문서 몫의 응답이 새 문서에 갈 수 있다(ADR 0003이 이 문제로 이 방식을 버렸다).

### 2. `flutter_inappwebview` `callHandler`

- **모양**: `window.flutter_inappwebview.callHandler(name, ...args)`가 Promise를 돌려준다. 인자는 `JSON.stringify`로 넘어가고 Dart 반환값이 JSON으로 Promise를 이행한다. 호출은 `flutterInAppWebViewPlatformReady` 이벤트 뒤에 한다 [R28].
- **응답 구현(새로 확인)**: 짝은 플랫폼이 아니라 패키지 JS가 맞춘다.
  - 주입 스크립트가 `setTimeout(function(){})`의 반환값을 호출 id로 쓰고, resolve·reject를 `window.top.flutter_inappwebview[id]`에 저장한다 [10][11].
  - Host는 응답을 `evaluateJavaScript`/`evaluateJavascript`로 `window.flutter_inappwebview[id].resolve(json)`을 실행해 보낸다. 대상 프레임을 지정하지 않으므로 메인 프레임에서 돈다 [10][11].
  - 따라서 이것은 응답 통로가 아니라 "JS 실행 위에 얹은 id 짝 맞추기"다. 문서가 바뀌면 이전 문서의 Promise는 끝나지 않는다. 새 문서의 `setTimeout` id는 다시 작은 수부터 시작하므로, 늦게 도착한 응답이 새 문서의 같은 id 호출을 이행할 수도 있다(추론, 실측 안 함).
- **Host→Web Event**: `evaluateJavascript`나 `WebMessageListener`를 따로 써야 한다.

### 3. `flutter_inappwebview` `WebMessageListener`

- **모양**: Android 플랫폼 `addWebMessageListener`와 같은 `postMessage`·`onmessage`·`addEventListener` 모양이다 [R28].
- **주입**: Android는 플랫폼 API로 넣는다. iOS는 출처를 `window.location`으로 검사하는 JS 폴리필(`FlutterInAppWebViewWebMessageListener`)을 문서 시작 user script로 넣는다 [12].
- **결함**: 응답이 다른 프레임으로 가고, iOS 허용 규칙에 포트를 적으면 메인 프레임에도 주입되지 않는다 [R48].

### 4. Android `addWebMessageListener`와 `WebMessagePort`

- **모양(Javadoc 원문 요지)** [1]:
  - `myObject.postMessage(message[, MessagePorts])`. `message`는 String이나 ArrayBuffer다.
  - `myObject.onmessage = function(event) { event.data }`, `addEventListener('message', fn)`, `removeEventListener`.
- **주입 시점**: "이 호출 뒤의 모든 탐색에서, 허용 규칙에 맞는 프레임에 주입하고, 페이지가 로드를 시작할 때 바로 쓸 수 있다" [1]. 문서 시작 스크립트(`addDocumentStartJavaScript`)보다 먼저 주입되므로, 문서 시작 스크립트가 이 객체를 감쌀 수 있다 [1].
- **Host→Web**: "통신은 JavaScript 쪽에서 시작한다. 앱이 보내려면 JavaScript가 먼저 보내서 앱이 `JavaScriptReplyProxy`를 갖게 해야 한다" [1]. 그 뒤로는 Host가 언제든 `replyProxy.postMessage`로 보낼 수 있다. 짝은 없다.
- **reply proxy와 문서**: proxy는 "프레임 안의 JS 객체와 1:1"이다 [2]. Chromium 구현에서 proxy는 보낸 문서의 `WeakDocumentPtr`를 들고 있고, 그 문서가 없으면 "메시지를 전달하지 않고 버린다" [13]. 문서가 BFCache에 들어가 있으면 그 페이지를 캐시에서 내쫓고 보내지 않는다 [13]. 즉 이전 문서 몫의 Message가 새 문서로 가지 않는다.
- **`removeWebMessageListener`**: 호출 뒤에도 JS 객체는 남지만 보낸 Message는 리스너에 닿지 않는다 [1]. Web 쪽에서는 "객체는 있는데 응답이 없음"으로 보인다.
- **`WebMessagePort`**: Host가 `createWebMessageChannel`로 포트 쌍을 만들고 `postWebMessage`로 한쪽을 메인 프레임에 보낸다. Web은 `window`의 `message` 이벤트에서 `event.ports[0]`을 받아 표준 `MessagePort`로 쓴다. `postWebMessage`는 메인 프레임에만 보내고 대상 출처를 지정할 수 있다 [1]. Web이 `myObject.postMessage(msg, [port])`로 포트를 Host에 넘길 수도 있다 [1].
  - 포트도 짝이 없는 Message 통로다. 문서가 사라지면 포트도 함께 사라진다고 본다(HTML 명세의 포트 소유 문서 규칙에서 추론, 실측 안 함). 포트가 닫혔다는 신호를 Web이 받는 경로는 확인하지 못했다.
  - Web 입장에서 `window`의 `message` 이벤트는 다른 창·iframe도 보낼 수 있으므로 포트를 받는 첫 단계에서 `event.origin`·`event.source` 검사가 필요하다(추론).

### 5. iOS `WKScriptMessageHandler`와 `WKScriptMessageHandlerWithReply`

- **모양**: 둘 다 `window.webkit.messageHandlers.<이름>.postMessage(body)`다 [4][5].
  - `WKScriptMessageHandler`: 응답이 없다. Host→Web은 `evaluateJavaScript`다 [4].
  - `WithReply`: `postMessage`가 Promise를 돌려준다. `replyHandler(reply, nil)`이면 직렬화된 값으로 이행하고, `errorMessage`가 nil이 아니면 그 문자열을 `message`로 가진 Error로 거부한다. reply가 nil이면 `undefined`로 이행한다. 허용 타입은 NSNumber·NSNull·NSString·NSDate·NSArray·NSDictionary다. **replyHandler는 많아야 한 번 부를 수 있고, 부르지 않고 해제되면 Promise가 거부된다** [5].
- **주입 시점(새로 확인)**: 등록하면 "지정한 content world의 모든 프레임에" 함수가 정의된다 [6]. WebKit은 `messageHandlers.<이름>`을 접근할 때마다 등록된 핸들러를 찾는다. 그래서 이미 떠 있는 문서에서도 등록 즉시 보이고, 문서 시작 스크립트에서도 보인다 [14]. 반면 열거는 지원하지 않는다(`supportedPropertyNames`가 빈 목록) [14]. Web의 감지는 `Object.keys`가 아니라 `window.webkit?.messageHandlers?.<이름>` 직접 접근으로 해야 한다.
- **Host→Web**: `evaluateJavaScript(_:in:in:)`은 대상 프레임(`WKFrameInfo`, nil이면 메인 프레임)과 content world를 고를 수 있다. 실행 시점에 그 프레임이 유효하지 않으면 오류를 돌려준다 [9]. 프레임은 고를 수 있지만 "어느 문서인지"는 고를 수 없다(추론). Android `postWebMessage`·포트 같은 Host 쪽 Message API는 iOS에 없다.
- **Host가 먼저 보내기**: `WithReply`만으로는 Host가 먼저 보낼 수 없다. ADR 0003은 Web이 `listen`을 걸어 두고 Host가 Event가 생기면 그 Promise를 이행하는 방식(대기 응답)으로 이를 메운다.

### 6. 플랫폼 코드로 붙인 통로

- `webview_flutter` + 플랫폼 코드(ADR 0002)는 위 4·5의 기본기를 그대로 쓴다. JS 모양은 4·5와 같다 [R48].
- 플랫폼 코드는 두 플랫폼의 모양을 하나로 맞추는 문서 시작 스크립트를 넣을 수 있다. Android `addDocumentStartJavaScript`(주입 객체보다 뒤, 페이지 스크립트보다 앞에 실행) [1], iOS `WKUserContentController.addUserScript` [R28]. 다만 iOS에서 `webview_flutter`의 `removeJavaScriptChannel`·`enableZoom(true)`가 이 스크립트를 지운다 [R48]. 그래서 "Host가 넣은 감싸기 스크립트가 있다"를 Web이 전제로 삼으면 깨질 수 있다. 감싸기는 Web 쪽 어댑터 코드에 두는 편이 안전하다(추론).
- Android `addJavascriptInterface`를 직접 붙이면 동기 반환값까지 쓸 수 있지만, 모든 프레임에 열리고 출처를 모르므로 R36·ADR 0002가 이미 배제했다.

## 프로토콜 층이 응답 통로를 가정해도 되는가

**가정하면 안 된다.** 근거는 세 가지다.

1. **응답 통로가 없는 후보가 있다.** JavaScript 채널, `WKScriptMessageHandler`, `addWebMessageListener`, 포트는 보내기가 `undefined`를 돌려준다 [1][4][7]. 이 통로에서 Call을 하려면 봉투의 id로 짝을 맞춰야 한다. 선행 사례도 플랫폼 짝(iOS reply)에 기대지 않는 곳은 모두 자체 id를 쓴다 [RP].
2. **"응답 통로"처럼 보이는 것도 실제로는 id + JS 실행이다.** `callHandler`의 Promise는 패키지 JS가 id로 맞추고 `evaluateJavascript`로 이행한다 [10][11]. 그래서 문서가 바뀌면 끝나지 않는다. 플랫폼이 짝을 보장하는 통로는 iOS `WithReply` 하나뿐이다 [5].
3. **응답 통로만 있는 통로는 Event를 못 보낸다.** `WithReply`와 `callHandler`는 Host가 먼저 보낼 수 없어서, Event를 보내려면 대기 응답(`listen`)이나 JS 실행이 따로 필요하다 [5](ADR 0003).

따라서 공통분모는 "짝 없는 Message 통로"이고, 프로토콜이 그 위에서 `kind`·`id`로 Call과 Event를 구분한다. 프로토콜 층이 가정해도 되는 것은 다음뿐이다.

- **Web이 먼저 말한다.** Android reply proxy는 Web이 먼저 보내야 생기고 [1], iOS `WithReply`의 대기 응답도 Web이 걸어야 한다. 핸드셰이크가 Web의 첫 Message이고, 핸드셰이크 전에는 Host가 Event를 보내지 않는다는 규칙과 맞는다(ADR 0003).
- **응답이 안 올 수 있다.** 문서 전환, 리스너 해제(`removeWebMessageListener`), 패키지 결함(응답이 다른 프레임으로 감)이 모두 "조용히 안 옴"으로 나타난다 [1][13][R48]. 메서드별 타임아웃이 필수다.
- **통로는 문서 하나 동안만 산다.** 문서가 바뀌면 새 Transport를 열고 핸드셰이크를 다시 한다. 이전 문서의 대기 Call을 이어받는 일은 없다.

## Transport 최소 인터페이스 후보

```ts
/** 문서 하나 동안 열리는 문자열 양방향 통로. 짝 맞추기·타임아웃·검증은 위 층이 한다. */
export interface Transport {
  /** Host로 Message 하나를 보낸다. 전달 여부는 알려 주지 않는다. */
  send(text: string): void;
  /** Host가 보낸 Message를 받는다. 돌려준 함수로 구독을 끊는다. */
  onMessage(listener: (text: string) => void): () => void;
}

/** 통로를 찾아 연다. 통로가 없거나 이 프레임에서 쓰면 안 되면 null(Bridge 없음으로 이어짐). */
export type ConnectTransport = (options: { signal?: AbortSignal }) => Promise<Transport | null>;
```

- **문자열만 싣는다.** 모든 후보가 문자열을 실을 수 있고, `webview_flutter` Android 채널은 문자열만 싣는다 [7]. 봉투는 위 층이 JSON으로 만든다. ArrayBuffer·포트는 공통분모가 아니므로 넣지 않는다.
- **`send`는 `void`다.** Promise를 돌려주면 "응답 통로"를 가정하게 된다. iOS `WithReply`·`callHandler` 어댑터는 돌아온 Promise의 값을 `onMessage`로 흘려보내고, 거부는 어댑터가 오류 Message로 바꾸거나 버린다(위 층은 타임아웃으로 처리).
- **`connect`가 비동기인 이유.** 통로가 보이는 시점이 통로마다 다르다. `callHandler`는 `flutterInAppWebViewPlatformReady` 이벤트를 기다려야 하고 [R28], Android JavaScript 채널은 다음 로드부터 보이며 [R28], iOS 핸들러와 Android 리스너는 문서 시작부터 있다 [1][14]. 기다리는 한도와 감지 방법(직접 속성 접근)은 어댑터가 정한다.
- **`connect`가 `null`을 돌려주는 경우.** 통로 객체가 없을 때, 그리고 `window !== window.top`일 때다. 후자는 Host가 iframe에도 통로를 여는 후보가 있어서(JavaScript 채널, iOS 핸들러, `callHandler` 기본 설정) Web 쪽에서 한 번 더 막는 방어선이다. 진짜 판정은 Host가 출처·프레임으로 한다(R36, ADR 0002). Web은 자기 출처나 프레임을 Host에 증명할 수 없으므로 Transport에 출처 정보를 싣지 않는다.
- **`close`는 넣지 않는다.** 문서가 사라지면 통로도 사라지고, Web이 먼저 닫을 이유가 핸드셰이크 실패(Bridge 없음) 말고는 없다. Bridge 없음은 위 층이 "더 보내지 않음"으로 처리하면 된다. 어댑터 정리용 `dispose`가 필요하면 테스트용으로만 둔다.
- **가짜 Host**: 이 모양은 `window.postMessage`·`MessageChannel`·메모리 큐로 바로 흉내 낼 수 있다. 그래서 가짜 Host 코어는 같은 Transport에 붙고, Vitest에서는 메모리 쌍, Playwright에서는 페이지 주입으로 껍데기를 바꾼다.

### iOS `WithReply` 어댑터가 이 모양을 만드는 방법(스케치)

- `send(text)`: `messageHandlers.<이름>.postMessage(text)`가 돌려준 Promise가 이행되면 그 값(문자열)을 `onMessage` 리스너에 넘긴다. Call 응답은 이 경로로 온다.
- Event: 어댑터가 첫 `send` 뒤에 `listen` 요청을 하나 걸어 두고, 이행될 때마다 받은 Event 묶음을 하나씩 `onMessage`로 넘긴 뒤 다시 건다(ADR 0003). 이렇게 하면 `listen`은 어댑터와 Host 플랫폼 코드 사이의 사정이 되고, 계약·가짜 Host·프로토콜 층은 몰라도 된다.
- 이 배치는 ADR 0003이 `listen`을 봉투 수준 요청으로 적은 것과 다르다. `listen`을 계약에 둘지, 어댑터 아래로 내릴지는 후속 결정이다.

## 확인하지 못한 것

- iOS `WithReply`: 대기 중인 Promise가 문서 탐색 때 거부되는지(handler 해제와 같은 경로인지). Apple 문서는 해제 시 거부만 적는다 [5].
- `callHandler`: 문서 전환 뒤 늦게 온 응답이 새 문서의 같은 id 호출을 이행하는지. 소스상 가능해 보이지만 실측하지 않았다.
- `WebMessagePort`: 문서가 사라질 때 Host 쪽 포트가 어떤 신호를 받는지, Web이 포트 닫힘을 알 방법이 있는지.
- Android JavaScript 채널을 첫 로드 전에 등록했을 때 첫 문서에서 바로 보이는지(문서는 "다음 로드부터"만 적음).

## 출처

1. androidx.webkit `WebViewCompat.java`(androidx-main `0e2330e`): `WebMessageListener`, `createWebMessageChannel`, `postWebMessage`, `addWebMessageListener`, `removeWebMessageListener`, `addDocumentStartJavaScript` Javadoc. https://github.com/androidx/androidx/blob/0e2330e89a086173c5841cadb6604cc6b6b6c176/webkit/webkit/src/main/java/androidx/webkit/WebViewCompat.java · 공개 문서 https://developer.android.com/reference/androidx/webkit/WebViewCompat
2. androidx.webkit `JavaScriptReplyProxy.java`(같은 커밋). https://github.com/androidx/androidx/blob/0e2330e89a086173c5841cadb6604cc6b6b6c176/webkit/webkit/src/main/java/androidx/webkit/JavaScriptReplyProxy.java
3. Android Developers, `WebView.addJavascriptInterface`. https://developer.android.com/reference/android/webkit/WebView#addJavascriptInterface(java.lang.Object,%20java.lang.String)
4. Apple Developer, `WKScriptMessageHandler`. https://developer.apple.com/documentation/webkit/wkscriptmessagehandler
5. Apple Developer, `WKScriptMessageHandlerWithReply`, 그리고 WebKit 헤더 `WKScriptMessageHandlerWithReply.h`(Promise 이행·거부, 한 번만 호출, 해제 시 거부). https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply · https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKScriptMessageHandlerWithReply.h
6. Apple Developer, `WKUserContentController.addScriptMessageHandler(_:contentWorld:name:)` · `add(_:contentWorld:name:)`. https://developer.apple.com/documentation/webkit/wkusercontentcontroller/addscriptmessagehandler(_:contentworld:name:) · https://developer.apple.com/documentation/webkit/wkusercontentcontroller/add(_:contentworld:name:)
7. webview_flutter_android 4.14.1 `JavaScriptChannel.java`(`postMessage(String)`). https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/JavaScriptChannel.java
8. webview_flutter_wkwebview 3.27.0 `webkit_webview_controller.dart`(채널 wrapper user script, 문서 시작·모든 프레임). https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_wkwebview/lib/src/webkit_webview_controller.dart
9. Apple Developer, `WKWebView.evaluateJavaScript(_:in:in:completionHandler:)`. https://developer.apple.com/documentation/webkit/wkwebview/evaluatejavascript(_:in:in:completionhandler:)
10. flutter_inappwebview 6.2.0-beta.3 iOS `JavaScriptBridgeJS.swift`(`callHandler`, `setTimeout` id, `window.top`에 resolve 저장) · `InAppWebView.swift`(`evaluateJavaScript`로 resolve·reject). https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_ios/ios/flutter_inappwebview_ios/Sources/flutter_inappwebview_ios/PluginScriptsJS/JavaScriptBridgeJS.swift · https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_ios/ios/flutter_inappwebview_ios/Sources/flutter_inappwebview_ios/InAppWebView/InAppWebView.swift
11. flutter_inappwebview 6.2.0-beta.3 Android `JavaScriptBridgeJS.java` · `JavaScriptBridgeInterface.java`(같은 구조, `evaluateJavascript`로 resolve). https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/plugin_scripts_js/JavaScriptBridgeJS.java · https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/JavaScriptBridgeInterface.java
12. flutter_inappwebview 6.2.0-beta.3 iOS `WebMessageListener.swift`(JS 폴리필, 문서 시작 plugin script). https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.2.0-beta.3/flutter_inappwebview_ios/ios/flutter_inappwebview_ios/Sources/flutter_inappwebview_ios/InAppWebView/WebMessage/WebMessageListener.swift
13. Chromium `components/js_injection/browser/js_to_browser_messaging.cc`·`.h`·`web_message_reply_proxy.h`(reply proxy가 `WeakDocumentPtr`를 들고, 문서가 없으면 메시지를 버림, BFCache 축출). https://chromium.googlesource.com/chromium/src/+/main/components/js_injection/browser/
14. WebKit `Source/WebCore/page/UserMessageHandlersNamespace.cpp`(접근 시 핸들러 조회, 열거 미지원). https://github.com/WebKit/WebKit/blob/main/Source/WebCore/page/UserMessageHandlersNamespace.cpp

- R28: [Flutter WebView 패키지 기능 비교 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/research/webview-package-matrix/docs/research/webview-package-matrix.md)
- R36: [WebView Bridge 보안 지침 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/research/webview-security/docs/research/webview-security.md)
- R48: [WebView 패키지 후보 빌드·동작 실측 결과](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/48)
- RP: [WebView Bridge 프로토콜 선행 사례 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/blob/research/bridge-protocol-prior-art/docs/research/bridge-protocol-prior-art.md)
