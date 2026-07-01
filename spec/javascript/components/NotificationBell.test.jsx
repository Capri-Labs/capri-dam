import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import NotificationBell from '../../../app/javascript/components/NotificationBell';

describe('NotificationBell', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === '[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
    delete window.location;
    window.location = { href: '/' };
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('renders the bell icon and notification badge count', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => [
        { id: 1, title: 'Task assigned', message: 'Review hero asset', action_url: '/tasks/1' },
        { id: 2, title: 'Approval needed', message: 'Approve campaign', action_url: '/tasks/2' },
      ],
    });

    render(<NotificationBell />);

    expect(await screen.findByText('2')).toBeInTheDocument();
  });

  it('opens the notification list on click', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => [{ id: 1, title: 'Task assigned', message: 'Review hero asset', action_url: '/tasks/1' }],
    });

    render(<NotificationBell />);
    await screen.findByText('1');

    fireEvent.click(screen.getAllByRole('button')[0]);

    expect(await screen.findByText('Notifications')).toBeInTheDocument();
    expect(screen.getByText('Task assigned')).toBeInTheDocument();
    expect(screen.getByText('Review hero asset')).toBeInTheDocument();
  });

  it('marks all notifications read', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => [{ id: 1, title: 'Task assigned', message: 'Review hero asset', action_url: '/tasks/1' }],
      })
      .mockResolvedValueOnce({ ok: true, json: async () => ({}) });

    render(<NotificationBell />);
    await screen.findByText('1');
    fireEvent.click(screen.getAllByRole('button')[0]);
    fireEvent.click(await screen.findByRole('button', { name: 'Mark all read' }));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/api/v1/notifications/mark_all_read', expect.objectContaining({ method: 'PATCH' })));
  });
});
