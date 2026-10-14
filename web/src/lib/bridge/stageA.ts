import { hasFlutterBridge } from './detection';

export interface ShowSnackBarPayload {
  type: 'showSnackBar';
  text: string;
}

/**
 * Stage A: Web -> Host 단방향 메시지 전송 함수
 * window.FlutterBridge.postMessage를 통해 showSnackBar 규격의 JSON 메시지를 전송합니다.
 */
export function sendSnackBarMessage(text: string): boolean {
  if (typeof window === 'undefined' || !hasFlutterBridge(window)) {
    console.warn('FlutterBridge가 활성화되지 않았습니다.');
    return false;
  }

  const payload: ShowSnackBarPayload = {
    type: 'showSnackBar',
    text,
  };

  window.FlutterBridge!.postMessage(JSON.stringify(payload));
  return true;
}
