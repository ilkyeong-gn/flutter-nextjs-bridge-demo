import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { sendSnackBarMessage } from '../stageA';

describe('stageA: sendSnackBarMessage', () => {
  const originalFlutterBridge = window.FlutterBridge;

  beforeEach(() => {
    delete (window as { FlutterBridge?: unknown }).FlutterBridge;
  });

  afterEach(() => {
    if (originalFlutterBridge) {
      window.FlutterBridge = originalFlutterBridge;
    } else {
      delete (window as { FlutterBridge?: unknown }).FlutterBridge;
    }
  });

  it('FlutterBridge가 없을 때 false를 반환하고 경고를 출력한다', () => {
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const result = sendSnackBarMessage('테스트 메시지');

    expect(result).toBe(false);
    expect(warnSpy).toHaveBeenCalledWith('FlutterBridge가 활성화되지 않았습니다.');
    warnSpy.mockRestore();
  });

  it('FlutterBridge가 있을 때 올바른 JSON 규격으로 postMessage를 호출하고 true를 반환한다', () => {
    const postMessageMock = vi.fn();
    window.FlutterBridge = {
      postMessage: postMessageMock,
    };

    const result = sendSnackBarMessage('안녕하세요 Flutter!');

    expect(result).toBe(true);
    expect(postMessageMock).toHaveBeenCalledTimes(1);
    expect(postMessageMock).toHaveBeenCalledWith(
      JSON.stringify({
        type: 'showSnackBar',
        text: '안녕하세요 Flutter!',
      })
    );
  });
});
