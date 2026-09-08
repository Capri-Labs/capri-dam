import React from 'react';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import i18n from 'i18next';
import en from '../../../../app/javascript/i18n/locales/en.json';
import AssetRenditionsTab from '../../../../app/javascript/components/Folders/AssetRenditionsTab';

i18n.addResourceBundle('en', 'translation', en, true, true);

const asset = { id: 'asset-uuid-1' };

const manual = {
    id: 'r1', asset_id: 'asset-uuid-1', kind: 'print_cmyk', content_type: 'image/tiff',
    width: 4000, height: 3000, file_size: 2048, source: 'manual',
    storage_backend: 'Local', metadata: {}, url: 'https://cdn.test/print.tiff',
    created_at: '2025-01-01T00:00:00Z',
};

const generated = { ...manual, id: 'r2', kind: 'thumbnail', source: 'generated', url: null };

function mockList(renditions) {
    global.fetch = jest.fn(() => Promise.resolve({
        ok: true,
        status: 200,
        json: () => Promise.resolve({ renditions, meta: { total: renditions.length } }),
    }));
}

beforeEach(() => { jest.restoreAllMocks(); });

describe('AssetRenditionsTab', () => {
    it('lists the asset renditions with derived dimensions and size', async () => {
        mockList([ manual ]);
        render(<AssetRenditionsTab asset={asset} />);

        expect(await screen.findByText('print_cmyk')).toBeInTheDocument();
        const table = screen.getByRole('table');
        expect(within(table).getByText('4000 × 3000')).toBeInTheDocument();
        expect(within(table).getByText('2.0 KB')).toBeInTheDocument();
        expect(within(table).getByText('Manual')).toBeInTheDocument();
    });

    it('shows the empty state when the asset has no renditions', async () => {
        mockList([]);
        render(<AssetRenditionsTab asset={asset} />);
        expect(await screen.findByText('No renditions yet.')).toBeInTheDocument();
    });

    // The pipeline owns these names; letting a person upload one would make
    // other code's assumption that a "thumbnail" came from the thumbnailer false.
    it('refuses a reserved kind before contacting the server', async () => {
        mockList([]);
        render(<AssetRenditionsTab asset={asset} />);
        await screen.findByText('No renditions yet.');

        fireEvent.change(screen.getByLabelText('Kind'), { target: { value: 'thumbnail' } });

        expect(await screen.findByText(/generated automatically and cannot be uploaded/i))
            .toBeInTheDocument();
        expect(screen.getByRole('button', { name: 'Upload' })).toBeDisabled();
    });

    it('rejects a kind that is not lowercase-underscored', async () => {
        mockList([]);
        render(<AssetRenditionsTab asset={asset} />);
        await screen.findByText('No renditions yet.');

        fireEvent.change(screen.getByLabelText('Kind'), { target: { value: 'Print CMYK' } });

        expect(await screen.findByText('Use lowercase words joined by underscores.')).toBeInTheDocument();
    });

    it('rejects a kind the asset already has', async () => {
        mockList([ manual ]);
        render(<AssetRenditionsTab asset={asset} />);
        await screen.findByText('print_cmyk');

        fireEvent.change(screen.getByLabelText('Kind'), { target: { value: 'print_cmyk' } });

        expect(await screen.findByText('This asset already has a rendition of that kind.')).toBeInTheDocument();
    });

    it('uploads as multipart and appends the stored rendition', async () => {
        const created = { ...manual, id: 'r9', kind: 'social_square' };
        const fetchMock = jest.fn()
            .mockResolvedValueOnce({ ok: true, status: 200, json: () => Promise.resolve({ renditions: [] }) })
            .mockResolvedValueOnce({ ok: true, status: 201, json: () => Promise.resolve(created) });
        global.fetch = fetchMock;

        render(<AssetRenditionsTab asset={asset} />);
        await screen.findByText('No renditions yet.');

        fireEvent.change(screen.getByLabelText('Kind'), { target: { value: 'social_square' } });
        fireEvent.change(screen.getByTestId('rendition-file-input'), {
            target: { files: [ new File([ 'bytes' ], 'square.jpg', { type: 'image/jpeg' }) ] },
        });

        fireEvent.click(screen.getByRole('button', { name: 'Upload' }));

        expect(await screen.findByText('social_square')).toBeInTheDocument();

        const [ url, options ] = fetchMock.mock.calls[1];
        expect(url).toBe('/api/v1/assets/asset-uuid-1/renditions');
        expect(options.method).toBe('POST');
        expect(options.body).toBeInstanceOf(FormData);
        // The browser must set its own multipart boundary.
        expect(options.headers['Content-Type']).toBeUndefined();
    });

    it('surfaces the server error message when an upload is refused', async () => {
        global.fetch = jest.fn()
            .mockResolvedValueOnce({ ok: true, status: 200, json: () => Promise.resolve({ renditions: [] }) })
            .mockResolvedValueOnce({
                ok: false, status: 503,
                json: () => Promise.resolve({ error: 'No active storage backend is configured.' }),
            });

        render(<AssetRenditionsTab asset={asset} />);
        await screen.findByText('No renditions yet.');

        fireEvent.change(screen.getByLabelText('Kind'), { target: { value: 'print_cmyk' } });
        fireEvent.change(screen.getByTestId('rendition-file-input'), {
            target: { files: [ new File([ 'b' ], 'a.tif', { type: 'image/tiff' }) ] },
        });
        fireEvent.click(screen.getByRole('button', { name: 'Upload' }));

        expect(await screen.findByText('No active storage backend is configured.')).toBeInTheDocument();
    });

    it('confirms before deleting and removes the row on success', async () => {
        global.fetch = jest.fn()
            .mockResolvedValueOnce({ ok: true, status: 200, json: () => Promise.resolve({ renditions: [ manual ] }) })
            .mockResolvedValueOnce({ ok: true, status: 200, json: () => Promise.resolve({ id: 'r1', deleted: true }) });

        render(<AssetRenditionsTab asset={asset} />);
        await screen.findByText('print_cmyk');

        fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
        expect(await screen.findByText('Delete rendition?')).toBeInTheDocument();

        fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Delete' }));

        await waitFor(() => expect(screen.queryByText('print_cmyk')).not.toBeInTheDocument());
    });

    // A generated rendition is reproducible from the source; deleting it here
    // would simply invite the pipeline to make it again.
    it('does not allow deleting a generated rendition', async () => {
        mockList([ generated ]);
        render(<AssetRenditionsTab asset={asset} />);
        await screen.findByText('thumbnail');

        expect(screen.getByRole('button', { name: 'Delete' })).toBeDisabled();
    });

    it('hides the upload form when the viewer cannot modify the asset', async () => {
        mockList([ manual ]);
        render(<AssetRenditionsTab asset={asset} canModify={false} />);
        await screen.findByText('print_cmyk');

        expect(screen.queryByLabelText('Kind')).not.toBeInTheDocument();
        expect(screen.queryByRole('button', { name: 'Delete' })).not.toBeInTheDocument();
    });
});
