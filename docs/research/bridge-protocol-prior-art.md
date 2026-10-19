# WebView Bridge 프로토콜 선행 사례 조사

- 질문: [#29 WebView Bridge 프로토콜 선행 사례 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/29)
- 조사일: 2026-10-19
- 확인한 버전: JSON-RPC 2.0(2013-01-04 개정) · LSP 3.18 · MCP 2026-07-28 · MCP Apps 명세 2026-01-26 / Capacitor 8.5.3 / cordova-android 15.1.0 · cordova-ios 8.1.1 · cordova-js 6.1.0 / react-native-webview 16.0.0 / androidx.webkit 1.17.1(Javadoc은 androidx-main 소스) / WebKit main 헤더(대상 API는 iOS 14+) / Telegram Mini Apps(telegram-web-app.js 2026-10-19 내려받음, Bot API 10.3 [48]) / LIFF 2.31.2 / TeamsJS 2.58.0 / Shopify App Bridge(CDN 최신판, 이전 세대는 `@shopify/app-bridge` 3.7.12) / webview_flutter 4.14.1

## 요약

- **봉투는 세 갈래다.** ① JSON-RPC 2.0 봉투를 그대로 쓴다(MCP Apps). ② 프레임워크 자체 봉투를 쓴다(Capacitor `callbackId`·`pluginId`·`methodName`·`options`, TeamsJS `id`·`uuid`·`func`·`args`, Telegram `eventType`·`eventData`). ③ 플랫폼이 짝을 맞춰 준다(iOS reply handler의 `postMessage`는 Promise를 돌려준다). 직접 짝을 맞추는 곳은 요청 쪽이 만든 id를 쓰고, Telegram은 일부를 이벤트 이름 쌍으로 맞춘다.
- **에러는 "코드 + 디버깅용 메시지 + 부가 정보"가 공통 골격이다.** 코드가 정수(JSON-RPC, TeamsJS)인지 문자열(Capacitor, LIFF)인지가 갈리고, TeamsJS·LIFF 문서는 메시지가 아니라 코드로 판별하라고 한다. iOS reply handler는 문자열 메시지 하나만 넘긴다.
- **WebView Bridge 구현에는 Call 단위 타임아웃·취소가 거의 없다**(Capacitor, Cordova, 플랫폼 API. TeamsJS는 초기화에만 60초). 규약으로 정한 곳은 JSON-RPC 위의 LSP(`$/cancelRequest`, 취소돼도 응답)와 MCP(`notifications/cancelled`, 응답 안 함, 타임아웃 권장)다.
- **Event는 이름 기반 구독과 해제 핸들이 일반적이다**(Capacitor, Telegram). 구독 전에 일어난 Event는 보관(Capacitor `retainUntilConsumed`), sticky(Cordova), 준비 전 전송 금지(MCP Apps)로 다룬다. Android `WebMessageListener`는 Web이 먼저 보내야 Host가 답할 수 있다.
- **Host가 Web에 묻고 답을 받는 형식은 일부에만 있다**: MCP Apps `ui/resource-teardown`, TeamsJS `beforeUnload`→`readyToUnload`. Capacitor·Cordova·React Native WebView 규약에는 없다. 플랫폼 API 중에는 iOS `callAsyncJavaScript`만 Promise를 기다린다고 문서화돼 있다.
- **기능 탐색·버전은 네 방식이다**: 핸드셰이크로 capability 교환(LSP, MCP Apps, TeamsJS), Host의 지원 목록 주입(Capacitor), 버전 숫자 비교(Telegram), API별 지원 질의(LIFF, TeamsJS). MCP 최신판(2026-07-28)은 핸드셰이크 없이 요청마다 버전을 싣는다.
- **출처 검증은 플랫폼과 구현마다 다르다.** Android `addWebMessageListener`는 허용 origin에 맞는 frame에만 주입하고 메시지마다 `sourceOrigin`·`isMainFrame`을 준다. iOS handler는 모든 frame에 노출되고 `frameInfo`로 확인한다. 현재 Demo의 webview_flutter JavaScript channel은 문자열만 넘기고, Android에서는 모든 frame에 주입되는 `addJavascriptInterface`를 쓴다.
- **큰 데이터는 대부분 바이트를 Bridge로 직접 보내지 않는다**: JSON 안 base64(Cordova, Capacitor HTTP), Bridge 밖 URL(Capacitor `convertFileSrc`, Telegram), 미리보기와 base64 조각(TeamsJS). 바이트를 그대로 보내는 것은 Android ArrayBuffer(androidx.webkit 1.8.0+)뿐이고 iOS script message에는 바이너리 타입이 없다.

## 상세

각 사례에서 웹 콘텐츠를 띄우는 쪽을 Host, 그 안의 웹 콘텐츠를 Web이라 부른다. 기준선은 현재 Demo Stage C 규약(`docs/spec.md` §4)이다: Call은 `{id, method, params}` → `{id, result}` 또는 `{id, error: "문자열"}`, Event는 `flutter:event` CustomEvent 하나로 전달한다.

**프로토콜·플랫폼 기본기**

| 항목 | JSON-RPC 2.0 (+LSP·MCP) | Android `WebMessageListener` | iOS reply handler | React Native WebView |
|---|---|---|---|---|
| 봉투·매칭 | Request `id`로 Response 매칭 [1] | String·ArrayBuffer 한 덩어리, 매칭 없음 [34] | Promise로 WebKit이 매칭 [39] | 문자열 하나, 매칭 없음 [30] |
| 에러 | 정수 `code`·`message`·`data` [1] | 없음 | 문자열 `errorMessage` [39] | 없음 |
| 타임아웃·취소 | 명세에 없음, LSP·MCP가 추가 [2][3] | 없음 | 시간 제한 없음, 미응답 handler 해제 시 reject [39] | 없음 |
| Host→Web Event | id 없는 Notification [1] | `replyProxy.postMessage`, Web이 먼저 보내야 함 [34] | JS 실행 API [43] | 이름 없는 `message` DOM 이벤트 [32][33] |
| Host가 묻고 답받기 | 역할 대칭 [1] | `evaluateJavascript` 결과 콜백 [37] | `callAsyncJavaScript`가 Promise 대기 [43] | 문서화된 응답 경로 없음 [29] |
| 기능·버전 | LSP 핸드셰이크, MCP 요청별 버전 [2][4] | `WebViewFeature` 런타임 확인 [34] | iOS 14+ [44] | 확인 안 함 |
| 출처 검증 | 전송 계층 몫 | 허용 origin 규칙 + `sourceOrigin`·`isMainFrame` [34] | 모든 frame 노출, `frameInfo` [40][41] | Android `*`, 이벤트 `url` [31][33] |
| 큰 데이터 | JSON 값만 | ArrayBuffer(1.8.0+) [36] | 바이너리 타입 없음 [39][41] | 문자열만 [30] |

**하이브리드 앱 프레임워크·임베디드 앱 SDK**

| 항목 | Capacitor | Cordova | Telegram Mini Apps | LIFF | TeamsJS | Shopify App Bridge |
|---|---|---|---|---|---|---|
| 봉투·매칭 | `callbackId` 매칭 [6] | `callbackId` 매칭 [18][26] | `eventType`·`eventData`, 일부 `req_id` [46] | 공개 문서에서 못 찾음 | `id`·`uuid`, 부분 응답 [52] | (이전 세대) action `type`·`payload` [62] |
| 에러 | 문자열 `code`·`message`·`data` [8][12] | 상태 enum 10종 [20] | `error` 문자열 [46] | `code`·`message`·`cause` [49] | 정수 `errorCode`·`message` [54] | `APP::ERROR::*` action [62] |
| 타임아웃·취소 | 없음, `keepAlive` [6][15] | 없음, `keepCallback` [24] | 확인 안 함 | 레퍼런스에 언급 없음 [49] | 초기화만 60초 [59] | 확인 안 함 |
| Event·구독 | `addListener`→`remove()` [6] | `keepCallback`, sticky 이벤트 [24][25] | `onEvent`/`offEvent` [45] | 확인 안 함 | 구독을 Host에 알림 [57] | 확인 안 함 |
| Host가 묻고 답받기 | 규약에 없음 | 규약에 없음 | 못 찾음 | 못 찾음 | `beforeUnload`→`readyToUnload` [57] | 확인 안 함 |
| 기능·버전 | `PluginHeaders` 주입 [14] | `INVALID_ACTION` [20] | `isVersionAtLeast` [45] | `isApiAvailable`, SemVer [49][51] | `isSupported()`, runtime [56][60] | CDN 항상 최신 [61] |
| 출처 검증 | Android만 frame·origin 확인 [9][13] | Android만 secret 발급 [19][27] | initData 서명 서버 검증 [45] | 공개 문서에서 못 찾음 | Host origin 허용 목록 [55] | (이전 세대) origin 불일치 거부 [62] |
| 큰 데이터 | base64, `convertFileSrc` [6][16] | base64 [18][26] | HTTPS URL [45] | 확인 안 함 | 미리보기 + base64 조각 [58] | 확인 안 함 |

### 1. 메시지 봉투 형식과 요청·응답 매칭

- **JSON-RPC 2.0**: Request는 `jsonrpc: "2.0"`, `method`, 생략 가능한 `params`, `id`(String·Number·Null, Null과 소수는 권장하지 않음)다. `id`가 없으면 Notification이고 응답하지 않는다. Response는 `result`와 `error` 중 정확히 하나를 담고 `id`는 요청과 같아야 한다. 배열로 묶어 보내는 batch도 있다. 명세는 전송 수단과 무관하다고 밝힌다 [1]. MCP Apps는 이 봉투를 iframe과 Host 사이의 `postMessage`에 그대로 얹는다 [5].
- **Capacitor**: Web→Host는 `{callbackId, pluginId, methodName, options}`(iOS는 `type: "message"` 추가), Host→Web은 `{callbackId, pluginId, methodName, success, data | error, save}`다 [6][13]. callbackId는 무작위 값에서 시작하는 증가 카운터인데, 주석에 따르면 reload 뒤 이전 세션의 같은 id로 응답이 돌아오는 문제를 피하려는 것이다 [6]. Android는 `WebMessageListener`의 replyProxy로 답하고, 지원하지 않으면 `evaluateJavascript`로 `window.Capacitor.fromNative(...)`를 실행한다 [9].
- **Cordova**: `exec(success, fail, service, action, args)`이고 callbackId는 service 이름에 증가 번호를 붙인다 [18][26]. iOS는 `[callbackId, service, action, args]` 배열을 보낸다 [26]. Host→Web은 `callbackFromNative(callbackId, isSuccess, status, args, keepCallback)`로 들어온다 [24]. Android는 길이 접두사를 붙인 문자열로 인코딩한다 [18].
- **TeamsJS**: 요청은 `{id(예전 숫자 id), uuid, func, args, timestamp, apiVersionTag}`, 응답은 `{id, uuid, args, isPartialResponse}`다. `isPartialResponse`가 참이면 같은 id로 응답이 더 온다 [52]. 같은 봉투를 모바일에서는 `nativeInterface.framelessPostMessage(JSON.stringify(...))`로, iframe에서는 `postMessage`로 보낸다 [53].
- **Telegram Mini Apps**: 모든 교환이 `{eventType, eventData}` 이벤트다. 모바일은 `TelegramWebviewProxy.postEvent`, iframe은 `postMessage`를 쓴다 [46][47]. 요청과 응답은 주로 이벤트 이름 쌍(`web_app_open_popup`→`popup_closed`)으로 짝짓고, 일부만 `req_id`를 쓴다(`web_app_invoke_custom_method`→`custom_method_invoked {req_id, result | error}`) [46].
- **플랫폼 기본기**: iOS reply handler에서는 `postMessage`가 Promise를 돌려주고, Host가 reply handler를 부르면 그 Promise가 이행된다 [39]. Android `WebMessageListener`는 String이나 ArrayBuffer 한 덩어리만 주고받으며 매칭 개념이 없다 [34]. React Native WebView의 `postMessage`는 문자열 인자 하나만 받는다 [30].

### 2. 에러 체계(코드, 메시지, 원인)

- **JSON-RPC 2.0**: `error {code: 정수, message, data?}`. -32700(Parse error), -32600(Invalid Request), -32601(Method not found), -32602(Invalid params), -32603(Internal error)이 정의돼 있고 -32768부터 -32000까지는 예약 범위다 [1]. LSP는 여기에 -32800 `RequestCancelled`, -32801 `ContentModified`, -32802 `ServerCancelled`, -32803 `RequestFailed`를 더한다 [2]. MCP는 지원하지 않는 프로토콜 버전에 -32022를 쓰고 `data.supported`에 지원 버전 목록을 담는다 [4].
- **Capacitor**: `CapacitorException(message, code?, data?)`. 공통 코드는 `UNIMPLEMENTED`(현재 플랫폼에 구현 없음)와 `UNAVAILABLE`(네트워크 같은 전제 조건이 없거나 특정 플랫폼 버전이 필요함)이다 [8]. Host는 `reject(msg, code, ex, data)`로 `{message, code, data}`를 보내고 [12], Web은 이를 Error 객체에 옮겨 담는다 [6].
- **Cordova**: 결과 상태가 `NO_RESULT`, `OK`, `CLASS_NOT_FOUND_EXCEPTION`, `ILLEGAL_ACCESS_EXCEPTION`, `INSTANTIATION_EXCEPTION`, `MALFORMED_URL_EXCEPTION`, `IO_EXCEPTION`, `INVALID_ACTION`, `JSON_EXCEPTION`, `ERROR` 열 가지다 [20]. 실패 내용의 형식은 플러그인마다 다르다. `execute()`가 false를 돌려주면 MethodNotFound 에러가 된다 [28].
- **TeamsJS**: `SdkError {errorCode, message?}`. 문서 주석은 message가 디버깅용이며 현지화되지 않고 Web이 그 내용에 기대면 안 된다고 적는다. 코드는 의미별로 나뉜다: 100 `NOT_SUPPORTED_ON_PLATFORM`, 500 `INTERNAL_ERROR`, 501 `NOT_SUPPORTED_IN_CURRENT_CONTEXT`, 1000 `PERMISSION_DENIED`, 2000 `NETWORK_ERROR`, 3000 `NO_HW_SUPPORT`, 4000 `INVALID_ARGUMENTS`, 5000 `UNAUTHORIZED_USER_OPERATION`, 6000 `INSUFFICIENT_RESOURCES`, 7000 `THROTTLE`, 8000 `USER_ABORT`, 8001 `OPERATION_TIMED_OUT`, 9000 `OLD_PLATFORM`, 404 `FILE_NOT_FOUND`, 10000 `SIZE_EXCEEDED` [54].
- **LIFF**: `LiffError {code: 문자열, message?, cause?}`. 문서는 에러 메시지가 예고 없이 바뀔 수 있으니 메시지만으로 판별하지 말라고 적는다 [49].
- **Shopify App Bridge 이전 세대**: 에러도 action으로 온다(`APP::ERROR::INVALID_ACTION`, `INVALID_PAYLOAD`, `UNSUPPORTED_OPERATION`, `PERMISSION`, `NETWORK`, `INVALID_ORIGIN` 등) [62].
- **iOS reply handler**: 두 번째 인자 `errorMessage` 문자열을 넘기면 Promise가 그 문자열을 `message`로 가진 JS Error로 거부된다. 코드 필드는 없다 [39].
- **사용자 취소를 어떻게 보는지가 갈린다.** TeamsJS는 `USER_ABORT` 에러 코드다 [54]. Telegram은 `phone_requested {status: "cancelled"}` 같은 정상 결과로 알린다 [46]. LIFF `shareTargetPicker`는 사용자가 닫으면 Promise가 값 없이 이행되고, 표시 전 문제일 때만 `LiffError`로 거부된다 [49].

### 3. 타임아웃과 취소

- **JSON-RPC 2.0** 명세는 타임아웃과 취소를 다루지 않는다 [1].
- **LSP**: 양방향 `$/cancelRequest {id}` Notification. 취소된 요청도 반드시 응답해야 하고(부분 결과 허용), 에러로 응답한다면 `RequestCancelled`를 권장한다 [2].
- **MCP 2026-07-28**: `notifications/cancelled {requestId, reason}`. 받은 쪽은 처리를 멈추고 응답을 보내지 않는 것이 권장(SHOULD)이다. 모든 요청에 타임아웃을 두고, 시간이 지나면 취소를 보내고 기다림을 멈추라고 권한다. 진행 알림을 받으면 타이머를 다시 시작해도 되지만 최대 시간은 항상 지키라고 한다. 취소 뒤 도착한 응답은 무시하고, 취소와 응답이 엇갈리는 경쟁 상태는 양쪽이 반드시 처리해야 한다 [3].
- **Capacitor**: Call 경로(`toNative`, `returnResult`)에 타임아웃·취소가 없다 [6]. 오래 걸리거나 결과를 여러 번 보내는 Call은 `keepAlive`로 유지하고 `releaseCall`로 놓는다 [15].
- **Cordova**: exec 경로에 타이머가 없다 [18][26]. `keepCallback`이 거짓인 결과가 오면 콜백을 지운다 [24]. Android는 페이지 이동 때 Bridge secret을 지우고 이전 페이지에서 온 호출을 무시한다 [19].
- **TeamsJS**: 일반 호출 경로에는 로컬 타임아웃이 없다 [53]. `app.initialize`만 60초 뒤 "SDK initialization timed out"으로 실패한다 [59]. 시간 초과는 Host가 `OPERATION_TIMED_OUT`(8001) 코드로 알릴 수 있다 [54].
- **iOS reply handler**: 최대 한 번만 부를 수 있고, 부르지 않은 채 해제되면 Promise가 거부된다. 시간 기반 타임아웃은 없다 [39].

### 4. 호스트→웹 이벤트와 구독

- **JSON-RPC 계열**: Event는 id 없는 Notification이다 [1]. MCP Apps는 Host→Web 알림(`ui/notifications/tool-input`, `ui/notifications/host-context-changed` 등)을 두고, Web의 `ui/notifications/initialized`를 받기 전에는 어떤 요청이나 알림도 보내지 말라고 정한다 [5].
- **Capacitor**: `addListener(eventName, cb)`는 keepAlive Call을 Host에 등록하고 `PluginListenerHandle.remove()`로 해제한다 [6][11]. Host는 `notifyListeners(eventName, data, retainUntilConsumed)`를 부른다 [11][17]. 리스너가 없을 때 `retainUntilConsumed`가 참이면 데이터를 쌓아 두었다가 첫 리스너가 붙을 때 전달한다 [11].
- **Cordova**: Call마다 `keepCallback`으로 결과를 여러 번 받는다 [24]. `deviceready` 같은 sticky 이벤트는 한 번 발생하면 그 상태를 유지해서, 나중에 구독해도 바로 실행된다 [25].
- **Telegram**: Web은 `onEvent(eventType, handler)`·`offEvent`로 구독하고 [45], Host는 `Telegram.WebView.receiveEvent(eventType, eventData)`를 호출한다 [46][47].
- **TeamsJS**: Web이 핸들러를 등록하면 `registerHandler` 메시지로 Host에도 이벤트 이름을 알리므로, Host는 Web이 어떤 Event를 듣는지 안다 [57]. Host는 `{func, args}`를 보낸다 [53].
- **React Native WebView**: 이름 없는 `message` DOM 이벤트 하나다. iOS는 `window`, Android는 `document`에서 dispatch한다 [33][32]. Event 종류는 메시지 내용으로 직접 구분해야 한다.
- **Android `WebMessageListener`**: Host는 `replyProxy.postMessage`로 JS 객체의 `onmessage`에 보낸다. Javadoc은 통신이 JavaScript 쪽에서 시작되며, Host가 보내려면 JavaScript가 먼저 메시지를 보내 `JavaScriptReplyProxy`를 넘겨줘야 한다고 적는다 [34]. replyProxy는 frame 안의 JS 객체와 1:1로 대응한다 [35].

### 5. 호스트가 웹에 먼저 묻고 답을 받는 반대 방향 호출

현재 GLOSSARY의 Call은 Web→Host 방향만 정의한다.

- **JSON-RPC 2.0**: Client와 Server는 역할일 뿐이고, 한 구현이 동시에 두 역할을 할 수 있다 [1]. LSP는 취소도 양방향으로 정의한다 [2]. MCP Apps에는 Host→Web 요청 `ui/resource-teardown`(id 있음)이 있다. Web이 정리를 마치고 `result`나 `error`로 답하면 Host가 iframe을 제거한다 [5].
- **TeamsJS**: 공개 API `app.lifecycle.registerBeforeSuspendOrTerminateHandler(() => Promise<void>)`는 사용자가 Web을 떠날 때 불리며, 저장하지 않은 데이터를 저장하는 데 쓰라고 안내한다 [65]. Host가 `beforeUnload`를 보내면 SDK가 이 핸들러의 Promise를 기다린 뒤 `readyToUnload` 메시지로 답한다 [57]. 핸들러 반환값을 그대로 돌려보내는 형식은 아니다. 응답은 별도 메시지이고, id가 아니라 메시지 이름으로 짝을 짓는다 [53][57].
- **Telegram**: Host가 묻는 대신 Web이 미리 상태를 선언한다. `web_app_setup_closing_behavior {need_confirmation: true}`를 보내 두면 Host는 닫기 전에 "Changes that you made may not be saved." 확인 창을 띄워야 한다 [46].
- **플랫폼 기본기**: iOS `callAsyncJavaScript`는 JS 함수가 thenable을 반환하면 해결될 때까지 기다려 값이나 거부 에러를 돌려준다. 그 객체가 해결 전에 GC되거나 대상 frame이 사라지면 에러로 끝난다 [43]. Android `evaluateJavascript` 문서는 실행 결과를 콜백으로 준다고만 적고 Promise 처리는 언급하지 않는다 [37]. androidx의 `JavaScriptReplyProxy.executeJavaScript`는 메시지를 보낸 frame과 world에서 JS를 실행한다(1.16.0-alpha03에서 추가) [35][36].
- **Capacitor·Cordova·React Native WebView**: 규약에 Host→Web 요청 형식이 없다. Host→Web으로 가는 것은 Call 결과와 Event뿐이다 [6][24]. React Native WebView는 임의 JS를 실행하는 `injectJavaScript`를 제공하고, 문서화된 응답 경로는 Web→Host `postMessage`뿐이다 [29].

### 6. 기능 탐색과 버전 관리

- **Capacitor**: Host가 문서 시작 시 `window.Capacitor.PluginHeaders`(플러그인 이름, 메서드, 반환 형태 `rtype`)를 주입한다 [14]. `isPluginAvailable(name)`은 등록된 Web 구현이나 이 header로 판단하고, 없는 플러그인·메서드를 부르면 `UNIMPLEMENTED`가 난다 [7]. 일시적으로 쓸 수 없으면 `UNAVAILABLE`이다(예: `call.unavailable("Not available on Android API 25 or earlier.")`) [8][17].
- **TeamsJS**: API를 capability(namespace)로 묶고 capability마다 `isSupported()`를 둔다. Host는 capability를 부분 구현할 수 없고, 지원하지 않는 API를 부르면 예외가 난다. 문서는 Host 이름이 아니라 `isSupported()`로 분기하라고 권한다 [60]. 초기화 응답에 runtime(`apiVersion`, `supports` 트리)이 오며, SDK는 예전 형식을 upgrade chain으로 최신 형식으로 바꾸고, runtime을 보내지 않는 Host는 버전별 capability 표로 추정한다 [56][59]. Host가 알려 준 지원 SDK 버전이 API별 최소 버전에 못 미치면 `OLD_PLATFORM`이다 [58]. `appHelpers.ts`에는 Host가 새 인자 순서로 업데이트되는 동안 세 가지 인자 배치를 모두 받아 주는 임시 코드가 있다 [59]. 버전 어긋남이 핸드셰이크 형식 자체에도 영향을 준 사례다.
- **Telegram**: 실행 파라미터 `tgWebAppVersion`이 `WebApp.version`이 되고 Web은 `isVersionAtLeast(version)`로 비교한다. 지원하지 않는 기능은 콘솔 경고로 끝나거나 `WebAppMethodUnsupported` 예외를 던진다 [45][47].
- **LIFF**: `liff.isApiAvailable(apiName)`, `getVersion()`(SDK), `getLineVersion()`(Host 버전)을 제공하고, 권한은 `permission.query()`가 `granted`·`prompt`·`unavailable`로 알려 준다 [49]. SDK는 v2.2.0부터 SemVer를 따르고 [51], CDN edge path(MAJOR만 고정, MINOR·PATCH 자동 반영)와 fixed path 중에서 고른다 [50].
- **Shopify App Bridge**: 현재판은 CDN에서 받는 스크립트가 스스로 최신 상태를 유지해서 Web은 항상 최신판을 쓴다 [61]. 이전 세대는 `featuresAvailable()`로 action마다 Dispatch·Subscribe 권한을 조회했다 [62].
- **JSON-RPC 계열**: LSP는 `initialize`에서 capability를 교환하며, 개발 도구 쪽은 이해하지 못하는 언어 서버 capability를 무시해야 한다 [2]. MCP 2026-07-28은 핸드셰이크를 없앴다. 요청마다 `_meta`에 버전을 싣고, 서버가 지원하지 않으면 -32022 에러에 지원 목록을 담아 답하며, 필요하면 `server/discover`로 미리 확인한다 [4]. MCP Apps는 `ui/initialize`(Web의 `appCapabilities`, `protocolVersion`) ↔ Host의 `hostCapabilities`·`hostContext`로 협상한다 [5].

### 7. 출처 검증

- **Android 플랫폼**: `addWebMessageListener`는 `allowedOriginRules`(`https://host[:port]`, `https://*.example.com`, 사용자 정의 scheme, `*`)에 맞는 frame에만 JS 객체를 주입한다. Javadoc은 HTTPS를 강하게 권장하고, `*`를 쓰면 모든 frame에 주입되므로 받은 메시지를 신뢰하지 말고 검증하라고 한다. 메시지마다 `sourceOrigin`과 `isMainFrame`이 오며, `file:`·`content:` 출처는 문자열 `"null"`이다 [34]. 반면 `addJavascriptInterface`는 iframe을 포함한 모든 frame에 객체를 주입한다 [38].
- **iOS 플랫폼**: script message handler는 해당 content world의 모든 frame에 노출된다 [40]. 메시지마다 `frameInfo`(`isMainFrame`, `request`, `securityOrigin`)와 `world`가 온다 [41][42].
- **구현별 차이**: Capacitor Android는 허용 origin(Web을 띄우는 자체 scheme/host, `server.url`, `allowNavigation`)으로 등록하고 main frame 메시지만 처리한다 [9][10]. Capacitor iOS 처리기는 `type`만 보고 frame을 확인하지 않으며, `window.Capacitor` 전역 주입만 main frame으로 한정한다 [13][14]. cordova-android는 `gap_init`을 부른 페이지가 navigation 허용 목록(기본은 시작 URL 접두사)에 있을 때만 Bridge secret을 발급하고, 이후 모든 exec에 secret을 요구하며, 틀리면 Bridge를 끈다 [19][22][23]. cordova-ios는 메시지 이름만 확인한다 [27]. React Native WebView Android는 `Set.of("*")`로 등록해 `sourceOrigin`을 이벤트 `url`로 넘기고, iOS는 frame의 URL을 넘긴다 [31][33]. `originWhitelist`는 탐색 허용 목록일 뿐이다 [30].
- **iframe 기반 SDK**: TeamsJS는 메시지 origin을 Host origin 목록(CDN 목록, 내장 대체 목록, Web이 넘긴 `validMessageOrigins`)과 대조하고, 표준 목록은 https만 허용한다 [55]. Shopify 이전 세대의 Host는 메시지 origin이 등록된 Web origin과 다르면 `INVALID_ORIGIN` 에러 action으로 답했다 [62]. Telegram SDK는 iframe에서 `event.source === window.parent`를 확인하지만, 보낼 때는 테스트 목적이라며 targetOrigin을 `*`로 둔다 [47]. 대신 Web에 넘기는 실행 데이터(initData)는 HMAC-SHA256(봇 토큰 기반)이나 Ed25519 서명으로 서버에서 검증한다 [45]. MCP Apps는 Host와 sandbox의 origin을 다르게 두고, Host가 들어오는 메시지를 모두 검증해 잘못된 형식을 거부하라고 정한다 [5].
- **webview_flutter**: `JavaScriptMessage`에는 `message` 문자열만 있고 [63], Android 구현은 `addJavascriptInterface`다 [64].

### 8. 큰 데이터(파일·바이너리) 전달

- **바이너리 직접 전달**: Android `WebMessageListener`·`WebMessagePort`는 androidx.webkit 1.8.0부터 ArrayBuffer를 양방향으로 지원한다(런타임에 `WEB_MESSAGE_ARRAY_BUFFER` 지원 확인 필요) [34][36]. Javadoc은 큰 byte 버퍼가 저사양 기기에서 메모리 부족 크래시를 낼 수 있다고 경고한다 [35]. iOS script message의 body와 reply는 NSNumber, NSString, NSDate, NSArray, NSDictionary, NSNull만 허용한다 [39][41]. React Native WebView는 문자열만 오간다 [30].
- **JSON 안의 base64**: Cordova는 ArrayBuffer 인자와 결과를 base64로 바꾼다(iOS는 `{CDVType: "ArrayBuffer", data}`) [18][20][26]. Android는 여러 응답을 한 번에 보낼 때 16MB 상한을 두지만 메시지 경계에서만 나누고 한 메시지를 쪼개지는 않는다 [21]. Capacitor의 HTTP 가로채기는 `File`과 `FormData` 안의 파일을 base64로 바꿔 Bridge로 보낸다 [6].
- **Bridge 밖으로 우회**: Capacitor `convertFileSrc`는 기기 파일 경로를 WebView 서버 URL(`/_capacitor_file_/...`)로 바꿔 Web이 보통 URL로 읽게 한다 [6][16]. Telegram은 파일을 HTTPS URL로 다룬다(`downloadFile`, `shareToStory(media_url)`). 봇에게 보내는 `sendData`는 4096바이트로 제한된다 [45].
- **조각 전송**: TeamsJS `selectMedia` 결과에는 형식에 따라 base64 내용이나 URI에 대응하는 id, 그리고 가벼운 미리보기(`preview`, 이미지는 썸네일 base64)가 들어 있다. 원본은 `getMedia()`가 base64 조각(`chunk`, `chunkSequence`, 0 이하이면 끝)으로 받아 Blob으로 조립한다 [58]. 크기 초과에는 `SIZE_EXCEEDED` 코드가 있다 [54].

## Reference App에 주는 시사점

「Bridge 계약 형태 결정」(#39)이 따져 볼 선택지와 맞바꿈이다. 여기서 고르지는 않는다.

- **봉투**
  - (A) JSON-RPC 2.0을 그대로 쓴다. id·Notification·에러 코드 범위가 정해져 있고, 방향이 대칭이라 Host→Web Call에도 같은 형식을 쓸 수 있다. LSP·MCP의 취소·버전 관례도 빌릴 수 있다. 대신 에러 코드가 정수이고, 타임아웃·취소·버전은 따로 규약을 써야 한다.
  - (B) 자체 봉투를 쓴다. 현재 Demo의 Call(`id`·`method`·`params` / `id`·`result`·`error`)은 JSON-RPC와 비슷하지만 `jsonrpc` 필드가 없고 error가 문자열이다. Message·Event·Call 구분을 필드로 드러내거나 문자열 코드를 쓰기 쉽다. 대신 매칭·Notification·에러 규칙을 모두 직접 정의하고 문서화해야 한다.
  - (C) 플랫폼 reply 기본기에 기댄다. iOS는 매칭이 공짜지만 에러가 문자열 하나뿐이고, Android에는 대응하는 Promise 매칭이 없어 플랫폼마다 구현이 달라진다. 선택할 Flutter WebView 패키지(#38)가 이런 API를 노출하는지에 달려 있다. 예를 들어 flutter_inappwebview 문서는 Promise를 돌려주는 `callHandler`와 `addWebMessageListener`(`allowedOriginRules`)를 제공한다고 적는다 [68].
  - Telegram, TeamsJS, JSON-RPC처럼 봉투를 전송 수단과 분리하면, 같은 봉투를 WebView 통로와 브라우저 `postMessage` 통로에 함께 쓸 수 있다 [1][47][53]. 이것은 아직 정하지 않은 개발용 가짜 Host와 맞닿는다.
- **에러**: 정수 코드냐 문자열 코드냐, 그리고 `data`나 `cause`를 둘지. S2에 필요한 분류(권한 거부, 사용자 취소, 개수·용량 초과, 시간 초과, 미지원 Host 기능, 구버전 Host)는 TeamsJS 분류에 거의 다 들어 있다. 사용자 취소를 에러(TeamsJS)로 볼지 정상 결과(Telegram, LIFF)로 볼지는 별도로 정해야 한다.
- **타임아웃·취소**
  - Web 쪽 Call마다 타임아웃을 두고 늦게 온 응답은 버린다(MCP 권장).
  - 취소 Message를 둘지, 둔다면 취소된 Call에 Host가 응답할지 정한다(LSP는 응답함, MCP는 응답하지 않음).
  - S2 업로드처럼 오래 걸리는 Call은 진행률 Event에 최대 시간을 함께 두거나(MCP), 결과를 여러 번 보내는 Call(Capacitor keepAlive)로 만든다.
  - 페이지 reload나 탐색 뒤 도착한 이전 응답을 어떻게 막을지 정한다(Capacitor의 무작위 id 시작값, Cordova의 secret 초기화).
- **Event 구독**
  - 하나의 DOM 이벤트에 type 필드를 붙이는 방식(현재 Demo, React Native WebView)과, 이름 기반 구독 API에 해제 핸들을 주는 방식(Capacitor, Telegram) 중에서 고른다. 후자에 구독 사실을 Host에 알리는 방식(TeamsJS)을 더할 수 있다.
  - Web이 준비되기 전에 일어난 Event(S3 콜드 스타트 딥링크, S4 로딩 중 멤버십 변경)는 보관(Capacitor), sticky(Cordova), ready 이후 전송(MCP Apps) 중 하나로 다룬다. Android `WebMessageListener`를 쓰게 되면 Web이 먼저 말해야 하므로 ready Message가 자연스럽게 필요해진다.
- **Host→Web Call**
  - 허용하면 GLOSSARY의 Call 정의가 양방향으로 바뀌고, S2 "작성 중 뒤로가기 이탈 확인"을 Host가 Web에 묻는 형태로 만들 수 있다(MCP Apps teardown, TeamsJS beforeUnload).
  - 다른 길은 Web이 "확인 필요" 상태를 미리 Message로 선언하고 Host가 지키게 하는 것이다(Telegram closing behavior). 이 길은 정의를 바꾸지 않고 Host가 기다릴 일도 없다.
  - 플랫폼 JS 실행에 기대면 iOS만 Promise를 기다린다고 문서화돼 있어 플랫폼 사이가 비대칭이 된다.
- **기능 탐색·버전**: 네 방식이 있다. ① ready 때 핸드셰이크로 버전과 capability를 교환한다(LSP, MCP Apps, TeamsJS). ② Host가 문서 시작 시 목록을 주입한다(Capacitor). ③ 메시지마다 버전을 싣는다(MCP 2026-07-28). ④ API별로 지원 여부를 묻는다(LIFF, TeamsJS). Web은 서버에서 배포되므로 Host보다 먼저 바뀐다. 오래된 Host와 새 Web이 만났을 때 무엇으로 판단할지는 Web 전달 방식과 버전 정책(#35, #46)과 함께 정해야 한다.
- **출처 검증**: 주로 보안 조사·결정(#36, #41)과 패키지 결정(#38)의 몫이다. 다만 계약이 메시지 출처나 main frame 여부를 기대할 수 있는지는 패키지가 정한다. 현재 webview_flutter JavaScript channel로는 그 정보를 얻을 수 없다.
- **큰 데이터 원칙**: 네 선택지가 있다. ① Bridge에는 핸들이나 URL만 싣고 바이트는 HTTP나 로컬 URL로 옮긴다(Capacitor `convertFileSrc`, Telegram). ② JSON 안에 base64로 싣는다(Cordova, Capacitor HTTP). ③ 조각으로 나눠 보낸다(TeamsJS). ④ ArrayBuffer를 쓴다(Android만 가능). S2 사진·영상 업로드 경로 결정(#32, #43)과 엮인다.

## 확인하지 못한 것과 새로 생긴 질문

확인하지 못한 것:

- LIFF SDK와 LINE 사이, 그리고 현재 Shopify App Bridge(CDN판)와 관리자 화면 사이의 메시지 형식은 공개 문서에서 찾지 못했다. Shopify는 이전 세대 npm 패키지 코드로만 확인했다.
- Telegram·LIFF·Shopify에 Host가 Web에 묻고 답을 받는 형식이 있는지는 찾지 못했다. 비교표에서 "확인 안 함"인 칸(Telegram 타임아웃, LIFF Event 구독·큰 데이터, Shopify 타임아웃·Event·큰 데이터, React Native WebView 기능·버전)은 조사하지 않았다.
- 실제 동작은 실험하지 않았다. 확인하지 않은 것: Android `evaluateJavascript`에 Promise를 반환하는 코드를 넘겼을 때의 결과, iOS의 교차 출처 iframe에 handler가 실제로 노출되는지, 사용자 기기의 WebView 버전별 `WEB_MESSAGE_LISTENER`·`WEB_MESSAGE_ARRAY_BUFFER` 지원 비율.
- 범위 밖으로 둔 사례: Tauri 2는 공식 문서만 훑었다. Tauri 2는 `invoke`에 ArrayBuffer를 그대로 싣고 `tauri::ipc::Response`로 바이트를 돌려줄 수 있으며, 스트리밍에는 Channel을 권하고, capability의 `remote.urls`로 원격 origin에 명령 접근을 허용한다 [66][67]. flutter_inappwebview는 문서 한 쪽만 확인했고 세부는 패키지 비교(#28)의 몫이다.

새로 생긴 질문:

1. 선택할 Flutter WebView 패키지가 `sourceOrigin`·`isMainFrame`, reply(Promise), ArrayBuffer를 노출하는가(#28, #38). 계약이 플랫폼 기본기에 기댈 수 있는지가 여기에 달렸다.
2. 사용자가 선택을 취소하거나 권한을 거부한 경우(S2)를 에러 코드로 둘지 정상 결과로 둘지.
3. Host→Web Call을 허용한다면, Web이 아직 로드되지 않았거나 준비되지 않았을 때 Host는 얼마나 기다리고 어떻게 포기하는가. GLOSSARY의 Call 정의 변경도 포함한다.
4. Web 준비 전에 일어난 Event(S3 콜드 스타트 딥링크, S4 멤버십 변경)를 보관, sticky, ready 핸드셰이크 중 무엇으로 다룰지.
5. 버전 어긋남을 누가 언제 판단하는가: Web 로드 시 핸드셰이크인가, 메시지마다인가. 호환되지 않을 때 Web 화면과 Host 화면은 무엇을 보여 주는가(#35, #46).
6. S2 사진·영상의 바이트 경로: Bridge(base64나 조각), Host 직접 업로드, Host가 준 로컬 URL·핸들로 Web이 업로드하는 방식 중 무엇인가(#32, #43).

## 출처

1. [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
2. [Language Server Protocol Specification 3.18](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/specification/)
3. [MCP Specification 2026-07-28: Cancellation](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/cancellation)
4. [MCP Specification 2026-07-28: Versioning and Compatibility](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning)
5. [SEP-1865 MCP Apps 명세 2026-01-26 (modelcontextprotocol/ext-apps)](https://github.com/modelcontextprotocol/ext-apps/blob/main/specification/2026-01-26/apps.mdx)
6. [Capacitor 8.5.3 `core/native-bridge.ts`](https://github.com/ionic-team/capacitor/blob/8.5.3/core/native-bridge.ts)
7. [Capacitor 8.5.3 `core/src/runtime.ts`](https://github.com/ionic-team/capacitor/blob/8.5.3/core/src/runtime.ts)
8. [Capacitor 8.5.3 `core/src/util.ts`](https://github.com/ionic-team/capacitor/blob/8.5.3/core/src/util.ts)
9. [Capacitor 8.5.3 `MessageHandler.java`](https://github.com/ionic-team/capacitor/blob/8.5.3/android/capacitor/src/main/java/com/getcapacitor/MessageHandler.java)
10. [Capacitor 8.5.3 `Bridge.java`](https://github.com/ionic-team/capacitor/blob/8.5.3/android/capacitor/src/main/java/com/getcapacitor/Bridge.java)
11. [Capacitor 8.5.3 `Plugin.java`](https://github.com/ionic-team/capacitor/blob/8.5.3/android/capacitor/src/main/java/com/getcapacitor/Plugin.java)
12. [Capacitor 8.5.3 `PluginCall.java`](https://github.com/ionic-team/capacitor/blob/8.5.3/android/capacitor/src/main/java/com/getcapacitor/PluginCall.java)
13. [Capacitor 8.5.3 `WebViewDelegationHandler.swift`](https://github.com/ionic-team/capacitor/blob/8.5.3/ios/Capacitor/Capacitor/WebViewDelegationHandler.swift)
14. [Capacitor 8.5.3 `JSExport.swift`](https://github.com/ionic-team/capacitor/blob/8.5.3/ios/Capacitor/Capacitor/JSExport.swift)
15. [Capacitor 문서: Persisting Plugin Calls](https://capacitorjs.com/docs/core-apis/saving-calls)
16. [Capacitor 문서: Capacitor Web API](https://capacitorjs.com/docs/core-apis/web)
17. [Capacitor 문서: Capacitor Android Plugin Guide](https://capacitorjs.com/docs/plugins/android)
18. [cordova-android 15.1.0 `cordova-js-src/exec.js`](https://github.com/apache/cordova-android/blob/rel/15.1.0/cordova-js-src/exec.js)
19. [cordova-android 15.1.0 `CordovaBridge.java`](https://github.com/apache/cordova-android/blob/rel/15.1.0/framework/src/org/apache/cordova/CordovaBridge.java)
20. [cordova-android 15.1.0 `PluginResult.java`](https://github.com/apache/cordova-android/blob/rel/15.1.0/framework/src/org/apache/cordova/PluginResult.java)
21. [cordova-android 15.1.0 `NativeToJsMessageQueue.java`](https://github.com/apache/cordova-android/blob/rel/15.1.0/framework/src/org/apache/cordova/NativeToJsMessageQueue.java)
22. [cordova-android 15.1.0 `CordovaPlugin.java`](https://github.com/apache/cordova-android/blob/rel/15.1.0/framework/src/org/apache/cordova/CordovaPlugin.java)
23. [cordova-android 15.1.0 `PluginManager.java`](https://github.com/apache/cordova-android/blob/rel/15.1.0/framework/src/org/apache/cordova/PluginManager.java)
24. [cordova-js 6.1.0 `src/cordova.js`](https://github.com/apache/cordova-js/blob/rel/6.1.0/src/cordova.js)
25. [cordova-js 6.1.0 `src/common/channel.js`](https://github.com/apache/cordova-js/blob/rel/6.1.0/src/common/channel.js)
26. [cordova-ios 8.1.1 `cordova-js-src/exec.js`](https://github.com/apache/cordova-ios/blob/rel/8.1.1/cordova-js-src/exec.js)
27. [cordova-ios 8.1.1 `CDVWebViewEngine.m`](https://github.com/apache/cordova-ios/blob/rel/8.1.1/CordovaLib/Classes/Private/Plugins/CDVWebViewEngine/CDVWebViewEngine.m)
28. [Cordova 문서: Android Plugin Development Guide](https://cordova.apache.org/docs/en/latest/guide/platforms/android/plugin.html)
29. [react-native-webview 16.0.0 `docs/Guide.md`](https://github.com/react-native-webview/react-native-webview/blob/v16.0.0/docs/Guide.md)
30. [react-native-webview 16.0.0 `docs/Reference.md`](https://github.com/react-native-webview/react-native-webview/blob/v16.0.0/docs/Reference.md)
31. [react-native-webview 16.0.0 `RNCWebView.java`](https://github.com/react-native-webview/react-native-webview/blob/v16.0.0/android/src/main/java/com/reactnativecommunity/webview/RNCWebView.java)
32. [react-native-webview 16.0.0 `RNCWebViewManager.kt`](https://github.com/react-native-webview/react-native-webview/blob/v16.0.0/android/src/main/java/com/reactnativecommunity/webview/RNCWebViewManager.kt)
33. [react-native-webview 16.0.0 `apple/RNCWebViewImpl.m`](https://github.com/react-native-webview/react-native-webview/blob/v16.0.0/apple/RNCWebViewImpl.m)
34. [AndroidX `WebViewCompat.java` (addWebMessageListener Javadoc)](https://github.com/androidx/androidx/blob/androidx-main/webkit/webkit/src/main/java/androidx/webkit/WebViewCompat.java)
35. [AndroidX `JavaScriptReplyProxy.java`](https://github.com/androidx/androidx/blob/androidx-main/webkit/webkit/src/main/java/androidx/webkit/JavaScriptReplyProxy.java)
36. [androidx.webkit 릴리스 노트](https://developer.android.com/jetpack/androidx/releases/webkit)
37. [Android API reference: `WebView.evaluateJavascript`](https://developer.android.com/reference/android/webkit/WebView#evaluateJavascript(java.lang.String,%20android.webkit.ValueCallback%3Cjava.lang.String%3E))
38. [Android 보안 가이드: WebView – Native bridges](https://developer.android.com/privacy-and-security/risks/insecure-webview-native-bridges)
39. [WebKit `WKScriptMessageHandlerWithReply.h`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKScriptMessageHandlerWithReply.h)
40. [WebKit `WKUserContentController.h`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKUserContentController.h)
41. [WebKit `WKScriptMessage.h`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKScriptMessage.h)
42. [WebKit `WKFrameInfo.h`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKFrameInfo.h)
43. [WebKit `WKWebView.h` (evaluateJavaScript, callAsyncJavaScript)](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebView.h)
44. [Apple Developer: WKScriptMessageHandlerWithReply](https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply)
45. [Telegram: Telegram Mini Apps](https://core.telegram.org/bots/webapps)
46. [Telegram: Web events](https://core.telegram.org/api/web-events)
47. [Telegram: `telegram-web-app.js`](https://telegram.org/js/telegram-web-app.js)
48. [Telegram: Bot API changelog](https://core.telegram.org/bots/api-changelog)
49. [LINE Developers: LIFF v2 API reference](https://developers.line.biz/en/reference/liff/)
50. [LINE Developers: Developing a LIFF app](https://developers.line.biz/en/docs/liff/developing-liff-apps/)
51. [LINE Developers: LIFF release notes](https://developers.line.biz/en/docs/liff/release-notes/)
52. [TeamsJS 2.58.0 `internal/messageObjects.ts`](https://github.com/OfficeDev/microsoft-teams-library-js/blob/v2.58.0/packages/teams-js/src/internal/messageObjects.ts)
53. [TeamsJS 2.58.0 `internal/communication.ts`](https://github.com/OfficeDev/microsoft-teams-library-js/blob/v2.58.0/packages/teams-js/src/internal/communication.ts)
54. [TeamsJS 2.58.0 `public/interfaces.ts`](https://github.com/OfficeDev/microsoft-teams-library-js/blob/v2.58.0/packages/teams-js/src/public/interfaces.ts)
55. [TeamsJS 2.58.0 `internal/validOrigins.ts`](https://github.com/OfficeDev/microsoft-teams-library-js/blob/v2.58.0/packages/teams-js/src/internal/validOrigins.ts)
56. [TeamsJS 2.58.0 `public/runtime.ts`](https://github.com/OfficeDev/microsoft-teams-library-js/blob/v2.58.0/packages/teams-js/src/public/runtime.ts)
57. [TeamsJS 2.58.0 `internal/handlers.ts`](https://github.com/OfficeDev/microsoft-teams-library-js/blob/v2.58.0/packages/teams-js/src/internal/handlers.ts)
58. [TeamsJS 2.58.0 `public/media.ts`](https://github.com/OfficeDev/microsoft-teams-library-js/blob/v2.58.0/packages/teams-js/src/public/media.ts)
59. [TeamsJS 2.58.0 `internal/appHelpers.ts`](https://github.com/OfficeDev/microsoft-teams-library-js/blob/v2.58.0/packages/teams-js/src/internal/appHelpers.ts)
60. [Microsoft Learn: Teams JavaScript client library](https://learn.microsoft.com/en-us/microsoftteams/platform/tabs/how-to/using-teams-client-library)
61. [Shopify: Migrate your app to Shopify App Bridge](https://shopify.dev/docs/api/app-bridge/migration-guide)
62. [`@shopify/app-bridge` 3.7.12 `umd/index.development.js` (npm 배포본)](https://unpkg.com/@shopify/app-bridge@3.7.12/umd/index.development.js)
63. [webview_flutter_platform_interface `JavaScriptMessage`](https://github.com/flutter/packages/blob/main/packages/webview_flutter/webview_flutter_platform_interface/lib/src/types/javascript_message.dart)
64. [webview_flutter_android `WebViewProxyApi.java`](https://github.com/flutter/packages/blob/main/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/WebViewProxyApi.java)
65. [TeamsJS 2.58.0 `public/app/lifecycle.ts`](https://github.com/OfficeDev/microsoft-teams-library-js/blob/v2.58.0/packages/teams-js/src/public/app/lifecycle.ts)
66. [Tauri 2: Calling Rust from the Frontend](https://v2.tauri.app/develop/calling-rust/)
67. [Tauri 2: Capabilities](https://v2.tauri.app/security/capabilities/)
68. [flutter_inappwebview: JavaScript WebView Communication](https://inappwebview.dev/docs/webview/javascript/communication/)
