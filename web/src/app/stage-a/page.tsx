'use client';

import React, { useState } from 'react';
import { useFlutterBridge } from '@/lib/bridge/detection';
import { sendSnackBarMessage } from '@/lib/bridge/stageA';

export default function StageAPage() {
  const isConnected = useFlutterBridge();
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
    <div className="bg-white rounded-xl p-6 shadow-sm border border-gray-200">
      <div className="mb-6">
        <h2 className="text-xl font-bold text-gray-900 mb-2">Stage A: 단방향 메시지 (Web → Host)</h2>
        <p className="text-gray-600 text-sm">
          Web에서 텍스트를 입력하고 전송하면, JavaScript 채널(<code className="bg-gray-100 px-1.5 py-0.5 rounded text-xs font-mono text-indigo-700">FlutterBridge</code>)을 통해
          Host(Flutter)로 메시지를 전달하여 Flutter 화면 하단에 SnackBar를 띄웁니다.
        </p>
      </div>

      {!isConnected && (
        <div className="mb-6 p-4 rounded-lg bg-amber-50 border border-amber-200 text-amber-800 text-sm flex items-start gap-2.5">
          <span className="text-lg leading-none" aria-hidden="true">⚠️</span>
          <div>
            <p className="font-medium">Host 외부에서 접속 중 (브릿지 비활성화)</p>
            <p className="text-xs text-amber-700 mt-1">
              Flutter Host의 WebView가 아닌 일반 브라우저에서 실행 중이므로 메시지 전송 기능이 비활성화됩니다.
            </p>
          </div>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label htmlFor="message-input" className="block text-sm font-medium text-gray-700 mb-1">
            전송할 텍스트
          </label>
          <div className="flex gap-2">
            <input
              id="message-input"
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
        <div className="mt-6 p-3.5 rounded-lg bg-emerald-50 border border-emerald-200 text-emerald-800 text-sm flex items-center justify-between">
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
  );
}
