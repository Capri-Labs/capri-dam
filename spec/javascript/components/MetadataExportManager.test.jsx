import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
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
      '/api/v1/metadata_exports': [],
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
      '/api/v1/metadata_exports': [
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
      '/api/v1/folders': { folders: [] }
    });

    render(<MetadataExportManager />);

    await waitFor(() =>
      expect(screen.getByText('q3_assets.csv')).toBeInTheDocument()
    );
    expect(screen.getByText('Marketing')).toBeInTheDocument();
    expect(screen.getByText(/CSV Download/i)).toBeInTheDocument();
  });
});

