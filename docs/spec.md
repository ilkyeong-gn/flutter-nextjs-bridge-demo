# 스펙: Flutter + Next.js 하이브리드 앱 브릿지 데모

- **문서 위치**: `docs/spec.md`
- **상태**: 확정 (Decisions Locked)
- **추적 지도**: [GitHub Issue #1 (Map: Flutter + Next.js 브릿지 데모)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/1)
- **기반 결정**:
  - [#2 Stage 구성 방식 트레이드오프 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/2)
  - [#3 webview_flutter 및 Next.js 메커니즘 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/3)
  - [#4 Stage 구성 방식 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/4)
  - [#5 Bridge 규약 확정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/5)
  - [#6 프로젝트 구조 및 데모 실행·검증 규격 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/6)

---

## 1. 목적 및 범위

### 1.1 목적
Flutter(Host) 앱이 Next.js(Web)를 WebView로 띄우고 브릿지로 통신하는 가장 간단한 형태의 데모를 구축한다. 독자가 브릿지의 발전 과정을 직관적으로 이해할 수 있도록 **Stage A(단방향) → Stage B(양방향 이벤트) → Stage C(양방향 호출/Promise)** 순서로 기능을 점진적으로 확장하여 제공한다.

### 1.2 범위
- **지원 플랫폼**: iOS 시뮬레이터, Android 에뮬레이터
- **핵심 기술**: Flutter 3.x, 공식 `webview_flutter: ^4.14.1`, Next.js 15+ (App Router, TypeScript)
- **제외 대상 (Out of Scope)**:
  - 타임아웃, 재시도, 취소 등 Call의 복잡한 실패 복구 메커니즘
  - 메시지 규약 코드 생성기(Protobuf 등)나 공유 npm/pub 패키지
  - 브라우저 대체 모의 호스트(Mock Host)
  - 프로덕션 배포(Vercel, 앱스토어 빌드) 및 Flutter Web/데스크톱

---

## 2. 도메인 용어 (GLOSSARY)

| 용어 | 정의 | 피해야 할 표현 |
| :--- | :--- | :--- |
| **Host (호스트)** | WebView를 띄우는 Flutter 앱 | 네이티브, 앱, 셸 |
| **Web (웹)** | WebView 안에서 실행되는 Next.js 페이지 | 프론트, 웹뷰(컴포넌트), 클라이언트 |
| **Bridge (브릿지)** | Host와 Web 사이의 메시지 통로와 통신 규약 | 채널, 인터페이스 |
| **Message (메시지)** | Bridge를 한 방향으로 건너는 응답 없는 단위 데이터 | 패킷, 신호 |
| **Event (이벤트)** | Host가 Web에 비동기로 전달하는 Message | 푸시, 알림 |
| **Call (호출)** | Web이 Host에 요청을 보내고 응답을 기다리는 단위 작업 | 요청, RPC, invoke |
| **Stage (단계)** | 데모가 보여주는 브릿지 능력의 수준 (A: 단방향, B: 양방향, C: 호출) | 레벨, 버전, 예제 |

---

## 3. 구조 및 구성 방식

### 3.1 단일 모노레포 및 탭/라우트 기반 Stage 분리
- `app/`(Flutter)과 `web/`(Next.js)을 단일 저장소에 배치한다.
- `pnpm dev` 1회, `flutter run` 1회로 한 번만 실행하면 화면 내 탭 전환을 통해 Stage A, B, C를 실시간으로 비교 시연할 수 있다.
- 구현 커밋은 `feat: Stage A` → `feat: Stage B` → `feat: Stage C` 3단계 선형 커밋으로 기록하여 `git diff`로도 순수 증분을 확인할 수 있도록 한다.

### 3.2 디렉터리 레이아웃
```
.
├── GLOSSARY.md
├── AGENTS.md
├── docs/
│   ├── spec.md
│   └── agents/
├── app/                                  # Flutter Host 프로젝트
│   ├── pubspec.yaml                      # webview_flutter: ^4.14.1
│   ├── android/app/src/main/AndroidManifest.xml # usesCleartextTraffic="true"
│   ├── ios/Runner/Info.plist             # NSAllowsLocalNetworking
│   └── lib/
│       ├── main.dart                     # 진입점 및 Stage SegmentedButton AppBar
│       └── bridge/
│           ├── stage_a_bridge.dart       # 채널 등록 및 SnackBar 표시
│           ├── stage_b_bridge.dart       # Stage A + runJavaScript CustomEvent 카운터
│           └── stage_c_bridge.dart       # Stage B + Call id 매칭 및 getDeviceInfo
└── web/                                  # Next.js Web 프로젝트
    ├── package.json                      # "dev": "next dev -H 0.0.0.0"
    └── src/
        ├── app/
        │   ├── layout.tsx                # 상단 Stage 네비게이션 탭 바
        │   ├── page.tsx                  # /stage-a 리다이렉트
        │   ├── stage-a/page.tsx          # Stage A UI (텍스트 입력 및 전송)
        │   ├── stage-b/page.tsx          # Stage B UI (카운터 수신 및 증감 표시)
        │   └── stage-c/page.tsx          # Stage C UI (기기 정보 호출 및 결과 표시)
        └── lib/bridge/
            ├── stageA.ts                 # postMessage 전송 함수
            ├── stageB.ts                 # CustomEvent 리스너 훅
            └── stageC.ts                 # callHost Promise RPC 함수
```

---

## 4. 통신 규약 (Bridge Contract)

### 4.1 기본 인터페이스
- **JavaScript 채널**: `FlutterBridge` (`window.FlutterBridge.postMessage(string)`)
- **Host → Web Event 통로**: `window.dispatchEvent(new CustomEvent('flutter:event', { detail: payload }))`
- **Host → Web Call 응답 통로**: `window.__onFlutterResponse(responseJson)`

### 4.2 Stage A: 단방향 메시지 (Web → Host)
- **요청 형태**:
  ```json
  {
    "type": "showSnackBar",
    "text": "웹에서 입력한 텍스트"
  }
  ```
- **Host 동작**: 전달받은 `text`를 `ScaffoldMessenger.of(context).showSnackBar`로 화면 하단에 표시.

### 4.3 Stage B: 양방향 이벤트 (Host → Web)
- Stage A 기능 완전 유지.
- **Host 발송 동작**: Flutter AppBar의 카운터 버튼 클릭 시 현재 카운트 값을 Web에 발송:
  ```dart
  controller.runJavaScript(
    'window.dispatchEvent(new CustomEvent("flutter:event", { detail: ${jsonEncode({"type": "incrementCounter", "count": counter})} }));'
  );
  ```
- **Web 수신 동작**:
  `useEffect`에서 `flutter:event` 이벤트 리스너를 등록하고, 수신된 `count` 값을 React 상태에 반영하여 화면에 갱신. 언마운트 시 리스너 제거.

### 4.4 Stage C: 호출 및 응답 (Web ↔ Host RPC)
- Stage B 기능 완전 유지.
- **Web 호출 함수 (`callHost`)**:
  ```typescript
  const pendingCalls = new Map<string, { resolve: Function; reject: Function }>();

  window.__onFlutterResponse = (response) => {
    const handler = pendingCalls.get(response.id);
    if (!handler) return;
    pendingCalls.delete(response.id);
    if (response.error) handler.reject(new Error(response.error));
    else handler.resolve(response.result);
  };

  export function callHost<T>(method: string, params: any = {}): Promise<T> {
    return new Promise((resolve, reject) => {
      const id = Math.random().toString(36).substring(2, 9);
      pendingCalls.set(id, { resolve, reject });
      window.FlutterBridge.postMessage(JSON.stringify({ id, method, params }));
    });
  }
  ```
- **요청 메시지 형태**:
  ```json
  {
    "id": "c1a2b3",
    "method": "getDeviceInfo",
    "params": {}
  }
  ```
- **성공 응답 형태**:
  ```json
  {
    "id": "c1a2b3",
    "result": {
      "platform": "ios",
      "version": "Version 18.0 (Build 22A3354)"
    }
  }
  ```
- **실패 응답 형태 (알 수 없는 method 호출 시)**:
  ```json
  {
    "id": "c1a2b3",
    "error": "Unknown method: invalidMethod"
  }
  ```
- **Host 정보 획득**: `dart:io` 내장 `Platform.operatingSystem` 및 `Platform.operatingSystemVersion` 사용.

### 4.5 Host 감지 및 브라우저 보호
- Web 컴포넌트 마운트 시 `typeof window !== 'undefined' && 'FlutterBridge' in window`로 감지.
- Host 외부(일반 브라우저 접속)인 경우 상단에 `⚠️ Host 외부에서 실행 중 (브릿지 비활성화)` 안내 뱃지를 띄우고 액션 버튼을 비활성화(`disabled`).

---

## 5. 플랫폼 및 개발 환경 설정

### 5.1 Next.js (`web/`)
- 바인딩 호스트: `next dev -H 0.0.0.0` (Android 에뮬레이터 접근 지원).
- 포트: 기본 `3000`.

### 5.2 Android Host (`app/`)
- 접속 URL: `http://10.0.2.2:3000`
- `android/app/src/main/AndroidManifest.xml`:
  ```xml
  <application
      ...
      android:usesCleartextTraffic="true">
  ```

### 5.3 iOS Host (`app/`)
- 접속 URL: `http://localhost:3000`
- `ios/Runner/Info.plist`:
  ```xml
  <key>NSAppTransportSecurity</key>
  <dict>
      <key>NSAllowsLocalNetworking</key>
      <true/>
  </dict>
  ```

### 5.4 Flutter URL 분기 로직
```dart
final String baseUrl = Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';
```

---

## 6. 데모 검증 체크리스트

1. **Stage A 검증**:
   - Web에서 텍스트 입력 후 [전송] 클릭 시 Flutter 화면 하단에 SnackBar 표시 확인.
2. **Stage B 검증**:
   - Flutter 상단 AppBar의 [+] 버튼 클릭 시 Web 화면의 카운터 숫자가 실시간 증가 확인.
   - Stage A의 SnackBar 전송도 정상 동작 유지 확인.
3. **Stage C 검증**:
   - Web의 [기기 정보 요청] 클릭 시 `플랫폼: ...`, `OS 버전: ...` 결과가 화면에 렌더링되는지 확인.
   - Web의 [에러 테스트] 클릭 시 `오류: Unknown method` 예외 처리 노출 확인.
4. **브라우저 단독 열람 검증**:
   - 데스크톱 브라우저에서 `http://localhost:3000` 접속 시 "Host 외부" 뱃지 노출 및 버튼 비활성화 확인.

---

## 7. 다음 단계 및 구현 위임

본 스펙은 `/to-spec` 단계를 통해 확정되었으며, 다음 단계는 `/implement-spec docs/spec.md`를 실행하여 실제 코드를 단계별 선형 커밋으로 작성하는 것입니다.
