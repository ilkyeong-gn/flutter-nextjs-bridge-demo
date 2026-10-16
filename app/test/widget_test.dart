import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/bridge/stage_a_bridge.dart';
import 'package:app/bridge/stage_b_bridge.dart';
import 'package:app/bridge/stage_c_bridge.dart';

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

    final segmentedButtonB = tester.widget<SegmentedButton<Stage>>(find.byType(SegmentedButton<Stage>));
    expect(segmentedButtonB.selected, {Stage.stageB});

    // In Stage B: counter button appears in AppBar
    expect(find.byKey(const Key('counter_increment_button')), findsOneWidget);

    // Switch to Stage C
    await tester.tap(find.text('Stage C'));
    await tester.pump();

    final segmentedButtonC = tester.widget<SegmentedButton<Stage>>(find.byType(SegmentedButton<Stage>));
    expect(segmentedButtonC.selected, {Stage.stageC});

    // In Stage C: counter button also appears in AppBar
    expect(find.byKey(const Key('counter_increment_button')), findsOneWidget);
  });

  testWidgets('HostApp increments counter and calls onCounterIncremented when [+] button tapped in Stage C', (WidgetTester tester) async {
    int? latestCounter;

    await tester.pumpWidget(
      HostApp(
        initialStage: Stage.stageC,
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

  testWidgets('HostApp in Stage C handles Stage A SnackBar and Stage C Call messages', (WidgetTester tester) async {
    StageCResponse? lastResponse;

    await tester.pumpWidget(
      HostApp(
        initialStage: Stage.stageC,
        webViewWidget: Builder(
          builder: (context) {
            return Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    StageCBridge.handleRawMessage(
                      '{"type":"showSnackBar","text":"Stage C 스낵바 메시지"}',
                      context,
                    );
                  },
                  child: const Text('Trigger Stage C SnackBar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    StageCBridge.handleRawMessage(
                      '{"id":"call-widget-1","method":"getDeviceInfo"}',
                      context,
                      onResponseSent: (res) {
                        lastResponse = res;
                      },
                      platform: 'ios',
                      version: '18.0',
                    );
                  },
                  child: const Text('Trigger Stage C Call'),
                ),
              ],
            );
          },
        ),
      ),
    );

    // SnackBar 테스트
    expect(find.text('Stage C 스낵바 메시지'), findsNothing);
    await tester.tap(find.text('Trigger Stage C SnackBar'));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Stage C 스낵바 메시지'), findsOneWidget);

    // Stage C Call 테스트
    await tester.tap(find.text('Trigger Stage C Call'));
    await tester.pump();
    expect(lastResponse, isNotNull);
    expect(lastResponse!.id, 'call-widget-1');
    expect(lastResponse!.result, {'platform': 'ios', 'version': '18.0'});
  });
}

