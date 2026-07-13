import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

const mockNotify = jest.fn();

const translate = (key, fallbackOrOptions, maybeOptions) => {
  if (typeof fallbackOrOptions === 'string') return fallbackOrOptions;
  if (maybeOptions && typeof maybeOptions === 'object' && 'defaultValue' in maybeOptions) {
    return maybeOptions.defaultValue;
  }
  if (fallbackOrOptions && typeof fallbackOrOptions === 'object' && 'defaultValue' in fallbackOrOptions) {
    return fallbackOrOptions.defaultValue;
  }
  return key;
};

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: translate,
    i18n: { language: 'en', changeLanguage: jest.fn() },
  }),
}));

jest.mock('../../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

import MetadataImportManager from '../../../../../app/javascript/components/Tools/MetadataImport';

function apiResponse(body, ok = true) {
  return Promise.resolve({
    ok,
    json: () => Promise.resolve(body),
  });
}

function sequence(...items) {
  return { __sequence: items };
}

function createFetchMock(routes) {
  return jest.fn((url, options = {}) => {
    const method = (options.method || 'GET').toUpperCase();
    const routeKey = Object.keys(routes)
      .filter((key) => {
        const [routeMethod, ...routePathParts] = key.split(' ');
        return routeMethod === method && String(url).startsWith(routePathParts.join(' '));
      })
      .sort((a, b) => b.length - a.length)[0];

    if (!routeKey) return apiResponse({});

    const handler = routes[routeKey];
    const value = handler && handler.__sequence ? handler.__sequence.shift() : handler;

    if (typeof value === 'function') return value(url, options);
    return apiResponse(value?.body ?? value, value?.ok ?? true);
  });
}

describe('<MetadataImportManager /> preview flow', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === 'meta[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('renders preview results inside the dialog', async () => {
    global.fetch = createFetchMock({
      'GET /api/v1/metadata_imports': { imports: [], meta: { total: 0, page: 1, per_page: 25 } },
      'POST /api/v1/metadata_imports/preview': {
        dry_run: true,
        total_rows: 2,
        success_count: 1,
        failure_count: 1,
        preview_csv: 'asset_path,import_status,import_message',
        rows: [
          {
            row_number: 2,
            asset_path: '/Adventures/bike.jpg',
            resolved_asset_path: '/Adventures/bike.jpg',
            status: 'success',
            message: 'Updated 1 property',
            changes: [
              { field: 'copyright', from: 'Original', to: 'ACME' },
            ],
          },
          {
            row_number: 3,
            asset_path: '/Adventures/missing.jpg',
            resolved_asset_path: '/Adventures/missing.jpg',
            status: 'fail',
            message: "No asset found at path '/Adventures/missing.jpg'",
            changes: [],
          },
        ],
      },
    });

    render(<MetadataImportManager />);

    await screen.findByText(/no imports yet/i);
    fireEvent.click(screen.getByRole('button', { name: /new import/i }));
    await screen.findByRole('dialog');

    const input = document.body.querySelector('input[type="file"]');
    const file = new File(['asset_path,copyright\n/Adventures/bike.jpg,ACME\n'], 'preview.csv', { type: 'text/csv' });
    fireEvent.change(input, { target: { files: [file] } });

    await waitFor(() => expect(screen.getByText(/Detected 2 columns/i)).toBeInTheDocument());

    fireEvent.click(screen.getByRole('button', { name: /^preview$/i }));

    expect(await screen.findByText(/Preview results/i)).toBeInTheDocument();
    expect(screen.getByText('Updated 1 property')).toBeInTheDocument();
    expect(screen.getByText(/No asset found at path/i)).toBeInTheDocument();
    expect(screen.getAllByText((_, element) => element.textContent === 'copyright: Original → ACME').length).toBeGreaterThan(0);
    expect(global.fetch).toHaveBeenCalledWith('/api/v1/metadata_imports/preview', expect.objectContaining({
      method: 'POST',
      headers: { 'X-CSRF-Token': 'csrf-token' },
      body: expect.any(FormData),
    }));
  });

  it('still creates a real import after preview support was added', async () => {
    const pendingImport = {
      id: 11,
      name: 'preview.csv',
      status: 'pending',
      batch_size: 50,
      field_separator: ',',
      asset_path_column: 'asset_path',
      launch_workflows: false,
      success_count: 0,
      failure_count: 0,
      created_by: 'admin@example.com',
      created_at: 'Jul 9, 2026 at 09:00',
      expires_at: null,
      source_file: null,
      result_file: null,
    };

    global.fetch = createFetchMock({
      'GET /api/v1/metadata_imports': sequence(
        { imports: [], meta: { total: 0, page: 1, per_page: 25 } },
        { imports: [ pendingImport ], meta: { total: 1, page: 1, per_page: 25 } }
      ),
      'POST /api/v1/metadata_imports': { id: 11, name: 'preview.csv', status: 'pending' },
    });

    render(<MetadataImportManager />);

    await screen.findByText(/no imports yet/i);
    fireEvent.click(screen.getByRole('button', { name: /new import/i }));
    await screen.findByRole('dialog');

    const input = document.body.querySelector('input[type="file"]');
    const file = new File(['asset_path,copyright\n/root.jpg,ACME\n'], 'preview.csv', { type: 'text/csv' });
    fireEvent.change(input, { target: { files: [file] } });

    await waitFor(() => expect(screen.getByText(/Detected 2 columns/i)).toBeInTheDocument());

    fireEvent.click(screen.getByRole('button', { name: /^import$/i }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/metadata_imports', expect.objectContaining({
        method: 'POST',
        headers: { 'X-CSRF-Token': 'csrf-token' },
        body: expect.any(FormData),
      }));
    });

    expect(mockNotify).toHaveBeenCalledWith(
      'Metadata import started. You will be notified when it is complete.',
      'success',
    );
    expect(await screen.findByText('preview.csv')).toBeInTheDocument();
  });
});

describe('<MetadataImportManager /> bulk select + delete', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === 'meta[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const importRow = (id, name) => ({
    id, name, status: 'completed', batch_size: 50, field_separator: ',',
    asset_path_column: 'asset_path', launch_workflows: false,
    total_rows: 1, success_count: 1, failure_count: 0,
    created_by: 'admin@example.com', created_at: 'Jul 9, 2026 at 09:00',
    expires_at: null, source_file: null, result_file: null,
  });

  it('selects all imports and bulk deletes them', async () => {
    global.fetch = createFetchMock({
      'GET /api/v1/metadata_imports': {
        imports: [ importRow(1, 'one.csv'), importRow(2, 'two.csv') ],
        meta: { total: 2, page: 1, per_page: 25 },
      },
      'DELETE /api/v1/metadata_imports/bulk_delete': { deleted_count: 2 },
    });
    window.confirm = jest.fn(() => true);

    render(<MetadataImportManager />);

    await screen.findByText('one.csv');

    const selectAll = screen.getByTestId('import-select-all').querySelector('input');
    fireEvent.click(selectAll);

    expect(await screen.findByText('Delete Selected (2)')).toBeInTheDocument();

    fireEvent.click(screen.getByTestId('import-bulk-delete-button'));

    await waitFor(() =>
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/metadata_imports/bulk_delete', expect.objectContaining({
        method: 'DELETE',
      }))
    );
  });

  it('does not show the Delete Selected button when nothing is checked', async () => {
    global.fetch = createFetchMock({
      'GET /api/v1/metadata_imports': {
        imports: [ importRow(1, 'one.csv') ],
        meta: { total: 1, page: 1, per_page: 25 },
      },
    });

    render(<MetadataImportManager />);

    await screen.findByText('one.csv');
    expect(screen.queryByTestId('import-bulk-delete-button')).not.toBeInTheDocument();
  });
});
