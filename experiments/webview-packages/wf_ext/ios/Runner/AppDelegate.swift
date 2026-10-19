import Flutter
import UIKit
import WebKit
import webview_flutter_wkwebview

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OriginBridge") {
      OriginBridge.register(with: registrar)
    }
  }
}

/// webview_flutter가 만든 WKWebView를 External API로 꺼내, 보낸 프레임의 출처를 아는 통로를 붙인다.
/// - SecureBridge: WKScriptMessageHandlerWithReply. 모든 프레임에 보이므로 받을 때 frameInfo로 판정한다.
/// - 문서 시작 스크립트: 메인 프레임에만 window.__docStartMarker를 넣는다.
final class OriginBridge: NSObject, WKScriptMessageHandlerWithReply {
  private static var instance: OriginBridge?
  private let registrar: FlutterPluginRegistrar
  private let channel: FlutterMethodChannel

  static func register(with registrar: FlutterPluginRegistrar) {
    instance = OriginBridge(registrar: registrar)
  }

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "exp/origin_bridge", binaryMessenger: registrar.messenger())
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "features":
      result(["systemVersion": UIDevice.current.systemVersion])
    case "attach":
      guard let args = call.arguments as? [String: Any],
        let identifier = (args["identifier"] as? NSNumber)?.int64Value,
        let webView = FWFWebViewFlutterWKWebViewExternalAPI.webView(
          forIdentifier: identifier, withPluginRegistrar: registrar)
      else {
        result(FlutterError(code: "no_webview", message: nil, details: nil))
        return
      }
      let contentController = webView.configuration.userContentController
      contentController.addScriptMessageHandler(self, contentWorld: .page, name: "SecureBridge")
      contentController.addUserScript(
        WKUserScript(
          source: "window.__docStartMarker = 'ios-userscript@' + location.origin;",
          injectionTime: .atDocumentStart, forMainFrameOnly: true))
      result(["SecureBridge", "docStartScript"])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
    replyHandler: @escaping (Any?, String?) -> Void
  ) {
    let origin = message.frameInfo.securityOrigin
    let port = origin.port > 0 ? ":\(origin.port)" : ""
    let args: [String: Any] = [
      "name": message.name,
      "message": message.body,
      "sourceOrigin": "\(origin.protocol)://\(origin.host)\(port)",
      "isMainFrame": message.frameInfo.isMainFrame,
    ]
    channel.invokeMethod("onSecureMessage", arguments: args) { reply in
      if let error = reply as? FlutterError {
        replyHandler(nil, error.code)
      } else {
        replyHandler(reply, nil)
      }
    }
  }
}
