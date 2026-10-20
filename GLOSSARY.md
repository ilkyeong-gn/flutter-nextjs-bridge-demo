# Flutter WebView Bridge

Flutter 앱이 Next.js 페이지를 WebView로 띄우고, 둘이 Bridge로 대화하는 하이브리드 앱의 언어. Bridge 능력을 단계별로 보여주는 Demo와, 실제 앱을 만들 때 참고하는 Reference App을 함께 다룬다.

## Language

### 결과물

**Demo (데모)**:
Stage를 따라 Bridge 능력을 한 단계씩 보여주는 학습용 구현.
_Avoid_: 예제, 샘플

**Reference App (레퍼런스 앱)**:
실제 하이브리드 앱을 만들 때 구조와 패턴을 그대로 가져다 쓰도록 만든 참고 구현. 실제로 배포·운영하는 제품은 아니다.
_Avoid_: 실전 예시, 템플릿, 보일러플레이트, 샘플 앱, PoC

### 참여자

**Host (호스트)**:
WebView를 띄우는 Flutter 앱.
_Avoid_: 네이티브, 앱, 셸, 컨테이너

**Web (웹)**:
Host의 WebView 안에서 실행되는 Next.js 페이지.
_Avoid_: 프론트, 웹뷰(컴포넌트와 혼동), 클라이언트

**Bridge (브릿지)**:
Host와 Web 사이의 메시지 통로와 그 통신 규약.
_Avoid_: 채널, 인터페이스

### 화면과 기능

**Host Screen (Host 화면)**:
Host가 Flutter로 직접 그리는 화면.
_Avoid_: 네이티브 화면

**Web Screen (Web 화면)**:
Host의 WebView 안에 Web을 띄운 화면.
_Avoid_: 웹뷰 화면

**Third-party Content (서드파티 콘텐츠)**:
Web 화면 안에 들어 있지만 Web이 아닌 출처에서 온 프레임이나 스크립트.
_Avoid_: 외부 콘텐츠, 써드파티

**Allowed Origin (허용 출처)**:
Bridge가 열리고 Web 화면의 메인 프레임이 머물 수 있는 Web의 출처.
_Avoid_: 화이트리스트, 신뢰 도메인

**Route Table (경로 표)**:
앱 안에서 열 수 있는 Web 화면 경로의 목록. 경로마다 딥링크와 콘텐츠 속 링크로 열 수 있는지, 어느 WebView에서 열 수 있는지가 표시된다. 모든 환경에서 같다.
_Avoid_: 라우트 목록, URL 허용 목록

**Host Capability (Host 기능)**:
Host가 Bridge를 통해 Web에 빌려주는 기기·앱 기능(카메라, 사진 선택, 공유 등).
_Avoid_: 네이티브 기능, 플러그인

### 멤버십

**Membership (멤버십)**:
팬이 가입해서 멤버 전용 글을 볼 수 있는 상태. 서버가 정한다.
_Avoid_: 구독, 유료 회원, 등급

**Member-only Post (멤버 전용 글)**:
멤버십이 있어야 본문과 사진을 볼 수 있는 글.
_Avoid_: 유료 글, 비공개 글, 잠긴 글(상태가 아니라 글의 종류를 가리킬 때)

### 진입

**Deep Link (딥링크)**:
앱 밖에서 앱의 특정 Web 화면을 여는 주소. 공유 링크와 커스텀 스킴 링크를 함께 가리킨다.
_Avoid_: 앱 링크, 유니버설 링크

**Share Link (공유 링크)**:
https 형식의 딥링크. 앱이 없으면 브라우저에서 앱 열기·설치 안내가 열린다.
_Avoid_: 공유 URL, 초대 링크

**Entry (진입)**:
딥링크나 알림으로 Host가 특정 Web 화면을 열라는 요청을 받는 일. Web 화면이 준비될 때까지 Host가 보관한다.
_Avoid_: 랜딩, 인입

### 메시지

**Message (메시지)**:
Bridge를 한 방향으로 건너는 응답 없는 단위 데이터.
_Avoid_: 패킷, 신호

**Event (이벤트)**:
Host가 Web에 보내는 Message.
_Avoid_: 푸시, 알림

**State Event (상태 Event)**:
최신 값만 의미가 있는 Event. 멤버십, 세션, 안 읽은 수처럼 지금의 상태를 알린다.
_Avoid_: sticky 이벤트

**One-off Event (일회 Event)**:
일어난 사건을 한 번만 전하는 Event. 딥링크 이동처럼 빠뜨리거나 두 번 전하면 안 된다.
_Avoid_: 알림 이벤트

**Call (호출)**:
Web이 Host에 보내고 응답을 기다리는 요청과 그 응답의 한 쌍. Host가 Web에 묻는 Call은 없다.
_Avoid_: 요청, RPC, invoke

**Handshake (핸드셰이크)**:
Web이 문서를 불러올 때마다 가장 먼저 보내는 Call. Web이 준비됐음을 알리고, Host가 지원하는 계약 버전과 기능 목록을 받는다.
_Avoid_: 초기화, init, ready

**Bridge Unavailable (Bridge 없음)**:
Web이 핸드셰이크를 마치지 못했거나 Host의 계약 major를 지원하지 않아서, 이 문서에서는 Host와 대화하지 않기로 한 상태. 문서를 다시 불러올 때까지 바뀌지 않는다.
_Avoid_: 오프라인, 연결 끊김, 브라우저 모드

**Bridge Contract (Bridge 계약)**:
Bridge로 오가는 Call·Message·Event의 이름과 모양, 그리고 그 버전(major.minor)의 정의. 한 원천에만 적는다.
_Avoid_: 프로토콜, 스펙, 인터페이스, 스키마

**Capability List (기능 목록)**:
핸드셰이크에서 Host가 알려 주는, 지금 이 Host에서 쓸 수 있는 Call·Message·Event 이름의 목록. Web은 기능마다 이 목록을 보고 분기한다.
_Avoid_: 기능 플래그, capabilities

### 버전

**Version Skew (버전 어긋남)**:
배포된 Web이 기대하는 Bridge 계약과 설치된 Host가 지원하는 Bridge 계약이 다른 상태. Web은 Host 출시와 따로 배포되므로 대개 새 Web이 옛 Host 위에서 돈다.
_Avoid_: 버전 불일치, 호환성 문제

**Minimum Host Version (최소 Host 버전)**:
Web이 동작을 보장하는 가장 낮은 Host 앱 버전. 이보다 낮은 Host는 업데이트 안내만 보이고 Web 화면을 열지 않는다.
_Avoid_: 강제 업데이트 버전, 최소 지원 버전

### 로그인

**Login Session (로그인 세션)**:
사용자가 한 번 로그인해서 서버에 생긴 세션. Host와 Web이 모두 여기에 묶이고, 이 세션이 끝나면 둘 다 비로그인이 된다.
_Avoid_: 세션(단독), 토큰

**Web Session (Web 세션)**:
로그인 세션에 묶여 WebView의 요청을 인증하는 자격. 쿠키일 수도, 토큰일 수도 있다.
_Avoid_: 웹 쿠키, 웹 토큰

**Session Handoff (핸드오프)**:
Host가 가진 로그인 세션으로 Web 세션을 만드는 일. 화면 밖 WebView로 서버에 코드를 내는 것, 쿠키를 심는 것, Bridge로 토큰을 넘기는 것은 모두 핸드오프의 방식이고, 어느 방식을 쓸지는 정하지 않았다.

### 글쓰기

**Attachment (첨부)**:
글쓰기 중에 사용자가 고른 사진·영상. 올리기 전까지는 Host가 가지고 있고, Web은 그 id와 썸네일만 안다.
_Avoid_: 파일, 업로드 항목

**Media (미디어)**:
서버에 올라가서 글에 붙일 수 있게 된 사진·영상. 첨부를 올리면 미디어가 된다.
_Avoid_: 에셋, 첨부(올린 뒤를 가리킬 때)

### 개발과 테스트

**Fake Host (가짜 Host)**:
Host 없이 Web을 돌리려고 Host 자리에 들어가, Bridge 계약대로 Message·Call·Event를 주고받는 대역.
_Avoid_: 목 브릿지, 모의 앱, 스텁

**Fake Web (가짜 Web)**:
Web 없이 Host를 돌리려고 Web 자리에 들어가, Bridge 계약대로 Message·Call·Event를 주고받는 대역.
_Avoid_: 목 페이지, 테스트 페이지

**Fake API (가짜 API)**:
실제 백엔드 대신 Web과 같은 출처에서 돌며, 로그인 세션·글·미디어·멤버십·메시지를 실제처럼 다루는 서버. Host와 Web 모두 이것을 진짜 백엔드로 대한다.
_Avoid_: 목 서버, 스텁 API, 백엔드(가짜 API를 가리킬 때)

**Debug API (개발 전용 API)**:
가짜 API 가운데 개발과 테스트에서만 켜는 조작들. 상태를 시드로 되돌리거나, 세션을 끊거나, 시간이 지난 것처럼 만들거나, 업로드를 느리게 한다.
_Avoid_: 치트, 관리자 API

### 단계

**Stage (단계)**:
데모가 보여주는 Bridge 능력의 수준. 한 단계는 앞 단계를 포함한다.
_Avoid_: 레벨, 버전, 예제

- **Stage A — 단방향**: Web → Host Message만.
- **Stage B — 양방향**: Stage A + Host → Web Event.
- **Stage C — 호출**: Stage B + Web → Host Call.
