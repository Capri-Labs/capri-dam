import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import BinActivePurgeBanner from '../../../../app/javascript/components/Bin/BinActivePurgeBanner';
import BinConfirmDialog from '../../../../app/javascript/components/Bin/BinConfirmDialog';
import BinEmptyState from '../../../../app/javascript/components/Bin/BinEmptyState';
import BinFilterBar from '../../../../app/javascript/components/Bin/BinFilterBar';
import BinGrid from '../../../../app/javascript/components/Bin/BinGrid';
import BinList from '../../../../app/javascript/components/Bin/BinList';
import BinManager from '../../../../app/javascript/components/Bin/BinManager';
import BinStatsBar from '../../../../app/javascript/components/Bin/BinStatsBar';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));
jest.mock('../../../../app/javascript/context/NotificationContext.jsx', () => ({
  useNotify: () => mockNotify,
}));

const item = {
  id: 1,
  grid_id: 'grid-1',
  name: 'Hero image',
  media_type: 'image',
  item_type: 'asset',
  url: 'https://example.com/hero.jpg',
  deleted_at: '2024-01-10T10:00:00Z',
  expires_at: '2099-01-17T00:00:00Z',
  size_human: '2 MB',
  original_path: '/campaigns/hero.jpg',
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

    if (!key) {
      return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
    }

    const handler = routes[key];
    if (typeof handler === 'function') return handler(url, opts);
    return Promise.resolve({ ok: true, json: () => Promise.resolve(handler) });
  });
}

describe('Bin components', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === '[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('BinActivePurgeBanner', () => {
    it('renders the active purge banner and can be dismissed', async () => {
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        json: async () => ({
          status: 'queued',
          started_at: '2024-01-01T12:00:00Z',
          triggered_by: { source: 'user', user_name: 'Admin' },
        }),
      });

      render(<BinActivePurgeBanner onComplete={jest.fn()} />);

      expect(await screen.findByText('bin.activePurge.queuedTitle')).toBeInTheDocument();
      expect(screen.getByText('bin.activePurge.hint')).toBeInTheDocument();

      fireEvent.click(screen.getAllByRole('button')[1]);
      await waitFor(() => expect(screen.queryByText('bin.activePurge.queuedTitle')).not.toBeInTheDocument());
    });

    it('calls onComplete when refresh sees the purge finish', async () => {
      const onComplete = jest.fn();
      global.fetch = jest
        .fn()
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ status: 'running', triggered_by: { source: 'scheduled' } }),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ status: 'completed', triggered_by: { source: 'scheduled' } }),
        });

      render(<BinActivePurgeBanner onComplete={onComplete} />);

      expect(await screen.findByText('bin.activePurge.runningTitle')).toBeInTheDocument();
      fireEvent.click(screen.getAllByRole('button')[0]);

      await waitFor(() => expect(onComplete).toHaveBeenCalledWith(expect.objectContaining({ status: 'completed' })));
    });
  });

  it('renders and handles BinConfirmDialog actions', () => {
    const onConfirm = jest.fn();
    const onClose = jest.fn();

    render(
      <BinConfirmDialog
        open
        variant="delete"
        count={2}
        onConfirm={onConfirm}
        onClose={onClose}
      />,
    );

    expect(screen.getByText('bin.confirm.delete')).toBeInTheDocument();
    expect(screen.getByText('bin.confirm.deleteBody')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'bin.confirm.confirm' }));
    fireEvent.click(screen.getByRole('button', { name: 'bin.confirm.cancel' }));

    expect(onConfirm).toHaveBeenCalled();
    expect(onClose).toHaveBeenCalled();
  });

  it('shows the empty state copy', () => {
    render(<BinEmptyState />);
    expect(screen.getByText('bin.empty')).toBeInTheDocument();
    expect(screen.getByText('bin.emptySubtitle')).toBeInTheDocument();
  });

  it('updates filters from BinFilterBar controls', async () => {
    const props = {
      query: '',
      onQueryChange: jest.fn(),
      typeFilter: 'all',
      onTypeFilterChange: jest.fn(),
      sort: { field: 'deleted_at', direction: 'desc' },
      onSortChange: jest.fn(),
      viewLayout: 'grid',
      onViewLayoutChange: jest.fn(),
      gridSize: 'medium',
      onGridSizeChange: jest.fn(),
      resultCount: 5,
      allSelected: false,
      hasSelection: false,
      onSelectAll: jest.fn(),
      onDeselectAll: jest.fn(),
    };

    render(<BinFilterBar {...props} />);

    fireEvent.change(screen.getByPlaceholderText('bin.search'), { target: { value: 'hero' } });
    fireEvent.click(screen.getByText('bin.filters.images'));
    fireEvent.click(screen.getByRole('button', { name: 'bin.sort.deletedNewest' }));
    fireEvent.click(await screen.findByRole('menuitem', { name: 'bin.sort.nameAZ' }));

    expect(props.onQueryChange).toHaveBeenCalledWith('hero');
    expect(props.onTypeFilterChange).toHaveBeenCalledWith('image');
    expect(props.onSortChange).toHaveBeenCalledWith({ field: 'name', direction: 'asc' });
  });

  it('renders BinGrid items and invokes actions', () => {
    const onToggleSelect = jest.fn();
    const onRestore = jest.fn();
    const onDelete = jest.fn();

    render(
      <BinGrid
        items={[item]}
        isSelected={() => false}
        onToggleSelect={onToggleSelect}
        onRestore={onRestore}
        onDelete={onDelete}
        gridSize="medium"
        loading={false}
      />,
    );

    expect(screen.getByText('Hero image')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getAllByRole('button')[0]);
    fireEvent.click(screen.getAllByRole('button')[1]);

    expect(onToggleSelect).toHaveBeenCalledWith('grid-1');
    expect(onRestore).toHaveBeenCalledWith(expect.objectContaining({ id: 1 }));
    expect(onDelete).toHaveBeenCalledWith(expect.objectContaining({ id: 1 }));
  });

  it('renders BinList rows and toggles sort and selection', () => {
    const onToggleSelect = jest.fn();
    const onSortChange = jest.fn();

    render(
      <BinList
        items={[item]}
        isSelected={() => false}
        onToggleSelect={onToggleSelect}
        onRestore={jest.fn()}
        onDelete={jest.fn()}
        loading={false}
        sort={{ field: 'deleted_at', direction: 'desc' }}
        onSortChange={onSortChange}
      />,
    );

    expect(screen.getByText('Hero image')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getByText('bin.item.name'));

    expect(onToggleSelect).toHaveBeenCalledWith('grid-1');
    expect(onSortChange).toHaveBeenCalledWith({ field: 'name', direction: 'asc' });
  });

  it('shows bin stats values', () => {
    render(
      <BinStatsBar
        loading={false}
        stats={{ total_items: 10, total_assets: 7, total_folders: 3, total_size_bytes: 2048 }}
      />,
    );

    expect(screen.getByText('10')).toBeInTheDocument();
    expect(screen.getByText('7')).toBeInTheDocument();
    expect(screen.getByText('3')).toBeInTheDocument();
    expect(screen.getByText('2.0 KB')).toBeInTheDocument();
  });

  it('renders BinManager with stats, filters, and list content', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/bin/stats': { total_items: 1, total_assets: 1, total_folders: 0, total_size_bytes: 1024, retention_days: 30 },
      'GET /api/v1/bin?': { items: [item], pagination: { total: 1, page: 1, per_page: 25, pages: 1 } },
      'GET /api/v1/bin/purge_status': { status: 'completed' },
    });

    render(<BinManager />);

    expect(await screen.findByText('bin.title')).toBeInTheDocument();
    expect(screen.getByText('Hero image')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('bin.search')).toBeInTheDocument();
    expect(screen.getAllByText('1').length).toBeGreaterThan(0);
  });

  it('shows bulk action buttons after selecting all items in BinManager', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/bin/stats': { total_items: 1, total_assets: 1, total_folders: 0, total_size_bytes: 1024, retention_days: 30 },
      'GET /api/v1/bin?': { items: [item], pagination: { total: 1, page: 1, per_page: 25, pages: 1 } },
      'GET /api/v1/bin/purge_status': { status: 'completed' },
    });

    render(<BinManager />);
    await screen.findByText('Hero image');

    fireEvent.click(screen.getAllByRole('checkbox')[0]);

    expect(await screen.findByRole('button', { name: /bin.restoreSelected/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /bin.deleteSelected/i })).toBeInTheDocument();
  });
});
