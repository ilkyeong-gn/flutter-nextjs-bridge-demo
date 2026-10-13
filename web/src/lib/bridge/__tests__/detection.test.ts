import { describe, it, expect, afterEach } from 'vitest';
import { hasFlutterBridge, useFlutterBridge, FlutterBridgeInterface } from '../detection';
import { renderHook } from '@testing-library/react';

type WindowWithBridge = Window & { FlutterBridge?: FlutterBridgeInterface };

describe('FlutterBridge detection seam', () => {
  const win = window as WindowWithBridge;
  const originalFlutterBridge = win.FlutterBridge;

  afterEach(() => {
    if (originalFlutterBridge === undefined) {
      delete win.FlutterBridge;
    } else {
      win.FlutterBridge = originalFlutterBridge;
    }
  });

  describe('hasFlutterBridge', () => {
    it('returns false when window is undefined', () => {
      expect(hasFlutterBridge(undefined)).toBe(false);
    });

    it('returns false when window.FlutterBridge is not defined', () => {
      delete win.FlutterBridge;
      expect(hasFlutterBridge(window)).toBe(false);
    });

    it('returns true when window.FlutterBridge is defined', () => {
      win.FlutterBridge = { postMessage: () => {} };
      expect(hasFlutterBridge(window)).toBe(true);
    });
  });

  describe('useFlutterBridge hook', () => {
    it('detects absence of FlutterBridge in browser environment', () => {
      delete win.FlutterBridge;
      const { result } = renderHook(() => useFlutterBridge());
      expect(result.current).toBe(false);
    });

    it('detects presence of FlutterBridge in Host environment', () => {
      win.FlutterBridge = { postMessage: () => {} };
      const { result } = renderHook(() => useFlutterBridge());
      expect(result.current).toBe(true);
    });
  });
});
