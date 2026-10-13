# webview_flutter와 Next.js로 Stage A/B/C를 구현하는 메커니즘 조사

Type: research
Status: resolved
Blocked by:
Map: [Flutter + Next.js 브릿지 데모](../map.md)
Findings: 브랜치 `research/bridge-mechanism`, 파일 `research/bridge-mechanism.md`

## Question

현재(2026년 10월) 안정 버전 기준으로, 아래 사실을 1차 자료(공식 문서, pub.dev, 소스 코드)로 확인한다.

1. `webview_flutter` 최신 버전에서 Web → Host Message(`addJavaScriptChannel`/`postMessage`), Host → Web(`runJavaScript` 등)의 정확한 API와 제약 (iOS·Android 차이 포함).
2. Stage C Call을 id 매칭으로 구현하는 최소 패턴: Web의 Promise 대기 → Host 처리 → Host가 결과를 Web에 돌려주는 경로. 알려진 함정(문자열 이스케이프, 페이지 로드 전 호출, 채널 주입 시점).
3. Next.js 최신 App Router에서 Web 쪽 연결 시점: 채널 전역 객체가 hydration 전후 언제 존재하는지, `'use client'` 컴포넌트에서 Host 존재 여부를 감지하는 방법, Host가 Event를 전달할 때 쓸 전역 함수나 `CustomEvent` 방식의 장단점.
4. 개발 서버 접속을 위한 플랫폼 설정: Android 에뮬레이터 `10.0.2.2` + 평문 HTTP 허용(network security config / `usesCleartextTraffic`), iOS 시뮬레이터 `localhost` + ATS 예외 필요 여부, Next.js dev 서버의 호스트 바인딩·`allowedDevOrigins` 같은 설정 필요 여부.
5. 기기 정보(플랫폼, OS 버전)를 얻는 가장 간단한 방법: `dart:io` `Platform`만으로 충분한지, `device_info_plus`가 필요한지.

추천 패턴과 최소 코드 스케치를 포함한다. 이 결과는 [Bridge 규약 확정](04-decide-bridge-contract.md)의 입력이 된다.

## Answer

- **핵심 사실 요약**:
  - `webview_flutter` 최신(`4.14.1`): `addJavaScriptChannel('FlutterBridge')`로 단일 문자열 수신, `runJavaScript`로 Web에 비동기 전달. iOS/Android 동일 인터페이스.
  - Stage C Call 매칭: Web은 `Map<string, {resolve, reject}>`에 대기 핸들러를 등록하고 `id`를 포함해 `postMessage`. Host는 처리 후 `window.__onFlutterResponse({ id, result, error })`를 `jsonEncode` 직렬화와 함께 호출하여 주입 위험 방지.
  - Next.js App Router: 브릿지 연동 컴포넌트는 `'use client'` 필수. `useEffect`에서 `window.FlutterBridge` 존재 여부로 Host 상태를 판정하고 `CustomEvent('flutter:event')`로 이벤트를 수신하여 React unmount cleanup과 자연스럽게 연계.
  - 개발 환경 통신 설정: Android는 `AndroidManifest.xml`에 `android:usesCleartextTraffic="true"` 및 `10.0.2.2:3000` 사용. iOS는 `Info.plist`에 `NSAllowsLocalNetworking: true` 및 `localhost:3000` 사용. Next.js는 `next dev -H 0.0.0.0`으로 실행.
  - 기기 정보 획득: 외부 플러그인(`device_info_plus`) 없이 `dart:io` 내장 `Platform.operatingSystem`과 `Platform.operatingSystemVersion`만으로 플랫폼 및 OS 버전을 완벽히 지원.
- **상세 보고서 위치**: 브랜치 `research/bridge-mechanism`, 파일 `research/bridge-mechanism.md`
