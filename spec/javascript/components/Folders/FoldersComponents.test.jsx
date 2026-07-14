import React from 'react';
import { render, screen, fireEvent, waitFor, within, act } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import AiAnalysisDialog from '../../../../app/javascript/components/Folders/AiAnalysisDialog';
import ApplySchemaDialog from '../../../../app/javascript/components/Folders/ApplySchemaDialog';
import AssetAuditTab from '../../../../app/javascript/components/Folders/AssetAuditTab';
import AssetCard from '../../../../app/javascript/components/Folders/AssetCard';
import AssetGrid from '../../../../app/javascript/components/Folders/AssetGrid';
import AssetMetadataPanel from '../../../../app/javascript/components/Folders/AssetMetadataPanel';
import AssetStatsPopover from '../../../../app/javascript/components/Folders/AssetStatsPopover';
import AssetTagsEditor from '../../../../app/javascript/components/Folders/AssetTagsEditor';
import AssetVersionsTab from '../../../../app/javascript/components/Folders/AssetVersionsTab';
import AssetViewer from '../../../../app/javascript/components/Folders/AssetViewer';
import CopyDialog from '../../../../app/javascript/components/Folders/CopyDialog';
import DuplicateResolverDialog from '../../../../app/javascript/components/Folders/DuplicateResolverDialog';
import ExplorerTopBar from '../../../../app/javascript/components/Folders/ExplorerTopBar';
import FolderAccessTab from '../../../../app/javascript/components/Folders/FolderAccessTab';
import FolderInfoPanel from '../../../../app/javascript/components/Folders/FolderInfoPanel';
import FoldersManager from '../../../../app/javascript/components/Folders/FoldersManager';
import ImageEditorDialog from '../../../../app/javascript/components/Folders/ImageEditorDialog';
import MoveDialog from '../../../../app/javascript/components/Folders/MoveDialog';
import PinToCollectionDialog from '../../../../app/javascript/components/Folders/PinToCollectionDialog';
import RenameDialog from '../../../../app/javascript/components/Folders/RenameDialog';
import UploadGrid from '../../../../app/javascript/components/Folders/UploadGrid';
import UploadSidebar from '../../../../app/javascript/components/Folders/UploadSidebar';
import UploadWorkspace from '../../../../app/javascript/components/Folders/UploadWorkspace';

const mockNotify = jest.fn();
const mockAssetExplorer = jest.fn();
const mockCalculateFileHash = jest.fn();
const mockParseProductFilename = jest.fn();
const mockDefaultSchemaSlugForMime = jest.fn();
let dropzoneOnDrop;

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key, opts) => (opts?.count != null ? `${key}:${opts.count}` : key),
  }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('../../../../app/javascript/components/Folders/AssetExplorer', () => (props) => {
  mockAssetExplorer(props);
  return <div data-testid="asset-explorer">AssetExplorer</div>;
});

jest.mock('../../../../app/javascript/components/Sidebar', () => () => <div data-testid="sidebar" />);

jest.mock('../../../../app/javascript/utils/globalutils', () => ({
  calculateFileHash: (...args) => mockCalculateFileHash(...args),
  navigateTo: jest.fn(),
}));

jest.mock('../../../../app/javascript/utils/productFilename', () => ({
  parseProductFilename: (...args) => mockParseProductFilename(...args),
  defaultSchemaSlugForMime: (...args) => mockDefaultSchemaSlugForMime(...args),
}));

jest.mock('react-dropzone', () => ({
  useDropzone: jest.fn((options = {}) => {
    dropzoneOnDrop = options.onDrop;
    return {
      getRootProps: () => ({ 'data-testid': 'dropzone-root' }),
      getInputProps: () => ({ 'data-testid': 'dropzone-input' }),
      isDragActive: false,
    };
  }),
}));

const jsonResponse = (data, { ok = true, status = 200 } = {}) => Promise.resolve({
  ok,
  status,
  json: () => Promise.resolve(data),
  blob: () => Promise.resolve(new Blob(['download'])),
});

const mockFetch = (routes) => jest.fn((url, options = {}) => {
  const method = (options.method || 'GET').toUpperCase();
  const path = String(url);
  const key = Object.keys(routes)
    .filter((route) => {
      const [routeMethod, routePath] = route.split(' ');
      return routeMethod === method && path.startsWith(routePath);
    })
    .sort((a, b) => b.length - a.length)[0];

  if (!key) {
    return jsonResponse({});
  }

  const handler = routes[key];
  if (typeof handler === 'function') {
    return handler(url, options);
  }

  if (handler && typeof handler === 'object' && 'ok' in handler) {
    return Promise.resolve(handler);
  }

  return jsonResponse(handler);
});

const iconButton = (testId, index = 0) => screen.getAllByTestId(testId)[index].closest('button');
const buildCanvasContext = ({ throwSecurityError = false } = {}) => {
  const getImageData = jest.fn(() => {
    if (throwSecurityError) {
      const error = new Error('The canvas has been tainted by cross-origin data');
      error.name = 'SecurityError';
      throw error;
    }

    return { data: new Uint8ClampedArray([0, 0, 0, 255]) };
  });

  return {
    clearRect: jest.fn(),
    drawImage: jest.fn(),
    getImageData,
    createImageData: jest.fn((width, height) => ({ data: new Uint8ClampedArray(width * height * 4), width, height })),
    putImageData: jest.fn(),
  };
};

beforeAll(() => {
  global.Image = class {
    set src(_value) {
      this.width = 800;
      this.height = 600;
      setTimeout(() => this.onload?.(), 0);
    }
  };
});

beforeEach(() => {
  jest.restoreAllMocks();
  jest.clearAllMocks();
  jest.useRealTimers();
  dropzoneOnDrop = null;
  mockCalculateFileHash.mockResolvedValue('hash-1');
  mockParseProductFilename.mockReturnValue({
    isProductNaming: true,
    productId: '0123',
    langCode: 'en',
    assetTypeCode: 'FR01',
  });
  mockDefaultSchemaSlugForMime.mockImplementation((mime) => (mime?.startsWith('image/') ? 'product-images' : 'default'));

  global.fetch = jest.fn(() => jsonResponse({}));
  navigator.clipboard.writeText = jest.fn(() => Promise.resolve());
  window.open = jest.fn();
  window.URL.createObjectURL = jest.fn(() => 'blob:preview');
  window.URL.revokeObjectURL = jest.fn();

  let meta = document.querySelector('meta[name="csrf-token"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.setAttribute('name', 'csrf-token');
    document.head.appendChild(meta);
  }
  meta.setAttribute('content', 'test-csrf-token');
});

describe('Folders components', () => {
  it('renders AiAnalysisDialog results and applies selected tags', async () => {
    global.fetch = mockFetch({
      'POST /api/v1/assets/1/ai_analysis': {
        description: 'Hero banner with summer colors',
        labels: ['outdoor'],
        colors: [{ name: 'Blue', hex: '#0000ff' }],
        quality_score: 87,
        suggested_tags: ['hero', 'summer'],
        similar_assets: [{ id: 2, title: 'Similar Hero', url: '/similar.jpg' }],
      },
      'PATCH /api/v1/assets/1': {},
    });

    render(<AiAnalysisDialog open onClose={jest.fn()} asset={{ id: 1, title: 'Hero', url: '/hero.jpg' }} />);

    expect((await screen.findAllByText('Hero banner with summer colors'))[0]).toBeInTheDocument();
    expect(screen.getByText('outdoor')).toBeInTheDocument();

    act(() => { fireEvent.click(screen.getByRole('checkbox', { name: 'summer' })); });
    act(() => { fireEvent.click(screen.getByRole('button', { name: 'folders.ai.apply_tags' })); });

    await waitFor(() => {
      const patchCall = global.fetch.mock.calls.find(([url, options]) => String(url) === '/api/v1/assets/1' && options.method === 'PATCH');
      expect(patchCall).toBeTruthy();
      expect(JSON.parse(patchCall[1].body)).toEqual({ asset: { tags: ['hero'] } });
    });
    expect(mockNotify).toHaveBeenCalledWith('folders.ai.apply_tags', 'success');
  });

  it('loads schemas in ApplySchemaDialog and applies the selected folder schema', async () => {
    const onClose = jest.fn();
    global.fetch = mockFetch({
      'GET /api/v1/metadata_schemas': [
        { id: 1, name: 'Marketing', level: 'root', description: 'Marketing assets', tabs: [{ fields: [{}, {}] }] },
        { id: 2, name: 'JPEG subtype', level: 'type' },
      ],
      'POST /api/v1/folders/10/apply_schema': {},
    });

    render(
      <ApplySchemaDialog
        open
        onClose={onClose}
        targetType="folder"
        targetIds={[10]}
        targetNames={['Catalog']}
        currentFolderId={10}
      />,
    );

    expect(await screen.findByText('Marketing')).toBeInTheDocument();
    fireEvent.click(screen.getByText('Marketing'));
    fireEvent.click(screen.getByRole('button', { name: /Apply "Marketing"/i }));

    await waitFor(() => {
      const postCall = global.fetch.mock.calls.find(([url, options]) => String(url) === '/api/v1/folders/10/apply_schema');
      expect(postCall).toBeTruthy();
      expect(JSON.parse(postCall[1].body)).toEqual({ schema_id: 1, cascade: true });
    });
    expect(onClose).toHaveBeenCalledWith(true);
  });

  it('renders AssetAuditTab audit history with change indicators', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/assets/7/audit_trail': {
        audit_trail: [
          {
            id: 'a1',
            version_number: 2,
            action_type: 'image_edit',
            created_at: '2024-01-03T10:00:00Z',
            created_by_id: 99,
            properties: JSON.stringify({ size: 2048, resolution: '1200x800', color_space: 'sRGB' }),
          },
          {
            id: 'a0',
            version_number: 1,
            action_type: 'branched_edit',
            created_at: '2024-01-02T10:00:00Z',
            created_by_id: 99,
            properties: JSON.stringify({ size: 1024, resolution: '1000x700', color_space: 'Adobe RGB' }),
          },
        ],
      },
    });

    render(<AssetAuditTab asset={{ id: 7 }} />);

    expect(await screen.findByText('Operational Ledger')).toBeInTheDocument();
    expect(screen.getByText('Image Edited')).toBeInTheDocument();
    expect(screen.getByText('Timeline Forked')).toBeInTheDocument();
    expect(screen.getByText(/1200x800/)).toBeInTheDocument();
  });

  it('renders AssetCard fallback preview and supports menu actions', async () => {
    const onPin = jest.fn();
    const onViewMore = jest.fn();
    render(<AssetCard asset={{ id: 1, title: 'Manual.pdf', size: '2 MB' }} onPin={onPin} onViewMore={onViewMore} />);

    expect(screen.getByText('No Preview')).toBeInTheDocument();
    fireEvent.click(iconButton('MoreVertIcon'));
    fireEvent.click(await screen.findByText('Add to Collection'));
    expect(onPin).toHaveBeenCalledWith(expect.objectContaining({ id: 1 }));
  });

  it('shows a Processing placeholder for an AssetCard whose worker has not finished yet', () => {
    render(<AssetCard asset={{ id: 2, title: 'Uploading.jpg', status: 'pending', url: '/api/v1/assets/local/uuid-pending' }} onPin={jest.fn()} onViewMore={jest.fn()} />);
    expect(screen.getByText('Processing…')).toBeInTheDocument();
    expect(screen.queryByRole('img', { name: 'Uploading.jpg' })).toBeNull();
  });

  it('shows a broken-image placeholder for an AssetCard whose preview fails to load', () => {
    render(<AssetCard asset={{ id: 3, title: 'Missing.jpg', status: 'ready', url: '/api/v1/assets/local/uuid-missing' }} onPin={jest.fn()} onViewMore={jest.fn()} />);
    const img = screen.getByRole('img', { name: 'Missing.jpg' });
    fireEvent.error(img);
    expect(screen.queryByRole('img', { name: 'Missing.jpg' })).toBeNull();
    expect(screen.getByText('Preview unavailable')).toBeInTheDocument();
  });

  it('renders AssetGrid and calls selection and AI actions', () => {
    const toggleSelection = jest.fn();
    const onAiAnalysis = jest.fn();
    render(
      <AssetGrid
        assets={[{ id: 3, title: 'Hero', content_type: 'image/jpeg', url: '/hero.jpg', status: 'published', size: 2048 }]}
        viewMode="active"
        selectedItems={{ assets: [] }}
        toggleSelection={toggleSelection}
        setSelectedAsset={jest.fn()}
        onPinClick={jest.fn()}
        onFindDuplicates={jest.fn()}
        onAiAnalysis={onAiAnalysis}
      />,
    );

    expect(screen.getByText('folders.filter.published')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('checkbox'));
    expect(toggleSelection).toHaveBeenCalledWith('assets', 3, expect.any(Object));

    fireEvent.click(iconButton('AutoAwesomeOutlinedIcon'));
    expect(onAiAnalysis).toHaveBeenCalledWith(expect.objectContaining({ id: 3 }));
  });

  it('renders a video poster thumbnail with a Play toggle in AssetGrid (Card view) and plays/pauses an inline preview', () => {
    const setSelectedAsset = jest.fn();
    render(
      <AssetGrid
        assets={[{
          id: 21,
          title: 'Product Demo.mp4',
          content_type: 'video/mp4',
          url: '/product-demo.mp4',
          video_poster_url: '/product-demo-poster.jpg',
          status: 'published',
          size: 4096,
        }]}
        viewMode="active"
        selectedItems={{ assets: [] }}
        toggleSelection={jest.fn()}
        setSelectedAsset={setSelectedAsset}
        onPinClick={jest.fn()}
        onFindDuplicates={jest.fn()}
        onAiAnalysis={jest.fn()}
      />,
    );

    expect(document.querySelector('img[src="/product-demo-poster.jpg"]')).toBeInTheDocument();
    expect(screen.queryByTestId('asset-grid-video-preview-playing')).not.toBeInTheDocument();

    fireEvent.click(screen.getByTestId('asset-grid-video-play-toggle'));
    expect(screen.getByTestId('asset-grid-video-preview-playing')).toBeInTheDocument();

    // Clicking the play/pause toggle must not bubble up and open the asset viewer.
    expect(setSelectedAsset).not.toHaveBeenCalled();

    fireEvent.click(screen.getByTestId('asset-grid-video-play-toggle'));
    expect(screen.queryByTestId('asset-grid-video-preview-playing')).not.toBeInTheDocument();
  });

  it('falls back to a VideoFile icon (no play toggle) in AssetGrid when a video has no poster/playable rendition', () => {
    render(
      <AssetGrid
        assets={[{
          id: 22,
          title: 'Untranscoded.mov',
          content_type: 'video/quicktime',
          status: 'published',
          size: 4096,
        }]}
        viewMode="active"
        selectedItems={{ assets: [] }}
        toggleSelection={jest.fn()}
        setSelectedAsset={jest.fn()}
        onPinClick={jest.fn()}
        onFindDuplicates={jest.fn()}
        onAiAnalysis={jest.fn()}
      />,
    );

    expect(screen.queryByTestId('asset-grid-video-play-toggle')).not.toBeInTheDocument();
  });

  it('loads schema in AssetMetadataPanel and saves changed metadata', async () => {
    const onAssetUpdated = jest.fn();
    global.fetch = mockFetch({
      'GET /api/v1/assets/1/metadata_schema': {
        id: 5,
        name: 'Product Schema',
        applied_schema_id: 5,
        resolved_tabs: [
          {
            id: 'general',
            name: 'General',
            fields: [{ id: 'sku', label: 'SKU', field_type: 'text', map_to_property: 'sku', value: 'SKU-1' }],
          },
        ],
      },
      'PATCH /api/v1/assets/1/metadata': { id: 1, properties: { sku: 'SKU-2' } },
    });

    render(<AssetMetadataPanel asset={{ id: 1, folder_id: 9, properties: { applied_schema_id: 5, sku: 'SKU-1' } }} onAssetUpdated={onAssetUpdated} />);

    expect(await screen.findByText('Product Schema')).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('SKU'), { target: { value: 'SKU-2' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    await waitFor(() => {
      const patchCall = global.fetch.mock.calls.find(([url]) => String(url) === '/api/v1/assets/1/metadata');
      expect(patchCall).toBeTruthy();
      expect(JSON.parse(patchCall[1].body)).toEqual({ schema_id: 5, metadata: { applied_schema_id: 5, sku: 'SKU-2' } });
    });
    expect(onAssetUpdated).toHaveBeenCalledWith({ id: 1, properties: { sku: 'SKU-2' } });
  });

  it('pre-fills schema fields from the asset-scoped metadata_schema endpoint', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/assets/2/metadata_schema': {
        id: 5,
        name: 'Image Schema',
        applied_schema_id: 5,
        resolved_tabs: [
          {
            id: 'basic',
            name: 'Basic',
            fields: [
              { id: 'creator', label: 'Creator', field_type: 'text', map_to_property: 'dc:creator', value: 'Jane Photographer' },
              { id: 'make', label: 'Camera Make', field_type: 'text', map_to_property: 'tiff:Make', value: 'Canon' },
            ],
          },
        ],
      },
    });

    render(
      <AssetMetadataPanel
        asset={{ id: 2, folder_id: 9, properties: { applied_schema_id: 5 } }}
        onAssetUpdated={jest.fn()}
      />
    );

    expect(await screen.findByText('Image Schema')).toBeInTheDocument();
    expect(screen.getByLabelText('Creator')).toHaveValue('Jane Photographer');
    expect(screen.getByLabelText('Camera Make')).toHaveValue('Canon');
  });

  it('lets a user edit values for fields inherited from a system/root schema, but keeps fields explicitly flagged read_only locked', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/assets/4/metadata_schema': {
        id: 6,
        name: 'Image Schema',
        applied_schema_id: 6,
        resolved_tabs: [
          {
            id: 'basic',
            name: 'Basic',
            inherited: true,
            schema_name: 'Default',
            fields: [
              { id: 'title', label: 'Title', field_type: 'text', map_to_property: 'dc:title', inherited: true, schema_name: 'Default', value: '' },
              { id: 'checksum', label: 'Checksum', field_type: 'text', map_to_property: 'sys:checksum', inherited: true, schema_name: 'Default', read_only: true, value: 'abc123' },
            ],
          },
        ],
      },
    });

    render(
      <AssetMetadataPanel
        asset={{ id: 4, folder_id: 9, properties: { applied_schema_id: 6 } }}
        onAssetUpdated={jest.fn()}
      />
    );

    expect(await screen.findByText('Image Schema')).toBeInTheDocument();

    // Inherited-but-not-read_only field: editable.
    const titleField = screen.getByLabelText(/Title/);
    expect(titleField).not.toBeDisabled();
    fireEvent.change(titleField, { target: { value: 'My New Title' } });
    expect(titleField).toHaveValue('My New Title');

    // Explicitly read_only field: still locked regardless of being inherited.
    const checksumField = screen.getByLabelText(/Checksum/);
    expect(checksumField).toBeDisabled();
  });

  it('falls back to client-side embedded mapping when the asset endpoint is unavailable', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/assets/3/metadata_schema': { ok: false, json: () => Promise.resolve({}) },
      'GET /api/v1/metadata_schemas/5': {
        id: 5,
        name: 'Image Schema',
        resolved_tabs: [
          {
            id: 'basic',
            name: 'Basic',
            fields: [
              { id: 'creator', label: 'Creator', field_type: 'text', map_to_property: 'dc:creator' },
              { id: 'make', label: 'Camera Make', field_type: 'text', map_to_property: 'tiff:Make' },
            ],
          },
        ],
      },
    });

    render(
      <AssetMetadataPanel
        asset={{
          id: 3,
          folder_id: 9,
          properties: {
            applied_schema_id: 5,
            embedded_metadata: {
              XMP: { Creator: 'Jane Photographer' },
              EXIF: { Make: 'Canon' },
            },
          },
        }}
        onAssetUpdated={jest.fn()}
      />
    );

    expect(await screen.findByText('Image Schema')).toBeInTheDocument();
    expect(screen.getByLabelText('Creator')).toHaveValue('Jane Photographer');
    expect(screen.getByLabelText('Camera Make')).toHaveValue('Canon');
  });

  it('renders AssetStatsPopover with real usage counts fetched from the API, in a popover triggered from the toolbar', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/assets/1/stats': { views: 12, downloads: 4, shares: 1 },
    });

    render(<AssetStatsPopover asset={{ id: 1 }} />);

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/api/v1/assets/1/stats'));

    fireEvent.click(screen.getByTestId('asset-stats-toggle'));

    expect(await screen.findByText('Asset Statistics')).toBeInTheDocument();
    expect(screen.getByText('Views')).toBeInTheDocument();
    expect(screen.getByText('Downloads')).toBeInTheDocument();
    expect(screen.getByText('Shares')).toBeInTheDocument();
    expect(screen.getByText('12')).toBeInTheDocument();
    expect(screen.getByText('4')).toBeInTheDocument();
    expect(screen.getByText('1')).toBeInTheDocument();
  });

  it('runs AI scan in AssetTagsEditor and saves updated tags', async () => {
    jest.useFakeTimers();
    const onSave = jest.fn();
    render(
      <AssetTagsEditor
        asset={{ id: 1, title: 'Portrait', url: '/portrait.jpg', properties: { tags: ['Manual'], ai_tags: { faces: [], text: [], general: [] } } }}
        open
        onClose={jest.fn()}
        onSave={onSave}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Run Smart Scan' }));
    await act(async () => {
      jest.advanceTimersByTime(2000);
    });

    expect(await screen.findByText('Unnamed Person 1')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Save Changes' }));
    expect(onSave).toHaveBeenCalledWith(expect.objectContaining({
      properties: expect.objectContaining({
        tags: ['Manual'],
        ai_tags: expect.objectContaining({ faces: ['Unnamed Person 1'] }),
      }),
    }));
  });

  it('renders AssetVersionsTab versions and restores an older version', async () => {
    const onAssetUpdated = jest.fn();
    global.fetch = mockFetch({
      'GET /api/v1/assets/1/versions': { versions: [
        { id: 'v2', version_number: 2, action_type: 'Edited', is_active: true, created_at: '2024-01-02', created_by: 'Alice', size: '2 MB', preview_url: '/preview-v2.png' },
        { id: 'v1', version_number: 1, action_type: 'Original Upload', is_active: false, created_at: '2024-01-01', created_by: 'Bob', size: '1 MB', preview_url: '/preview-v1.png' },
      ] },
      'POST /api/v1/assets/1/versions/v1/restore': {},
    });

    render(<AssetVersionsTab asset={{ id: 1 }} onAssetUpdated={onAssetUpdated} />);

    expect(await screen.findByText('Original Upload')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Restore' }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/assets/1/versions/v1/restore', expect.objectContaining({ method: 'POST' }));
    });
    expect(onAssetUpdated).toHaveBeenCalled();
    expect(mockNotify).toHaveBeenCalledWith('Asset successfully rolled back to selected version.', 'success');
  });

  it('enters AssetVersionsTab compare mode and renders the diff overlay canvas', async () => {
    const canvasContext = buildCanvasContext();
    const getContextSpy = jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => canvasContext);

    global.fetch = mockFetch({
      'GET /api/v1/assets/1/versions': { versions: [
        { id: 'v2', version_number: 2, action_type: 'Edited', is_active: true, created_at: '2024-01-02', created_by: 'Alice', size: '2 MB', preview_url: '/preview-v2.png' },
        { id: 'v1', version_number: 1, action_type: 'Original Upload', is_active: false, created_at: '2024-01-01', created_by: 'Bob', size: '1 MB', preview_url: '/preview-v1.png' },
      ] },
    });

    render(<AssetVersionsTab asset={{ id: 1 }} onAssetUpdated={jest.fn()} />);

    expect(await screen.findByText('Original Upload')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('checkbox', { name: 'Compare v2' }));
    fireEvent.click(screen.getByRole('checkbox', { name: 'Compare v1' }));
    fireEvent.click(screen.getByRole('button', { name: 'Compare selected' }));

    expect(await screen.findByText('Comparing v2 against v1')).toBeInTheDocument();
    await waitFor(() => expect(canvasContext.getImageData).toHaveBeenCalledTimes(2));
    expect(screen.getByLabelText('Show diff overlay')).toBeInTheDocument();
    expect(screen.getByTestId('version-diff-overlay-canvas')).toBeInTheDocument();

    getContextSpy.mockRestore();
  });

  it('falls back to side-by-side AssetVersionsTab compare mode when canvas diff access is blocked', async () => {
    const canvasContext = buildCanvasContext({ throwSecurityError: true });
    const getContextSpy = jest.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => canvasContext);

    global.fetch = mockFetch({
      'GET /api/v1/assets/1/versions': { versions: [
        { id: 'v2', version_number: 2, action_type: 'Edited', is_active: true, created_at: '2024-01-02', created_by: 'Alice', size: '2 MB', preview_url: 'https://cdn.example.com/preview-v2.png' },
        { id: 'v1', version_number: 1, action_type: 'Original Upload', is_active: false, created_at: '2024-01-01', created_by: 'Bob', size: '1 MB', preview_url: 'https://cdn.example.com/preview-v1.png' },
      ] },
    });

    render(<AssetVersionsTab asset={{ id: 1 }} onAssetUpdated={jest.fn()} />);

    expect(await screen.findByText('Original Upload')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('checkbox', { name: 'Compare v2' }));
    fireEvent.click(screen.getByRole('checkbox', { name: 'Compare v1' }));
    fireEvent.click(screen.getByRole('button', { name: 'Compare selected' }));

    expect(await screen.findByText(/cross-origin canvas access/i)).toBeInTheDocument();
    expect(screen.getByAltText('Version 2 preview')).toBeInTheDocument();
    expect(screen.getByAltText('Version 1 preview')).toBeInTheDocument();
    expect(screen.queryByTestId('version-diff-overlay-canvas')).not.toBeInTheDocument();

    getContextSpy.mockRestore();
  });

  it('renders AssetViewer info and copies the asset URL', async () => {
    const asset = {
      id: 11,
      title: 'Viewer Asset',
      url: '/viewer.jpg',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: {
        content_type: 'image/jpeg',
        file_size: '4 MB',
        resolution: '1200x800',
        tags: ['hero'],
        ai_tags: { faces: ['person'], text: ['SALE'], general: [] },
        color_palette: ['#123456'],
        creator: ['Andy Thoma'],
        copyright: 'ALDI US',
        camera_make: 'NIKON CORPORATION',
        camera_model: 'NIKON D850',
        lens: 'Nikon AF-S NIKKOR 24-70mm f/2.8E ED VR',
        color_mode: 'CMYK',
        metadata_field_count: 89,
        embedded_metadata: { XMP: { Creator: ['Andy Thoma'] }, EXIF: { Make: 'NIKON CORPORATION' } },
      },
    };

    render(<AssetViewer asset={asset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByText('General Metadata')).toBeInTheDocument();
    expect(screen.getByText('3 tags')).toBeInTheDocument();
    expect(screen.getByText('Creator')).toBeInTheDocument();
    expect(screen.getByText('Andy Thoma')).toBeInTheDocument();
    expect(screen.getByText('NIKON CORPORATION NIKON D850')).toBeInTheDocument();
    expect(screen.getByText('Nikon AF-S NIKKOR 24-70mm f/2.8E ED VR')).toBeInTheDocument();
    expect(screen.getByText('CMYK')).toBeInTheDocument();
    expect(screen.getByText('89')).toBeInTheDocument();
    fireEvent.click(iconButton('ContentCopyIcon'));

    await waitFor(() => expect(navigator.clipboard.writeText).toHaveBeenCalledWith('/viewer.jpg'));
    expect(mockNotify).toHaveBeenCalledWith('Asset URL copied to clipboard!', 'success');
  });

  it('collapses the EXIF / IPTC / XMP Data section by default and expands it on click', () => {
    const asset = {
      id: 11,
      title: 'Viewer Asset',
      url: '/viewer.jpg',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: {
        content_type: 'image/jpeg',
        embedded_metadata: { XMP: { Creator: ['Andy Thoma'] }, EXIF: { Make: 'NIKON CORPORATION' } },
      },
    };

    render(<AssetViewer asset={asset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByText('EXIF / IPTC / XMP Data')).toBeInTheDocument();
    // Collapsed by default: the raw JSON dump isn't rendered/visible yet.
    expect(screen.queryByText(/NIKON CORPORATION/)).not.toBeInTheDocument();

    fireEvent.click(screen.getByText('EXIF / IPTC / XMP Data'));

    expect(screen.getByText(/NIKON CORPORATION/)).toBeInTheDocument();
  });

  it('collapses the Raw Metadata section by default and expands/collapses it on click', async () => {
    const asset = {
      id: 11,
      title: 'Viewer Asset',
      url: '/viewer.jpg',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: {
        content_type: 'image/jpeg',
        embedded_metadata: { XMP: { Creator: ['Andy Thoma'] } },
        raw_test_marker: 'RAWMARKERXYZ',
      },
    };

    render(<AssetViewer asset={asset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByText('Raw Metadata')).toBeInTheDocument();
    // Collapsed by default: the raw JSON dump isn't rendered/visible yet.
    expect(screen.queryByText(/RAWMARKERXYZ/)).not.toBeInTheDocument();

    fireEvent.click(screen.getByText('Raw Metadata'));

    expect(screen.getByText(/RAWMARKERXYZ/)).toBeInTheDocument();

    fireEvent.click(screen.getByLabelText(/collapse raw metadata/i));

    await waitFor(() => expect(screen.queryByText(/RAWMARKERXYZ/)).not.toBeInTheDocument());
  });

  it('shows a fallback message in Raw Metadata when the asset has no properties', () => {
    const asset = {
      id: 11,
      title: 'Viewer Asset',
      url: '/viewer.jpg',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: {},
    };

    render(<AssetViewer asset={asset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    fireEvent.click(screen.getByText('Raw Metadata'));

    expect(screen.getByText('No raw metadata available.')).toBeInTheDocument();
  });

  it('renders the interactive Asset3DViewer (not the plain <img> preview) for a 3D model asset', () => {
    const glbAsset = {
      id: 14,
      title: 'Product Hero.glb',
      url: '/product-hero.glb',
      preview_url: '/product-hero.glb',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: { content_type: 'model/gltf-binary', size: 4 * 1024 * 1024 },
    };

    render(<AssetViewer asset={glbAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByTestId('asset-3d-viewer')).toBeInTheDocument();
    expect(screen.getByTestId('asset-3d-model-viewer')).toBeInTheDocument();
    expect(document.querySelector('img[src="/product-hero.glb"]')).not.toBeInTheDocument();
  });

  it('shows the Download Original fallback (not a broken viewer) for USDZ assets in the Asset viewer', () => {
    const usdzAsset = {
      id: 15,
      title: 'AR Model.usdz',
      url: '/ar-model.usdz',
      preview_url: '/ar-model.usdz',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: { content_type: 'model/vnd.usdz+zip', size: 2 * 1024 * 1024 },
    };

    render(<AssetViewer asset={usdzAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByTestId('asset-3d-viewer-download-fallback')).toBeInTheDocument();
    expect(screen.queryByTestId('asset-3d-model-viewer')).not.toBeInTheDocument();
  });

  it('renders a native <video> player (poster + controls) for an MP4 video asset', () => {
    const mp4Asset = {
      id: 16,
      title: 'Product Demo.mp4',
      url: '/product-demo.mp4',
      preview_url: '/product-demo.mp4',
      video_poster_url: '/product-demo-poster.jpg',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: { content_type: 'video/mp4', size: 8 * 1024 * 1024 },
    };

    render(<AssetViewer asset={mp4Asset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    const player = screen.getByTestId('asset-viewer-video-player');
    expect(player).toBeInTheDocument();
    expect(player).toHaveAttribute('src', '/product-demo.mp4');
    expect(player).toHaveAttribute('poster', '/product-demo-poster.jpg');
    expect(player).toHaveAttribute('controls');
  });

  it('plays a non-native video format (QuickTime) via its transcoded MP4 rendition when available', () => {
    const movAsset = {
      id: 17,
      title: 'Legacy Clip.mov',
      url: '/legacy-clip.mov',
      video_mp4_rendition_url: '/legacy-clip-rendition.mp4',
      video_poster_url: '/legacy-clip-poster.jpg',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: { content_type: 'video/quicktime', size: 8 * 1024 * 1024 },
    };

    render(<AssetViewer asset={movAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    const player = screen.getByTestId('asset-viewer-video-player');
    expect(player).toHaveAttribute('src', '/legacy-clip-rendition.mp4');
  });

  it('shows a transcoding-required fallback (with Download Original) for a non-native video format with no MP4 rendition yet', () => {
    const movAsset = {
      id: 18,
      title: 'Untranscoded Clip.mov',
      url: '/untranscoded-clip.mov',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: { content_type: 'video/quicktime', size: 8 * 1024 * 1024 },
    };

    render(<AssetViewer asset={movAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.queryByTestId('asset-viewer-video-player')).not.toBeInTheDocument();
    expect(screen.getByText(/Video preview isn't available for this format yet/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Download Original/i })).toBeInTheDocument();
  });

  it('falls back to the native MP4 source when the browser cannot decode AV1, even if an AV1 rendition exists', () => {
    const mp4Asset = {
      id: 19,
      title: 'Product Demo.mp4',
      url: '/product-demo.mp4',
      preview_url: '/product-demo.mp4',
      video_poster_url: '/product-demo-poster.jpg',
      video_av1_rendition_url: '/product-demo-rendition.webm',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: { content_type: 'video/mp4', size: 8 * 1024 * 1024 },
    };

    render(<AssetViewer asset={mp4Asset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    const player = screen.getByTestId('asset-viewer-video-player');
    expect(player).toHaveAttribute('src', '/product-demo.mp4');
  });

  it('prefers the AV1/WebM rendition over the MP4/native source when the browser can decode AV1', () => {
    const originalCanPlayType = window.HTMLMediaElement.prototype.canPlayType;
    window.HTMLMediaElement.prototype.canPlayType = (type) =>
      (type && type.includes('av01') ? 'probably' : '');

    try {
      const mp4Asset = {
        id: 20,
        title: 'Product Demo.mp4',
        url: '/product-demo.mp4',
        preview_url: '/product-demo.mp4',
        video_poster_url: '/product-demo-poster.jpg',
        video_av1_rendition_url: '/product-demo-rendition.webm',
        created_at: '2024-01-01T10:00:00Z',
        status: 'approved',
        properties: { content_type: 'video/mp4', size: 8 * 1024 * 1024 },
      };

      render(<AssetViewer asset={mp4Asset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

      const player = screen.getByTestId('asset-viewer-video-player');
      expect(player).toHaveAttribute('src', '/product-demo-rendition.webm');
    } finally {
      window.HTMLMediaElement.prototype.canPlayType = originalCanPlayType;
    }
  });

  it('shows the download-to-view fallback (not a broken <img>) for a Camera RAW image with no server-generated preview', () => {
    const rawAsset = {
      id: 21,
      title: 'DSC_0001.nef',
      url: '/dsc_0001.nef',
      preview_url: null,
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: { content_type: 'image/x-raw-nikon', size: 24 * 1024 * 1024 },
    };

    render(<AssetViewer asset={rawAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByText(/Preview not available for this file type/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Download Original/i })).toBeInTheDocument();
    expect(screen.queryByRole('img', { name: 'DSC_0001.nef' })).not.toBeInTheDocument();
  });

  it('renders the flattened PNG preview (not a broken <img>) for a Camera RAW image once the backend generates one', () => {
    const rawAssetWithPreview = {
      id: 22,
      title: 'DSC_0002.nef',
      url: '/dsc_0002.nef',
      preview_url: '/dsc_0002-preview.png',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: {
        content_type: 'image/x-raw-nikon',
        preview_storage_path: 'uuid/v1_preview.png',
        preview_content_type: 'image/png',
        size: 24 * 1024 * 1024,
      },
    };

    render(<AssetViewer asset={rawAssetWithPreview} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByRole('img', { name: 'DSC_0002.nef' })).toHaveAttribute('src', expect.stringContaining('/dsc_0002-preview.png'));
  });

  it('shows the download-to-view fallback for a proprietary design-tool source file (Adobe XD/Figma/Sketch)', () => {
    const xdAsset = {
      id: 23,
      title: 'Homepage.xd',
      url: '/homepage.xd',
      preview_url: null,
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: { content_type: 'application/vnd.adobe.xd', format: 'Design Source File', size: 4 * 1024 * 1024 },
    };

    render(<AssetViewer asset={xdAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByText(/Preview not available for this file type/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Download Original/i })).toBeInTheDocument();
  });

  it('renders the flattened PNG preview for a Word document once LibreOffice generates one', () => {
    const docxAsset = {
      id: 24,
      title: 'Quarterly-Report.docx',
      url: '/report.docx',
      preview_url: '/report-preview.png',
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: {
        content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        format: 'Office Document',
        document_type: 'Word Document',
        preview_storage_path: 'uuid/v1_preview.png',
        preview_content_type: 'image/png',
        size: 2 * 1024 * 1024,
      },
    };

    render(<AssetViewer asset={docxAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByRole('img', { name: 'Quarterly-Report.docx' })).toHaveAttribute('src', expect.stringContaining('/report-preview.png'));
  });

  it('shows the download-to-view fallback for an Excel spreadsheet with no LibreOffice-generated preview', () => {
    const xlsxAsset = {
      id: 25,
      title: 'Budget.xlsx',
      url: '/budget.xlsx',
      preview_url: null,
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: {
        content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        format: 'Office Document',
        document_type: 'Excel Spreadsheet',
        document_conversion_available: false,
        size: 512 * 1024,
      },
    };

    render(<AssetViewer asset={xlsxAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByText(/Preview not available for this file type/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Download Original/i })).toBeInTheDocument();
  });

  it('shows the download-to-view fallback for an Apple Keynote presentation (no rasteriser available)', () => {
    const keyAsset = {
      id: 26,
      title: 'Pitch-Deck.key',
      url: '/pitch.key',
      preview_url: null,
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: {
        content_type: 'application/vnd.apple.keynote',
        format: 'Apple iWork Document',
        document_type: 'Keynote Presentation',
        size: 8 * 1024 * 1024,
      },
    };

    render(<AssetViewer asset={keyAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByText(/Preview not available for this file type/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Download Original/i })).toBeInTheDocument();
  });

  it('renders an inline text preview for a .txt document', () => {
    const txtAsset = {
      id: 27,
      title: 'ReadMe.txt',
      url: '/readme.txt',
      preview_url: null,
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: {
        content_type: 'text/plain',
        format: 'Plain Text Document',
        document_type: 'Plain Text Document',
        text_preview: 'Hello world\nSecond line',
        text_preview_truncated: false,
        line_count: 2,
        size: 128,
      },
    };

    render(<AssetViewer asset={txtAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByTestId('asset-viewer-text-preview')).toHaveTextContent('Hello world');
    expect(screen.queryByText(/Preview truncated/i)).not.toBeInTheDocument();
  });

  it('renders an inline text preview with a truncation notice for a large .csv document', () => {
    const csvAsset = {
      id: 28,
      title: 'Export.csv',
      url: '/export.csv',
      preview_url: null,
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: {
        content_type: 'text/csv',
        format: 'Plain Text Document',
        document_type: 'CSV Spreadsheet',
        text_preview: 'name,age\nAlice,30',
        text_preview_truncated: true,
        line_count: 50000,
        size: 5 * 1024 * 1024,
      },
    };

    render(<AssetViewer asset={csvAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByTestId('asset-viewer-text-preview')).toHaveTextContent('name,age');
    expect(screen.getByText(/Preview truncated/i)).toBeInTheDocument();
  });

  it('shows the download-to-view fallback for a plain-text document with no extracted text_preview', () => {
    const noPreviewTxtAsset = {
      id: 29,
      title: 'Locked.txt',
      url: '/locked.txt',
      preview_url: null,
      created_at: '2024-01-01T10:00:00Z',
      status: 'approved',
      properties: { content_type: 'text/plain', format: 'Plain Text Document', size: 128 },
    };

    render(<AssetViewer asset={noPreviewTxtAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);

    expect(screen.getByText(/Preview not available for this file type/i)).toBeInTheDocument();
    expect(screen.queryByTestId('asset-viewer-text-preview')).not.toBeInTheDocument();
  });

  it('enables Edit Image for web-renderable formats and disables it for PSD (relies on the backend `editable` flag)', () => {
    const jpegAsset = {
      id: 12,
      title: 'Photo.jpg',
      url: '/photo.jpg',
      preview_url: '/photo.jpg',
      editable: true,
      properties: { content_type: 'image/jpeg' },
    };
    const { unmount } = render(<AssetViewer asset={jpegAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);
    expect(screen.getByRole('button', { name: /Edit Image/i })).toBeEnabled();
    unmount();

    const psdAsset = {
      id: 13,
      title: 'Artwork.psd',
      url: '/artwork.psd',
      preview_url: '/artwork-preview.png',
      editable: false,
      properties: { content_type: 'image/vnd.adobe.photoshop', preview_storage_path: 'previews/artwork.png' },
    };
    render(<AssetViewer asset={psdAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);
    expect(screen.getByRole('button', { name: /Edit Image/i })).toBeDisabled();
  });

  it('falls back to a client-side content-type check for Edit Image when the backend `editable` flag is absent', () => {
    const tiffAsset = {
      id: 14,
      title: 'Scan.tiff',
      url: '/scan.tiff',
      properties: { content_type: 'image/tiff', preview_storage_path: 'previews/scan.png' },
    };
    render(<AssetViewer asset={tiffAsset} open onClose={jest.fn()} onAssetUpdated={jest.fn()} />);
    expect(screen.getByRole('button', { name: /Edit Image/i })).toBeDisabled();
  });

  it('supports legacy duplicate resolution with AI merge', async () => {
    jest.useFakeTimers();
    const onResolve = jest.fn();
    render(
      <DuplicateResolverDialog
        open
        onClose={jest.fn()}
        fileData={{
          id: 'file-1',
          preview: '/new.jpg',
          meta: { title: 'Upload.jpg' },
          duplicateData: [{ id: 5, title: 'Existing', url: '/existing.jpg', folderName: 'Root' }],
        }}
        onResolve={onResolve}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Merge Metadata' }));
    await act(async () => {
      jest.advanceTimersByTime(1500);
    });

    expect(onResolve).toHaveBeenCalledWith('file-1', 'skip');
  });

  it('flags a legacy duplicate match that lives in the Recycle Bin with a Bin chip, matching Search results', () => {
    render(
      <DuplicateResolverDialog
        open
        onClose={jest.fn()}
        fileData={{
          id: 'file-2',
          preview: '/new.jpg',
          meta: { title: 'Upload.jpg' },
          duplicateData: [
            { id: 5, title: 'Binned Existing', url: '/existing.jpg', folderName: 'Root', in_bin: true },
            { id: 6, title: 'Binned Existing', url: '/existing2.jpg', folderName: 'Archive', in_bin: false },
          ],
        }}
        onResolve={jest.fn()}
      />,
    );

    // One Bin chip for the primary asset's image badge, one for the binned
    // location chip — the active (non-bin) location must NOT get a chip.
    // (Jest's i18n test bundle is empty, so the raw translation key renders.)
    expect(screen.getAllByText('search.binBadge')).toHaveLength(2);
  });

  it('loads duplicate assets and can ignore them in DuplicateResolverDialog asset mode', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/assets/4/duplicates': {
        duplicates: [{ id: 8, title: 'Copy', similarity_type: 'exact', similarity_score: 100, size: 1024, folder_name: 'Archive', url: '/copy.jpg' }],
      },
      'PATCH /api/v1/assets/4': {},
    });

    render(<DuplicateResolverDialog open onClose={jest.fn()} asset={{ id: 4, title: 'Source', properties: { ignored_duplicate_asset_ids: [] } }} />);

    expect(await screen.findByText('Copy')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'folders.duplicates.ignore_all' }));

    await waitFor(() => {
      const patchCall = global.fetch.mock.calls.find(([url, options]) => String(url) === '/api/v1/assets/4' && options.method === 'PATCH');
      expect(patchCall).toBeTruthy();
    });
    expect(mockNotify).toHaveBeenCalledWith('folders.duplicates.ignore_all', 'success');
  });

  it('renders ExplorerTopBar navigation and smart actions', async () => {
    const handleCopyPath = jest.fn();
    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{ breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }], folders: [{ id: 13, name: 'Child' }], assets: [{ id: 20, title: 'Asset' }] }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={handleCopyPath}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [], assets: [20] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(iconButton('ContentCopyIcon'));
    expect(handleCopyPath).toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.smartActions' }));
    fireEvent.click(await screen.findByText('explorerTopBar.autoTagEnrich'));
    expect(mockNotify).toHaveBeenCalledWith('explorerTopBar.notifications.autoEnrichQueued', 'info');
  });

  it('renames a single selected folder via the Tools menu Rename overlay', async () => {
    global.fetch = mockFetch({
      'PATCH /api/v1/folders/13': { id: 13, name: 'Renamed Folder', slug: 'renamed-folder', updated_at: '2024-01-01' },
    });
    const onSchemaApplied = jest.fn();

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{ breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }], folders: [{ id: 13, name: 'Child', can_modify: true }], assets: [] }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [] }}
        onSchemaApplied={onSchemaApplied}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    fireEvent.click(await screen.findByText('explorerTopBar.renameFolder'));

    const input = await screen.findByLabelText('renameDialog.newNameLabel');
    fireEvent.change(input, { target: { value: 'Renamed Folder' } });
    fireEvent.click(screen.getByRole('button', { name: 'renameDialog.save' }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/v1/folders/13',
        expect.objectContaining({
          method: 'PATCH',
          body: JSON.stringify({ folder: { name: 'Renamed Folder' } }),
        }),
      );
    });
    expect(onSchemaApplied).toHaveBeenCalled();
  });

  it('renames a single selected asset via the Tools menu Rename overlay', async () => {
    global.fetch = mockFetch({
      'PATCH /api/v1/assets/20': { id: 20, title: 'New Title' },
    });

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{ breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }], folders: [], assets: [{ id: 20, title: 'Old Title', can_modify: true }] }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [], assets: [20] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    fireEvent.click(await screen.findByText('explorerTopBar.renameAsset'));

    const input = await screen.findByLabelText('renameDialog.newNameLabel');
    fireEvent.change(input, { target: { value: 'New Title' } });
    fireEvent.click(screen.getByRole('button', { name: 'renameDialog.save' }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/v1/assets/20',
        expect.objectContaining({
          method: 'PATCH',
          body: JSON.stringify({ asset: { title: 'New Title' } }),
        }),
      );
    });
  });

  it('disables Rename in the Tools menu when the selected item lacks modify rights', async () => {
    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{ breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }], folders: [{ id: 13, name: 'Child', can_modify: false }], assets: [] }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    const renameItem = (await screen.findByText('explorerTopBar.renameFolder')).closest('li');
    expect(renameItem).toHaveAttribute('aria-disabled', 'true');
  });

  it('hides the Rename option entirely when more than one item is selected', async () => {
    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{ breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }], folders: [{ id: 13, name: 'Child', can_modify: true }], assets: [{ id: 20, title: 'Asset', can_modify: true }] }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [20] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    expect(screen.queryByText('explorerTopBar.renameFolder')).not.toBeInTheDocument();
    expect(screen.queryByText('explorerTopBar.renameAsset')).not.toBeInTheDocument();
  });

  it('moves a mixed multi-selection (folders + assets) via the Tools menu Move overlay', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/folders': { folders: [ { id: 99, name: '/Marketing', slug: 'marketing' } ] },
      'POST /api/v1/move_operations': { success: true, moved_folders: 1, moved_assets: 1, errors: [] },
    });
    const onSchemaApplied = jest.fn();

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{
          breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }],
          folders: [{ id: 13, name: 'Child', can_delete: true }],
          assets: [{ id: 20, title: 'Asset', can_delete: true }],
        }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [20] }}
        onSchemaApplied={onSchemaApplied}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    fireEvent.click(await screen.findByText('explorerTopBar.moveItems'));

    // Selected-items summary should list both the folder and the asset.
    expect(await screen.findByText('Child')).toBeInTheDocument();
    expect(screen.getByText('Asset')).toBeInTheDocument();

    const destinationInput = await screen.findByLabelText('moveDialog.destinationLabel');
    fireEvent.change(destinationInput, { target: { value: 'Marketing' } });
    fireEvent.click(await screen.findByText('/Marketing'));

    fireEvent.click(screen.getByRole('button', { name: 'moveDialog.move' }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/v1/move_operations',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({ folder_ids: [ 13 ], asset_ids: [ 20 ], destination_folder_id: 99 }),
        }),
      );
    });
    await waitFor(() => expect(onSchemaApplied).toHaveBeenCalled());
  });

  it('moves an item to the root destination', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/folders': { folders: [] },
      'POST /api/v1/move_operations': { success: true, moved_folders: 1, moved_assets: 0, errors: [] },
    });

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{
          breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }],
          folders: [{ id: 13, name: 'Child', can_delete: true }],
          assets: [],
        }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    fireEvent.click(await screen.findByText('explorerTopBar.moveItems'));

    const destinationInput = await screen.findByLabelText('moveDialog.destinationLabel');
    fireEvent.change(destinationInput, { target: { value: 'moveDialog.rootOption' } });
    fireEvent.click(await screen.findByText('moveDialog.rootOption'));

    fireEvent.click(screen.getByRole('button', { name: 'moveDialog.move' }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/v1/move_operations',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({ folder_ids: [ 13 ], asset_ids: [], destination_folder_id: 'root' }),
        }),
      );
    });
  });

  it('disables Move in the Tools menu when any selected item lacks delete rights', async () => {
    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{
          breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }],
          folders: [{ id: 13, name: 'Child', can_delete: false }],
          assets: [{ id: 20, title: 'Asset', can_delete: true }],
        }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [20] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    const moveItem = (await screen.findByText('explorerTopBar.moveItems')).closest('li');
    expect(moveItem).toHaveAttribute('aria-disabled', 'true');
  });

  it('shows a partial-failure warning in MoveDialog when some items cannot be moved', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/folders': { folders: [ { id: 99, name: '/Marketing', slug: 'marketing' } ] },
      'POST /api/v1/move_operations': {
        success: false,
        moved_folders: 1,
        moved_assets: 0,
        errors: [ { type: 'asset', id: 20, name: 'Asset', error: 'You do not have permission to move this asset.' } ],
      },
    });

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{
          breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }],
          folders: [{ id: 13, name: 'Child', can_delete: true }],
          assets: [{ id: 20, title: 'Asset', can_delete: true }],
        }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [20] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    fireEvent.click(await screen.findByText('explorerTopBar.moveItems'));

    const destinationInput = await screen.findByLabelText('moveDialog.destinationLabel');
    fireEvent.change(destinationInput, { target: { value: 'Marketing' } });
    fireEvent.click(await screen.findByText('/Marketing'));
    fireEvent.click(screen.getByRole('button', { name: 'moveDialog.move' }));

    expect(await screen.findByText('moveDialog.partialFailureTitle')).toBeInTheDocument();
    expect(await screen.findByText(/You do not have permission to move this asset\./)).toBeInTheDocument();
  });

  it('requires a destination before allowing MoveDialog submission (standalone)', async () => {
    global.fetch = mockFetch({ 'GET /api/v1/folders': { folders: [] } });
    const onClose = jest.fn();

    render(
      <MoveDialog
        open
        onClose={onClose}
        selectedItems={{ folders: [13], assets: [] }}
        itemNames={{ folders: { 13: 'Child' }, assets: {} }}
        currentFolderId={12}
      />,
    );

    const moveButton = await screen.findByRole('button', { name: 'moveDialog.move' });
    expect(moveButton).toBeDisabled();

    fireEvent.click(screen.getByRole('button', { name: 'common.cancel' }));
    expect(onClose).toHaveBeenCalledWith(false);
  });

  it('copies folders and assets to a destination via Tools > Copy', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/folders': { folders: [ { id: 99, name: '/Marketing', slug: 'marketing' } ] },
      'POST /api/v1/copy_operations': { success: true, copied_folders: 1, copied_assets: 1, errors: [] },
    });
    const onSchemaApplied = jest.fn();

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{
          breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }],
          folders: [{ id: 13, name: 'Child', can_delete: true }],
          assets: [{ id: 20, title: 'Asset', can_delete: true }],
        }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [20] }}
        onSchemaApplied={onSchemaApplied}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    fireEvent.click(await screen.findByText('explorerTopBar.copyItems'));

    const destinationInput = await screen.findByLabelText('copyDialog.destinationLabel');
    fireEvent.change(destinationInput, { target: { value: 'Marketing' } });
    fireEvent.click(await screen.findByText('/Marketing'));
    fireEvent.click(screen.getByRole('button', { name: 'copyDialog.copy' }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/v1/copy_operations',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({ folder_ids: [ 13 ], asset_ids: [ 20 ], destination_folder_id: 99 }),
        }),
      );
    });
    await waitFor(() => expect(onSchemaApplied).toHaveBeenCalled());
  });

  it('copies an item to the root destination', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/folders': { folders: [] },
      'POST /api/v1/copy_operations': { success: true, copied_folders: 1, copied_assets: 0, errors: [] },
    });

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{
          breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }],
          folders: [{ id: 13, name: 'Child', can_delete: true }],
          assets: [],
        }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    fireEvent.click(await screen.findByText('explorerTopBar.copyItems'));

    const destinationInput = await screen.findByLabelText('copyDialog.destinationLabel');
    fireEvent.change(destinationInput, { target: { value: 'copyDialog.rootOption' } });
    fireEvent.click(await screen.findByText('copyDialog.rootOption'));

    fireEvent.click(screen.getByRole('button', { name: 'copyDialog.copy' }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/v1/copy_operations',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({ folder_ids: [ 13 ], asset_ids: [], destination_folder_id: 'root' }),
        }),
      );
    });
  });

  it('never disables Copy in the Tools menu, even when a selected item lacks delete rights (unlike Move)', async () => {
    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{
          breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }],
          folders: [{ id: 13, name: 'Child', can_delete: false }],
          assets: [{ id: 20, title: 'Asset', can_delete: true }],
        }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [20] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    // Move is disabled (no delete rights on the folder)...
    const moveItem = (await screen.findByText('explorerTopBar.moveItems')).closest('li');
    expect(moveItem).toHaveAttribute('aria-disabled', 'true');
    // ...but Copy never removes anything from the source, so it stays enabled.
    const copyItem = (await screen.findByText('explorerTopBar.copyItems')).closest('li');
    expect(copyItem).not.toHaveAttribute('aria-disabled', 'true');
  });

  it('shows a partial-failure warning in CopyDialog when some items cannot be copied', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/folders': { folders: [ { id: 99, name: '/Marketing', slug: 'marketing' } ] },
      'POST /api/v1/copy_operations': {
        success: false,
        copied_folders: 1,
        copied_assets: 0,
        errors: [ { type: 'asset', id: 20, name: 'Asset', error: 'You do not have permission to copy this asset.' } ],
      },
    });

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{
          breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }],
          folders: [{ id: 13, name: 'Child', can_delete: true }],
          assets: [{ id: 20, title: 'Asset', can_delete: true }],
        }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [20] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.tools' }));
    fireEvent.click(await screen.findByText('explorerTopBar.copyItems'));

    const destinationInput = await screen.findByLabelText('copyDialog.destinationLabel');
    fireEvent.change(destinationInput, { target: { value: 'Marketing' } });
    fireEvent.click(await screen.findByText('/Marketing'));
    fireEvent.click(screen.getByRole('button', { name: 'copyDialog.copy' }));

    expect(await screen.findByText('copyDialog.partialFailureTitle')).toBeInTheDocument();
    expect(await screen.findByText(/You do not have permission to copy this asset\./)).toBeInTheDocument();
  });

  it('requires a destination before allowing CopyDialog submission (standalone)', async () => {
    global.fetch = mockFetch({ 'GET /api/v1/folders': { folders: [] } });
    const onClose = jest.fn();

    render(
      <CopyDialog
        open
        onClose={onClose}
        selectedItems={{ folders: [13], assets: [] }}
        itemNames={{ folders: { 13: 'Child' }, assets: {} }}
        currentFolderId={12}
      />,
    );

    const copyButton = await screen.findByRole('button', { name: 'copyDialog.copy' });
    expect(copyButton).toBeDisabled();

    fireEvent.click(screen.getByRole('button', { name: 'common.cancel' }));
    expect(onClose).toHaveBeenCalledWith(false);
  });

  it('sends the actual current selection (not a stale/incorrect reference) when forcing an Edge CDN sync', async () => {
    global.fetch = mockFetch({
      'POST /api/v1/edge_operations/sync': { success: true, message: 'Metadata sync initiated for 1 folders and 2 assets.' },
    });

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{ breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }], folders: [{ id: 13, name: 'Child' }], assets: [{ id: 20, title: 'Asset' }] }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [ 13 ], assets: [ 20, 21 ] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.edgeCdnOps' }));
    fireEvent.click(await screen.findByText('explorerTopBar.syncMetadataToCdn'));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/v1/edge_operations/sync',
        expect.objectContaining({
          method: 'POST',
          headers: expect.objectContaining({ 'X-CSRF-Token': 'test-csrf-token' }),
          body: JSON.stringify({ folders: [ 13 ], assets: [ 20, 21 ] }),
        }),
      );
    });
    expect(mockNotify).toHaveBeenCalledWith('explorerTopBar.notifications.forceSyncStarted', 'success');
  });

  it('sends the current selection when purging the Edge cache and surfaces a notification on failure', async () => {
    global.fetch = jest.fn(() => Promise.resolve({ ok: false, status: 422, json: () => Promise.resolve({ success: false, error: 'boom' }) }));

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{ breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }], folders: [], assets: [{ id: 20, title: 'Asset' }] }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [], assets: [ 20 ] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.edgeCdnOps' }));
    fireEvent.click(await screen.findByText('explorerTopBar.purgeEdgeCache'));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/v1/edge_operations/purge',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({ folders: [], assets: [ 20 ] }),
        }),
      );
    });
    expect(mockNotify).toHaveBeenCalledWith('boom', 'error');
  });

  it('triggers a workflow for the current selection via the Workflow button', async () => {
    global.fetch = mockFetch({
      'GET /workflows.json': [
        { id: 1, name: 'Brand Review', status: 'active', workflow_steps: [ {}, {} ] },
        { id: 2, name: 'Draft Workflow', status: 'draft', workflow_steps: [] },
      ],
      'POST /api/v1/workflows/bulk_trigger': { message: 'queued', queued: 3, workflow_id: 1 },
    });

    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{ breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }], folders: [{ id: 13, name: 'Child' }], assets: [{ id: 20, title: 'Asset' }] }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [13], assets: [20] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'explorerTopBar.workflow' }));

    // Only the active workflow should be listed
    expect(await screen.findByText('Brand Review')).toBeInTheDocument();
    expect(screen.queryByText('Draft Workflow')).not.toBeInTheDocument();

    fireEvent.click(screen.getByText('Brand Review'));
    fireEvent.click(screen.getByRole('button', { name: 'triggerWorkflowDialog.trigger' }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith(
        '/api/v1/workflows/bulk_trigger',
        expect.objectContaining({
          method: 'POST',
          body: JSON.stringify({ workflow_id: 1, asset_ids: [ 20 ], folder_ids: [ 13 ] }),
        }),
      );
    });
    expect(mockNotify).toHaveBeenCalledWith('triggerWorkflowDialog.queued', 'success');
  });

  it('hides the Workflow button entirely when nothing is selected', () => {
    render(
      <ExplorerTopBar
        currentId={12}
        viewData={{ breadcrumbs: [{ id: 'root', name: 'Home' }, { id: 12, name: 'Catalog' }], folders: [], assets: [] }}
        viewMode="active"
        setViewMode={jest.fn()}
        handleNavigate={jest.fn()}
        handleCopyPath={jest.fn()}
        isAllSelected={false}
        handleSelectAll={jest.fn()}
        hasSelection={false}
        handleDeleteSelected={jest.fn()}
        handleRestoreSelected={jest.fn()}
        handlePermanentDelete={jest.fn()}
        setOpenFolderDialog={jest.fn()}
        onUploadSuccess={jest.fn()}
        selectedItems={{ folders: [], assets: [] }}
        onSchemaApplied={jest.fn()}
      />,
    );

    expect(screen.queryByRole('button', { name: 'explorerTopBar.workflow' })).not.toBeInTheDocument();
  });

  it('renders FolderAccessTab policies and removes an explicit policy', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/folders/3/policies': {
        explicit_policies: [{ group_id: 7, group_name: 'Editors', read_access: true, modify_access: true }],
        inherited_policies: [{ group_id: 8, group_name: 'Viewers', read_access: true, source_folder_name: 'Root' }],
      },
      'DELETE /api/v1/folders/3/policies/7': {},
    });

    render(<FolderAccessTab folder={{ id: 3, name: 'Catalog' }} />);

    expect(await screen.findByText('Editors')).toBeInTheDocument();
    expect(screen.getByText('Viewers')).toBeInTheDocument();
    fireEvent.click(iconButton('DeleteOutlinedIcon'));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/api/v1/folders/3/policies/7', expect.objectContaining({ method: 'DELETE' })));
    expect(mockNotify).toHaveBeenCalledWith('folder.access.removed', 'success');
  });

  it('renders FolderInfoPanel and saves general folder details', async () => {
    const onFolderUpdated = jest.fn();
    global.fetch = mockFetch({
      'GET /api/v1/folders/9/profiles': { image_profile: null, video_profile: null, metadata_schema: null },
      'PATCH /api/v1/folders/9': { id: 9, name: 'Updated Folder', description: 'New description' },
    });

    render(<FolderInfoPanel folder={{ id: 9, name: 'Folder A', description: 'Old description', slug: 'folder-a', created_at: '2024-01-01' }} open onClose={jest.fn()} onFolderUpdated={onFolderUpdated} />);

    expect(await screen.findByText('Folder properties')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Edit' }));

    const nameInput = screen.getByDisplayValue('Folder A');
    const descriptionInput = screen.getByDisplayValue('Old description');
    fireEvent.change(nameInput, { target: { value: 'Updated Folder' } });
    fireEvent.change(descriptionInput, { target: { value: 'New description' } });
    fireEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    await waitFor(() => expect(onFolderUpdated).toHaveBeenCalledWith({ id: 9, name: 'Updated Folder', description: 'New description' }));
  });

  it('renders FoldersManager heading and mounts AssetExplorer', () => {
    render(<FoldersManager someProp="value" />);
    expect(screen.getByText('foldersManager.title')).toBeInTheDocument();
    expect(screen.getByTestId('asset-explorer')).toBeInTheDocument();
    expect(mockAssetExplorer).toHaveBeenCalledWith(expect.objectContaining({ someProp: 'value' }));
  });

  it('renders ImageEditorDialog and saves current adjustments', async () => {
    const onSave = jest.fn();
    global.fetch = mockFetch({
      'POST /api/v1/assets/21/process_image': { id: 21, version: 2 },
    });

    render(<ImageEditorDialog asset={{ id: 21, url: '/edit.jpg', properties: {} }} open onClose={jest.fn()} onSave={onSave} />);

    fireEvent.click(iconButton('RotateRightIcon'));
    fireEvent.click(screen.getByRole('button', { name: 'Export & Save' }));

    await waitFor(() => {
      const saveCall = global.fetch.mock.calls.find(([url]) => String(url) === '/api/v1/assets/21/process_image');
      expect(saveCall).toBeTruthy();
      expect(JSON.parse(saveCall[1].body).geometry.rotate).toBe(90);
    });
    expect(onSave).toHaveBeenCalledWith({ id: 21, version: 2 });
  });

  it('appends the cache-busting `v` param with `&` (not `?`) when asset.url already carries a query string', () => {
    // Regression test: `asset.url` returned by the backend (via
    // AssetUrlHelper#asset_url_for) always includes a `?version_id=...` query
    // string. The editor canvas used to hardcode `${asset.url}?v=...`, which
    // produced a malformed double-`?` URL (e.g. `...?version_id=1?v=2`) that
    // 404'd and broke the "Edit Image" feature entirely.
    render(<ImageEditorDialog asset={{ id: 21, url: '/api/v1/assets/local/21?version_id=9', version: 3, properties: {} }} open onClose={jest.fn()} onSave={jest.fn()} />);

    const img = screen.getByAltText('Editor Canvas');
    expect(img).toHaveAttribute('src', '/api/v1/assets/local/21?version_id=9&v=3');
  });

  it('renders PinToCollectionDialog and pins an asset to a collection', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/collections?asset_id=2': [
        { id: 1, name: 'Summer', slug: 'summer', collection_type: 'manual', pinned_for_asset: false, assets_count: 2 },
        { id: 2, name: 'Smart Picks', slug: 'smart-picks', collection_type: 'smart', pinned_for_asset: true, assets_count: 5 },
      ],
      'POST /api/v1/collections/summer/assets': {},
    });

    render(<PinToCollectionDialog open onClose={jest.fn()} asset={{ id: 2, title: 'Hero Asset' }} />);

    expect(await screen.findByText('Summer')).toBeInTheDocument();
    fireEvent.click(screen.getByText('Summer'));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/api/v1/collections/summer/assets', expect.objectContaining({ method: 'POST' })));
    expect(mockNotify).toHaveBeenCalledWith('Added to collection.', 'success');
  });

  it('shows a validation error in RenameDialog when the name is cleared and submitted', async () => {
    const onClose = jest.fn();
    render(<RenameDialog open onClose={onClose} targetType="folder" targetId={13} initialName="Old Name" />);

    const input = screen.getByLabelText('renameDialog.newNameLabel');
    fireEvent.change(input, { target: { value: '   ' } });
    // Save is disabled once the field is blank/whitespace-only.
    expect(screen.getByRole('button', { name: 'renameDialog.save' })).toBeDisabled();
  });

  it('disables Save in RenameDialog when the name is unchanged, and cancels without calling fetch', () => {
    const onClose = jest.fn();
    global.fetch = jest.fn();
    render(<RenameDialog open onClose={onClose} targetType="asset" targetId={20} initialName="Same Title" />);

    expect(screen.getByRole('button', { name: 'renameDialog.save' })).toBeDisabled();

    fireEvent.click(screen.getByRole('button', { name: 'common.cancel' }));
    expect(onClose).toHaveBeenCalledWith(false);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('surfaces a server error in RenameDialog without closing the dialog', async () => {
    global.fetch = jest.fn(() => Promise.resolve({ ok: false, status: 422, json: () => Promise.resolve({ errors: ['Name has already been taken'] }) }));
    const onClose = jest.fn();
    render(<RenameDialog open onClose={onClose} targetType="folder" targetId={13} initialName="Old Name" />);

    fireEvent.change(screen.getByLabelText('renameDialog.newNameLabel'), { target: { value: 'Duplicate Name' } });
    fireEvent.click(screen.getByRole('button', { name: 'renameDialog.save' }));

    expect(await screen.findByText('Name has already been taken')).toBeInTheDocument();
    expect(onClose).not.toHaveBeenCalledWith(true);
  });

  it('renders UploadGrid and triggers duplicate and AI actions', () => {
    const handleSingleFileAi = jest.fn();
    const onOpenDuplicate = jest.fn();
    render(
      <UploadGrid
        filesData={[{
          id: 'f1',
          selected: true,
          isDuplicate: true,
          preview: '/preview.jpg',
          status: 'ready',
          meta: { title: 'Hero.jpg', size: '1.20 MB', dimensions: '800 x 600', type: '', schemaId: 7, aiTags: [] },
        }]}
        setFilesData={jest.fn()}
        getRootProps={() => ({})}
        getInputProps={() => ({})}
        isDragActive={false}
        handleToggleSelectAll={jest.fn()}
        handleToggleSelectFile={jest.fn()}
        handleRemoveFile={jest.fn()}
        allSelected
        selectedCount={1}
        onClose={jest.fn()}
        globalMeta={{ imageType: '', schemaId: 7 }}
        schemaOptions={[{ id: 7, name: 'Product Images', slug: 'product-images' }]}
        handleSingleFileAi={handleSingleFileAi}
        onOpenDuplicate={onOpenDuplicate}
      />,
    );

    expect(screen.getByText('Staging Area')).toBeInTheDocument();
    expect(screen.getByText('1 of 1 selected')).toBeInTheDocument();
    fireEvent.click(screen.getByText('Duplicate Found'));
    expect(onOpenDuplicate).toHaveBeenCalled();

    fireEvent.click(iconButton('AutoAwesomeIcon'));
    expect(handleSingleFileAi).toHaveBeenCalledWith('f1');
  });

  it('renders a placeholder for non-web-renderable files without a preview', () => {
    render(
      <UploadGrid
        filesData={[{
          id: 'psd1',
          selected: true,
          isDuplicate: false,
          preview: null,
          file: { name: 'artwork.psd', type: 'image/vnd.adobe.photoshop' },
          status: 'ready',
          meta: { title: 'artwork.psd', size: '5.00 MB', dimensions: 'N/A', type: '', schemaId: 7, aiTags: [] },
        }]}
        setFilesData={jest.fn()}
        getRootProps={() => ({})}
        getInputProps={() => ({})}
        isDragActive={false}
        handleToggleSelectAll={jest.fn()}
        handleToggleSelectFile={jest.fn()}
        handleRemoveFile={jest.fn()}
        allSelected
        selectedCount={1}
        onClose={jest.fn()}
        globalMeta={{ imageType: '', schemaId: 7 }}
        schemaOptions={[{ id: 7, name: 'Product Images', slug: 'product-images' }]}
        handleSingleFileAi={jest.fn()}
        onOpenDuplicate={jest.fn()}
      />,
    );

    expect(screen.getByText('psd')).toBeInTheDocument();
    expect(screen.getByText('Preview generated after upload')).toBeInTheDocument();
  });

  it('renders UploadSidebar and triggers AI and upload actions', async () => {
    const handleAiGlobalAction = jest.fn();
    const handleUploadAll = jest.fn();
    render(
      <UploadSidebar
        globalMeta={{ collection: null, imageType: '', manualTags: [], aiTagsEnabled: true, schemaId: null }}
        setGlobalMeta={jest.fn()}
        handleGlobalSchemaChange={jest.fn()}
        schemaOptions={[{ id: 1, name: 'Product Schema' }]}
        collectionOptions={[{ id: 1, name: 'Summer' }]}
        handleAiGlobalAction={handleAiGlobalAction}
        isAiProcessing={false}
        filesData={[{ id: 'f1' }]}
        handleUploadAll={handleUploadAll}
        isUploading={false}
        selectedCount={1}
        onClose={jest.fn()}
      />,
    );

    expect(screen.getByText('Upload & Enrich')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Smart Describe Selected' }));
    expect(handleAiGlobalAction).toHaveBeenCalledWith('tag');

    fireEvent.click(screen.getByRole('button', { name: 'Upload (1)' }));
    expect(handleUploadAll).toHaveBeenCalled();
  });

  it('shows a batch upload progress bar while uploading', () => {
    render(
      <UploadSidebar
        globalMeta={{ collection: null, imageType: '', manualTags: [], aiTagsEnabled: true, schemaId: null }}
        setGlobalMeta={jest.fn()}
        handleGlobalSchemaChange={jest.fn()}
        schemaOptions={[]}
        collectionOptions={[]}
        handleAiGlobalAction={jest.fn()}
        isAiProcessing={false}
        filesData={[{ id: 'f1' }]}
        handleUploadAll={jest.fn()}
        isUploading
        uploadProgress={{ done: 2, total: 5 }}
        selectedCount={5}
        onClose={jest.fn()}
      />,
    );

    expect(screen.getByTestId('upload-progress')).toBeInTheDocument();
    expect(screen.getByText('2 of 5')).toBeInTheDocument();
    const bar = within(screen.getByTestId('upload-progress')).getByRole('progressbar');
    expect(bar).toHaveAttribute('aria-valuenow', '40');
  });

  it('loads UploadWorkspace dependencies, stages a dropped file, and uploads it', async () => {
    const onUploadComplete = jest.fn();
    global.fetch = mockFetch({
      'GET /api/v1/metadata_schemas': [{ id: 7, name: 'Product Images', slug: 'product-images', level: 'root' }],
      'GET /api/v1/upload_restrictions': { allowed_mime_types: ['image/*'] },
      'GET /api/v1/collections': [{ id: 1, name: 'Summer', slug: 'summer' }],
      'POST /api/v1/assets/check_hashes': { duplicates: {} },
      'POST /api/v1/assets': {},
    });

    render(<UploadWorkspace folderId={15} onClose={jest.fn()} onUploadComplete={onUploadComplete} />);

    await waitFor(() => expect(dropzoneOnDrop).toBeInstanceOf(Function));

    await act(async () => {
      await dropzoneOnDrop([new File(['file'], '0123-en-FR01.jpg', { type: 'image/jpeg' })]);
    });

    expect(await screen.findByDisplayValue('0123-en-FR01.jpg')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Upload (1)' }));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/api/v1/assets', expect.objectContaining({ method: 'POST' })));
    expect(onUploadComplete).toHaveBeenCalled();
    expect(mockNotify).toHaveBeenCalledWith('Upload sequence complete.', 'success');
  });

  it('merges sidebar manual tags with the per-file AI tags into the uploaded asset metadata (de-duplicated)', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/metadata_schemas': [{ id: 7, name: 'Product Images', slug: 'product-images', level: 'root' }],
      'GET /api/v1/upload_restrictions': { allowed_mime_types: ['image/*'] },
      'GET /api/v1/collections': [],
      'POST /api/v1/assets/check_hashes': { duplicates: {} },
      'POST /api/v1/assets': {},
    });

    render(<UploadWorkspace folderId={15} onClose={jest.fn()} onUploadComplete={jest.fn()} />);

    await waitFor(() => expect(dropzoneOnDrop).toBeInstanceOf(Function));
    await act(async () => {
      await dropzoneOnDrop([new File(['file'], 'hero.jpg', { type: 'image/jpeg' })]);
    });
    expect(await screen.findByDisplayValue('hero.jpg')).toBeInTheDocument();

    // Enter a custom manual tag in the sidebar's Tags Autocomplete.
    const tagsInput = screen.getByPlaceholderText('Type and press enter');
    fireEvent.change(tagsInput, { target: { value: 'Campaign' } });
    fireEvent.keyDown(tagsInput, { key: 'Enter', code: 'Enter' });

    // Run the per-file AI enhance, which sets meta.aiTags = ['Enhanced', 'Web-Ready'].
    fireEvent.click(screen.getByRole('button', { name: /run ai enhance on this file/i }));
    expect(await screen.findByText('Enhanced')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Upload (1)' }));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/api/v1/assets', expect.objectContaining({ method: 'POST' })));

    const [, options] = global.fetch.mock.calls.find(([url, opts]) => String(url) === '/api/v1/assets' && opts.method === 'POST');
    const metadataRaw = options.body.get('metadata');
    const metadata = JSON.parse(metadataRaw);

    expect(metadata.tags).toEqual(expect.arrayContaining(['Campaign', 'Enhanced', 'Web-Ready']));
    expect(metadata.tags).toHaveLength(3); // de-duplicated, no repeats
  });

  it('attaches dam:product_id/language_code/asset_type metadata when the filename matches ProductID-LanguageCode-AssetTypeCode naming', async () => {
    // mockParseProductFilename (see beforeEach) returns isProductNaming: true
    // for any filename, standing in for a real "0123-en-FR01.jpg"-style name.
    global.fetch = mockFetch({
      'GET /api/v1/metadata_schemas': [{ id: 7, name: 'Product Images', slug: 'product-images', level: 'root' }],
      'GET /api/v1/upload_restrictions': { allowed_mime_types: ['image/*'] },
      'GET /api/v1/collections': [],
      'POST /api/v1/assets/check_hashes': { duplicates: {} },
      'POST /api/v1/assets': {},
    });

    render(<UploadWorkspace folderId={15} onClose={jest.fn()} onUploadComplete={jest.fn()} />);

    await waitFor(() => expect(dropzoneOnDrop).toBeInstanceOf(Function));
    await act(async () => {
      await dropzoneOnDrop([new File(['file'], '0123-en-FR01.jpg', { type: 'image/jpeg' })]);
    });
    expect(await screen.findByDisplayValue('0123-en-FR01.jpg')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Upload (1)' }));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/api/v1/assets', expect.objectContaining({ method: 'POST' })));

    const [, options] = global.fetch.mock.calls.find(([url, opts]) => String(url) === '/api/v1/assets' && opts.method === 'POST');
    const metadata = JSON.parse(options.body.get('metadata'));

    expect(metadata['dam:product_id']).toBe('0123');
    expect(metadata['dam:language_code']).toBe('en');
    expect(metadata['dam:asset_type']).toBe('FR01');
  });
});
