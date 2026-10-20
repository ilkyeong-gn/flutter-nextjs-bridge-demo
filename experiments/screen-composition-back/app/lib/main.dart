// 화면 구성·뒤로 가기 실측용 Host. webview_flutter만 쓴다.
//
// 앱은 스스로 시나리오를 돌지 않는다. 0.3초마다 수집기(:8090/cmd)에서 명령을 가져와 실행하고,
// 결과와 관찰한 콜백을 모두 수집기(:8090/log)로 보낸다. 명령 순서는 ../run_*.sh가 정한다.
// 실제 탭·스와이프는 스크립트가 adb(Android)나 XCUITest(iOS)로 보낸다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

final _host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
final _collector = 'http://${Platform.isAndroid ? '10.0.2.2' : '127.0.0.1'}:8090';
final _navigatorKey = GlobalKey<NavigatorState>();
final _pages = <String, _WebPageState>{};

Future<void> report(String event, [Object? data]) async {
  final record = {'src': 'dart', 'platform': Platform.operatingSystem, 'event': event, 'data': data, 't': DateTime.now().millisecondsSinceEpoch};
  // ignore: avoid_print
  print('EXP ${jsonEncode(record)}');
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.postUrl(Uri.parse('$_collector/log'));
    final bytes = utf8.encode(jsonEncode(record));
    request.headers.contentType = ContentType.json;
    request.contentLength = bytes.length;
    request.add(bytes);
    await (await request.close()).drain<void>();
    client.close();
  } catch (_) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(report('app.launch'));
  runApp(MaterialApp(
    navigatorKey: _navigatorKey,
    navigatorObservers: [_Observer()],
    home: const WebPage(id: 'root', path: '/', root: true),
  ));
  _Lifecycle();
  unawaited(_pollCommands());
}

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => unawaited(report('app.lifecycle', state.name));
}

class _Observer extends NavigatorObserver {
  String _name(Route<dynamic>? r) => '${r?.settings.name ?? r.runtimeType}';
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => unawaited(report('route.push', _name(route)));
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => unawaited(report('route.pop', _name(route)));
  @override
  void didStartUserGesture(Route<dynamic> route, Route<dynamic>? previousRoute) => unawaited(report('route.userGesture.start', _name(route)));
  @override
  void didStopUserGesture() => unawaited(report('route.userGesture.stop'));
}

Future<void> _pollCommands() async {
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final response = await (await client.getUrl(Uri.parse('$_collector/cmd'))).close();
      final list = jsonDecode(await response.transform(utf8.decoder).join()) as List;
      client.close();
      for (final cmd in list) {
        await _run(Map<String, Object?>.from(cmd as Map));
      }
    } catch (_) {}
  }
}

Future<void> _run(Map<String, Object?> cmd) async {
  final name = cmd['cmd'] as String;
  final page = _pages[cmd['id'] ?? 'root'];
  final c = page?._controller;
  unawaited(report('cmd', cmd));
  if (page == null && const {'load', 'js', 'state', 'goBack', 'hostMsg', 'rect'}.contains(name)) {
    await report('cmd.noPage', cmd);
    return;
  }
  switch (name) {
    case 'reset':
      // 루트를 새 WebView로 바꿔 WebView 기록을 비운다.
      unawaited(_navigatorKey.currentState!.pushAndRemoveUntil(
        PageRouteBuilder<void>(settings: const RouteSettings(name: 'root'), pageBuilder: (_, _, _) => WebPage(id: 'root', path: cmd['path'] as String, root: true)),
        (_) => false,
      ));
    case 'load':
      await c!.loadRequest(Uri.parse('http://$_host:3000${cmd['path']}'));
    case 'js':
      await c!.runJavaScript(cmd['code'] as String);
    case 'state':
      await report('state', {'id': page!.widget.id, 'canGoBack': await c!.canGoBack(), 'currentUrl': await c.currentUrl(), 'tag': cmd['tag']});
    case 'goBack':
      await c!.goBack();
    case 'hostMsg':
      // 가린 동안 보낸 runJavaScript가 언제 끝나는지 본다.
      final sentAt = DateTime.now().millisecondsSinceEpoch;
      final n = cmd['n'];
      unawaited(c!.runJavaScript('window.__hostMsg && window.__hostMsg($n, $sentAt)').then(
            (_) => report('hostMsg.done', {'n': n, 'elapsedMs': DateTime.now().millisecondsSinceEpoch - sentAt}),
            onError: (Object e) => report('hostMsg.error', {'n': n, 'error': '$e'}),
          ));
    case 'cover':
      unawaited(_navigatorKey.currentState!.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'cover'),
        builder: (_) => Scaffold(appBar: AppBar(title: const Text('Flutter 화면(가림)')), body: const Center(child: Text('opaque MaterialPageRoute'))),
      )));
    case 'pushWeb':
      final id = cmd['id'] as String;
      final route = cmd['cupertino'] == false
          ? MaterialPageRoute<void>(settings: RouteSettings(name: 'web:$id'), builder: (_) => WebPage(id: id, path: cmd['path'] as String))
          : CupertinoPageRoute<void>(settings: RouteSettings(name: 'web:$id'), builder: (_) => WebPage(id: id, path: cmd['path'] as String));
      unawaited(_navigatorKey.currentState!.push(route));
    case 'pop':
      _navigatorKey.currentState!.pop();
    case 'rect':
      // 요소 가운데의 화면 좌표. 논리 좌표(iOS XCUITest)와 물리 픽셀(adb input tap)을 함께 준다.
      final sel = cmd['selector'] as String;
      final inner = cmd['inFrame'] == true;
      final js = inner
          ? "(()=>{const f=document.getElementById('frame').getBoundingClientRect();return JSON.stringify({x:f.left+f.width/2,y:f.top+60});})()"
          : "(()=>{const r=document.querySelector('$sel').getBoundingClientRect();return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()";
      var raw = await c!.runJavaScriptReturningResult(js);
      if (raw is String && raw.startsWith('"')) raw = jsonDecode(raw);
      final p = jsonDecode(raw as String) as Map;
      final box = page!._webKey.currentContext!.findRenderObject()! as RenderBox;
      final origin = box.localToGlobal(Offset.zero);
      final dpr = page.mounted ? MediaQuery.devicePixelRatioOf(page.context) : 1.0;
      final lx = origin.dx + (p['x'] as num), ly = origin.dy + (p['y'] as num);
      await report('rect', {'selector': sel, 'x': lx, 'y': ly, 'px': (lx * dpr).round(), 'py': (ly * dpr).round(), 'tag': cmd['tag']});
  }
}

class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.id, required this.path, this.root = false});
  final String id;
  final String path;
  final bool root;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController _controller;
  final _webKey = GlobalKey();

  void _log(String event, [Object? data]) => unawaited(report(event, {'id': widget.id, ...?data as Map<String, Object?>?}));

  @override
  void initState() {
    super.initState();
    _pages[widget.id] = this;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (r) {
          _log('nav.request', {'url': r.url, 'isMainFrame': r.isMainFrame});
          return NavigationDecision.navigate;
        },
        onPageStarted: (url) => _log('page.started', {'url': url}),
        onPageFinished: (url) => _log('page.finished', {'url': url}),
        onUrlChange: (change) => _log('url.change', {'url': change.url}),
      ))
      ..addJavaScriptChannel('Log', onMessageReceived: (m) {
        final data = jsonDecode(m.message) as Map<String, Object?>;
        unawaited(report('js.channel', {'id': widget.id, 'recvT': DateTime.now().millisecondsSinceEpoch, ...data}));
      });
    final platform = _controller.platform;
    if (platform is WebKitWebViewController) {
      unawaited(platform.setInspectable(true));
      unawaited(platform.setAllowsBackForwardNavigationGestures(true));
      unawaited(platform.setOnCanGoBackChange((v) => _log('ios.canGoBackChange', {'canGoBack': v})));
    }
    unawaited(_controller.loadRequest(Uri.parse('http://$_host:3000${widget.path}')));
    _log('webpage.init');
  }

  @override
  void dispose() {
    _log('webpage.dispose');
    if (_pages[widget.id] == this) _pages.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(title: Text('WebView ${widget.id}${widget.root ? ' (root)' : ''}')),
      body: WebViewWidget(key: _webKey, controller: _controller),
    );
    if (!widget.root) return scaffold;
    // 루트는 Flutter가 뒤로 가기를 받는다. WebView가 뒤로 가기를 먼저 먹는지 본다.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        _log('popScope.invoked', {'didPop': didPop, 'canGoBack': await _controller.canGoBack(), 'currentUrl': await _controller.currentUrl()});
      },
      child: scaffold,
    );
  }
}
