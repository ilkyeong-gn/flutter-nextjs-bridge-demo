// 후보 C 실측: flutter_inappwebview 6.2.0-beta.3.
//
// MODE=full (기본)
//   - callHandler(6.2 베타의 origin·isMainFrame)와 WebMessageListener를 같은 페이지에서 확인한다.
//   - shouldOverrideUrlLoading으로 iframe의 첫 로드와 이후 탐색이 콜백을 거치는지 본다.
//   - iOS: UIScene 생명주기에서 keyWindow·delegate.window에 기대는 기능(InAppBrowser,
//     ChromeSafariBrowser, HeadlessInAppWebView)과 JS alert가 동작하는지 본다.
// MODE=hardened
//   - full과 같되 6.2 베타의 Bridge 제한 설정(메인 프레임만, 허용 출처만)을 켜고 1단계만 본다.
// MODE=coldstart
//   - flutter_inappwebview #2843의 재현 앱 모양(1×1 about:blank InAppWebView)으로
//     onWebViewCreated가 불리는지만 기록한다. release 빌드 콜드 스타트 반복용.
// 모든 관찰은 수집기(:8090, ../server.py)로 보낸다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const _mode = String.fromEnvironment('MODE', defaultValue: 'full');
// iOS 시뮬레이터는 Mac의 localhost를 그대로 쓰고, Android 에뮬레이터는 10.0.2.2가 Mac을 가리킨다.
// 실기기는 HOST로 바꾼다(예: adb reverse 뒤 --dart-define=HOST=127.0.0.1).
const _hostOverride = String.fromEnvironment('HOST');
final _host = _hostOverride.isNotEmpty ? _hostOverride : (Platform.isAndroid ? '10.0.2.2' : 'localhost');
// MAIN_PORT=80이면 포트를 생략한 출처(http://localhost)로 띄운다. 출처 규칙의 포트 처리 확인용.
const _mainPort = int.fromEnvironment('MAIN_PORT', defaultValue: 8080);
final _mainOrigin = 'http://$_host${_mainPort == 80 ? '' : ':$_mainPort'}';
final _mainUrl = '$_mainOrigin/index.html';
final _allowedOrigin = _mainOrigin;
final _runId = DateTime.now().millisecondsSinceEpoch.toString();
final _start = DateTime.now();

Future<void> report(String event, [Object? data]) async {
  final record = {
    'src': 'dart',
    'app': 'iaw_beta',
    'mode': _mode,
    'buildMode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    'platform': Platform.operatingSystem,
    'runId': _runId,
    'event': event,
    'data': data,
    'sinceStartMs': DateTime.now().difference(_start).inMilliseconds,
    't': DateTime.now().millisecondsSinceEpoch,
  };
  // ignore: avoid_print
  print('EXP ${jsonEncode(record)}');
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.postUrl(Uri.parse('http://$_host:8090/log'));
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
  runApp(MaterialApp(home: _mode == 'coldstart' ? const ColdStartPage() : const FullPage()));
}

/// MODE=hardened에서 쓰는 6.2 베타의 Bridge 제한 설정.
/// iOS는 허용 목록을 JS 정규식으로, Android는 addWebMessageListener 규칙으로 해석한다.
InAppWebViewSettings _settings() {
  final hardened = _mode == 'hardened';
  return InAppWebViewSettings(
    useShouldOverrideUrlLoading: true,
    isInspectable: true,
    javaScriptBridgeForMainFrameOnly: hardened ? true : null,
    javaScriptBridgeOriginAllowList: hardened ? {_allowedOrigin} : null,
    javaScriptHandlersForMainFrameOnly: hardened ? true : null,
    javaScriptHandlersOriginAllowList: hardened ? {_allowedOrigin} : null,
  );
}

/// #2843 재현 앱과 같은 모양: 1×1 about:blank InAppWebView 하나, 3초 뒤 판정.
class ColdStartPage extends StatefulWidget {
  const ColdStartPage({super.key});

  @override
  State<ColdStartPage> createState() => _ColdStartPageState();
}

class _ColdStartPageState extends State<ColdStartPage> {
  bool _created = false;
  bool _stuck = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _stuck = !_created);
      unawaited(report('verdict', {'created': _created}));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_created ? 'onWebViewCreated FIRED' : (_stuck ? 'STUCK' : 'waiting...')),
            const SizedBox(height: 20),
            SizedBox(
              width: 1,
              height: 1,
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri('about:blank')),
                onWebViewCreated: (_) {
                  setState(() => _created = true);
                  unawaited(report('onWebViewCreated'));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FullPage extends StatefulWidget {
  const FullPage({super.key});

  @override
  State<FullPage> createState() => _FullPageState();
}

class _FullPageState extends State<FullPage> {
  InAppWebViewController? _controller;
  final _lines = <String>[];

  void _log(String event, [Object? data]) {
    unawaited(report(event, data));
    if (mounted) setState(() => _lines.insert(0, '$event ${data ?? ''}'));
  }

  Future<void> _onCreated(InAppWebViewController controller) async {
    _controller = controller;
    _log('onWebViewCreated', {'mode': _mode});

    controller.addJavaScriptHandler(
      handlerName: 'Legacy',
      callback: (JavaScriptHandlerFunctionData data) {
        final accepted = data.origin.toString() == _allowedOrigin && data.isMainFrame;
        _log('callHandler.received', {
          'args': data.args,
          'origin': data.origin.toString(),
          'isMainFrame': data.isMainFrame,
          'requestUrl': data.requestUrl.toString(),
          'hostDecision': accepted ? 'accept' : 'reject',
        });
        return {'accepted': accepted, 'origin': data.origin.toString(), 'isMainFrame': data.isMainFrame};
      },
    );

    final listenerSupported = defaultTargetPlatform != TargetPlatform.android ||
        await WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER);
    _log('webMessageListener.supported', listenerSupported);
    if (listenerSupported) {
      for (final (name, rules) in [('SecureBridge', {_allowedOrigin}), ('SecureBridgeAll', {'*'})]) {
        await controller.addWebMessageListener(
          WebMessageListener(
            jsObjectName: name,
            allowedOriginRules: rules,
            onPostMessage: (message, sourceOrigin, isMainFrame, replyProxy) {
              final accepted = sourceOrigin.toString() == _allowedOrigin && isMainFrame;
              _log('secure.received', {
                'name': name,
                'message': message?.data,
                'sourceOrigin': sourceOrigin.toString(),
                'isMainFrame': isMainFrame,
                'hostDecision': accepted ? 'accept' : 'reject',
              });
              unawaited(replyProxy.postMessage(WebMessage(
                data: jsonEncode({'accepted': accepted, 'verifiedOrigin': sourceOrigin.toString(), 'isMainFrame': isMainFrame}),
              )));
            },
          ),
        );
      }
    }

    _log('phase', {'n': 1, 'what': 'callHandler·WebMessageListener·내비게이션 콜백'});
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri('$_mainUrl?phase=1')));
    await Future<void>.delayed(const Duration(seconds: 6));
    if (_mode == 'hardened') {
      _log('done');
      return;
    }

    // 대조군: 페이지가 JS로 메인 프레임을 옮기면 내비게이션 콜백이 오는지
    _log('phase', {'n': '1b', 'what': '대조군: JS로 메인 프레임 이동'});
    await controller.evaluateJavascript(source: "location.href = '/index.html?phase=1b'");
    await Future<void>.delayed(const Duration(seconds: 5));

    if (defaultTargetPlatform == TargetPlatform.iOS) await _uiSceneChecks();
    _log('done');
  }

  /// keyWindow·delegate.window에 기대는 iOS 기능을 UIScene 앱에서 차례로 연다.
  Future<void> _uiSceneChecks() async {
    _log('phase', {'n': 'uiscene', 'what': 'InAppBrowser → ChromeSafariBrowser → HeadlessInAppWebView → JS alert'});

    final browser = _LoggingInAppBrowser(_log);
    try {
      await browser.openUrlRequest(urlRequest: URLRequest(url: WebUri('$_mainUrl?phase=inappbrowser')));
      _log('inAppBrowser.openReturned', {'isOpened': browser.isOpened()});
    } catch (e) {
      _log('inAppBrowser.openError', '$e');
    }
    await Future<void>.delayed(const Duration(seconds: 4));
    if (browser.isOpened()) await browser.close();
    await Future<void>.delayed(const Duration(seconds: 2));
    _log('mainWebView.afterInAppBrowser', {'eval': await _controller?.evaluateJavascript(source: 'location.href')});

    final safari = _LoggingSafariBrowser(_log);
    try {
      await safari.open(url: WebUri('$_mainUrl?phase=safari'));
      _log('safari.openReturned', {'isOpened': safari.isOpened()});
    } catch (e) {
      _log('safari.openError', '$e');
    }
    await Future<void>.delayed(const Duration(seconds: 4));
    if (safari.isOpened()) await safari.close();
    await Future<void>.delayed(const Duration(seconds: 2));

    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('$_mainUrl?phase=headless')),
      onWebViewCreated: (_) => _log('headless.created'),
      onLoadStop: (controller, url) async {
        _log('headless.loadStop', {'url': '$url', 'title': await controller.evaluateJavascript(source: 'document.title')});
      },
    );
    await headless.run();
    _log('headless.run', {'isRunning': headless.isRunning()});
    await Future<void>.delayed(const Duration(seconds: 4));
    await headless.dispose();

    // 마지막: 네이티브 alert가 뜨는지(화면 캡처로 확인). 닫지 않으면 이후 JS가 멈추므로 맨 끝에 둔다.
    _log('alert.trigger');
    await _controller?.evaluateJavascript(source: "setTimeout(() => alert('alert under UIScene'), 200)");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InAppWebView(
                initialSettings: _settings(),
                onWebViewCreated: (controller) => unawaited(_onCreated(controller)),
                shouldOverrideUrlLoading: (controller, action) async {
                  _log('nav.request', {
                    'url': action.request.url.toString(),
                    'isForMainFrame': action.isForMainFrame,
                    'navigationType': action.navigationType?.toString(),
                  });
                  return NavigationActionPolicy.ALLOW;
                },
                onLoadStart: (controller, url) => _log('page.started', {'url': '$url'}),
                onLoadStop: (controller, url) => _log('page.finished', {'url': '$url'}),
                onReceivedError: (controller, request, error) => _log('resource.error', {
                  'url': request.url.toString(),
                  'isForMainFrame': request.isForMainFrame,
                  'type': error.type.toString(),
                  'description': error.description,
                }),
              ),
            ),
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

class _LoggingInAppBrowser extends InAppBrowser {
  _LoggingInAppBrowser(this._log);
  final void Function(String, [Object?]) _log;

  @override
  void onBrowserCreated() => _log('inAppBrowser.created');

  @override
  void onLoadStop(WebUri? url) => _log('inAppBrowser.loadStop', {'url': '$url'});

  @override
  void onExit() => _log('inAppBrowser.exit');
}

class _LoggingSafariBrowser extends ChromeSafariBrowser {
  _LoggingSafariBrowser(this._log);
  final void Function(String, [Object?]) _log;

  @override
  void onOpened() => _log('safari.opened');

  @override
  void onCompletedInitialLoad(bool? didLoadSuccessfully) =>
      _log('safari.initialLoad', {'didLoadSuccessfully': didLoadSuccessfully});

  @override
  void onClosed() => _log('safari.closed');
}
