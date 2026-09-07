import { renderHook, act, waitFor } from '@testing-library/react';
import useGuestReview from '../../../../app/javascript/components/GuestReview/useGuestReview';

const TOKEN = 'tok-abc';

const ASSETS_PAYLOAD = {
    review: {
        name: 'Client review',
        target_label: 'Hero shot',
        allow_comments: true,
        allow_downloads: false,
        require_email: true,
        identified: false,
    },
    guest: null,
    assets: [
        { id: 'asset-1', title: 'Hero shot', preview_url: `/s/reviews/${TOKEN}/assets/asset-1/preview`, downloadable: false },
        { id: 'asset-2', title: 'Pack shot', preview_url: `/s/reviews/${TOKEN}/assets/asset-2/preview`, downloadable: false },
    ],
};

const THREADS_PAYLOAD = {
    can_comment: false,
    threads: [
        {
            id: 'thread-1',
            status: 'open',
            closed: false,
            author: { display_name: 'Priya', kind: 'guest' },
            comments: [
                {
                    id: 'c-1',
                    body: 'Logo is clipped.',
                    author: { display_name: 'Priya', kind: 'guest' },
                    annotations: [{ id: 'ann-1', shape: 'rect', bbox: { x: 0.1, y: 0.1, w: 0.2, h: 0.2 } }],
                    replies: [],
                },
            ],
        },
    ],
};

function mockRoutes(overrides = {}) {
    global.fetch = jest.fn((url, options = {}) => {
        const path = String(url);
        const method = options.method || 'GET';
        const key = `${method} ${path}`;

        if (overrides[key]) return Promise.resolve(overrides[key]);

        if (path.endsWith('/assets')) return json(ASSETS_PAYLOAD);
        if (path.endsWith('/threads')) return json(THREADS_PAYLOAD);
        return json({});
    });
}

function json(body, ok = true, status = 200) {
    return Promise.resolve({ ok, status, json: () => Promise.resolve(body) });
}

beforeEach(() => {
    document.head.innerHTML = '<meta name="csrf-token" content="csrf-123">';
});

afterEach(() => { jest.restoreAllMocks(); });

describe('useGuestReview', () => {
    it('loads the review and selects the first asset automatically', async () => {
        mockRoutes();
        const { result } = renderHook(() => useGuestReview(TOKEN));

        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.review.name).toBe('Client review');
        expect(result.current.assets).toHaveLength(2);
        expect(result.current.selectedAssetId).toBe('asset-1');
    });

    it('flattens annotations across threads and tags them with their thread', async () => {
        mockRoutes();
        const { result } = renderHook(() => useGuestReview(TOKEN));

        await waitFor(() => expect(result.current.threads).toHaveLength(1));

        expect(result.current.annotations).toEqual([
            expect.objectContaining({ id: 'ann-1', thread_id: 'thread-1' }),
        ]);
    });

    it('sends the CSRF token on writes', async () => {
        mockRoutes({
            [`POST /s/reviews/${TOKEN}/identify`]: {
                ok: true, status: 201,
                json: () => Promise.resolve({ guest: { id: 'g-1', display_name: 'Priya' } }),
            },
        });

        const { result } = renderHook(() => useGuestReview(TOKEN));
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => {
            await result.current.identify({ email: 'priya@client.com', name: 'Priya' });
        });

        const call = global.fetch.mock.calls.find(([, opts]) => opts?.method === 'POST');
        expect(call[1].headers['X-CSRF-Token']).toBe('csrf-123');
        expect(result.current.guest.display_name).toBe('Priya');
    });

    it('appends a new thread without refetching everything', async () => {
        const created = { id: 'thread-2', closed: false, comments: [{ id: 'c-2', body: 'Crop tighter', author: {}, annotations: [] }] };
        mockRoutes({
            [`POST /s/reviews/${TOKEN}/assets/asset-1/comments`]: {
                ok: true, status: 201, json: () => Promise.resolve({ thread: created }),
            },
        });

        const { result } = renderHook(() => useGuestReview(TOKEN));
        await waitFor(() => expect(result.current.threads).toHaveLength(1));

        const before = global.fetch.mock.calls.length;
        await act(async () => {
            await result.current.createThread({ body: 'Crop tighter', annotations: [] });
        });

        expect(result.current.threads.map((t) => t.id)).toEqual(['thread-1', 'thread-2']);
        // One POST, and no follow-up GET storm.
        expect(global.fetch.mock.calls.length).toBe(before + 1);
    });

    it('appends a reply into the right thread only', async () => {
        mockRoutes({
            [`POST /s/reviews/${TOKEN}/threads/thread-1/comments`]: {
                ok: true, status: 201,
                json: () => Promise.resolve({ comment: { id: 'c-9', body: 'Agreed', author: {}, annotations: [] } }),
            },
        });

        const { result } = renderHook(() => useGuestReview(TOKEN));
        await waitFor(() => expect(result.current.threads).toHaveLength(1));

        await act(async () => {
            await result.current.createReply('thread-1', { body: 'Agreed' });
        });

        expect(result.current.threads[0].comments.map((c) => c.id)).toEqual(['c-1', 'c-9']);
    });

    it('surfaces a server refusal rather than failing silently', async () => {
        global.fetch = jest.fn(() => json({ error: 'This review link has expired.' }, false, 410));

        const { result } = renderHook(() => useGuestReview(TOKEN));
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.error).toBe('This review link has expired.');
    });
});
