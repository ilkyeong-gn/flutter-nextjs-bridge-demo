import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/bridge/stage_a_bridge.dart';

void main() {
  group('StageAMessage parsing', () {
    test('올바른 showSnackBar 규격의 JSON 문자열을 성공적으로 파싱한다', () {
      const raw = '{"type":"showSnackBar","text":"안녕하세요 Flutter"}';
      final message = StageAMessage.fromJsonString(raw);

      expect(message, isNotNull);
      expect(message!.text, '안녕하세요 Flutter');
    });

    test('type이 일치하지 않는 메시지는 null을 반환한다', () {
      const raw = '{"type":"otherType","text":"무시되어야 함"}';
      final message = StageAMessage.fromJsonString(raw);

      expect(message, isNull);
    });

    test('text 필드가 누락되었거나 문자열이 아닌 경우 null을 반환한다', () {
      const rawNoText = '{"type":"showSnackBar"}';
      const rawNumberText = '{"type":"showSnackBar","text":123}';

      expect(StageAMessage.fromJsonString(rawNoText), isNull);
      expect(StageAMessage.fromJsonString(rawNumberText), isNull);
    });

    test('잘못된 형식의 JSON 문자열은 null을 반환하고 예외를 던지지 않는다', () {
      const malformed = '{invalid-json}';
      final message = StageAMessage.fromJsonString(malformed);

      expect(message, isNull);
    });
  });

  group('StageABridge message handling', () {
    testWidgets('handleMessage 호출 시 콜백이 제공되면 콜백에 텍스트가 전달된다', (WidgetTester tester) async {
      String? receivedText;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    StageABridge.handleMessage(
                      '{"type":"showSnackBar","text":"콜백 테스트"}',
                      context,
                      onShowSnackBar: (text) {
                        receivedText = text;
                      },
                    );
                  },
                  child: const Text('Send'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Send'));
      await tester.pump();

      expect(receivedText, '콜백 테스트');
    });

    testWidgets('handleMessage 호출 시 콜백이 없으면 ScaffoldMessenger에 SnackBar를 띄운다', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    StageABridge.handleMessage(
                      '{"type":"showSnackBar","text":"스낵바 표시 확인"}',
                      context,
                    );
                  },
                  child: const Text('Show SnackBar'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('스낵바 표시 확인'), findsNothing);

      await tester.tap(find.text('Show SnackBar'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('스낵바 표시 확인'), findsOneWidget);
    });
  });
}
