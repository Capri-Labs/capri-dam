import { renderHook, act, waitFor } from '@testing-library/react';
import useAssetComments from '../../../../app/javascript/components/Folders/useAssetComments';

const THREAD_A = {
    id: 'thread-a',
    status: 'open',
    closed: false,
    created_at: '2026-09-01T10:00:00Z',
    comments: [{
        id: 'c1',
        annotations: [{ id: 'ann-1', shape: 'pin', bbox: { x: 0.5, y: 0.5, w: 0, h: 0 } }],
    }],
};

const THREAD_B = {
    id: 'thread-b',
    status: 'resolved',
    closed: true,
    created_at: '2026-09-02T10:00:00Z',
    comments: [{
        id: 'c2',
        annotations: [{ id: 'ann-2', shape: 'rect', bbox: { x: 0.1, y: 0.1, w: 0.2, h: 0.2 } }],
    }],
};

let requests;

const mockFetch = (handler) => {
    global.fetch = jest.fn((url, options = {}) => {
        requests.push({ url: String(url), method: options.method || 'GET', body: options.body });
        return handler(String(url), options);
    });
};

const okJson = (payload, status = 200) => Promise.resolve({
    ok: true,
    status,
    json: () => Promise.resolve(payload),
});

beforeEach(() => {
    requests = [];
    document.head.insertAdjacentHTML('beforeend', '<meta name="csrf-token" content="test-csrf">');
    mockFetch(() => okJson({ threads: [THREAD_A, THREAD_B], meta: { total: 2, unresolved: 1 } }));
});

afterEach(() => {
    document.querySelector('meta[name="csrf-token"]')?.remove();
    jest.resetAllMocks();
});

const renderReady = async () => {
    const view = renderHook(() => useAssetComments({ assetId: 'asset-1' }));
    await waitFor(() => expect(view.result.current.loading).toBe(false));
    return view;
};

describe('useAssetComments loading', () => {
    it('loads threads for the asset', async () => {
        const { result } = await renderReady();

        expect(requests[0].url).toBe('/api/v1/assets/asset-1/comments');
        expect(result.current.threads).toHaveLength(2);
        expect(result.current.unresolvedCount).toBe(1);
    });

    it('does not fetch when disabled', async () => {
        renderHook(() => useAssetComments({ assetId: 'asset-1', enabled: false }));

        await waitFor(() => expect(global.fetch).not.toHaveBeenCalled());
    });

    it('applies the version and unresolved filters as query params', async () => {
        const { result } = await renderReady();

        await act(async () => { result.current.setVersionFilter('v2'); });
        await waitFor(() => expect(requests.at(-1).url).toContain('version_id=v2'));

        await act(async () => { result.current.setUnresolvedOnly(true); });
        await waitFor(() => expect(requests.at(-1).url).toContain('unresolved=true'));
    });

    it('surfaces a server error message instead of throwing', async () => {
        mockFetch(() => Promise.resolve({
            ok: false,
            status: 403,
            json: () => Promise.resolve({ error: 'Forbidden' }),
        }));

        const { result } = await renderReady();

        expect(result.current.error).toBe('Forbidden');
        expect(result.current.threads).toEqual([]);
    });
});

describe('useAssetComments derived state', () => {
    it('numbers markers in thread order and stamps the owning thread on each', async () => {
        const { result } = await renderReady();

        expect(result.current.annotations).toEqual([
            expect.objectContaining({ id: 'ann-1', thread_id: 'thread-a', marker_label: '1', resolved: false }),
            expect.objectContaining({ id: 'ann-2', thread_id: 'thread-b', marker_label: '2', resolved: true }),
        ]);
        expect(result.current.markerLabels).toEqual({ 'thread-a': '1', 'thread-b': '2' });
    });

    it('reports the anchor point of a thread s first marker', async () => {
        const { result } = await renderReady();

        expect(result.current.threadAnchor('thread-a')).toEqual({ x: 0.5, y: 0.5 });
        expect(result.current.threadAnchor('nope')).toBeNull();
    });
});

describe('useAssetComments draft handling', () => {
    it('collects drawn shapes and disarms the tool after each one', async () => {
        const { result } = await renderReady();

        await act(async () => { result.current.setTool('rect'); });
        expect(result.current.tool).toBe('rect');

        await act(async () => { result.current.addDraftAnnotation({ shape: 'rect' }); });

        expect(result.current.draft).toEqual([{ shape: 'rect' }]);
        // One shape per click, so the tool cannot "stick" and litter the image.
        expect(result.current.tool).toBeNull();
    });

    it('removes a single pending shape by index', async () => {
        const { result } = await renderReady();

        await act(async () => {
            result.current.addDraftAnnotation({ shape: 'pin' });
        });
        await act(async () => {
            result.current.addDraftAnnotation({ shape: 'rect' });
        });
        await act(async () => { result.current.removeDraftAnnotation(0); });

        expect(result.current.draft).toEqual([{ shape: 'rect' }]);
    });
});

describe('useAssetComments mutations', () => {
    it('creates a thread, clears the draft and reloads', async () => {
        const { result } = await renderReady();

        await act(async () => { result.current.addDraftAnnotation({ shape: 'pin' }); });

        await act(async () => {
            await result.current.createThread({ body: 'Look here', annotations: [{ shape: 'pin' }] });
        });

        const created = requests.find((r) => r.method === 'POST');
        expect(created.url).toBe('/api/v1/assets/asset-1/comments');
        expect(JSON.parse(created.body)).toEqual({
            body: 'Look here',
            visibility: 'internal',
            annotations: [{ shape: 'pin' }],
        });
        expect(result.current.draft).toEqual([]);
        // A reload always follows a mutation so the panel and overlay agree.
        expect(requests.at(-1).method).toBe('GET');
    });

    it('posts a reply with mark_addressed', async () => {
        const { result } = await renderReady();

        await act(async () => {
            await result.current.createReply('thread-a', { body: 'Done', markAddressed: true });
        });

        const reply = requests.find((r) => r.url.includes('/comment_threads/thread-a/comments'));
        expect(JSON.parse(reply.body)).toMatchObject({ body: 'Done', mark_addressed: true });
    });

    it('resolves, verifies and reopens a thread', async () => {
        const { result } = await renderReady();

        await act(async () => { await result.current.resolveThread('thread-a', 'verified'); });
        const resolved = requests.find((r) => r.url.includes('/resolve'));
        expect(resolved.method).toBe('PATCH');
        expect(JSON.parse(resolved.body)).toEqual({ status: 'verified' });

        await act(async () => { await result.current.reopenThread('thread-b'); });
        expect(requests.some((r) => r.url.includes('/reopen') && r.method === 'PATCH')).toBe(true);
    });

    it('sends the CSRF token on every mutating request', async () => {
        const { result } = await renderReady();

        await act(async () => { await result.current.deleteComment('c1'); });

        const [, options] = global.fetch.mock.calls.find(([url]) => String(url).includes('/comments/c1'));
        expect(options.headers['X-CSRF-Token']).toBe('test-csrf');
        expect(options.method).toBe('DELETE');
    });

    it('keeps a failed mutation visible rather than silently swallowing it', async () => {
        const { result } = await renderReady();

        mockFetch((url, options) => {
            if ((options.method || 'GET') !== 'GET') {
                return Promise.resolve({ ok: false, status: 422, json: () => Promise.resolve({ error: 'Body can\'t be blank' }) });
            }
            return okJson({ threads: [THREAD_A], meta: {} });
        });

        let outcome;
        await act(async () => { outcome = await result.current.createThread({ body: '' }); });

        expect(outcome).toBeNull();
        expect(result.current.error).toBe("Body can't be blank");
    });
});
