import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:app/config.dart';
import 'package:app/bridge/stage_a_bridge.dart';

enum Stage {
  stageA('stage-a', 'Stage A'),
  stageB('stage-b', 'Stage B'),
  stageC('stage-c', 'Stage C');

  final String path;
  final String label;
  const Stage(this.path, this.label);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HostApp());
}

class HostApp extends StatelessWidget {
  final Widget? webViewWidget;
  final void Function(String text)? onShowSnackBar;

  const HostApp({
    super.key,
    this.webViewWidget,
    this.onShowSnackBar,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Host: Flutter WebView Bridge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: HostHomeScreen(
        webViewWidget: webViewWidget,
        onShowSnackBar: onShowSnackBar,
      ),
    );
  }
}

class HostHomeScreen extends StatefulWidget {
  final Widget? webViewWidget;
  final void Function(String text)? onShowSnackBar;

  const HostHomeScreen({
    super.key,
    this.webViewWidget,
    this.onShowSnackBar,
  });

  @override
  State<HostHomeScreen> createState() => _HostHomeScreenState();
}

class _HostHomeScreenState extends State<HostHomeScreen> {
  WebViewController? _controller;
  Stage _selectedStage = Stage.stageA;

  @override
  void initState() {
    super.initState();
    if (widget.webViewWidget == null) {
      final baseUrl = getBaseUrl();
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);

      StageABridge.register(
        _controller!,
        context,
        onShowSnackBar: widget.onShowSnackBar,
      );

      _controller!.loadRequest(Uri.parse('$baseUrl/${_selectedStage.path}'));
    }
  }

  void _onStageSelected(Set<Stage> newSelection) {
    final stage = newSelection.first;
    setState(() {
      _selectedStage = stage;
    });
    if (_controller != null) {
      final baseUrl = getBaseUrl();
      _controller!.loadRequest(Uri.parse('$baseUrl/${stage.path}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host: Flutter WebView Bridge'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: SegmentedButton<Stage>(
              segments: const [
                ButtonSegment(value: Stage.stageA, label: Text('Stage A')),
                ButtonSegment(value: Stage.stageB, label: Text('Stage B')),
                ButtonSegment(value: Stage.stageC, label: Text('Stage C')),
              ],
              selected: {_selectedStage},
              onSelectionChanged: _onStageSelected,
            ),
          ),
        ),
      ),
      body: widget.webViewWidget ?? WebViewWidget(controller: _controller!),
    );
  }
}
