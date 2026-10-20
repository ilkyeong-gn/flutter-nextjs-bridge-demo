# 딥 링크 진입 실측

「팬룸」 Host(Flutter)가 바깥에서 들어오는 링크(커스텀 스킴 `fanapp://`, 앱 링크 `https://fan.example/...`)를 받는 설계에 앞서, 개발 환경에서 바로 확인할 수 있는 사실 세 가지를 직접 재 본 실험 코드와 결과다. 이 브랜치(`experiment/deeplink-entry`)는 머지하지 않는다.

- 실측일: 2026-10-20

## 환경

| 항목 | 값 |
|---|---|
| Flutter | 3.47.7 stable(Dart 3.13.5) |
| iOS 빌드 | Xcode 27.0(27A266a), Swift Package Manager(Podfile 없음), UIScene 생명주기(`FlutterSceneDelegate`, `FlutterImplicitEngineDelegate` — `flutter create` 기본 템플릿 그대로) |
| iOS 실행 | iPhone 18 Pro 시뮬레이터, iOS 27.0. 이 Mac에는 코드 서명 인증서가 하나도 없다(`security find-identity -v -p codesigning` → `0 valid identities found`). 프로젝트에 `DEVELOPMENT_TEAM` 없음 |
| Android 빌드 | AGP 9.1.0, Kotlin 2.4.0, compile/target SDK는 Flutter 기본값 |
| Android 실행 | 에뮬레이터 Pixel 10a AVD, Android 17(API 37), Chrome 155.0.8059.84(첫 실행 설정 안 함), Android System WebView 149.0.7827.5 |
| 패키지 | `app_links` 7.2.2(SwiftPM·UIScene 지원 판), `url_launcher` 6.3.3(android 6.3.33, ios 6.4.2) |
| Flutter 기본 딥 링크 | 끔. iOS `Info.plist` `FlutterDeepLinkingEnabled = false`, Android `<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />` |

## 구성

| 경로 | 내용 |
|---|---|
| `app/` | 실측 앱(번들 ID·패키지 `example.fan.exp.dle`). `main()`에서 `AppLinks().getInitialLink()`를 기다린 뒤 `uriLinkStream`을 듣는다. 받은 값을 화면에 쌓고 `print('DLE …')`로 로그에 남긴다(앱 시작부터 경과 ms 포함). 화면의 `/not-in-table`, `/posts/3` 단추는 `launchUrl(Uri.parse('https://fan.example/…'), mode: LaunchMode.externalApplication)`을 부른다 |
| `app/ios/Runner/Info.plist` | `CFBundleURLTypes`에 `fanapp` 스킴 등록 |
| `app/android/app/src/main/AndroidManifest.xml` | `fanapp://app` VIEW 필터, `android:autoVerify="true"`인 `https://fan.example` VIEW 필터. 액티비티는 템플릿 기본 `launchMode="singleTop"` |
| `entitlement.sh` | Runner에 `com.apple.developer.associated-domains` 엔타이틀먼트 파일과 `CODE_SIGN_ENTITLEMENTS`를 붙이거나 뗀다. 커밋된 상태는 뗀 상태다 |
| `ios-entitlement-check.sh` | 1번. 엔타이틀먼트 적용 → `flutter build ios --simulator --debug` → 재설치 → `simctl launch` → 8초 뒤 프로세스·로그 확인 |
| `ios-openurl.sh` | 2번. `simctl terminate` 뒤 `simctl openurl`(cold), 또는 앱을 띄우고 Safari를 실행해 백그라운드로 보낸 뒤 `simctl openurl`(warm) |
| `ios-uitests/` | `simctl openurl`이 띄우는 "Open in "Dle"?" 확인 알림의 Open 단추만 누르는 XCUITest(대상 앱 없는 UI 테스트 번들). `gen.rb`(xcodeproj gem)로 프로젝트를 만든다 |
| `android-selfloop.sh` | 3번. 필터 data 줄을 바꿔 빌드·설치 → `pm set-app-links` 승인 → 앱 실행 → 단추를 실제 탭(`uiautomator dump`로 좌표를 찾아 `input tap`) → 맨 앞 액티비티와 로그 확인 |
| `results/` | 스크립트 출력과 화면 |

## 다시 해 보기

```sh
cd experiments/deeplink-entry
# iOS 시뮬레이터(iPhone 18 Pro)와 Android 에뮬레이터를 미리 부팅한다.

# 1. associated-domains 엔타이틀먼트(팀 없음)
./ios-entitlement-check.sh 'applinks:fan.example'
./ios-entitlement-check.sh 'applinks:fan.example?mode=developer'
./ios-entitlement-check.sh off          # 기준선으로 되돌림

# 2. simctl openurl로 debug 빌드 cold/warm 진입
(cd ios-uitests && ruby gen.rb && xcodebuild build-for-testing -project AlertTapper.xcodeproj \
   -scheme AlertTapper -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build)
(cd ios-uitests && TEST_RUNNER_TAPPER_SECONDS=420 xcodebuild test-without-building -project AlertTapper.xcodeproj \
   -scheme AlertTapper -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build) &   # 확인 알림을 누름
./ios-openurl.sh cold 5
./ios-openurl.sh warm 5

# 3. Android 자기 순환
./android-selfloop.sh host 3
./android-selfloop.sh posts 3
```

## 결과

### 1. 팀 없이 associated-domains 엔타이틀먼트를 넣은 시뮬레이터 debug 빌드

| 엔타이틀먼트 값 | 빌드 | 설치 | 실행 | 앱 로그 |
|---|---|---|---|---|
| (없음, 기준선) | ○ | ○ | ○ | `main start`, `initial null` |
| `applinks:fan.example` | ○ | ○ | ○ | 같음 |
| `applinks:fan.example?mode=developer` | ○ | ○ | ○ | 같음 |
| (다시 없음) | ○ | ○ | ○ | 같음. `project.pbxproj`가 처음 파일과 바이트 단위로 같음(`cmp`) |

- 오류는 없었다. `xcodebuild … -configuration Debug -sdk iphonesimulator clean build`를 직접 돌려도 `** BUILD SUCCEEDED **`이고, 경고는 `appintentsmetadataprocessor … warning: Metadata extraction skipped, no AppIntents.framework dependency found` 하나뿐이다. 이 경고는 `app_links` SwiftPM 타깃의 App Intents 메타데이터 단계에서 나온 것으로 엔타이틀먼트와 관계없다.
- 서명은 `Signing Identity: "Sign to Run Locally"`, 결과물은 `Signature=adhoc`, `TeamIdentifier=not set`이다.
- 시뮬레이터용 빌드는 엔타이틀먼트를 코드 서명에 넣지 않는다(`codesign -d --entitlements :-`는 빈 dict). 대신 실행 파일의 `__TEXT,__entitlements` 섹션에 넣는다. 꺼내 보면 아래와 같고, 팀 ID 자리에 `FAKETEAMID`가 들어간다.

  ```xml
  <key>application-identifier</key>
  <string>FAKETEAMID.example.fan.exp.dle</string>
  <key>com.apple.developer.associated-domains</key>
  <array>
      <string>applinks:fan.example</string>
  </array>
  ```

- 시뮬레이터의 `swcd`는 이 값을 실제로 읽었다. 설치 직후 로그:
  - `applinks:fan.example` → `Beginning data task AASA-… { domain: fan.example, bytes: 0, route: cdn }` → `Request for 'https://app-site-association.cdn-apple.com/a/v1/fan.example' … denied because the CDN told us to stop with HTTP status 404: SWCERR00202 Connections to private/reserved IP addresses are not allowed`
  - `applinks:fan.example?mode=developer` → `{ domain: fan.example?mode=developer, bytes: 0, route: .wk }`. Apple CDN을 거치지 않고 도메인의 `/.well-known/`에서 직접 받으려 한다. `fan.example`은 응답하는 서버가 없어 결과 줄은 관찰하는 동안 나오지 않았다.
  - 같은 로그에 `Developer mode enabled: YES`가 있다.
- 뜻: 팀이 없어도 엔타이틀먼트를 Runner에 넣어 둔 채로 시뮬레이터 개발은 막히지 않는다. 기기 빌드(팀·프로비저닝 프로파일 필요)는 이 실측 범위 밖이다.

### 2. `xcrun simctl openurl`로 debug 빌드 진입(Flutter 도구 밖)

`flutter build ios --simulator --debug`로 만든 앱을 `simctl install`로 넣고, `flutter run` 없이 열었다.

| 경우 | 시도 | 앱 실행 | 크래시 | 플러그인 등록 | `getInitialLink()` | `uriLinkStream` |
|---|---|---|---|---|---|---|
| cold(`simctl terminate` 뒤 `openurl`) | 5 | 5/5 | 0 | 5/5 | 5/5 그 URI | 5/5 같은 URI가 한 번 더 옴 |
| warm(Safari로 백그라운드, 같은 pid) | 5 | 5/5(같은 pid 유지) | 0 | — | — | 5/5 그 URI |

- cold 한 회의 로그(`results/ios-debug-cold.txt`):

  ```text
  The Dart VM service is listening on http://127.0.0.1:58568/gL9AvpGv1Sg=/
  DLE main start (+0ms)
  DLE initial fanapp://app/posts/3?run=cold-1 (+85ms)
  DLE stream fanapp://app/posts/3?run=cold-1 (+119ms)
  ```

- debug 빌드가 Flutter 도구 밖에서도 JIT로 정상 실행됐다(시뮬레이터). `app_links`는 debug에서 registrar의 messenger가 없으면 `Flutter application in debug mode can only be launched from Flutter tooling, use profile or release modes instead.`를 찍고 등록을 건너뛰는데, 10회 모두 이 문구가 없었고 `getInitialLink()`가 `MissingPluginException` 없이 값을 돌려줬다. 그래서 profile·release로 다시 해 볼 필요는 없었다(시뮬레이터는 profile·release 빌드를 지원하지 않기도 한다).
- **cold 진입 URI는 두 번 온다.** `getInitialLink()`와 첫 `uriLinkStream` 이벤트가 같은 URI다(5/5). `app_links` 7.2.2는 Dart가 처음 들을 때 실행 전에 받은 링크(`launchLinks`)를 스트림으로 다시 흘려 보낸다(`AppLinksIosPlugin.addListener`). 두 길을 모두 쓰면 중복을 걸러야 하고, 스트림만 들어도 cold URI를 받는다.
- **`simctl openurl`은 커스텀 스킴에 확인 알림을 띄운다.** 첫 `openurl`에서 SpringBoard가 "Open in "Dle"?"(Cancel/Open)를 띄웠고(`results/ios-openurl-confirm.png`), 누르지 않으면 앱이 실행되지 않았다(본 실측 전 시험 1회, 8초 뒤 `pid(after)=none`). 약 68초 뒤 XCUITest가 그 알림의 Open을 누르자 앱이 cold로 떠서 그 URI를 `initial`·`stream`으로 받았다(09:30:14, pid 14545). XCUITest가 Open을 누른 것은 이 실측 전체에서 이 1번뿐이고, 한 번 허용한 뒤 본 실측 10회(cold 5, warm 5)는 알림 없이 바로 열렸다. 자동화 스크립트에서 cold 진입을 돌리려면 첫 알림을 처리할 장치가 필요하다.
- 화면: `results/ios-after-warm.png`(cold-5 뒤 warm 1–5가 쌓인 모습).

### 3. Android 자기 순환(`launchUrl` + `externalApplication`)

`pm set-app-links --package example.fan.exp.dle 2 fan.example`로 승인한 뒤 `pm get-app-links`는 `fan.example: approved`. 앱 화면의 단추를 실제로 탭해 `launchUrl(…, mode: LaunchMode.externalApplication)`을 불렀다. 매 회 앱과 Chrome을 `force-stop`하고 시작했다.

| intent-filter | 연 주소 | 시도 | 결과 |
|---|---|---|---|
| `host="fan.example"`(경로 제한 없음) | `/not-in-table` | 3 | 3/3 **앱으로 돌아옴**. 맨 앞은 `example.fan.exp.dle/.MainActivity`, 같은 엔진의 `uriLinkStream`에 그 URI가 옴 |
| 〃 | `/posts/3` | 3 | 3/3 앱으로 돌아옴 |
| `host="fan.example" pathPrefix="/posts/"` | `/not-in-table` | 3 | 3/3 **Chrome이 열림**(맨 앞 `com.android.chrome/…FirstRunActivity`), 앱 스트림에 아무것도 오지 않음 |
| 〃 | `/posts/3` | 3 | 3/3 앱으로 돌아옴 |

- 모든 회에서 `launchUrl`은 `true`를 돌려줬다. 앱으로 돌아왔는지 브라우저로 갔는지 반환값으로는 구별할 수 없다.
- 앱으로 돌아올 때 `main start`는 한 번뿐이고 `initial`이 아니라 `stream`으로 왔다. `singleTop` 액티비티가 새로 만들어지지 않고 `onNewIntent`로 받은 것이다.
- 뜻: 앱 링크 필터를 도메인 전체로 걸면 "표에 없는 경로는 외부 브라우저로 연다"가 `externalApplication`만으로는 성립하지 않는다(자기 자신에게 돌아온다). 필터를 앱이 받을 경로로 좁히면 나머지 경로는 브라우저로 간다.

## 확인하지 못한 것

- iOS Universal Link 자체(`https://fan.example/...`로 앱이 열리는가)는 확인하지 못했다. `fan.example`은 AASA 파일을 내줄 서버가 없고, 시뮬레이터 `swcd`의 CDN 경로는 예약 주소라 거절했다(`SWCERR00202`). `?mode=developer` 경로의 직접 요청 결과는 관찰 시간 안에 로그에 나오지 않았다.
- 실기기 빌드, 개발 팀·프로비저닝 프로파일이 있을 때의 엔타이틀먼트 검증은 하지 않았다(이 Mac에 서명 인증서 없음).
- iOS profile·release 빌드는 시뮬레이터에서 만들 수 없어 하지 않았다. debug가 성공해 대체 실측도 필요 없었다.
- Android `autoVerify` 실제 검증(assetlinks.json)은 하지 않았다. 승인 상태는 `pm set-app-links`로 만든 것이다.
- Android에서 `LaunchMode.externalNonBrowserApplication` 등 다른 모드, iOS에서 `launchUrl`의 자기 순환은 재지 않았다.
- Android cold 진입(`am start -a android.intent.action.VIEW -d …`)은 이번 질문 범위가 아니어서 재지 않았다.
