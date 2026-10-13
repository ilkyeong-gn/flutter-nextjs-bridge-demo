# Flutter WebView Bridge Demo

A Flutter 앱이 Next.js 페이지를 WebView로 띄우고, 둘이 브릿지로 대화하는 가장 단순한 형태를 단계별로 보여주는 데모.

## Language

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

### 메시지

**Message (메시지)**:
Bridge를 한 방향으로 건너는 응답 없는 단위 데이터.
_Avoid_: 패킷, 신호

**Event (이벤트)**:
Host가 Web에 보내는 Message.
_Avoid_: 푸시, 알림

**Call (호출)**:
Web이 Host에 보내고 응답을 기다리는 요청과 그 응답의 한 쌍.
_Avoid_: 요청, RPC, invoke

### 단계

**Stage (단계)**:
데모가 보여주는 Bridge 능력의 수준. 한 단계는 앞 단계를 포함한다.
_Avoid_: 레벨, 버전, 예제

- **Stage A — 단방향**: Web → Host Message만.
- **Stage B — 양방향**: Stage A + Host → Web Event.
- **Stage C — 호출**: Stage B + Web → Host Call.
