# 커뮤니티 탭은 WebView 하나이고, 그 안의 뒤로가기는 Web이 처리한다 (Host는 `goBack()`을 쓰지 않는다)

커뮤니티 탭에는 WebView를 하나만 두고, 커뮤니티·게시글·아티스트 프로필은 그 안에서 Web history로 오간다. 탭 막대를 덮는 Web 화면(글쓰기)과 그 위에 쌓이는 Web 화면만 Host route와 자기 WebView를 따로 가진다. 그 안의 뒤로가기는 Web이 처리한다. Web은 Message `nav.backState {handled}`로 지금 뒤로가기를 처리할지 미리 알리고, Host는 Android 뒤로가기를 받으면 일회 Event `nav.back`을 보낸다. Web은 작성 중이면 이탈 확인 창을 띄우고, 아니면 `history.back()`을 한다. Host는 Web의 경로도 history도 보지 않는다. 실측에서 사용자 활성화 없이 쌓은 기록을 Android는 `canGoBack()`에 세지 않았고, iOS `goBack()`은 건너뛰었다. 그런데 딥링크 등 Event로 시작한 이동이 바로 그런 기록이라, Host의 `goBack()`으로는 "뒤로 가면 목록"을 지킬 수 없다.

## Considered Options

- **Web 화면마다 Host route와 WebView**: 뒤로가기가 Navigator 하나로 끝나고 전환도 네이티브다. 하지만 화면을 열 때마다 문서를 새로 불러오고 핸드셰이크를 다시 하며, WebView끼리 TanStack Query 캐시를 나누지 못해 무효화 Event가 늘어난다. Android는 WebView들이 렌더러 하나를 같이 써서 늘려도 장애가 격리되지 않는다.
- **앱 전체에 WebView 하나**: 글쓰기까지 같은 WebView에 두면 탭 막대를 Web 상태에 맞춰 숨겨야 하고, Host 화면 위에 Web을 쌓을 수 없다.
- **Host가 `canGoBack()`·`goBack()`으로 WebView history를 직접 되돌림**: 위의 사용자 활성화 문제가 있다. 출처가 다른 iframe 안의 이동도 기록에 쌓여, `goBack()`이 메인 프레임 대신 iframe을 되돌린다.
- **작성 중 가드(`nav.setLeaveGuard`·`nav.backBlocked`)와 뒤로가기 위임을 별도 통로로**: 뒤로가기를 막는 통로가 둘이 되어, 둘 다 켜졌을 때 어느 쪽이 먼저인지 정해야 한다. 가드는 `nav.backState`를 켜는 조건 하나로 흡수했다.

## Consequences

- Web 안의 팝업(안내 창·확인 창·시트)은 history 항목으로 만든다. 그래야 `history.back()` 하나로 팝업도 닫힌다. Web은 이동 깊이를 메모리에서 센다.
- 탭 이동과 재선택은 Event(`tab.reset`, `tab.reselected`)로 Web에 맡긴다. `tab.reset`은 Host가 그 WebView 자신의 이동을 지시하는 일회 Event라서, 가려진 WebView에도 보낸다.
- 글쓰기처럼 자기 route를 가진 WebView는 Message `nav.close`로 route를 닫는다. history가 없어 `history.back()`으로는 닫을 수 없기 때문이다.
- 서드파티 임베드가 안에서 이동하면 뒤로가기가 임베드를 되돌린다. 가짜 영상 플레이어는 안에서 이동하지 않게 만든다([ADR 0001](0001-web-screen-content-policy.md)).
- iOS에서는 WK 스와이프를 켜지 않는다. 켜면 `nav.back`을 거치지 않아 팝업 항목과 이탈 확인을 건너뛰기 때문이다. 그래서 탭 안의 Web 이동은 Web 헤더의 ‹ 버튼으로만 뒤로 간다.

결정의 자세한 내용: [화면 구성과 뒤로가기 설계 (S5)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/44)
