# 메인 프레임에서는 우리 번들만 실행하고, 이를 nonce CSP로 강제한다

Bridge는 Transport를 `window`에서 찾으므로([ADR 0017](0017-bridge-finds-transport-on-window.md)), 메인 프레임에서 실행되는 스크립트는 무엇이든 Bridge 전체 권한을 가진다. 이 사실은 인증 방식이나 WebView 패키지와 상관없이 성립한다. 그래서 메인 프레임에서는 우리 번들만 실행한다. 분석·에러 수집·광고 SDK도 메인 프레임에 넣지 않는다. 이를 CSP `script-src 'self' 'nonce-…' 'strict-dynamic'`로 강제하고, 외부 호스트는 적지 않는다. nonce는 `proxy.ts`가 요청마다 만든다. nonce를 쓰려면 모든 페이지를 동적으로 렌더링해야 한다. Next.js 문서는 PPR과 nonce를 함께 쓸 수 없다고 적고 있으므로 `cacheComponents`는 끈다. CSP는 처음부터 강제 모드로 걸고, 보고는 받지 않는다. 이 지도에서는 Host가 출처를 어떻게 판정할지 정하지 않으므로, Web의 기본선은 Host가 무엇을 지켜 주는지와 상관없이 그 자체로 성립해야 한다.

이 ADR은 [ADR 0010](0010-remote-web-with-nonce-csp.md)의 CSP 부분과 [ADR 0001](0001-web-screen-content-policy.md)의 "메인 프레임에서는 우리 번들만" 부분을 이어받는다. 결정은 같지만 근거가 달라졌다. 이슈 26에서는 출처 판정이 근거였고([ADR 0005](0005-main-frame-stays-in-route-table.md)), 여기서는 `window`의 Transport가 근거다. 0010의 원격 URL·번들 논의와 0001의 영상 임베드 시나리오는 이 결정과 관계가 없다.

## Considered Options

- **해시 CSP**: Next App Router가 페이지마다 내보내는 인라인 부트스트랩(RSC 페이로드)은 요청마다 내용이 달라서 해시를 미리 계산할 수 없다. `experimental.sri`는 외부 스크립트에만 해시를 붙인다. 결국 `'unsafe-inline'`이 필요해진다.
- **정적 CSP(`'self' 'unsafe-inline'`)**: 정적 셸과 `cacheComponents`를 유지할 수 있다. 대신 주입된 인라인 스크립트가 실행되어, XSS 한 번이 곧 Bridge 전체 권한이 된다. 나중에 nonce로 옮기려면 인라인 스크립트를 쓴 코드를 모두 고쳐야 한다.
- **Report-Only로 시작한다**: 보고를 모을 곳이 없다(운영 모니터링은 범위 밖). 위반을 처음부터 깨지는 테스트로 드러내는 편이 싸다.
- **서드파티 SDK를 `script-src`에 허용한다**: SDK 제공자와 그 CDN에 Bridge 권한을 넘기는 것과 같다.

## Consequences

- 모든 페이지가 `no-store`로 나간다. `'use cache'`와 정적 셸은 쓰지 않는다. 데이터는 이미 클라이언트에서 HTTP로 읽으므로([ADR 0014](0014-web-reads-data-over-http-only.md)) 잃는 것이 적고, WebView에 오래된 HTML이 남지 않는다.
- nonce와 `cacheComponents`를 함께 쓸 수 없다는 것은 실측하지 않았다. 문서를 근거로 정했으므로 구현할 때 한 번 확인한다.
- 개발에서만 `script-src`에 `'unsafe-eval'`을 더한다(React 개발 모드에 필요).
- SDK가 꼭 필요해지면 새 ADR로 예외를 정한다. 이때 npm 패키지로 번들에 넣어 우리 코드로 취급할지, 다른 출처의 iframe에 격리할지를 판단한다.
- `frame-ancestors 'none'` 때문에 우리 문서는 프레임에 들어가지 않는다. 그래서 Bridge 모듈에 최상위 문서 검사를 따로 두지 않는다.

결정의 자세한 내용: [Web 보안 기본선과 CSP 방식 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/66)
