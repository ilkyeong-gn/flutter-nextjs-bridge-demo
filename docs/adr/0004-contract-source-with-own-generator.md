# Bridge 계약은 JSON Schema 부분집합 원천 하나에 적고, 생성기와 호환성 검사기는 직접 만든다

Bridge 계약(Call·Message·Event의 payload와 메타데이터)은 언어 중립 원천 파일(YAML) 하나에만 적는다. 생성기와 호환성 검사기는 직접 만든 작은 Node 스크립트다. 생성기는 이 원천에서 Dart와 TypeScript의 타입, 디코더, 타입 안전한 진입점, Markdown 계약 문서를 만든다. 기성 도구는 쓰지 않는다. 확인한 범위에서는 한 원천에서 양쪽 타입과 검증을 모두 만들어 주는 기성 도구가 없었다. 게다가 기성 도구는 Dart 유니언을 평탄화하거나 `Object`로 만든다. 모르는 필드를 처리하는 방식도 도구마다 다르고, 타임아웃·Event 종류·`since` 같은 메타데이터를 담을 곳도 없다. 원천을 JSON Schema의 작은 부분집합(object, string, number, integer, boolean, enum, array, optional, nullable, `$ref`, 판별 유니언)으로 제한하기 때문에, 생성기와 검사기는 직접 유지할 만한 크기로 남는다.

## Considered Options

- **JSON Schema + 기성 생성기(quicktype, Zod/Ajv)**: Dart에서는 판별 유니언이 nullable 필드로 평탄화된다. 모르는 필드를 처리하는 방식이 양쪽에서 같다고 보장할 수 없다.
- **TypeSpec**: 안정판 JSON Schema 이미터가 `@discriminated`와 versioning을 반영하지 않고, Dart 이미터도 없다.
- **Protobuf + ProtoJSON**: 이 선택지에만 `buf breaking`이 있다. 하지만 자체 봉투(`kind`·`id`)의 JSON 모양을 ProtoJSON이 정하게 되고, Dart에서 쓸 제약 검증이 없다.
- **Zod 원천**: Web 쪽만 편하다. 원천이 TypeScript에 묶이고, Dart는 첫 번째 선택지와 같은 한계를 진다.
- **양쪽 손작성 + 공유 픽스처**: 두 정의가 일치한다는 보장이 픽스처 범위까지뿐이다.

## Consequences

- 봉투(`kind`·`id`·에러 객체)는 원천에 넣지 않고 양쪽 Bridge 모듈에 손으로 고정한다. 원천에는 payload와 메타데이터만 들어간다.
- 생성물은 커밋한다. 그래서 Host 빌드에 Node가 필요 없다. CI는 다시 생성한 결과가 커밋된 생성물과 다르면 실패한다.
- `buf breaking`에 해당하는 검사는 직접 만든 검사기가 맡는다. 원천을 버전마다 스냅숏으로 남기고, 현재 원천과의 차이를 분류해 major·minor가 맞게 올랐는지 확인한다. 같은 major 안에서는 이전 버전의 픽스처를 계속 디코딩할 수 있어야 한다.
- Demo 스펙이 범위 밖으로 뒀던 Message 규약 코드 생성기를 Reference App에서는 둔다.

결정의 자세한 내용: [Bridge 계약 단일 원천 결정](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/40)
