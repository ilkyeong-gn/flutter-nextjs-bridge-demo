# 딥링크·알림 진입과 앱 열기 안내 조사

- 질문: [#34 딥링크·알림 진입과 앱 열기 안내 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/34)
- 조사일: 2026-10-19
- 확인한 버전: Flutter 3.47.7 stable(2026-10-08, Dart 3.13.5)과 같은 태그의 엔진 소스 [47], Xcode 27.0(27A266a), app_links 7.2.2, flutter_local_notifications 22.3.2, go_router 18.1.0, url_launcher 6.3.3, Android Developers 문서(2026-10-16 갱신본), Apple·Chrome 문서(2026-10-19 열람)

## 요약

- **실제 https 진입에는 공개 HTTPS 도메인, 검증 파일, 앱 쪽 선언이 모두 필요하다.** iOS Universal Links는 `/.well-known/apple-app-site-association`과 Associated Domains 엔타이틀먼트, Android App Links는 `/.well-known/assetlinks.json`과 `autoVerify` intent-filter가 필요하다 [1][10][12]. iOS의 Associated Domains 기능은 유료 프로그램(ADP·ADEP) 전용이라 무료 계정으로는 쓸 수 없다 [4][5]. Android는 계정 없이 디버그 서명 지문으로도 검증할 수 있지만 공개 도메인은 피할 수 없다 [12].
- **외부 계정·도메인 없이 재현할 수 있는 범위는 플랫폼마다 다르다.** iOS 시뮬레이터에서는 커스텀 스킴(`xcrun simctl openurl`), 로컬 알림, `xcrun simctl push`(payload 주입)까지 된다. https 링크로 앱이 열리는 Universal Link는 재현할 수 없다. Android 에뮬레이터에서는 커스텀 스킴과 https 링크 모두 `adb shell am start`(패키지 지정)나 `pm set-app-links`로 앱에 강제로 연결할 수 있어 처리 코드까지 재현된다. 빠지는 것은 도메인 검증뿐이다 [11][29][30].
- **콜드·웜 스타트에서 링크가 도착하는 지점이 다르다.** iOS(UIScene)는 콜드 스타트면 `scene(_:willConnectTo:options:)`, 웜 스타트면 `scene(_:continue:)`·`scene(_:openURLContexts:)`로 링크가 온다 [6][7]. Xcode 27부터 UIScene 채택이 필수다(Flutter 3.41+는 자동 이전) [15]. Android는 Activity를 시작한 Intent와 `onNewIntent()`다 [11][16].
- **Flutter에서 링크를 받는 길은 둘이다.** Flutter 기본 딥링크(3.27부터 기본 켜짐)는 링크를 Router 경로로 넘긴다 [18][19]. app_links는 기본 딥링크를 끈 뒤 원본 URI를 스트림으로 준다 [5][24]. 기본 딥링크는 iOS에서 첫 프레임을 최대 3초 기다리고, 실패하면 Universal Link를 iOS로 되돌린다(3.47.7) [20]. app_links 7.2.2는 Dart가 구독하기 전에 온 링크를 모두 모아 두었다가 첫 구독에 넘긴다 [24].
- **OS 알림은 "앱을 띄운 알림"과 "실행 중에 탭한 알림"을 다른 API로 준다** [25]. 링크 스트림까지 합치면 Host가 받는 입력은 셋이다. 이를 한곳에 모아, Web 화면이 준비될 때까지(WebView 로드, Bridge 준비, 세션 복원) 보관하는 단계가 필요하다.
- **외부 계정 없이 만들 수 있는 "가짜 알림"은 양 플랫폼 모두 로컬 알림이다.** `simctl push`는 계정 없이 원격 알림 모양의 payload를 넣을 수 있다. 다만 flutter_local_notifications는 자기가 만든 알림만 처리하므로, 탭이 Dart까지 오려면 별도 플랫폼 코드가 필요하다 [25][27].
- **앱이 없는 사용자용 안내 페이지의 1차 문서 관례**는 iOS의 Smart App Banner(App Store `app-id` 필수, 시뮬레이터에서는 표시되지 않음) [36]와 Android Chrome의 `intent://…;S.browser_fallback_url=…` 링크 [14]다. Universal Link는 같은 도메인 안에서 이동하면 Safari에 머문다. 그래서 "앱에서 열기" 버튼은 다른 서브도메인이나 커스텀 스킴이어야 한다 [3][8]. 스토어 등록이 없는 Reference App에서 스토어 링크와 배너는 자리표시자일 뿐이다. 설치 뒤 원래 링크로 이어 주던 Firebase Dynamic Links는 2025-08-25에 종료됐다 [40].
- **허용 목록 검증에 대한 플랫폼 요구는 일치한다.** Apple과 Android 모두 들어온 URL의 매개변수를 전부 검증하고, 잘못된 URL은 버리고, 링크로 민감한 동작을 하지 말라고 한다 [6][7][42]. Android 보안 문서는 URI를 파싱해 scheme과 host를 전체 일치로 비교하고 `startsWith`·`endsWith`·정규식 검사를 피하라고 한다 [43]. 플랫폼 설정(AASA `components`, intent-filter 경로)과 Host의 경로 패턴 표에서 두 번 거를 수 있다 [1][9][11].
- **허용 목록 밖 링크를 시스템 브라우저로 보낼 때 플랫폼 동작이 다르다.** iOS는 앱이 자기 Universal Link를 `open`해도 그 앱에서 열리지 않는다고 문서에 있다 [8]. Android는 그 도메인이 승인된 상태라면 같은 앱으로 되돌아올 수 있다(문서에서 추론, 미검증) [13].

## 상세

### 1. Universal Links·App Links의 요구 조건과 커스텀 스킴과의 차이

| 항목 | iOS Universal Links | Android App Links | 커스텀 스킴(예: `fanapp://`) |
|---|---|---|---|
| 웹 쪽 파일 | `https://<도메인>/.well-known/apple-app-site-association`. 확장자 없음, 유효한 인증서, 리디렉션 금지 [1] | `https://<호스트>/.well-known/assetlinks.json`. `application/json`, HTTPS, 리디렉션 금지 [12] | 없음 |
| 앱 쪽 선언 | `com.apple.developer.associated-domains` 엔타이틀먼트에 `applinks:<도메인>` [1][2] | `android:autoVerify="true"`인 intent-filter(VIEW, DEFAULT·BROWSABLE, http/https, host) [10] | iOS Info.plist의 URL Types [7], Android intent-filter의 `android:scheme` [11] |
| 파일에 적는 앱 식별자 | `<Team ID>.<Bundle ID>` [1][5] | 패키지 이름과 서명 인증서 SHA-256 지문. 디버그·릴리스용 지문을 여러 개 넣을 수 있다 [12] | — |
| 필요한 계정 | Associated domains 기능은 ADP·ADEP에만 있고 무료 "Apple Developer"에는 없다 [4]. Flutter 문서도 Personal Team은 이 기능을 지원하지 않는다고 적는다 [5] | 계정이 필요 없다. Play App Signing을 쓰면 실제 지문을 Play Console에서 확인한다 [12] | 필요 없음 |
| 검증 주체와 시점 | iOS 14+는 Apple CDN이 파일을 가져간다. CDN은 24시간 안에 요청하고, 기기는 설치 뒤 대략 주 1회 갱신한다 [1]. 모든 IP와 User-Agent에서 접근할 수 있어야 한다 [3] | 설치 시 기기가 확인한다(최소 20초 대기). Android 15+는 주기적으로 재검증하며 반영에 최대 7일이 걸린다 [10]. Google 서비스가 있는 기기에서만 동작한다 [9] | 없음 |
| 앱이 없을 때 | 기본 브라우저가 URL을 연다 [8] | 웹사이트로 간다 [9] | 처리할 앱이 없다. 웹 폴백을 하려면 Chrome `intent://` 폴백 같은 장치가 따로 필요하다 [14] |
| 다른 앱의 가로채기 | 파일로 검증된 앱만 연결된다 [8] | 도메인 소유 검증으로 막는다 [9] | 다른 앱도 같은 스킴을 등록할 수 있고, iOS에서 여러 앱이 등록하면 어느 앱이 열릴지 정해져 있지 않다 [7]. Android에서는 선택 대화상자가 뜰 수 있다 [11] |

덧붙일 사실:

- **포트와 서브도메인**: `applinks:example.com:8080`처럼 포트가 붙은 도메인은 앱을 열지 않는다 [3]. 서브도메인마다 엔타이틀먼트 항목과 파일이 따로 필요하다 [1]. 따라서 `localhost:3000` 같은 로컬 Next.js 개발 서버는 Universal Link 도메인이 될 수 없다.
- **개발용 우회(developer mode)**: 엔타이틀먼트에 `?mode=developer`를 붙이면 CDN을 거치지 않고 서버에 직접 접속한다. 이때는 시스템이 신뢰하지 않는 인증서도 쓸 수 있다. 단 개발 프로파일로 서명한 앱에서만 동작하고, 사용자가 기기마다 직접 켜야 한다 [2][3]. 개발 프로파일 서명에는 팀이 필요하고 무료 팀은 Associated Domains를 쓸 수 없으므로 [4][5], 이 우회도 유료 계정이 있어야 쓸 수 있다.
- **Android 12+의 https 링크**: 승인되지 않은 도메인의 일반 web intent는 앱이 아니라 기본 브라우저로 간다 [13]. 승인은 App Links 검증이나 사용자의 "기본으로 열기" 설정으로 얻는다 [10][13]. 검증되지 않은 https 링크는 Android에서도 앱을 열지 않는다는 뜻이다.
- **Android 15+ Dynamic App Links**: assetlinks.json의 `dynamic_app_link_components`로 경로·쿼리·프래그먼트 규칙과 제외 규칙을 서버에서 바꿀 수 있다. 다만 manifest intent-filter의 범위를 넓히지는 못한다 [9][12].
- **Flutter 설정**: Flutter 3.27부터 기본 딥링크가 켜져 있다. app_links 같은 서드파티 플러그인을 쓰려면 iOS `FlutterDeepLinkingEnabled`와 Android `flutter_deeplinking_enabled`를 `false`로 꺼야 한다 [18][5][29].

### 2. 콜드·웜 스타트에서 링크를 받아 Web 경로로 보내는 처리

#### 2.1 플랫폼이 링크를 건네는 지점

| | 콜드 스타트(앱이 꺼져 있음) | 웜 스타트(실행 중·백그라운드) |
|---|---|---|
| iOS Universal Link(UIScene) | `scene(_:willConnectTo:options:)`의 `connectionOptions.userActivities` [6] | `scene(_:continue:)` [6] |
| iOS 커스텀 스킴(UIScene) | `connectionOptions.urlContexts` [7] | `scene(_:openURLContexts:)` [7] |
| Android | Activity를 시작한 Intent의 data(`onCreate()` 등에서 `getIntent()`) [11] | `launchMode="singleTop"`이고 Activity가 맨 위에 있으면 `onNewIntent()` [16]. Flutter 앱 템플릿은 `singleTop`이다 [17] |
| iOS OS 알림 | `UNUserNotificationCenter` delegate를 앱 실행이 끝나기 전에 지정해야 알림을 놓치지 않는다 [26] | 같은 delegate |

Flutter 문서에 따르면 Xcode 27(iOS 27 SDK)부터 UIScene을 채택하지 않은 UIKit 앱은 실행되지 않는다. Flutter 3.41부터 UIScene이 기본이고, 수정하지 않은 `AppDelegate`는 자동으로 이전된다 [15]. 이전한 뒤에는 `application(_:didFinishLaunchingWithOptions:)`의 launch options가 `nil`이므로, launch options에서 링크를 읽던 코드는 scene 이벤트로 옮겨야 한다 [15]. 이 저장소의 개발 환경도 Xcode 27.0이므로 Reference App은 UIScene을 전제로 한다.

#### 2.2 Flutter에서 링크를 받는 두 가지 길

**(가) Flutter 기본 딥링크 + Router(go_router)**

- 플랫폼별 동작: iOS 콜드 스타트는 먼저 `/`로 시작하고 잠시 뒤 링크 경로가 들어온다. Android 콜드 스타트는 처음부터 링크 경로가 initialRoute로 들어온다. 실행 중이면 두 플랫폼 모두 경로를 다시 파싱한다 [19].
- 엔진은 경로만이 아니라 전체 URL 문자열을 넘긴다(iOS `url.absoluteString`, Android `data.toString()`) [20][21].
- iOS 엔진은 링크를 넘기기 전에 첫 프레임을 최대 3초 기다린다. 시간을 넘기거나 프레임워크가 처리하지 못하면, 3.47.7은 Universal Link와 콜드 스타트 URL을 `openURL`로 iOS에 되돌린다(웜 스타트 커스텀 스킴은 되돌리지 않는다) [20]. 앱이 자기 Universal Link를 `open`하면 그 앱에서 열리지 않으므로 [8], 사용자는 브라우저로 넘어갈 것으로 보인다(추론). 같은 파일의 master(2026-10-16)는 되돌리지 않고 무시하도록 바뀌어 있어, 다음 stable에서 동작이 달라질 수 있다 [20].
- go_router는 URL 경로를 기준으로 화면을 고른다 [22]. 18.x의 `onEnter`는 딥링크를 포함한 모든 이동을 redirect보다 먼저 검사한다. 첫 진입 딥링크를 막으면 `BlockedInitialNavigationException`을 `onException`으로 넘긴다 [22].

**(나) app_links 7.2.2**

- Flutter 기본 딥링크를 꺼야 한다. Flutter 문서는 기본 딥링크를 켜 두면 이런 플러그인이 깨진다고 적는다 [5][18][23].
- `AppLinks()`를 앱 초기에 만들어야 콜드 스타트 링크를 잡는다. `uriLinkStream` 하나로 첫 링크와 이후 링크를 모두 받는다 [24]. 6.0.2 변경 기록은 이 플러그인을 Flutter·go_router 딥링크와 함께 쓸 이유가 없다고 적는다 [24].
- 7.2.2는 첫 구독 전에 받은 링크를 첫 번째만이 아니라 모두 넘기도록 고쳤다. Android에서는 Activity가 다시 만들어질 때 시작 링크를 다시 보내지 않는다 [24]. 소스를 보면 최근 앱 목록에서 다시 연 Intent(`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`)는 무시한다 [24].
- 소스상 버퍼는 첫 구독 전에만 쓰인다. 한 번 구독한 뒤에 구독자가 없는 동안 온 링크는 버려진다(iOS `listenedOnce`, Android `pendingLinks = null`) [24]. 앱 수명 동안 유지되는 구독 하나를 Host 최상단에 두어야 하는 이유다.
- 7.0.0부터 UIScene 이벤트(`willConnectTo`, `openURLContexts`, `continue`)를 직접 받는다 [24][23].

**(다) OS 알림 탭: flutter_local_notifications 22.3.2**

- README는 `onDidReceiveNotificationResponse`가 앱이 실행 중일 때만 쓰인다고 못 박는다. 알림이 앱을 띄운 경우는 시작 시 `getNotificationAppLaunchDetails()`로 확인해야 한다 [25].
- iOS 플러그인은 Dart가 `initialize()`를 부르기 전에 온 탭을 launch details로 보관한다. Android에서 알림 탭 Intent의 action은 `SELECT_NOTIFICATION`이고 payload를 extra로 싣는다 [25]. 이 Intent에는 data URI가 없으므로 app_links 스트림에는 나타나지 않는다. app_links는 Intent의 data 문자열만 읽는다 [24][25].
- iOS에서는 `application(_:didFinishLaunchingWithOptions:)`에서 `UNUserNotificationCenter` delegate를 지정하라고 한다 [25]. Flutter의 UIScene 문서도 이 delegate를 앱 실행이 끝나기 전에 설정해야 하는 API로 꼽는다 [15].

#### 2.3 초기화가 끝나기 전에 도착한 링크

링크가 너무 일찍 도착하는 틈은 세 곳이다.

1. **플랫폼에서 Dart로**: app_links는 첫 구독 전에 온 링크를 모아 두고 [24], flutter_local_notifications는 `initialize()` 전에 온 탭을 launch details로 남긴다 [25]. Flutter 기본 딥링크에는 iOS 첫 프레임 3초 제한이 있다 [20]. 세션 복원 등으로 첫 프레임을 늦추면 이 제한에 걸릴 수 있다.
2. **Host에서 Web 화면으로**: WebView가 아직 없거나, 페이지가 로드 중이거나, Bridge가 준비되지 않았을 수 있다. Event는 응답 없는 Message이므로(GLOSSARY 정의) Host는 Web이 받았는지 알 수 없다. 순서를 보장하려면 Web이 준비됐다는 신호가 있거나, Web이 준비된 뒤 Host에 묻는 Call이 있어야 한다.
3. **앱 상태**: 세션 복원이 끝나지 않았거나 대상 화면이 로그인을 요구할 수 있다(S1과 겹침). Android 보안 문서는 민감한 정보를 보여 주기 전에 인증 상태 같은 내부 상태를 확인하라고 한다 [42].

### 3. 외부 계정 없이 시뮬레이터·에뮬레이터에서 재현하는 방법

| 시나리오 | iOS 시뮬레이터 | Android 에뮬레이터 |
|---|---|---|
| 커스텀 스킴, 웜 스타트 | ✔ `xcrun simctl openurl booted "fanapp://posts/123"` [27][23] | ✔ `adb shell am start -W -a android.intent.action.VIEW -d "fanapp://posts/123" <패키지>` [11] |
| 커스텀 스킴, 콜드 스타트 | ✔ `xcrun simctl terminate booted <번들 ID>`를 먼저 실행 [27] | ✔ 위 명령에 `-S`(시작 전 강제 종료) 추가 [28] |
| https 링크로 앱의 처리 코드 실행 | ✘ Associated Domains를 쓸 수 없어 연결이 성립하지 않는다 [4][5] | ✔ 패키지를 지정한 `am start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "https://fan.example/posts/123" <패키지>`는 웹 파일이 없어도 앱을 띄운다(앱 설정만 시험) [29]. 또는 `adb shell pm set-app-links --package <패키지> 2 fan.example`(항상 승인)이나 `adb shell pm set-app-links-user-selection --user cur --package <패키지> true fan.example`로 승인 상태를 만든 뒤 일반 링크로 연다 [30][10] |
| https 도메인 검증까지 | ✘ 유료 팀과 공개 HTTPS 도메인이 필요하다 [1][4]. 2026년 1월 Apple DTS 엔지니어는 시뮬레이터에서 AASA 동작을 일관되게 확인하기 어려워 실기기를 주로 쓴다고 답했다 [31] | ✘ 공개 HTTPS 도메인, 인터넷, Google 서비스가 든 이미지가 필요하다 [9][10] |
| 로컬 알림 탭, 콜드·웜 스타트 | ✔ flutter_local_notifications. 알림 권한 승인이 필요하다 [25] | ✔ 같은 플러그인. Android 13+는 `POST_NOTIFICATIONS` 런타임 권한이 필요하다 [32] |
| 원격 푸시 모양의 payload | △ `xcrun simctl push booted <번들 ID> payload.json`. 최상위 객체, `aps` 키 필수, 4096바이트 이하, 앱 원격 알림만 지원 [27][33]. Notification Service Extension은 동작하지 않는다 [33][35]. flutter_local_notifications는 자기 키가 없는 알림을 무시하므로, Dart까지 오려면 별도 플랫폼 코드가 필요하다 [25] | △ 계정 없이 원격 푸시를 받을 방법은 없다. `adb shell cmd notification post -c activity <am start 인자> <tag> <text>`로 셸이 알림을 올리고, 탭하면 지정한 Intent가 실행되게 할 수 있다(AOSP main 소스 기준, 실행해 보지 않음) [34] |
| 실제 원격 푸시 | ✘ 시뮬레이터는 Apple silicon·T2 Mac에서 APNs sandbox 알림을 받을 수 있다 [35]. 하지만 Push Notifications 기능이 무료 계정에 없다 [4] | ✘ FCM 같은 외부 계정이 필요하다(지도 범위 밖) |
| Smart App Banner | ✘ 시뮬레이터에서는 배너가 나타나지 않고, App Store 앱 ID가 필요하다 [36] | 해당 없음 |

- Android 검증 상태는 `adb shell pm get-app-links <패키지>`로 확인한다 [10]. Android 17부터는 `am start --debug-link`로 어떤 intent-filter와 규칙이 매칭됐는지 볼 수 있다 [37][28]. `pm set-app-links`는 패키지가 `autoVerify`로 선언한 도메인에만, `set-app-links-user-selection`은 패키지가 선언한 도메인에만 적용된다 [30]. app_links 문서도 Android 13 이상에서는 개발 중에 앱 정보 > "기본으로 열기"에서 링크를 직접 켜야 할 수 있다고 적는다 [23].
- adb로 넘기는 URI의 특수문자(`&` 등)는 이스케이프해야 한다 [11][23].
- flutter_local_notifications의 Android 탭 Intent(`SELECT_NOTIFICATION` action과 `payload` extra)를 `am start`로 흉내 내면 알림 없이도 탭 경로를 시험할 수 있다. iOS에서도 `simctl push` payload에 플러그인의 userInfo 키(`NotificationId`, `presentAlert`, `presentSound`, `presentBadge`, `payload`)를 넣으면 플러그인이 자기 알림으로 취급할 것으로 보인다. 두 방법 모두 플러그인 내부 상수에 기대므로 버전이 바뀌면 깨질 수 있다 [25].
- 실기기 iOS 14+에서는 debug 빌드를 Flutter 도구 밖(홈 화면 등)에서 실행하면 크래시가 나는 이슈가 열려 있다 [46]. app_links는 이 상황에서 등록을 건너뛰고 경고만 출력한다 [24]. 콜드 스타트를 시험할 때는 실행 경로에 주의해야 한다. 시뮬레이터에도 해당하는지는 아래 "확인하지 못한 것"에 적었다.

### 4. 앱이 없는 사용자를 위한 "앱에서 열기·설치" 안내 페이지 관례

**iOS**

- Smart App Banner: 페이지 `head`에 `<meta name="apple-itunes-app" content="app-id=…, app-argument=…">`를 넣는다. `app-id`(App Store 앱 ID)는 필수고, `app-argument`는 앱에 넘길 URL이다. 앱이 설치돼 있으면 배너를 눌렀을 때 앱이 열리고, 없으면 App Store로 간다. 프레임 안에서는 표시되지 않고, 시뮬레이터에서는 나타나지 않는다 [36].
- Safari에서 Universal Link가 동작하는 방식: 주소창에 직접 입력한 URL은 앱을 열지 않는다. 사용자가 직접 들어와 그 도메인에 머무는 동안에는 사이트에 앱을 여는 배너가 표시된다 [3]. 같은 도메인 안에서 누른 Universal Link는 Safari에 머무르므로, 웹에서 앱으로 넘기려면 다른 서브도메인의 링크를 써야 한다 [3][8]. 서드파티 브라우저는 Universal Link를 지원하지 않을 수 있다 [3]. 사용자가 링크를 길게 눌러 브라우저로 열기를 고르면 그 도메인의 기본 동작으로 기억된다 [3].

**Android**

- Chrome의 `intent:` URL: `intent://posts/123#Intent;scheme=fanapp;package=<패키지>;S.browser_fallback_url=<인코딩된 URL>;end` 형태다. 앱이 없거나 Intent를 처리할 수 없으면 폴백 URL로 보낸다. 사용자 제스처 없이 JavaScript 타이머로 열거나, 주소창 입력에서 리디렉션된 경우에는 앱을 띄우지 않는다. BROWSABLE 카테고리가 있는 Activity만 열 수 있다 [14].
- 설치 여부 확인: Android Chrome 80+는 `navigator.getInstalledRelatedApps()`로 관련 앱이 설치됐는지 확인할 수 있다. 앱 manifest의 `asset_statements`와 웹 앱 manifest의 `related_applications`가 서로를 가리켜야 하고, HTTPS에서만 동작한다 [38].
- Chrome의 Native App Install Prompt(웹 앱 manifest의 `prefer_related_applications`와 `related_applications`)로 Play 스토어 설치를 띄울 수 있지만 Play 앱 ID가 필요하다. 근거 문서가 2014년 Chrome 블로그라 현재 동작은 따로 확인해야 한다 [39].

**공통**

- 스토어 이동: App Store 링크는 앱 ID로 [36], Play 링크는 `https://play.google.com/store/apps/details?id=<패키지>` 형태로 [38] 만든다. 스토어 등록이 없는 Reference App에서는 둘 다 자리표시자다.
- 설치 뒤 원래 콘텐츠로 이어 주기(deferred deep link): 이 일을 주로 맡던 Firebase Dynamic Links는 2025-08-25에 종료됐다. Firebase는 생태계 변화로 설치 후 이어 주기를 일관되게 제공하기 어려워졌다고 설명한다 [40]. Android에는 Play 설치 경로를 알려 주는 Install Referrer API가 있지만 Play 배포가 전제다 [41].

### 5. 들어온 링크를 허용 목록으로 검증하는 방법

**플랫폼의 요구**

- Apple: Universal Link와 커스텀 스킴 모두 공격 경로가 될 수 있다. 모든 URL 매개변수를 검증하고, 잘못된 URL은 버리고, 링크로 콘텐츠 삭제나 민감 정보 접근 같은 동작을 허용하지 말라고 한다. 테스트에는 잘못된 형식의 URL을 넣으라고 한다 [6][7].
- Android: 들어온 매개변수를 모두 미리 정한 허용 목록과 비교하고, 민감한 정보를 보여 주기 전에 인증·권한 상태를 확인하라고 한다 [42]. WebView에 URI를 싣기 전에는 문자열을 URI로 파싱해 scheme과 host를 모두 검증해야 한다. host는 전체 일치로 비교하고, `startsWith`·`endsWith`·`contains`로 부분 비교하거나 정규식을 쓰지 말라고 한다 [43].

**거르는 층**

1. **OS 설정**: AASA `components`로 경로·쿼리·프래그먼트를 고르고 `exclude`로 제외한다 [1]. Android intent-filter의 host와 `pathPrefix` 등으로 범위를 정한다. 한 intent-filter에 `<data>`를 여러 개 넣으면 속성이 조합으로 합쳐지므로 URL마다 필터를 나눠야 한다 [11]. Android 15+는 Dynamic App Links로 서버에서 제외 규칙을 더할 수 있다 [9].
2. **Host**: 다음 순서로 거른다.
   1. URI로 파싱한다.
   2. scheme(`https`·`fanapp`)과 host(`fan.example`)를 전체 일치로 비교한다.
   3. 경로 패턴 표(예: `/posts/{숫자}`, `/artists/{숫자}`, `/community`)와 맞춘다.
   4. 쿼리 매개변수를 허용 목록으로 거른다.
   5. 신뢰하는 Web 기준 URL과 검증된 경로를 합쳐 WebView에 실을 URL을 만든다. 들어온 URL을 그대로 싣지 않는 것이 [43]의 취지에 맞는다.
3. **Web**: 경로 매개변수를 다시 검증하고 접근 권한을 확인한다 [42].

**관련 변화**

- Flutter 3.50.0-0.1.pre에 들어간 변경으로, release 빌드의 Android 임베더는 외부 Intent가 준 `route` 등의 extra를 무시하고, 딥링크는 manifest intent-filter와 일치할 때만 받는다. 현재 stable(3.47.7)에는 아직 들어오지 않았다 [44][21].

**허용 목록 밖 링크**

- url_launcher의 `LaunchMode.externalApplication`은 URL을 OS에 넘겨 다른 앱이 처리하게 한다 [45].
- iOS: Apple 문서에 따르면 앱이 자기 웹사이트의 Universal Link를 `open`으로 열면 그 앱에서 열리지 않는다 [8].
- Android: 앱이 그 도메인에 승인된 상태라면 일반 web intent가 그 앱의 Activity로 풀린다 [13]. 그래서 같은 도메인의 허용 목록 밖 경로를 외부로 보내면 다시 앱으로 돌아올 수 있다(추론, 미검증). intent-filter 경로를 허용 목록에 맞춰 좁히는 방법이 있다.

## Reference App에 주는 시사점

「딥링크·알림 진입 설계 (S3)」(#45)가 따질 선택지와 trade-off를 정리한다. 여기서는 고르지 않는다.

1. **링크 수신 방식**
   - (a) Flutter 기본 딥링크 + go_router: 추가 플러그인 없이 `onEnter`·`redirect`로 링크를 막을 수 있다 [22]. 대신 링크가 곧 Host Router의 경로가 되므로 Web 경로와 Host 경로를 한 표로 관리해야 한다. iOS 첫 프레임 3초 제한이 있고, 처리에 실패했을 때의 동작이 버전마다 다르다 [20].
   - (b) app_links + Host의 진입 조정 모듈: 원본 URI를 받아 허용 목록, 대기, 전달을 한곳에서 다루고, 첫 구독 전 링크를 버퍼링한다 [24]. 기본 딥링크를 꺼야 하고, 플러그인 의존이 하나 늘며, 구독을 앱 수명 동안 유지해야 한다 [24].
2. **링크 URL 모양과 도메인**
   - (a) 공유 링크 경로 = Web 경로(같은 origin): 변환이 단순하고, 브라우저로 열리면 같은 URL에서 안내 페이지를 보여 줄 수 있다. 그러나 안내 페이지의 "앱에서 열기"가 같은 도메인 링크면 iOS에서는 Safari에 머문다 [3].
   - (b) 링크 전용 서브도메인: 안내 페이지에서 앱으로 넘어가기 쉽다. 대신 도메인과 검증 파일이 늘고 경로 변환 표가 필요하다 [1][3].
   - (c) 커스텀 스킴 병행: 계정·도메인 없이 iOS에서 재현할 수 있는 유일한 경로다 [4][27]. 다른 앱이 같은 스킴을 쓸 수 있으므로 [7] https와 똑같이 허용 목록으로 검증해야 한다.
3. **Web 화면으로 전달하는 방식**
   - 콜드 스타트: 첫 WebView URL을 링크 대상으로 정하면 Bridge 없이 끝난다.
   - 웜 스타트 (a) 기존 WebView에 `loadUrl`: 단순하지만 Web 상태(스크롤, 작성 중인 내용)를 잃는다.
   - 웜 스타트 (b) Host가 Event를 보내 Web이 클라이언트 라우팅: 상태가 남지만 Bridge 준비 확인과 계약 항목이 필요하다.
   - 웜 스타트 (c) 새 Web 화면을 스택에 올림: 뒤로 가기로 이전 화면에 돌아갈 수 있지만 WebView가 하나 더 생긴다.
   - 어느 쪽이든 위에 Host 화면(S5의 메시지 화면 등)이 떠 있을 때의 정리 규칙을 함께 정해야 한다.
4. **초기화 전 링크 보관**
   - 대기 슬롯 하나(마지막 링크가 이김)로 할지, 큐로 할지 정한다.
   - 언제 꺼낼지 정한다: Host 초기화, 세션 복원, WebView 로드, Bridge 준비 중 어느 시점인지.
   - Host가 Event로 밀어 넣을지, Web이 준비된 뒤 Call로 가져갈지 정한다. Call은 응답이 있어 준비 순서 문제를 피하지만 Web에 진입 처리 코드가 생긴다.
   - 로그인이 필요한 대상(S1)이면 대기 링크를 로그인 뒤 복귀 대상으로 넘길지 정한다.
5. **알림 payload와 가짜 알림**
   - payload에 공유 링크와 같은 https URL을 담으면 링크와 같은 허용 목록과 전달 경로를 쓸 수 있다. 타입별 데이터(`{type, id}`)를 담으면 Host가 변환해야 하지만 payload가 짧아진다.
   - 가짜 알림을 어디서 발생시킬지 정한다: Host 디버그 메뉴, Web의 Call, 지연 예약(앱을 종료한 뒤 콜드 스타트 시험용) 중에서.
   - `simctl push`까지 지원하려면 원격 알림 탭을 받는 플랫폼 코드가 따로 필요하다 [25][27].
6. **허용 목록의 위치와 공유**
   - Host에서만 검증할지, Host와 Web 양쪽에서 검증할지 정한다.
   - 경로 패턴 표를 Web 라우트와 한곳에서 관리할지 정한다(계약 공유 위치와 연결된다).
   - 허용 목록 밖 https는 외부 브라우저로, 커스텀 스킴은 무시하고 홈으로 보낼지 정한다.
   - Android 자기 루프 가능성 때문에 intent-filter 경로를 표에 맞출지 정한다.
7. **안내 페이지 구성**
   - 같은 URL에서 Host 안팎을 구분해 그릴지(서버에서 UA·헤더로, 또는 클라이언트에서 Bridge 존재로), 별도 경로로 보낼지 정한다.
   - iOS "앱에서 열기" 버튼: 커스텀 스킴은 재현할 수 있지만 앱이 없으면 열 곳이 없다. 다른 서브도메인 Universal Link는 재현할 수 없다.
   - Android는 `intent://`와 폴백을 쓸지 [14], 설치 확인에 `getInstalledRelatedApps()`를 쓸지 정한다 [38].
   - Smart App Banner 메타 태그와 스토어 링크는 넣더라도 동작하지 않는 자리표시자다 [36].
8. **검증 파일과 설정을 "형태만" 넣을지**
   - Next.js에서 AASA와 assetlinks.json을 서빙하고 엔타이틀먼트와 `autoVerify` 필터를 넣어 두면, 실제 앱에 옮길 형태를 보여 줄 수 있다.
   - 하지만 Reference App 환경에서는 검증되지 않는 설정이 된다. Personal Team은 Associated Domains를 지원하지 않으므로 [5], 엔타이틀먼트를 넣으면 무료 계정 빌드에 영향을 줄 수 있다(시뮬레이터 빌드 영향은 미확인).
9. **재현 범위 문서화**: iOS는 커스텀 스킴과 로컬 알림까지, Android는 https 강제 연결까지라는 비대칭을 README와 테스트 시나리오에 적을지, 어떤 시나리오를 자동 테스트로 돌릴지 정한다.

## 확인하지 못한 것과 새로 생긴 질문

**확인하지 못한 것**

- 팀 없이 서명한 시뮬레이터 빌드가 `com.apple.developer.associated-domains` 엔타이틀먼트를 인정하는지, 시뮬레이터에서 developer mode(Associated Domains Development)를 켤 수 있는지. 1차 문서에서 찾지 못했다. DTS 엔지니어도 시뮬레이터 동작이 일관되지 않다고 답했다 [31].
- `xcrun simctl push`가 push 엔타이틀먼트 없이도 알림 표시와 탭 이벤트까지 전달하는지. 릴리스 노트와 `simctl help`에 조건이 적혀 있지 않다 [27][33].
- `adb shell cmd notification post -c activity …`가 에뮬레이터의 Android 버전에서 동작하는지. AOSP main 소스만 확인했다 [34].
- Android에서 승인된 도메인의 허용 목록 밖 링크를 외부로 열 때 앱 자신으로 돌아오는지. 문서에서 추론했을 뿐이다 [13].
- Host의 WKWebView 안에서 Web이 링크 도메인 URL로 이동할 때 Universal Link로 처리되는지. Apple 문서는 WKWebView 안에서 누른 링크도 Universal Link로 앱을 연다고만 한다 [8].
- Flutter debug 빌드를 시뮬레이터에서 Flutter 도구 밖으로(`simctl openurl`로) 콜드 스타트할 때 플러그인이 정상 등록되는지. 실기기 iOS 14+ 문제는 열려 있다 [46].
- `getInstalledRelatedApps()`를 에뮬레이터와 로컬 개발 서버에서 재현할 수 있는지(HTTPS 요구) [38].
- Flutter master의 iOS 딥링크 실패 처리 변경 [20]과 Android Intent 검증 강화 [44]가 어느 stable 버전에 들어오는지.

**새로 생긴 질문**

- Host 기능인 공유가 만드는 링크 형식과 허용 목록 경로 표는 누가 소유하나(계약 공유 위치와 연결).
- 링크가 도착했을 때 위에 Host 화면이 있거나 Web에서 글을 쓰는 중이면(S2의 이탈 확인) 화면 스택을 어떻게 정리하나.
- 가짜 알림은 누가 어떻게 만들고, 알림 권한은 언제 요청하나. iOS 27에서는 권한 없이 `show()`를 부르면 예외가 났고, 22.3.2에서 이전 동작으로 되돌렸다 [25].
- 안내 페이지와 개발용 가짜 Host 모드가 "브라우저에서 열린 Web"을 판별하는 같은 로직을 쓰는가.

## 출처

1. [Supporting associated domains — Apple Developer Documentation](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
2. [Associated Domains Entitlement — Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.associated-domains)
3. [TN3155: Debugging universal links — Apple Developer Documentation](https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links) (2025-05-15 개정판)
4. [Supported capabilities (iOS) — Apple Developer Account Help](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
5. [Set up universal links for iOS — Flutter docs](https://docs.flutter.dev/cookbook/navigation/set-up-universal-links)
6. [Supporting universal links in your app — Apple Developer Documentation](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)
7. [Defining a custom URL scheme for your app — Apple Developer Documentation](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)
8. [Allowing apps and websites to link to your content — Apple Developer Documentation](https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content)
9. [About App Links — Android Developers](https://developer.android.com/training/app-links/about)
10. [Verify App Links — Android Developers](https://developer.android.com/training/app-links/verify-applinks)
11. [Create deep links — Android Developers](https://developer.android.com/training/app-links/create-deeplinks)
12. [Configure website associations and dynamic rules — Android Developers](https://developer.android.com/training/app-links/configure-assetlinks)
13. [Behavior changes: all apps (Android 12), Web intent resolution — Android Developers](https://developer.android.com/about/versions/12/behavior-changes-all#web-intent-resolution)
14. [Android Intents with Chrome — Chrome for Developers](https://developer.chrome.com/docs/android/intents)
15. [UIScene adoption — Flutter docs (breaking changes)](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)
16. [Tasks and the back stack — Android Developers](https://developer.android.com/guide/components/activities/tasks-and-back-stack)
17. [AndroidManifest.xml.tmpl, Flutter app template (tag 3.47.7) — flutter/flutter](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_tools/templates/app/android.tmpl/app/src/main/AndroidManifest.xml.tmpl)
18. [Deep links flag change — Flutter docs (breaking changes)](https://docs.flutter.dev/release/breaking-changes/deep-links-flag-change)
19. [Deep linking — Flutter docs](https://docs.flutter.dev/ui/navigation/deep-linking)
20. Flutter iOS 엔진 소스 — flutter/flutter: [FlutterEngine.mm (tag 3.47.7)](https://github.com/flutter/flutter/blob/3.47.7/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm), [FlutterSceneLifeCycle.mm (tag 3.47.7)](https://github.com/flutter/flutter/blob/3.47.7/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterSceneLifeCycle.mm), [FlutterSceneLifeCycle.mm (master, 2026-10-16)](https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterSceneLifeCycle.mm)
21. [FlutterActivityAndFragmentDelegate.java (tag 3.47.7) — flutter/flutter](https://github.com/flutter/flutter/blob/3.47.7/engine/src/flutter/shell/platform/android/io/flutter/embedding/android/FlutterActivityAndFragmentDelegate.java)
22. go_router 18.1.0: [Deep linking topic](https://pub.dev/documentation/go_router/latest/topics/Deep%20linking-topic.html), [RoutingConfig.onEnter API](https://pub.dev/documentation/go_router/latest/go_router/RoutingConfig/onEnter.html), [패키지 18.1.0](https://pub.dev/packages/go_router/versions/18.1.0)
23. app_links 설정 문서: [README_ios_7.md](https://github.com/llfbandit/app_links/blob/main/doc/README_ios_7.md), [README_android.md](https://github.com/llfbandit/app_links/blob/main/doc/README_android.md)
24. [app_links 7.2.2 — pub.dev](https://pub.dev/packages/app_links/versions/7.2.2) (README, CHANGELOG, `AppLinksIosPlugin.swift`·`AppLinksPlugin.java`·`AppLinksHelper.java` 소스)
25. [flutter_local_notifications 22.3.2 — pub.dev](https://pub.dev/packages/flutter_local_notifications/versions/22.3.2) (README, CHANGELOG, iOS `FlutterLocalNotificationsPlugin.m`·Android `FlutterLocalNotificationsPlugin.java` 소스)
26. [UNUserNotificationCenterDelegate — Apple Developer Documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate)
27. Xcode 27.0(27A266a)의 `xcrun simctl help openurl`, `help push`, `help terminate` 출력(로컬에서 확인, 웹 URL 없음)
28. [Android Debug Bridge (adb) — Android Developers](https://developer.android.com/tools/adb)
29. [Set up app links for Android — Flutter docs](https://docs.flutter.dev/cookbook/navigation/set-up-app-links)
30. [DomainVerificationShell.java — AOSP frameworks/base (main)](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/pm/verify/domain/DomainVerificationShell.java)
31. [Universal Links are not working in the Xcode 26 simulators — Apple Developer Forums](https://developer.apple.com/forums/thread/812475)
32. [Notification runtime permission — Android Developers](https://developer.android.com/develop/ui/views/notifications/notification-permission)
33. [Xcode 11.4 Release Notes — Apple Developer Documentation](https://developer.apple.com/documentation/xcode-release-notes/xcode-11_4-release-notes)
34. [NotificationShellCmd.java — AOSP frameworks/base (main)](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/notification/NotificationShellCmd.java)
35. [Xcode 14 Release Notes — Apple Developer Documentation](https://developer.apple.com/documentation/xcode-release-notes/xcode-14-release-notes)
36. [Promoting Apps with Smart App Banners — Apple Developer Documentation](https://developer.apple.com/documentation/webkit/promoting-apps-with-smart-app-banners)
37. [Test App Links — Android Developers](https://developer.android.com/training/app-links/test-applinks)
38. [Is your app installed? Get Installed Related Apps API will tell you! — web.dev](https://web.dev/articles/get-installed-related-apps)
39. [Native App Install Prompt — Chrome for Developers Blog](https://developer.chrome.com/blog/app-install-banners-native)
40. [Dynamic Links Deprecation FAQ — Firebase](https://firebase.google.com/support/dynamic-links-faq)
41. [Google Play Install Referrer — Android Developers](https://developer.android.com/google/play/installreferrer)
42. [Unsafe use of deep links — Android Developers](https://developer.android.com/privacy-and-security/risks/unsafe-use-of-deeplinks)
43. [Webviews – Unsafe URI Loading — Android Developers](https://developer.android.com/privacy-and-security/risks/unsafe-uri-loading)
44. [Stricter Android Intent verification for app entrypoints — Flutter docs (breaking changes)](https://docs.flutter.dev/release/breaking-changes/stricter-android-entrypoint-intent-verification)
45. [LaunchMode — url_launcher API](https://pub.dev/documentation/url_launcher/latest/url_launcher/LaunchMode.html)
46. [[iOS] Crash in debug when opening from the home screen — flutter/flutter#67624](https://github.com/flutter/flutter/issues/67624)
47. [Flutter SDK releases (macOS) — releases_macos.json](https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json)
