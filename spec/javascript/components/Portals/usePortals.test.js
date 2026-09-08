import { renderHook, act, waitFor } from '@testing-library/react';
import usePortals from '../../../../app/javascript/components/Portals/usePortals';

jest.mock('../../../../app/javascript/utils/format', () => ({
    __esModule: true,
    csrfToken: () => 'test-csrf',
    humanFileSize: (n) => `${n} B`,
}));

const jsonResponse = (body, ok = true, status = 200) => ({
    ok, status, json: async () => body,
});

beforeEach(() => {
    global.fetch = jest.fn();
});

describe('usePortals', () => {
    it('loads the portal list on mount', async () => {
        global.fetch.mockResolvedValue(jsonResponse({ portals: [{ id: 1 }], meta: { total: 1 } }));

        const { result } = renderHook(() => usePortals());

        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.portals).toEqual([{ id: 1 }]);
        expect(global.fetch).toHaveBeenCalledWith('/api/v1/portals', expect.any(Object));
    });

    it('sends the CSRF token on writes', async () => {
        global.fetch.mockResolvedValue(jsonResponse({ portals: [] }));
        const { result } = renderHook(() => usePortals());
        await waitFor(() => expect(result.current.loading).toBe(false));

        global.fetch.mockResolvedValue(jsonResponse({ id: 5, token: 't', url: 'u' }));
        await act(async () => { await result.current.create({ collection_id: '7' }); });

        const [, options] = global.fetch.mock.calls[1];
        expect(options.method).toBe('POST');
        expect(options.headers['X-CSRF-Token']).toBe('test-csrf');
    });

    it('returns the created portal so the one-time token can be shown', async () => {
        global.fetch.mockResolvedValue(jsonResponse({ portals: [] }));
        const { result } = renderHook(() => usePortals());
        await waitFor(() => expect(result.current.loading).toBe(false));

        global.fetch.mockResolvedValue(jsonResponse({ id: 5, token: 'sekrit', url: 'https://x/y' }));

        let created;
        await act(async () => { created = await result.current.create({ collection_id: '7' }); });
        expect(created.url).toBe('https://x/y');
    });

    // The API reports validation problems as `errors` and everything else as
    // `error`; callers should not have to know which one they are about to get.
    it('flattens both error shapes into a message', async () => {
        global.fetch.mockResolvedValue(jsonResponse({ errors: ['Name is too long'] }, false, 422));

        const { result } = renderHook(() => usePortals());
        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.error).toBe('Name is too long');

        global.fetch.mockResolvedValue(jsonResponse({ error: 'Portal not found' }, false, 404));
        await act(async () => { await result.current.reload(); });
        expect(result.current.error).toBe('Portal not found');
    });

    it('revokes with DELETE and reloads', async () => {
        global.fetch.mockResolvedValue(jsonResponse({ portals: [] }));
        const { result } = renderHook(() => usePortals());
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => { await result.current.revoke(3); });

        const [url, options] = global.fetch.mock.calls[1];
        expect(url).toBe('/api/v1/portals/3');
        expect(options.method).toBe('DELETE');
        // Third call is the reload that follows.
        expect(global.fetch.mock.calls[2][0]).toBe('/api/v1/portals');
    });

    it('fetches the download log for one portal', async () => {
        global.fetch.mockResolvedValue(jsonResponse({ portals: [] }));
        const { result } = renderHook(() => usePortals());
        await waitFor(() => expect(result.current.loading).toBe(false));

        global.fetch.mockResolvedValue(jsonResponse({ downloads: [], meta: { total: 0 } }));
        await act(async () => { await result.current.fetchDownloads(3); });

        expect(global.fetch.mock.calls[1][0]).toBe('/api/v1/portals/3/downloads');
    });
});
