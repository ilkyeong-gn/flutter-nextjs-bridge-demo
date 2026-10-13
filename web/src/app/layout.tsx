import type { Metadata } from 'next';
import './globals.css';
import { StageNav } from '@/components/StageNav';
import { HostBadge } from '@/components/HostBadge';

export const metadata: Metadata = {
  title: 'Flutter WebView Bridge Demo',
  description: 'Stage A / B / C Demo Web Application',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko" className="h-full bg-gray-50">
      <body className="min-h-full flex flex-col font-sans text-gray-900">
        <header className="sticky top-0 z-50 bg-white border-b border-gray-200">
          <div className="max-w-4xl mx-auto px-4 py-3 flex items-center justify-between gap-4">
            <div>
              <h1 className="text-base font-bold text-gray-900 leading-tight">
                Web: Bridge Demo
              </h1>
              <p className="text-xs text-gray-500">
                Flutter WebView Hybrid Bridge
              </p>
            </div>
            <HostBadge />
          </div>
          <StageNav />
        </header>
        <main className="flex-1 max-w-4xl w-full mx-auto p-4">
          {children}
        </main>
      </body>
    </html>
  );
}
