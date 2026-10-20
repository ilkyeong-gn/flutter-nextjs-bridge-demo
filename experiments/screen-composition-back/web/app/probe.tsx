'use client';

// 레이아웃에 한 번만 올라가 클라이언트 탐색 동안 계속 산다.
// 관찰한 것을 두 길로 보낸다: Host의 JavaScript 채널(Log)과 수집기(:8090)로 직접 fetch.
// 기록마다 JS 시각(t)과 그때의 visibilityState, 1초 타이머 횟수(tick)를 붙인다.
import { usePathname } from 'next/navigation';
import { useEffect } from 'react';

declare global {
  interface Window {
    Log?: { postMessage(message: string): void };
    __hostMsg?: (n: number, sentAt: number) => void;
    __probe?: boolean;
  }
}

let tick = 0;

export function log(event: string, data?: unknown) {
  const record = {
    src: 'js',
    event,
    data,
    t: Date.now(),
    vis: document.visibilityState,
    path: location.pathname,
    histLen: history.length,
    tick,
  };
  try {
    window.Log?.postMessage(JSON.stringify({ ...record, via: 'channel' }));
  } catch {}
  fetch('http://' + location.hostname + ':8090/log', {
    method: 'POST',
    body: JSON.stringify({ ...record, via: 'fetch' }),
    keepalive: true,
    headers: { 'content-type': 'text/plain' },
  }).catch(() => {});
}

export default function Probe() {
  const pathname = usePathname();

  useEffect(() => {
    if (window.__probe) return;
    window.__probe = true;
    log('probe.start', { href: location.href });
    document.addEventListener('visibilitychange', () => log('visibilitychange'));
    addEventListener('pagehide', (e) => log('pagehide', { persisted: e.persisted }));
    addEventListener('pageshow', (e) => log('pageshow', { persisted: e.persisted }));
    addEventListener('popstate', () => log('popstate', { href: location.href }));
    addEventListener('focus', () => log('focus'));
    addEventListener('blur', () => log('blur'));
    setInterval(() => {
      tick += 1;
      log('tick');
    }, 1000);
    // Host가 runJavaScript로 부른다. 받은 시각과 Host가 보낸 시각을 함께 남긴다.
    window.__hostMsg = (n, sentAt) => log('host.msg', { n, sentAt, delayMs: Date.now() - sentAt });
  }, []);

  useEffect(() => {
    log('route', { pathname });
  }, [pathname]);

  return null;
}
