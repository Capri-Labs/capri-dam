import React from 'react';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key, opts) => opts?.defaultValue || key,
  }),
}));

jest.mock('../../../app/javascript/components/MenuConfig', () => ({
  MENU_GROUPS: [
    {
      id: 'main',
      title: 'Main',
      items: [
        {
          id: 'Assets',
          label: 'Assets',
          children: [
            { id: 'Collections', label: 'Collections', url: '/collections' },
          ],
        },
        { id: 'Standalone', label: 'Standalone', url: '/standalone' },
        { id: 'Internal', label: 'Internal' },
      ],
    },
  ],
}));

import Sidebar from '../../../app/javascript/components/Sidebar';

describe('Sidebar', () => {
  let originalLocation;

  beforeEach(() => {
    localStorage.clear();
    sessionStorage.clear();
    window.history.replaceState({}, '', '/');
    originalLocation = window.location;
    delete window.location;
    window.location = { href: 'http://localhost/', pathname: '/' };
  });

  afterEach(() => {
    window.location = originalLocation;
  });

  it('expands the parent menu when an active child is selected', () => {
    render(<Sidebar activeView="Collections" onNavigate={jest.fn()} />);

    expect(screen.getByText('Collections')).toBeInTheDocument();
  });

  it('persists collapsed state and reopens when a parent menu is clicked', async () => {
    localStorage.setItem('dam_sidebar_open', 'false');
    render(<Sidebar activeView="Standalone" onNavigate={jest.fn()} />);

    const buttons = screen.getAllByRole('button');
    await userEvent.click(buttons[1]);

    expect(screen.getByText('Collections')).toBeInTheDocument();
  });

  it('toggles sidebar state into localStorage', async () => {
    render(<Sidebar activeView="Standalone" onNavigate={jest.fn()} />);

    await userEvent.click(screen.getAllByRole('button')[0]);
    expect(localStorage.getItem('dam_sidebar_open')).toBe('false');

    await userEvent.click(screen.getAllByRole('button')[0]);
    expect(localStorage.getItem('dam_sidebar_open')).toBe('true');
  });

  it('navigates to URLs and falls back to onNavigate for internal items', async () => {
    const onNavigate = jest.fn();
    render(<Sidebar activeView="Standalone" onNavigate={onNavigate} />);

    await userEvent.click(screen.getByText('Standalone'));
    expect(window.location.href).toBe('/standalone');

    await userEvent.click(screen.getByText('Internal'));
    expect(onNavigate).toHaveBeenCalledWith('Internal');
  });

  it('restores the saved nav scroll position after a re-mount (full page navigation)', () => {
    sessionStorage.setItem('dam_sidebar_scroll_top', '250');
    render(<Sidebar activeView="Standalone" onNavigate={jest.fn()} />);

    const scrollable = screen.getByTestId('sidebar-nav-scroll');
    expect(scrollable.scrollTop).toBe(250);
  });

  it('persists the nav scroll position to sessionStorage on scroll', () => {
    render(<Sidebar activeView="Standalone" onNavigate={jest.fn()} />);
    const scrollable = screen.getByTestId('sidebar-nav-scroll');

    Object.defineProperty(scrollable, 'scrollTop', { value: 120, writable: true });
    scrollable.dispatchEvent(new Event('scroll', { bubbles: false }));

    expect(sessionStorage.getItem('dam_sidebar_scroll_top')).toBe('120');
  });
});
