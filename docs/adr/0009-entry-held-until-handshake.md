# 진입은 Host가 보관했다가 핸드셰이크 뒤 `tab.open` Event 한 길로 열고, 경로 표 밖 링크는 브라우저로 다시 보내지 않는다

딥링크(`https://fan.example/<경로>`, `fanapp://app/<경로>`)와 알림(payload `{path}`)은 모두 Host의 진입 모듈 하나로 모인다. Host는 경로 표로 판정해 Web 경로 하나로 바꾸고, 슬롯 하나(마지막 진입이 이김)에 보관한다. 커뮤니티 탭 WebView는 콜드 스타트든 웜 스타트든 평소처럼 `/community`를 연다. 그 WebView의 핸드셰이크가 끝나고 보이는 상태가 되면, Host가 일회 Event `tab.open {path}`를 보낸다. Web은 `tab.reset`과 같은 정리를 한 뒤 `path`로 클라이언트 이동을 한다. 핸드셰이크 Call이 Web이 준비됐다는 신호라서 Event를 놓치지 않는다. 그리고 이 이동이 Web history에 쌓이므로 "뒤로 가면 목록"이 지켜진다([ADR 0008](0008-web-owns-back-in-tab-webview.md)). 경로 표 밖 링크는 거절하고 안내만 한다. 시스템 브라우저로 다시 보내지 않는다. 실측에서 Android가 도메인 전체를 승인한 상태면 `externalApplication`으로 보낸 링크가 3/3 앱으로 돌아왔기 때문이다.

## Considered Options

- **콜드 스타트에 목적지 URL을 바로 불러온다**: 목록이 잠깐 보이지 않는다. 하지만 history에 목록이 없어 뒤로 가면 앱이 끝나고, 웜 스타트와 길이 갈린다.
- **목적지 URL을 불러온 뒤 Web이 history를 `/community` → 목적지로 채운다**: 깜빡임 없이 "뒤로 가면 목록"이 된다. 대신 콜드·웜 스타트의 길이 둘이 되고, Web에 진입 전용 처리가 생긴다.
- **Flutter 기본 딥링크 + Router**: 링크가 Host Router 경로가 되는데 Host는 Web 경로를 다루지 않는다. iOS에서는 첫 프레임을 3초까지만 기다린다.
- **표 밖 https 링크를 시스템 브라우저로 넘긴다**: 위의 자기 루프 때문에 성립하지 않는다. `launchUrl`의 반환값으로는 앱으로 돌아왔는지 구별할 수도 없다.

## Consequences

- 콜드 스타트에서는 목적지가 열리기 전에 목록이 잠깐 보인다.
- 탭 WebView가 "Bridge 없음" 상태면 Event를 보낼 수 없으므로, Host가 그 WebView에 `loadRequest(기준 URL + path)`를 한다. 이때는 "뒤로 가면 목록"이 성립하지 않는다.
- 글쓰기 중의 진입은 예외다. 루트 Navigator에 쌓는 Web 화면 route가 새 WebView라서 Event 없이 `loadRequest`로 연다.
- Android intent-filter는 경로 표의 딥링크 경로(`/community`, `/posts/`, `/artist`)로 좁힌다. 그래야 표 밖 https 링크는 처음부터 브라우저가 연다. 커스텀 스킴은 경로로 거를 수 없어 Host 판정에만 맡긴다.
- `app_links`는 콜드 스타트 URI를 `getInitialLink()`와 첫 스트림 이벤트로 두 번 준다(실측 5/5). 그래서 앱 수명 동안 유지되는 `uriLinkStream` 구독 하나만 쓴다.

결정의 자세한 내용: [딥링크·알림 진입 설계 (S3)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/45)
