import type { ReactNode } from 'react';
import Probe from './probe';

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="ko">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </head>
      <body style={{ margin: 0, font: '16px sans-serif' }}>
        <Probe />
        {children}
      </body>
    </html>
  );
}
