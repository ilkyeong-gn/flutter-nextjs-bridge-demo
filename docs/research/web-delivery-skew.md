# Web 전달 방식과 Host·Web 버전 어긋남 대응 조사

- 질문: [#35 Web 전달 방식과 Host·Web 버전 어긋남 대응 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/35)
- 조사일: 2026-10-19
- 확인한 버전: Next.js 16.4.0(저장소 고정 버전과 패키지 동봉 문서, 일부는 최신 안정판 16.4.2에서 재확인), Flutter 3.47.7, webview_flutter 4.14.1(webview_flutter_android 4.14.1, webview_flutter_wkwebview 3.27.0), flutter_inappwebview 6.1.5, Capacitor 8.5.3, Android platform-tools 37.0.1

## 요약

- **원격 URL**은 Next.js 서버 기능을 모두 쓰고 Web을 Host 출시와 따로 배포할 수 있다. 대신 오프라인에서는 시작할 수 없고, 새 Web이 옛 Host 위에서 도는 버전 어긋남을 반드시 다뤄야 한다.
- **번들(static export)**은 오프라인 시작과 Host·Web 버전 고정을 얻고 서버 기능을 잃는다. Request를 읽는 Route Handlers, Server Actions, cookies, Proxy, `generateStaticParams` 없는 동적 라우트 등이 빠지고, 16.4.x에서는 저장소가 켠 `cacheComponents`와 함께 빌드되지 않는다. 가짜 API는 앱 밖 서버로 나가야 한다.
- 기본 export 결과물은 루트 절대 경로(`/_next/...`)를 써서 `file://`로는 뜨지 않는다. http(s)나 사용자 정의 scheme 출처가 필요한데 webview_flutter 4.14.1에는 그 수단이 없다. iOS는 앱이 `https` scheme을 직접 처리할 수 없어 Web과 API의 출처가 갈리고 쿠키·CORS 제약이 생긴다.
- **혼합**(원격 기본 + 오프라인 대체)의 선례는 Capacitor `errorPath`다. 대체를 오류·재시도 화면으로 한정하면 번들 제약을 지지 않고, Web 전체를 대체로 번들하면 두 방식의 제약을 함께 진다.
- 새 Web이 옛 Host에 없는 Host 기능을 부를 때의 공개 선례는 기능 단위 탐색(Capacitor `isPluginAvailable`), Host API 버전 비교(Telegram Mini Apps `isVersionAtLeast`), 모르는 호출에 표준 오류(JSON-RPC `-32601`), 배포 단계의 호환 Host 버전 제한(Ionic Appflow, Expo `runtimeVersion`)이다. 앱 안 업데이트 API는 Android에 In-App Updates가 있고, iOS에서는 같은 API를 찾지 못했다.
- Next.js `deploymentId`는 Web 클라이언트와 Web 서버 사이의 어긋남만 다룬다. 불일치를 감지하면 전체 새로고침으로 바꿀 뿐이고(컴포넌트 상태 손실), 배포별 라우팅은 호스트·CDN 몫이다. Host·Web 어긋남은 다루지 않는다.
- 캐시와 서비스 워커: 16.4.0 `next start`는 해시 파일에 1년 `immutable`, 사전 렌더 HTML에 공유 캐시용 `s-maxage`와 ETag를 보낸다. 서비스 워커는 Android WebView에서는 되지만 iOS WKWebView에서는 App-Bound Domains 밖에서 지원되는 방법이 없어, 오프라인 대체를 서비스 워커에 맡기기 어렵다.
- 환경 분리: Host는 flavor(`--flavor`, `appFlavor`, flavor별 asset)와 `--dart-define-from-file`(.json·.env)로, Web은 `.env*`로 나눈다. Next.js `NODE_ENV`에는 staging이 없어 공식 예제는 staging용 env 파일로 production 빌드를 하나 더 만든다. `NEXT_PUBLIC_` 값은 빌드 때 고정된다.
- 로컬 접속: Android 에뮬레이터 `10.0.2.2`, iOS 시뮬레이터 `localhost`(저장소에서 검증), 실기기는 `adb reverse`나 LAN IP이며, `localhost`가 아닌 주소(`10.0.2.2`, LAN IP)는 `allowedDevOrigins`에 넣어야 한다. iOS 17부터 ATS는 IP 주소 접속을 기본 차단한다. Android `usesCleartextTraffic`은 API 38 이상 타깃에서 무시될 예정이라 네트워크 보안 설정으로 dev 주소만 허용하는 것이 공식 권장 경로다.

## 상세

> 표기: [n]은 출처 번호다. **(직접 확인)**은 저장소 `web/`을 임시 디렉터리에 복사해 Next.js 16.4.0으로 빌드·실행한 결과이고(저장소 파일은 바꾸지 않음), **(추론)**은 출처에서 끌어낸 판단이다.

### 1. 원격·번들·혼합의 장단점과 번들 시 Next.js 서버 기능 제약

**원격 URL**

- Next.js 배포 방식 가운데 Node.js 서버와 Docker는 모든 기능을, static export는 "Limited" 기능만 지원한다 [1]. 원격 방식은 Web을 서버로 띄우므로 RSC 스트리밍, Route Handlers, Server Actions, cookies, Cache Components를 그대로 쓴다.
- 스토어 정책: Google Play는 Play 업데이트 외의 방법으로 앱이 스스로를 바꾸는 것을 금지하면서, "JavaScript in a webview or browser"처럼 인터프리터에서 도는 코드는 예외로 명시한다 [2]. Apple 지침 2.5.2는 앱의 기능을 추가·변경하는 코드를 내려받아 실행하지 말라고 하고, 4.2는 "repackaged website" 이상의 기능·UI를 요구한다 [3]. 원격 Web에 이 조항이 어떻게 적용되는지에 대한 공식 해석은 찾지 못했다.
- Capacitor는 원격 URL을 띄우는 `server.url`을 "live-reload 서버용이며 production용이 아니다"라고 적는다. 기본으로는 앱에 묶은 `webDir`을 iOS `capacitor://localhost`, Android `https://localhost`에서 제공한다 [4][5].

**번들: Next.js static export**

- `output: 'export'`로 빌드하면 `out/`에 라우트별 HTML과 클라이언트 이동용 정적 payload가 생기고, Server Components는 빌드 때 한 번 실행된다 [6]. 사용자별 데이터는 클라이언트에서 가져와야 하므로 고정 스택의 TanStack Query 방식과는 맞는다(추론).
- 지원하지 않는 기능 [6]: `dynamicParams: true`이거나 `generateStaticParams()`가 없는 동적 라우트, Request에 의존하는 Route Handlers(정적 GET만 가능), Cookies, Rewrites, Redirects, Headers, Proxy, ISR, 기본 loader의 Image Optimization, Draft Mode, Server Actions, Intercepting Routes.
- **(직접 확인)** 저장소 설정(`cacheComponents: true`, `partialPrefetching: true`)에 `output: 'export'`만 더하면 `Invariant: PPR cannot be enabled in export mode`로 빌드가 실패한다. 이 검사는 "Export mode provide static outputs that are not compatible with PPR mode" 주석과 함께 소스에 들어 있고 16.4.2에도 그대로다 [7]. 둘을 함께 쓰게 하는 PR은 열려 있지만 머지되지 않았고, 검사를 지우는 PR은 머지 없이 닫혔다 [8][9].
- **(직접 확인)** `cacheComponents`를 끄면 빌드된다. 라우트 5개짜리 이 Demo의 `out/`은 972KB이고, HTML은 `/_next/static/...`을, 링크는 `/stage-b`를 루트 절대 경로로 참조한다.
- **(직접 확인)** POST Route Handler(`app/api/posts/route.ts`)를 둔 채 빌드하면 빌드는 성공하지만 `out/`에 그 경로가 생기지 않는다. 문서는 이런 기능을 `next dev`에서 오류로 알린다고만 적는다 [6]. 번들 Web 안에는 가짜 API가 없다.
- **(직접 확인)** `app/posts/[id]/page.tsx`처럼 `generateStaticParams()`가 없는 동적 라우트는 `Page "/posts/[id]" is missing "generateStaticParams()"` 오류로 빌드가 멈춘다. 팬이 계속 올리는 게시글의 ID는 빌드 때 알 수 없으므로, 쿼리 파라미터와 클라이언트 조회 같은 다른 라우팅이 필요하다(추론).
- 정적 서버는 `/blog/post-1` 요청을 `post-1.html`로 잇는 규칙(nginx `try_files $uri $uri.html $uri/`)이 필요하고, `trailingSlash: true`면 `/about/index.html`로 출력된다 [6][10]. 앱 안에서 파일을 내주는 계층도 같은 규칙을 구현해야 한다(추론).

**앱 안에서 번들을 제공하는 수단**

- webview_flutter 4.14.1의 `loadFlutterAsset`은 Android에서 `file:///android_asset/...` URL을 열고 [11], iOS에서는 `loadFileURL(url, allowingReadAccessTo: 그 파일의 디렉터리)`를 부른다 [12]. 따라서 export 결과물의 `/_next/...` 참조는 `file:///_next/...`로 풀려 깨진다(추론). WebView 요청에 앱이 직접 응답하게 해 달라는 기능 요청(flutter/flutter#27896)은 2019-02부터 열려 있다(P3) [13].
- Android 공식 문서는 `WebViewAssetLoader`를 권한다. http(s) URL로 앱 파일을 내주어 same-origin 정책과 맞고, `file://`는 opaque origin이라 `fetch()`·XHR 같은 API를 제대로 쓰지 못한다 [14]. 기본 도메인은 `appassets.androidplatform.net`이고, `setDomain`으로 자기 도메인을 쓸 수 있다 [14].
- iOS는 `WKURLSchemeHandler`로 앱이 응답할 scheme을 등록한다. 하지만 `https`처럼 WebKit이 이미 처리하는 scheme은 등록할 수 없다(예외 발생) [15]. Capacitor가 iOS에서 `capacitor://`를 쓰는 이유다 [5].
- flutter_inappwebview 6.1.5는 Android `WebViewAssetLoader` [16], Android·iOS 사용자 정의 scheme(`resourceCustomSchemes` + `onLoadResourceWithCustomScheme`) [17], `http://localhost:[port]/` 로컬 서버인 `InAppLocalhostServer`(기본 포트 8080) [18]를 제공한다. 최신 안정판 6.1.5는 2024-10에 나왔고, 그 뒤로는 6.2.0-beta.3(2026-02)뿐이다 [19]. WebView 패키지 결정(#38)에 걸리는 조건이다.
- Flutter asset의 디렉터리 항목은 바로 아래 파일만 포함하므로 하위 디렉터리마다 항목을 따로 써야 한다 [20]. export 결과물은 `_next/static/chunks/`, `_next/static/<빌드 ID>/`, 라우트별 디렉터리로 나뉘어 있어(직접 확인) pubspec 항목을 빌드마다 생성하는 단계가 필요할 것이다(추론).
- 출처 분리: 번들 Web(`https://appassets.androidplatform.net`이나 사용자 정의 scheme)과 API 서버의 출처가 달라 API 호출이 cross-origin이 된다(추론). Android WebView는 Lollipop 이상을 타깃하는 앱에서 서드파티 쿠키를 기본 거부한다 [21]. WKWebView는 iOS 14부터 ITP가 기본으로 켜져 있고 [22], ITP는 iOS 13.4부터 cross-site 쿠키를 기본 차단한다 [23]. Android는 `setDomain`으로 API와 같은 도메인을 쓸 여지가 있지만 iOS는 `https`를 처리할 수 없어 두 플랫폼이 비대칭이다(추론, [14][15]). 로그인과 세션 설계(#42)에 바로 영향을 준다.

**혼합: 원격 + 오프라인 대체**

- Capacitor `server.errorPath`(4.0.0+)는 원격 로딩이 실패하면 로컬 HTML을 띄운다. Android에서는 그 페이지가 Capacitor 플러그인에 접근하지 못한다 [5].
- Host는 webview_flutter `NavigationDelegate`의 `onWebResourceError`·`onHttpError`로 실패를 받아 Host 화면이나 번들 오류 페이지로 바꿀 수 있다 [24].
- Web 쪽에서는 Next.js 16의 실험 기능 `experimental.useOffline`이 오프라인 감지, `HEAD` 폴링(최대 3초 간격), 이동·prefetch·Server Action 자동 재시도와 `useOffline()` 훅을 준다 [25]. 오프라인 캐시는 아니며, 서비스 워커 기반 캐시는 PWA 가이드가 외부 라이브러리(Serwist)를 안내한다 [26].
- 대체를 오류·재시도 화면으로 한정하면 export 제약을 지지 않는다. 대체로 Web 전체를 번들하면 번들의 제약과 원격의 버전 어긋남을 함께 지고, 번들 사본과 원격 Web이 서로 달라지는 문제가 더해진다(추론).

### 2. 새 Web이 옛 Host에 없는 Host 기능을 부를 때

| 패턴 | 공개 선례 | 동작 |
|---|---|---|
| 기능 단위 탐색 | Capacitor `isPluginAvailable(name)` [27] | 지금 플랫폼에서 그 플러그인(Host 기능에 해당)을 쓸 수 있는지 boolean으로 답한다 |
| Host API 버전 비교 | Telegram Mini Apps `WebApp.version`, `isVersionAtLeast(version)` [28] | Host가 지원하는 API 버전을 알려 준다. 문서는 기능마다 "Bot API 6.1+"처럼 도입 버전을 적는다 |
| 모르는 호출에 표준 오류 | JSON-RPC 2.0 `-32601 Method not found` [29] | "The method does not exist / is not available." |
| 배포 단계 제한 | Ionic Appflow live update [30][31], Expo `runtimeVersion` [32] | Ionic은 live update마다 받을 수 있는 네이티브 바이너리(Host 빌드에 해당)의 버전 조건(`--ios-min`, `--android-max` 등)을 정한다. Expo는 빌드와 runtime version이 맞는 업데이트만 호환으로 본다 |

- Ionic은 live update가 HTML·CSS·JS 같은 "binary compatible" 변경에만 통하고, 플러그인 추가·제거 같은 변경은 새 바이너리를 스토어에 내야 한다고 적는다 [30]. Expo는 runtime version을 "a property that guarantees compatibility between a build's native code and an update"로 정의한다 [32]. 둘 다 앱에 묶은 웹·JS 코드를 원격으로 갱신하는 방식(번들 + live update)의 선례다(Expo는 React Native 대상).
- Host가 자기 버전을 Web에 알리는 통로로 webview_flutter는 `setUserAgent`(HTTP `User-Agent` 헤더)를 제공한다 [33]. Bridge Call로 조회하거나 시작 URL에 붙이는 방법도 있다(추론). User-Agent에 넣으면 원격 서버도 요청마다 Host 버전을 읽을 수 있다(추론).
- 업데이트 안내: Android Play In-App Updates는 전체 화면에서 업데이트와 재시작을 요구하는 immediate 흐름과 백그라운드로 받는 flexible 흐름을 제공한다 [34]. iOS에서 같은 성격의 API는 찾지 못했고, 앱 안에 App Store 상품 페이지를 띄우는 `SKStoreProductViewController`가 있다 [35].
- 원격 방식에서는 Web을 배포하는 즉시 "새 Web + 옛 Host" 조합이 생긴다. 번들 방식에서는 Web이 Host와 함께 나가므로 이 조합이 없고, API와 설치된 Host 사이의 어긋남만 남는다(추론).

### 3. 배포 중 버전 어긋남을 막는 기능과 캐시·서비스 워커

- Next.js는 version skew를 새 배포 뒤에도 살아 있는 클라이언트가 옛 빌드의 JS·CSS·데이터를 참조하는 상태로 정의하고, 누락 자산·Server Action 오류·이동 실패를 예로 든다 [36][37].
- `deploymentId`(또는 `NEXT_DEPLOYMENT_ID`)를 정하면 정적 자산 URL에 `?dpl=`, 클라이언트 이동 요청에 `x-deployment-id`, 응답에 `x-nextjs-deployment-id`, `<html>`에 `data-dpl-id`가 붙고 `'use cache'` 키에도 들어간다. 클라이언트가 불일치를 감지하면 클라이언트 이동 대신 전체 새로고침을 한다 [38].
- Next.js는 `?dpl=`을 라우팅에 쓰지 않는다. 호스트·CDN이 배포별로 라우팅하지 않으면, 롤아웃 중 다른 배포의 서버에 닿은 클라이언트는 이동 대신 새로고침을 한다 [38]. 새로고침하면 URL이나 localStorage에 둔 상태는 남지만 `useState` 같은 컴포넌트 상태는 사라진다 [37].
- 16.3부터는 내용 주소로 이름 붙은 정적 파일을 `?dpl` 없이 배포 간에 공유하는 immutable static assets가 있다. 문서는 같은 폴더나 버킷에 계속 쌓으면 어긋남이 없다고 설명하지만, 어댑터가 지원해야 하고 앱 개발자는 문제 해결용으로만 설정하라고 한다 [39][37].
- **(직접 확인)** 저장소 설정에 `deploymentId: 'exp-dpl-1'`을 더해 `next start`로 띄우면 청크는 `?dpl=exp-dpl-1`과 `Cache-Control: public, max-age=31536000, immutable`을, 사전 렌더 HTML은 `Cache-Control: s-maxage=31536000`, ETag, `data-dpl-id="exp-dpl-1"`을 보낸다. RSC 요청의 응답에는 `x-nextjs-deployment-id` 헤더가 있다. `s-maxage`는 공유 캐시에만 적용되는 지시어다 [40]. 문서에 따르면 immutable 헤더는 덮어쓸 수 없고, 동적 렌더링 페이지는 `private, no-cache, no-store, max-age=0, must-revalidate`를 받는다 [37].
- Host·Web 맥락에서의 의미(추론): `deploymentId`는 Web 클라이언트와 Web 서버만 맞출 뿐 Bridge 계약의 어긋남은 다루지 않는다. Host가 백그라운드에 오래 머무르면 WebView는 옛 JS를 계속 돌리다가 다음 이동에서 새로고침될 수 있고, 그때 Web 쪽 Bridge 상태(응답을 기다리던 Call 등)는 초기화된다.
- Host는 webview_flutter `clearCache()`·`clearLocalStorage()`로 WebView 캐시와 저장소를 비울 수 있다 [33]. Host 업데이트 직후 한 번 비우는 식으로 쓸 수 있다(추론).
- 서비스 워커: Android에는 `ServiceWorkerController`("Manages Service Workers used by WebView", API 24+)가 있다 [41]. iOS는 Apple Frameworks Engineer가 2025-02에 "There's no supported way for you to explicitly support service workers in iOS WKWebView with the APIs currently available."라고 답했다 [42]. WebKit 버그 206741은 2026-08-04 기준 NEW이고, 2023년 사용자 댓글은 App-Bound Domains를 켜도 워커가 HTTP/HTTPS로만 로드되고 사용자 정의 scheme으로는 로드되지 않는다고 보고한다 [43]. App-Bound Domains(최대 10개, `limitsNavigationsToAppBoundDomains`)에 옵트인하면 그 밖의 도메인에서는 JS 주입과 메시지 핸들러가 거부되므로 [22] Bridge 설계와 부딪칠 수 있다(추론). Next.js PWA 가이드는 서비스 워커 파일에 `Cache-Control: no-cache, no-store, must-revalidate`를 권한다 [26].

### 4. dev/staging/prod 환경 분리와 로컬 접속 주소

**Host (Flutter)**

- flavor는 아이콘·앱 이름·API 키·기능 플래그·로그 수준 등을 버전별로 묶는 단위다. `flutter run --flavor <name>`으로 고르고 코드에서는 `appFlavor`로 읽으며, flavor 없이 빌드하면 `null`이다 [44]. iOS는 Xcode scheme과 build configuration으로 구현하고, `appFlavor`는 scheme 이름과 같다 [45]. pubspec의 asset `flavors:`로 flavor별 asset을 묶고, `default-flavor`로 기본 flavor를 정한다 [46].
- `--dart-define` 값은 `String.fromEnvironment` 같은 생성자로 읽고, const로 부를 때만 동작이 보장된다 [47]. `--dart-define-from-file`은 `.json`이나 `.env` 파일을 받고, 여러 번 줄 수 있으며, 같은 키는 `--dart-define`이 우선한다 [48].
- 현재 저장소는 `app/lib/config.dart`에서 플랫폼별 dev 주소(Android `http://10.0.2.2:3000`, 그 밖 `http://localhost:3000`)를 코드로 고정한다.

**Web (Next.js)**

- `.env*`는 `process.env` → `.env.$(NODE_ENV).local` → `.env.local`(test 제외) → `.env.$(NODE_ENV)` → `.env` 순서로 찾고, `NODE_ENV`는 production·development·test만 허용한다 [49].
- `NEXT_PUBLIC_` 값은 `next build` 때 JS에 인라인되어 빌드 뒤에는 바뀌지 않는다. 빌드 하나를 여러 환경에 쓰려면 서버에서 동적 렌더링 중에 읽거나 별도 API로 내려 줘야 한다 [49].
- 공식 예제 with-docker-multi-env는 development·staging·production env 파일을 둔다. staging Dockerfile은 `.env.staging.sample`을 `.env.production`으로 복사해 production 모드로 빌드한다 [50].
- 번들 방식이면 Web 빌드가 Host 빌드에 들어가므로 Web 환경은 Host flavor와 짝으로 고정된다(추론).

**로컬 접속 주소**

| 대상 | 주소 | 근거와 조건 |
|---|---|---|
| Android 에뮬레이터 | `http://10.0.2.2:3000` | `10.0.2.2`는 개발 머신 루프백(127.0.0.1)의 별칭이다 [51] |
| Android 실기기 | `adb reverse tcp:3000 tcp:3000` 뒤 `http://localhost:3000`, 또는 LAN IP | adb의 reverse socket 연결 [52]. 기기 쪽 포트를 개발 머신으로 잇는다는 해석은 추론 |
| iOS 시뮬레이터 | `http://localhost:3000` | 이 저장소에서 검증(README). Apple 문서 근거는 찾지 못함 |
| iOS 실기기 | LAN IP 또는 `.local` 이름 | iOS 17부터 ATS가 IP 주소 접속을 기본 허용하지 않고, `NSAllowsLocalNetworking`이 unqualified·`.local`·IP 접속을 허용한다 [53]. WKWebView 트래픽에는 로컬 네트워크 권한이 필요 없다 [54] |

- Next dev 서버는 `localhost`와 그 하위 도메인, 시작할 때 쓴 hostname만 허용하므로 `10.0.2.2`·LAN IP·`.local` 이름은 `allowedDevOrigins`에 넣어야 한다. 비교는 Origin의 hostname만 본다 [55].
- Android는 API 28 이상을 타깃하면 cleartext가 기본으로 막힌다. `usesCleartextTraffic`은 deprecated 예정이고 API 38 이상 타깃에서는 무시되므로 네트워크 보안 설정을 쓰라고 한다 [56]. 네트워크 보안 설정은 도메인별로 `cleartextTrafficPermitted`를 줄 수 있다 [57]. 저장소는 main 매니페스트에 `usesCleartextTraffic="true"`를 두어 release 빌드에도 적용된다. Flutter 템플릿이 만든 `src/debug`·`src/profile` 매니페스트처럼 빌드 타입별 소스셋으로 dev 전용 설정을 나눌 수 있다(추론).

## Reference App에 주는 시사점

「Web 전달 방식과 버전·환경 정책 결정」(#46)이 따질 선택지와 맞바꾸는 것을 정리한다. 고르지는 않는다.

### 전달 방식

| 선택지 | 얻는 것 | 잃는 것·비용 | 다른 결정과의 관계 |
|---|---|---|---|
| A. 원격 URL | 고정 스택(Route Handlers 가짜 API, Cache Components, Server Actions)을 그대로 쓴다. Web과 API가 같은 출처라 쿠키 세션이 단순하다. HMR 개발 루프. 버전 어긋남 대응을 실제로 보여 줄 수 있다 | 오프라인 시작 불가라 Host 쪽 오류 화면이 필요하다. 어긋남 정책이 필수다. dev용 cleartext·ATS 예외. 실제 앱이라면 스토어 정책 검토 | WebView 패키지(#38)에 로컬 제공 조건이 붙지 않는다. 「로딩·오프라인·에러 화면」 정책이 필요하다 |
| B. 번들(static export) | 오프라인 시작, Host·Web 버전 고정, 첫 로딩에 네트워크 불필요 | `cacheComponents`를 꺼야 한다. 가짜 API를 별도 서버로 분리하고 cross-origin 쿠키·CORS를 풀어야 한다. 동적 라우트 우회, asset 목록 생성. webview_flutter만으로는 띄울 수 없다. Web 수정마다 Host 빌드 | #38에 로컬 제공 요구 조건이 생긴다. 로그인·세션(#42)이 어려워진다. "가짜 API를 Next.js 안에" 범위 결정을 다시 봐야 한다 |
| C. 혼합: 원격 + 대체 화면 | A의 이점에, 실패할 때 Host가 통제하는 화면(Capacitor `errorPath` 선례)이 더해진다 | 실패 감지·재시도 경로의 구현과 테스트. 대체 화면에는 기능이 없다 | 「로딩·오프라인·에러 화면」과 바로 이어진다 |
| D. 혼합: 번들 + 원격 갱신 | 오프라인 시작과 빠른 Web 수정을 함께 얻는다 | B의 제약 전부에 다운로드·검증·롤백·호환 Host 버전 관리(Ionic·Expo 선례)가 더해진다. Apple 2.5.2 해석 문제 | 범위가 가장 크다 |

- 어느 쪽이든 공유 링크용 "앱에서 열기·설치" 안내 페이지는 웹 서버에 있어야 하므로, 번들을 골라도 원격 Web 서버가 완전히 사라지지는 않는다(추론, 딥링크 조사 #34와 함께 볼 것).

### 버전 어긋남 정책

- **Host가 알릴 정보**: Bridge 버전 숫자 하나(Telegram형), Host 기능 목록(Capacitor형), 또는 둘 다. Bridge 계약 형태(#39)의 버전 필드·오류 코드와 함께 정해야 한다.
- **모르는 Call 처리**: 옛 Host가 표준 오류 코드(JSON-RPC `-32601`형)로 답하고 Web이 대체 UI를 보이는 방식. 계약에 오류 코드가 있어야 한다.
- **최소 Host 버전 판단 위치**: Web(코드나 원격 설정의 최소 버전과 Host 버전을 비교) 또는 Host(시작할 때 조회해 Host 화면으로 막기). 안내 UI는 Android In-App Updates와 iOS App Store 페이지로 갈린다.
- **보장 수준**: "모든 Host 기능에 대체 UI"부터 "최소 버전 미만은 차단"까지의 폭이 있다. 넓게 보장할수록 Web 코드에 분기가 는다.
- **검증 방법**: Reference App은 배포하지 않으므로 옛 Host를 흉내 내는 수단(예: `--dart-define`으로 Host 버전·기능 목록을 낮춰 실행)이 있어야 어긋남을 시연할 수 있다(추론). `deploymentId`는 설정만 해 두고 동작은 문서로 남기는 선택지도 있다.

### 환경 분리

- **Host**: flavor(dev·staging·prod별 앱 ID·이름 구분)와 `--dart-define-from-file`(Web base URL 등)의 조합, 또는 dart-define만. 에뮬레이터·시뮬레이터 주소 차이를 지금처럼 코드 분기로 둘지 파일로 뺄지.
- **Web**: `.env.development`·`.env.production`에 staging용 production 빌드를 더하는 공식 예제 방식, 또는 서버 런타임 env. 번들을 고르면 Web 환경이 Host flavor에 묶인다.
- **dev 전용 네트워크 예외**: Android 네트워크 보안 설정(dev 주소만 cleartext)을 debug 소스셋에 두고, iOS ATS 예외도 dev 구성에만 두는 방식. 지금처럼 main에 두면 단순하지만 release에도 남는다.

## 확인하지 못한 것과 새로 생긴 질문

**확인하지 못한 것**

- iOS 시뮬레이터가 Mac의 `localhost`를 함께 쓴다는 Apple 공식 문서. 저장소에서 동작은 검증했다.
- iOS에서 Android In-App Updates에 해당하는 업데이트 강제 API. 찾지 못했다.
- 번들 Web을 사용자 정의 scheme(iOS)이나 `WebViewAssetLoader`(Android)로 띄웠을 때 Next.js 클라이언트 라우터의 RSC payload(`.txt`) 요청이 제대로 동작하는지, 어떤 Content-Type이 필요한지. 기기에서 시험하지 않았다.
- WKWebView가 사용자 정의 scheme 출처를 secure context로 보는지.
- Apple 2.5.2·4.2가 원격 Web을 쓰는 하이브리드 앱에 적용되는 방식에 대한 공식 해석.
- `cacheComponents`와 export를 함께 지원하는 PR [8]이 언제 안정판에 들어올지.
- 앱 업데이트 뒤에도 WebView의 HTTP 캐시가 유지되는지에 대한 플랫폼 문서.

**새로 생긴 질문**

1. 번들(B·D)을 고르면 가짜 API를 어디서 띄우고, cross-origin 쿠키 세션을 어떻게 유지하나? "가짜 API를 Next.js 안에" 범위 결정과 로그인·세션 설계(#42)를 함께 다시 봐야 한다.
2. Host가 Web에 알릴 버전 정보의 형태(버전 숫자 또는 Host 기능 목록)와 통로(User-Agent, 주입 전역, Call)를 Bridge 계약 형태(#39)에서 다룰지.
3. 최소 Host 버전의 원천(Web 코드, 원격 설정, 서버 응답)과 업데이트 안내를 Host 화면으로 할지 Web 화면으로 할지.
4. 로딩·오프라인·에러 화면을 Host 화면으로 그릴지, 번들 오류 페이지로 둘지("Not yet specified" 항목).
5. 옛 Host를 흉내 내 버전 어긋남을 시연하는 모드를 개발용 가짜 Host와 함께 설계할지.
6. 공유 링크 안내 페이지와 링크 검증 파일을 둘 서버가 Web 서버와 같은 Next 앱인지(#34·#45).

## 출처

1. Next.js Docs — Deploying: https://nextjs.org/docs/app/getting-started/deploying
2. Google Play Console Help — Device and Network Abuse: https://support.google.com/googleplay/android-developer/answer/9888379?hl=en
3. Apple — App Review Guidelines (2.5.2, 4.2): https://developer.apple.com/app-store/review/guidelines/
4. Capacitor Docs (v8) — Configuration: https://capacitorjs.com/docs/config
5. Capacitor 8.5.3 소스 — `cli/src/declarations.ts`(`server.hostname`, `iosScheme`, `androidScheme`, `url`, `cleartext`, `errorPath`): https://github.com/ionic-team/capacitor/blob/8.5.3/cli/src/declarations.ts#L574-L662
6. Next.js Docs — Static Exports: https://nextjs.org/docs/app/guides/static-exports
7. Next.js v16.4.0 소스 — `packages/next/src/export/index.ts`(PPR invariant): https://github.com/vercel/next.js/blob/v16.4.0/packages/next/src/export/index.ts#L903-L907
8. vercel/next.js PR #95485 — Support `output: 'export'` in Cache Components(열림, 미머지): https://github.com/vercel/next.js/pull/95485
9. vercel/next.js PR #94928 — [CC] Remove invariant breaking output: export(머지 없이 닫힘): https://github.com/vercel/next.js/pull/94928
10. Next.js Docs — trailingSlash: https://nextjs.org/docs/app/api-reference/config/next-config-js/trailingSlash
11. webview_flutter_android 4.14.1 소스 — `android_webview_controller.dart`(`loadFlutterAsset`): https://github.com/flutter/packages/blob/webview_flutter_android-v4.14.1/packages/webview_flutter/webview_flutter_android/lib/src/android_webview_controller.dart#L437-L451
12. webview_flutter_wkwebview 3.27.0 소스 — `WebViewProxyAPIDelegate.swift`(`loadFlutterAsset`): https://github.com/flutter/packages/blob/webview_flutter_wkwebview-v3.27.0/packages/webview_flutter/webview_flutter_wkwebview/darwin/webview_flutter_wkwebview/Sources/webview_flutter_wkwebview/WebViewProxyAPIDelegate.swift#L204-L219
13. flutter/flutter#27896 — [webview] Allow overriding responses to webview requests with local resources: https://github.com/flutter/flutter/issues/27896
14. Android Developers — Load in-app content: https://developer.android.com/develop/ui/views/layout/webapps/load-local-content
15. Apple Developer — `setURLSchemeHandler(_:forURLScheme:)`: https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/seturlschemehandler(_:forurlscheme:)
16. flutter_inappwebview Docs (6.x) — WebViewAssetLoader: https://inappwebview.dev/docs/webview/webview-asset-loader/
17. flutter_inappwebview 6.1.5 API — `InAppWebViewSettings.resourceCustomSchemes`: https://pub.dev/documentation/flutter_inappwebview/latest/flutter_inappwebview/InAppWebViewSettings/resourceCustomSchemes.html
18. flutter_inappwebview Docs (6.x) — InAppLocalhostServer: https://inappwebview.dev/docs/in-app-localhost-server/
19. pub.dev — flutter_inappwebview versions: https://pub.dev/packages/flutter_inappwebview/versions
20. Flutter Docs — Adding assets and images: https://docs.flutter.dev/ui/assets/assets-and-images
21. Android Developers — `CookieManager.setAcceptThirdPartyCookies`: https://developer.android.com/reference/android/webkit/CookieManager
22. WebKit Blog — App-Bound Domains (2020-06-26): https://webkit.org/blog/10882/app-bound-domains/
23. WebKit Blog — Full Third-Party Cookie Blocking and More (2020-03-24): https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/
24. webview_flutter 4.14.1 API — NavigationDelegate: https://pub.dev/documentation/webview_flutter/latest/webview_flutter/NavigationDelegate-class.html
25. Next.js Docs — useOffline (experimental config): https://nextjs.org/docs/app/api-reference/config/next-config-js/useOffline
26. Next.js Docs — Progressive Web Apps: https://nextjs.org/docs/app/guides/progressive-web-apps
27. Capacitor Docs (v8) — Capacitor Web API(`isPluginAvailable`): https://capacitorjs.com/docs/core-apis/web
28. Telegram — Telegram Mini Apps(`WebApp.version`, `isVersionAtLeast`): https://core.telegram.org/bots/webapps
29. JSON-RPC 2.0 Specification — Error object: https://www.jsonrpc.org/specification
30. Ionic Docs — Appflow Live Updates: https://ionic.io/docs/appflow/deploy/intro
31. Ionic Docs — `appflow live-update set-native-versions`: https://ionic.io/docs/appflow/cli/reference/appflow_live-update_set-native-versions
32. Expo Docs — Runtime versions and updates: https://docs.expo.dev/eas-update/runtime-versions/
33. webview_flutter 4.14.1 API — WebViewController: https://pub.dev/documentation/webview_flutter/latest/webview_flutter/WebViewController-class.html
34. Android Developers — In-app updates: https://developer.android.com/guide/playcore/in-app-updates
35. Apple Developer — SKStoreProductViewController: https://developer.apple.com/documentation/storekit/skstoreproductviewcontroller
36. Next.js Docs — Glossary(Version skew): https://nextjs.org/docs/app/glossary#version-skew
37. Next.js Docs — Self-Hosting(Caching, Build Cache, Version Skew): https://nextjs.org/docs/app/guides/self-hosting
38. Next.js Docs — deploymentId: https://nextjs.org/docs/app/api-reference/config/next-config-js/deploymentId
39. Next.js Docs — supportsImmutableAssets: https://nextjs.org/docs/app/api-reference/config/next-config-js/supportsImmutableAssets
40. RFC 9111 HTTP Caching — 5.2.2.10 s-maxage: https://www.rfc-editor.org/rfc/rfc9111#name-s-maxage
41. Android Developers — ServiceWorkerController: https://developer.android.com/reference/android/webkit/ServiceWorkerController
42. Apple Developer Forums — ServiceWorker Support in iOS WKWebView(Frameworks Engineer 답변, 2025-02): https://developer.apple.com/forums/thread/773539
43. WebKit Bugzilla — Bug 206741 WKWebView support for Service Workers: https://bugs.webkit.org/show_bug.cgi?id=206741
44. Flutter Docs — Set up Flutter flavors for Android: https://docs.flutter.dev/deployment/flavors
45. Flutter Docs — Set up Flutter flavors for iOS and macOS: https://docs.flutter.dev/deployment/flavors-ios
46. Flutter Docs — Flutter pubspec options(`flavors`, `default-flavor`): https://docs.flutter.dev/tools/pubspec
47. Dart Docs — Configuring apps with compilation environment declarations: https://dart.dev/libraries/core/environment-declarations
48. Flutter 3.47.7 소스 — `flutter_tools/lib/src/runner/flutter_command.dart`(`--dart-define-from-file`): https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_tools/lib/src/runner/flutter_command.dart#L800-L806
49. Next.js Docs — Environment Variables: https://nextjs.org/docs/app/guides/environment-variables
50. Next.js 예제 — with-docker-multi-env(v16.4.2): https://github.com/vercel/next.js/tree/v16.4.2/examples/with-docker-multi-env
51. Android Developers — Emulator network address space: https://developer.android.com/studio/run/emulator-networking-address
52. AOSP adb 소스 — `client/commandline.cpp`(`reverse` 도움말): https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/commandline.cpp
53. Apple Developer — NSAllowsLocalNetworking: https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking
54. Apple Developer — TN3179: Understanding local network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
55. Next.js Docs — allowedDevOrigins: https://nextjs.org/docs/app/api-reference/config/next-config-js/allowedDevOrigins
56. Android Developers — `<application>`(`android:usesCleartextTraffic`): https://developer.android.com/guide/topics/manifest/application-element
57. Android Developers — Network security configuration: https://developer.android.com/privacy-and-security/security-config
