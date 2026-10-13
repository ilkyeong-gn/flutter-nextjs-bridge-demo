import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import React from 'react';
import { StageNav } from '../StageNav';

vi.mock('next/navigation', () => ({
  usePathname: () => '/stage-a',
}));

describe('StageNav component seam', () => {
  it('renders all three stage links', () => {
    render(<StageNav />);
    const stageALink = screen.getByRole('link', { name: /stage a/i });
    const stageBLink = screen.getByRole('link', { name: /stage b/i });
    const stageCLink = screen.getByRole('link', { name: /stage c/i });

    expect(stageALink.getAttribute('href')).toBe('/stage-a');
    expect(stageBLink.getAttribute('href')).toBe('/stage-b');
    expect(stageCLink.getAttribute('href')).toBe('/stage-c');
  });

  it('marks current stage as active', () => {
    render(<StageNav />);
    const stageALink = screen.getByRole('link', { name: /stage a/i });
    expect(stageALink.getAttribute('aria-current')).toBe('page');
  });
});
