import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key, opts) => {
      if (opts && typeof opts === 'object' && 'defaultValue' in opts) return opts.defaultValue;
      if (opts?.name) return `${key}:${opts.name}`;
      return key;
    },
  }),
}));

jest.mock('../../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => jest.fn(),
}));

import MetadataSchemasManager from '../../../../../app/javascript/components/Tools/MetadataSchemas/MetadataSchemasManager';

function rootSchema(id, overrides = {}) {
  return {
    id, name: `Schema ${id}`, level: 'root', is_builtin: false,
    mime_segment: null, children: [], folder_count: 0, child_count: 0,
    ...overrides,
  };
}

function mockFetchSequence(schemas) {
  global.fetch = jest.fn((url, options = {}) => {
    if (url === '/api/v1/metadata_schemas' && (!options.method || options.method === 'GET')) {
      return Promise.resolve({ ok: true, json: () => Promise.resolve(schemas) });
    }
    if (url === '/api/v1/metadata_schemas/bulk_delete' && options.method === 'DELETE') {
      const body = JSON.parse(options.body);
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ deleted_count: body.ids.length, skipped_builtin_ids: [] }),
      });
    }
    return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
  });
}

describe('<MetadataSchemasManager />', () => {
  afterEach(() => jest.restoreAllMocks());

  it('renders the schema library header and empty state', async () => {
    mockFetchSequence([]);

    render(<MetadataSchemasManager canManageSchemas />);

    expect(screen.getByText('Schema Library')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText('No schemas found.')).toBeInTheDocument());
  });

  it('paginates root schemas at 10 per page', async () => {
    const schemas = Array.from({ length: 15 }, (_, i) => rootSchema(i + 1));
    mockFetchSequence(schemas);

    render(<MetadataSchemasManager canManageSchemas />);

    await waitFor(() => expect(screen.getByText('Schema 1')).toBeInTheDocument());
    expect(screen.getByText('Schema 10')).toBeInTheDocument();
    expect(screen.queryByText('Schema 11')).not.toBeInTheDocument();
    expect(screen.getByText('Page 1 of 2')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /Next/ }));

    await waitFor(() => expect(screen.getByText('Schema 11')).toBeInTheDocument());
    expect(screen.queryByText('Schema 1')).not.toBeInTheDocument();
    expect(screen.getByText('Page 2 of 2')).toBeInTheDocument();
  });

  it('does not show pagination controls when a single page is enough', async () => {
    mockFetchSequence([ rootSchema(1), rootSchema(2) ]);

    render(<MetadataSchemasManager canManageSchemas />);

    await waitFor(() => expect(screen.getByText('Schema 1')).toBeInTheDocument());
    expect(screen.queryByText(/Page \d+ of \d+/)).not.toBeInTheDocument();
  });

  it('selects all selectable schemas on the page and bulk deletes them', async () => {
    const schemas = [ rootSchema(1), rootSchema(2), rootSchema(3, { is_builtin: true }) ];
    mockFetchSequence(schemas);
    window.confirm = jest.fn(() => true);

    render(<MetadataSchemasManager canManageSchemas />);

    await waitFor(() => expect(screen.getByText('Schema 1')).toBeInTheDocument());

    const selectAll = screen.getByTestId('schema-select-all').querySelector('input');
    fireEvent.click(selectAll);

    // Built-in schema (id 3) is not selectable, so only 2 get checked.
    expect(screen.getByText('2 selected')).toBeInTheDocument();

    fireEvent.click(screen.getByTestId('schema-bulk-delete-button'));

    await waitFor(() =>
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/metadata_schemas/bulk_delete', expect.objectContaining({
        method: 'DELETE',
      }))
    );
  });

  it('does not show selection checkboxes when the user cannot manage schemas', async () => {
    mockFetchSequence([ rootSchema(1) ]);

    render(<MetadataSchemasManager canManageSchemas={false} />);

    await waitFor(() => expect(screen.getByText('Schema 1')).toBeInTheDocument());
    expect(screen.queryByTestId('schema-select-all')).not.toBeInTheDocument();
    expect(screen.queryByTestId('schema-select-1')).not.toBeInTheDocument();
  });
});
