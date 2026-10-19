# WebView에서 사진·영상 선택과 업로드 경로 조사

- **질문**: [#32 WebView에서 사진·영상 선택과 업로드 경로 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/32). WebView 안의 Web이 사진 여러 장이나 영상 하나를 받아 업로드하는 경로들은 iOS와 Android에서 각각 어떻게 동작하고, 큰 파일·진행률·취소·권한 거부를 어떻게 다루는가?
- **조사일**: 2026-10-19
- **확인한 버전**: webview_flutter 4.14.1(webview_flutter_android 4.14.1, webview_flutter_wkwebview 3.27.0, flutter/packages `0259ad7`), flutter_inappwebview 6.1.5(최신 안정판, 2024-10-08)와 6.2.0-beta.3, image_picker 1.2.4(image_picker_android 0.8.13+25, image_picker_ios 0.8.13+12), permission_handler 13.0.2(android 14.1.0, apple 9.6.2), image_cropper 13.0.0, dio 5.11.1, background_downloader 9.6.4, WebKit `2edaa07`(2026-10-09), Next.js 16.4.2, Android·Apple 개발자 문서(2026-08~10 갱신본)

## 요약

- **경로 A(파일 input)는 플랫폼마다 주인이 다르다.** iOS에서는 WKWebView가 사진 보관함(PHPicker)·촬영·파일 선택 메뉴를 직접 띄우고, `capture`가 있으면 카메라를 바로 연다 [11]. Android WebView는 Host가 `onShowFileChooser`를 구현하지 않으면 모든 파일 요청을 취소하므로 [1], webview_flutter에서는 Host가 `setOnShowFileSelector`로 카메라·사진 선택기를 직접 띄워 URI를 돌려줘야 한다 [3][6].
- **iOS 경로 A에는 Host가 끼어들 자리가 없다.** iOS 18.4에 `runOpenPanelWith` 위임 메서드가 생겼지만 [16], webview_flutter_wkwebview 3.27.0과 flutter_inappwebview(iOS)는 이를 노출하지 않는다 [18][19]. 그래서 개수 제한(`multiple`이면 한도 없음), 형식 변환(PHPicker `compatible` 표현), 카메라 권한 흐름을 모두 WebKit과 시스템이 정한다 [11][12].
- **경로 B의 base64 전달은 썸네일·작은 사진까지만 현실적이다.** 현재 Bridge(webview_flutter)는 문자열만 주고받고 [34][35], base64는 3바이트를 4글자로 늘린다 [39]. 파일을 URL로 노출하는 플랫폼 API(WKURLSchemeHandler, WebViewAssetLoader)는 있지만 [40][41] webview_flutter는 노출하지 않고 [38][42], flutter_inappwebview의 커스텀 스킴 응답은 바이트 전체를 한 덩어리로 돌려준다 [44].
- **경로 C(Host 업로드)가 큰 영상·백그라운드 지속·재시도에 가장 강하다.** dio는 진행률 콜백과 취소 토큰을 [46], background_downloader는 iOS URLSession·Android WorkManager/UIDT 위에서 진행률·취소·백그라운드 전송을 준다 [47]. 대가로 업로드 상태와 인증 수단을 Host가 가져야 하고, Web은 진행률 Event·결과 ID·미리보기용 썸네일을 Bridge로 받아야 한다.
- **Web이 업로드하는 경로(A·B)의 진행률·취소는 XHR로 해결된다.** `xhr.upload`의 progress(약 50ms 간격)와 `abort()`가 표준이고 [22], fetch에는 아직 업로드 진행률 API가 없다 [23]. 이어 올리기 표준은 IETF 초안(14판) 단계다 [25].
- **보관함에서 고르는 일 자체는 두 플랫폼 모두 권한이 필요 없다.** iOS PHPicker는 별도 프로세스에서 돌아 사용자 승인이 필요 없고 [55], Android 사진 선택기는 고른 항목만 넘긴다 [53]. 권한 거부가 실제로 문제 되는 것은 카메라, 그리고 Host가 PhotoKit이나 `READ_MEDIA_*` 접근을 요청할 때다.
- **거부 뒤 규칙이 다르다.** iOS는 한 번 답하면 다시 묻지 않으므로 설정 앱으로 보내야 하고 [56][59], Android는 두 번 거부하면 영구 거부로 본다 [60]. permission_handler(android 14.1.0)는 Android에서 영구 거부를 `status`가 아니라 `request()` 결과로만 알려준다 [61].
- **iOS 제한된 사진 접근은 Host가 PhotoKit 권한을 요청할 때만 생긴다.** PHPicker만 쓰면 해당이 없지만, image_picker는 `requestFullMetadata` 기본값이 `true`라 사진 보관함 권한을 요청할 수 있다 [26][27].
- **Android 13 이상에서는 사진 선택기가 사실상 기본이다.** Google Play는 넓은 사진 접근이 핵심 기능인 앱만 `READ_MEDIA_IMAGES/VIDEO`를 쓰게 한다(2025-05-28 전면 적용) [63]. image_picker_android는 API 36 이상에서만 항상 사진 선택기를 쓰고, 그 아래는 `useAndroidPhotoPicker = true`여야 사진 선택기와 `limit`이 동작한다 [29][31].
- **크롭·회전 위치는 경로가 거의 정한다.** iOS 경로 A에서는 Host가 파일을 보지 못하니 Web 편집만 가능하고, 경로 C에서는 Web에 바이트가 없으니 Host 편집(image_cropper)이 자연스럽다 [11][65].

## 상세

### 1. 경로 A: `<input type="file">`을 그대로 쓰기

#### 1.1 Android: Host가 파일 선택기를 연결해야 한다

- Android WebView는 `WebChromeClient.onShowFileChooser`(API 21)로 파일 선택을 Host에 맡긴다. 기본 동작은 모든 파일 요청 취소이고, 구현하면 `true`를 반환한 뒤 선택한 URI(취소면 `null`)를 `filePathCallback`에 넘겨야 한다. WebView는 고른 파일을 검사하지 않으므로 Host가 URI를 확인해야 한다 [1].
- `FileChooserParams`는 `getAcceptTypes()`, `getMode()`(단일·다중 등), `isCaptureEnabled()`를 준다. `createIntent()`는 "단순한 파일 소스"용이라 라이브 캡처(카메라)는 지원하지 않을 수 있으니 필요하면 인텐트를 직접 만들라고 문서가 안내한다 [2].
- webview_flutter에서는 `AndroidWebViewController.setOnShowFileSelector`(webview_flutter_android 3.2.0부터)가 이 훅이다. 콜백은 `FileSelectorParams`(`acceptTypes`, `isCaptureEnabled`, `mode`, `filenameHint`)를 받아 `List<String>`을 돌려주고, 플러그인이 각 문자열을 `Uri.parse`해 `filePathCallback`에 넘긴다 [3][4][5]. 훅을 설정하지 않으면 file input을 눌러도 아무 일도 일어나지 않으며, Flutter 팀은 플랫폼 동작을 감싼 결과로 보고 이슈를 닫았다 [6]. README 예시는 아직 없고(#118836 열림), 이슈의 사용 예는 image_picker로 고른 캐시 파일을 `File(path).uri.toString()`(`file://`)으로 돌려준다 [7].
- 결국 Android 경로 A에서도 카메라를 띄울지, 사진 선택기를 쓸지, 몇 장까지 받을지는 Host 코드가 정한다. Web의 `capture`는 `isCaptureEnabled` 불리언으로만 전달되고 `user`/`environment` 구분은 오지 않는다 [3].
- flutter_inappwebview 6.1.5는 Android에서 이를 플러그인이 직접 처리한다. `capture`면 `ACTION_IMAGE_CAPTURE`/`ACTION_VIDEO_CAPTURE`를 바로 띄우고, 아니면 `ACTION_GET_CONTENT` 선택기에 카메라 인텐트를 붙인다. 단 매니페스트에 `CAMERA`가 선언됐는데 허용되지 않았으면 카메라 항목을 조용히 빼며, 권한 요청은 하지 않는다 [8]. Host가 이 동작을 바꾸는 `onShowFileChooser` 이벤트는 6.2.0-beta.3에만 있다 [9].
- 매니페스트에 `CAMERA`를 선언했는데 허용되지 않은 상태에서 `ACTION_IMAGE_CAPTURE`를 쓰면 `SecurityException`이 난다 [10]. 다른 플러그인의 매니페스트가 병합되며 `CAMERA`가 들어오는 경우도 같은 규칙을 탄다.

#### 1.2 iOS: WKWebView가 직접 처리하고 Host는 끼어들 수 없다

- WebKit(`WKFileUploadPanel`, `2edaa07`)의 동작은 다음과 같다 [11].
  - `capture`가 있고 카메라가 있으면 메뉴 없이 카메라(`UIImagePickerController`)를 바로 연다. `user`는 전면, 그 밖에는 후면 카메라다.
  - 그 밖에는 "사진 보관함"(PHPicker), "사진 또는 비디오 찍기"(카메라가 있을 때만), "파일 선택"(문서 선택기) 메뉴를 띄운다. `accept`가 이미지만이면 사진 필터, 영상만이면 영상 필터를 건다.
  - PHPicker의 `selectionLimit`은 `multiple`이면 0(시스템 최대), 아니면 1이다 [11][15]. Web이 "최대 10장" 같은 한도를 선택 단계에서 걸 방법은 없다.
  - PHPicker에는 `compatible` 표현을 요청한다. 원본 형식을 받는 설정(`PhotoPickerPrefersOriginalImageFormat`)은 내부(internal) 설정이고 기본값이 false다 [11][12]. Apple 문서상 이 모드에서는 시스템이 추가로 변환(transcoding)할 수 있고, 변환을 피하려면 `current`를 쓰라고 한다 [14]. WebKit 주석에도 "accept 값에 따라 변환해야 한다"는 FIXME가 남아 있다 [11].
  - 카메라로 찍은 사진은 파일 URL이 없어 품질 0.8의 JPEG로 다시 인코딩하고, 이름은 모두 `image.jpg`이며, EXIF 유지 여부는 FIXME로 남아 있다 [11]. 영상을 `AVAssetExportPresetHighestQuality`로 다시 내보내며 "Preparing…" 진행 창(취소 가능)을 띄우는 코드도 iOS 빌드에서 켜져 있지만 [11][13], `UIImagePickerController`의 다중 선택 결과와 원본 형식 모드의 PHPicker 결과에서만 호출돼 카메라 단일 촬영이 이 경로를 타는지는 확정하지 못했다.
  - 고른 파일은 임시 디렉터리로 옮겨지고 WebView가 해제될 때 지워진다 [11].
- iOS 18.4부터 `WKUIDelegate.webView(_:runOpenPanelWith:initiatedByFrame:completionHandler:)`를 iOS에서도 쓸 수 있다. 구현하지 않으면 기본 업로드 UI가 뜨고, 구현하면 Host가 URL 목록을 돌려주거나 `nil`로 막을 수 있다 [16]. 다만 iOS에서 `WKOpenPanelParameters`가 주는 정보는 다중 선택·디렉터리 허용 여부뿐이라 `accept`·`capture`를 알 수 없다 [17]. webview_flutter_wkwebview 3.27.0의 UIDelegate는 이 메서드를 구현하지 않고 [18], flutter_inappwebview 저장소에서 이 메서드는 macOS 구현에만 있다 [19].
- 권한: PHPicker로 보관함에서 고르는 데는 승인이 필요 없다 [55]. 카메라는 `NSCameraUsageDescription`, 영상 녹화는 `NSMicrophoneUsageDescription`이 필요하고, 키 없이 캡처 장치를 쓰면 시스템이 Host를 종료한다 [56][57][58]. WebKit은 카메라 UI를 Host 프로세스 안의 `UIImagePickerController`로 띄우므로 [11], 경로 A만 쓰더라도 Host Info.plist에 이 키를 두는 것이 안전하다(WebKit 문서에서 직접 확인한 문장은 없음).

#### 1.3 `accept`·`multiple`·`capture`는 힌트다

- HTML 표준에서 `accept`는 힌트이고, 사용자 에이전트는 맞지 않는 파일을 막아야 한다(should) 정도다. `multiple`이 없으면 파일은 최대 1개다. 개수·용량을 제한하는 속성은 없고, 선택이 끝나면 `input`·`change`, 선택 창을 그냥 닫으면 `cancel` 이벤트가 발생한다 [20].
- HTML Media Capture(W3C 권고안, 2018-02-01)에서 `capture`(`user`/`environment`)는 선호하는 카메라 방향이고, 캡처로 받을 수 없는 `accept`와 함께 쓰면 `capture`가 없는 것처럼 동작해야 한다 [21].
- 따라서 경로 A에서는 개수·용량·형식 검증을 Web이 선택 뒤에 해야 하고, 서버도 다시 검사해야 한다.

#### 1.4 경로 A의 업로드: 큰 파일·진행률·취소

- Web은 받은 `File`(`Blob`)을 그대로 XHR 본문이나 `FormData`에 넣는다. XHR은 `upload` 객체에서 `loadstart`·`progress`(약 50ms 간격)·`load`·`abort`·`error`·`timeout`·`loadend`를 보내고 `abort()`로 취소한다 [22]. fetch는 `signal`(AbortSignal)로 취소할 수 있지만 [68] 진행률을 관찰하는 API는 아직 논의 중이다 [23].
- `Blob.slice()`로 파일 일부를 잘라 청크 업로드를 만들 수 있고, File API는 파일 읽기를 비동기로 정의한다 [24]. 끊긴 업로드를 이어 올리는 표준은 IETF "Resumable Uploads for HTTP" 초안 14판(2026-10-18)으로 아직 RFC가 아니다 [25].
- WebView 안의 업로드가 Host가 백그라운드로 간 뒤 얼마나 이어지는지는 확인하지 못했다. 백그라운드 지속을 문서로 보장하는 수단으로는 3절의 Host API(iOS 백그라운드 세션, Android UIDT)가 있다 [50][52].

### 2. 경로 B: Host 선택기로 고른 뒤 Bridge로 Web에 전달

#### 2.1 Host 선택기(image_picker)의 성질

- iOS: 보관함 선택은 PHPicker에 `current` 표현(가능하면 변환하지 않음)을 요청하고 `selectionLimit`에 `limit`을 넣는다. 카메라는 `AVCaptureDevice` 권한을 확인해 미결정이면 요청하고, 거부·제한이면 `camera_access_denied`·`camera_access_restricted` 오류를 돌려준다 [28]. Info.plist에는 `NSPhotoLibraryUsageDescription`·`NSCameraUsageDescription`·(영상 녹화 시) `NSMicrophoneUsageDescription`이 필요하고, 사진 보관함 권한은 `requestFullMetadata: false`일 때 요청하지 않는다 [26][27].
- Android: 보관함 선택은 API 36 이상이면 항상 사진 선택기, 그 아래는 `useAndroidPhotoPicker = true`일 때만 사진 선택기이고 아니면 `ACTION_GET_CONTENT`다. `limit`도 이 플래그가 있어야 한다 [29][30][31]. 앱용 README는 "Android 13 이상은 사진 선택기를 쓴다"고 적어 구현과 어긋난다 [26]. 고른 항목은 `{cacheDir}/{uuid}/파일명`으로 복사돼 경로로 돌아오므로, 큰 영상은 복사 시간과 캐시 공간을 쓰고 정리는 Host 몫이다 [32]. 카메라 권한은 매니페스트에 `CAMERA`가 있을 때만 요청하고, 거부되면 `camera_access_denied`를 돌려준다 [31][33].
- 외부 선택기나 카메라가 떠 있는 동안 메모리 부족으로 Host 액티비티가 종료될 수 있고, 이때 결과는 `retrieveLostData()`로 다시 받는다 [26]. 경로 A에서 같은 일이 생기면 WebView가 기다리던 `filePathCallback`을 되살릴 방법이 없다(추론).

#### 2.2 base64로 Bridge 전달

- 현재 Demo가 쓰는 webview_flutter Bridge는 Web→Host가 `JavaScriptMessage.message`(문자열), Host→Web이 `runJavaScript(String)`이라 바이너리를 그대로 보낼 수 없다 [34][35]. iOS `WKScriptMessage.body`도 숫자·문자열·날짜·배열·딕셔너리·null만 허용한다 [36]. Android에는 ArrayBuffer를 보내는 `WebMessageCompat`(androidx.webkit 1.8.0)이 있지만 webview_flutter_android의 Pigeon 정의에는 JavaScriptChannel만 있다 [37][38].
- base64는 24비트를 4글자로 표현하므로 크기가 4/3배가 된다 [39]. 여기에 파일 읽기 → Dart 문자열 → 플랫폼 채널 → JS 문자열 → 디코딩 → `Blob`의 단계마다 전체 크기만큼의 사본이 생긴다. 이 부분은 API 형태에서 끌어낸 추론이고 측정한 수치는 없다.
- 그래서 base64는 Host가 줄인 썸네일이나 작은 사진(image_picker의 `maxWidth`·`imageQuality`로 축소 [27])에는 쓸 만하지만 큰 영상에는 맞지 않는다고 보는 것이 합리적이다. 여러 Call로 쪼개 보내면 메모리 최고치는 줄지만 계약이 복잡해진다.

#### 2.3 파일을 URL로 노출

- iOS는 `WKWebViewConfiguration.setURLSchemeHandler`로 커스텀 스킴의 응답을 Host가 만들 수 있다. `https`처럼 WebKit이 이미 처리하는 스킴은 등록할 수 없다 [40].
- Android는 androidx.webkit `WebViewAssetLoader`가 `shouldInterceptRequest` 안에서 로컬 파일을 http(s) URL(기본 도메인 `appassets.androidplatform.net`)로 제공한다 [41].
- webview_flutter 4.14.1은 둘 다 노출하지 않는다. Android Pigeon 정의에는 `shouldInterceptRequest` 콜백 없이 요청 타입만 있고, WKWebView Pigeon 정의에는 URL 스킴 핸들러가 없다 [38][42]. 쓰려면 플러그인 밖의 플랫폼 코드가 필요하다.
- flutter_inappwebview 6.1.5는 `onLoadResourceWithCustomScheme`(Android, iOS는 WKURLSchemeHandler)과 모바일에서는 Android만 지원하는 `shouldInterceptRequest`를 준다 [43]. 하지만 응답 `CustomSchemeResponse`가 `Uint8List data` 한 덩어리라 [44], 영상을 내보내면 전체 바이트가 Dart 메모리와 플랫폼 채널을 지난다.
- 선례로 Capacitor(v8)는 기기 파일 경로를 `convertFileSrc()`로 바꿔 WebView가 읽게 하며, Android에서는 `http://localhost/_capacitor_file_/...` 형태가 된다 [45].
- 이렇게 노출한 URL은 Web과 origin이 달라, Web이 `fetch`로 바이트를 읽을 때의 CORS·Range 처리는 따로 확인해야 한다.

### 3. 경로 C: Host가 직접 업로드하고 Web에는 진행률과 결과 ID만 전달

- 전송 수단
  - 포그라운드: dio는 `MultipartFile.fromFile`, `onSendProgress(sent, total)`, `CancelToken`을 제공한다 [46].
  - 백그라운드: background_downloader는 iOS `URLSession`, Android WorkManager·UIDT(JobService) 위에서 업로드(multipart 또는 바이너리, 예: 사전 서명 URL)·진행률·취소를 제공한다 [47][48]. Android 일반 작업은 WorkManager 제약으로 9분까지다 [47]. 다운로드는 일시정지·재개를 반복해 이 한도를 넘기지만 일시정지는 다운로드 GET 요청에만 가능하므로 [49], 9분을 넘는 업로드는 Android 14 이상의 UIDT(`priority: 0`)에 기대야 한다고 읽힌다(문서 조합에서 나온 추론) [47].
- 플랫폼이 보장하는 범위
  - iOS 백그라운드 세션은 Host가 일시중지되거나 시스템에 의해 종료돼도 전송을 이어가지만, 사용자가 앱 전환기에서 강제 종료하면 모두 취소된다 [50]. iOS 17부터 `URLSession`은 이어 올리기를 지원하지만 서버가 IETF 초안을 구현해야 한다 [51].
  - Android UIDT(Android 14+)는 사용자가 시작한 긴 전송용으로, 알림이 필요하고 Host가 보이는 상태에서 예약해야 한다 [52].
  - 사진 선택기 URI 접근권은 기기 재시작이나 Host 종료까지만 유지되므로, 긴 백그라운드 업로드에는 `takePersistableUriPermission()`이 필요하다 [53]. image_picker처럼 캐시로 복사하면 이 문제는 없지만 복사 비용이 든다 [32].
- Bridge 계약에 생기는 것: 선택·업로드 시작 Call, 진행률 Event(빈도 조절 필요), 취소·재시도 Call, 완료 Event(서버가 준 결과 ID), 미리보기용 썸네일 전달(2.2의 작은 base64나 2.3의 URL). WebView가 다시 로드돼도 업로드는 Host에서 계속되므로, Web 작성 화면이 다시 열릴 때 Host에 현재 상태를 묻는 Call도 필요하다(설계 추론).
- 인증: Host가 쓰는 HTTP 라이브러리(dio 등)가 업로드 엔드포인트 자격을 가져야 한다. Web 세션을 Host와 공유할지, Web이 짧은 수명의 업로드 URL·토큰을 Call 인자로 넘길지는 S1 세션 설계(#31, #42)와 묶인다. background_downloader 문서도 사전 서명 URL로 보내는 바이너리 업로드를 예로 든다 [48].
- 가짜 API 주의: Next.js 16에서 middleware가 이름을 바꾼 proxy [69]를 쓰면 요청 본문을 기본 10MB까지만 메모리에 버퍼링하고, 넘으면 오류 없이 잘린 본문으로 Route Handler까지 진행한다(실험적 옵션 `proxyClientMaxBodySize`로 조정) [54]. Web이 올리든 Host가 올리든 업로드 경로가 proxy를 지나면 해당한다.

### 4. 카메라·사진 권한 요청과 거부·영구 거부

| 상황 | iOS | Android |
|---|---|---|
| 보관함에서 고르기 | PHPicker는 승인 불필요 [55] | 사진 선택기는 권한 불필요 [53], `READ_MEDIA_*`는 정책상 제한 [63] |
| 사진 촬영 | `NSCameraUsageDescription` 필요, 첫 사용 때 한 번 묻고 기억 [56][57] | 카메라 인텐트는 권한 불필요, 단 `CAMERA`를 선언했다면 런타임 허용 필요 [10] |
| 영상 촬영 | 위에 더해 `NSMicrophoneUsageDescription` [58] | 위와 같음 |
| 거부 뒤 | 다시 묻지 않음, 설정 앱으로 이동(`openSettingsURLString`) [56][59] | 두 번 거부하면 영구 거부(`USER_FIXED`) [60] |

- permission_handler에서 iOS는 사용자가 거부하면 상태가 곧 `permanentlyDenied`가 되지만 [70], Android(14.1.0)에서는 `status`가 `denied`만 돌려주고 `request()` 결과만 `permanentlyDenied`가 될 수 있다(이미 영구 거부면 대화상자 없이 바로 반환). 그 뒤 `openAppSettings()`로 설정 화면을 연다. iOS에서는 Podfile 매크로로 쓸 권한(`PERMISSION_CAMERA` 등)을 켜야 한다 [61].
- 거부를 Web에 알리는 길: Host 선택기(B·C)는 image_picker 오류 코드(`camera_access_denied` 등)를 Call 오류로 바꿔, Web이 안내 문구를 보여주고 "설정 열기" Call을 보낼 수 있다 [28][33]. iOS 경로 A는 WebKit이 카메라 권한을 처리하므로 Web이 거부 이유를 알 수 없다.
- Android 문서는 거부 뒤에도 기능을 최대한 유지하고, 막힌 기능 자리에 구체적으로 안내하되 계속 조르지 말라고 권한다 [60].

### 5. iOS의 제한된 사진 접근

- iOS 14부터 사용자는 PhotoKit 접근 요청에 "선택한 사진만"으로 답할 수 있고(`.limited`), 그러면 Host는 선택된 항목만 본다 [55]. 시스템은 Host가 실행될 때마다 한 번 선택을 갱신하라는 안내를 자동으로 띄우며, Info.plist에 `PHPhotoLibraryPreventAutomaticLimitedAccessAlert`를 `true`로 두고 `presentLimitedLibraryPicker`로 직접 띄우는 방식이 권장된다 [55][62].
- 이 상황은 Host가 PhotoKit 권한을 요청할 때만 생긴다. WebKit 파일 input과 image_picker(`requestFullMetadata: false`)의 PHPicker 경로는 해당이 없다 [11][26]. Apple 문서도 사진을 골라 올리는 정도의 읽기 용도라면 PHPicker가 가장 단순하다고 권한다 [55].

### 6. Android 13 이상의 사진 선택기

- 사진 선택기는 Android 11(API 30) 이상에서 Google 시스템 업데이트로 제공되고, Android 4.4~10은 Google Play 서비스 백포트(매니페스트 항목 필요)로 쓸 수 있다. AndroidX `PickVisualMedia`/`PickMultipleVisualMedia(max)`로 띄우고, 최대 개수는 `MediaStore.getPickImagesMaxLimit()`가 상한이며, 선택기가 없어 `ACTION_OPEN_DOCUMENT`로 대체되면 최대 개수는 무시된다 [53][10]. HDR 영상을 SDR로 바꾸는 변환은 앱이 명시적으로 켜야 하고 1분 이하 영상만 대상이다 [53].
- Google Play 정책상 `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO`는 넓은 접근이 핵심 기능인 앱(예: 갤러리 앱)만 쓸 수 있고 2025-05-28부터 전면 적용됐다 [63]. Android 14의 부분 접근(`READ_MEDIA_VISUAL_USER_SELECTED`)도 이 권한을 쓰는 앱에만 해당하며, 문서는 사진 선택기를 먼저 권한다 [64]. 팬이 게시글에 사진을 첨부하는 용도는 사진 선택기 쪽에 해당한다고 보는 것이 자연스럽다.
- 경로 A에서 사진 선택기를 쓰려면 Host가 `setOnShowFileSelector` 안에서 직접 띄워야 한다. `createIntent()`는 단순 파일 소스용이고 [2], flutter_inappwebview 6.1.5의 기본 처리는 `ACTION_GET_CONTENT`다 [8].

### 7. 크롭·회전 편집 위치

- Host 편집: image_cropper 13.0.0은 Android uCrop(매니페스트에 `UCropActivity` 추가 필요), iOS TOCropViewController, Web Cropper.js를 감싼 이미지 전용 편집기다 [65]. Host가 파일을 가진 경로 B·C에서 바로 쓸 수 있고, Flutter 위젯이 아니라 플랫폼 편집 화면으로 뜬다.
- Web 편집: canvas 기반 편집은 Web이 바이트를 가진 경로 A·B에서 쓸 수 있고 브라우저 개발 모드에서도 똑같이 동작한다. 표준은 `createImageBitmap`의 `imageOrientation` 기본값을 `"from-image"`로 두어 이미지 방향 메타데이터를 따르게 한다 [66]. WebView별 HEIC 디코딩 지원은 확인하지 못했다.
- 경로가 선택을 좁힌다. iOS 경로 A에서는 Host가 파일을 볼 수 없어 Web 편집만 가능하고, 경로 C에서 Web 편집을 하려면 바이트를 Web으로 보내야 한다. 어느 쪽이든 다시 인코딩하면 메타데이터가 바뀔 수 있다(WebKit 카메라 경로는 이미 EXIF 유지가 FIXME다 [11]). 영상 자르기 같은 영상 편집은 이번 조사 범위 밖이다.

## Reference App에 주는 시사점

「사진·영상 첨부와 업로드 설계 (S2)」(#43)가 비교할 사실을 경로별로 모으면 다음과 같다.

| 기준 | A: file input | B: Host 선택 → Bridge 전달 | C: Host 선택·업로드 |
|---|---|---|---|
| 선택 UI를 정하는 쪽 | iOS는 WebKit, Android는 Host(훅 구현 필수) | Host | Host |
| 개수 제한 | iOS 불가(선택 뒤 Web 검증), Android는 Host 재량 | 선택기 `limit` | 선택기 `limit` |
| 원본 보존 | iOS `compatible` 변환, 카메라 사진 JPEG 재인코딩 | image_picker iOS는 `current` | B와 같음 |
| 바이트 위치 | Web(`File`) | Host에서 Web으로 옮겨야 함 | Host |
| 큰 영상 | Web XHR로 가능 | base64는 비현실적, URL 노출은 플랫폼 코드 필요 | 가장 적합 |
| 진행률·취소 | XHR progress·`abort()` | 전송 뒤 XHR | Host 진행률을 Event로, 취소는 Call |
| 백그라운드 지속 | 보장 근거 없음 | A와 같음 | iOS URLSession, Android WorkManager(9분)·UIDT |
| 권한 거부 안내 | iOS는 Web이 이유를 모름 | Host 오류 코드를 Call 오류로 | B와 같음 |
| 편집 위치 | Web | Host 또는 Web | Host |
| 업로드 인증 | Web 세션 그대로 | Web 세션 그대로 | Host에 자격 필요(S1과 결합) |
| 브라우저 개발(가짜 Host) | 그대로 동작 | 가짜 Host가 선택·전달을 흉내 | 가짜 Host가 업로드·진행률을 흉내 |

#43이 저울질할 선택지와 각각의 대가:

1. **A 중심(파일 input + Android 훅 + Web XHR 업로드)**: Web 코드가 가장 단순하고 브라우저 개발 모드와 동작이 같다. 대신 iOS에서는 개수 제한·원본 형식·카메라 권한 안내를 통제할 수 없고, Android에서는 어차피 Host 선택기 코드가 필요하며, 백그라운드 업로드 보장이 없다.
2. **B 중심(사진 선택을 Host 기능으로, 업로드는 Web)**: 선택 UX(`limit`, 사진 선택기, 권한 오류 코드, Host 크롭)를 두 플랫폼에서 맞출 수 있고 업로드 로직은 Web에 남는다. 대신 바이트를 Web으로 옮기는 수단이 병목이다. base64는 사진에만 맞고, 영상은 URL 노출(현재 패키지로는 플랫폼 코드 추가나 flutter_inappwebview 필요)이 있어야 한다.
3. **C 중심(선택·업로드 모두 Host 기능)**: 큰 영상·백그라운드·재시도가 가장 견고하다. 대신 업로드 상태·인증·썸네일 전달을 Host가 맡아 Bridge 표면(진행률 Event, 취소·상태 조회 Call)이 가장 넓고, 가짜 Host가 업로드 진행률까지 흉내 내야 한다.
4. **혼합(사진은 A 또는 B, 영상은 C)**: 각 미디어에 맞는 경로를 쓰지만 코드 경로가 둘이 되고, 작성 화면이 두 종류의 진행 상태를 합쳐 보여줘야 한다.

어느 선택지든 #43에서 함께 정해야 할 것:

- 검증 위치: 선택기 `limit`(B·C)과 Web 검증(A는 필수), 서버 검증을 어떻게 나눌지.
- 권한 거부 계약: 거부·영구 거부를 나타내는 Call 오류 코드와 "설정 열기" Call.
- 진행률 Event 빈도, 취소·재시도, WebView 재로드 뒤 상태 복구.
- WebView 패키지 결정(#38)에 걸리는 조건: Android 파일 선택 훅, iOS 18.4 open panel, 커스텀 스킴·요청 가로채기, 바이너리 메시지 지원.
- 가짜 API 업로드 엔드포인트가 proxy를 지나는지(10MB 버퍼 한도) [54].
- 검증 환경: iOS 시뮬레이터에서 카메라 경로를 어떻게 확인할지.

## 확인하지 못한 것과 새로 생긴 질문

확인하지 못한 것:

- base64 Bridge 전달의 크기별 실제 시간·메모리. 프로토타입에서 측정이 필요하다.
- WebView 안의 XHR 업로드가 Host가 백그라운드로 간 뒤 얼마나 이어지는지(iOS, Android 모두).
- WKWebView에서 카메라 권한이 거부됐을 때 `UIImagePickerController`가 보여주는 화면과 Web이 받는 이벤트, Info.plist 키가 없을 때 경로 A 카메라 항목의 동작.
- WebKit이 카메라 단일 촬영 영상도 다시 내보내는지, PHPicker `compatible` 변환에 걸리는 시간과 그동안 Web이 받는 피드백.
- WebKit이 켜는 비공개 옵션(`_setAllowsDownscaling`, `_setShowsFileSizePicker`)이 실제로 사용자에게 크기 선택 UI를 주는지 [11].
- Android 훅에서 `file://`과 `content://` 중 무엇을 돌려줘야 하는지와 WebView `allowFileAccess` 설정의 영향, 빈 목록을 돌려줄 때 Web에 `cancel` 이벤트가 오는지.
- 커스텀 스킴이나 `appassets.androidplatform.net` URL을 다른 origin의 Web이 `fetch`할 때 필요한 CORS 헤더와 Range 지원.
- Android WebView의 HEIC 디코딩 지원(Web 편집 시).
- iOS 시뮬레이터의 카메라 가용성. Apple 문서는 시뮬레이터에 일부 하드웨어 기능이 없을 수 있으니 가용성 API로 확인하고 실기기에서 시험하라고만 하며 [67], WebKit은 카메라가 없으면 카메라 항목을 숨기고 `capture`도 무시한다 [11].

새로 생긴 질문:

- WebView 패키지 결정(#38): 파일 선택 훅(iOS 18.4 open panel 포함), 커스텀 스킴·요청 가로채기, 바이너리 메시지를 비교 기준에 넣을지.
- Bridge 계약 형태(#39): 큰 페이로드(청크, 파일 핸들), 진행률 Event 빈도, 취소 Call, 권한 오류 코드의 공통 형식.
- 로그인과 세션(#42): Host가 업로드할 때의 인증 수단(세션 공유 또는 업로드 전용 URL·토큰).
- 가짜 API: 업로드 엔드포인트의 본문 처리 방식과 용량 한도, 이어 올리기를 흉내 낼지, proxy 매처에서 뺄지.
- 개발용 가짜 Host와 테스트(#37, #47): 브라우저와 자동화 테스트에서 Host 선택기·카메라·권한 거부·업로드 진행률을 어떻게 대신할지.

## 출처

1. Android Developers, `WebChromeClient.onShowFileChooser`: https://developer.android.com/reference/android/webkit/WebChromeClient#onShowFileChooser(android.webkit.WebView,%20android.webkit.ValueCallback%3Candroid.net.Uri[]%3E,%20android.webkit.WebChromeClient.FileChooserParams)
2. Android Developers, `WebChromeClient.FileChooserParams`: https://developer.android.com/reference/android/webkit/WebChromeClient.FileChooserParams
3. flutter/packages, webview_flutter_android `android_webview_controller.dart`(`setOnShowFileSelector`, `FileSelectorParams`): https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_android/lib/src/android_webview_controller.dart#L629-L638
4. flutter/packages, webview_flutter_android `WebChromeClientProxyApi.java`: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_android/android/src/main/java/io/flutter/plugins/webviewflutter/WebChromeClientProxyApi.java#L77-L110
5. flutter/packages, webview_flutter_android CHANGELOG(3.2.0): https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_android/CHANGELOG.md
6. flutter/flutter#163965, "[webview_flutter] Android 14 - Camera not opening for input type="file"": https://github.com/flutter/flutter/issues/163965
7. flutter/flutter#118836, "[webview_flutter] Add example file chooser callback to README": https://github.com/flutter/flutter/issues/118836
8. flutter_inappwebview v6.1.5, `InAppWebViewChromeClient.java`: https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/in_app_webview/InAppWebViewChromeClient.java#L985-L1090
9. flutter_inappwebview CHANGELOG(6.2.0-beta.3): https://github.com/pichillilorenzo/flutter_inappwebview/blob/17527cae5a3371c1e87f9c1df4281a7710debf28/flutter_inappwebview/CHANGELOG.md
10. Android Developers, `MediaStore`(`ACTION_IMAGE_CAPTURE`, `getPickImagesMaxLimit`): https://developer.android.com/reference/android/provider/MediaStore
11. WebKit, `WKFileUploadPanel.mm`: https://github.com/WebKit/WebKit/blob/2edaa071178a43a44dfaa4c37716247c43642c66/Source/WebKit/UIProcess/ios/forms/WKFileUploadPanel.mm
12. WebKit, `UnifiedWebPreferences.yaml`(`PhotoPickerPrefersOriginalImageFormat`): https://github.com/WebKit/WebKit/blob/513284123393281aba066f5e044cce3151ca93fc/Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml#L4825-L4832
13. WebKit, `PlatformEnableCocoa.h`(`ENABLE_TRANSCODE_UIIMAGEPICKERCONTROLLER_VIDEO`): https://github.com/WebKit/WebKit/blob/577d6b79b2a2667f5e89abb756974296b5d1523e/Source/WTF/wtf/PlatformEnableCocoa.h#L958-L961
14. Apple Developer, `PHPickerConfiguration.preferredAssetRepresentationMode`: https://developer.apple.com/documentation/photosui/phpickerconfiguration-swift.struct/preferredassetrepresentationmode
15. Apple Developer, `PHPickerConfiguration.selectionLimit`: https://developer.apple.com/documentation/photosui/phpickerconfiguration-swift.struct/selectionlimit
16. Apple Developer, `webView(_:runOpenPanelWith:initiatedByFrame:completionHandler:)`: https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:runopenpanelwith:initiatedbyframe:completionhandler:)
17. Apple Developer, `WKOpenPanelParameters`: https://developer.apple.com/documentation/webkit/wkopenpanelparameters
18. flutter/packages, webview_flutter_wkwebview `UIDelegateProxyAPIDelegate.swift`: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_wkwebview/darwin/webview_flutter_wkwebview/Sources/webview_flutter_wkwebview/UIDelegateProxyAPIDelegate.swift
19. flutter_inappwebview, macOS `InAppWebView.swift`(`runOpenPanelWith`): https://github.com/pichillilorenzo/flutter_inappwebview/blob/17527cae5a3371c1e87f9c1df4281a7710debf28/flutter_inappwebview_macos/macos/flutter_inappwebview_macos/Sources/flutter_inappwebview_macos/InAppWebView/InAppWebView.swift
20. WHATWG HTML Standard, File Upload state (`type=file`): https://html.spec.whatwg.org/multipage/input.html#file-upload-state-(type=file)
21. W3C, HTML Media Capture(Recommendation, 2018-02-01): https://www.w3.org/TR/html-media-capture/
22. WHATWG, XMLHttpRequest Standard: https://xhr.spec.whatwg.org/
23. whatwg/fetch#607, "FetchObserver (for a single fetch)": https://github.com/whatwg/fetch/issues/607
24. W3C, File API(Working Draft, 2026-09-12): https://www.w3.org/TR/FileAPI/
25. IETF, draft-ietf-httpbis-resumable-upload(Resumable Uploads for HTTP): https://datatracker.ietf.org/doc/draft-ietf-httpbis-resumable-upload/
26. flutter/packages, image_picker README: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/image_picker/image_picker/README.md
27. flutter/packages, image_picker `image_picker.dart`(`requestFullMetadata`, `limit`): https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/image_picker/image_picker/lib/image_picker.dart
28. flutter/packages, image_picker_ios `FLTImagePickerPlugin.m`: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/image_picker/image_picker_ios/ios/image_picker_ios/Sources/image_picker_ios/FLTImagePickerPlugin.m
29. flutter/packages, image_picker_android README: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/image_picker/image_picker_android/README.md
30. flutter/packages, image_picker_android CHANGELOG(0.8.13+22): https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/image_picker/image_picker_android/CHANGELOG.md
31. flutter/packages, image_picker_android `ImagePickerUtils.java`: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/image_picker/image_picker_android/android/src/main/java/io/flutter/plugins/imagepicker/ImagePickerUtils.java
32. flutter/packages, image_picker_android `FileUtils.java`: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/image_picker/image_picker_android/android/src/main/java/io/flutter/plugins/imagepicker/FileUtils.java#L62-L72
33. flutter/packages, image_picker_android `ImagePickerDelegate.java`: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/image_picker/image_picker_android/android/src/main/java/io/flutter/plugins/imagepicker/ImagePickerDelegate.java
34. flutter/packages, webview_flutter_platform_interface `javascript_message.dart`: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_platform_interface/lib/src/types/javascript_message.dart
35. flutter/packages, webview_flutter `webview_controller.dart`(`runJavaScript`): https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter/lib/src/webview_controller.dart
36. Apple Developer, `WKScriptMessage.body`: https://developer.apple.com/documentation/webkit/wkscriptmessage/body
37. Android Developers, AndroidX `WebMessageCompat`: https://developer.android.com/reference/androidx/webkit/WebMessageCompat
38. flutter/packages, webview_flutter_android `pigeons/android_webkit.dart`: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_android/pigeons/android_webkit.dart
39. RFC 4648, The Base16, Base32, and Base64 Data Encodings, §4: https://www.rfc-editor.org/rfc/rfc4648#section-4
40. Apple Developer, `WKWebViewConfiguration.setURLSchemeHandler(_:forURLScheme:)`: https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/seturlschemehandler(_:forurlscheme:)
41. Android Developers, AndroidX `WebViewAssetLoader`: https://developer.android.com/reference/androidx/webkit/WebViewAssetLoader
42. flutter/packages, webview_flutter_wkwebview `pigeons/web_kit.dart`: https://github.com/flutter/packages/blob/0259ad7e515b74f6855c4c72d81abe2231fe31d3/packages/webview_flutter/webview_flutter_wkwebview/pigeons/web_kit.dart
43. flutter_inappwebview v6.1.5, `platform_webview.dart`(`onLoadResourceWithCustomScheme`, `shouldInterceptRequest`): https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/in_app_webview/platform_webview.dart
44. flutter_inappwebview v6.1.5, `custom_scheme_response.dart`: https://github.com/pichillilorenzo/flutter_inappwebview/blob/v6.1.5/flutter_inappwebview_platform_interface/lib/src/types/custom_scheme_response.dart
45. Capacitor Docs(v8), Web API `convertFileSrc`: https://capacitorjs.com/docs/core-apis/web#convertfilesrc
46. cfug/dio, dio README: https://github.com/cfug/dio/blob/main/dio/README.md
47. background_downloader README: https://github.com/781flyingdutchman/background_downloader/blob/main/README.md
48. background_downloader, Uploads 문서: https://github.com/781flyingdutchman/background_downloader/blob/main/doc/uploads.md
49. background_downloader, Lifecycle 문서: https://github.com/781flyingdutchman/background_downloader/blob/main/doc/lifecycle.md
50. Apple Developer, `URLSessionConfiguration.background(withIdentifier:)`: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)
51. Apple Developer, `URLSession.uploadTask(withResumeData:)`: https://developer.apple.com/documentation/foundation/urlsession/uploadtask(withresumedata:)
52. Android Developers, User-initiated data transfer: https://developer.android.com/develop/background-work/background-tasks/uidt
53. Android Developers, Photo picker: https://developer.android.com/training/data-storage/shared/photopicker
54. Next.js Docs, `proxyClientMaxBodySize`: https://nextjs.org/docs/app/api-reference/config/next-config-js/proxyClientMaxBodySize
55. Apple Developer, Delivering an Enhanced Privacy Experience in Your Photos App: https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app
56. Apple Developer, Requesting authorization to capture and save media: https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media
57. Apple Developer, `NSCameraUsageDescription`: https://developer.apple.com/documentation/bundleresources/information-property-list/nscamerausagedescription
58. Apple Developer, `NSMicrophoneUsageDescription`: https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription
59. Apple Developer, `UIApplication.openSettingsURLString`: https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring
60. Android Developers, Request runtime permissions: https://developer.android.com/training/permissions/requesting
61. Baseflow, permission_handler README: https://github.com/baseflow/flutter-permission-handler/blob/main/permission_handler/README.md
62. Apple Developer, `PHAuthorizationStatus.limited`: https://developer.apple.com/documentation/photos/phauthorizationstatus/limited
63. Play Console Help, Understanding Restricted Permissions with minimum scope alternatives(Photo and Video Permissions): https://support.google.com/googleplay/android-developer/answer/14115180
64. Android Developers, Grant partial access to photos and videos(Android 14): https://developer.android.com/about/versions/14/changes/partial-photo-video-access
65. hnvn/flutter_image_cropper, image_cropper README: https://github.com/hnvn/flutter_image_cropper/blob/master/image_cropper/README.md
66. WHATWG HTML Standard, ImageBitmap and animations(`createImageBitmap`): https://html.spec.whatwg.org/multipage/imagebitmap-and-animations.html
67. Apple Developer, Running your app on simulated or physical devices: https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices
68. WHATWG, Fetch Standard(`RequestInit.signal`): https://fetch.spec.whatwg.org/#dom-requestinit-signal
69. Next.js Docs, `proxy.js` 파일 규칙(v16.0.0에서 Middleware 이름 변경): https://nextjs.org/docs/app/api-reference/file-conventions/proxy
70. Baseflow, permission_handler_platform_interface `permission_status.dart`: https://github.com/baseflow/flutter-permission-handler/blob/main/permission_handler_platform_interface/lib/src/permission_status.dart
