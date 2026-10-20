---
status: partially superseded by ADR-0018
---

# Web은 데이터를 클라이언트에서 HTTP로만 읽고, 이동은 `shared/nav`로만 한다

Web의 페이지는 얇은 서버 컴포넌트다. 데이터는 클라이언트에서 TanStack Query가 `shared/api`의 `fetch` 래퍼로 읽는다. 서버 컴포넌트의 prefetch와 `HydrationBoundary`는 쓰지 않는다. 가짜 API는 같은 Next.js 앱의 Route Handlers에 있지만, Web 코드는 그것을 별도 백엔드처럼 HTTP로만 다룬다. 실제 하이브리드 앱의 API는 보통 별도 서버라서, 이렇게 해야 Reference App의 패턴을 그대로 가져다 쓸 수 있다. 인증 검사도 Route Handlers 한 곳에만 생긴다.

이동도 한 길로만 한다. Web은 이동 깊이를 메모리에서 세어 `nav.backState`를 알린다([ADR 0008](0008-web-owns-back-in-tab-webview.md)). 그런데 Next.js의 `Link`와 `router.push`는 밖에서 push와 replace를 구분할 수 없다. 그래서 모든 이동은 `shared/nav`의 `<AppLink>`와 `useAppNavigation()`을 거친다. `next/link`와 `next/navigation`의 이동 API를 다른 곳에서 import하면 import 방향 검사가 막는다.

## Considered Options

- **서버 컴포넌트가 도메인 함수를 직접 불러 prefetch**: 첫 화면에 데이터가 바로 보인다. 하지만 인증 검사가 HTTP 경로와 직접 호출 경로 두 곳에 생기고, API가 별도 서버인 구조로는 옮겨 갈 수 없다.
- **서버 컴포넌트가 자기 Route Handlers를 쿠키와 함께 `fetch`**: 같은 서버 안에서 HTTP를 한 번 더 거친다. 얻는 것은 첫 화면뿐이다.
- **`next/link`를 그대로 쓰고 `popstate`·`usePathname`으로 깊이를 추정**: replace와 push를 구분할 수 없어서 깊이가 틀어진다. 깊이가 틀어지면 뒤로가기가 앱을 닫거나 먹통이 된다.

## Consequences

- 페이지마다 처음에 로딩 상태가 보인다. 모든 페이지가 이미 동적 렌더링이라([ADR 0010](0010-remote-web-with-nonce-csp.md)) 캐시로 줄일 수도 없다.
- 상태 Event(`session`·`membership`)는 `_root`의 표 하나가 쿼리 무효화로 바꾼다. Bridge 모듈은 TanStack Query를 모른다.

결정의 자세한 내용: [Web 코드 구조 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/54)
