import { render, screen, fireEvent, act } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import React from 'react';
import StageBPage from '../page';
import { FLUTTER_EVENT_NAME } from '@/lib/bridge/stageB';

describe('StageBPage', () => {
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

  it('Host 외부(FlutterBridge 부재) 환경에서는 비활성화 안내가 표시되고 SnackBar 폼이 비활성화된다', () => {
    render(<StageBPage />);

    expect(screen.getByText('Host 외부에서 접속 중 (브릿지 비활성화)')).toBeDefined();

    const input = screen.getByLabelText('전송할 텍스트') as HTMLInputElement;
    expect(input.disabled).toBe(true);

    const button = screen.getByRole('button', { name: '전송' }) as HTMLButtonElement;
    expect(button.disabled).toBe(true);

    // 기본 카운트 값 0 확인
    const counterDisplay = screen.getByTestId('counter-value');
    expect(counterDisplay.textContent).toBe('0');
  });

  it('Host 내부(FlutterBridge 존재) 환경에서 flutter:event 수신 시 카운터 숫자가 실시간 갱신된다', () => {
    window.FlutterBridge = {
      postMessage: vi.fn(),
    };

    render(<StageBPage />);

    expect(screen.queryByText('Host 외부에서 접속 중 (브릿지 비활성화)')).toBeNull();

    const counterDisplay = screen.getByTestId('counter-value');
    expect(counterDisplay.textContent).toBe('0');

    // flutter:event 1 수신
    act(() => {
      window.dispatchEvent(
        new CustomEvent(FLUTTER_EVENT_NAME, {
          detail: { type: 'incrementCounter', count: 1 },
        })
      );
    });
    expect(counterDisplay.textContent).toBe('1');

    // flutter:event 2 수신
    act(() => {
      window.dispatchEvent(
        new CustomEvent(FLUTTER_EVENT_NAME, {
          detail: { type: 'incrementCounter', count: 2 },
        })
      );
    });
    expect(counterDisplay.textContent).toBe('2');
  });

  it('Stage B 화면에서도 Stage A SnackBar 메시지 전송이 정상 작동한다', () => {
    const postMessageMock = vi.fn();
    window.FlutterBridge = {
      postMessage: postMessageMock,
    };

    render(<StageBPage />);

    const input = screen.getByLabelText('전송할 텍스트') as HTMLInputElement;
    expect(input.disabled).toBe(false);

    const button = screen.getByRole('button', { name: '전송' }) as HTMLButtonElement;
    expect(button.disabled).toBe(true);

    // 텍스트 입력 및 전송
    fireEvent.change(input, { target: { value: 'Stage B에서 보낸 SnackBar' } });
    expect(button.disabled).toBe(false);

    fireEvent.click(button);

    expect(postMessageMock).toHaveBeenCalledTimes(1);
    expect(postMessageMock).toHaveBeenCalledWith(
      JSON.stringify({
        type: 'showSnackBar',
        text: 'Stage B에서 보낸 SnackBar',
      })
    );

    expect(input.value).toBe('');
    expect(screen.getByText(/Host로 메시지를 전송했습니다/)).toBeDefined();
  });
});
