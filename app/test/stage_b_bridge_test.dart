import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/bridge/stage_b_bridge.dart';

void main() {
  group('StageBBridge JavaScript generation', () {
    test('createIncrementCounterJs generates valid JavaScript for CustomEvent dispatch', () {
      final js = StageBBridge.createIncrementCounterJs(1);
      expect(
        js,
        'window.dispatchEvent(new CustomEvent("flutter:event", { detail: {"type":"incrementCounter","count":1} }));',
      );
    });

    test('createIncrementCounterJs handles counter value 0 and large values', () {
      expect(
        StageBBridge.createIncrementCounterJs(0),
        'window.dispatchEvent(new CustomEvent("flutter:event", { detail: {"type":"incrementCounter","count":0} }));',
      );
      expect(
        StageBBridge.createIncrementCounterJs(100),
        'window.dispatchEvent(new CustomEvent("flutter:event", { detail: {"type":"incrementCounter","count":100} }));',
      );
    });
  });

  group('StageBBridge Stage A compatibility', () {
    testWidgets('handleMessage calls onShowSnackBar callback when provided', (WidgetTester tester) async {
      String? receivedText;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    StageBBridge.handleMessage(
                      '{"type":"showSnackBar","text":"Stage B 스낵바 콜백"}',
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

      expect(receivedText, 'Stage B 스낵바 콜백');
    });

    testWidgets('handleMessage displays SnackBar when callback is not provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    StageBBridge.handleMessage(
                      '{"type":"showSnackBar","text":"Stage B 스낵바 표시"}',
                      context,
                    );
                  },
                  child: const Text('Show'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Stage B 스낵바 표시'), findsNothing);

      await tester.tap(find.text('Show'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Stage B 스낵바 표시'), findsOneWidget);
    });
  });
}
