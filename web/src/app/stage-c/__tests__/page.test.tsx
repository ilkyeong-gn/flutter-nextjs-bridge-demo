import { render, screen, fireEvent, act, waitFor } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import React from 'react';
import StageCPage from '../page';
import { FLUTTER_EVENT_NAME } from '@/lib/bridge/stageB';
import { clearPendingCalls } from '@/lib/bridge/stageC';

describe('StageCPage', () => {
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

  it('Host 외부(FlutterBridge 부재) 환경에서는 비활성화 안내가 표시되고 모든 조작 버튼이 비활성화된다', () => {
    render(<StageCPage />);

    expect(screen.getByText('Host 외부에서 접속 중 (브릿지 비활성화)')).toBeDefined();

    const getDeviceBtn = screen.getByRole('button', { name: '기기 정보 요청' }) as HTMLButtonElement;
    expect(getDeviceBtn.disabled).toBe(true);

    const errorTestBtn = screen.getByRole('button', { name: '에러 테스트' }) as HTMLButtonElement;
    expect(errorTestBtn.disabled).toBe(true);

    const snackBarInput = screen.getByLabelText('전송할 텍스트') as HTMLInputElement;
    expect(snackBarInput.disabled).toBe(true);

    const snackBarBtn = screen.getByRole('button', { name: '전송' }) as HTMLButtonElement;
    expect(snackBarBtn.disabled).toBe(true);
  });

  it('기기 정보 요청 버튼 클릭 시 Host로 getDeviceInfo 호출을 보내고 응답을 화면에 렌더링한다', async () => {
    let capturedId = '';
    window.FlutterBridge = {
      postMessage: vi.fn((rawMsg: string) => {
        const parsed = JSON.parse(rawMsg);
        if (parsed.method === 'getDeviceInfo') {
          capturedId = parsed.id;
          setTimeout(() => {
            window.__onFlutterResponse!({
              id: capturedId,
              result: {
                platform: 'ios',
                version: 'Version 18.0 (Build 22A3354)',
              },
            });
          }, 0);
        }
      }),
    };

    render(<StageCPage />);

    expect(screen.queryByText('Host 외부에서 접속 중 (브릿지 비활성화)')).toBeNull();

    const getDeviceBtn = screen.getByRole('button', { name: '기기 정보 요청' });
    fireEvent.click(getDeviceBtn);

    await waitFor(() => {
      expect(screen.getByTestId('device-info-result')).toBeDefined();
    });

    expect(screen.getByText(/ios/)).toBeDefined();
    expect(screen.getByText(/Version 18.0/)).toBeDefined();
  });

  it('에러 테스트 버튼 클릭 시 잘못된 method를 호출하고 반환된 에러 메시지를 화면에 렌더링한다', async () => {
    let capturedId = '';
    window.FlutterBridge = {
      postMessage: vi.fn((rawMsg: string) => {
        const parsed = JSON.parse(rawMsg);
        if (parsed.method === 'invalidMethod') {
          capturedId = parsed.id;
          setTimeout(() => {
            window.__onFlutterResponse!({
              id: capturedId,
              error: 'Unknown method: invalidMethod',
            });
          }, 0);
        }
      }),
    };

    render(<StageCPage />);

    const errorTestBtn = screen.getByRole('button', { name: '에러 테스트' });
    fireEvent.click(errorTestBtn);

    await waitFor(() => {
      expect(screen.getByTestId('rpc-error-result')).toBeDefined();
    });

    expect(screen.getByText(/Unknown method: invalidMethod/)).toBeDefined();
  });

  it('Stage C 화면에서도 Stage B 카운터 이벤트 수신이 정상 작동한다', () => {
    window.FlutterBridge = {
      postMessage: vi.fn(),
    };

    render(<StageCPage />);

    const counterDisplay = screen.getByTestId('counter-value');
    expect(counterDisplay.textContent).toBe('0');

    act(() => {
      window.dispatchEvent(
        new CustomEvent(FLUTTER_EVENT_NAME, {
          detail: { type: 'incrementCounter', count: 7 },
        })
      );
    });

    expect(counterDisplay.textContent).toBe('7');
  });

  it('Stage C 화면에서도 Stage A SnackBar 메시지 전송이 정상 작동한다', () => {
    const postMessageMock = vi.fn();
    window.FlutterBridge = {
      postMessage: postMessageMock,
    };

    render(<StageCPage />);

    const input = screen.getByLabelText('전송할 텍스트') as HTMLInputElement;
    const button = screen.getByRole('button', { name: '전송' }) as HTMLButtonElement;

    fireEvent.change(input, { target: { value: 'Stage C에서 보낸 SnackBar' } });
    expect(button.disabled).toBe(false);

    fireEvent.click(button);

    expect(postMessageMock).toHaveBeenCalledWith(
      JSON.stringify({
        type: 'showSnackBar',
        text: 'Stage C에서 보낸 SnackBar',
      })
    );

    expect(input.value).toBe('');
    expect(screen.getByText(/Host로 메시지를 전송했습니다/)).toBeDefined();
  });
});
