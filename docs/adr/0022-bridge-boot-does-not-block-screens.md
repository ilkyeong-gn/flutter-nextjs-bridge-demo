# Bridge를 기다리며 화면을 막지 않고, 실패는 쓰는 자리와 띠로만 보인다

`BridgeBoot`는 자식 화면을 핸드셰이크 뒤로 미루지 않는다. Web의 데이터는 Bridge가 아니라 HTTP로 오고 모든 페이지가 동적으로 렌더링되므로, SSR한 화면은 Bridge 상태와 상관없이 바로 보인다. `connecting` 동안 부른 Call은 `hello` 전 대기열에서 기다린다. Bridge 없음이 되면 Call은 `unavailable`로 실패한다. 그 실패는 그 기능을 쓰는 자리에서만 드러난다. 화면 전체를 덮는 로딩이나 안내는 없다. 사유 몇 가지만 `BridgeBoot`가 화면을 막지 않는 띠(`role="status"`)로 미리 알린다.

| 상태 | 띠 |
| --- | --- |
| `connecting` | 없음 |
| `major` | "앱을 최신 버전으로 업데이트해 주세요" + "다시 불러오기", 닫을 수 없음 |
| `handshake` | "앱과 연결하지 못했어요" + "다시 불러오기" |
| `no-channel`, 운영 빌드 | 없음 |
| `no-channel`, 개발 모드 | "가짜 Host가 꺼져 있어요 — `?fakeHost=1`로 켜기" |

이 ADR은 이슈 26의 `BridgeBoot`가 Bridge 없음을 "다시 불러오기" 전체 안내 하나로 그리던 것을 대체한다.

## Considered Options

- **`ready`까지 앱 전체를 로딩으로 덮고, Bridge 없음이면 전체 안내를 보인다(이슈 26)**: 기능 코드가 `connecting`을 생각하지 않아도 된다. 하지만 문서를 열 때마다 첫 화면이 핸드셰이크만큼 늦어진다. 핸드셰이크가 실패하면 Bridge 없이도 읽을 수 있는 내용까지 가린다.
- **경로마다 `<RequireBridge>`로 감싼다**: 어떤 화면이 Bridge를 기다려야 하는지는 화면 구성이 정해져야 안다. 지금은 감쌀 화면이 없다.
- **`major`의 방향을 사유로 나눈다(`major-host-old`·`major-web-old`)**: 문구를 정확하게 쓸 수 있다. 하지만 `status` 모양이 바뀐다. Web이 옛것인 경우는 배포 순서를 지키면 드물고, 다시 불러오면 대개 풀린다. 그래서 띠 하나에 업데이트 문구와 다시 불러오기를 함께 둔다.

## Consequences

- 기능 코드는 `connecting`을 견뎌야 한다. Bridge 기능의 컨트롤은 상태가 정해지기 전에도 누를 수 있고, 그 Call은 대기열에서 기다린다.
- 외부 링크 관문의 "열 수 없음"(Bridge 없음의 `unavailable`, 기능 목록에 없는 `unsupported`)은 짧은 알림으로 보인다([ADR 0018](0018-thin-nav-gate-and-no-origin-env.md)). `<AppLink>`의 기본 처리는 "링크를 열 수 없어요" 알림이다. `useAppNavigation()`을 쓰는 쪽은 실패 결과를 받아 직접 처리한다. 알림 자리는 `BridgeBoot` 근처의 `role="status"` live region 하나와 `notify(text)`뿐이다. 토스트 컴포넌트는 기반에 두지 않는다.
- "다시 불러오기"는 `shared/nav`의 `reloadDocument()`로 한다. `location`은 Biome로 막혀 있기 때문이다.
- `hello` 타임아웃은 다른 메서드 기본값과 같은 10초다. 이 값은 계약 메타 표가 아니라 `shared/bridge`의 `hello` 판정에 상수로 둔다. 짧게 잡아 늦은 기기에서 잘못 Bridge 없음이 되면 문서를 다시 불러올 때까지 회복할 수 없다. 반면 화면을 막지 않으므로 길게 잡아도 비용이 작다.
- 운영 빌드의 일반 브라우저에서는 내용이 그대로 읽힌다. Bridge 기능은 쓰는 순간 그 자리에서 실패한다.
- 브라우저 테스트는 띠와 알림을 접근성 이름으로 찾는다([ADR 0021](0021-browser-tests-on-production-build.md)). `hello: 'silent'`의 10초는 Playwright `page.clock`으로 앞당긴다. 운영 빌드에 타임아웃을 바꾸는 테스트 경로는 두지 않는다. `page.clock`이 init script보다 먼저 타이머를 잡는지는 첫 테스트에서 확인한다.
- Host 쪽 로딩·에러 화면이 첫 문서 로딩과 네트워크 실패를 어떻게 덮을지는 아직 정하지 않았다.

결정의 자세한 내용: [Bridge 시작 상태와 실패 화면 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/69)
