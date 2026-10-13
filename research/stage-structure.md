# Stage 구성 방식의 트레이드오프 조사 (Findings)

- **티켓**: [01-research-stage-structure.md](../../.scratch/bridge-demo/issues/01-research-stage-structure.md)
- **작성일**: 2026-10-13
- **목적**: Flutter + Next.js 하이브리드 앱 브릿지 데모에서 Stage A(단방향) → B(양방향) → C(호출/Promise)를 표현하는 저장소 및 코드 구조의 적정성을 비교 분석하고 최적의 방식을 제안한다.

---

## 1. 비교 후보

다음 네 가지 주요 접근 방식을 비교 대상으로 검토하였다.

1. **방식 1: Git 브랜치 / 태그 / 선형 커밋 분리** (`stage-a` → `stage-b` → `stage-c`)
2. **방식 2: Git Worktree 분리** (`.worktrees/stage-a`, `stage-b`, `stage-c`)
3. **방식 3: 물리적 독립 프로젝트 3쌍** (`stages/stage-a/{app,web}`, `stages/stage-b/...`)
4. **방식 4: 단일 앱 쌍 내 탭/라우트 분리** (`app/`, `web/` 단일 프로젝트에서 라우트/탭으로 전환)

---

## 2. 세부 트레이드오프 분석

| 비교 기준 | 1. Git 브랜치/태그 | 2. Git Worktree | 3. 독립 프로젝트 3쌍 | 4. 단일 앱 내 탭/라우트 (추천) |
| :--- | :--- | :--- | :--- | :--- |
| **코드 순수성 (Diff 가시성)** | **최상** (불필요한 전환 로직 없음, `git diff`로 증분 확인) | **최상** (브랜치 방식과 동일한 순수성) | **중** (폴더 간 비교 툴 필요, 중복 보일러플레이트 많음) | **상** (단계별 브릿지 파일/화면을 나란히 배치해 IDE에서 즉시 비교 가능) |
| **실행 및 시연 편의성 (DX)** | **하** (`git checkout` 시 앱 재빌드, 핫 리로드 단절) | **중** (각 디렉터리별 빌드/포트 분리 필요, 동시 실행 시 리소스 소모) | **하** (3개 프로젝트 각각 `pnpm dev`, `flutter run` 수행, 포트 충돌 관리) | **최상** (`pnpm dev` 1개, `flutter run` 1개로 실행 후 UI에서 탭 전환 즉시 테스트) |
| **의존성 및 디스크 비용** | **상** (공통 의존성 사용하나 브랜치 전환 시 캐시 무효화 가능) | **하** (각 worktree마다 `node_modules`, `build/` 수백 MB~GB 중복) | **최하** (3개 앱 x 2개 프레임워크 = 6개 프로젝트 디렉터리 빌드 캐시 누적) | **최상** (단일 의존성 트리, 1회 빌드 아티팩트만 유지) |
| **유지보수 비용 (공통 설정 변경)** | **하** (Android 권한, Next 설정 변경 시 브랜치마다 cherry-pick/rebase) | **하** (브랜치 방식과 동일하게 수동 반영 필요) | **하** (공통 설정 수정 시 3개 폴더에 복사/붙여넣기) | **최상** (단일 `AndroidManifest.xml`, `Info.plist`, `next.config.ts` 유지) |
| **웹(GitHub) 열람 편의성** | **중** (브랜치 셀렉터를 바꿔가며 봐야 함) | **하** (Worktree는 로컬 설정이므로 GitHub UI에 노출 안 됨) | **상** (폴더 트리에서 모든 코드가 한눈에 보임) | **최상** (단일 트리에서 `stages/` 또는 `bridge/` 폴더 내 `a.dart`, `b.dart`, `c.dart` 나란히 열람) |

---

## 3. 심층 평가

### 방식 1: Git 브랜치 / 태그 분리
- **장점**: 각 단계의 코드가 해당 단계에 필요한 최소한의 코드만 담고 있어 코드 자체의 군더더기가 없다.
- **치명적 단점**:
  - Flutter 앱 특성상 브랜치를 바꾸면 Gradle 캐시 또는 Pods 구성이 재검증되거나 프로세스가 재시작되어 데모 시연 흐름이 끊어진다.
  - "이 버튼을 누르면 A에서는 안 되는데 C에서는 어떻게 동작하는가?"를 실시간으로 비교하기가 매우 불편하다.
  - 공통 플랫폼 설정(예: Android 에뮬레이터 HTTP 통신 허용 설정)에 버그가 발견되면 A, B, C 세 브랜치에 모두 rebase/cherry-pick을 반복해야 한다.

### 방식 2: Git Worktree 분리
- **장점**: 로컬 개발 환경에서 터미널을 여러 개 띄워 단계별로 분리 보관할 수 있다.
- **치명적 단점**:
  - Worktree는 개발자의 로컬 Git 메커니즘일 뿐이므로, 저장소를 방문하는 외부 독자나 클론한 사용자에게는 아무런 가치를 제공하지 못한다.
  - 각 워크트리마다 `node_modules`와 Flutter 빌드 아티팩트가 중복 생성되어 디스크 낭비가 심하다.

### 방식 3: 물리적 독립 프로젝트 3쌍 (`stages/stage-a/...`)
- **장점**: GitHub 웹 인터페이스에서 각 단계의 코드를 폴더별로 즉시 찾아볼 수 있다.
- **치명적 단점**:
  - `flutter create` 및 `create-next-app`을 3번 수행하므로 프로젝트 셋업 보일러플레이트(설정 파일, 아이콘, 폰트, 테마 등)가 전체 코드의 90% 이상을 차지하여 정작 중요한 "Bridge 핵심 코드"가 묻힌다.
  - 디스크 공간과 빌드 시간이 3배로 증가한다.

### 방식 4: 단일 앱 내 단계별 모듈 분리 + UI 탭 전환 (추천)
- **구조**:
  - Next.js Web: URL 경로 `/stage-a`, `/stage-b`, `/stage-c` (또는 메인 화면 상단 Tab).
  - Flutter Host: 상단 TabBar 또는 SegmentedControl로 Stage A / Stage B / Stage C WebView 화면 전환 (또는 URL 동적 로드).
  - 코드 구조:
    - `web/lib/bridge/`: `stageA.ts`, `stageB.ts`, `stageC.ts`
    - `app/lib/bridge/`: `stage_a_bridge.dart`, `stage_b_bridge.dart`, `stage_c_bridge.dart`
- **장점**:
  1. **최고의 시연 경험 (Interactive Demo)**: Next.js와 Flutter를 한 번만 실행(`pnpm dev`, `flutter run`)해 두면, 화면에서 탭을 누르는 것만으로 단방향/양방향/Call의 차이를 1초 만에 직접 확인 가능.
  2. **높은 코드 가독성**: IDE에서 `stage_a`와 `stage_b`, `stage_c` 파일을 나란히 열어두고 "무엇이 추가되었는가"를 한눈에 비교 가능.
  3. **유지보수 단일화**: 플랫폼 설정(Android cleartext traffic, iOS ATS, Next.js hydration)을 단 한 번만 구성.

---

## 4. 추천안 (Recommendation)

> **추천: 방식 4 (단일 앱 쌍 내 단계별 모듈화 및 탭/라우트 전환) + 선형 Git 커밋 기록 결합**

- **기본 구조**: 단일 모노레포(`app/`, `web/`)에서 Stage A, B, C를 단계별 파일(`stage_a_*`, `stage_b_*`, `stage_c_*`) 및 라우트로 분리하여 단 한 번의 실행으로 모든 단계를 시연할 수 있도록 구성한다.
- **보완책 (Git Diff 지원)**: 구현 커밋을 작성할 때 `feat: Stage A 기본 단방향 브릿지` → `feat: Stage B 양방향 이벤트 추가` → `feat: Stage C Promise Call 및 에러 처리 추가`의 3단계 선형 커밋으로 기록한다. 이렇게 하면 **실행 시에는 탭으로 즉시 비교**할 수 있고, **Git 기록 상으로는 `git diff`를 통해 순수 증분**을 완벽하게 확인할 수 있어 두 방식의 장점을 모두 취할 수 있다.

---

## 5. 출처 및 참고 자료

1. [Git 공식 문서 - git-worktree](https://git-scm.com/docs/git-worktree): "A git repository can support multiple working trees... each linked working tree has its own index and working tree."
2. [Flutter 공식 샘플 저장소 아키텍처 (flutter/samples)](https://github.com/flutter/samples): 여러 예제를 제공할 때 다중 프로젝트 분리 vs 단일 앱 내 네비게이션 패턴 비교.
3. [Next.js App Router 공식 문서 - Parallel Routes & Sub-navigation](https://nextjs.org/docs/app/building-your-application/routing): 단일 애플리케이션 내에서의 단계별 격리 뷰 구성.
