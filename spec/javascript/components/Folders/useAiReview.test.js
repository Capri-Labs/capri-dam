import { renderHook, act, waitFor } from '@testing-library/react';
import useAiReview from '../../../../app/javascript/components/Folders/useAiReview';

const SUGGESTION = {
    id: 'thread-ai-1',
    status: 'open',
    suggestion: { state: 'pending', ai_review_id: 'rev-1', model_name: 'gpt-vision' },
    comments: [{
        id: 'c1',
        body: 'Logo is outside the safe area.',
        confidence: 0.82,
        annotations: [{ id: 'ann-1', shape: 'rect', bbox: { x: 0.1, y: 0.1, w: 0.2, h: 0.2 } }],
    }],
};

const COMPLETED_REVIEW = {
    id: 'rev-1', status: 'completed', profile: 'safe_area',
    model_name: 'gpt-vision', findings_count: 1,
};

const RUNNING_REVIEW = { ...COMPLETED_REVIEW, status: 'running', findings_count: 0 };

let requests;
let handler;

const okJson = (payload, status = 200) => Promise.resolve({
    ok: true, status, json: () => Promise.resolve(payload),
});

const errJson = (payload, status) => Promise.resolve({
    ok: false, status, json: () => Promise.resolve(payload),
});

const defaultHandler = (url) => {
    if (url.includes('/ai_reviews/pending')) return okJson({ threads: [SUGGESTION] });
    if (url.includes('/ai_reviews')) return okJson({ reviews: [COMPLETED_REVIEW] });
    return okJson({});
};

beforeEach(() => {
    requests = [];
    handler = defaultHandler;
    document.head.insertAdjacentHTML('beforeend', '<meta name="csrf-token" content="test-csrf">');
    global.fetch = jest.fn((url, options = {}) => {
        requests.push({ url: String(url), method: options.method || 'GET', body: options.body });
        return handler(String(url), options);
    });
});

afterEach(() => {
    jest.useRealTimers();
    delete global.fetch;
});

const setup = (props = {}) => renderHook(() => useAiReview({ assetId: 'asset-1', ...props }));

describe('useAiReview', () => {
    it('loads the pending queue and the run history', async () => {
        const { result } = setup();

        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.suggestions).toHaveLength(1);
        expect(result.current.pendingCount).toBe(1);
        expect(result.current.latestReview).toMatchObject({ id: 'rev-1', status: 'completed' });
    });

    it('does not fetch anything while disabled', async () => {
        setup({ enabled: false });

        await waitFor(() => expect(requests).toHaveLength(0));
    });

    it('flattens suggestion annotations for the overlay and labels them', async () => {
        const { result } = setup();

        await waitFor(() => expect(result.current.annotations).toHaveLength(1));

        expect(result.current.annotations[0]).toMatchObject({
            id: 'ann-1',
            thread_id: 'thread-ai-1',
            marker_label: 'AI',
        });
    });

    it('does not colour annotations client-side, leaving the server stroke intact', async () => {
        const { result } = setup();

        await waitFor(() => expect(result.current.annotations).toHaveLength(1));

        // The server stamps #a855f7 on the annotation itself; re-applying it
        // here would create a second source of truth that could drift from the
        // colour used in exports.
        expect(result.current.annotations[0].style).toBeUndefined();
    });

    it('posts the selected profile when running a review', async () => {
        const { result } = setup();
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => { await result.current.runReview('accessibility'); });

        const post = requests.find((r) => r.method === 'POST');
        expect(post.url).toBe('/api/v1/assets/asset-1/ai_reviews');
        expect(JSON.parse(post.body)).toEqual({ profile: 'accessibility' });
    });

    it('accepts a suggestion via the thread endpoint and refreshes', async () => {
        const { result } = setup();
        await waitFor(() => expect(result.current.loading).toBe(false));
        const before = requests.length;

        await act(async () => { await result.current.acceptSuggestion('thread-ai-1'); });

        expect(requests[before]).toMatchObject({
            url: '/api/v1/comment_threads/thread-ai-1/accept_suggestion',
            method: 'POST',
        });
        // Re-reads both lists afterwards, so an accepted card leaves the queue.
        expect(requests.length).toBeGreaterThan(before + 1);
    });

    it('dismisses a suggestion via the dismiss endpoint', async () => {
        const { result } = setup();
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => { await result.current.dismissSuggestion('thread-ai-1'); });

        expect(requests.some((r) => r.url.endsWith('/dismiss_suggestion') && r.method === 'POST')).toBe(true);
    });

    it('notifies the caller when a suggestion is accepted so comments can refresh', async () => {
        const onAccepted = jest.fn();
        const { result } = setup({ onAccepted });
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => { await result.current.acceptSuggestion('thread-ai-1'); });

        expect(onAccepted).toHaveBeenCalledTimes(1);
    });

    it('does not notify the caller when a suggestion is dismissed', async () => {
        const onAccepted = jest.fn();
        const { result } = setup({ onAccepted });
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => { await result.current.dismissSuggestion('thread-ai-1'); });

        // A dismissal creates no thread, so refreshing the comment list would
        // be a pointless round trip.
        expect(onAccepted).not.toHaveBeenCalled();
    });

    it('clears selection when the selected suggestion is decided', async () => {
        const { result } = setup();
        await waitFor(() => expect(result.current.loading).toBe(false));

        act(() => { result.current.setSelectedThreadId('thread-ai-1'); });
        expect(result.current.selectedThreadId).toBe('thread-ai-1');

        await act(async () => { await result.current.acceptSuggestion('thread-ai-1'); });

        // Otherwise the overlay keeps emphasising a marker that has left the queue.
        expect(result.current.selectedThreadId).toBeNull();
    });

    it('surfaces a server error instead of failing silently', async () => {
        const { result } = setup();
        await waitFor(() => expect(result.current.loading).toBe(false));

        handler = (url, options) => {
            if (options.method === 'POST') {
                return errJson({ error: 'A review is already running for this asset.' }, 409);
            }
            return defaultHandler(url);
        };

        await act(async () => { await result.current.runReview('brand_guidelines'); });

        expect(result.current.error).toBe('A review is already running for this asset.');
    });

    it('reports running while a review is in flight', async () => {
        handler = (url) => {
            if (url.includes('/ai_reviews/pending')) return okJson({ threads: [] });
            return okJson({ reviews: [RUNNING_REVIEW] });
        };

        const { result } = setup();

        await waitFor(() => expect(result.current.running).toBe(true));
    });

    it('polls while a review is in flight and stops once it completes', async () => {
        jest.useFakeTimers();
        handler = (url) => {
            if (url.includes('/ai_reviews/pending')) return okJson({ threads: [] });
            return okJson({ reviews: [RUNNING_REVIEW] });
        };

        const { result } = setup();
        await waitFor(() => expect(result.current.running).toBe(true));

        const duringRun = requests.length;
        await act(async () => { jest.advanceTimersByTime(4000); });
        expect(requests.length).toBeGreaterThan(duringRun);

        // Findings have landed; the run is terminal.
        handler = defaultHandler;
        await act(async () => { jest.advanceTimersByTime(4000); });
        await waitFor(() => expect(result.current.running).toBe(false));

        const afterCompletion = requests.length;
        await act(async () => { jest.advanceTimersByTime(20000); });

        // A finished run must not leave a timer ticking against the API.
        expect(requests.length).toBe(afterCompletion);
    });

    it('does not poll when no review is in flight', async () => {
        jest.useFakeTimers();
        const { result } = setup();
        await waitFor(() => expect(result.current.loading).toBe(false));

        const settled = requests.length;
        await act(async () => { jest.advanceTimersByTime(20000); });

        expect(requests.length).toBe(settled);
    });

    it('sends the CSRF token on mutating requests', async () => {
        const { result } = setup();
        await waitFor(() => expect(result.current.loading).toBe(false));

        await act(async () => { await result.current.runReview('composition'); });

        const call = global.fetch.mock.calls.find(([, opts]) => opts?.method === 'POST');
        expect(call[1].headers['X-CSRF-Token']).toBe('test-csrf');
    });
});
