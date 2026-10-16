import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/bridge/stage_c_bridge.dart';

void main() {
  group('StageCCallRequest parsing', () {
    test('정상적인 JSON 문자열로부터 StageCCallRequest를 파싱한다', () {
      const raw = '{"id":"req-123","method":"getDeviceInfo","params":{"foo":"bar"}}';
      final request = StageCCallRequest.fromJsonString(raw);

      expect(request, isNotNull);
      expect(request!.id, 'req-123');
      expect(request.method, 'getDeviceInfo');
      expect(request.params, {'foo': 'bar'});
    });

    test('params가 생략되었거나 빈 객체인 경우 빈 맵으로 기본 설정된다', () {
      const raw = '{"id":"req-456","method":"getDeviceInfo"}';
      final request = StageCCallRequest.fromJsonString(raw);

      expect(request, isNotNull);
      expect(request!.id, 'req-456');
      expect(request.method, 'getDeviceInfo');
      expect(request.params, isEmpty);
    });

    test('잘못된 JSON 형식 또는 필수 필드 누락 시 null을 반환한다', () {
      expect(StageCCallRequest.fromJsonString('invalid json'), isNull);
      expect(StageCCallRequest.fromJsonString('{"method":"getDeviceInfo"}'), isNull);
      expect(StageCCallRequest.fromJsonString('{"id":"123"}'), isNull);
      expect(StageCCallRequest.fromJsonString('{"id":123,"method":"getDeviceInfo"}'), isNull);
    });
  });

  group('StageCResponse and JavaScript generation', () {
    test('성공 응답에 대해 createResponseJs가 올바른 JavaScript 코드를 생성한다', () {
      const response = StageCResponse.success(
        id: 'c1a2b3',
        result: {'platform': 'ios', 'version': '18.0'},
      );

      final js = StageCBridge.createResponseJs(response);
      expect(
        js,
        'window.__onFlutterResponse({"id":"c1a2b3","result":{"platform":"ios","version":"18.0"}});',
      );
    });

    test('에러 응답에 대해 createResponseJs가 올바른 JavaScript 코드를 생성한다', () {
      const response = StageCResponse.error(
        id: 'c1a2b3',
        error: 'Unknown method: invalidMethod',
      );

      final js = StageCBridge.createResponseJs(response);
      expect(
        js,
        'window.__onFlutterResponse({"id":"c1a2b3","error":"Unknown method: invalidMethod"});',
      );
    });
  });

  group('StageCBridge.handleCallRequest', () {
    test('method가 getDeviceInfo일 때 Platform 정보를 담은 성공 응답을 반환한다', () {
      const request = StageCCallRequest(
        id: 'req-1',
        method: 'getDeviceInfo',
      );

      final response = StageCBridge.handleCallRequest(
        request,
        platform: 'ios',
        version: 'Version 18.0 (Build 22A3354)',
      );

      expect(response.id, 'req-1');
      expect(response.error, isNull);
      expect(response.result, {
        'platform': 'ios',
        'version': 'Version 18.0 (Build 22A3354)',
      });
    });

    test('platform/version 미지정 시 dart:io Platform 기본값을 사용한다', () {
      const request = StageCCallRequest(
        id: 'req-default',
        method: 'getDeviceInfo',
      );

      final response = StageCBridge.handleCallRequest(request);
      expect(response.id, 'req-default');
      expect(response.error, isNull);
      expect(response.result, isNotNull);
      expect(response.result!['platform'], isNotEmpty);
      expect(response.result!['version'], isNotEmpty);
    });

    test('알 수 없는 method 호출 시 Unknown method 에러 응답을 반환한다', () {
      const request = StageCCallRequest(
        id: 'req-err',
        method: 'unknownMethod',
      );

      final response = StageCBridge.handleCallRequest(request);
      expect(response.id, 'req-err');
      expect(response.result, isNull);
      expect(response.error, 'Unknown method: unknownMethod');
    });
  });

  group('StageCBridge.handleRawMessage', () {
    testWidgets('Stage A showSnackBar 메시지 수신 시 SnackBar 표시를 처리한다', (WidgetTester tester) async {
      String? receivedSnackBar;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    StageCBridge.handleRawMessage(
                      '{"type":"showSnackBar","text":"Stage C에서 보낸 스낵바"}',
                      context,
                      onShowSnackBar: (text) {
                        receivedSnackBar = text;
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

      expect(receivedSnackBar, 'Stage C에서 보낸 스낵바');
    });

    testWidgets('Stage C getDeviceInfo 호출 시 runJavaScript로 성공 응답 스크립트를 전달한다', (WidgetTester tester) async {
      String? executedJs;
      StageCResponse? sentResponse;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    StageCBridge.handleRawMessage(
                      '{"id":"call-100","method":"getDeviceInfo"}',
                      context,
                      runJavaScript: (script) async {
                        executedJs = script;
                      },
                      onResponseSent: (response) {
                        sentResponse = response;
                      },
                      platform: 'android',
                      version: 'API 34',
                    );
                  },
                  child: const Text('Call'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Call'));
      await tester.pump();

      expect(executedJs, isNotNull);
      expect(
        executedJs,
        'window.__onFlutterResponse({"id":"call-100","result":{"platform":"android","version":"API 34"}});',
      );
      expect(sentResponse?.id, 'call-100');
      expect(sentResponse?.result, {'platform': 'android', 'version': 'API 34'});
    });

    testWidgets('Stage C 알 수 없는 method 호출 시 runJavaScript로 에러 응답 스크립트를 전달한다', (WidgetTester tester) async {
      String? executedJs;
      StageCResponse? sentResponse;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    StageCBridge.handleRawMessage(
                      '{"id":"call-err","method":"invalidRpc"}',
                      context,
                      runJavaScript: (script) async {
                        executedJs = script;
                      },
                      onResponseSent: (response) {
                        sentResponse = response;
                      },
                    );
                  },
                  child: const Text('Call Error'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Call Error'));
      await tester.pump();

      expect(
        executedJs,
        'window.__onFlutterResponse({"id":"call-err","error":"Unknown method: invalidRpc"});',
      );
      expect(sentResponse?.id, 'call-err');
      expect(sentResponse?.error, 'Unknown method: invalidRpc');
    });
  });
}
