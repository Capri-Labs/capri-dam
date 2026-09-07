import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

/**
 * Owns the AI review assistant's state for one asset: the run history, the
 * queue of suggestions awaiting a human decision, and the accept/dismiss
 * actions that triage them.
 *
 * WHY THIS IS SEPARATE FROM `useAssetComments`
 * -------------------------------------------
 * A pending suggestion is deliberately *not* returned by the comments
 * endpoint — the API filters it out of every human and guest listing until
 * somebody accepts it, so a model's guess can never surface as though a
 * colleague had written it. Folding suggestions into `useAssetComments` would
 * mean re-mixing the two sets in the client, which is exactly the confusion
 * the server-side split exists to prevent. Keeping them in separate hooks
 * means the only place they meet is the overlay, where each is drawn in its
 * own colour.
 *
 * WHY IT POLLS
 * ------------
 * A run is dispatched to an external AI gateway over Redis and its findings
 * arrive later via a server-to-server callback. Nothing pushes to the browser,
 * so an in-flight review is polled until it reaches a terminal state. Polling
 * stops the moment it does — this is not a background ticker.
 */
const POLL_INTERVAL_MS = 4000;
const IN_FLIGHT = ['queued', 'running'];

const jsonHeaders = () => ({
    'Content-Type': 'application/json',
    'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content,
});

async function request(url, options = {}) {
    const response = await fetch(url, {
        headers: jsonHeaders(),
        credentials: 'same-origin',
        ...options,
    });

    if (!response.ok) {
        let message = `HTTP ${response.status}`;
        try {
            const payload = await response.json();
            if (payload?.error) message = payload.error;
            else if (payload?.errors) message = payload.errors.join(', ');
        } catch {
            // Non-JSON error body (e.g. an HTML 500 page) — keep the status.
        }
        throw new Error(message);
    }

    return response.status === 204 ? null : response.json();
}

export default function useAiReview({ assetId, enabled = true, onAccepted }) {
    const [reviews, setReviews] = useState([]);
    const [suggestions, setSuggestions] = useState([]);
    const [loading, setLoading] = useState(false);
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState(null);
    const [selectedThreadId, setSelectedThreadId] = useState(null);
    const [hoveredThreadId, setHoveredThreadId] = useState(null);

    // Read inside the polling effect so that changing it does not tear down and
    // recreate the timer on every tick.
    const onAcceptedRef = useRef(onAccepted);
    useEffect(() => { onAcceptedRef.current = onAccepted; }, [onAccepted]);

    const refresh = useCallback(async () => {
        if (!assetId || !enabled) return;

        setLoading(true);
        try {
            const [pending, history] = await Promise.all([
                request(`/api/v1/assets/${assetId}/ai_reviews/pending`),
                request(`/api/v1/assets/${assetId}/ai_reviews`),
            ]);
            setSuggestions(pending?.threads || []);
            setReviews(history?.reviews || []);
            setError(null);
        } catch (e) {
            setError(e.message);
        } finally {
            setLoading(false);
        }
    }, [assetId, enabled]);

    useEffect(() => { refresh(); }, [refresh]);

    const latestReview = reviews[0] || null;
    const running = Boolean(latestReview && IN_FLIGHT.includes(latestReview.status));

    // Poll only while a run is actually in flight.
    useEffect(() => {
        if (!running || !enabled) return undefined;

        const timer = setInterval(refresh, POLL_INTERVAL_MS);
        return () => clearInterval(timer);
    }, [running, enabled, refresh]);

    const act = useCallback(async (fn) => {
        setBusy(true);
        setError(null);
        try {
            const result = await fn();
            await refresh();
            return result;
        } catch (e) {
            setError(e.message);
            return null;
        } finally {
            setBusy(false);
        }
    }, [refresh]);

    const runReview = useCallback((profile) => act(
        () => request(`/api/v1/assets/${assetId}/ai_reviews`, {
            method: 'POST',
            body: JSON.stringify({ profile }),
        }),
    ), [assetId, act]);

    const decide = useCallback((threadId, decision) => act(async () => {
        const path = decision === 'accept' ? 'accept_suggestion' : 'dismiss_suggestion';
        const result = await request(`/api/v1/comment_threads/${threadId}/${path}`, { method: 'POST' });

        // Drop the highlight with the card it belonged to, otherwise the
        // overlay keeps emphasising a marker that is no longer in the queue.
        setSelectedThreadId((current) => (current === threadId ? null : current));
        setHoveredThreadId((current) => (current === threadId ? null : current));

        // An accepted suggestion becomes a real thread, so the comments list
        // alongside this panel is now stale.
        if (decision === 'accept') onAcceptedRef.current?.();

        return result;
    }), [act]);

    const acceptSuggestion = useCallback((threadId) => decide(threadId, 'accept'), [decide]);
    const dismissSuggestion = useCallback((threadId) => decide(threadId, 'dismiss'), [decide]);

    /**
     * Suggestion geometry for the overlay.
     *
     * The server already stamps these annotations with the assistant's purple
     * (`#a855f7`), so no colour is applied here — a machine suggestion must
     * look unmistakably unlike a colleague's markup, and having one source for
     * that decision keeps the API export and the UI in agreement.
     */
    const annotations = useMemo(() => suggestions.flatMap((thread) => {
        const all = (thread.comments || []).flatMap((comment) => comment.annotations || []);
        return all.map((annotation) => ({
            ...annotation,
            thread_id: annotation.thread_id || thread.id,
            marker_label: 'AI',
        }));
    }), [suggestions]);

    return {
        reviews,
        latestReview,
        suggestions,
        annotations,
        pendingCount: suggestions.length,
        running,
        loading,
        busy,
        error,
        clearError: () => setError(null),
        refresh,
        runReview,
        acceptSuggestion,
        dismissSuggestion,
        selectedThreadId,
        setSelectedThreadId,
        hoveredThreadId,
        setHoveredThreadId,
    };
}
