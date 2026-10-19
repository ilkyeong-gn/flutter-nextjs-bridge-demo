# Host는 Event를 플랫폼 응답 통로로만 보낸다 (iOS는 대기 응답)

Host가 Web에 보내는 Event도 Call 응답처럼 출처를 판정한 프레임에만 가야 한다. 그래서 `evaluateJavaScript`로 전역 함수를 부르거나 `CustomEvent`를 띄우지 않고, 플랫폼 응답 통로로만 보낸다. Android는 출처를 판정한 프레임의 reply proxy를 쓴다. iOS는 대기 응답을 쓴다. Web이 `listen` 요청을 보내 두면 Host는 Event가 생길 때 그 Promise를 Event 묶음으로 이행하고, Web은 받자마자 `listen`을 다시 보낸다. 이렇게 하면 [ADR 0002](0002-webview-package-with-platform-code.md)의 "Bridge 통로는 출처 판정 통로 하나뿐"이 Event에도 그대로 적용된다.

## Considered Options

- **`evaluateJavaScript`로 전역 함수 호출 또는 `CustomEvent` 띄우기(Demo 방식)**: 실행 시점에 메인 프레임에 떠 있는 문서라면 어떤 문서에서든 실행된다. Web이 다른 출처로 이동한 뒤라면 그 페이지에 Event가 간다. 같은 페이지의 다른 스크립트가 전역 함수를 덮어써서 Event를 가로챌 수 있고, `CustomEvent`는 위조할 수 있다.
- **문서 시작 스크립트로 수신 함수를 미리 넣기**: Android는 WebView 101 이상이 필요하다. iOS는 `removeJavaScriptChannel`과 `enableZoom`이 스크립트를 지우므로 어댑터 층이 이 둘을 막아야 한다. 그리고 실행 대상 문서를 고를 수 없다는 문제는 그대로 남는다.

## Consequences

- iOS에서는 Web이 항상 `listen` 하나를 걸어 두어야 한다. 걸어 둔 요청이 없는 동안 생긴 Event는 Host가 WebView별로 보관한다. 상태 Event는 마지막 값만 보관하고, 일회 Event는 순서대로 큐에 쌓는다.
- Android reply proxy는 Web이 먼저 보내야 생긴다. 그래서 핸드셰이크가 끝나기 전에는 두 플랫폼 모두 Event를 보내지 않는다.
- iOS reply handler에는 시간 제한이 없다. 응답하지 않은 채 handler가 해제되면 Promise가 거부된다(문서 확인). 문서가 바뀌면 걸려 있던 `listen`이 끝나는지는 실측하지 않았으므로 플랫폼 코드 통합 테스트에 넣는다.
- Event에는 민감한 값을 싣지 않고, Web은 Event를 권한 판단의 근거로 삼지 않는다. Event를 받은 Web은 필요한 값을 서버에서 다시 읽는다.
- 개발용 가짜 Host도 같은 봉투와 `listen` 흐름을 흉내 낸다.

결정의 자세한 내용: [Bridge 계약 형태 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/39)
