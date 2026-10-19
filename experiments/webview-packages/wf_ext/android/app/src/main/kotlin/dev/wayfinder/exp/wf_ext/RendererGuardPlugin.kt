package dev.wayfinder.exp.wf_ext

import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Build
import android.os.Message
import android.os.Process
import android.util.Log
import android.view.KeyEvent
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.RenderProcessGoneDetail
import android.webkit.SafeBrowsingResponse
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.annotation.RequiresApi
import androidx.webkit.WebViewClientCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

/**
 * 렌더러 종료 처리 실측(MODE=renderer).
 *
 * webview_flutter_android 4.14.1의 WebViewClient는 onRenderProcessGone을 구현하지 않는다. 기본값(false)이면
 * 렌더러가 죽을 때 Host 앱도 같이 죽는다. Dart가 내비게이션 대리자를 붙인 뒤 install을 부르면, WebView의
 * 현재 WebViewClient(패키지가 만든 것)를 [RendererGuardClient]로 감싼다.
 *
 * scenario는 실행 Intent의 extra(`--es scenario ...`)로 받는다. 같은 APK로 여러 경우를 돌리기 위함이다.
 */
class RendererGuardPlugin(private val scenario: String?) : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        channel = MethodChannel(binding.binaryMessenger, "exp/renderer_guard")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scenario" -> return result.success(scenario)
            "hostPid" -> return result.success(Process.myPid())
        }
        val id = call.argument<Number>("identifier")!!.toLong()
        if (call.argument<Boolean>("gc") == true) {
            // 실측용: 플러그인 InstanceManager가 놓은 WebView가 실제로 수거되는지 보려고 Java GC를 재촉한다.
            Runtime.getRuntime().gc()
            System.runFinalization()
            Runtime.getRuntime().gc()
        }
        val webView = WebViewFlutterAndroidExternalApi.getWebView(binding, id)
        when (call.method) {
            "install" -> result.success(if (webView == null) mapOf("installed" to false, "reason" to "no_webview") else install(id, webView))
            "inspect" -> result.success(inspect(webView, call.argument<Boolean>("deep") == true))
            "disableMultipleWindows" -> {
                // window.open이 패키지의 임시 WebView(감쌀 수 없음)를 만들지 않게 한다.
                webView?.settings?.setSupportMultipleWindows(false)
                result.success(webView != null)
            }
            "destroy" -> {
                webView?.destroy()
                result.success(webView != null)
            }
            else -> result.notImplemented()
        }
    }

    private fun install(id: Long, webView: WebView): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return mapOf("installed" to false, "reason" to "API < 26")
        val inner = webView.webViewClient
        if (inner is RendererGuardClient) return mapOf("installed" to false, "reason" to "already")
        webView.webViewClient = RendererGuardClient(inner) { _, detail -> onGone(id, detail) }
        return mapOf(
            "installed" to true,
            "innerClass" to inner.javaClass.name,
            "innerSuperclass" to inner.javaClass.superclass?.name,
            "innerIsWebViewClientCompat" to (inner is WebViewClientCompat),
        )
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun onGone(id: Long, detail: RenderProcessGoneDetail): Boolean {
        val args = mapOf(
            "identifier" to id,
            "didCrash" to detail.didCrash(),
            "rendererPriorityAtExit" to detail.rendererPriorityAtExit(),
            "hostPid" to Process.myPid(),
        )
        Log.w("RendererGuard", "onRenderProcessGone $args")
        channel.invokeMethod("onRenderProcessGone", args)
        return true // 처리했다고 알린다. 이 WebView는 다시 쓰지 않고 Dart가 버린다.
    }

    private fun inspect(webView: WebView?, deep: Boolean): Map<String, Any?> {
        if (webView == null) return mapOf("found" to false)
        val info = mutableMapOf<String, Any?>(
            "found" to true,
            "attachedToWindow" to webView.isAttachedToWindow,
            "client" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) webView.webViewClient.javaClass.name else null,
        )
        if (deep && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // 살아 있는 WebView에만 쓴다. 같은 렌더러 프로세스면 같은 객체가 돌아온다.
            info["renderProcess"] = webView.webViewRenderProcess?.let { System.identityHashCode(it) }
            info["rendererRequestedPriority"] = webView.rendererRequestedPriority
        }
        return info
    }
}

/**
 * 패키지의 WebViewClient에 모든 콜백을 그대로 넘기고 onRenderProcessGone만 직접 처리한다.
 * 패키지 클라이언트는 android.webkit.WebViewClient를 바로 상속하므로(WebViewClientCompat 아님) 같은 타입으로 감싼다.
 * 매개변수를 모두 nullable로 두어 Kotlin이 넣는 null 검사로 새 예외가 생기지 않게 한다.
 */
@RequiresApi(Build.VERSION_CODES.O)
class RendererGuardClient(
    private val inner: WebViewClient,
    private val onGone: (WebView?, RenderProcessGoneDetail) -> Boolean,
) : WebViewClient() {
    override fun onRenderProcessGone(view: WebView?, detail: RenderProcessGoneDetail): Boolean = onGone(view, detail)

    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?) = inner.shouldOverrideUrlLoading(view, request)

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun shouldOverrideUrlLoading(view: WebView?, url: String?) = inner.shouldOverrideUrlLoading(view, url)

    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) = inner.onPageStarted(view, url, favicon)

    override fun onPageFinished(view: WebView?, url: String?) = inner.onPageFinished(view, url)

    override fun onLoadResource(view: WebView?, url: String?) = inner.onLoadResource(view, url)

    override fun onPageCommitVisible(view: WebView?, url: String?) = inner.onPageCommitVisible(view, url)

    override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? =
        inner.shouldInterceptRequest(view, request)

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun shouldInterceptRequest(view: WebView?, url: String?): WebResourceResponse? = inner.shouldInterceptRequest(view, url)

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onTooManyRedirects(view: WebView?, cancelMsg: Message?, continueMsg: Message?) =
        inner.onTooManyRedirects(view, cancelMsg, continueMsg)

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onReceivedError(view: WebView?, errorCode: Int, description: String?, failingUrl: String?) =
        inner.onReceivedError(view, errorCode, description, failingUrl)

    override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) =
        inner.onReceivedError(view, request, error)

    override fun onReceivedHttpError(view: WebView?, request: WebResourceRequest?, errorResponse: WebResourceResponse?) =
        inner.onReceivedHttpError(view, request, errorResponse)

    override fun onFormResubmission(view: WebView?, dontResend: Message?, resend: Message?) =
        inner.onFormResubmission(view, dontResend, resend)

    override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) = inner.doUpdateVisitedHistory(view, url, isReload)

    override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) = inner.onReceivedSslError(view, handler, error)

    override fun onReceivedClientCertRequest(view: WebView?, request: ClientCertRequest?) = inner.onReceivedClientCertRequest(view, request)

    override fun onReceivedHttpAuthRequest(view: WebView?, handler: HttpAuthHandler?, host: String?, realm: String?) =
        inner.onReceivedHttpAuthRequest(view, handler, host, realm)

    override fun shouldOverrideKeyEvent(view: WebView?, event: KeyEvent?) = inner.shouldOverrideKeyEvent(view, event)

    override fun onUnhandledKeyEvent(view: WebView?, event: KeyEvent?) = inner.onUnhandledKeyEvent(view, event)

    override fun onScaleChanged(view: WebView?, oldScale: Float, newScale: Float) = inner.onScaleChanged(view, oldScale, newScale)

    override fun onReceivedLoginRequest(view: WebView?, realm: String?, account: String?, args: String?) =
        inner.onReceivedLoginRequest(view, realm, account, args)

    @RequiresApi(Build.VERSION_CODES.O_MR1)
    override fun onSafeBrowsingHit(view: WebView?, request: WebResourceRequest?, threatType: Int, callback: SafeBrowsingResponse?) =
        inner.onSafeBrowsingHit(view, request, threatType, callback)
}
