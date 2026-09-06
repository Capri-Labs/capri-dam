import { useCallback, useEffect, useMemo, useState } from 'react';
import { anchorPoint } from '../../utils/annotationGeometry';

/**
 * Owns every piece of comment state for one asset.
 *
 * The comments UI is split across two sibling components — the annotation
 * overlay sits on the preview pane, the thread list sits in the inspector tab
 * — and they must stay in lockstep: hovering a marker highlights its thread,
 * selecting a thread highlights its marker, and a shape drawn on the overlay
 * becomes a pending attachment on the composer. Duplicating that state in both
 * components would guarantee they drift, so it is lifted into this hook and
 * the parent passes one object to both.
 */
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
        } catch {
            // Non-JSON error body (e.g. an HTML 500 page) — keep the status.
        }
        throw new Error(message);
    }

    return response.status === 204 ? null : response.json();
}

export default function useAssetComments({ assetId, enabled = true }) {
    const [threads, setThreads] = useState([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [saving, setSaving] = useState(false);

    // UI state shared between the overlay and the panel.
    const [tool, setTool] = useState(null);
    const [draft, setDraft] = useState([]);
    const [selectedThreadId, setSelectedThreadId] = useState(null);
    const [hoveredThreadId, setHoveredThreadId] = useState(null);
    const [versionFilter, setVersionFilter] = useState(null);
    const [unresolvedOnly, setUnresolvedOnly] = useState(false);

    const refresh = useCallback(async () => {
        if (!assetId || !enabled) return;

        setLoading(true);
        setError(null);
        try {
            const params = new URLSearchParams();
            if (versionFilter) params.set('version_id', versionFilter);
            if (unresolvedOnly) params.set('unresolved', 'true');
            const query = params.toString();

            const data = await request(`/api/v1/assets/${assetId}/comments${query ? `?${query}` : ''}`);
            setThreads(data?.threads || []);
        } catch (e) {
            setError(e.message);
            setThreads([]);
        } finally {
            setLoading(false);
        }
    }, [assetId, enabled, versionFilter, unresolvedOnly]);

    useEffect(() => { refresh(); }, [refresh]);

    const mutate = useCallback(async (fn) => {
        setSaving(true);
        setError(null);
        try {
            const result = await fn();
            await refresh();
            return result;
        } catch (e) {
            setError(e.message);
            return null;
        } finally {
            setSaving(false);
        }
    }, [refresh]);

    const createThread = useCallback(({ body, versionId, annotations, visibility }) => mutate(async () => {
        const thread = await request(`/api/v1/assets/${assetId}/comments`, {
            method: 'POST',
            body: JSON.stringify({
                body,
                asset_version_id: versionId,
                visibility: visibility || 'internal',
                annotations: annotations || [],
            }),
        });
        setDraft([]);
        setTool(null);
        return thread;
    }), [assetId, mutate]);

    const createReply = useCallback((threadId, { body, versionId, markAddressed, parentCommentId }) => mutate(
        () => request(`/api/v1/comment_threads/${threadId}/comments`, {
            method: 'POST',
            body: JSON.stringify({
                body,
                asset_version_id: versionId,
                parent_comment_id: parentCommentId,
                mark_addressed: Boolean(markAddressed),
            }),
        }),
    ), [mutate]);

    const updateComment = useCallback((commentId, body) => mutate(
        () => request(`/api/v1/comments/${commentId}`, { method: 'PATCH', body: JSON.stringify({ body }) }),
    ), [mutate]);

    const deleteComment = useCallback((commentId) => mutate(
        () => request(`/api/v1/comments/${commentId}`, { method: 'DELETE' }),
    ), [mutate]);

    const resolveThread = useCallback((threadId, status = 'resolved') => mutate(
        () => request(`/api/v1/comment_threads/${threadId}/resolve`, { method: 'PATCH', body: JSON.stringify({ status }) }),
    ), [mutate]);

    const reopenThread = useCallback((threadId) => mutate(
        () => request(`/api/v1/comment_threads/${threadId}/reopen`, { method: 'PATCH' }),
    ), [mutate]);

    const deleteThread = useCallback((threadId) => mutate(async () => {
        await request(`/api/v1/comment_threads/${threadId}`, { method: 'DELETE' });
        setSelectedThreadId((current) => (current === threadId ? null : current));
    }), [mutate]);

    const addDraftAnnotation = useCallback((annotation) => {
        setDraft((current) => [...current, annotation]);
        // One shape per click keeps the tool from "sticking" and littering the
        // image while the reviewer is typing.
        setTool(null);
    }, []);

    const removeDraftAnnotation = useCallback((index) => {
        setDraft((current) => current.filter((_, i) => i !== index));
    }, []);

    /**
     * Flattens every annotation across every thread into the list the overlay
     * renders, numbering the markers in the same order the panel lists the
     * threads so "pin 3" on the image is the third card in the sidebar.
     */
    const annotations = useMemo(() => {
        const ordered = [...threads].sort(
            (a, b) => new Date(a.created_at) - new Date(b.created_at),
        );

        return ordered.flatMap((thread, threadIndex) => {
            const all = (thread.comments || []).flatMap((comment) => comment.annotations || []);
            return all.map((annotation) => ({
                ...annotation,
                thread_id: annotation.thread_id || thread.id,
                marker_label: String(threadIndex + 1),
                resolved: thread.closed,
            }));
        });
    }, [threads]);

    /** Marker number for a thread, so the panel can show the same badge. */
    const markerLabels = useMemo(() => {
        const ordered = [...threads].sort(
            (a, b) => new Date(a.created_at) - new Date(b.created_at),
        );
        return ordered.reduce((acc, thread, index) => {
            acc[thread.id] = String(index + 1);
            return acc;
        }, {});
    }, [threads]);

    const unresolvedCount = useMemo(
        () => threads.filter((thread) => !thread.closed).length,
        [threads],
    );

    /** Where a thread's first marker sits, for scroll-into-view / zoom. */
    const threadAnchor = useCallback((threadId) => {
        const found = annotations.find((a) => a.thread_id === threadId);
        return found ? anchorPoint(found) : null;
    }, [annotations]);

    return {
        threads,
        annotations,
        markerLabels,
        unresolvedCount,
        loading,
        saving,
        error,
        clearError: () => setError(null),
        refresh,

        tool,
        setTool,
        draft,
        addDraftAnnotation,
        removeDraftAnnotation,
        clearDraft: () => setDraft([]),

        selectedThreadId,
        setSelectedThreadId,
        hoveredThreadId,
        setHoveredThreadId,
        threadAnchor,

        versionFilter,
        setVersionFilter,
        unresolvedOnly,
        setUnresolvedOnly,

        createThread,
        createReply,
        updateComment,
        deleteComment,
        resolveThread,
        reopenThread,
        deleteThread,
    };
}
