package dev.wayfinder.exp.wf_ext

import android.content.Context
import android.os.Build
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import org.json.JSONObject

/**
 * webview_flutter가 만든 WebView를 External API로 꺼내, 출처를 아는 통로를 붙인다.
 * - SecureBridge: 허용 출처에만 주입되는 addWebMessageListener
 * - SecureBridgeAll: 모든 출처에 주입(iframe의 실제 출처가 어떻게 보고되는지 보기 위함)
 * - 문서 시작 스크립트: 허용 출처에만 window.__docStartMarker를 넣는다
 */
class OriginBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        channel = MethodChannel(binding.binaryMessenger, "exp/origin_bridge")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "features" -> result.success(features(binding.applicationContext))
            "attach" -> attach(call, result)
            else -> result.notImplemented()
        }
    }

    private fun features(context: Context): Map<String, Any?> {
        val webViewPackage = WebViewCompat.getCurrentWebViewPackage(context)
        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "webViewPackage" to webViewPackage?.packageName,
            "webViewVersion" to webViewPackage?.versionName,
            "WEB_MESSAGE_LISTENER" to WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER),
            "DOCUMENT_START_SCRIPT" to WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT),
            "GET_COOKIE_INFO" to WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO),
        )
    }

    private fun attach(call: MethodCall, result: MethodChannel.Result) {
        val identifier = call.argument<Number>("identifier")!!.toLong()
        val allowedOrigins = call.argument<List<String>>("allowedOrigins")!!.toSet()
        val webView = WebViewFlutterAndroidExternalApi.getWebView(binding, identifier)
            ?: return result.error("no_webview", "identifier $identifier", null)

        val added = mutableListOf<String>()
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(webView, "SecureBridge", allowedOrigins, listener("SecureBridge"))
            WebViewCompat.addWebMessageListener(webView, "SecureBridgeAll", setOf("*"), listener("SecureBridgeAll"))
            added += listOf("SecureBridge", "SecureBridgeAll")
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(
                webView,
                "window.__docStartMarker = 'android-docstart@' + location.origin;",
                allowedOrigins,
            )
            added += "docStartScript"
        }
        result.success(added)
    }

    private fun listener(name: String) =
        WebViewCompat.WebMessageListener { _, message, sourceOrigin, isMainFrame, replyProxy ->
            val args = mapOf(
                "name" to name,
                "message" to message.data,
                "sourceOrigin" to sourceOrigin.toString(),
                "isMainFrame" to isMainFrame,
            )
            channel.invokeMethod("onSecureMessage", args, object : MethodChannel.Result {
                override fun success(reply: Any?) {
                    replyProxy.postMessage(JSONObject(reply as Map<*, *>).toString())
                }

                override fun error(code: String, message: String?, details: Any?) {
                    replyProxy.postMessage("""{"error":"$code"}""")
                }

                override fun notImplemented() {
                    replyProxy.postMessage("""{"error":"notImplemented"}""")
                }
            })
        }
}
