---
status: partially superseded by ADR-0018
---

# 경로 표는 계약 원천에 두고, 허용 출처는 환경 파일에 둔다

경로 표는 계약 원천 YAML의 `routes` 절에 둔다. 생성기가 Dart·TypeScript 계약 패키지로 표를 내보내고, Host·Web·가짜 Host가 모두 이 표를 읽는다. 행마다 딥링크와 콘텐츠 속 링크로 열 수 있는지, 그리고 그 경로가 어느 WebView(`tab`·`stacked`·`compose`·`handoff`)의 메인 프레임이 될 수 있는지를 적는다. Android intent-filter 블록도 이 표에서 생성하고, AASA는 Web이 표에서 만들어 서빙한다. 허용 출처는 환경마다 값이 다르므로 원천에 넣지 않는다. `APP_ORIGIN`은 Host의 `app/config/<env>.json`과 Web의 `web/.env.<env>`에 따로 적고, PR 워크플로가 둘이 같은지 검사한다. 경로 표는 모든 환경에서 같고, Host와 Web이 함께 지키는 약속이다. 그래서 Call·Event처럼 버전과 호환성 검사를 받는다.

## Considered Options

- **경로 표를 `routes.yaml`로 따로 두고 생성기를 하나 더 만든다**: 계약 패키지와 같은 전달 통로를 또 만들어야 하고, 버전 규칙과 호환성 검사도 따로 둬야 한다.
- **Host와 Web에 손으로 두 벌 적고 공유 픽스처로 맞춘다**: 표가 하나 바뀔 때마다 두 곳을 고쳐야 한다. 또 intent-filter와 AASA를 만들 원천이 없다.
- **허용 출처도 원천에 넣는다**: 원천이 환경을 알게 된다. 그러면 환경마다 생성물이 달라져, 커밋한 생성물을 CI diff로 검사하는 방식이 성립하지 않는다.
- **허용 출처 두 환경 파일을 한 파일에서 생성한다**: 값 두 개와 환경 셋을 위해 생성 단계를 하나 더 두는 것보다 일치 검사 하나가 가볍다.

## Consequences

- 판정 함수는 각 계약 패키지에 손으로 쓴다. 두 언어의 판정은 공유 픽스처로 맞춘다. 일치 규칙은 이렇다. `{id}`는 세그먼트 하나이고, 퍼센트 디코딩한 값이 `[A-Za-z0-9_-]{1,64}`여야 한다. 대소문자를 구분하고, 끝의 `/` 하나는 지운다. `..`, 빈 세그먼트, `%2F`가 있으면 표 밖으로 본다. 메인 프레임 이동은 경로만 판정하고 쿼리와 프래그먼트는 통과시킨다.
- 경로 추가와 삭제는 minor다. 있는 id의 경로를 바꾸거나 WebView 종류를 좁히는 것은 major다. 경로를 바꾸려면 새 id를 추가한 뒤 옛 id를 지운다.
- intent-filter의 host는 모든 빌드에서 `fan.example`로 고정한다. 로컬 빌드도 공유 링크의 경로만 받아 자기 허용 출처에서 연다. AASA는 원격 Web이 늘 최신 표로 내준다. 그래서 앱에 묶인 intent-filter와 어긋날 수 있지만, Host 판정이 마지막에 거른다.
- 공유 링크 출처 `https://fan.example`은 모든 환경에서 같으므로 원천의 `constants`에 둔다. Web은 콘텐츠 속 링크를 셋으로 나눈다. 허용 출처나 이 출처이면서 `contentLink`인 경로는 앱 안에서 이동한다. 두 출처의 다른 경로는 링크로 만들지 않는다. 나머지는 `browser.open`으로 연다.
- 플랫폼 코드는 자기 설정을 읽지 않는다. Android 주입 규칙과 iOS 판정은 어댑터 층이 넘긴 `APP_ORIGIN`을 쓴다. `EMBED_ORIGIN`은 Web에만 있다.

결정의 자세한 내용: [허용 출처·경로 표의 정의와 공유](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/57)
