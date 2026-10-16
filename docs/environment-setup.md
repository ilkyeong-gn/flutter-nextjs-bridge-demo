# 하이브리드 앱 데모 실행을 위한 로컬 환경 구성 가이드

본 문서는 **Flutter(Host) + Next.js(Web) 하이브리드 앱 브릿지 데모**를 로컬 머신에서 처음 실행해보는 입문자/초보자를 위한 환경 설정 안내서입니다.

---

## 📌 시작하기 전에: 왜 이 설정이 필요한가요?

터미널에서 단순히 `flutter run`을 실행했을 때 아래와 같은 오류가 발생할 수 있습니다:

```
No supported devices connected.
The following devices were found, but are not supported by this project:
macOS (desktop) • macos
Chrome (web)    • chrome
```

### 왜 이런 메시지가 나오나요?

- 본 프로젝트는 모바일 웹뷰 통신(`webview_flutter`)을 시연하기 위해 **iOS 시뮬레이터** 및 **Android 에뮬레이터** 전용으로 설계되었습니다.
- Flutter는 기본적으로 Mac 데스크톱이나 Chrome 브라우저를 감지할 수 있지만, 본 프로젝트의 빌드 타깃이 아니므로 **실행 가능한 모바일 가상 기기(시뮬레이터/에뮬레이터)**가 실행 중이어야 합니다.

아래 가이드 중 원하시는 플랫폼(**Part 1: iOS** 또는 **Part 2: Android**)을 선택하여 환경을 구성해 주세요.

---

## 🍎 Part 1: iOS 환경 구성 가이드 (macOS 전용)

iOS 시뮬레이터를 띄워 Flutter 앱을 실행하기 위한 단계별 안내입니다.

```
[ 전체 흐름 요약 ]
Xcode 설치 → CocoaPods 설치 → xcode-select 경로 설정 → iOS 런타임/시뮬레이터 실행 → flutter run
```

### 1단계: Xcode 설치 (Mac App Store)

iOS 앱을 빌드하고 시뮬레이터를 띄우려면 Apple 공식 통합 개발 환경인 **Xcode**가 필수적입니다.

1. **Mac App Store**를 실행하거나 터미널에서 아래 명령을 실행합니다:
   ```bash
   open "https://apps.apple.com/kr/app/xcode/id497799835"
   ```
2. Xcode 페이지에서 **[받기]** 또는 **[설치]**(구름 모양 아이콘)를 클릭합니다.
3. _주의_: Xcode는 약 7~10GB 이상의 대용량 프로그램이므로 다운로드 및 설치에 시간이 다소 소요될 수 있습니다.

---

### 2단계: CocoaPods 설치

Flutter에서 iOS 네이티브 플러그인(웹뷰 등) 의존성을 관리하기 위해 **CocoaPods** 패키지 매니저가 필요합니다.

터미널에서 Homebrew를 통해 간편하게 설치할 수 있습니다:

```bash
brew install cocoapods
```

설치 후 정상 동작 여부 확인:

```bash
pod --version
# 예: 1.17.0 등이 출력되면 정상
```

---

### 3단계: Xcode 개발자 도구 경로 활성화 및 초기화

Mac에 기본으로 설정된 커맨드라인 도구 경로를 새로 설치한 `Xcode.app`으로 연결해야 합니다.

터미널에서 아래 **2줄의 명령어를 실행**하고, Mac 관리자(로그인) 비밀번호를 입력합니다:

```bash
# 1. 활성 개발자 도구 경로를 Xcode로 전환
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

# 2. 첫 실행 필수 구성 요소 초기화
sudo xcodebuild -runFirstLaunch
```

---

### 4단계: iOS 시뮬레이터 런타임 설치 및 시뮬레이터 구동

최신 Xcode 버전에서는 iOS 시뮬레이터 런타임이 별도로 분리되어 있습니다.

#### 런타임이 설치되어 있지 않은 경우:

터미널에서 바로 iOS 시뮬레이터 런타임을 다운로드할 수 있습니다:

```bash
xcodebuild -downloadPlatform iOS
```

_(또는 Xcode 실행 후 상단 메뉴 **Xcode > Settings... > Platforms** 탭에서 **iOS** 항목의 다운로드를 진행하셔도 됩니다.)_

#### 시뮬레이터 실행하기:

1. Spotlight(`Cmd + Space`)에서 **Simulator**를 검색하여 실행하거나,
2. Xcode 상단 메뉴 바에서 **`Xcode` > `Open Developer Tool` > `Simulator`** 를 클릭합니다.
3. 화면에 iPhone 가상 기기 창이 부팅되어 켜지는지 확인합니다.

---

### 5단계: 환경 검증 및 디바이스 확인

터미널에서 모든 설정이 완료되었는지 확인합니다:

```bash
# 1. Flutter 상태 점검 (Xcode 항목이 [✓]로 표시되어야 함)
flutter doctor

# 2. 연결된 기기 목록 확인 (iPhone Simulator가 목록에 떠야 함)
flutter devices
```

출력 예시:

```
Found 3 connected devices:
  iPhone 18 Pro (mobile) • 9DAEA0BA-... • ios • com.apple.CoreSimulator.SimRuntime.iOS-27-0 (simulator)
  macOS (desktop)        • macos
  Chrome (web)           • chrome
```

---

### 🚨 iOS 흔한 오류 및 해결법 (FAQ)

- **Q: `Unable to locate Xcode` 또는 `xcode-select` 경로 오류가 뜹니다.**
  - **해결**: Mac에 `CommandLineTools` 경로만 연결되어 있을 때 발생합니다. 3단계의 `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`를 실행해 주세요.
- **Q: `Unable to get list of installed Simulator runtimes` 오류가 나옵니다.**
  - **해결**: iOS 런타임이 아직 마운트되지 않은 상태입니다. Xcode 앱을 켠 뒤 상단 메뉴에서 `Xcode > Open Developer Tool > Simulator`를 1회 클릭하여 시뮬레이터를 켜주면 시스템 데몬(`CoreSimulator`)이 런타임을 자동으로 등록합니다.
- **Q: `CocoaPods not installed` 경고가 표시됩니다.**
  - **해결**: `brew install cocoapods`를 실행해 주시면 해결됩니다.

---

## 🤖 Part 2: Android 환경 구성 가이드 (macOS / Windows / Linux)

Android 에뮬레이터를 띄워 Flutter 앱을 실행하기 위한 단계별 안내입니다.

```
[ 전체 흐름 요약 ]
Android Studio 설치 → Android SDK & 컴포넌트 설치 → AVD 가상 기기 생성 → 라이선스 동의 → flutter run
```

### 1단계: Android Studio 설치

Android 앱 빌드 및 에뮬레이터 구동을 위해 **Android Studio**가 필요합니다.

1. [Android Studio 공식 다운로드 페이지](https://developer.android.com/studio)에 접속합니다.
2. 본인의 OS(Mac Apple Silicon / Intel 등)에 맞는 설치 파일을 다운로드하여 설치합니다.
3. 설치 완료 후 Android Studio를 실행하여 초기 Setup Wizard(설치 마법사)를 기본값(Standard)으로 완료합니다.

---

### 2단계: 필수 Android SDK 컴포넌트 구성

Flutter가 Android 빌드를 수행하기 위해 추가 SDK 컴포넌트가 필요합니다.

1. Android Studio 첫 화면에서 **More Actions** (또는 상단 메뉴 **Settings / Settings for New Projects**)를 클릭합니다.
2. **SDK Manager**로 이동합니다.
3. **SDK Tools** 탭을 클릭하고 아래 3가지 항목이 체크되어 있는지 확인하고 적용(Apply)합니다:
   - ✅ **Android SDK Build-Tools**
   - ✅ **Android SDK Command-line Tools (latest)** _(매우 중요)_
   - ✅ **Android Emulator**
   - ✅ **Android SDK Platform-Tools**

---

### 3단계: Android 가상 기기 (AVD Emulator) 생성

앱을 띄울 안드로이드 폰 가상 머신을 만듭니다.

1. Android Studio에서 **Virtual Device Manager** (또는 Device Manager)를 엽니다.
2. **Create Device** 버튼을 클릭합니다.
3. Phone 카테고리에서 **Pixel 7** 또는 **Pixel 8** 등을 선택하고 Next를 클릭합니다.
4. 시스템 이미지(OS 버전)에서 최신 안정 버전(예: **UpsideDownCake (Android 14)** 또는 **VanillaIceCream (Android 15)**) 옆의 다운로드 아이콘을 눌러 다운로드한 뒤 선택합니다.
5. Finish를 눌러 생성을 마칩니다.
6. Device Manager 목록에서 재생(▶) 버튼을 클릭하여 에뮬레이터를 부팅합니다.

---

### 4단계: Android 라이선스 동의

Flutter가 Android SDK를 사용하도록 라이선스에 동의해야 합니다.

터미널에서 아래 명령을 실행하고, 질문이 나올 때마다 `y`를 입력하여 동의합니다:

```bash
flutter doctor --android-licenses
```

> 💡 최신 Android SDK 환경에서는 명령 실행 시 아래와 같은 **deprecated 경고**가 먼저 출력될 수 있습니다. 오류가 아니라 안내 메시지이므로 무시하고 진행하셔도 됩니다.
>
> ```
> WARNING: The SDK Manager CLI tool (sdkmanager) is deprecated. Android CLI will be used instead.
> The 'android' binary can also be found in the cmdline-tools directory, and 'android sdk' is the replacement for 'sdkmanager'.
> ```
>
> 기존 `sdkmanager` 대신 Android CLI(`android` 바이너리, `cmdline-tools` 디렉터리에 포함)가 사용된다는 뜻입니다. 따라서 2단계의 **Android SDK Command-line Tools (latest)** 설치가 여전히 필수입니다.
>
> 경고만 출력되고 `y/N` 동의 질문 없이 종료되었다면, 5단계의 `flutter doctor`로 라이선스 상태를 확인하세요.

---

### 5단계: 환경 검증 및 디바이스 확인

```bash
# 1. Android toolchain 항목이 [✓]로 표시되는지 확인
flutter doctor

# 2. 부팅된 에뮬레이터가 목록에 나오는지 확인
flutter devices
```

출력 예시:

```
Found 3 connected devices:
  sdk gphone64 arm64 (mobile) • emulator-5554 • android-arm64 • Android 14 (API 34) (emulator)
  macOS (desktop)             • macos
  Chrome (web)                • chrome
```

---

### 🚨 Android 흔한 오류 및 해결법 (FAQ)

- **Q: `Unable to locate Android SDK` 오류가 발생합니다.**
  - **해결**: Android Studio가 기본 경로가 아닌 곳에 설치되었거나 SDK가 아직 다운로드되지 않았습니다. Android Studio를 1회 실행하여 SDK 다운로드를 마치거나, 터미널에서 경로를 수동 지정합니다:
    ```bash
    flutter config --android-sdk ~/Library/Android/sdk
    ```
- **Q: `cmdline-tools component is missing` 경고가 발생합니다.**
  - **해결**: 2단계의 SDK Manager > SDK Tools 탭에서 **Android SDK Command-line Tools (latest)** 항목에 체크 후 설치해 주세요.
- **Q: `flutter doctor --android-licenses` 실행 시 `sdkmanager is deprecated` 경고가 출력됩니다.**
  - **해결**: 오류가 아닙니다. `sdkmanager`가 Android CLI(`android sdk`)로 대체되었다는 안내이며, `cmdline-tools`가 설치되어 있으면 자동으로 Android CLI가 사용됩니다. 4단계 안내에 따라 진행하고, 이후 `flutter doctor`에서 `Android toolchain`이 `[✓]`인지 확인하세요.
- **Q: Android 에뮬레이터에서 Web 서버에 연결이 안 됩니다.**
  - **해결**: Android 에뮬레이터는 호스트 PC의 `localhost` 대신 가상 루프백 주소인 `http://10.0.2.2:3000`을 통해 PC에 접근합니다. 본 프로젝트는 이미 플랫폼 분기(`app/lib/config.dart`)와 `android:usesCleartextTraffic="true"` 설정이 적용되어 있으므로 별도 수정 없이 동작합니다.

---

## 🚀 Part 3: 통합 데모 실행 및 브릿지 동작 확인

환경 구성이 완료되면 Web 개발 서버와 Flutter Host 앱을 동시에 실행하여 브릿지 기능을 체험해볼 수 있습니다.

### 1단계: Web 개발 서버 실행 (터미널 1)

모바일 기기 및 에뮬레이터 접근을 허용하기 위해 `0.0.0.0` 호스트로 구동됩니다:

```bash
cd web
pnpm install
pnpm dev
```

> 서버 시작 확인: `Ready in ... on http://0.0.0.0:3000`

---

### 2단계: Host (Flutter) 앱 실행 (터미널 2)

새 터미널 창을 열고, 시뮬레이터 또는 에뮬레이터가 켜진 상태에서 앱을 실행합니다:

```bash
cd app
flutter pub get
flutter run
```

---

### 3단계: 브릿지 동작 확인

1. **Stage A (Web → Host 단방향 통신)**:
   - 가상 기기 화면 안의 Web 텍스트 입력창에 메시지(예: `안녕하세요 Flutter!`)를 입력하고 **[전송]** 버튼을 누릅니다.
   - Flutter 네이티브 화면 하단에 **SnackBar 알림**이 즉시 표시되는지 확인합니다.
2. **브라우저 단독 접속 모드 확인**:
   - PC 브라우저에서 [http://localhost:3000](http://localhost:3000)을 직접 열어봅니다.
   - Host(Flutter) 외부 접속을 감지하여 상단에 `⚠️ Host 외부에서 실행 중 (브릿지 비활성화)` 배지가 뜨고 전송 버튼이 비활성화되는 보호 기능을 확인합니다.
