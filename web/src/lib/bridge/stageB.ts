import { useState, useEffect } from 'react';

export const FLUTTER_EVENT_NAME = 'flutter:event';

export interface IncrementCounterPayload {
  type: 'incrementCounter';
  count: number;
}

export type FlutterEventPayload = IncrementCounterPayload;

/**
 * flutter:event CustomEvent detail 타입 가드
 */
export function isIncrementCounterEvent(
  payload: unknown
): payload is IncrementCounterPayload {
  if (typeof payload !== 'object' || payload === null) {
    return false;
  }
  const candidate = payload as Record<string, unknown>;
  return candidate.type === 'incrementCounter' && typeof candidate.count === 'number';
}

/**
 * Stage B: Host로부터의 flutter:event CustomEvent를 수신하여 카운트 상태를 관리하는 React Hook
 */
export function useFlutterCounter(initialCount: number = 0): number {
  const [count, setCount] = useState<number>(initialCount);

  useEffect(() => {
    if (typeof window === 'undefined') return;

    const handleEvent = (event: Event) => {
      const customEvent = event as CustomEvent<unknown>;
      if (isIncrementCounterEvent(customEvent.detail)) {
        setCount(customEvent.detail.count);
      }
    };

    window.addEventListener(FLUTTER_EVENT_NAME, handleEvent);
    return () => {
      window.removeEventListener(FLUTTER_EVENT_NAME, handleEvent);
    };
  }, []);

  return count;
}

/**
 * flutter:event 이벤트 리스너를 직접 등록하고 구독 해제 함수를 반환하는 헬퍼 함수
 */
export function subscribeFlutterEvent(
  handler: (payload: FlutterEventPayload) => void
): () => void {
  if (typeof window === 'undefined') {
    return () => {};
  }

  const listener = (event: Event) => {
    const customEvent = event as CustomEvent<unknown>;
    if (isIncrementCounterEvent(customEvent.detail)) {
      handler(customEvent.detail);
    }
  };

  window.addEventListener(FLUTTER_EVENT_NAME, listener);
  return () => {
    window.removeEventListener(FLUTTER_EVENT_NAME, listener);
  };
}
