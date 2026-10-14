import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Stage A: Web -> Host 단방향 메시지 (showSnackBar) 데이터 모델
class StageAMessage {
  final String text;

  const StageAMessage({required this.text});

  static StageAMessage? fromJsonString(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['type'] == 'showSnackBar' &&
          decoded['text'] is String) {
        return StageAMessage(text: decoded['text'] as String);
      }
    } catch (e) {
      debugPrint('Failed to parse StageAMessage: $e');
    }
    return null;
  }
}

/// Stage A: Web -> Host 단방향 Bridge 핸들러
class StageABridge {
  static const String channelName = 'FlutterBridge';

  /// 수신된 raw 메시지를 파싱하여 SnackBar를 표시하거나 콜백을 호출합니다.
  static void handleMessage(
    String rawMessage,
    BuildContext context, {
    void Function(String text)? onShowSnackBar,
  }) {
    final message = StageAMessage.fromJsonString(rawMessage);
    if (message == null) return;
    if (!context.mounted) return;

    if (onShowSnackBar != null) {
      onShowSnackBar(message.text);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.text)),
      );
    }
  }

  /// WebViewController에 FlutterBridge JavaScript 채널을 등록합니다.
  static void register(
    WebViewController controller,
    BuildContext context, {
    void Function(String text)? onShowSnackBar,
  }) {
    controller.addJavaScriptChannel(
      channelName,
      onMessageReceived: (JavaScriptMessage message) {
        handleMessage(
          message.message,
          context,
          onShowSnackBar: onShowSnackBar,
        );
      },
    );
  }
}
