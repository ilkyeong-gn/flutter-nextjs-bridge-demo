# Host는 go_router 없이 Navigator로 화면을 쌓고, 뒤로가기는 탭 셸의 `PopScope` 하나에서 정한다

Host의 화면은 루트 `Navigator` 하나와, 탭 셸의 `IndexedStack` 안에 탭(커뮤니티 · 메시지 · 마이)마다 둔 `Navigator`로 쌓는다. go_router도 `Router`(Navigator 2.0)도 쓰지 않는다. go_router가 주는 핵심은 URL을 Host route로 바꾸는 일이다. 그런데 Host는 Web 경로를 다루지 않고, 딥링크는 진입 모듈이 받아 Web으로 넘긴다([ADR 0009](0009-entry-held-until-handshake.md)). 그래서 go_router로 얻을 것이 거의 없다. 반면 2026-10 기준 go_router 18.1.0에는 우리 구조, 곧 탭마다 Navigator, 루트 push, Android predictive back을 함께 쓰는 구조를 직접 건드리는 버그가 열려 있다.

- 비활성 branch까지 pop된다([flutter#188018](https://github.com/flutter/flutter/issues/188018)).
- 하위 route가 쌓인 branch를 떠나면 back이 먹통이 된다([flutter#193098](https://github.com/flutter/flutter/issues/193098)). go_router가 shell마다 넣는 `PopScope` 때문이다.
- pop과 같은 프레임에 branch를 바꾸면 pop된 route가 되살아난다([flutter#194801](https://github.com/flutter/flutter/issues/194801)).

뒤로가기는 탭 셸의 `PopScope` 하나가 받는다. 순서는 순수 함수 `BackRouter`가 정하고, 그 순서는 이렇다.

1. 루트에 쌓인 route: Host 화면이면 pop하고, Web 화면이면 그 Web 화면에 맡긴다.
2. 지금 탭의 Navigator가 pop할 수 있으면 pop한다.
3. 커뮤니티 탭이고 Web이 `nav.backState {handled: true}`를 알렸으면 `nav.back`을 보낸다.
4. 커뮤니티가 아닌 탭의 루트에서는 커뮤니티 탭으로 옮긴다.
5. 그 밖에는 시스템에 넘긴다.

`canPop`은 이 조건에서 동기적으로 계산되므로, predictive back을 켜 둬도 홈 미리보기는 5번 경우에만 나온다.

## Considered Options

- **go_router `StatefulShellRoute` + `parentNavigatorKey`**: 탭 상태 유지와 루트 push를 선언적으로 적을 수 있다. 하지만 위 버그에는 패치 없이 쓸 우회법이 없고, go_router가 넣는 `PopScope`가 Web에 맡기는 뒤로가기([ADR 0008](0008-web-owns-back-in-tab-webview.md))와 섞인다.
- **go_router를 쓰고 predictive back을 끈다**: #188018은 피하지만 #193098과 #194801은 남는다.
- **화면마다 `PopScope`**: 뒤로가기를 막는 곳이 여러 군데가 되어 순서를 한곳에서 볼 수 없다. 루트에 쌓인 Host 화면이 스스로 막아야 할 때(예: 업로드 중 확인)만 예외로 둔다.

## Consequences

- 화면은 각 기능의 타입 있는 `push` 함수로 연다. Host에는 문자열 경로가 없다.
- Host route를 URL로 복원하거나 공유할 수 없다. 필요해지면 이 결정을 다시 본다.
- 뒤로가기 순서는 `BackRouter`의 표 테스트로 확인하고, 실제 시스템 back은 E2E가 확인한다.

결정의 자세한 내용: [Host 코드 구조 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/53)
