import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import React from 'react';
import { HostBadge } from '../HostBadge';

describe('HostBadge component seam', () => {
  it('renders warning badge when Host is not connected', () => {
    render(<HostBadge isConnected={false} />);
    expect(screen.getByText('⚠️ Host 외부에서 실행 중 (브릿지 비활성화)')).toBeDefined();
  });

  it('renders nothing when Host is connected', () => {
    const { container } = render(<HostBadge isConnected={true} />);
    expect(screen.queryByText('⚠️ Host 외부에서 실행 중 (브릿지 비활성화)')).toBeNull();
    expect(container.firstChild).toBeNull();
  });
});
