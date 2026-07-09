import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

import QuarantineManager from '../../../../../app/javascript/components/Admin/Quarantine/QuarantineManager';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
}));

jest.mock('../../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

function mockFetch(routes) {
  return jest.fn((url, opts = {}) => {
    const method = opts.method || 'GET';
    const key = Object.keys(routes)
      .filter((route) => {
        const [routeMethod, routePath] = route.split(' ');
        return routeMethod === method && String(url).startsWith(routePath);
      })
      .sort((a, b) => b.length - a.length)[0];

    if (!key) {
      return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
    }

    const handler = routes[key];
    if (typeof handler === 'function') return handler(url, opts);
    return Promise.resolve({ ok: true, json: () => Promise.resolve(handler) });
  });
}

describe('QuarantineManager', () => {
  const entry = {
    id: 10,
    status: 'pending_review',
    rejection_reason: 'Malware scan returned a suspicious signature.',
    flagged_at: '2026-07-08T12:00:00Z',
    review_notes: null,
    system_connector: { id: 4, name: 'Dropbox Connector' },
    asset: {
      title: 'hero-banner.png',
      content_type: 'image/png',
      uploaded_by: 'editor@example.com',
      uploaded_at: '2026-07-08T11:55:00Z',
      preview_url: 'https://example.com/preview.png',
      url: 'https://example.com/file.png',
    },
    original_payload: { asset: { name: 'hero-banner.png' } },
  };

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === '[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('renders quarantine entries and stats', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/quarantined_assets/stats': {
        pending_review: 1,
        resolved: 0,
        discarded: 0,
        total: 1,
      },
      'GET /api/v1/quarantined_assets?status=pending_review&page=1&per_page=25': {
        items: [entry],
        pagination: { total: 1, page: 1, per_page: 25, pages: 1 },
      },
    });

    render(<QuarantineManager />);

    expect(await screen.findByText('quarantine.title')).toBeInTheDocument();
    expect(await screen.findByText('hero-banner.png')).toBeInTheDocument();
    expect(screen.getByText('Malware scan returned a suspicious signature.')).toBeInTheDocument();
    expect(screen.getAllByText('1').length).toBeGreaterThan(0);
  });

  it('loads details and sends the release action to the API', async () => {
    let releaseCalled = false;

    global.fetch = mockFetch({
      'GET /api/v1/quarantined_assets/stats': {
        pending_review: 1,
        resolved: 0,
        discarded: 0,
        total: 1,
      },
      'GET /api/v1/quarantined_assets?status=pending_review&page=1&per_page=25': {
        items: [entry],
        pagination: { total: 1, page: 1, per_page: 25, pages: 1 },
      },
      'GET /api/v1/quarantined_assets/10': { entry },
      'PATCH /api/v1/quarantined_assets/10/release': () => {
        releaseCalled = true;
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({
            entry: { ...entry, status: 'resolved', review_notes: 'Reviewed and released.' },
            message: 'Quarantined asset released.',
          }),
        });
      },
    });

    render(<QuarantineManager />);

    fireEvent.click(await screen.findByRole('button', { name: 'quarantine.actions.view' }));
    expect(await screen.findByText('quarantine.detail.title')).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText('quarantine.detail.reviewNotes'), {
      target: { value: 'Reviewed and released.' },
    });
    fireEvent.click((await screen.findAllByRole('button', { name: 'quarantine.actions.release' })).at(-1));

    await waitFor(() => expect(releaseCalled).toBe(true));
  });

  it('confirms discard before calling the discard endpoint', async () => {
    let discardCalled = false;

    global.fetch = mockFetch({
      'GET /api/v1/quarantined_assets/stats': {
        pending_review: 1,
        resolved: 0,
        discarded: 0,
        total: 1,
      },
      'GET /api/v1/quarantined_assets?status=pending_review&page=1&per_page=25': {
        items: [entry],
        pagination: { total: 1, page: 1, per_page: 25, pages: 1 },
      },
      'PATCH /api/v1/quarantined_assets/10/discard': () => {
        discardCalled = true;
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({
            entry: { ...entry, status: 'discarded' },
            message: 'Quarantined asset discarded.',
          }),
        });
      },
    });

    render(<QuarantineManager />);

    fireEvent.click(await screen.findByRole('button', { name: 'quarantine.actions.discard' }));
    expect(await screen.findByText('quarantine.confirmDiscard.title')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'quarantine.confirmDiscard.confirm' }));

    await waitFor(() => expect(discardCalled).toBe(true));
  });
});
