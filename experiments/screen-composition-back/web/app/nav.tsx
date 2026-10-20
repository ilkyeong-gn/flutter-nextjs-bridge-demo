'use client';

// 모든 화면에 같은 단추를 둔다. 실측 스크립트는 id로 찾아 JS로 누르거나, 좌표를 얻어 실제 탭을 보낸다.
import Link from 'next/link';
import { useRouter } from 'next/navigation';

const big = { display: 'block', margin: 8, padding: 18, background: '#cde', color: '#000', border: 0, fontSize: 16, width: 'calc(100% - 16px)', textAlign: 'left' } as const;

export default function Nav({ title }: { title: string }) {
  const router = useRouter();
  return (
    <div>
      <h2 style={{ margin: 8 }}>{title}</h2>
      <Link id="to-a" href="/a" style={big}>Link → /a</Link>
      <button id="push-b" style={big} onClick={() => router.push('/b')}>router.push('/b')</button>
      <button id="back" style={big} onClick={() => router.back()}>router.back()</button>
      <Link id="to-iframe" href="/iframe" style={big}>Link → /iframe</Link>
    </div>
  );
}
