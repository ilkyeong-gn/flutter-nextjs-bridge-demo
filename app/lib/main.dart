import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:app/config.dart';
import 'package:app/bridge/stage_b_bridge.dart';

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
  final Stage initialStage;
  final WebViewController? controller;
  final void Function(int counter)? onCounterIncremented;

  const HostApp({
    super.key,
    this.webViewWidget,
    this.onShowSnackBar,
    this.initialStage = Stage.stageA,
    this.controller,
    this.onCounterIncremented,
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
        initialStage: initialStage,
        controller: controller,
        onCounterIncremented: onCounterIncremented,
      ),
    );
  }
}

class HostHomeScreen extends StatefulWidget {
  final Widget? webViewWidget;
  final void Function(String text)? onShowSnackBar;
  final Stage initialStage;
  final WebViewController? controller;
  final void Function(int counter)? onCounterIncremented;

  const HostHomeScreen({
    super.key,
    this.webViewWidget,
    this.onShowSnackBar,
    this.initialStage = Stage.stageA,
    this.controller,
    this.onCounterIncremented,
  });

  @override
  State<HostHomeScreen> createState() => _HostHomeScreenState();
}

class _HostHomeScreenState extends State<HostHomeScreen> {
  WebViewController? _controller;
  late Stage _selectedStage;
  int _counter = 0;

  @override
  void initState() {
    super.initState();
    _selectedStage = widget.initialStage;
    _controller = widget.controller;

    if (widget.webViewWidget == null && _controller == null) {
      final baseUrl = getBaseUrl();
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);

      StageBBridge.register(
        _controller!,
        context,
        onShowSnackBar: widget.onShowSnackBar,
      );

      _controller!.loadRequest(Uri.parse('$baseUrl/${_selectedStage.path}'));
    } else if (_controller != null) {
      StageBBridge.register(
        _controller!,
        context,
        onShowSnackBar: widget.onShowSnackBar,
      );
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

  void _onIncrementCounter() {
    setState(() {
      _counter++;
    });
    if (_controller != null) {
      StageBBridge.sendIncrementCounter(_controller!, _counter);
    }
    widget.onCounterIncremented?.call(_counter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host: Flutter WebView Bridge'),
        actions: [
          if (_selectedStage == Stage.stageB || _selectedStage == Stage.stageC)
            IconButton(
              key: const Key('counter_increment_button'),
              icon: Badge.count(
                count: _counter,
                child: const Icon(Icons.add),
              ),
              tooltip: '카운터 증가 (현재: $_counter)',
              onPressed: _onIncrementCounter,
            ),
        ],
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
