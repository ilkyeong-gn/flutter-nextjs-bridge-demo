'use client';

import React, { useState } from 'react';
import { useFlutterBridge } from '@/lib/bridge/detection';
import { sendSnackBarMessage } from '@/lib/bridge/stageA';
import { useFlutterCounter } from '@/lib/bridge/stageB';

export default function StageBPage() {
  const isConnected = useFlutterBridge();
  const counter = useFlutterCounter(0);
  const [text, setText] = useState('');
  const [lastSentText, setLastSentText] = useState<string | null>(null);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = text.trim();
    if (!trimmed || !isConnected) return;

    const success = sendSnackBarMessage(trimmed);
    if (success) {
      setLastSentText(trimmed);
      setText('');
    }
  };

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-xl p-6 shadow-sm border border-gray-200">
        <div className="mb-6">
          <h2 className="text-xl font-bold text-gray-900 mb-2">Stage B: 양방향 이벤트 (Host → Web)</h2>
          <p className="text-gray-600 text-sm">
            Host(Flutter)에서 발생한 상태 변경 이벤트를 Web이 수신하여 화면에 실시간으로 반영하는 양방향 통신입니다.
            Flutter 상단 AppBar의 카운터 증가(<code className="bg-gray-100 px-1.5 py-0.5 rounded text-xs font-mono text-indigo-700">[+]</code>) 버튼을 누르면
            {' '}<code className="bg-gray-100 px-1.5 py-0.5 rounded text-xs font-mono text-indigo-700">flutter:event</code> CustomEvent를 통해 Web 카운터 숫자가 실시간 갱신됩니다.
          </p>
        </div>

        {!isConnected && (
          <div className="mb-6 p-4 rounded-lg bg-amber-50 border border-amber-200 text-amber-800 text-sm flex items-start gap-2.5">
            <span className="text-lg leading-none" aria-hidden="true">⚠️</span>
            <div>
              <p className="font-medium">Host 외부에서 접속 중 (브릿지 비활성화)</p>
              <p className="text-xs text-amber-700 mt-1">
                Flutter Host의 WebView가 아닌 일반 브라우저에서 실행 중이므로 이벤트 수신 및 메시지 전송 기능이 비활성화됩니다.
              </p>
            </div>
          </div>
        )}

        {/* 카운터 수신 섹션 */}
        <div className="bg-gradient-to-br from-indigo-50/50 to-purple-50/30 rounded-xl p-6 border border-indigo-100">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div>
              <span className="text-xs font-semibold text-indigo-600 uppercase tracking-wider">Host → Web Event</span>
              <h3 className="text-base font-semibold text-gray-900 mt-0.5">실시간 카운터 수신</h3>
              <p className="text-xs text-gray-500 mt-1">
                Host AppBar의 [+] 버튼을 누를 때마다 수신되는 카운트 값입니다.
              </p>
            </div>
            <div className="flex items-baseline gap-2 bg-white px-5 py-3 rounded-lg border border-indigo-100 shadow-sm self-start sm:self-auto">
              <span className="text-xs font-medium text-gray-500">현재 카운트:</span>
              <span
                data-testid="counter-value"
                className="text-4xl font-black text-indigo-600 font-mono tracking-tight"
              >
                {counter}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Stage A 연동 유지: SnackBar 전송 섹션 */}
      <div className="bg-white rounded-xl p-6 shadow-sm border border-gray-200">
        <div className="mb-4">
          <span className="text-xs font-semibold text-emerald-600 uppercase tracking-wider">Web → Host Message</span>
          <h3 className="text-base font-semibold text-gray-900 mt-0.5">Stage A 단방향 메시지 (연동 유지 확인)</h3>
          <p className="text-gray-500 text-xs mt-1">
            Stage B에서도 이전 단계(Stage A)의 SnackBar 전송 기능이 정상 작동함을 검증할 수 있습니다.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="stage-b-message-input" className="block text-sm font-medium text-gray-700 mb-1">
              전송할 텍스트
            </label>
            <div className="flex gap-2">
              <input
                id="stage-b-message-input"
                type="text"
                value={text}
                onChange={(e) => setText(e.target.value)}
                placeholder="Host에 띄울 SnackBar 메시지를 입력하세요"
                disabled={!isConnected}
                className="flex-1 px-3.5 py-2.5 rounded-lg border border-gray-300 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed"
              />
              <button
                type="submit"
                disabled={!isConnected || !text.trim()}
                className="px-5 py-2.5 rounded-lg text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
              >
                전송
              </button>
            </div>
          </div>
        </form>

        {lastSentText && (
          <div className="mt-4 p-3.5 rounded-lg bg-emerald-50 border border-emerald-200 text-emerald-800 text-sm flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="text-emerald-600">✓</span>
              <span>
                Host로 메시지를 전송했습니다: <strong className="font-semibold">&quot;{lastSentText}&quot;</strong>
              </span>
            </div>
            <button
              type="button"
              onClick={() => setLastSentText(null)}
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
