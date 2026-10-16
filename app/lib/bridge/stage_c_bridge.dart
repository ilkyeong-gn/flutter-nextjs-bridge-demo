import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:app/bridge/stage_a_bridge.dart';
import 'package:app/bridge/stage_b_bridge.dart';

/// Stage C: Web -> Host RPC Call 요청 모델
class StageCCallRequest {
  final String id;
  final String method;
  final Map<String, dynamic> params;

  const StageCCallRequest({
    required this.id,
    required this.method,
    this.params = const {},
  });

  static StageCCallRequest? fromJsonString(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['id'] is String &&
          decoded['method'] is String) {
        final params = decoded['params'];
        return StageCCallRequest(
          id: decoded['id'] as String,
          method: decoded['method'] as String,
          params: params is Map<String, dynamic> ? params : const {},
        );
      }
    } catch (e) {
      debugPrint('Failed to parse StageCCallRequest: $e');
    }
    return null;
  }
}

/// Stage C: Host -> Web RPC Call 응답 모델
class StageCResponse {
  final String id;
  final Map<String, dynamic>? result;
  final String? error;

  const StageCResponse.success({
    required this.id,
    required this.result,
  }) : error = null;

  const StageCResponse.error({
    required this.id,
    required this.error,
  }) : result = null;

  Map<String, dynamic> toJson() {
    if (error != null) {
      return {
        'id': id,
        'error': error,
      };
    }
    return {
      'id': id,
      'result': result ?? {},
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

/// Stage C: Web ↔ Host 양방향 RPC 및 이전 Stage (A: SnackBar, B: Counter) 호환 Bridge
class StageCBridge {
  static const String channelName = StageABridge.channelName;
  static const String eventName = StageBBridge.eventName;

  /// CustomEvent를 발송하기 위한 JavaScript 코드를 생성합니다. (Stage B 호환)
  static String createIncrementCounterJs(int counter) {
    return StageBBridge.createIncrementCounterJs(counter);
  }

  /// WebViewController를 통해 Web으로 카운터 증가 이벤트를 발송합니다. (Stage B 호환)
  static Future<void> sendIncrementCounter(
    WebViewController controller,
    int counter,
  ) {
    return StageBBridge.sendIncrementCounter(controller, counter);
  }

  /// Call 응답을 Web의 window.__onFlutterResponse로 전달하는 JavaScript 코드를 생성합니다.
  static String createResponseJs(StageCResponse response) {
    return 'window.__onFlutterResponse(${response.toJsonString()});';
  }

  /// Call 요청을 처리하여 성공 또는 에러 응답 객체를 반환합니다.
  static StageCResponse handleCallRequest(
    StageCCallRequest request, {
    String? platform,
    String? version,
  }) {
    if (request.method == 'getDeviceInfo') {
      return StageCResponse.success(
        id: request.id,
        result: {
          'platform': platform ?? Platform.operatingSystem,
          'version': version ?? Platform.operatingSystemVersion,
        },
      );
    } else {
      return StageCResponse.error(
        id: request.id,
        error: 'Unknown method: ${request.method}',
      );
    }
  }

  /// 수신된 raw 메시지를 분석하여 Stage A SnackBar 또는 Stage C Call을 처리합니다.
  static Future<void> handleRawMessage(
    String rawMessage,
    BuildContext context, {
    Future<void> Function(String script)? runJavaScript,
    void Function(String text)? onShowSnackBar,
    void Function(StageCResponse response)? onResponseSent,
    String? platform,
    String? version,
  }) async {
    // 1. Stage A: showSnackBar 단방향 메시지 확인
    final stageAMessage = StageAMessage.fromJsonString(rawMessage);
    if (stageAMessage != null) {
      StageABridge.handleMessage(
        rawMessage,
        context,
        onShowSnackBar: onShowSnackBar,
      );
      return;
    }

    // 2. Stage C: Call RPC 요청 확인
    final callRequest = StageCCallRequest.fromJsonString(rawMessage);
    if (callRequest != null) {
      final response = handleCallRequest(
        callRequest,
        platform: platform,
        version: version,
      );
      final script = createResponseJs(response);
      if (runJavaScript != null) {
        await runJavaScript(script);
      }
      onResponseSent?.call(response);
      return;
    }

    debugPrint('StageCBridge: Unrecognized message: $rawMessage');
  }

  /// WebViewController에 FlutterBridge JavaScript 채널을 등록합니다. (Stage A & Stage C 호환)
  static void register(
    WebViewController controller,
    BuildContext context, {
    void Function(String text)? onShowSnackBar,
    void Function(StageCResponse response)? onResponseSent,
    String? platform,
    String? version,
  }) {
    controller.addJavaScriptChannel(
      channelName,
      onMessageReceived: (JavaScriptMessage message) {
        handleRawMessage(
          message.message,
          context,
          runJavaScript: controller.runJavaScript,
          onShowSnackBar: onShowSnackBar,
          onResponseSent: onResponseSent,
          platform: platform,
          version: version,
        );
      },
    );
  }
}
