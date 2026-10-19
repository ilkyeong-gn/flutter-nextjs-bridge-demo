// 각 프레임이 자기가 볼 수 있는 Bridge 통로를 확인하고, 통로마다 Message를 보내 본 뒤
// 결과를 로그 수집기(:8090)로 보낸다. iframe은 주 출처(:8080)인 척하는 값을 본문에 넣는다.
(() => {
  const params = new URLSearchParams(location.search);
  const kind = document.body.dataset.role;
  const role = kind + (params.get('label') ? ':' + params.get('label') : '');
  const step = params.get('step') || '1';
  const out = document.getElementById('out');
  document.getElementById('origin').textContent = location.origin;

  function report(event, data = {}) {
    const record = { src: 'web', role, step, origin: location.origin, href: location.href, event, data, t: Date.now() };
    out.textContent += event + ' ' + JSON.stringify(data) + '\n';
    fetch(`http://${location.hostname}:8090/log`, { method: 'POST', body: JSON.stringify(record), mode: 'no-cors', keepalive: true }).catch(() => {});
  }
  window.report = report;

  const claimedOrigin = `http://${location.hostname}:8080`;
  const body = (via) => ({ via, role, step, claimedOrigin, realOrigin: location.origin });
  const handlers = window.webkit && window.webkit.messageHandlers;

  report('probe.seen', {
    Legacy: typeof window.Legacy,                       // webview_flutter JavaScript 채널
    SecureBridge: typeof window.SecureBridge,           // addWebMessageListener (허용 출처 :8080)
    SecureBridgeAll: typeof window.SecureBridgeAll,     // addWebMessageListener (허용 출처 *)
    webkitSecureBridge: !!(handlers && handlers.SecureBridge), // iOS WKScriptMessageHandlerWithReply
    flutter_inappwebview: typeof window.flutter_inappwebview,
    docStartMarker: window.__docStartMarker || null,    // Host가 플랫폼 코드로 넣은 문서 시작 스크립트
  });

  // 1) webview_flutter JavaScript 채널: 문자열 하나만 Host로 간다
  if (window.Legacy && typeof window.Legacy.postMessage === 'function') {
    try { window.Legacy.postMessage(JSON.stringify(body('Legacy'))); report('Legacy.sent'); }
    catch (e) { report('Legacy.error', { e: String(e) }); }
  }

  // 2) WebMessageListener: Android androidx 구현과 flutter_inappwebview 구현이 같은 JS 모양이다
  for (const name of ['SecureBridge', 'SecureBridgeAll']) {
    const port = window[name];
    if (port && typeof port.postMessage === 'function') {
      port.onmessage = (event) => report(name + '.reply', { data: event.data });
      try { port.postMessage(JSON.stringify(body(name))); report(name + '.sent'); }
      catch (e) { report(name + '.error', { e: String(e) }); }
    }
  }

  // 3) iOS WKScriptMessageHandlerWithReply: postMessage가 Promise를 돌려준다
  if (handlers && handlers.SecureBridge) {
    const pending = handlers.SecureBridge.postMessage(body('webkit.SecureBridge'));
    if (pending && typeof pending.then === 'function') {
      pending.then((r) => report('webkit.SecureBridge.reply', { r }), (e) => report('webkit.SecureBridge.error', { e: String(e) }));
    } else {
      report('webkit.SecureBridge.noPromise');
    }
  }

  // 4) flutter_inappwebview callHandler: 6.2 베타는 Host 콜백에 origin·isMainFrame을 준다
  let called = false;
  const callInapp = (trigger) => {
    if (called || !(window.flutter_inappwebview && window.flutter_inappwebview.callHandler)) return;
    called = true;
    window.flutter_inappwebview.callHandler('Legacy', body('callHandler'))
      .then((r) => report('callHandler.reply', { trigger, r }), (e) => report('callHandler.error', { trigger, e: String(e) }));
  };
  window.addEventListener('flutterInAppWebViewPlatformReady', () => callInapp('platformReady'), { once: true });
  setTimeout(() => {
    if (window.flutter_inappwebview !== undefined || window.SecureBridge !== undefined) {
      report('probe.late', { flutter_inappwebview: typeof window.flutter_inappwebview, called });
      callInapp('timeout');
    }
  }, 1500);

  // iframe은 한 번 더 자기 주소를 바꾼다(사용자 동작 없는 JS 탐색). 내비게이션 콜백이 오는지 본다.
  if (kind === 'frame' && step === '1') {
    setTimeout(() => {
      params.set('step', '2');
      location.href = location.pathname + '?' + params.toString();
    }, 1200);
  }
})();
