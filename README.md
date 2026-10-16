# Flutter + Next.js WebView Bridge Demo

Flutter(Host) 앱이 Next.js(Web) 페이지를 WebView로 임베드하고, 둘 사이의 통신(Bridge) 메커니즘을 단계별(**Stage A → Stage B → Stage C**)로 검증하고 시연하는 하이브리드 앱 모노레포 프로젝트입니다.

---

## 📌 프로젝트 진행 현황

| 단계 | 목표 및 기능 | 상태 | 연관 Issue |
| :--- | :--- | :---: | :--- |
| **인프라** | 모노레포 환경 구축 및 WebView 기본 연결 | **완료 (Merged)** | [#7](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/7) |
| **Stage A** | Web → Host 단방향 Message (SnackBar 표시) | **완료** | [#8](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/8) |
| **Stage B** | Host → Web 양방향 Event (CustomEvent 카운터 동기화) | **완료** | [#9](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/9) |
| **Stage C** | Web ↔ Host 양방향 Call (Promise 기반 RPC 기기 정보 조회) | **완료** | [#10](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/10) |

---

## 🏛️ 핵심 개념 및 Stage 로드맵

데모는 브릿지의 복잡도를 점진적으로 높여가는 3단계 구조로 설계되었습니다:

```
[ Stage A: 단방향 Message ]
Web  ---(window.FlutterBridge.postMessage)--->  Host (SnackBar 표시)

[ Stage B: 양방향 Event ]
Host ---(runJavaScript: CustomEvent)-------->  Web (React State 카운터 동기화)
Web  ---(Stage A 메시지 유지)--------------->  Host

[ Stage C: 양방향 Call (RPC) ]
Web  ---(callHost Promise 요청)------------->  Host (기기 정보 조회)
Host ---(window.__onFlutterResponse)--------->  Web (Promise Resolve/Reject)
```

1. **Stage A — 단방향**: Web에서 텍스트를 입력하고 전송하면, Host가 수신하여 화면 하단에 `SnackBar`를 띄웁니다.
2. **Stage B — 양방향 (이벤트)**: Stage A 기능을 유지하며, Host AppBar의 카운터 버튼을 누를 때마다 Web에 브로드캐스트 이벤트를 전달하여 Web의 숫자가 실시간으로 갱신됩니다.
3. **Stage C — 양방향 (호출/RPC)**: Web에서 `callHost<DeviceInfo>('getDeviceInfo')` 형태의 Promise 함수를 호출하면, Host가 네이티브 기기/OS 정보를 반환하거나 에러를 반환하는 요청-응답(RPC)을 처리합니다.
4. **브라우저 보호 모드**: 일반 웹 브라우저 단독 접속 시 `window.FlutterBridge` 유무를 실시간 감지하여 상단에 `⚠️ Host 외부에서 실행 중 (브릿지 비활성화)` 배지를 띄우고 브릿지 호출 버튼을 안전하게 비활성화합니다.

---

## 📖 도메인 용어 (GLOSSARY)

본 프로젝트는 일관된 설계 및 커뮤니케이션을 위해 정의된 표준 용어를 준수합니다:

| 용어 | 정의 | 피해야 할 표현 |
| :--- | :--- | :--- |
| **Host (호스트)** | WebView를 띄우는 Flutter 앱 | 네이티브, 앱, 셸, 컨테이너 |
| **Web (웹)** | Host의 WebView 안에서 실행되는 Next.js 페이지 | 프론트, 웹뷰, 클라이언트 |
| **Bridge (브릿지)** | Host와 Web 사이의 메시지 통로와 그 통신 규약 | 채널, 인터페이스 |
| **Message (메시지)** | Bridge를 한 방향으로 건너는 응답 없는 단위 데이터 | 패킷, 신호 |
| **Event (이벤트)** | Host가 Web에 비동기로 전달하는 Message | 푸시, 알림 |
| **Call (호출)** | Web이 Host에 보내고 응답을 기다리는 단위 작업 | 요청, RPC, invoke |
| **Stage (단계)** | 데모가 보여주는 브릿지 능력의 수준 (A / B / C) | 레벨, 버전, 예제 |

자세한 내용은 [GLOSSARY.md](GLOSSARY.md)를 참고하세요.

---

## 📂 프로젝트 구조

```
.
├── GLOSSARY.md                                # 프로젝트 표준 도메인 용어집
├── AGENTS.md                                  # 에이전트 작업 지침
├── docs/
│   ├── spec.md                                # 최종 확정된 브릿지 데모 구현 스펙
│   └── agents/                                # 거버넌스 및 이슈 트래커 문서
├── app/                                       # Host: Flutter 프로젝트
│   ├── lib/
│   │   ├── bridge/
│   │   │   ├── stage_a_bridge.dart                # Stage A: FlutterBridge 채널 등록 및 SnackBar 표시
│   │   │   ├── stage_b_bridge.dart                # Stage B: runJavaScript CustomEvent 카운터 발송
│   │   │   └── stage_c_bridge.dart                # Stage C: Web ↔ Host 양방향 RPC 응답 및 기기 정보 반환
│   │   ├── config.dart                        # 플랫폼별(Android/iOS) WebView Base URL 분기
│   │   └── main.dart                          # 진입점 및 Stage SegmentedButton 네비게이션
│   ├── android/app/src/main/AndroidManifest.xml # usesCleartextTraffic 설정
│   ├── ios/Runner/Info.plist                  # NSAllowsLocalNetworking 설정
│   └── test/                                  # Flutter 위젯 및 URL 단위 테스트
└── web/                                       # Web: Next.js (App Router, Tailwind CSS)
    ├── src/app/
    │   ├── layout.tsx                         # 글로벌 레이아웃 및 Stage 네비게이션 바
    │   ├── page.tsx                           # /stage-a 리다이렉트 진입점
    │   ├── stage-a/page.tsx                   # Stage A 화면 (텍스트 입력 및 전송)
    │   ├── stage-b/page.tsx                   # Stage B 화면 (실시간 카운터 수신 및 SnackBar 전송)
    │   └── stage-c/page.tsx                   # Stage C 화면 (기기 정보 호출 및 에러 테스트)
    ├── src/components/                        # HostBadge, StageNav 등 공통 UI 컴포넌트
    ├── src/lib/bridge/
    │   ├── detection.ts                       # 브릿지 감지(useFlutterBridge)
    │   ├── stageA.ts                          # Stage A: sendSnackBarMessage 클라이언트
    │   ├── stageB.ts                          # Stage B: useFlutterCounter 커스텀 훅
    │   └── stageC.ts                          # Stage C: callHost Promise RPC 함수
    └── package.json                           # Next.js 15+, React 19, Vitest
```

---

## 🚀 로컬 개발 및 실행 방법

### 1. 사전 요구사항
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.13.5+
- [Node.js](https://nodejs.org/) v20+ 및 [pnpm](https://pnpm.io/) 10+
- iOS Simulator (macOS) 또는 Android Emulator
  - 📖 **초보자를 위한 가상 기기 환경 구성 안내**: [docs/environment-setup.md](docs/environment-setup.md)에서 iOS/Android 파트별 상세 설정을 확인하실 수 있습니다.

---

### 2. Web 개발 서버 실행

Android 에뮬레이터(`10.0.2.2`) 및 로컬 기기 접속을 지원하기 위해 `0.0.0.0` 호스트로 바인딩됩니다:

```bash
cd web
pnpm install
pnpm dev
```
> 기본 로컬 접속 주소: `http://localhost:3000`

---

### 3. Host (Flutter) 실행

새 터미널 창을 열고 대상 시뮬레이터/에뮬레이터로 앱을 실행합니다:

```bash
cd app
flutter pub get
flutter run
```

#### 플랫폼별 WebView 접속 URL
- **iOS 시뮬레이터**: `http://localhost:3000`
- **Android 에뮬레이터**: `http://10.0.2.2:3000`
- Flutter 앱의 `app/lib/config.dart`에서 플랫폼(`Platform.isAndroid`)을 감지하여 자동으로 올바른 주소로 연결합니다.

---

## 🧪 테스트 및 정적 분석

### Web 테스트
```bash
cd web

# Vitest 컴포넌트 및 브릿지 감지 테스트 실행
pnpm test

# TypeScript 타입 검사
pnpm typecheck

# ESLint 린트 검사
pnpm lint
```

### Host 테스트
```bash
cd app

# Flutter 위젯 및 URL 단위 테스트 실행
flutter test
```

---

## 📚 관련 문서 및 사양
- 초보자를 위한 로컬 환경 구성 가이드 (iOS/Android): [docs/environment-setup.md](docs/environment-setup.md)
- 전체 기능 요구사항 및 세부 통신 규약: [docs/spec.md](docs/spec.md)
- 도메인 용어 정의: [GLOSSARY.md](GLOSSARY.md)
- 작업 트래킹: [GitHub Issues (#1 ~ #10)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues)
