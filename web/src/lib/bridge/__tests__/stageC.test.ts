import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
  callHost,
  handleFlutterResponse,
  clearPendingCalls,
  getPendingCallsCount,
  type DeviceInfoResult,
} from '../stageC';

describe('stageC: callHost and response handling', () => {
  const originalFlutterBridge = window.FlutterBridge;

  beforeEach(() => {
    clearPendingCalls();
    delete (window as { FlutterBridge?: unknown }).FlutterBridge;
    delete (window as { __onFlutterResponse?: unknown }).__onFlutterResponse;
  });

  afterEach(() => {
    clearPendingCalls();
    if (originalFlutterBridge) {
      window.FlutterBridge = originalFlutterBridge;
    } else {
      delete (window as { FlutterBridge?: unknown }).FlutterBridge;
    }
    delete (window as { __onFlutterResponse?: unknown }).__onFlutterResponse;
  });

  it('FlutterBridge가 없으면 에러와 함께 reject된다', async () => {
    await expect(callHost('getDeviceInfo')).rejects.toThrow(
      'FlutterBridge가 활성화되지 않았습니다.'
    );
  });

  it('callHost 호출 시 id, method, params를 담아 postMessage를 호출하고 window.__onFlutterResponse를 등록한다', async () => {
    const postMessageMock = vi.fn();
    window.FlutterBridge = { postMessage: postMessageMock };

    const promise = callHost('getDeviceInfo', { foo: 'bar' });

    expect(postMessageMock).toHaveBeenCalledTimes(1);
    const sentRaw = postMessageMock.mock.calls[0][0];
    const sentData = JSON.parse(sentRaw);

    expect(sentData).toHaveProperty('id');
    expect(typeof sentData.id).toBe('string');
    expect(sentData.method).toBe('getDeviceInfo');
    expect(sentData.params).toEqual({ foo: 'bar' });

    expect(typeof window.__onFlutterResponse).toBe('function');
    expect(getPendingCallsCount()).toBe(1);

    // 응답 시뮬레이션
    window.__onFlutterResponse!({
      id: sentData.id,
      result: { platform: 'ios', version: 'Version 18.0' },
    });

    const result = await promise;
    expect(result).toEqual({ platform: 'ios', version: 'Version 18.0' });
    expect(getPendingCallsCount()).toBe(0);
  });

  it('성공 응답 수신 시 Promise가 올바른 결과값으로 resolve된다', async () => {
    const postMessageMock = vi.fn((messageString: string) => {
      const { id } = JSON.parse(messageString);
      // 비동기 응답 시뮬레이션
      setTimeout(() => {
        window.__onFlutterResponse!({
          id,
          result: { platform: 'android', version: 'API 34' } satisfies DeviceInfoResult,
        });
      }, 10);
    });
    window.FlutterBridge = { postMessage: postMessageMock };

    const result = await callHost<DeviceInfoResult>('getDeviceInfo');
    expect(result).toEqual({ platform: 'android', version: 'API 34' });
    expect(getPendingCallsCount()).toBe(0);
  });

  it('에러 응답 수신 시 Promise가 Error 객체로 reject된다', async () => {
    const postMessageMock = vi.fn((messageString: string) => {
      const { id } = JSON.parse(messageString);
      setTimeout(() => {
        window.__onFlutterResponse!({
          id,
          error: 'Unknown method: testInvalid',
        });
      }, 10);
    });
    window.FlutterBridge = { postMessage: postMessageMock };

    await expect(callHost('testInvalid')).rejects.toThrow('Unknown method: testInvalid');
    expect(getPendingCallsCount()).toBe(0);
  });

  it('응답이 JSON 문자열로 전달되어도 정상적으로 파싱하여 처리한다', async () => {
    let capturedId = '';
    window.FlutterBridge = {
      postMessage: (msg: string) => {
        capturedId = JSON.parse(msg).id;
      },
    };

    const promise = callHost('getDeviceInfo');

    handleFlutterResponse(
      JSON.stringify({
        id: capturedId,
        result: { platform: 'macos', version: '15.0' },
      })
    );

    const result = await promise;
    expect(result).toEqual({ platform: 'macos', version: '15.0' });
  });

  it('일치하지 않는 id를 가진 응답은 무시된다', async () => {
    let capturedId = '';
    window.FlutterBridge = {
      postMessage: (msg: string) => {
        capturedId = JSON.parse(msg).id;
      },
    };

    const promise = callHost('getDeviceInfo');
    expect(getPendingCallsCount()).toBe(1);

    // 다른 id로 응답
    handleFlutterResponse({
      id: 'unmatched-id',
      result: { foo: 'bar' },
    });

    expect(getPendingCallsCount()).toBe(1);

    // 올바른 id로 응답
    handleFlutterResponse({
      id: capturedId,
      result: { success: true },
    });

    const result = await promise;
    expect(result).toEqual({ success: true });
    expect(getPendingCallsCount()).toBe(0);
  });

  it('동시에 여러 요청이 발생해도 각각의 id에 맞는 결과로 올바르게 resolve된다', async () => {
    const responses: Array<{ id: string; method: string }> = [];
    window.FlutterBridge = {
      postMessage: (msg: string) => {
        const parsed = JSON.parse(msg);
        responses.push(parsed);
      },
    };

    const promise1 = callHost('method1');
    const promise2 = callHost('method2');

    expect(responses.length).toBe(2);
    expect(responses[0].id).not.toBe(responses[1].id);

    // 역순으로 응답 도착
    window.__onFlutterResponse!({
      id: responses[1].id,
      result: 'res-2',
    });
    window.__onFlutterResponse!({
      id: responses[0].id,
      result: 'res-1',
    });

    const [res1, res2] = await Promise.all([promise1, promise2]);
    expect(res1).toBe('res-1');
    expect(res2).toBe('res-2');
  });
});
