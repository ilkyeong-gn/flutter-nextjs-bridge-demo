import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:app/bridge/stage_a_bridge.dart';

/// Stage B: Host -> Web 양방향 이벤트 및 Stage A 메시지 Bridge
class StageBBridge {
  static const String channelName = StageABridge.channelName;
  static const String eventName = 'flutter:event';

  /// CustomEvent를 발송하기 위한 JavaScript 코드를 생성합니다.
  static String createIncrementCounterJs(int counter) {
    final payload = jsonEncode({
      'type': 'incrementCounter',
      'count': counter,
    });
    return 'window.dispatchEvent(new CustomEvent("$eventName", { detail: $payload }));';
  }

  /// WebViewController를 통해 Web으로 카운터 증가 이벤트를 발송합니다.
  static Future<void> sendIncrementCounter(
    WebViewController controller,
    int counter,
  ) {
    final script = createIncrementCounterJs(counter);
    return controller.runJavaScript(script);
  }

  /// Web -> Host 메시지를 처리합니다 (Stage A 호환).
  static void handleMessage(
    String rawMessage,
    BuildContext context, {
    void Function(String text)? onShowSnackBar,
  }) {
    StageABridge.handleMessage(
      rawMessage,
      context,
      onShowSnackBar: onShowSnackBar,
    );
  }

  /// WebViewController에 브릿지 채널을 등록합니다. (Stage A 기능 포함)
  static void register(
    WebViewController controller,
    BuildContext context, {
    void Function(String text)? onShowSnackBar,
  }) {
    StageABridge.register(
      controller,
      context,
      onShowSnackBar: onShowSnackBar,
    );
  }
}
