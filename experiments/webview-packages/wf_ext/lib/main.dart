// 후보 B 실측: webview_flutter + 플랫폼 코드 확장.
//
// - 기존 JavaScript 채널(`Legacy`)과 플랫폼 코드로 붙인 출처 확인 통로(`SecureBridge`)를
//   한 WebView에 함께 둔다.
//   - Android: androidx.webkit `addWebMessageListener`(+ `addDocumentStartJavaScript`)
//   - iOS: `WKScriptMessageHandlerWithReply` + `WKScriptMessage.frameInfo`(+ 문서 시작 `WKUserScript`)
// - 1단계: 두 통로를 모두 둔 채 로드한다.
// - 2단계: webview_flutter의 `removeJavaScriptChannel`을 부른 뒤 다시 로드해, 플랫폼 코드가
//   넣은 것이 남는지 본다.
// - 모든 관찰은 수집기(:8090, ../server.py)로 보낸다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'renderer.dart';

// iOS 시뮬레이터는 Mac의 localhost를 그대로 쓰고, Android 에뮬레이터는 10.0.2.2가 Mac을 가리킨다.
final _host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
final _mainUrl = 'http://$_host:8080/index.html';
final _allowedOrigins = ['http://$_host:8080'];
const _originBridge = MethodChannel('exp/origin_bridge');
final _runId = DateTime.now().millisecondsSinceEpoch.toString();

Future<void> report(String event, [Object? data]) async {
  final record = {
    'src': 'dart',
    'app': 'wf_ext',
    'platform': Platform.operatingSystem,
    'runId': _runId,
    'event': event,
    'data': data,
    't': DateTime.now().millisecondsSinceEpoch,
  };
  // ignore: avoid_print
  print('EXP ${jsonEncode(record)}');
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.postUrl(Uri.parse('http://${Platform.isAndroid ? '10.0.2.2' : '127.0.0.1'}:8090/log'));
    final bytes = utf8.encode(jsonEncode(record));
    request.headers.contentType = ContentType.json;
    request.contentLength = bytes.length; // chunked로 보내면 수집기가 본문을 읽지 못한다
    request.add(bytes);
    await (await request.close()).drain<void>();
    client.close();
  } catch (e) {
    // ignore: avoid_print
    print('EXP report failed: $e');
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(report('app.launch'));
  // MODE=renderer는 Android 렌더러 종료 처리 실측(renderer.dart). 기본값은 #48의 출처 확인 실측이다.
  runApp(const MaterialApp(home: String.fromEnvironment('MODE') == 'renderer' ? RendererPage() : ExperimentPage()));
}

class ExperimentPage extends StatefulWidget {
  const ExperimentPage({super.key});

  @override
  State<ExperimentPage> createState() => _ExperimentPageState();
}

class _ExperimentPageState extends State<ExperimentPage> {
  late final WebViewController _controller;
  final _lines = <String>[];

  void _log(String event, [Object? data]) {
    unawaited(report(event, data));
    if (mounted) setState(() => _lines.insert(0, '$event ${data ?? ''}'));
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            _log('nav.request', {'url': request.url, 'isMainFrame': request.isMainFrame});
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) => _log('page.started', {'url': url}),
          onPageFinished: (url) => _log('page.finished', {'url': url}),
          onWebResourceError: (error) => _log('resource.error', {
            'url': error.url,
            'code': error.errorCode,
            'description': error.description,
            'isForMainFrame': error.isForMainFrame,
          }),
        ),
      )
      ..addJavaScriptChannel(
        'Legacy',
        onMessageReceived: (message) => _log('Legacy.received', {'message': message.message}),
      );
    final platform = _controller.platform;
    if (platform is WebKitWebViewController) unawaited(platform.setInspectable(true));
    _originBridge.setMethodCallHandler(_onNativeCall);
    unawaited(_run());
  }

  /// 플랫폼 코드가 받은 Message를 넘긴다. Host는 플랫폼이 판정한 출처와 프레임으로 받아들일지 정한다.
  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method != 'onSecureMessage') return null;
    final args = Map<String, Object?>.from(call.arguments as Map);
    final accepted = _allowedOrigins.contains(args['sourceOrigin']) && args['isMainFrame'] == true;
    _log('secure.received', {...args, 'hostDecision': accepted ? 'accept' : 'reject'});
    return {'accepted': accepted, 'verifiedOrigin': args['sourceOrigin'], 'isMainFrame': args['isMainFrame']};
  }

  int get _webViewIdentifier => switch (_controller.platform) {
    final AndroidWebViewController android => android.webViewIdentifier,
    final WebKitWebViewController webKit => webKit.webViewIdentifier,
    _ => throw UnsupportedError('unknown platform'),
  };

  Future<void> _run() async {
    _log('features', await _originBridge.invokeMethod<Object?>('features'));
    _log(
      'attach',
      await _originBridge.invokeMethod<Object?>('attach', {
        'identifier': _webViewIdentifier,
        'allowedOrigins': _allowedOrigins,
      }),
    );

    _log('phase', {'n': 1, 'what': 'Legacy 채널과 플랫폼 코드 통로를 함께 둔 채 로드'});
    await _controller.loadRequest(Uri.parse('$_mainUrl?phase=1'));
    await Future<void>.delayed(const Duration(seconds: 6));

    // 대조군: 페이지가 JS로 메인 프레임을 옮기면 내비게이션 콜백이 오는지
    _log('phase', {'n': '1b', 'what': '대조군: JS로 메인 프레임 이동'});
    await _controller.runJavaScript("location.href = '/index.html?phase=1b'");
    await Future<void>.delayed(const Duration(seconds: 5));

    _log('phase', {'n': 2, 'what': 'removeJavaScriptChannel(Legacy) 뒤 다시 로드'});
    await _controller.removeJavaScriptChannel('Legacy');
    await _controller.loadRequest(Uri.parse('$_mainUrl?phase=2'));
    await Future<void>.delayed(const Duration(seconds: 6));

    _log('done');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: WebViewWidget(controller: _controller)),
            SizedBox(
              height: 180,
              child: ListView(
                children: [for (final line in _lines) Text(line, style: const TextStyle(fontSize: 9))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
