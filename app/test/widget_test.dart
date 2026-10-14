import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/bridge/stage_a_bridge.dart';

void main() {
  testWidgets('HostApp renders HostHomeScreen with AppBar and SegmentedButton', (WidgetTester tester) async {
    await tester.pumpWidget(
      const HostApp(
        webViewWidget: SizedBox(key: Key('placeholder_webview')),
      ),
    );

    expect(find.text('Host: Flutter WebView Bridge'), findsOneWidget);
    expect(find.byType(SegmentedButton<Stage>), findsOneWidget);
    expect(find.text('Stage A'), findsOneWidget);
    expect(find.text('Stage B'), findsOneWidget);
    expect(find.text('Stage C'), findsOneWidget);

    // Switch to Stage B
    await tester.tap(find.text('Stage B'));
    await tester.pump();

    final segmentedButton = tester.widget<SegmentedButton<Stage>>(find.byType(SegmentedButton<Stage>));
    expect(segmentedButton.selected, {Stage.stageB});
  });

  testWidgets('HostApp displays SnackBar when StageABridge handles showSnackBar message', (WidgetTester tester) async {
    await tester.pumpWidget(
      HostApp(
        webViewWidget: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                StageABridge.handleMessage(
                  '{"type":"showSnackBar","text":"테스트 스낵바 메시지"}',
                  context,
                );
              },
              child: const Text('Trigger Message'),
            );
          },
        ),
      ),
    );

    expect(find.text('테스트 스낵바 메시지'), findsNothing);

    await tester.tap(find.text('Trigger Message'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('테스트 스낵바 메시지'), findsOneWidget);
  });
}
