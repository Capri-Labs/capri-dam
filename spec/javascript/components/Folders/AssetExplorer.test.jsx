import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

import AssetExplorer from '../../../../app/javascript/components/Folders/AssetExplorer';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key, opts) => (opts?.count != null ? `${key}:${opts.count}` : key),
  }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('../../../../app/javascript/utils/globalutils', () => ({
  calculateFileHash: jest.fn(),
  navigateTo: jest.fn(),
}));

jest.mock('../../../../app/javascript/utils/productFilename', () => ({
  parseProductFilename: jest.fn(),
  defaultSchemaSlugForMime: jest.fn(),
}));

jest.mock('react-dropzone', () => ({
  useDropzone: jest.fn(() => ({
    getRootProps: () => ({ 'data-testid': 'dropzone-root' }),
    getInputProps: () => ({ 'data-testid': 'dropzone-input' }),
    isDragActive: false,
  })),
}));

const viewData = {
  breadcrumbs: [{ id: 'root', name: 'Home' }],
  folders: [],
  assets: [
    { id: 20, uuid: '20', title: 'Asset One', can_modify: true, can_delete: true },
    { id: 21, uuid: '21', title: 'Asset Two', can_modify: true, can_delete: true },
  ],
};

const mockFetch = (routes) => jest.fn((url, options = {}) => {
  const method = (options.method || 'GET').toUpperCase();
  const path = String(url);
  const key = Object.keys(routes)
    .filter((route) => {
      const [routeMethod, routePath] = route.split(' ');
      return routeMethod === method && path.startsWith(routePath);
    })
    .sort((a, b) => b.length - a.length)[0];

  if (!key) return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });

  const handler = routes[key];
  return Promise.resolve({ ok: true, json: () => Promise.resolve(handler) });
});

beforeEach(() => {
  mockNotify.mockClear();
  document.body.innerHTML = '<meta name="csrf-token" content="test-csrf-token">';
});

describe('AssetExplorer select-all toggle', () => {
  it('deselects all items when "Select All" is clicked a second time (bug: previously a no-op)', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/folders/root': viewData,
    });

    render(<AssetExplorer />);

    await screen.findByText('Asset One');

    const selectAllCheckbox = screen.getByRole('checkbox', { name: 'explorerTopBar.selectAll' });

    // First click selects everything visible.
    fireEvent.click(selectAllCheckbox);
    await waitFor(() => expect(selectAllCheckbox).toBeChecked());
    expect(screen.getByTestId('manage-publish-button')).toBeInTheDocument();

    // Second click (unchecking) must clear the selection instead of
    // re-selecting everything again.
    fireEvent.click(selectAllCheckbox);
    await waitFor(() => expect(selectAllCheckbox).not.toBeChecked());
    expect(screen.queryByTestId('manage-publish-button')).not.toBeInTheDocument();
  });
});

describe('AssetExplorer Manage Publish actions', () => {
  it('publishes all selected assets immediately via the Manage Publish menu', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/folders/root': viewData,
      'POST /api/v1/assets/20/publish': { id: 20, published: true },
      'POST /api/v1/assets/21/publish': { id: 21, published: true },
    });

    render(<AssetExplorer />);

    await screen.findByText('Asset One');
    fireEvent.click(screen.getByRole('checkbox', { name: 'explorerTopBar.selectAll' }));

    fireEvent.click(await screen.findByTestId('manage-publish-button'));
    fireEvent.click(await screen.findByTestId('publish-menu-publish'));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/assets/20/publish', expect.objectContaining({ method: 'POST' }));
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/assets/21/publish', expect.objectContaining({ method: 'POST' }));
    });
  });

  it('unpublishes all selected assets immediately via the Manage Publish menu', async () => {
    global.fetch = mockFetch({
      'GET /api/v1/folders/root': viewData,
      'POST /api/v1/assets/20/unpublish': { id: 20, published: false },
      'POST /api/v1/assets/21/unpublish': { id: 21, published: false },
    });

    render(<AssetExplorer />);

    await screen.findByText('Asset One');
    fireEvent.click(screen.getByRole('checkbox', { name: 'explorerTopBar.selectAll' }));

    fireEvent.click(await screen.findByTestId('manage-publish-button'));
    fireEvent.click(await screen.findByTestId('publish-menu-unpublish'));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/assets/20/unpublish', expect.objectContaining({ method: 'POST' }));
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/assets/21/unpublish', expect.objectContaining({ method: 'POST' }));
    });
  });
});
