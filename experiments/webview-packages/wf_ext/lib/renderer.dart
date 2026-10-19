// MODE=renderer: Android 렌더러 종료 처리 실측.
//
// webview_flutter_android는 WebViewClient.onRenderProcessGone을 구현하지 않는다. 플랫폼 코드
// (RendererGuardPlugin.kt)가 Dart가 붙인 WebViewClient를 위임 클라이언트로 감싸 렌더러 종료를 받는다.
// 이 화면은 그 알림을 받아 죽은 WebView(위젯·컨트롤러)를 버리고 새로 만든다.
//
// 실행 Intent의 scenario extra로 경우를 고른다(../renderer.sh).
//   control-crash, control-kill  감싸지 않은 WebView 하나: 내비게이션 콜백 → chrome://crash 또는 chrome://kill
//   guard                         감싼 WebView 하나: 콜백 → crash → 재생성 → 콜백 → kill → 재생성(직접 destroy)
//                                 → 대리자 다시 설정 → 다시 감싸기 → crash → 재생성 → 해제 확인
//   two                           보이는 A와 화면 밖 B를 모두 감싸고 A에서 crash
//   two-a-only, two-b-only        한쪽만 감싸고 A에서 crash
//   popup, popup-gc, popup-nomulti  감싼 WebView 하나에서 window.open 뒤 crash. -gc는 crash 전에 Java GC,
//                                 -nomulti는 플랫폼 코드로 setSupportMultipleWindows(false)
// iOS에서는 scenario 없이 _runIos 하나만 돈다(../renderer_ios.sh).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'main.dart' show report;

final _base = Platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://localhost:8080';
const _guard = MethodChannel('exp/renderer_guard');
const _originBridge = MethodChannel('exp/origin_bridge');

/// 화면의 WebView 자리 하나. 렌더러가 죽으면 같은 자리에 세대(generation)를 올려 새 WebView를 만든다.
class _Slot {
  _Slot(this.name, {required this.guarded, required this.visible});
  final String name;
  final bool guarded;
  final bool visible;
  int generation = 0;
  WebViewController? controller;
  int? identifier;
  final deadIdentifiers = <int>[];
  Completer<Map<String, Object?>> gone = Completer();
  final finished = StreamController<String>.broadcast();
  String get tag => '$name$generation';
}

class RendererPage extends StatefulWidget {
  const RendererPage({super.key});

  @override
  State<RendererPage> createState() => _RendererPageState();
}

class _RendererPageState extends State<RendererPage> {
  final _lines = <String>[];
  final _slots = <_Slot>[];
  String _scenario = '?';

  void _log(String event, [Object? data]) {
    unawaited(report(event, data));
    if (mounted) setState(() => _lines.insert(0, '$event ${data ?? ''}'));
  }

  @override
  void initState() {
    super.initState();
    _guard.setMethodCallHandler(_onGuardCall);
    _originBridge.setMethodCallHandler(_onSecureMessage);
    unawaited(_run());
  }

  Future<Object?> _onGuardCall(MethodCall call) async {
    if (call.method != 'onRenderProcessGone') return null;
    final args = Map<String, Object?>.from(call.arguments as Map);
    final slot = _slots.where((s) => s.identifier == args['identifier']).firstOrNull;
    _log('renderer.gone', {'wv': slot?.tag, ...args});
    if (slot != null && !slot.gone.isCompleted) slot.gone.complete(args);
    return null;
  }

  /// #48과 같은 판정: 플랫폼이 알려 준 출처가 허용 출처이고 메인 프레임일 때만 받는다.
  Future<Object?> _onSecureMessage(MethodCall call) async {
    if (call.method != 'onSecureMessage') return null;
    final args = Map<String, Object?>.from(call.arguments as Map);
    final accepted = args['sourceOrigin'] == _base && args['isMainFrame'] == true;
    _log('secure.received', {...args, 'hostDecision': accepted ? 'accept' : 'reject'});
    return {'accepted': accepted, 'verifiedOrigin': args['sourceOrigin'], 'isMainFrame': args['isMainFrame']};
  }

  Future<Map<String, Object?>> _inspect(int id, {bool gc = false, bool deep = false}) async =>
      (await _guard.invokeMapMethod<String, Object?>('inspect', {'identifier': id, 'gc': gc, 'deep': deep}))!;

  NavigationDelegate _delegate(_Slot s) {
    final tag = s.tag;
    return NavigationDelegate(
      onNavigationRequest: (r) {
        final decision = r.url.contains('blocked') ? NavigationDecision.prevent : NavigationDecision.navigate;
        _log('nav.request', {'wv': tag, 'url': r.url, 'isMainFrame': r.isMainFrame, 'decision': decision.name});
        return decision;
      },
      onPageStarted: (url) => _log('page.started', {'wv': tag, 'url': url}),
      onPageFinished: (url) {
        _log('page.finished', {'wv': tag, 'url': url});
        s.finished.add('$tag $url');
      },
      onUrlChange: (change) => _log('url.change', {'wv': tag, 'url': change.url}),
      onWebResourceError: (e) => _log('resource.error', {
        'wv': tag,
        'url': e.url,
        'code': e.errorCode,
        'type': e.errorType?.name,
        'isForMainFrame': e.isForMainFrame,
      }),
      onHttpError: (e) => _log('http.error', {'wv': tag, 'url': e.request?.uri.toString(), 'status': e.response?.statusCode}),
    );
  }

  /// 새 WebView를 만든다. 내비게이션 대리자를 붙인 뒤에 감싼다(대리자를 붙이면 패키지가 WebViewClient를 바꾸므로).
  Future<void> _create(_Slot s) async {
    s.generation++;
    s.gone = Completer();
    final c = WebViewController();
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await c.setNavigationDelegate(_delegate(s));
    final id = (c.platform as AndroidWebViewController).webViewIdentifier;
    s.identifier = id;
    if (s.guarded) {
      final installed = await _guard.invokeMapMethod<String, Object?>('install', {'identifier': id});
      _log('guard.install', {'wv': s.tag, 'identifier': id, ...?installed});
    }
    final added = await _originBridge.invokeMethod<Object?>('attach', {
      'identifier': id,
      'allowedOrigins': [_base],
    });
    _log('created', {'wv': s.tag, 'identifier': id, 'guarded': s.guarded, 'originBridge': added});
    setState(() => s.controller = c);
    await WidgetsBinding.instance.endOfFrame;
  }

  /// 죽은 WebView를 버린다: 위젯을 트리에서 빼고 컨트롤러 참조를 놓는다.
  Future<void> _discard(_Slot s, {bool destroy = false}) async {
    final deadId = s.identifier!;
    final deadTag = s.tag;
    setState(() {
      s.controller = null;
      s.identifier = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    s.deadIdentifiers.add(deadId);
    _log('discarded', {'wv': deadTag, 'identifier': deadId, ...await _inspect(deadId)});
    if (destroy) {
      final called = await _guard.invokeMethod<bool>('destroy', {'identifier': deadId});
      _log('destroy.called', {'wv': deadTag, 'identifier': deadId, 'found': called});
    }
  }

  Future<void> _finished(_Slot s, String needle) {
    final tag = s.tag;
    return s.finished.stream.firstWhere((u) => u.startsWith('$tag ') && u.contains(needle)).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _log('timeout', {'wv': tag, 'waitingFor': needle});
        return '';
      },
    );
  }

  Future<void> _load(_Slot s, String url, String needle) async {
    final done = _finished(s, needle);
    await s.controller!.loadRequest(Uri.parse(url));
    await done;
  }

  /// 내비게이션 콜백 6종이 Dart까지 오는지 본다. index.html은 #48의 출처 확인 통로(SecureBridge)도 다시 확인한다.
  Future<void> _navSuite(_Slot s) async {
    final t = s.tag;
    final c = s.controller!;
    _log('phase', {'n': '$t-nav', 'what': '$t 내비게이션 콜백과 Message 통로'});
    await _load(s, '$_base/index.html?step=$t-load', '$t-load'); // started·finished·urlChange
    await Future<void>.delayed(const Duration(seconds: 3)); // probe.js의 Message와 응답
    final allowed = _finished(s, '$t-allow');
    await c.runJavaScript("location.href = '/index.html?step=$t-allow'"); // onNavigationRequest → 허용
    await allowed;
    await Future<void>.delayed(const Duration(seconds: 2));
    await c.runJavaScript("location.href = '/blocked.html?step=$t-prevent'"); // onNavigationRequest → 막음
    await Future<void>.delayed(const Duration(seconds: 2));
    _log('check.prevented', {'wv': t, 'currentUrl': await c.currentUrl()});
    await c.runJavaScript("history.pushState(null, '', '/index.html?step=$t-pushState')"); // onUrlChange
    await Future<void>.delayed(const Duration(seconds: 1));
    await _load(s, '$_base/missing.html?step=$t-404', '$t-404'); // onHttpError
    await _load(s, 'http://10.0.2.2:1/unreachable?step=$t-neterr', '$t-neterr'); // onWebResourceError
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> _kill(_Slot s, String how) async {
    _log('phase', {'n': '${s.tag}-$how', 'what': '${s.tag}에서 chrome://$how'});
    _log('renderer.before', {'hostPid': await _guard.invokeMethod<int>('hostPid')});
    unawaited(s.controller!.loadRequest(Uri.parse('chrome://$how')));
  }

  Future<void> _awaitGone(Iterable<_Slot> slots) => Future.wait([
    for (final s in slots)
      s.gone.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _log('gone.timeout', {'wv': s.tag});
          return const {};
        },
      ),
  ]);

  /// 큰 배열을 만들고 바로 버려 Dart GC를 일으킨다. Dart 쪽 WebView 객체가 수거되어야
  /// 패키지 InstanceManager가 Java 쪽 강한 참조를 놓는다(그때 WebView.destroy()도 부른다).
  Future<void> _checkReleased() async {
    _log('phase', {'n': 'release', 'what': 'Dart GC를 재촉한 뒤 죽은 WebView가 패키지에서 풀렸는지'});
    for (final s in _slots) {
      for (final id in s.deadIdentifiers) {
        _log('dead.inspect.beforeGc', {'slot': s.name, 'identifier': id, ...await _inspect(id, gc: true)});
      }
    }
    var sink = 0;
    for (var round = 0; round < 4; round++) {
      for (var i = 0; i < 24; i++) {
        sink ^= List<int>.filled(1 << 20, i).length;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await Future<void>.delayed(const Duration(seconds: 4)); // Java InstanceManager는 3초마다 정리한다
    for (final s in _slots) {
      for (final id in s.deadIdentifiers) {
        _log('dead.inspect', {'slot': s.name, 'identifier': id, 'sink': sink & 1, ...await _inspect(id, gc: true)});
      }
    }
  }

  /// iOS(선택 항목): WebContent 프로세스가 끝난 뒤 다시 로드하면 플랫폼 코드가 붙인 Message 통로와
  /// WKUserScript가 남는지 본다. 프로세스는 ../renderer_ios.sh가 Mac에서 kill -9로 끝낸다.
  Future<void> _runIos() async {
    final s = _Slot('I', guarded: false, visible: true)..generation = 1;
    setState(() {
      _scenario = 'ios-webcontent';
      _slots.add(s);
    });
    final terminated = Completer<void>();
    final c = WebViewController();
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await c.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) {
          _log('page.finished', {'wv': s.tag, 'url': url});
          s.finished.add('${s.tag} $url');
        },
        onWebResourceError: (e) {
          _log('resource.error', {'wv': s.tag, 'url': e.url, 'code': e.errorCode, 'type': e.errorType?.name});
          if (e.errorType == WebResourceErrorType.webContentProcessTerminated && !terminated.isCompleted) {
            terminated.complete();
          }
        },
      ),
    );
    final id = (c.platform as WebKitWebViewController).webViewIdentifier;
    final added = await _originBridge.invokeMethod<Object?>('attach', {
      'identifier': id,
      'allowedOrigins': [_base],
    });
    _log('created', {'wv': s.tag, 'identifier': id, 'originBridge': added});
    setState(() => s.controller = c);
    await _load(s, '$_base/index.html?step=I1-load', 'I1-load');
    await Future<void>.delayed(const Duration(seconds: 3));
    _log('phase', {'n': 'ios-kill', 'what': '이제 WebContent 프로세스를 끝낸다'});
    await terminated.future.timeout(
      const Duration(seconds: 40),
      onTimeout: () => _log('timeout', {'waitingFor': 'webContentProcessTerminated'}),
    );
    _log('phase', {'n': 'ios-reload', 'what': 'reload 뒤 Message 통로와 문서 시작 스크립트'});
    final reloaded = _finished(s, 'I1-load');
    await c.reload();
    await reloaded;
    await Future<void>.delayed(const Duration(seconds: 3));
    await _load(s, '$_base/index.html?step=I1-afterKill', 'I1-afterKill');
    await Future<void>.delayed(const Duration(seconds: 3));
    _log('done');
  }

  Future<void> _run() async {
    if (Platform.isIOS) return _runIos();
    final scenario = await _guard.invokeMethod<String>('scenario') ?? 'guard';
    final slots = switch (scenario) {
      'control-crash' || 'control-kill' => [_Slot('A', guarded: false, visible: true)],
      'guard' || 'popup' || 'popup-gc' || 'popup-nomulti' => [_Slot('A', guarded: true, visible: true)],
      'two' => [_Slot('A', guarded: true, visible: true), _Slot('B', guarded: true, visible: false)],
      'two-a-only' => [_Slot('A', guarded: true, visible: true), _Slot('B', guarded: false, visible: false)],
      'two-b-only' => [_Slot('A', guarded: false, visible: true), _Slot('B', guarded: true, visible: false)],
      _ => throw ArgumentError('unknown scenario $scenario'),
    };
    setState(() {
      _scenario = scenario;
      _slots.addAll(slots);
    });
    _log('scenario', {'name': scenario, 'hostPid': await _guard.invokeMethod<int>('hostPid')});
    final a = _slots.first;

    if (scenario.startsWith('control-')) {
      await _create(a);
      await _navSuite(a); // 감싸지 않았을 때의 콜백(대조군)
      await _kill(a, scenario.substring('control-'.length));
      await Future<void>.delayed(const Duration(seconds: 8));
      _log('survived', {'hostPid': await _guard.invokeMethod<int>('hostPid')}); // 앱이 죽었으면 찍히지 않는다
      return;
    }

    if (scenario == 'guard') {
      await _create(a);
      await _navSuite(a); // A1: 원래 WebView
      await _kill(a, 'crash');
      await _awaitGone([a]);
      await _discard(a); // destroy는 패키지 InstanceManager에 맡긴다
      await _create(a);
      await _navSuite(a); // A2: 다시 만든 WebView
      await _kill(a, 'kill');
      await _awaitGone([a]);
      await _discard(a, destroy: true); // 이번에는 플랫폼 코드에서 직접 destroy
      await _create(a);
      await _load(a, '$_base/index.html?step=${a.tag}-load', '${a.tag}-load');
      await Future<void>.delayed(const Duration(seconds: 3));

      // 대리자를 다시 설정하면 패키지가 WebViewClient를 새로 넣어 감싼 것이 빠지는지
      _log('phase', {'n': '${a.tag}-redelegate', 'what': 'setNavigationDelegate를 다시 부른 뒤'});
      _log('client.before', {'wv': a.tag, ...await _inspect(a.identifier!)});
      await a.controller!.setNavigationDelegate(_delegate(a));
      _log('client.afterRedelegate', {'wv': a.tag, ...await _inspect(a.identifier!)});
      final again = await _guard.invokeMapMethod<String, Object?>('install', {'identifier': a.identifier});
      _log('guard.install', {'wv': a.tag, 'identifier': a.identifier, ...?again});
      _log('client.afterReinstall', {'wv': a.tag, ...await _inspect(a.identifier!)});
      await _kill(a, 'crash');
      await _awaitGone([a]);
      await _discard(a);
      await _create(a);
      await _load(a, '$_base/index.html?step=${a.tag}-load', '${a.tag}-load');
      await Future<void>.delayed(const Duration(seconds: 3));
      await _checkReleased();
      _log('done', {'hostPid': await _guard.invokeMethod<int>('hostPid')});
      return;
    }

    if (scenario.startsWith('popup')) {
      // 패키지는 setSupportMultipleWindows(true)가 기본값이다. window.open이 오면 패키지 WebChromeClient가
      // 임시 WebView(new WebView)를 만들어 URL만 가로챈다. 그 임시 WebView는 감쌀 수 없다.
      await _create(a);
      if (scenario == 'popup-nomulti') {
        final off = await _guard.invokeMethod<bool>('disableMultipleWindows', {'identifier': a.identifier});
        _log('multipleWindows.off', {'wv': a.tag, 'found': off});
      }
      await _load(a, '$_base/index.html?step=${a.tag}-load', '${a.tag}-load');
      final popped = _finished(a, '${a.tag}-popup');
      await a.controller!.runJavaScript("window.open('/index.html?step=${a.tag}-popup')");
      await popped;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (scenario == 'popup-gc') {
        // 임시 WebView가 Java GC로 수거되면 렌더러와의 연결도 풀리는지 본다.
        for (var i = 0; i < 3; i++) {
          await _inspect(a.identifier!, gc: true);
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        _log('popup.gc', {'wv': a.tag});
      }
      await _kill(a, 'crash');
      await _awaitGone([a]);
      await Future<void>.delayed(const Duration(seconds: 3));
      _log('survived', {'hostPid': await _guard.invokeMethod<int>('hostPid')});
      return;
    }

    // 두 WebView: 보이는 A와 화면 밖(Offstage) B. 렌더러 프로세스는 앱 안에서 하나를 같이 쓴다.
    for (final s in _slots) {
      await _create(s);
    }
    for (final s in _slots) {
      await _load(s, '$_base/index.html?step=${s.tag}-load', '${s.tag}-load');
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    for (final s in _slots) {
      _log('renderer.info', {'wv': s.tag, ...await _inspect(s.identifier!, deep: true)});
    }
    await _kill(a, 'crash');
    await _awaitGone(_slots.where((s) => s.guarded));
    await Future<void>.delayed(const Duration(seconds: 1));
    for (final s in _slots) {
      await _discard(s);
    }
    for (final s in _slots) {
      await _create(s);
    }
    for (final s in _slots) {
      await _load(s, '$_base/index.html?step=${s.tag}-load', '${s.tag}-load');
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await _checkReleased();
    _log('done', {'hostPid': await _guard.invokeMethod<int>('hostPid')});
  }

  @override
  Widget build(BuildContext context) {
    Widget view(_Slot s) => s.controller == null
        ? Center(child: Text('${s.tag}: WebView 없음'))
        : WebViewWidget(key: ValueKey(s.tag), controller: s.controller!);
    final status = [for (final s in _slots) '${s.tag}${s.guarded ? '(감쌈)' : ''} id=${s.identifier}'].join('  ');
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Text('scenario=$_scenario  $status', style: const TextStyle(fontSize: 11)),
            for (final s in _slots.where((s) => s.visible)) Expanded(child: view(s)),
            for (final s in _slots.where((s) => !s.visible))
              Offstage(child: SizedBox(width: 360, height: 300, child: view(s))),
            SizedBox(
              height: 200,
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
