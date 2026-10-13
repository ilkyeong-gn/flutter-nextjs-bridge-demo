'use client';

import React from 'react';
import { useFlutterBridge } from '@/lib/bridge/detection';

interface HostBadgeProps {
  isConnected?: boolean;
}

export function HostBadge({ isConnected }: HostBadgeProps) {
  const bridgeAvailable = useFlutterBridge();
  const connected = isConnected !== undefined ? isConnected : bridgeAvailable;

  if (connected) {
    return null;
  }

  return (
    <div className="px-3 py-1.5 text-xs font-medium rounded-md bg-amber-50 text-amber-800 border border-amber-300 flex items-center gap-1.5 shadow-sm">
      <span>⚠️ Host 외부에서 실행 중 (브릿지 비활성화)</span>
    </div>
  );
}
