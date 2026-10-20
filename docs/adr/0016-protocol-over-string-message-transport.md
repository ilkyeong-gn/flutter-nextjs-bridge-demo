# Bridge 프로토콜은 짝 없는 문자열 통로만 가정한다

WebView 패키지가 정해지지 않았어도 Bridge 프로토콜은 지금 고정한다. 그래서 프로토콜 층이 통로에 기대는 것은 Transport 하나로 줄인다. Transport는 문서 하나 동안 열리는 문자열 양방향 통로다(`send(text): void`, `onMessage`, 그리고 통로가 없으면 `null`을 돌려주는 비동기 `connect`). 후보 통로 가운데 응답 통로가 없는 것이 있으므로, Call과 결과의 짝은 봉투의 `id`로만 맞추고 응답이 오지 않는 경우는 타임아웃으로 처리한다. 프로토콜이 통로에 대해 가정하는 것은 셋뿐이다. Web이 먼저 말한다, 응답이 오지 않을 수 있다, 통로는 문서 하나 동안만 산다. 이 ADR은 [ADR 0003](0003-events-over-platform-reply-channel.md)을 대체한다. "Event는 출처를 판정한 프레임에만 간다"는 조건은 이제 Transport 어댑터와 Host가 지킬 요구 조건이다. iOS `listen` 대기 응답도 계약에서 빼고, iOS `WithReply` 어댑터와 Host 플랫폼 코드 사이의 사정으로 내린다.

## Considered Options

- **ADR 0003처럼 계약에 플랫폼 응답 통로와 `listen`을 둔다**: 이 방식은 특정 패키지와 플랫폼 API를 고른 뒤에야 성립한다. JavaScript 채널, `WKScriptMessageHandler`, `addWebMessageListener`에는 응답 통로가 없다. 그리고 가짜 Host가 iOS 사정까지 흉내 내야 한다.
- **`send`가 Promise를 돌려주게 한다**: 응답 통로가 있다고 가정하게 된다. 플랫폼이 짝을 보장하는 통로는 iOS `WithReply` 하나뿐이고, 그 통로는 Host가 먼저 보낼 수 없다.

## Consequences

- 봉투는 `kind`(`message`·`event`·`call`·`result`)와 `id`를 가진 JSON이고, Transport에는 문자열 하나로 싣는다. JSON이 아니거나 `kind`를 모르는 문자열은 조용히 버린다. 가짜 Host 껍데기의 `window.postMessage`에는 다른 스크립트가 보낸 메시지도 섞이기 때문이다.
- Call `id`는 문서마다 무작위로 정한 접두어에 순번을 붙여 만든다. 문서가 바뀐 뒤 늦게 온 결과가 새 문서에서 같은 id의 Call을 이행하는 일을 막기 위해서다. 이런 일이 `callHandler`에서 생기는지는 아직 실측하지 않았다.
- 프로토콜 버전은 Bridge 계약 major.minor 하나뿐이다. 봉투 형식이 깨지면 그것도 major 변경이다. 메시지마다 버전 필드를 붙이지 않는다. 그 대신 `hello` Call과 결과의 `contractVersion` 필드 모양은 모든 major에서 고정하고, Web도 `hello` 인자에 자기 계약 버전을 실어 보낸다.
- 메시지 크기 상한(출발값 1 MB)은 계약에 적는다. Web은 보내기 전에 크기를 검사해서 넘으면 Call을 `invalid_params`로 바로 실패시킨다.
- 핸드셰이크 전에는 Host가 Event를 보내지 않는다. Host는 상태 Event의 마지막 값과 일회 Event의 큐를 보관한다. 이 둘은 Host가 지킬 의무로 계약에 적고, 가짜 Host가 흉내 낸다.
- 확인하지 못한 통로 동작이 셋 있다. iOS `WithReply`의 대기 Promise가 탐색 때 거부되는지, `callHandler`의 늦은 응답이 어떻게 처리되는지, `WebMessagePort`가 어떻게 닫히는지다. 프로토콜은 이 동작들에 기대지 않으므로, 패키지가 정해진 뒤 어댑터 통합 테스트에서 확인한다.

결정의 자세한 내용: [Bridge 프로토콜 기반 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/60)
