/**
 * Data layer for the guest review surface.
 *
 * WHY THIS IS NOT `useAssetComments`
 * ----------------------------------
 * The internal hook talks to `/api/v1/**`, which requires a Devise session or
 * an OAuth token, and it sends `visibility` on create. None of that applies
 * here: a guest is authenticated solely by the token in the URL, may only see
 * guest-visible threads, and must never be able to influence visibility.
 *
 * Sharing the hook would have meant threading an `isGuest` flag through every
 * request path — the exact "one flag away from a leak" shape the backend
 * deliberately avoids. This is a separate, much smaller client for a
 * separate, much smaller API.
 */
import { useCallback, useEffect, useMemo, useState } from 'react';

/** @returns {string} the Rails CSRF token from the page meta tag */
function csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || '';
}

/**
 * Fetch wrapper for the guest API.
 *
 * Always sends the session cookie (the passphrase clearance and the guest
 * identity both live there) and always asks for JSON, so a denial renders as
 * a JSON error rather than the HTML "unavailable" page.
 */
async function request(url, options = {}) {
    const response = await fetch(url, {
        credentials: 'same-origin',
        ...options,
        headers: {
            'Content-Type': 'application/json',
            Accept: 'application/json',
            'X-CSRF-Token': csrfToken(),
            ...(options.headers || {}),
        },
    });

    let payload = null;
    try {
        payload = await response.json();
    } catch {
        payload = null;
    }

    if (!response.ok) {
        const error = new Error(payload?.error || 'Something went wrong.');
        error.status = response.status;
        error.reason = payload?.reason;
        throw error;
    }

    return payload;
}

/**
 * @param {string} token the review link token from the page URL
 */
export default function useGuestReview(token) {
    const base = useMemo(() => `/s/reviews/${token}`, [token]);

    const [review, setReview] = useState(null);
    const [guest, setGuest] = useState(null);
    const [assets, setAssets] = useState([]);
    const [selectedAssetId, setSelectedAssetId] = useState(null);
    const [threads, setThreads] = useState([]);
    const [canComment, setCanComment] = useState(false);
    const [loading, setLoading] = useState(true);
    const [threadsLoading, setThreadsLoading] = useState(false);
    const [error, setError] = useState(null);

    const loadAssets = useCallback(async () => {
        setLoading(true);
        try {
            const data = await request(`${base}/assets`);
            setReview(data.review);
            setGuest(data.guest);
            setAssets(data.assets || []);
            // Open the first asset automatically. A review link usually points
            // at one thing, and making the reviewer click once more before
            // seeing it serves nobody.
            setSelectedAssetId((current) => current || data.assets?.[0]?.id || null);
            setError(null);
        } catch (e) {
            setError(e.message);
        } finally {
            setLoading(false);
        }
    }, [base]);

    const loadThreads = useCallback(async (assetId) => {
        if (!assetId) return;
        setThreadsLoading(true);
        try {
            const data = await request(`${base}/assets/${assetId}/threads`);
            setThreads(data.threads || []);
            setCanComment(Boolean(data.can_comment));
        } catch (e) {
            setError(e.message);
        } finally {
            setThreadsLoading(false);
        }
    }, [base]);

    useEffect(() => { loadAssets(); }, [loadAssets]);
    useEffect(() => { loadThreads(selectedAssetId); }, [selectedAssetId, loadThreads]);

    const identify = useCallback(async ({ email, name }) => {
        const data = await request(`${base}/identify`, {
            method: 'POST',
            body: JSON.stringify({ email, name }),
        });
        setGuest(data.guest);
        // Identifying may unlock commenting, which is reported alongside the
        // threads rather than with the guest.
        await loadThreads(selectedAssetId);
        return data.guest;
    }, [base, selectedAssetId, loadThreads]);

    const createThread = useCallback(async ({ body, annotations }) => {
        const data = await request(`${base}/assets/${selectedAssetId}/comments`, {
            method: 'POST',
            body: JSON.stringify({ body, annotations: annotations || [] }),
        });
        setThreads((current) => [...current, data.thread]);
        return data.thread;
    }, [base, selectedAssetId]);

    const createReply = useCallback(async (threadId, { body }) => {
        const data = await request(`${base}/threads/${threadId}/comments`, {
            method: 'POST',
            body: JSON.stringify({ body }),
        });
        // Appended locally rather than refetching the whole asset: a reply is
        // additive, and a full reload would scroll the reviewer away from what
        // they were reading.
        setThreads((current) => current.map((thread) => (
            thread.id === threadId
                ? { ...thread, comments: [...(thread.comments || []), data.comment] }
                : thread
        )));
        return data.comment;
    }, [base]);

    const selectedAsset = useMemo(
        () => assets.find((asset) => asset.id === selectedAssetId) || null,
        [assets, selectedAssetId],
    );

    // Every annotation across every visible thread, tagged with its thread so
    // the overlay can highlight the one being read.
    const annotations = useMemo(() => threads.flatMap((thread) => (
        (thread.comments || []).flatMap((comment) => (
            (comment.annotations || []).map((annotation) => ({
                ...annotation,
                thread_id: thread.id,
            }))
        ))
    )), [threads]);

    return {
        review,
        guest,
        assets,
        selectedAsset,
        selectedAssetId,
        setSelectedAssetId,
        threads,
        annotations,
        canComment,
        loading,
        threadsLoading,
        error,
        identify,
        createThread,
        createReply,
        reload: loadAssets,
    };
}
