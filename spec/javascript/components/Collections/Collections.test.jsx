import React from 'react';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { TextEncoder, TextDecoder } from 'util';
if (!global.TextEncoder) global.TextEncoder = TextEncoder;
if (!global.TextDecoder) global.TextDecoder = TextDecoder;
const CollectionsWorkspace = require('../../../../app/javascript/components/Collections').default;
import CollectionCreateDialog from '../../../../app/javascript/components/Collections/CollectionCreateDialog';
import CollectionDetail from '../../../../app/javascript/components/Collections/CollectionDetail';
import CollectionPropertiesDialog from '../../../../app/javascript/components/Collections/CollectionPropertiesDialog';
import CollectionsBoard from '../../../../app/javascript/components/Collections/CollectionsBoard';
import SemanticClusterMap from '../../../../app/javascript/components/Collections/SemanticClusterMap';
import ShareCollectionDialog from '../../../../app/javascript/components/Collections/ShareCollectionDialog';
import AddAssetsToCollectionDialog from '../../../../app/javascript/components/Collections/AddAssetsToCollectionDialog';
import { CollectionProvider, useCollections } from '../../../../app/javascript/components/Collections/CollectionContext';
import * as CollectionContextModule from '../../../../app/javascript/components/Collections/CollectionContext';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));
jest.mock('@xyflow/react', () => ({}));
jest.mock('../../../../app/javascript/context/NotificationContext.jsx', () => ({
  useNotify: () => mockNotify,
}));
jest.mock('../../../../app/javascript/utils/globalutils.js', () => ({
  navigateTo: jest.fn(),
}));

const collection = {
  id: 1,
  slug: 'spring-launch',
  name: 'Spring Launch',
  description: 'Seasonal launch assets',
  collection_type: 'smart',
  assets_count: 3,
  properties: { tags: ['Embargoed'], allowed_groups: ['Global Admin'], denied_groups: [] },
  collection_rule: { semantic_prompt: 'spring campaign', similarity_threshold: 0.88 },
  collection_assets: [
    {
      id: 11,
      asset_id: 11,
      pinned: false,
      asset: {
        id: 11,
        original_filename: 'hero.jpg',
        title: 'Hero',
        url: 'https://example.com/hero.jpg',
        file_size: '2 MB',
      },
    },
  ],
  compliance_violations: [{ title: 'Hero', reason: 'Missing rights' }],
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
    if (!handler) return Promise.resolve({ ok: true, json: () => Promise.resolve([]) });
    if (typeof handler === 'function') return handler(url, opts);
    return Promise.resolve({ ok: true, json: () => Promise.resolve(handler) });
  });
}

function Consumer() {
  const ctx = useCollections();
  return (
    <div>
      <span>child wrapped</span>
      <span>count:{ctx.collections.length}</span>
      <button type="button" onClick={() => ctx.fetchCollections()}>load collections</button>
    </div>
  );
}

describe('Collections components', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.clearAllMocks();
    window.history.pushState({}, '', '/collections');
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === '[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
    window.confirm = jest.fn(() => true);
    navigator.clipboard.writeText = jest.fn();
  });

  afterEach(() => {
    jest.runOnlyPendingTimers();
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('wraps children with CollectionProvider and loads collections', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/collections': [collection],
    });

    render(
      <CollectionProvider>
        <Consumer />
      </CollectionProvider>,
    );

    expect(screen.getByText('child wrapped')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'load collections' }));

    await waitFor(() => expect(screen.getByText('count:1')).toBeInTheDocument());
  });

  it('submits CollectionCreateDialog and passes the new slug to onSuccess', async () => {
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({
      createCollection: jest.fn().mockResolvedValue({ slug: 'new-workspace' }),
    });
    const onSuccess = jest.fn();
    const onClose = jest.fn();

    render(<CollectionCreateDialog open onClose={onClose} onSuccess={onSuccess} />);

    fireEvent.change(screen.getByLabelText(/Collection Name/i), { target: { value: 'Launch Plan' } });
    fireEvent.click(screen.getByRole('button', { name: 'Initialize Workspace' }));

    await waitFor(() => expect(onSuccess).toHaveBeenCalledWith('new-workspace'));
    expect(onClose).toHaveBeenCalled();
  });

  it('disables CollectionCreateDialog submit until a name is entered', () => {
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({ createCollection: jest.fn() });

    render(<CollectionCreateDialog open onClose={jest.fn()} onSuccess={jest.fn()} />);

    const submit = screen.getByRole('button', { name: 'Initialize Workspace' });
    expect(submit).toBeDisabled();

    fireEvent.change(screen.getByLabelText(/Collection Name/i), { target: { value: 'Launch Plan' } });
    expect(submit).not.toBeDisabled();
  });

  it('updates a single collection from CollectionPropertiesDialog', async () => {
    const updateCollection = jest.fn().mockResolvedValue(true);
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({
      updateCollection,
      bulkUpdateCollections: jest.fn(),
    });

    render(<CollectionPropertiesDialog open onClose={jest.fn()} selectedCollections={[collection]} />);

    fireEvent.change(screen.getByLabelText(/Collection Name/i), { target: { value: 'Updated Workspace' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save Properties' }));

    await waitFor(() => expect(updateCollection).toHaveBeenCalledWith('spring-launch', expect.objectContaining({ name: 'Updated Workspace' })));
  });

  it('bulk updates selected collections from CollectionPropertiesDialog', async () => {
    const bulkUpdateCollections = jest.fn().mockResolvedValue(true);
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({
      updateCollection: jest.fn(),
      bulkUpdateCollections,
    });

    render(<CollectionPropertiesDialog open onClose={jest.fn()} selectedCollections={[collection, { ...collection, id: 2, slug: 'summer' }]} />);

    fireEvent.click(screen.getAllByRole('checkbox')[0]);
    fireEvent.click(screen.getByRole('button', { name: 'Apply to Selected' }));

    await waitFor(() => expect(bulkUpdateCollections).toHaveBeenCalledWith([1, 2], { properties: { tags: [] } }));
  });

  it('renders CollectionsBoard cards, bulk toolbar, and copy link action', async () => {
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({
      collections: [collection],
      loadingCollections: false,
      fetchCollections: jest.fn(),
      deleteCollection: jest.fn(),
      bulkDeleteCollections: jest.fn().mockResolvedValue(true),
      purgeCdnCache: jest.fn(),
    });

    const setSelectedIds = jest.fn();
    render(<CollectionsBoard onSelectCollection={jest.fn()} selectedIds={[]} setSelectedIds={setSelectedIds} />);

    expect(screen.getByText('Spring Launch')).toBeInTheDocument();
    fireEvent.click(screen.getAllByRole('checkbox')[0]);
    expect(setSelectedIds).toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'Open Workspace' }));
    fireEvent.click(screen.getAllByRole('button').slice(-1)[0]);
    fireEvent.click(await screen.findByText('Copy Workspace Link'));

    expect(navigator.clipboard.writeText).toHaveBeenCalled();
  });

  it('loads CollectionDetail and handles back navigation and AI analysis', async () => {
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({
      updateSmartRule: jest.fn().mockResolvedValue(collection),
      toggleAssetPin: jest.fn().mockResolvedValue(true),
      simulateSmartRule: jest.fn().mockResolvedValue([]),
      temporalDate: '',
    });
    global.fetch = mockFetch({
      'GET /api/v1/collections/spring-launch': collection,
      'GET /api/v1/collections/spring-launch/cluster_map': { nodes: [] },
    });
    const onBack = jest.fn();

    render(<CollectionDetail slug="spring-launch" onBack={onBack} />);

    expect(await screen.findByText('Spring Launch')).toBeInTheDocument();
    expect(screen.getByText('Curated Assets (1)')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Back to Workspace Board' }));
    expect(onBack).toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'Ask AI about this Collection' }));
    act(() => jest.advanceTimersByTime(1600));
    expect(await screen.findByText('Semantic Summary')).toBeInTheDocument();
  });

  it('renders SemanticClusterMap, fetches nodes, and closes', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/collections/spring-launch/cluster_map': { nodes: [{ id: 1, x: 20, y: 30, title: 'Node 1' }] },
    });
    const onClose = jest.fn();

    render(<SemanticClusterMap open onClose={onClose} slug="spring-launch" />);

    expect(await screen.findByText('Semantic Cluster Map')).toBeInTheDocument();
    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/api/v1/collections/spring-launch/cluster_map'));
    fireEvent.click(screen.getByRole('button'));
    expect(onClose).toHaveBeenCalled();
  });

  it('renders CollectionsWorkspace board route and opens the create dialog', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/collections': [collection],
    });

    render(<CollectionsWorkspace />);

    expect(await screen.findByText('My Collections')).toBeInTheDocument();
    expect(await screen.findByText('Spring Launch')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Create Collection' }));
    expect(await screen.findByText('Create New Workspace')).toBeInTheDocument();
  });

  it('opens Add Assets and Share dialogs from CollectionDetail toolbar', async () => {
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({
      updateSmartRule: jest.fn(),
      toggleAssetPin: jest.fn(),
      simulateSmartRule: jest.fn(),
      temporalDate: '',
      generateShareLink: jest.fn().mockResolvedValue({ url: 'https://dam.test/s/collections/tok', expires_at: '2026-08-01T00:00:00Z' }),
      addAssetToCollection: jest.fn(),
    });
    global.fetch = mockFetch({
      'GET /api/v1/collections/spring-launch': collection,
    });

    render(<CollectionDetail slug="spring-launch" onBack={jest.fn()} />);

    expect(await screen.findByText('Spring Launch')).toBeInTheDocument();

    fireEvent.click(screen.getByTestId('collection-add-assets-button'));
    expect(screen.getByTestId('add-assets-dialog')).toBeInTheDocument();

    fireEvent.click(screen.getByTestId('collection-share-button'));
    expect(screen.getByTestId('share-collection-dialog')).toBeInTheDocument();
  });

  it('renders the empty-state Add Assets CTA when a collection has no assets', async () => {
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({
      updateSmartRule: jest.fn(),
      toggleAssetPin: jest.fn(),
      simulateSmartRule: jest.fn(),
      temporalDate: '',
      generateShareLink: jest.fn(),
      addAssetToCollection: jest.fn(),
    });
    global.fetch = mockFetch({
      'GET /api/v1/collections/spring-launch': { ...collection, collection_assets: [] },
    });

    render(<CollectionDetail slug="spring-launch" onBack={jest.fn()} />);

    expect(await screen.findByText('Curated Assets (0)')).toBeInTheDocument();
    fireEvent.click(screen.getByTestId('collection-add-assets-empty-cta'));
    expect(screen.getByTestId('add-assets-dialog')).toBeInTheDocument();
  });

  it('ShareCollectionDialog fetches and copies a signed share link', async () => {
    const generateShareLink = jest.fn().mockResolvedValue({
      url: 'https://dam.test/s/collections/tok', expires_at: '2026-08-01T00:00:00Z',
    });
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({ generateShareLink });

    render(<ShareCollectionDialog open onClose={jest.fn()} slug="spring-launch" />);

    await waitFor(() => expect(generateShareLink).toHaveBeenCalledWith('spring-launch'));
    expect(await screen.findByTestId('share-collection-url-input')).toHaveValue('https://dam.test/s/collections/tok');

    fireEvent.click(screen.getByTestId('share-collection-copy-button'));
    await waitFor(() => expect(navigator.clipboard.writeText).toHaveBeenCalledWith('https://dam.test/s/collections/tok'));
  });

  it('ShareCollectionDialog surfaces an error when link generation fails', async () => {
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({
      generateShareLink: jest.fn().mockResolvedValue(null),
    });

    render(<ShareCollectionDialog open onClose={jest.fn()} slug="spring-launch" />);

    expect(await screen.findByText('collectionShare.error')).toBeInTheDocument();
  });

  it('AddAssetsToCollectionDialog searches the library and attaches a selected asset', async () => {
    const addAssetToCollection = jest.fn().mockResolvedValue({ slug: 'spring-launch' });
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({ addAssetToCollection });
    global.fetch = mockFetch({
      'GET /api/v1/search/suggestions': {
        query: 'hero',
        results: [{ type: 'asset', id: 42, title: 'Hero Shot', subtitle: 'hero.jpg', thumb_url: '' }],
      },
    });

    render(<AddAssetsToCollectionDialog open onClose={jest.fn()} slug="spring-launch" onAssetsAdded={jest.fn()} />);

    fireEvent.change(screen.getByTestId('add-assets-search-input'), { target: { value: 'hero' } });
    act(() => jest.advanceTimersByTime(350));

    expect(await screen.findByText('Hero Shot')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('checkbox'));

    await waitFor(() => expect(addAssetToCollection).toHaveBeenCalledWith('spring-launch', 42));
    expect(await screen.findByText('addAssetsDialog.added')).toBeInTheDocument();
  });

  it('AddAssetsToCollectionDialog shows a hint before any search query is entered', () => {
    jest.spyOn(CollectionContextModule, 'useCollections').mockReturnValue({ addAssetToCollection: jest.fn() });

    render(<AddAssetsToCollectionDialog open onClose={jest.fn()} slug="spring-launch" onAssetsAdded={jest.fn()} />);

    expect(screen.getByText('addAssetsDialog.searchHint')).toBeInTheDocument();
  });
});