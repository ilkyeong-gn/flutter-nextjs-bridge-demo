import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/bridge/stage_a_bridge.dart';
import 'package:app/bridge/stage_b_bridge.dart';

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

    // Initial stage is Stage A: counter button is not in AppBar
    expect(find.byKey(const Key('counter_increment_button')), findsNothing);

    // Switch to Stage B
    await tester.tap(find.text('Stage B'));
    await tester.pump();

    final segmentedButton = tester.widget<SegmentedButton<Stage>>(find.byType(SegmentedButton<Stage>));
    expect(segmentedButton.selected, {Stage.stageB});

    // In Stage B: counter button appears in AppBar
    expect(find.byKey(const Key('counter_increment_button')), findsOneWidget);
  });

  testWidgets('HostApp increments counter and calls onCounterIncremented when [+] button tapped', (WidgetTester tester) async {
    int? latestCounter;

    await tester.pumpWidget(
      HostApp(
        initialStage: Stage.stageB,
        webViewWidget: const SizedBox(key: Key('placeholder_webview')),
        onCounterIncremented: (counter) {
          latestCounter = counter;
        },
      ),
    );

    expect(find.byKey(const Key('counter_increment_button')), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);

    // Tap counter increment button
    await tester.tap(find.byKey(const Key('counter_increment_button')));
    await tester.pump();

    expect(latestCounter, 1);

    // Tap again
    await tester.tap(find.byKey(const Key('counter_increment_button')));
    await tester.pump();

    expect(latestCounter, 2);
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

  testWidgets('HostApp in Stage B displays SnackBar when StageBBridge handles showSnackBar message', (WidgetTester tester) async {
    await tester.pumpWidget(
      HostApp(
        initialStage: Stage.stageB,
        webViewWidget: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                StageBBridge.handleMessage(
                  '{"type":"showSnackBar","text":"Stage B 스낵바 메시지"}',
                  context,
                );
              },
              child: const Text('Trigger Stage B Message'),
            );
          },
        ),
      ),
    );

    expect(find.text('Stage B 스낵바 메시지'), findsNothing);

    await tester.tap(find.text('Trigger Stage B Message'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Stage B 스낵바 메시지'), findsOneWidget);
  });
}
