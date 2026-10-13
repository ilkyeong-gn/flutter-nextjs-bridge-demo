# Map: Flutter + Next.js 브릿지 데모

Label: wayfinder:map

## Destination

Stage A(단방향) → B(양방향) → C(호출)를 순서대로 보여주는 Flutter(Host) + Next.js(Web) 브릿지 데모의 **구현에 바로 넘길 수 있는 스펙** (`.scratch/bridge-demo/spec.md`). 모든 결정이 닫히면 `/to-spec`으로 조립해 `/implement-spec`에 넘긴다.

## Notes

- 도메인: 하이브리드 앱 WebView 브릿지. 용어는 [GLOSSARY.md](../../GLOSSARY.md)를 따른다 (Host, Web, Bridge, Message, Event, Call, Stage).
- 기본 스킬: grilling + domain-modeling. 연구는 research.
- 차트 시 확정한 전제 (모든 세션의 기준):
  - 목적지는 스펙. 지도 안에서 구현하지 않는다.
  - 플랫폼: iOS 시뮬레이터 + Android 에뮬레이터. Flutter Web/데스크톱 제외.
  - 저장소: 단일 모노레포, `app/`(Flutter) + `web/`(Next.js).
  - WebView: 공식 `webview_flutter`. 메커니즘 가시성을 코드 최소화보다 우선한다 (Stage C의 Promise 대응도 id 매칭으로 직접 구현).
  - Web 제공: 개발 머신의 `next dev` (iOS `localhost:3000`, Android `10.0.2.2:3000`).
  - Host 밖(일반 브라우저)에서는 "Host 밖" 상태 표시 + 브릿지 버튼 비활성화만.
  - 예시 동작: A = Web 버튼 → Host SnackBar(입력 텍스트) / B = + Host AppBar 버튼 → Web 카운터 증가(Event) / C = + Web → Host 기기 정보 Call(플랫폼, OS 버전).
  - Stage C 실패 처리: 알 수 없는 메서드 → reject 한 경로만.
  - 메시지 규약: JSON(`{type, payload}`, Call은 `{id, method, params}`)을 Dart/TS 양쪽에 손으로 정의.
  - 문서·주석 한국어, 식별자 영어.
- 트래커: 로컬 마크다운. 티켓은 `issues/NN-*.md`, `Type:`/`Status:`/`Blocked by:` 줄 사용.

## Decisions so far

- [Stage 구성 방식의 트레이드오프 조사](issues/01-research-stage-structure.md): 단일 앱 쌍(`app/`, `web/`) 내 단계별 모듈 분리 + 탭/라우트 실시간 전환 구조에 선형 Git 커밋 히스토리를 결합하는 방식을 추천.
- [webview_flutter와 Next.js로 Stage A/B/C를 구현하는 메커니즘 조사](issues/02-research-bridge-mechanism.md): webview_flutter 4.14.1의 `addJavaScriptChannel`/`runJavaScript`와 Web의 id 매칭 Promise 패턴, Next.js App Router `'use client'` + `CustomEvent`, Android/iOS 로컬 네트워크 설정 사실 확인.

## Not yet specified

- **디렉터리 레이아웃과 실행 방법**: `app/`, `web/` 내부 구조, 단계 전환 방법, 실행 명령. Stage 구성 방식과 플랫폼 설정 사실에 달려 있음.
- **단계 간 차이를 읽히게 하는 방법**: 독자가 A→B→C에서 "무엇이 추가됐는지"를 어떻게 보게 할지 (diff, 주석, README 표 등). Stage 구성 방식에 달려 있음.
- **데모 검증 방법**: 수동 체크리스트로 충분한지, 자동화가 필요한지.

## Out of scope

- 타임아웃·재시도·취소 등 Call의 고급 실패 처리: "가장 간단한 형식" 범위 밖.
- 메시지 규약 코드 생성·공유 패키지: 손으로 정의하기로 함.
- 일반 브라우저용 대체 동작(fallback/mock Host).
- 정적 빌드 번들링, 배포(Vercel 등), 스토어 빌드.
- Flutter Web·데스크톱 플랫폼.
