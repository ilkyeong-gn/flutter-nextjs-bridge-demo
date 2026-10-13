# Stage 구성 방식의 트레이드오프 조사

Type: research
Status: open
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
