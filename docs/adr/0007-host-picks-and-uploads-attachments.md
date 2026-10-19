# 사진·영상은 Host가 고르고 Host가 올린다 (file input을 쓰지 않는다)

글쓰기의 사진·영상은 Web의 `<input type="file">`을 쓰지 않는다. Host가 첨부 방법 시트, 선택기, 카메라를 띄운다. 고른 첨부는 Host가 가지고 있다가 직접 서버에 올린다. Web은 첨부 id와 작은 썸네일, 업로드 진행률, 결과 미디어 id만 받는다. 글 등록은 Web이 미디어 id로 한다. 바이트는 Bridge를 지나지 않고, Web은 파일을 보지 않는다.

## Considered Options

- **file input(경로 A)**: Web 코드가 가장 단순하고 일반 브라우저에서도 똑같이 동작한다. 하지만 iOS에서는 WebKit이 선택기를 띄워 Host가 끼어들 수 없다. 그래서 첨부 방법 시트, 10장 제한, 카메라 거부 안내를 지킬 수 없다. Android는 어차피 Host가 `setOnShowFileSelector`로 선택기를 붙여야 한다.
- **Host가 고르고 Web이 올린다(경로 B)**: 바이트를 Web으로 옮길 길이 없다. 바이너리는 Bridge에 싣지 않기로 했고([ADR 0003](0003-events-over-platform-reply-channel.md)의 계약 결정), iOS에서는 커스텀 스킴으로 Host 파일을 URL로 보여 줄 수 없다([ADR 0002](0002-webview-package-with-platform-code.md)). base64는 100MB 영상에 맞지 않는다.

## Consequences

- Bridge 표면이 넓어진다: `media.pick`, `media.discard`, `upload.start`·`upload.cancel`, `upload.progress`·`upload.finished`·`upload.failed`, `app.openSettings`, 상태 Event `permission.camera`.
- Host가 업로드 인증(Host access token)을 가진다. 업로드 주소는 Host 설정에서 만든다.
- 첨부는 그것을 고른 WebView에 묶인다. 문서가 바뀌면(`hello`가 다시 오면) Host가 첨부와 진행 중인 업로드를 버린다. 백그라운드 전송과 이어 올리기는 하지 않는다.
- Android에서 file input이 열리면 Host가 빈 목록을 돌려줘 막는다.
- 개발용 가짜 Host가 선택과 업로드 진행률까지 흉내 내야 한다.

결정의 자세한 내용: [사진·영상 첨부와 업로드 설계 (S2)](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/43)
