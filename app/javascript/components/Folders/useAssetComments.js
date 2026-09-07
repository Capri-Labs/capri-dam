import { useCallback, useEffect, useMemo, useState } from 'react';
import { anchorPoint, isTemporal, isVisibleAtFrame } from '../../utils/annotationGeometry';

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

    // ---- Video review state -------------------------------------------------
    // Kept here rather than in the player because the composer needs to stamp a
    // new comment with the frame the reviewer was looking at, the panel needs
    // to seek the player when a timecode chip is clicked, and the overlay needs
    // to hide markers that belong to a different part of the timeline. Three
    // separate components, one play head.
    const [currentFrame, setCurrentFrame] = useState(0);
    const [inPoint, setInPoint] = useState(null);
    const [outPoint, setOutPoint] = useState(null);
    const [loopRange, setLoopRange] = useState(false);
    // A monotonic token, not just a frame: clicking the same chip twice after
    // scrubbing away must seek again, which a bare value could not express.
    const [seekRequest, setSeekRequest] = useState(null);

    const seekToFrame = useCallback((frame) => {
        if (frame == null) return;
        setSeekRequest({ frame, token: Date.now() + Math.random() });
    }, []);

    const setRangeIn = useCallback((frame) => {
        setInPoint(frame);
        // An out point that now precedes the in point is nonsense, so drop it
        // rather than silently storing an inverted range the API would reject.
        setOutPoint((current) => (current != null && current <= frame ? null : current));
    }, []);

    const setRangeOut = useCallback((frame) => {
        setOutPoint(frame);
        setInPoint((current) => (current != null && current >= frame ? null : current));
    }, []);

    const clearRange = useCallback(() => {
        setInPoint(null);
        setOutPoint(null);
        setLoopRange(false);
    }, []);

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
        clearRange();
        return thread;
    }), [assetId, mutate, clearRange]);

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

    /**
     * Attaches the current play head (or the selected in/out range) to the
     * pending comment without drawing anything.
     *
     * "The music is too loud from 0:12 to 0:20" is a comment about a moment,
     * not about a region, and forcing the reviewer to scribble a shape
     * somewhere on the frame just to record a time would be noise on the
     * image. Hence the spatially-empty `time` shape.
     */
    const addTimeDraft = useCallback(({ fps, dropFrame }) => {
        if (!fps) return;

        const start = inPoint != null ? inPoint : currentFrame;
        const end = inPoint != null && outPoint != null && outPoint > inPoint ? outPoint : null;

        setDraft((current) => [
            ...current,
            {
                media_type: 'video',
                shape: 'time',
                bbox: { x: 0, y: 0, w: 0, h: 0 },
                svg_path: null,
                video: {
                    start_frame: Math.max(0, Math.trunc(start || 0)),
                    end_frame: end != null ? Math.trunc(end) : null,
                    fps,
                    drop_frame: Boolean(dropFrame),
                },
            },
        ]);
    }, [currentFrame, inPoint, outPoint]);

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

    /**
     * The annotations the overlay should actually draw on the video right now.
     *
     * Rendering every frame's markup at once would bury the picture under
     * every note ever left on the clip, so a temporal annotation is only shown
     * while the play head is inside its range (or close to its instant).
     * `time` targets are excluded outright — they have no spatial extent and
     * live on the scrubber's marker track instead.
     */
    const visibleAnnotations = useMemo(
        () => annotations.filter(
            (annotation) => annotation.shape !== 'time' && isVisibleAtFrame(annotation, currentFrame),
        ),
        [annotations, currentFrame],
    );

    /** Every annotation that carries a frame, for the scrubber marker track. */
    const temporalAnnotations = useMemo(
        () => annotations.filter(isTemporal),
        [annotations],
    );

    /** Where a thread's first marker sits, for scroll-into-view / zoom. */
    const threadAnchor = useCallback((threadId) => {
        const found = annotations.find((a) => a.thread_id === threadId);
        return found ? anchorPoint(found) : null;
    }, [annotations]);

    /** The earliest frame a thread refers to, so selecting it can seek there. */
    const threadFrame = useCallback((threadId) => {
        const frames = annotations
            .filter((a) => a.thread_id === threadId && isTemporal(a))
            .map((a) => a.video.start_frame);
        return frames.length > 0 ? Math.min(...frames) : null;
    }, [annotations]);

    return {
        threads,
        annotations,
        visibleAnnotations,
        temporalAnnotations,
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
        addTimeDraft,
        removeDraftAnnotation,
        clearDraft: () => setDraft([]),

        selectedThreadId,
        setSelectedThreadId,
        hoveredThreadId,
        setHoveredThreadId,
        threadAnchor,
        threadFrame,

        currentFrame,
        setCurrentFrame,
        inPoint,
        outPoint,
        setRangeIn,
        setRangeOut,
        clearRange,
        loopRange,
        setLoopRange,
        seekRequest,
        seekToFrame,

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
