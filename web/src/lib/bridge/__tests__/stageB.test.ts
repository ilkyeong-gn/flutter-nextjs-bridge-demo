import { describe, it, expect, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import {
  isIncrementCounterEvent,
  useFlutterCounter,
  subscribeFlutterEvent,
  FLUTTER_EVENT_NAME,
} from '../stageB';

describe('stageB: isIncrementCounterEvent', () => {
  it('올바른 incrementCounter payload인 경우 true를 반환한다', () => {
    expect(isIncrementCounterEvent({ type: 'incrementCounter', count: 0 })).toBe(true);
    expect(isIncrementCounterEvent({ type: 'incrementCounter', count: 42 })).toBe(true);
  });

  it('type이 다르거나 count가 없는 경우 false를 반환한다', () => {
    expect(isIncrementCounterEvent({ type: 'otherEvent', count: 1 })).toBe(false);
    expect(isIncrementCounterEvent({ type: 'incrementCounter' })).toBe(false);
    expect(isIncrementCounterEvent({ type: 'incrementCounter', count: '1' })).toBe(false);
  });

  it('null, undefined, 원시값인 경우 false를 반환한다', () => {
    expect(isIncrementCounterEvent(null)).toBe(false);
    expect(isIncrementCounterEvent(undefined)).toBe(false);
    expect(isIncrementCounterEvent('string')).toBe(false);
    expect(isIncrementCounterEvent(123)).toBe(false);
  });
});

describe('stageB: useFlutterCounter', () => {
  it('초기 카운트 값을 설정하고 flutter:event CustomEvent 수신 시 상태를 갱신한다', () => {
    const { result } = renderHook(() => useFlutterCounter(0));
    expect(result.current).toBe(0);

    // 이벤트 발송
    act(() => {
      window.dispatchEvent(
        new CustomEvent(FLUTTER_EVENT_NAME, {
          detail: { type: 'incrementCounter', count: 1 },
        })
      );
    });
    expect(result.current).toBe(1);

    act(() => {
      window.dispatchEvent(
        new CustomEvent(FLUTTER_EVENT_NAME, {
          detail: { type: 'incrementCounter', count: 5 },
        })
      );
    });
    expect(result.current).toBe(5);
  });

  it('일치하지 않는 이벤트 또는 형식에 맞지 않는 detail은 무시한다', () => {
    const { result } = renderHook(() => useFlutterCounter(10));
    expect(result.current).toBe(10);

    act(() => {
      window.dispatchEvent(
        new CustomEvent(FLUTTER_EVENT_NAME, {
          detail: { type: 'unknownType', count: 99 },
        })
      );
    });
    expect(result.current).toBe(10);

    act(() => {
      window.dispatchEvent(
        new CustomEvent('other:event', {
          detail: { type: 'incrementCounter', count: 99 },
        })
      );
    });
    expect(result.current).toBe(10);
  });

  it('언마운트 시 이벤트 리스너가 정상적으로 해제된다', () => {
    const removeEventListenerSpy = vi.spyOn(window, 'removeEventListener');
    const { unmount } = renderHook(() => useFlutterCounter());

    unmount();

    expect(removeEventListenerSpy).toHaveBeenCalledWith(
      FLUTTER_EVENT_NAME,
      expect.any(Function)
    );
    removeEventListenerSpy.mockRestore();
  });
});

describe('stageB: subscribeFlutterEvent', () => {
  it('이벤트 발생 시 핸들러를 호출하고 반환된 해제 함수로 구독을 해제한다', () => {
    const handler = vi.fn();
    const unsubscribe = subscribeFlutterEvent(handler);

    window.dispatchEvent(
      new CustomEvent(FLUTTER_EVENT_NAME, {
        detail: { type: 'incrementCounter', count: 3 },
      })
    );

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler).toHaveBeenCalledWith({ type: 'incrementCounter', count: 3 });

    // 구독 해제
    unsubscribe();

    window.dispatchEvent(
      new CustomEvent(FLUTTER_EVENT_NAME, {
        detail: { type: 'incrementCounter', count: 4 },
      })
    );

    expect(handler).toHaveBeenCalledTimes(1);
  });
});
