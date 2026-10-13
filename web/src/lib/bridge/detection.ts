import { useSyncExternalStore } from 'react';

export interface FlutterBridgeInterface {
  postMessage: (message: string) => void;
}

declare global {
  interface Window {
    FlutterBridge?: FlutterBridgeInterface;
  }
}

export function hasFlutterBridge(win?: Window): boolean {
  if (!win && typeof window === 'undefined') {
    return false;
  }
  const targetWindow = win ?? (typeof window !== 'undefined' ? window : undefined);
  return typeof targetWindow !== 'undefined' && 'FlutterBridge' in targetWindow;
}

function subscribe(callback: () => void) {
  if (typeof window === 'undefined') {
    return () => {};
  }
  // Periodically check in case FlutterBridge is injected slightly after page load
  const timer = setInterval(() => {
    if ('FlutterBridge' in window) {
      callback();
      clearInterval(timer);
    }
  }, 50);

  return () => clearInterval(timer);
}

function getSnapshot(): boolean {
  return hasFlutterBridge(typeof window !== 'undefined' ? window : undefined);
}

function getServerSnapshot(): boolean {
  return false;
}

export function useFlutterBridge(): boolean {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
