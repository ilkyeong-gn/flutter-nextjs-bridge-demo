# Web은 원격 URL로만 띄우고, CSP nonce를 위해 모든 페이지를 동적 렌더링한다

Host는 Web을 원격 URL에서만 불러온다. 앱에는 Web 파일을 하나도 넣지 않고, 로딩에 실패하면 Host 화면을 보인다. 가짜 API는 Next.js Route Handlers에 그대로 두어 Web과 같은 출처에 있다. 그래야 서버가 만든 HttpOnly 쿠키로 Web 세션을 유지할 수 있다([ADR 0006](0006-web-session-by-offscreen-handoff.md)). 또 동적 라우트 `/posts/{id}`도 그대로 쓸 수 있다. CSP `script-src`는 `'self' 'nonce-…' 'strict-dynamic'`으로 둔다. 메인 프레임에서 주입된 인라인 스크립트가 Bridge를 부르지 못하게 하는 방법은 nonce뿐이기 때문이다([ADR 0005](0005-main-frame-stays-in-route-table.md)). nonce를 쓰려면 모든 페이지를 동적으로 렌더링해야 한다. Next.js 문서는 PPR과 nonce를 함께 쓸 수 없다고 적고 있으므로 `cacheComponents`는 끈다.

## Considered Options

- **번들(static export)**: 오프라인에서 시작할 수 있고 Host·Web 버전이 함께 고정된다. 대신 Request를 읽는 Route Handlers, 동적 라우트, `cacheComponents`를 쓸 수 없다. `webview_flutter`만으로는 띄울 수 없고, iOS는 `https` 스킴을 처리할 수 없어서 Web과 API의 출처가 갈린다. 그러면 S1의 쿠키 세션이 성립하지 않는다.
- **원격 + 번들 오류 HTML(Capacitor `errorPath`)**: 오류 페이지 하나를 위해 번들을 로컬에서 내주는 수단이 필요하다. iOS에서는 그 수단이 `file://`뿐이다. 오류 화면은 Host 화면이 맡을 수 있다.
- **번들 + 원격 갱신**: 번들의 제약을 모두 지고, 그 위에 다운로드·검증·롤백·호환 Host 버전 관리까지 더해야 한다.
- **`'self' 'unsafe-inline'`(nonce 없음)**: 정적 셸과 `cacheComponents`를 유지할 수 있다. 대신 주입된 인라인 스크립트가 실행된다. 실험 기능인 SRI는 외부 스크립트에만 해시를 붙이므로 이 문제를 막지 못한다.

## Consequences

- 오프라인에서는 앱이 시작되지 않는다. 로딩 실패는 Host 화면으로 보인다.
- Web을 배포하는 즉시 "새 Web + 옛 Host" 조합이 생긴다. Host는 WebView를 열기 전에 같은 출처의 `GET /api/host-config`로 최소 Host 버전을 확인하고, 그보다 낮으면 Host 화면으로 업데이트를 안내한다. 이 요청이 실패하면 막지 않는다. Web은 기능 목록에 없는 Call을 Host에 보내지 않고 그 자리에서 `unsupported`로 실패시킨다. 계약 major가 맞지 않으면 "Bridge 없음"으로 처리하고 업데이트 안내만 보인다.
- 모든 페이지가 `no-store`로 나가므로 WebView에 오래된 HTML이 남지 않는다. 대신 `'use cache'`와 정적 셸은 쓰지 않는다. 데이터는 TanStack Query로 클라이언트에서 가져온다.
- nonce와 `cacheComponents`가 실제로 함께 동작하지 않는지는 실측하지 않았다. 문서 근거로 정했으므로 구현할 때 한 번 확인한다.
- `deploymentId`는 빌드의 git SHA로 둔다. Web 클라이언트와 Web 서버가 어긋나면 Next가 전체 새로고침을 하고, Web은 핸드셰이크를 다시 한다. 이때 아직 올리지 않은 첨부는 사라진다([ADR 0007](0007-host-picks-and-uploads-attachments.md)).

결정의 자세한 내용: [Web 전달 방식과 버전·환경 정책 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/46)
