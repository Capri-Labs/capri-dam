import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key, opts) => opts?.defaultValue || key,
  }),
}));

import InboxPage from '../../../../app/javascript/components/Inbox/InboxPage';

global.fetch = jest.fn();

describe('InboxPage', () => {
  beforeEach(() => {
    global.fetch.mockImplementation((url, options = {}) => {
      if (url === '/api/v1/inbox/unread_count') {
        return Promise.resolve({ ok: true, json: async () => ({ unread_count: 1 }) });
      }

      if (url.startsWith('/api/v1/inbox/') && url.endsWith('/mark_read')) {
        return Promise.resolve({ ok: true, json: async () => ({ success: true, unread_count: 0 }) });
      }

      if (url.startsWith('/api/v1/inbox/') && !options.method) {
        return Promise.resolve({
          ok: true,
          json: async () => ({
            message: {
              id: 'uuid-1',
              subject: 'You were mentioned in Asset Review',
              message_type: 'mention',
              read: true,
              starred: false,
              snippet: 'Hey @john, please review this asset.',
              created_at: new Date().toISOString(),
              sender: { id: 'uuid-s', name: 'Alice', email: 'alice@example.com' },
              body_html: '<p>Full body</p>',
              body_text: 'Full body',
            },
          }),
        });
      }

      return Promise.resolve({
        ok: true,
        json: async () => ({
          messages: [
            {
              id: 'uuid-1',
              subject: 'You were mentioned in Asset Review',
              message_type: 'mention',
              read: false,
              starred: false,
              snippet: 'Hey @john, please review this asset.',
              created_at: new Date().toISOString(),
              sender: { id: 'uuid-s', name: 'Alice', email: 'alice@example.com' },
            },
          ],
          pagination: { page: 1, per_page: 25, total: 1, total_pages: 1 },
          unread_count: 1,
        }),
      });
    });
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('renders inbox page', async () => {
    render(<InboxPage />);

    expect(screen.getByRole('heading', { name: 'Inbox' })).toBeInTheDocument();
    expect(await screen.findAllByText('You were mentioned in Asset Review')).not.toHaveLength(0);
  });

  it('shows unread badge', async () => {
    render(<InboxPage />);

    await screen.findAllByText('You were mentioned in Asset Review');
    expect(screen.getAllByText('1').length).toBeGreaterThan(0);
  });

  it('marks message read from the viewer toolbar', async () => {
    render(<InboxPage />);

    await screen.findAllByText('You were mentioned in Asset Review');
    const markReadButton = screen.getByTestId('MarkEmailReadIcon').closest('button');
    await userEvent.click(markReadButton);

    await waitFor(() => {
      expect(global.fetch.mock.calls.some(([url]) => url === '/api/v1/inbox/uuid-1/mark_read')).toBe(true);
    });
  });
});
