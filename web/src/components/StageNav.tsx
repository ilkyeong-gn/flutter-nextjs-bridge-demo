'use client';

import React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const STAGES = [
  { id: 'stage-a', href: '/stage-a', label: 'Stage A: 단방향' },
  { id: 'stage-b', href: '/stage-b', label: 'Stage B: 양방향' },
  { id: 'stage-c', href: '/stage-c', label: 'Stage C: 호출' },
];

export function StageNav() {
  const pathname = usePathname();

  return (
    <nav className="w-full bg-white border-b border-gray-200 px-4 py-2">
      <div className="max-w-4xl mx-auto flex items-center justify-between gap-2 overflow-x-auto">
        <div className="flex gap-1 sm:gap-2">
          {STAGES.map((stage) => {
            const isActive = pathname === stage.href;
            return (
              <Link
                key={stage.id}
                href={stage.href}
                aria-current={isActive ? 'page' : undefined}
                className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                  isActive
                    ? 'bg-blue-600 text-white shadow-sm'
                    : 'text-gray-600 hover:text-gray-900 hover:bg-gray-100'
                }`}
              >
                {stage.label}
              </Link>
            );
          })}
        </div>
      </div>
    </nav>
  );
}
