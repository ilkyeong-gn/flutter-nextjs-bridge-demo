# webview_flutter와 Next.js로 Stage A/B/C를 구현하는 메커니즘 조사 (Findings)

- **티켓**: [02-research-bridge-mechanism.md](../../.scratch/bridge-demo/issues/02-research-bridge-mechanism.md)
- **작성일**: 2026-10-13
- **환경 기준**: Flutter 3.47.7 (Stable), `webview_flutter: ^4.14.1`, Next.js 15+ (App Router), Node v26.11.1

---

## 1. webview_flutter 4.x API 및 통신 메커니즘

`webview_flutter` 4.x는 `WebViewController` 중심의 객체 지향 API를 사용한다.

### 1.1 Web → Host (Message)
- **Host (Flutter)**:
  ```dart
  controller.addJavaScriptChannel(
    'FlutterBridge',
    onMessageReceived: (JavaScriptMessage message) {
      // message.message는 JavaScript에서 전달한 raw string
      handleIncomingMessage(message.message);
    },
  );
  ```
- **Web (JavaScript)**:
  `addJavaScriptChannel('FlutterBridge', ...)`을 등록하면 브라우저 전역에 `window.FlutterBridge` 객체가 생성된다.
  ```javascript
  if (typeof window !== 'undefined' && window.FlutterBridge) {
    window.FlutterBridge.postMessage(JSON.stringify({ type: 'A', payload: '...' }));
  }
  ```
- **제약 및 플랫폼 차이**:
  - `postMessage`는 단일 문자열 인자만 받는다. 따라서 복합 데이터는 반드시 `JSON.stringify`로 직렬화하여 전달한다.
  - Android와 iOS 모두 동일한 `window.<ChannelName>.postMessage(...)` 인터페이스로 통일되어 있어 플랫폼별 JS 분기가 필요 없다.

### 1.2 Host → Web (Event)
- **Host (Flutter)**:
  ```dart
  // runJavaScript는 결과를 기다리지 않고 비동기로 스크립트를 실행한다.
  await controller.runJavaScript(
    'window.dispatchEvent(new CustomEvent("flutter:event", { detail: ${jsonEncode(payload)} }));'
  );
  ```
- **Web (JavaScript)**:
  ```javascript
  window.addEventListener('flutter:event', (e) => {
    console.log('수신된 이벤트:', e.detail);
  });
  ```
- **장점**:
  - `CustomEvent`를 사용하면 Next.js(React) 컴포넌트의 `useEffect` 훅에서 `addEventListener` 및 `removeEventListener`(cleanup)와 자연스럽게 결합되어 메모리 누수가 발생하지 않는다.

---

## 2. Stage C (Call/Promise) 매칭 패턴 및 주의점

### 2.1 메커니즘 설계 (Request-Response Matching)
단방향 메시지 채널만 제공하는 `webview_flutter`에서 양방향 RPC(Call)를 구현하는 최소 구조:

```
[Web]                                             [Host]
  │                                                 │
  ├─ 1. callHost('getDeviceInfo')                  │
  │    (UUID 생성, pendingCalls에 resolve/reject 보관)│
  │    postMessage({ id, method, params }) ─────────>│
  │                                                 ├─ 2. method 라우팅 및 처리
  │                                                 │    (Platform.operatingSystem 등)
  │                                                 │
  │<── runJavaScript(`__onFlutterResponse(...)`) ───┤ 3. { id, result, error } 응답
  │                                                 │
  ├─ 4. pendingCalls.get(id) 찾아 resolve/reject   │
```

### 2.2 코드 스케치

#### Web (TypeScript/Client Component)
```typescript
interface PendingHandler {
  resolve: (value: any) => void;
  reject: (reason: any) => void;
}

const pendingCalls = new Map<string, PendingHandler>();

// 전역 응답 수신부 (초기화 1회)
if (typeof window !== 'undefined') {
  (window as any).__onFlutterResponse = (response: { id: string; result?: any; error?: string }) => {
    const handler = pendingCalls.get(response.id);
    if (!handler) return;
    pendingCalls.delete(response.id);

    if (response.error) {
      handler.reject(new Error(response.error));
    } else {
      handler.resolve(response.result);
    }
  };
}

export function callHost<T = any>(method: string, params?: any): Promise<T> {
  return new Promise((resolve, reject) => {
    if (typeof window === 'undefined' || !(window as any).FlutterBridge) {
      return reject(new Error('Host 브릿지를 찾을 수 없습니다.'));
    }

    const id = Math.random().toString(36).substring(2, 9);
    pendingCalls.set(id, { resolve, reject });

    (window as any).FlutterBridge.postMessage(
      JSON.stringify({ id, method, params })
    );
  });
}
```

#### Host (Dart)
```dart
void handleMessage(String rawMessage) {
  try {
    final Map<String, dynamic> data = jsonDecode(rawMessage);
    final String? id = data['id'];
    final String? method = data['method'];

    if (id != null && method != null) {
      // Stage C: Call 처리
      _handleCall(id, method, data['params']);
    } else {
      // Stage A: 단순 Message 처리
      _handleSimpleMessage(data);
    }
  } catch (e) {
    debugPrint('JSON 파싱 오류: $e');
  }
}

void _handleCall(String id, String method, dynamic params) {
  if (method == 'getDeviceInfo') {
    final result = {
      'platform': Platform.operatingSystem, // 'android' 또는 'ios'
      'version': Platform.operatingSystemVersion,
    };
    _sendResponse(id, result: result);
  } else {
    _sendResponse(id, error: 'Unknown method: $method');
  }
}

void _sendResponse(String id, {dynamic result, String? error}) {
  final payload = {
    'id': id,
    if (result != null) 'result': result,
    if (error != null) 'error': error,
  };
  // 중요: Dart의 jsonEncode를 사용하여 문자열 이스케이프 안전성 확보
  final script = 'window.__onFlutterResponse && window.__onFlutterResponse(${jsonEncode(payload)});';
  controller.runJavaScript(script);
}
```

### 2.3 주요 함정 및 해결책
1. **문자열 이스케이프(Injection/SyntaxError)**: JS 문자열 템플릿에 직접 변수를 넣으면 작은따옴표/줄바꿈 등으로 인해 스크립트 실행이 깨질 수 있다. Dart 표준 라이브러리의 `jsonEncode(payload)`를 그대로 인자로 삽입하여 항상 유효한 JSON 표현식이 되도록 보장한다.
2. **페이지 로드 전 호출 방지**: 웹 페이지가 아직 로드되지 않은 상태에서 Host가 이벤트를 보내면 수신되지 않는다. Web에서 Host 준비 상태를 알리거나, 사용자의 명시적인 버튼 인터랙션에 의해서만 통신하도록 구성한다.

---

## 3. Next.js App Router 연동 시점 및 감지

1. **Hydration 및 클라이언트 바운더리**:
   - `window` 객체에 접근하는 브릿지 인터랙션 컴포넌트는 반드시 최상단에 `'use client'`를 선언해야 한다.
2. **Host 존재 여부 감지 (`isHostAvailable`)**:
   - SSR 시점에는 `false`.
   - `useEffect` 훅 내부에서 `typeof window !== 'undefined' && 'FlutterBridge' in window`로 감지하여 React 상태로 보관한다.
   - 브라우저에서 직접 접속한 경우(Next.js 개발 서버를 Chrome 등으로 열람 시) "Host 외부에서 실행 중" 배지를 표시하고 브릿지 호출 버튼을 `disabled` 처리한다.
3. **이벤트 구독 라이프사이클**:
   - `CustomEvent`를 사용해 React 컴포넌트 마운트 시 `window.addEventListener('flutter:event', handler)`를 등록하고 unmount 시 `removeEventListener`를 호출한다.

---

## 4. 로컬 개발 환경 플랫폼 설정 사실

### 4.1 Android 에뮬레이터
- **접속 호스트**: `http://10.0.2.2:3000` (Android 에뮬레이터에서 호스트 머신의 `localhost:3000`으로 매핑되는 주소).
- **Cleartext HTTP 허용**: Android 9(API 28) 이상에서는 평문 HTTP가 기본 차단된다.
  - `android/app/src/main/AndroidManifest.xml`의 `<application>` 태그에 속성 추가:
    ```xml
    <application
        ...
        android:usesCleartextTraffic="true">
    ```

### 4.2 iOS 시뮬레이터
- **접속 호스트**: `http://localhost:3000` (iOS 시뮬레이터는 macOS의 로컬 네트워크를 공유).
- **ATS (App Transport Security)**:
  - iOS 시뮬레이터에서 `localhost`에 대한 HTTP 연결은 기본 허용되나, 안정성을 위해 `ios/Runner/Info.plist`에 다음 키를 추가하는 것이 안전하다:
    ```xml
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    ```

### 4.3 Next.js 개발 서버
- Next.js의 `next dev` 명령은 기본적으로 `localhost:3000`에 바인딩된다.
- Android 에뮬레이터(`10.0.2.2`)에서의 원활한 바인딩을 위해 `next dev -H 0.0.0.0` 또는 `package.json`의 `"dev": "next dev -H 0.0.0.0"`으로 지정하는 것이 가장 확실하다.

---

## 5. 기기 정보 획득 방식

- `dart:io`의 표준 라이브러리인 `Platform` 클래스만으로 충분하다:
  - `Platform.operatingSystem`: `'android'` 또는 `'ios'`
  - `Platform.operatingSystemVersion`: OS 버전 문자열
- 서드파티 패키지(`device_info_plus` 등)를 추가하지 않아도 요구사항인 "플랫폼 및 OS 버전"을 완벽하게 반환할 수 있으므로, 의존성 없는 가장 단순한 형식을 유지할 수 있다.

---

## 6. 결론 및 추천안

- **Channel 이름**: `'FlutterBridge'`로 단일화.
- **Event 방식**: `window.dispatchEvent(new CustomEvent('flutter:event', { detail: payload }))` 채택 (React cleanup과 궁합 우수).
- **Call 방식**: Web의 `Map<string, {resolve, reject}>` + Host의 `_sendResponse(id, result, error)` 및 `jsonEncode` 직렬화 채택.
- **플랫폼 설정**: Android `usesCleartextTraffic="true"`, iOS `NSAllowsLocalNetworking: true`, Next.js `-H 0.0.0.0` 적용.
- **기기 정보**: `dart:io` `Platform` 내장 API 사용.

---

## 7. 출처

1. [pub.dev - webview_flutter 4.14.1 Documentation](https://pub.dev/packages/webview_flutter)
2. [flutter/packages repository - webview_flutter source](https://github.com/flutter/packages/tree/main/packages/webview_flutter)
3. [Android Developers - Network security configuration & cleartext traffic](https://developer.android.com/privacy-and-security/security-config)
4. [Apple Developer - NSAppTransportSecurity Documentation](https://developer.apple.com/documentation/bundleresources/information_property_list/nsapptransportsecurity)
5. [Next.js Documentation - 'use client' Directive](https://nextjs.org/docs/app/building-your-application/rendering/client-components)
