import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// 받은 URI를 화면에 쌓고 `DLE` 접두어로 로그에 남긴다.
// iOS는 `xcrun simctl spawn booted log stream`, Android는 `adb logcat -s flutter`로 본다.
final _received = ValueNotifier<List<String>>([]);
final _startedAt = DateTime.now();

void _log(String kind, Object? value) {
  final ms = DateTime.now().difference(_startedAt).inMilliseconds;
  final line = '$kind $value (+${ms}ms)';
  // ignore: avoid_print
  print('DLE $line');
  _received.value = [..._received.value, line];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _log('main', 'start');
  final appLinks = AppLinks();
  try {
    final initial = await appLinks.getInitialLink();
    _log('initial', initial);
  } catch (e) {
    _log('initial-error', e);
  }
  appLinks.uriLinkStream.listen(
    (uri) => _log('stream', uri),
    onError: (Object e) => _log('stream-error', e),
  );
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('deeplink-entry')),
        body: Column(
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final url in const [
                  'https://fan.example/not-in-table',
                  'https://fan.example/posts/3',
                ])
                  ElevatedButton(
                    key: ValueKey(url),
                    onPressed: () async {
                      final ok = await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                      _log('launchUrl', '$url -> $ok');
                    },
                    child: Text(Uri.parse(url).path),
                  ),
              ],
            ),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: _received,
                builder: (context, lines, _) => ListView(
                  children: [for (final l in lines) Text(l)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
