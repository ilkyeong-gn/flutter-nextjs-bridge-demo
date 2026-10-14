import { render, screen, fireEvent } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import React from 'react';
import StageAPage from '../page';

describe('StageAPage', () => {
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

  it('Host 외부(FlutterBridge 부재) 환경에서는 비활성화 안내가 표시되고 버튼이 비활성화된다', () => {
    render(<StageAPage />);

    expect(screen.getByText('Host 외부에서 접속 중 (브릿지 비활성화)')).toBeDefined();

    const input = screen.getByLabelText('전송할 텍스트') as HTMLInputElement;
    expect(input.disabled).toBe(true);

    const button = screen.getByRole('button', { name: '전송' }) as HTMLButtonElement;
    expect(button.disabled).toBe(true);
  });

  it('Host 내부(FlutterBridge 존재) 환경에서는 입력을 입력하고 전송할 수 있다', () => {
    const postMessageMock = vi.fn();
    window.FlutterBridge = {
      postMessage: postMessageMock,
    };

    render(<StageAPage />);

    expect(screen.queryByText('Host 외부에서 접속 중 (브릿지 비활성화)')).toBeNull();

    const input = screen.getByLabelText('전송할 텍스트') as HTMLInputElement;
    expect(input.disabled).toBe(false);

    const button = screen.getByRole('button', { name: '전송' }) as HTMLButtonElement;
    // 빈 텍스트일 때는 비활성화
    expect(button.disabled).toBe(true);

    // 텍스트 입력
    fireEvent.change(input, { target: { value: 'Flutter에 보낼 인사' } });
    expect(button.disabled).toBe(false);

    // 전송 클릭
    fireEvent.click(button);

    expect(postMessageMock).toHaveBeenCalledTimes(1);
    expect(postMessageMock).toHaveBeenCalledWith(
      JSON.stringify({
        type: 'showSnackBar',
        text: 'Flutter에 보낼 인사',
      })
    );

    // 입력창이 비워지고 완료 메시지 노출 확인
    expect(input.value).toBe('');
    expect(screen.getByText(/Host로 메시지를 전송했습니다/)).toBeDefined();
  });
});
