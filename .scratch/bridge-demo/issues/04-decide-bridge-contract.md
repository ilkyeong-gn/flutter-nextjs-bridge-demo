# Bridge 규약 확정

Type: grilling
Status: open
Blocked by: 02
Map: [Flutter + Next.js 브릿지 데모](../map.md)

## Question

[webview_flutter와 Next.js로 Stage A/B/C를 구현하는 메커니즘 조사](02-research-bridge-mechanism.md) 결과를 바탕으로 Bridge 규약을 정확히 정한다.

- JavaScript 채널 이름, Web에 노출할 전역 API 형태
- Host → Web Event 전달 방식 (전역 함수 호출 vs `CustomEvent`)
- Message / Event / Call의 정확한 JSON 형태와 필드 이름
- Call 응답 경로, id 생성 방식, 알 수 없는 메서드일 때 reject 형태
- Web의 Host 존재 감지 방식
- 단계마다 규약의 어느 부분이 추가되는지
