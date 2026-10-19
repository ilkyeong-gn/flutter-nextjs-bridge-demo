# Bridge 계약 단일 원천과 Dart·TypeScript 코드 생성 조사

- **질문**: [#30 Bridge 계약 단일 원천과 Dart·TypeScript 코드 생성 조사](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/30)
- **조사일**: 2026-10-19
- **확인한 버전**: quicktype 26.0.0 · TypeSpec 1.17.0(@typespec/compiler, @typespec/json-schema), 0.87.0(@typespec/protobuf, @typespec/versioning) · @bufbuild/protobuf·@bufbuild/protoc-gen-es 2.16.0, @bufbuild/buf 1.74.0, @bufbuild/protovalidate 1.3.0 · protobuf(Dart) 6.1.0, protoc_plugin 25.1.0 · zod 4.6.7 · AsyncAPI 명세 3.1.0, @asyncapi/modelina 5.10.1(안정판)·6.0.0-next.18, @asyncapi/cli 6.2.1 · ajv 8.20.0 · json-schema-to-typescript 16.0.0 · typebox 1.4.2 · freezed 4.0.3, json_serializable 6.14.1, json_annotation 4.12.0, build_runner 2.17.1, dart_mappable 4.10.0, json_schema(Dart) 5.2.2 · 실행 확인 환경: Node 26.12.0, Flutter 3.47.7 / Dart 3.13.5

## 요약

- 이번에 확인한 범위에서는 한 원천에서 Dart와 TypeScript 양쪽의 **타입과 런타임 검증을 모두** 만들어 주는 도구가 없었다. 어느 후보를 골라도 "TS 타입", "TS 검증", "Dart 타입", "Dart 검증" 가운데 일부는 다른 도구나 손작성으로 채워야 한다.
- 후보를 가장 크게 가르는 기준은 **판별 유니언**이다. TS 쪽은 protobuf-es, Zod, json-schema-to-typescript, Modelina가 유니언 타입을 만든다(quicktype만 평탄화한다). 하지만 이번에 확인한 생성기 중 Dart에서 sealed class를 만드는 것은 없었다. quicktype은 변형들을 한 클래스로 합쳐 변형 전용 필드를 모두 nullable로 만들고, Modelina는 `Object`로 내보내고, protobuf.dart는 `whichX()` enum으로 표현한다. Dart에서 sealed class와 완전성 검사를 쓰려면 freezed·dart_mappable이나 손작성이 필요하다.
- **JSON Schema + quicktype**이 가장 가볍다. Node CLI 하나로 TS(런타임 검사 포함)·Zod·Dart(런타임 의존 없음)를 만든다. 대신 유니언이 평탄화되고, Dart `fromJson`은 타입 캐스트 수준에서만 검사한다. 생성된 Dart를 실행해 보니 `toJson`이 다른 변형의 키를 `null`로 채워 보냈고, TS 쪽 strict 스키마가 이 JSON을 거부했다.
- **TypeSpec**은 정의 언어로서 연산(`op`), 판별 유니언, 버전 데코레이터까지 표현한다. 하지만 안정판 JSON Schema 이미터는 데이터 타입만 내보내고, 유니언의 `@discriminated`를 반영하지 않으며(1.17.0 실행 확인), versioning 라이브러리와 연결되지 않는다. Dart 이미터가 없으므로 JSON Schema나 Protobuf를 거치는 2단 생성이 된다.
- **Protocol Buffers**는 스키마 진화 규칙(필드 번호, `reserved`)을 갖췄고, 이번 조사에서 자동 호환성 검사 도구(`buf breaking`의 WIRE_JSON)까지 확인된 것은 이 후보뿐이다. 생성 결과는 TS에서 판별 유니언, Dart에서 null 없는 기본값과 `hasX()`/`whichX()`다. 다만 Bridge가 JSON 문자열을 주고받으면 ProtoJSON 규칙(필드·enum 이름이 그대로 실림, 기본값 생략, int64는 문자열, oneof는 설정된 멤버의 키)을 따라야 해서 Message의 JSON 모양을 자유롭게 정할 수 없다. 제약 검증(protovalidate)은 TS 구현만 있고 Dart 구현은 없다.
- **Zod → JSON Schema → Dart**는 TS 쪽 검증과 타입 추론이 가장 좋다(Zod 4의 `discriminatedUnion` → `oneOf`). Dart 쪽은 JSON Schema 경로의 한계를 그대로 이어받는다(실행 확인).
- **AsyncAPI 3.x**는 channel·operation(`send`/`receive`)·`reply`로 Event와 Call의 짝을 문서화하기에 가장 잘 맞는다. 하지만 코드 생성기 Modelina는 Dart 유니언을 `Object`로, 모든 필드를 nullable로 만들고, 안정판은 AsyncAPI 3.1과 JSON Schema 2020-12를 받지 않는다. 예시 계약에서는 컴파일되지 않는 Dart enum과 이름이 바뀐 TS 속성도 나왔다(실행 확인). 문서의 원천으로는 쓸 만하지만 코드의 원천으로는 약하다.
- **손작성 + 공유 JSON 픽스처**는 양쪽에서 관용적인 코드(TS의 Zod, Dart의 sealed class·freezed)와 가장 넓은 검증 선택지를 주고 생성기에 묶이지 않는다. 대신 원천이 둘이 되고, 두 정의가 일치한다는 보장은 픽스처가 다루는 범위까지만이다.
- 받는 쪽이 모르는 필드나 변형을 만났을 때의 **기본 동작이 도구마다 다르다**(거부, 무시, 제거). 이 기본값은 Host와 Web의 버전 어긋남 대응([#35](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/35))과 직접 맞물린다.
- 유지보수 측면에서 모든 후보가 2026년에 릴리스를 냈다. 다만 Modelina 안정판의 마지막 릴리스는 2025-10이고, TypeSpec의 protobuf·versioning 패키지는 아직 preview(0.x)다.

## 상세

### 확인 방법과 예시 계약

- 버전과 게시일은 npm 레지스트리와 pub.dev API의 `latest`를 기준으로 했다 [64].
- 문서만으로 판단하기 애매한 생성 결과는 같은 계약을 각 도구로 직접 생성해 확인했고, 본문에 "(실행 확인)"으로 표시했다. 예시 계약은 S4의 멤버십 변경 Event `membershipChanged`다. `membership.status`는 `none`·`active`·`expired` 중 하나인 판별 유니언이고, `active`만 `tier`(`basic`|`premium`)와 `expiresAt`을, `expired`만 `expiredAt`을 가진다. 여기에 선택 필드 `note: string | null`을 더했다.

### 1. JSON Schema + 코드 생성기 (quicktype 등)

**quicktype 26.0.0**

- 26.0.0(2026-07-20)은 24–26을 연달아 낸 뒤의 정리 릴리스이고, 패키지 실행에 Node.js 20.19 이상이 필요하다 [1].
- Dart 출력에는 null safety를 켜고 끄는 옵션이 없다. 옵션은 `required-props`, `final-props`(기본 켬), `copy-with`, `use-freezed`, `use-json-annotation` 등이다 [2]. 렌더러는 nullable 타입에 `?`를 붙인다 [3]. 기본 출력은 외부 패키지 없이 `dart:convert`만 쓰는 `fromJson`/`toJson`이다(실행 확인).
- Dart 렌더러는 `T | null`이 아닌 유니언을 `dynamic`으로 내보낸다 [3]. 객체 변형들로 된 `oneOf`는 렌더링 전에 한 클래스로 합쳐진다. 예시 계약에서는 `Membership { Status status; DateTime? expiresAt; Tier? tier; DateTime? expiredAt; }` 하나가 나왔고, `--use-freezed`를 줘도 결과는 같았다. TS의 `interface Membership`과 Zod의 `z.object` 출력도 똑같이 평탄화됐다(실행 확인).
- TS 출력은 `runtime-typecheck` 옵션이 기본으로 켜져 있어 `JSON.parse` 결과를 런타임에 검사하는 `Convert` 클래스를 함께 만든다 [4][5]. 스키마에 `additionalProperties: false`가 있으면 모르는 키를 거부한다(생성 코드로 확인).
- Zod 렌더러도 있지만 유니언은 `z.union`으로만 내보낸다 [6].
- Dart `fromJson`이 하는 일은 스키마 검증이 아니라 캐스트다. 판별자 `status`에 모르는 값이 오면 `!`에서 `TypeError`가 나고, 선택 enum `tier`에 모르는 값이 오면 조용히 `null`이 되며, 모르는 키는 무시된다(실행 확인).
- 평탄화된 Dart `toJson`은 다른 변형의 키까지 `null`로 채워 보낸다. `none` 변형은 `{"status":"none","expiresAt":null,"tier":null,"expiredAt":null}`이 됐고, 이 JSON을 TS 쪽 Zod strict 판별 유니언으로 파싱하면 `unrecognized_keys`로 실패했다(실행 확인).

**그 밖의 JSON Schema 도구**

- json-schema-to-typescript 16.0.0은 타입만 만든다. `oneOf`를 `anyOf`처럼 다루고 `const`를 리터럴 타입으로 바꾸므로, 변형마다 `const` 판별자가 있으면 TS 판별 유니언이 된다 [7].
- TS 런타임 검증은 Ajv 8.20.0이 맡을 수 있다. `discriminator` 키워드는 생성자 옵션으로 켜야 동작한다 [8]. 빌드할 때 검증 함수를 미리 만들어 두는 standalone 모드를 쓰면 `Function` 생성자 없이 동작하므로 CSP 제약이 있는 페이지에서도 쓸 수 있다 [9].
- Dart 런타임 검증 도구로는 `json_schema` 5.2.2가 있다. 4.0에서 Draft 2019-09와 2020-12 지원이 추가됐고, 그때 기본 draft는 호환성을 위해 draft7로 남았다 [10]. labs.flutter.dev가 게시한 `json_schema_builder` 0.1.7도 Draft 2020-12 준수를 내세우지만 아직 0.x다 [11].

### 2. TypeSpec

- 1.0 GA(2025-05)에서 compiler, http, openapi3와 함께 `@typespec/json-schema`가 안정판이 됐다. `@typespec/protobuf`, `@typespec/versioning`, 언어별 클라이언트·서버 생성기는 preview로 남았다 [12]. 2026-10 현재 protobuf·versioning 패키지는 0.87.0이다.
- 표준 라이브러리의 `@discriminated`는 유니언의 직렬화 모양을 정한다. 기본은 `{kind, value}` 봉투이고, `envelope: "none"`이면 판별자가 객체 안에 들어간다 [13].
- JSON Schema 이미터는 유니언을 기본으로 `anyOf`, `@oneOf`가 붙으면 `oneOf`로 내보낸다. 모델 상속에 쓰는 `@discriminator`는 `polymorphic-models-strategy`를 `oneOf`나 `anyOf`로 설정했을 때만 판별 유니언 스키마가 된다(기본값은 `ignore`) [14].
- 1.17.0으로 `@discriminated(#{ envelope: "none", discriminatorPropertyName: "status" })` 유니언을 내보내 보니 `status` 속성이 아예 없는 `anyOf`가 나왔다. 반면 `@discriminator("status")` 모델에 `polymorphic-models-strategy: oneOf`를 주면 `oneOf`와 변형별 `const`가 나왔다(실행 확인). 이미터 소스는 모델·enum·유니언·scalar 선언만 처리하고 연산(`op`)은 다루지 않는다 [15].
- versioning 라이브러리는 `@added`, `@renamedFrom`, `@madeOptional` 같은 데코레이터로 버전별 모양을 기술하고, 그 결과가 OpenAPI 출력에 버전별로 반영된다 [16]. 하지만 `@typespec/json-schema` 패키지는 versioning에 의존하지 않는다. versioning을 peer 의존성으로 두는 쪽은 openapi3다 [17][18].
- 1.17.0(2026-10-07)부터 Protobuf 이미터가 이름 있는 유니언을 `oneof`로 내보낸다 [19].
- 공식 저장소에는 Dart 이미터가 없다 [20]. 직접 만들려면 0.x인 emitter-framework(0.21.0)를 써야 한다.

### 3. Protocol Buffers (protobuf-es, protobuf.dart)

**protobuf-es 2.16.0 (TS)**

- oneof는 `{ case: "x"; value: X } | … | { case: undefined }` 형태의 판별 유니언이 된다. 서비스 정의에서는 타입이 붙은 스키마(`GenService`)만 만들고 전송 계층은 구현하지 않는다 [21].
- 메시지 필드는 선택 속성(`?: T | undefined`)이 되고, 암묵적 presence 스칼라는 기본값(`""`, `0`)을, 64비트 정수는 `bigint`를 쓴다 [22].
- ProtoJSON용 `toJson`/`fromJson`이 있다. `fromJson`은 기본적으로 모르는 필드와 enum 이름을 거부하고, `ignoreUnknownFields`로 완화할 수 있다 [23].

**protobuf.dart (protobuf 6.1.0, protoc_plugin 25.1.0)**

- 단일 필드의 getter는 값이 설정되지 않았으면 `null` 대신 기본값을 돌려준다. 값의 존재 여부는 `hasFoo()`/`clearFoo()`로 다룬다. oneof는 `enum Foo_Test { …, notSet }`과 `whichTest()`로 표현된다 [24].
- `mergeFromProto3Json`은 모르는 필드나 enum, 타입 불일치를 만나면 `FormatException`을 던진다. `ignoreUnknownFields`, `permissiveEnums` 옵션으로 완화할 수 있다 [25].
- protoc_plugin은 23.0.0부터 editions를 지원한다 [26]. 권장 설치 방법은 `dart pub global activate protoc_plugin`이고 [27], Buf Schema Registry에 원격 플러그인 `protocolbuffers/dart` v25.1.0도 있다 [28].

**ProtoJSON과 스키마 진화**

- ProtoJSON에서 필드 이름은 lowerCamelCase 키로, enum은 이름으로, int64는 10진 문자열로 나간다. presence가 없는 필드의 기본값은 생략된다. 파서는 모르는 필드를 기본적으로 거부하고 `null`은 값이 없는 것으로 본다 [29].
- 같은 문서는 ProtoJSON이 필드·enum 이름을 메시지에 넣기 때문에 이름을 나중에 바꾸기가 훨씬 어렵고, 필드를 지우면 파싱 오류가 나는 breaking change가 된다고 설명한다. 같은 oneof의 여러 멤버를 한꺼번에 내보내는 것도 금지된다(MUST NOT) [29]. 결국 JSON에서 oneof는 설정된 멤버의 키 하나로만 나타난다.
- 필드 번호는 바꿀 수 없다. 지운 필드는 번호를 `reserved`로 막아야 하고, JSON을 쓴다면 이름도 예약해야 한다 [30].
- `buf breaking`의 WIRE_JSON 범주는 바이너리나 JSON 인코딩을 깨는 변경(`json_name` 변경 등)을 잡는다. Buf 문서는 이것을 권장 최소 수준으로 안내하고, 기본 범주는 FILE이다 [31].
- protovalidate의 공식 구현은 Go, Java, Python, C++, TS/JS뿐이다 [32].
- `buf.gen.yaml`에서는 플러그인을 `local`(경로, 또는 명령과 인자의 목록), `remote`(BSR), `protoc_builtin` 중 하나로 지정한다 [33]. 따라서 `buf generate` 한 번으로 TS와 Dart를 함께 만들 수 있다.

### 4. Zod 같은 TS 스키마 → JSON Schema → Dart

- Zod 4의 `z.toJSONSchema()`는 Draft 2020-12(기본), draft-07, draft-04, openapi-3.0을 출력한다. `transform`이나 `bigint`처럼 JSON Schema로 표현할 수 없는 타입을 만나면 기본적으로 예외를 던진다. 반대 방향의 `z.fromJSONSchema()`는 실험 기능이다 [34].
- `z.discriminatedUnion`과 `z.xor`는 `oneOf`로, 일반 `z.union`은 `anyOf`로 바뀐다 [35]. 예시 계약을 변환하면 변형이 이름 없이 인라인된 `oneOf`와 `const` 판별자가 나왔다(실행 확인).
- 이 JSON Schema를 quicktype으로 Dart 코드로 만들면 1절과 똑같이 평탄화된 `Membership` 한 클래스가 나왔다. TS 쪽은 Zod 스키마가 곧 검증기라서 `safeParse`가 잘못된 `tier` 값과 빠진 `expiresAt`을 경로와 함께 보고했다(실행 확인).
- `z.object`는 모르는 키를 기본적으로 제거한다. `z.strictObject`는 거부하고 `z.looseObject`는 그대로 통과시킨다 [36].
- 같은 계열의 TypeBox 1.x는 스키마 자체가 JSON Schema 객체라서 변환 단계가 없고, Draft 3부터 2020-12까지 다루는 JIT 검증기를 포함한다 [37]. Dart 쪽 사정은 Zod 경로와 같다.

### 5. AsyncAPI

- 최신 명세는 3.1.0(2026-01-31)이고, 이 버전에서 ROS 2 바인딩이 추가됐다 [38]. operation은 `action: send|receive`로 방향을 나타내고, `reply` 객체로 request/reply 패턴의 응답 Message를 기술한다. Schema Object는 JSON Schema Draft 07의 상위 집합이며 `discriminator`를 지원한다 [39]. 따라서 Bridge의 Message, Event, Call(reply가 있는 operation)을 한 문서에 담을 수 있다. `info.version`은 명세 버전과 구분되는 API 버전 필드다 [39].
- 코드 생성기 Modelina의 안정판 5.10.1(2025-10-19)은 AsyncAPI 입력을 2.0.0부터 3.0.0까지만 받는다. 3.1.0은 `next` 브랜치(6.0.0-next.18, 2026-09-01)에서만 받는다 [40][41]. 공식 문서에 따르면 `discriminator`를 상속 구조로 만들지 않고 스키마를 병합한다 [42].
- JSON Schema 입력은 `$schema`가 Draft 04·06·07일 때만 받고, Draft 2020-12를 선언한 스키마는 거부한다 [65]. 2020-12로 쓴 예시 스키마도 실제로 거부됐다(실행 확인). Zod [34]와 TypeSpec(실행 확인)의 기본 출력이 2020-12이므로, 이 경로를 쓰려면 draft-07로 내보내야 한다.
- Dart 생성 결과에서 유니언은 `Object`가 되고, 모든 속성은 `Type? name;` 형태가 된다 [43][44]. 예시 계약을 Draft 07로 바꿔 넣으니 `membership`은 `Object?`, 필수인 `changedAt`도 `DateTime?`이었다. 문자열 enum은 `enum AnonymSchema4 { "basic", "premium" }`으로 나왔는데, 이는 `dart analyze`에서 문법 오류였다(실행 확인). JSON 직렬화는 json_serializable 애너테이션을 붙이는 `DART_JSON_PRESET`으로만 가능하다 [45]. Modelina CLI의 Dart 생성기에는 옵션이 하나도 없다 [46].
- TS 생성 결과에서 유니언은 TS 유니언 타입이 된다 [47]. 예시 계약에서도 리터럴 판별자를 가진 interface 세 개의 유니언이 나왔다. 하지만 `status`가 Modelina의 JavaScript 예약어 목록에 들어 있어 속성 이름이 `reservedStatus`로 바뀌었고 [66], 그래서 interface 출력은 JSON 키와 맞지 않았다(실행 확인). 문서에 나온 TS 기능은 marshal/unmarshal, JSON Binpack, 예제 데이터 등이고, 런타임 검증 프리셋은 없다 [48].

### 6. 생성 없이 양쪽 손작성 + 공유 JSON 픽스처

- Dart 3의 `sealed` 클래스는 하위 타입이 같은 라이브러리 안에만 있을 수 있어서, 컴파일러가 모든 하위 타입을 알고 `switch`가 빠짐없는지 알려 준다 [49].
- freezed 4.0.3(2026-10-17)은 `@Freezed(unionKey: 'type')`과 `@FreezedUnionValue`로 판별자 기반 `fromJson`을 만든다 [50]. 모르는 변형이 오면 `CheckedFromJsonException`을 던지고, `fallbackUnion`을 지정하면 대체 생성자로 받는다 [51]. 4.0.0(2026-08-22)은 Dart 3.13 문법 변화 때문에 breaking 릴리스였다 [52].
- json_serializable의 관련 옵션은 다음과 같다. `checked`는 역직렬화 중 예외를 `CheckedFromJsonException`으로 감싸고, `disallowUnrecognizedKeys`는 켜면 모르는 키에 예외를 던진다(기본은 무시) [53]. `JsonKey(required: true)`는 키가 있는지만 검사하고 `null` 값은 허용한다 [54]. 6.12.0(2026-01-29)부터는 `createJsonSchema: true`로 Dart 클래스에서 JSON Schema를 만들 수 있다 [55][56]. 다만 유니언을 다루는 옵션은 없다 [53].
- dart_mappable 4.10.0도 `discriminatorKey`/`discriminatorValue`로 다형성을 지원한다 [57].
- freezed와 json_serializable은 build_runner로 코드를 생성한다 [50][56]. Dart 팀은 2025-01-29 매크로 작업을 중단했고, 데이터 처리는 build_runner 개선, augmentations, 별도의 언어 기능으로 풀겠다고 밝혔다 [58].
- 픽스처 공유: `flutter test`는 기기가 아니라 개발 머신에서 화면 없이(headless) 실행된다 [59]. 그래서 저장소의 JSON 픽스처를 Host 테스트와 Web 테스트가 함께 읽을 수 있다.

### 7. 범위 밖으로 확인한 도구

- Pigeon 29.0.10은 Kotlin/Java, Swift/Objective-C, C++, GObject 코드만 생성한다. JS/TS 출력이 없으므로 WebView Bridge에는 맞지 않는다 [60].
- JSON Type Definition(RFC 8927)의 코드 생성기 jtd-codegen은 마지막 릴리스가 2021-04(v0.4.1)이고 Dart를 지원하지 않는다 [61].

### 8. pnpm + Flutter 모노레포 통합

- 현재 저장소에는 `web/`(pnpm, `pnpm-workspace.yaml`에 빌드 의존성 설정만 있음)과 `app/`(Flutter)이 나란히 있다. pnpm은 루트의 `pnpm-workspace.yaml`로 여러 패키지를 묶는다 [62]. Dart pub workspace(Dart 3.6 이상)는 루트 pubspec의 `workspace:` 목록과 멤버의 `resolution: workspace`로 `pubspec.lock` 하나를 공유한다 [63]. 따라서 생성된 Dart 코드를 별도 패키지로 두고 Host가 workspace 멤버로 가져오는 구성이 가능하다.
- 생성 도구 실행 환경: quicktype, TypeSpec(`tsp`), Zod 변환 스크립트, Modelina·AsyncAPI CLI, `@bufbuild/buf`, `@bufbuild/protoc-gen-es`는 모두 npm 패키지라 pnpm 스크립트로 돌릴 수 있다. 예외는 protoc-gen-dart로, 전역 활성화하거나 [27] BSR 원격 플러그인을 써야 한다 [28][33].
- Dart 쪽에 build_runner가 필요한지도 후보마다 다르다. quicktype 기본 출력은 필요 없다(실행 확인). protobuf.dart 생성물은 `protobuf` 런타임 패키지에만 의존한다 [27]. Modelina의 JSON 프리셋, freezed, json_serializable은 build_runner가 필요하다 [45][50][56].

### 9. 받는 쪽 기본 동작 (버전 관리·하위 호환)

| 도구 | 모르는 필드 | 모르는 판별자 값 / 변형 |
|---|---|---|
| Zod `z.object` / `z.strictObject` | 제거 / 거부 [36] (제거는 실행 확인) | `discriminatedUnion`이 `invalid_union`으로 실패(실행 확인) |
| quicktype TS `Convert` | `additionalProperties: false`면 거부(생성 코드) | 판별자가 평탄화된 enum 검사에 걸려 거부(생성 코드) |
| quicktype Dart `fromJson` | 읽지 않고 무시(실행 확인) | 판별자는 `TypeError`, 선택 enum은 `null`(실행 확인) |
| protobuf-es `fromJson` | 거부, `ignoreUnknownFields`로 완화 [23] | 모르는 enum 이름 거부 [23] |
| protobuf.dart `mergeFromProto3Json` | `FormatException`, 옵션으로 완화 [25] | `FormatException`, `permissiveEnums`는 대소문자·하이픈·밑줄 차이만 완화 [25] |
| json_serializable | 무시, `disallowUnrecognizedKeys`면 예외 [53] | (유니언 없음) |
| freezed 유니언 | `fromJson`을 json_serializable이 만들므로 그 설정을 따름 [50] | `CheckedFromJsonException`, `fallbackUnion`으로 대체 [51] |

### 10. 비교 요약

| 후보 | 생성 품질: 판별 유니언 (TS / Dart) | 널 안전성 | 런타임 검증 (TS / Dart) | 버전·하위 호환 | 모노레포 통합 | 유지보수 (2026-10) |
|---|---|---|---|---|---|---|
| JSON Schema + quicktype | 평탄화 / 평탄화 | Dart는 null-safe지만 변형 필드가 모두 nullable | 생성된 `Convert`나 Zod, 또는 Ajv / 캐스트 수준, `json_schema`로 보강 | 자동 검사 도구는 확인하지 못함 | Node CLI 하나, Dart 런타임 의존 없음 | 26.0.0(2026-07), 활발 |
| TypeSpec | `@discriminator` 모델만 JSON Schema에 반영 / Dart 이미터 없음 | 경유하는 생성기에 따름 | 경유하는 생성기에 따름 | `@versioning`(preview), JSON Schema 이미터와는 연결 안 됨 | Node(`tsp`) + 2단 생성 | 1.17.0, 월간 릴리스, 일부 preview |
| Protobuf | `{case, value}` / `whichX()` enum | Dart는 `null` 대신 기본값과 `hasX()` | `fromJson`, protovalidate-es / `mergeFromProto3Json`, 제약 검증 없음 | 필드 번호, `reserved`, `buf breaking` WIRE_JSON | npm(buf, protoc-gen-es), Dart 플러그인은 전역 설치나 BSR | es 2.16.0(2026-09), dart 6.1.0(2026-09, 커밋 간격 김) |
| Zod → JSON Schema → Dart | 판별 유니언 / 평탄화 | TS 좋음, Dart는 quicktype과 같음 | Zod / 캐스트 수준 | 자동 검사 도구는 확인하지 못함 | Node 스크립트 + quicktype | zod 4.6.7(2026-10) |
| AsyncAPI + Modelina | TS 유니언(속성 이름이 바뀔 수 있음) / `Object`, enum 문법 오류 | Dart 필드가 필수까지 모두 nullable | 생성 안 함 / 생성 안 함 | `info.version`(문서용) | Node CLI, Dart JSON에는 build_runner 필요 | 명세 3.1.0, Modelina 안정판 2025-10 |
| 손작성 + 픽스처 | Zod / sealed class·freezed | 직접 설계 | Zod / freezed·json_serializable 옵션 | 이전 버전 픽스처로 회귀 테스트 | 생성기 없음, Dart는 build_runner | zod·freezed·json_serializable 모두 2026 릴리스 |

## Reference App에 주는 시사점

「Bridge 계약 단일 원천 결정」([#40](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/40))이 견줘 볼 선택지와 각각의 트레이드오프를 정리한다. 하나를 고르지는 않는다.

- **A. JSON Schema를 원천으로**(직접 작성하거나 TypeSpec·Zod에서 내보냄). TS는 Zod나 Ajv로 검증하고, Dart는 quicktype으로 생성하거나 손으로 쓴다.
  - 장점: 특정 언어에 묶이지 않는다. 지금의 JSON Message 모양을 유지할 수 있고, 같은 스키마로 픽스처도 검증할 수 있다.
  - 비용: Dart로 생성하면 판별 유니언이 사라진다. 호환성을 자동으로 검사하는 도구가 확인되지 않았다.
- **B. TypeSpec을 원천으로**, JSON Schema(안정판)나 Protobuf(preview)를 거친다.
  - 장점: Call의 이름·매개변수·결과·에러와 버전까지 한 파일에 읽기 좋게 적을 수 있다.
  - 비용: 거쳐 가는 형식의 한계를 그대로 물려받는다. 게다가 `@discriminated`와 versioning이 JSON Schema 출력에 반영되지 않고 Dart 이미터도 없다.
- **C. Protobuf를 원천으로, Bridge에는 ProtoJSON**.
  - 장점: 양쪽 모두 공식 수준의 생성기가 있다. 계약 버전 절차를 `buf breaking`으로 자동 검사할 수 있다.
  - 비용: Message의 JSON 모양을 ProtoJSON이 정하므로 「Bridge 계약 형태 결정」([#39](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/39))과 부딪칠 수 있다. Dart의 oneof·기본값 모델은 Dart 관용 코드와 다르고, Dart용 제약 검증이 없으며, Dart 플러그인을 따로 설치해야 한다.
- **D. TS(Zod)를 원천으로** JSON Schema를 내보낸다. Dart는 생성하거나 손으로 쓰고 픽스처로 맞춘다.
  - 장점: Web 쪽 개발 경험과 검증이 가장 좋다.
  - 비용: JSON Schema로 옮길 수 없는 Zod 기능(`transform` 등)을 계약에서 금지해야 한다. Dart 쪽은 A와 같은 한계를 지거나 손작성이 된다.
- **E. 양쪽 손작성 + 공유 JSON 픽스처**. 필요하면 JSON Schema를 픽스처 검증에만 쓴다.
  - 장점: 양쪽 모두 관용적인 코드를 쓸 수 있고, 받는 쪽 정책을 세밀하게 정할 수 있으며, 생성기에 의존하지 않는다.
  - 비용: 엄밀한 단일 원천이 아니다. 두 정의의 일치는 픽스처 범위만큼만 보장되고, 바꿀 때마다 두 곳을 고쳐야 한다.
- **F. AsyncAPI를 계약 목록 문서의 원천으로** 두고, 코드는 A–E 중 하나로 만든다.
  - 장점: Event, Call, reply 구조를 표준 형식으로 남길 수 있다.
  - 비용: 코드 생성 품질이 낮아서 문서와 코드가 어긋나지 않는지 따로 확인해야 한다.

어느 선택지든 결정하면서 함께 정해야 할 것이 있다.

1. Dart에서 판별 유니언을 sealed class로 받아야 하는가. 그래야 한다면 이번에 확인한 생성기 경로(A·D의 quicktype, C의 protobuf.dart, F의 Modelina)로는 얻을 수 없고, freezed나 손작성이 필요하다.
2. Message의 JSON 모양을 직접 정할 것인가([#39](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/39)). 직접 정한다면 C와는 긴장 관계다.
3. 받는 쪽의 관용성 정책. 9절 표처럼 도구 기본값이 서로 다르므로 [#35](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/35)와 함께 정해야 한다.
4. 계약 버전을 올리는 절차. 이번 조사에서 자동 호환성 검사를 제공하는 1차 도구는 `buf breaking`뿐이었다. 그 밖의 선택지에서는 이전 버전 픽스처를 남겨 두고 돌리는 회귀 테스트 같은 장치를 따로 마련해야 한다.
5. Demo 스펙(`docs/spec.md` 1.2절)은 Message 규약 코드 생성기와 공유 npm/pub 패키지를 범위 밖으로 뒀다. Reference App에서 이 제외를 유지할지 다시 여는 것도 [#40](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/40)이 정할 일이다.

## 확인하지 못한 것과 새로 생긴 질문

**확인하지 못한 것**

- JSON Schema 계열에서 `buf breaking`처럼 계약의 하위 호환을 자동으로 검사하는 1차 도구.
- `json_schema_to_freezed`(1.0.1, 2025-05, 게시자 미인증)가 `oneOf`를 freezed 유니언으로 바꾸는지. 직접 실행하지 않았다.
- protoc_plugin이 `grpc` 옵션 없이 서비스 정의에서 무엇을 생성하는지. 문서에 나와 있지 않았다.
- TypeSpec의 `seal-object-schemas`가 만드는 `unevaluatedProperties`를 quicktype이 해석하는지.
- Modelina 6.0 정식판의 출시 시점. 6.0.0-next.18에서도 Dart 유니언은 여전히 `Object`였다.
- 이 조사는 Bridge가 문자열을 주고받는다는 현재 Demo 구현(`webview_flutter` JavaScript 채널)을 전제로 했다. WebView 패키지 결정([#38](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/38))에 따라 전송 형식이 바뀌면 ProtoJSON과 바이너리 중 무엇을 쓸지가 달라질 수 있다.

**새로 생긴 질문**

- 계약 원천 파일과 생성물을 어디에 둘 것인가. 루트의 계약 패키지를 pnpm workspace와 pub workspace 양쪽에 걸칠지는 지도의 "코드 구조"와 연결된다.
- 생성물을 커밋할 것인가, 빌드할 때 만들 것인가. 커밋한다면 CI에서 다시 생성해 diff를 검사할 것인가.
- 공유 픽스처를 개발용 가짜 Host(⑦)와 Host–Web 통합 테스트(⑧, [#37](https://github.com/ilkyeong-gn/flutter-nextjs-bridge-demo/issues/37))에서 재사용할 것인가.
- Call의 에러를 계약에서 어떻게 표현할 것인가. 판별 유니언으로 할지 공통 에러 객체로 할지에 따라 1·3·4·5절의 유니언 한계가 영향을 미친다.

## 출처

1. quicktype 26.0.0 릴리스 노트 — https://github.com/glideapps/quicktype/releases/tag/v26.0.0
2. quicktype Dart 옵션 (`language.ts`, v26.0.0) — https://github.com/glideapps/quicktype/blob/v26.0.0/packages/quicktype-core/src/language/Dart/language.ts
3. quicktype Dart 렌더러 (`DartRenderer.ts`, v26.0.0) — https://github.com/glideapps/quicktype/blob/v26.0.0/packages/quicktype-core/src/language/Dart/DartRenderer.ts
4. quicktype JavaScript 옵션 (`runtime-typecheck`, v26.0.0) — https://github.com/glideapps/quicktype/blob/v26.0.0/packages/quicktype-core/src/language/JavaScript/language.ts
5. quicktype TypeScript 옵션 (JavaScript 옵션 상속, v26.0.0) — https://github.com/glideapps/quicktype/blob/v26.0.0/packages/quicktype-core/src/language/TypeScriptFlow/language.ts
6. quicktype TypeScript Zod 렌더러 (v26.0.0) — https://github.com/glideapps/quicktype/blob/v26.0.0/packages/quicktype-core/src/language/TypeScriptZod/TypeScriptZodRenderer.ts
7. json-schema-to-typescript README — https://github.com/bcherny/json-schema-to-typescript
8. Ajv, JSON Schema keywords (`discriminator`) — https://ajv.js.org/json-schema.html
9. Ajv, Standalone validation code — https://ajv.js.org/standalone.html
10. Workiva json_schema CHANGELOG — https://github.com/workiva/json_schema/blob/master/CHANGELOG.md
11. json_schema_builder (pub.dev) — https://pub.dev/packages/json_schema_builder
12. TypeSpec 1.0 GA 발표 — https://typespec.io/blog/typespec-1-0-GA-release/
13. TypeSpec, Discriminated Types — https://typespec.io/docs/standard-library/discriminated-types/
14. @typespec/json-schema README (1.17.0) — https://github.com/microsoft/typespec/blob/typespec-stable@1.17.0/packages/json-schema/README.md
15. @typespec/json-schema 이미터 소스 (1.17.0) — https://github.com/microsoft/typespec/blob/typespec-stable@1.17.0/packages/json-schema/src/json-schema-emitter.ts
16. TypeSpec, Versioning 가이드 — https://typespec.io/docs/libraries/versioning/guide/
17. @typespec/json-schema package.json (1.17.0) — https://github.com/microsoft/typespec/blob/typespec-stable@1.17.0/packages/json-schema/package.json
18. @typespec/openapi3 package.json (1.17.0) — https://github.com/microsoft/typespec/blob/typespec-stable@1.17.0/packages/openapi3/package.json
19. TypeSpec 1.17.0 릴리스 노트 — https://typespec.io/release-notes/typespec-1-17-0/
20. TypeSpec 저장소 packages 목록 (1.17.0) — https://github.com/microsoft/typespec/tree/typespec-stable@1.17.0/packages
21. Protobuf-ES, Generated code: Features (oneof, services) — https://protobufes.com/reference/generated-code/features/
22. Protobuf-ES, Generated code: Field types — https://protobufes.com/reference/generated-code/field-types/
23. Protobuf-ES, Serialization — https://protobufes.com/guides/serialization/
24. Protocol Buffers, Dart Generated Code — https://protobuf.dev/reference/dart/dart-generated/
25. protobuf (Dart) API, `GeneratedMessage.mergeFromProto3Json` — https://pub.dev/documentation/protobuf/latest/protobuf/GeneratedMessage/mergeFromProto3Json.html
26. protoc_plugin CHANGELOG — https://github.com/google/protobuf.dart/blob/master/protoc_plugin/CHANGELOG.md
27. protoc_plugin README — https://github.com/google/protobuf.dart/blob/master/protoc_plugin/README.md
28. Buf 원격 플러그인 정의 `protocolbuffers/dart` — https://github.com/bufbuild/plugins/tree/main/plugins/protocolbuffers/dart
29. Protocol Buffers, ProtoJSON Format — https://protobuf.dev/programming-guides/json/
30. Protocol Buffers, Language Guide (proto 3) — https://protobuf.dev/programming-guides/proto3/
31. Buf, Breaking change rules and categories — https://buf.build/docs/breaking/rules/
32. protovalidate README — https://github.com/bufbuild/protovalidate
33. Buf, `buf.gen.yaml` v2 — https://buf.build/docs/configuration/v2/buf-gen-yaml/
34. Zod, JSON Schema — https://zod.dev/json-schema
35. Zod 소스 `json-schema-processors.ts` (v4.6.7) — https://github.com/colinhacks/zod/blob/v4.6.7/packages/zod/src/v4/core/json-schema-processors.ts
36. Zod, Defining schemas (객체의 strip/strict/loose) — https://zod.dev/api
37. TypeBox README — https://github.com/sinclairzx81/typebox
38. AsyncAPI 명세 v3.1.0 릴리스 — https://github.com/asyncapi/spec/releases/tag/v3.1.0
39. AsyncAPI Specification 3.1.0 — https://www.asyncapi.com/docs/reference/specification/v3.1.0
40. Modelina `AsyncAPIInputProcessor.ts` (v5.10.1) — https://github.com/asyncapi/modelina/blob/v5.10.1/src/processors/AsyncAPIInputProcessor.ts
41. Modelina `AsyncAPIInputProcessor.ts` (`next` 브랜치) — https://github.com/asyncapi/modelina/blob/next/src/processors/AsyncAPIInputProcessor.ts
42. Modelina 사용 문서 (v5.10.1) — https://github.com/asyncapi/modelina/blob/v5.10.1/docs/usage.md
43. Modelina Dart 타입 매핑 `DartConstrainer.ts` (v5.10.1) — https://github.com/asyncapi/modelina/blob/v5.10.1/src/generators/dart/DartConstrainer.ts
44. Modelina Dart `ClassRenderer.ts` (v5.10.1) — https://github.com/asyncapi/modelina/blob/v5.10.1/src/generators/dart/renderers/ClassRenderer.ts
45. Modelina Dart `JsonSerializablePreset.ts` (v5.10.1) — https://github.com/asyncapi/modelina/blob/v5.10.1/src/generators/dart/presets/JsonSerializablePreset.ts
46. Modelina CLI Dart 생성기 (v5.10.1) — https://github.com/asyncapi/modelina/blob/v5.10.1/modelina-cli/src/helpers/dart.ts
47. Modelina TypeScript 타입 매핑 `TypeScriptConstrainer.ts` (v5.10.1) — https://github.com/asyncapi/modelina/blob/v5.10.1/src/generators/typescript/TypeScriptConstrainer.ts
48. Modelina TypeScript 문서 (v5.10.1) — https://github.com/asyncapi/modelina/blob/v5.10.1/docs/languages/TypeScript.md
49. Dart, Class modifiers (`sealed`) — https://dart.dev/language/class-modifiers
50. freezed README — https://github.com/rrousselGit/freezed/blob/master/packages/freezed/README.md
51. freezed `from_json_template.dart` — https://github.com/rrousselGit/freezed/blob/master/packages/freezed/lib/src/templates/from_json_template.dart
52. freezed CHANGELOG — https://github.com/rrousselGit/freezed/blob/master/packages/freezed/CHANGELOG.md
53. json_annotation `JsonSerializable` 소스 — https://github.com/google/json_serializable.dart/blob/master/json_annotation/lib/src/json_serializable.dart
54. json_annotation `JsonKey` 소스 — https://github.com/google/json_serializable.dart/blob/master/json_annotation/lib/src/json_key.dart
55. json_serializable CHANGELOG — https://github.com/google/json_serializable.dart/blob/master/json_serializable/CHANGELOG.md
56. json_serializable README — https://github.com/google/json_serializable.dart/blob/master/json_serializable/README.md
57. dart_mappable, Polymorphism — https://pub.dev/documentation/dart_mappable/latest/topics/Polymorphism-topic.html
58. Dart 블로그, An update on Dart macros & data serialization (2025-01-29) — https://dart.dev/blog/an-update-on-dart-macros-data-serialization
59. Flutter, Running and writing tests — https://github.com/flutter/flutter/blob/master/docs/contributing/testing/Running-and-writing-tests.md
60. Pigeon README — https://github.com/flutter/packages/blob/main/packages/pigeon/README.md
61. jtd-codegen 저장소 — https://github.com/jsontypedef/json-typedef-codegen
62. pnpm, Workspace — https://pnpm.io/workspaces
63. Dart, Pub workspaces — https://dart.dev/tools/pub/workspaces
64. 버전 확인: npm 레지스트리(https://registry.npmjs.org/), pub.dev API(https://pub.dev/api/packages/)
65. Modelina `JsonSchemaInputProcessor.ts` (v5.10.1) — https://github.com/asyncapi/modelina/blob/v5.10.1/src/processors/JsonSchemaInputProcessor.ts
66. Modelina JavaScript 예약어 목록 `Constants.ts` (v5.10.1) — https://github.com/asyncapi/modelina/blob/v5.10.1/src/generators/javascript/Constants.ts
