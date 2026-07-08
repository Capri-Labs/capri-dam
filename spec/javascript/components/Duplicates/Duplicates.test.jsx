import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import DuplicateManager from '../../../../app/javascript/components/Duplicates/DuplicateManager';
import DuplicateResolutionModal from '../../../../app/javascript/components/Duplicates/DuplicateResolutionModal';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));
jest.mock('../../../../app/javascript/context/NotificationContext.jsx', () => ({
  useNotify: () => mockNotify,
}));
jest.mock('../../../../app/javascript/utils/globalutils.js', () => ({ navigateTo: jest.fn() }));

const group = {
  id: 12,
  total_count: 2,
  checksum: 'abcdef1234567890abcdef',
  status: 'pending',
  assets: [
    { asset_id: 1, title: 'Hero.jpg', url: 'https://example.com/hero.jpg', content_type: 'image/jpeg', is_original: true, folder_name: 'Root', uploaded_at: '2024-01-01T00:00:00Z' },
    { asset_id: 2, title: 'Hero-copy.jpg', url: 'https://example.com/hero2.jpg', content_type: 'image/jpeg', folder_name: 'Root', uploaded_at: '2024-01-02T00:00:00Z' },
  ],
};

function mockFetch(routes) {
  return jest.fn((url, opts = {}) => {
    const method = opts.method || 'GET';
    const key = Object.keys(routes)
      .filter((route) => {
        const [m, path] = route.split(' ');
        return m === method && String(url).startsWith(path);
      })
      .sort((a, b) => b.length - a.length)[0];
    const handler = key ? routes[key] : null;
    if (!handler) return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
    if (typeof handler === 'function') return handler(url, opts);
    return Promise.resolve({ ok: true, json: () => Promise.resolve(handler) });
  });
}

describe('Duplicates components', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === '[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('renders DuplicateManager with duplicate groups and stats', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/duplicate_groups/stats': { pending: 1, resolved: 0, total: 1 },
      'GET /api/v1/duplicate_groups?status=pending': { groups: [group] },
      'GET /api/v1/duplicate_groups/12': { group },
    });

    render(<DuplicateManager />);

    expect(await screen.findByText('duplicateManager.title')).toBeInTheDocument();
    expect(await screen.findByText('duplicateManager.group.potentialMatch')).toBeInTheDocument();
    expect(screen.getAllByText('1').length).toBeGreaterThan(0);
  });

  it('opens group details from DuplicateManager', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/duplicate_groups/stats': { pending: 1, resolved: 0, total: 1 },
      'GET /api/v1/duplicate_groups?status=pending': { groups: [group] },
      'GET /api/v1/duplicate_groups/12': { group },
    });

    render(<DuplicateManager />);

    const cardLabel = await screen.findByText('duplicateManager.group.potentialMatch');
    fireEvent.click(cardLabel);
    expect(await screen.findByText('duplicateManager.resolution.title')).toBeInTheDocument();
  });

  it('renders DuplicateResolutionModal options and resolves selected duplicates', async () => {
    const onResolve = jest.fn();
    const onDismiss = jest.fn();

    render(
      <DuplicateResolutionModal
        open
        duplicateGroup={group}
        loading={false}
        onClose={jest.fn()}
        onResolve={onResolve}
        onDismiss={onDismiss}
      />,
    );

    expect(screen.getByText('duplicateManager.resolution.title')).toBeInTheDocument();
    fireEvent.click(screen.getByText('Hero.jpg'));
    fireEvent.click(screen.getByRole('button', { name: /duplicateManager.resolution.delete/i }));
    fireEvent.click(await screen.findByRole('button', { name: 'common.confirm' }));

    expect(onResolve).toHaveBeenCalledWith(12, 'delete', [1]);

    fireEvent.click(screen.getByRole('button', { name: /duplicateManager.resolution.accept/i }));
    expect(onResolve).toHaveBeenCalledWith(12, 'accept', []);
  });

  it('dismisses a duplicate group from the resolution modal', () => {
    const onDismiss = jest.fn();

    render(
      <DuplicateResolutionModal
        open
        duplicateGroup={group}
        loading={false}
        onClose={jest.fn()}
        onResolve={jest.fn()}
        onDismiss={onDismiss}
      />,
    );

    // Regression check: the dismiss icon button must expose an accessible
    // name (aria-label), not just a Tooltip title, so it can be targeted by
    // assistive tech and by getByRole/getByLabel queries in tests.
    fireEvent.click(screen.getByRole('button', { name: 'duplicateManager.resolution.dismiss' }));
    expect(onDismiss).toHaveBeenCalledWith(12);
  });

  it('removes a dismissed group from the pending list in DuplicateManager', async () => {
    const dismissedGroup = { ...group, id: 99 };
    let isDismissed = false;
    global.fetch = mockFetch({
      'GET /api/v1/duplicate_groups/stats': { pending: 1, resolved: 0, total: 1 },
      'GET /api/v1/duplicate_groups?status=pending': () => Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ groups: isDismissed ? [] : [ dismissedGroup ] }),
      }),
      'GET /api/v1/duplicate_groups/99': { group: dismissedGroup },
      'PATCH /api/v1/duplicate_groups/99/dismiss': () => {
        isDismissed = true;
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ group: { ...dismissedGroup, status: 'dismissed' }, message: 'Group dismissed.' }),
        });
      },
    });

    render(<DuplicateManager />);

    const cardLabel = await screen.findByText('duplicateManager.group.potentialMatch');
    fireEvent.click(cardLabel);
    expect(await screen.findByText('duplicateManager.resolution.title')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'duplicateManager.resolution.dismiss' }));

    await waitFor(() => expect(screen.queryByText('duplicateManager.resolution.title')).not.toBeInTheDocument());
    await waitFor(() => expect(screen.queryByText('duplicateManager.group.potentialMatch')).not.toBeInTheDocument());
    expect(await screen.findByText('duplicateManager.emptyState')).toBeInTheDocument();
  });
});
