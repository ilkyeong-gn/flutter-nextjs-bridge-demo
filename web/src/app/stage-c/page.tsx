'use client';

import React, { useState } from 'react';
import { useFlutterBridge } from '@/lib/bridge/detection';
import { sendSnackBarMessage } from '@/lib/bridge/stageA';
import { useFlutterCounter } from '@/lib/bridge/stageB';
import { callHost, type DeviceInfoResult } from '@/lib/bridge/stageC';

export default function StageCPage() {
  const isConnected = useFlutterBridge();
  const counter = useFlutterCounter(0);

  // Stage C RPC 상태
  const [isLoading, setIsLoading] = useState(false);
  const [deviceInfo, setDeviceInfo] = useState<DeviceInfoResult | null>(null);
  const [rpcError, setRpcError] = useState<string | null>(null);

  // Stage A SnackBar 상태
  const [snackBarText, setSnackBarText] = useState('');
  const [lastSentSnackBarText, setLastSentSnackBarText] = useState<string | null>(null);

  const handleGetDeviceInfo = async () => {
    if (!isConnected || isLoading) return;

    setIsLoading(true);
    setRpcError(null);
    setDeviceInfo(null);

    try {
      const result = await callHost<DeviceInfoResult>('getDeviceInfo');
      setDeviceInfo(result);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      setRpcError(message);
    } finally {
      setIsLoading(false);
    }
  };

  const handleErrorTest = async () => {
    if (!isConnected || isLoading) return;

    setIsLoading(true);
    setRpcError(null);
    setDeviceInfo(null);

    try {
      await callHost('invalidMethod');
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      setRpcError(message);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSnackBarSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = snackBarText.trim();
    if (!trimmed || !isConnected) return;

    const success = sendSnackBarMessage(trimmed);
    if (success) {
      setLastSentSnackBarText(trimmed);
      setSnackBarText('');
    }
  };

  return (
    <div className="space-y-6">
      {/* Stage C 메인 카드 */}
      <div className="bg-white rounded-xl p-6 shadow-sm border border-gray-200">
        <div className="mb-6">
          <h2 className="text-xl font-bold text-gray-900 mb-2">Stage C: 호출 및 응답 (Web ↔ Host RPC)</h2>
          <p className="text-gray-600 text-sm">
            Web에서 Host로 요청을 보내고 응답을 기다리는 Promise 기반 RPC(<code className="bg-gray-100 px-1.5 py-0.5 rounded text-xs font-mono text-indigo-700">callHost</code>) 메커니즘입니다.
            Host는 기기 정보(플랫폼, OS 버전)를 반환하거나 알 수 없는 호출에 대한 에러를 반환하며, Web은 이를 비동기로 수신하여 화면에 표시합니다.
          </p>
        </div>

        {!isConnected && (
          <div className="mb-6 p-4 rounded-lg bg-amber-50 border border-amber-200 text-amber-800 text-sm flex items-start gap-2.5">
            <span className="text-lg leading-none" aria-hidden="true">⚠️</span>
            <div>
              <p className="font-medium">Host 외부에서 접속 중 (브릿지 비활성화)</p>
              <p className="text-xs text-amber-700 mt-1">
                Flutter Host의 WebView가 아닌 일반 브라우저에서 실행 중이므로 RPC 호출, 이벤트 수신 및 메시지 전송 기능이 비활성화됩니다.
              </p>
            </div>
          </div>
        )}

        {/* RPC 호출 조작 섹션 */}
        <div className="bg-gradient-to-br from-blue-50/50 to-indigo-50/30 rounded-xl p-6 border border-blue-100 mb-6">
          <span className="text-xs font-semibold text-blue-600 uppercase tracking-wider">Web ↔ Host RPC</span>
          <h3 className="text-base font-semibold text-gray-900 mt-0.5">기기 정보 조회 및 에러 처리 테스트</h3>
          <p className="text-xs text-gray-500 mt-1 mb-4">
            아래 버튼을 눌러 Host로 RPC 요청을 보내고 비동기 응답(Promise) 결과를 확인하세요.
          </p>

          <div className="flex flex-wrap gap-3">
            <button
              type="button"
              onClick={handleGetDeviceInfo}
              disabled={!isConnected || isLoading}
              className="px-5 py-2.5 rounded-lg text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors shadow-sm"
            >
              {isLoading ? '요청 처리 중...' : '기기 정보 요청'}
            </button>
            <button
              type="button"
              onClick={handleErrorTest}
              disabled={!isConnected || isLoading}
              className="px-5 py-2.5 rounded-lg text-sm font-medium text-rose-700 bg-rose-50 border border-rose-200 hover:bg-rose-100 focus:outline-none focus:ring-2 focus:ring-rose-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              에러 테스트
            </button>
          </div>

          {/* 성공 결과 카드 */}
          {deviceInfo && (
            <div
              data-testid="device-info-result"
              className="mt-5 p-4 rounded-lg bg-emerald-50 border border-emerald-200 text-emerald-900"
            >
              <div className="flex items-center gap-2 mb-2">
                <span className="text-emerald-600 font-bold">✓</span>
                <span className="font-semibold text-sm text-emerald-800">기기 정보 응답 (성공)</span>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs bg-white/70 p-3 rounded border border-emerald-100">
                <div>
                  <span className="text-gray-500 font-medium">플랫폼: </span>
                  <strong className="text-gray-800 font-mono">{deviceInfo.platform}</strong>
                </div>
                <div>
                  <span className="text-gray-500 font-medium">OS 버전: </span>
                  <strong className="text-gray-800 font-mono">{deviceInfo.version}</strong>
                </div>
              </div>
            </div>
          )}

          {/* 에러 결과 카드 */}
          {rpcError && (
            <div
              data-testid="rpc-error-result"
              className="mt-5 p-4 rounded-lg bg-rose-50 border border-rose-200 text-rose-900"
            >
              <div className="flex items-center gap-2 mb-1">
                <span className="text-rose-600 font-bold">✕</span>
                <span className="font-semibold text-sm text-rose-800">RPC 오류 응답 (실패)</span>
              </div>
              <p className="text-xs text-rose-700 bg-white/70 p-3 rounded border border-rose-100 font-mono">
                {rpcError}
              </p>
            </div>
          )}
        </div>
      </div>

      {/* Stage B 연동 유지: 카운터 수신 섹션 */}
      <div className="bg-white rounded-xl p-6 shadow-sm border border-gray-200">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <span className="text-xs font-semibold text-indigo-600 uppercase tracking-wider">Host → Web Event</span>
            <h3 className="text-base font-semibold text-gray-900 mt-0.5">Stage B 실시간 카운터 수신 (연동 유지 확인)</h3>
            <p className="text-xs text-gray-500 mt-1">
              Stage C에서도 Flutter AppBar의 [+] 버튼을 누를 때마다 카운터가 실시간 갱신됩니다.
            </p>
          </div>
          <div className="flex items-baseline gap-2 bg-indigo-50/50 px-5 py-3 rounded-lg border border-indigo-100 shadow-sm self-start sm:self-auto">
            <span className="text-xs font-medium text-gray-500">현재 카운트:</span>
            <span
              data-testid="counter-value"
              className="text-3xl font-black text-indigo-600 font-mono tracking-tight"
            >
              {counter}
            </span>
          </div>
        </div>
      </div>

      {/* Stage A 연동 유지: SnackBar 전송 섹션 */}
      <div className="bg-white rounded-xl p-6 shadow-sm border border-gray-200">
        <div className="mb-4">
          <span className="text-xs font-semibold text-emerald-600 uppercase tracking-wider">Web → Host Message</span>
          <h3 className="text-base font-semibold text-gray-900 mt-0.5">Stage A 단방향 메시지 (연동 유지 확인)</h3>
          <p className="text-gray-500 text-xs mt-1">
            Stage C에서도 이전 단계(Stage A)의 SnackBar 전송 기능이 정상 작동함을 검증할 수 있습니다.
          </p>
        </div>

        <form onSubmit={handleSnackBarSubmit} className="space-y-4">
          <div>
            <label htmlFor="stage-c-message-input" className="block text-sm font-medium text-gray-700 mb-1">
              전송할 텍스트
            </label>
            <div className="flex gap-2">
              <input
                id="stage-c-message-input"
                type="text"
                value={snackBarText}
                onChange={(e) => setSnackBarText(e.target.value)}
                placeholder="Host에 띄울 SnackBar 메시지를 입력하세요"
                disabled={!isConnected}
                className="flex-1 px-3.5 py-2.5 rounded-lg border border-gray-300 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed"
              />
              <button
                type="submit"
                disabled={!isConnected || !snackBarText.trim()}
                className="px-5 py-2.5 rounded-lg text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
              >
                전송
              </button>
            </div>
          </div>
        </form>

        {lastSentSnackBarText && (
          <div className="mt-4 p-3.5 rounded-lg bg-emerald-50 border border-emerald-200 text-emerald-800 text-sm flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="text-emerald-600">✓</span>
              <span>
                Host로 메시지를 전송했습니다: <strong className="font-semibold">&quot;{lastSentSnackBarText}&quot;</strong>
              </span>
            </div>
            <button
              type="button"
              onClick={() => setLastSentSnackBarText(null)}
              className="text-emerald-600 hover:text-emerald-800 text-xs underline ml-2"
            >
              닫기
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
