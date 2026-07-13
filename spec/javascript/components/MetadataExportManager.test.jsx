import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import MetadataExportManager from '../../../app/javascript/components/Tools/MetadataExport/MetadataExportManager';

function mockFetch(routes) {
  return jest.fn((url) => {
    const match = Object.keys(routes).find((key) => url.startsWith(key));
    const body = match ? routes[match] : [];
    return Promise.resolve({
      ok: true,
      json: () => Promise.resolve(body)
    });
  });
}

describe('<MetadataExportManager />', () => {
  afterEach(() => jest.restoreAllMocks());

  it('renders the header and the empty-state when there are no exports', async () => {
    global.fetch = mockFetch({
      '/api/v1/metadata_exports': { exports: [], meta: { total: 0, page: 1, per_page: 25 } },
      '/api/v1/folders': { folders: [] }
    });

    render(<MetadataExportManager />);

    expect(screen.getByText('Metadata Export')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /new export/i })).toBeInTheDocument();

    await waitFor(() =>
      expect(screen.getByText(/no exports yet/i)).toBeInTheDocument()
    );
  });

  it('renders an export row returned by the API', async () => {
    global.fetch = mockFetch({
      '/api/v1/metadata_exports': {
        exports: [
          {
            id: 1,
            name: 'q3_assets',
            status: 'completed',
            folder_name: 'Marketing',
            include_subfolders: true,
            property_mode: 'all',
            selected_properties: [],
            total_assets: 12,
            file_count: 1,
            created_by: 'ashok@example.com',
            created_at: 'Jun 23, 2026 at 10:00',
            expires_at: 'Jul 23, 2026',
            files: [{ id: 9, filename: 'q3_assets.csv', byte_size: 2048, download_url: '/dl/9' }]
          }
        ],
        meta: { total: 1, page: 1, per_page: 25 }
      },
      '/api/v1/folders': { folders: [] }
    });

    render(<MetadataExportManager />);

    await waitFor(() =>
      expect(screen.getByText('q3_assets.csv')).toBeInTheDocument()
    );
    expect(screen.getByText('Marketing')).toBeInTheDocument();
    expect(screen.getByText(/CSV Download/i)).toBeInTheDocument();
  });

  it('renders pagination controls with 25/50/100 rows-per-page options', async () => {
    global.fetch = mockFetch({
      '/api/v1/metadata_exports': { exports: [], meta: { total: 0, page: 1, per_page: 25 } },
      '/api/v1/folders': { folders: [] }
    });

    render(<MetadataExportManager />);

    await waitFor(() =>
      expect(screen.getByText(/no exports yet/i)).toBeInTheDocument()
    );
    // No pagination footer is shown while the list is empty.
    expect(screen.queryByText(/rows per page/i)).not.toBeInTheDocument();
  });

  it('shows the pagination footer with rows-per-page options once exports exist', async () => {
    global.fetch = mockFetch({
      '/api/v1/metadata_exports': {
        exports: [
          {
            id: 1, name: 'q3_assets', status: 'completed', folder_name: 'Marketing',
            include_subfolders: false, property_mode: 'all', selected_properties: [],
            total_assets: 1, file_count: 1, created_by: 'a@example.com',
            created_at: 'Jun 23, 2026 at 10:00', expires_at: 'Jul 23, 2026', files: []
          }
        ],
        meta: { total: 1, page: 1, per_page: 25 }
      },
      '/api/v1/folders': { folders: [] }
    });

    render(<MetadataExportManager />);

    await waitFor(() => expect(screen.getByText(/rows per page/i)).toBeInTheDocument());
  });

  it('selects all exports and bulk deletes them', async () => {
    const exportsPayload = {
      exports: [
        {
          id: 1, name: 'export_one', status: 'completed', folder_name: 'Marketing',
          include_subfolders: false, property_mode: 'all', selected_properties: [],
          total_assets: 1, file_count: 1, created_by: 'a@example.com',
          created_at: 'Jun 23, 2026 at 10:00', expires_at: 'Jul 23, 2026', files: []
        },
        {
          id: 2, name: 'export_two', status: 'completed', folder_name: 'Marketing',
          include_subfolders: false, property_mode: 'all', selected_properties: [],
          total_assets: 1, file_count: 1, created_by: 'a@example.com',
          created_at: 'Jun 23, 2026 at 10:00', expires_at: 'Jul 23, 2026', files: []
        }
      ],
      meta: { total: 2, page: 1, per_page: 25 }
    };

    global.fetch = jest.fn((url, options = {}) => {
      if (url.startsWith('/api/v1/metadata_exports/bulk_delete')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ deleted_count: 2 }) });
      }
      if (url.startsWith('/api/v1/metadata_exports')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve(exportsPayload) });
      }
      if (url.startsWith('/api/v1/folders')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ folders: [] }) });
      }
      return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
    });
    window.confirm = jest.fn(() => true);

    render(<MetadataExportManager />);

    await waitFor(() => expect(screen.getByText('export_one.csv')).toBeInTheDocument());

    const selectAllCheckbox = screen.getByTestId('export-select-all').querySelector('input');
    fireEvent.click(selectAllCheckbox);

    expect(await screen.findByText('Delete Selected (2)')).toBeInTheDocument();

    fireEvent.click(screen.getByTestId('export-bulk-delete-button'));

    await waitFor(() =>
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/metadata_exports/bulk_delete', expect.objectContaining({
        method: 'DELETE',
      }))
    );
  });

  it('does not show the Delete Selected button when nothing is checked', async () => {
    global.fetch = mockFetch({
      '/api/v1/metadata_exports': {
        exports: [
          {
            id: 1, name: 'q3_assets', status: 'completed', folder_name: 'Marketing',
            include_subfolders: false, property_mode: 'all', selected_properties: [],
            total_assets: 1, file_count: 1, created_by: 'a@example.com',
            created_at: 'Jun 23, 2026 at 10:00', expires_at: 'Jul 23, 2026', files: []
          }
        ],
        meta: { total: 1, page: 1, per_page: 25 }
      },
      '/api/v1/folders': { folders: [] }
    });

    render(<MetadataExportManager />);

    await waitFor(() => expect(screen.getByText('q3_assets.csv')).toBeInTheDocument());
    expect(screen.queryByTestId('export-bulk-delete-button')).not.toBeInTheDocument();
  });
});

