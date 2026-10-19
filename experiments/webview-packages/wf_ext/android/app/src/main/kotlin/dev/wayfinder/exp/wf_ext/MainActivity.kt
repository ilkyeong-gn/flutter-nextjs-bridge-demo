package dev.wayfinder.exp.wf_ext

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(OriginBridgePlugin())
        flutterEngine.plugins.add(RendererGuardPlugin(intent?.getStringExtra("scenario")))
    }
}
