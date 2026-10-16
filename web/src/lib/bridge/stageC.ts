import { hasFlutterBridge } from './detection';

export interface DeviceInfoResult {
  platform: string;
  version: string;
}

export interface FlutterCallRequest<P = Record<string, unknown>> {
  id: string;
  method: string;
  params: P;
}

export interface FlutterResponse<T = unknown> {
  id: string;
  result?: T;
  error?: string;
}

interface PendingCall {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
}

declare global {
  interface Window {
    __onFlutterResponse?: (response: unknown) => void;
  }
}

const pendingCalls = new Map<string, PendingCall>();

/**
 * Host에서 window.__onFlutterResponse로 전달된 응답을 처리합니다.
 * 객체 또는 JSON 문자열 형식 모두 지원합니다.
 */
export function handleFlutterResponse(response: unknown): void {
  let parsed: unknown = response;
  if (typeof response === 'string') {
    try {
      parsed = JSON.parse(response);
    } catch {
      return;
    }
  }

  if (!parsed || typeof parsed !== 'object') {
    return;
  }

  const { id, result, error } = parsed as FlutterResponse;
  if (!id || typeof id !== 'string') {
    return;
  }

  const handler = pendingCalls.get(id);
  if (!handler) {
    return;
  }

  pendingCalls.delete(id);

  if (error) {
    handler.reject(new Error(error));
  } else {
    handler.resolve(result);
  }
}

/**
 * window.__onFlutterResponse 콜백 함수를 등록합니다.
 */
export function setupFlutterResponseHandler(win?: Window): void {
  const targetWindow = win ?? (typeof window !== 'undefined' ? window : undefined);
  if (!targetWindow) return;

  targetWindow.__onFlutterResponse = handleFlutterResponse;
}

// 브라우저 환경에서 즉시 전역 핸들러 등록
if (typeof window !== 'undefined') {
  setupFlutterResponseHandler(window);
}

/**
 * Stage C: Web -> Host Promise 기반 RPC 호출 함수
 * window.FlutterBridge.postMessage를 통해 { id, method, params } 요청을 전송하고,
 * Host의 window.__onFlutterResponse 응답을 기다리는 Promise를 반환합니다.
 */
export function callHost<T>(
  method: string,
  params: Record<string, unknown> = {}
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    if (typeof window === 'undefined' || !hasFlutterBridge(window)) {
      reject(new Error('FlutterBridge가 활성화되지 않았습니다.'));
      return;
    }

    // 전역 응답 핸들러가 등록되어 있는지 보장
    setupFlutterResponseHandler(window);

    const id = Math.random().toString(36).substring(2, 9);
    pendingCalls.set(id, {
      resolve: resolve as (value: unknown) => void,
      reject,
    });

    const payload: FlutterCallRequest = {
      id,
      method,
      params,
    };

    window.FlutterBridge!.postMessage(JSON.stringify(payload));
  });
}

/**
 * 테스트용 헬퍼: pendingCalls 초기화
 */
export function clearPendingCalls(): void {
  pendingCalls.clear();
}

/**
 * 테스트용 헬퍼: 현재 대기 중인 pendingCalls 개수 반환
 */
export function getPendingCallsCount(): number {
  return pendingCalls.size;
}
