# Stage 구성 방식의 트레이드오프 조사

Type: research
Status: resolved
Blocked by:
Map: [Flutter + Next.js 브릿지 데모](../map.md)
Findings: 브랜치 `research/stage-structure`, 파일 `research/stage-structure.md`

## Question

Stage A → B → C를 한 저장소에서 보여주는 방식으로 무엇이 적절한가? 아래 후보를 비교하고 트레이드오프를 정리한다.

- git 브랜치 또는 태그/커밋 단위로 단계 구분 (`stage-a` → `stage-b` → `stage-c`)
- git worktree로 단계별 디렉터리를 동시에 체크아웃
- 단계마다 독립된 앱 3쌍 (`stage-a/app`, `stage-a/web`, …)
- 한 쌍의 앱 안에서 단계 전환 (라우트, 탭, 플래그)
- 그 밖에 조사 중 발견한 방식

비교 기준: 독자가 단계 간 차이를 얼마나 쉽게 보는가, 실행이 얼마나 간단한가(빌드·의존성 중복, 동시 실행), 유지보수 비용(공통 코드 수정 시 전파), 데모 맥락(발표, 저장소 열람, 학습용)에서의 적합성. 근거가 되는 1차 자료나 잘 알려진 예시 저장소가 있으면 인용한다. 추천안을 하나 제시하되 결정은 [Stage 구성 방식 결정](03-decide-stage-structure.md)에서 사용자가 내린다.

## Answer

- **추천안**: **단일 앱 쌍(`app/`, `web/`) 내 단계별 모듈 분리 및 탭/라우트 전환 + 3단계 선형 Git 커밋 히스토리 결합**
- **주요 트레이드오프 요약**:
  - **Git 브랜치/Worktree**: 코드 자체는 깔끔하나 `git checkout` 시 Flutter/Gradle 재빌드로 인해 실시간 시연 및 비교가 끊기며, Worktree는 외부 독자나 GitHub 웹에서 보이지 않고 디스크/빌드 캐시가 중복됨.
  - **독립 앱 3쌍**: 3개의 Flutter + Next.js 프로젝트로 인해 프로젝트 셋업 보일러플레이트가 과도하게 중복되고 빌드 및 유지보수 비용이 3배로 증가함.
  - **단일 앱 내 탭/라우트 분리**: `pnpm dev` 1회, `flutter run` 1회로 한 번만 실행하면 화면 내에서 탭 클릭으로 A/B/C를 실시간 비교 시연할 수 있어 데모 UX/DX가 최상임. 단계별 브릿지 파일(`stage_a`, `stage_b`, `stage_c`)을 나란히 배치하여 코드 차이 가시성도 확보 가능함.
- **상세 보고서 위치**: 브랜치 `research/stage-structure`, 파일 `research/stage-structure.md`
