'use client';

// 출처가 다른 iframe(:3001)을 품은 화면.
// - #iframe-src: 부모 JS가 iframe의 src를 바꾼다.
// - #iframe-click: iframe에 postMessage를 보내 안의 링크를 JS로 누르게 한다.
// iframe 안 링크를 실제로 탭하는 경우는 실측 스크립트가 좌표로 보낸다.
import { useEffect, useRef, useState } from 'react';
import Nav from '../nav';

const big = { display: 'block', margin: 8, padding: 18, background: '#dec', border: 0, fontSize: 16, width: 'calc(100% - 16px)', textAlign: 'left' } as const;

export default function IframePage() {
  const [src, setSrc] = useState<string | null>(null);
  const count = useRef(100);
  useEffect(() => setSrc(`http://${location.hostname}:3001/frame.html?n=1`), []);
  return (
    <div>
      {src && <iframe id="frame" src={src} style={{ width: 'calc(100% - 16px)', height: 140, margin: 8, border: '2px solid #f90' }} />}
      <button
        id="iframe-src"
        style={big}
        onClick={() => {
          count.current += 1;
          setSrc(`http://${location.hostname}:3001/frame.html?n=${count.current}`);
        }}
      >
        부모 JS로 iframe src 바꾸기
      </button>
      <button
        id="iframe-click"
        style={big}
        onClick={() => (document.getElementById('frame') as HTMLIFrameElement).contentWindow?.postMessage('click', '*')}
      >
        iframe 안 링크를 JS로 누르기
      </button>
      <Nav title="/iframe" />
    </div>
  );
}
