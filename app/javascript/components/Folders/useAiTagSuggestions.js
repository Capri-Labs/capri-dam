import { useCallback, useEffect, useState } from 'react';

/**
 * Owns the AI tag-suggestion queue for one asset.
 *
 * Accept and dismiss are kept as distinct calls rather than one "decide"
 * endpoint because they are not symmetrical: accepting writes a tag onto the
 * asset, dismissing only records a judgement. Collapsing them would hide that
 * asymmetry behind a parameter.
 */
const csrfToken = () => document.querySelector('[name="csrf-token"]')?.content;

const headers = () => ({
    'Content-Type': 'application/json',
    'X-CSRF-Token': csrfToken(),
});

async function readError(response) {
    let message = `HTTP ${response.status}`;
    try {
        const payload = await response.json();
        if (payload?.error) message = payload.error;
        else if (Array.isArray(payload?.errors) && payload.errors.length) message = payload.errors.join(', ');
    } catch {
        // Non-JSON body — the status is all we have.
    }
    return message;
}

export default function useAiTagSuggestions({ assetId, enabled = true }) {
    const [suggestions, setSuggestions] = useState([]);
    const [runs, setRuns] = useState([]);
    const [loading, setLoading] = useState(false);
    const [requesting, setRequesting] = useState(false);
    const [error, setError] = useState(null);

    const load = useCallback(async () => {
        if (!assetId || !enabled) return;
        setLoading(true);
        setError(null);
        try {
            const [ pendingRes, runsRes ] = await Promise.all([
                fetch(`/api/v1/assets/${assetId}/ai_tag_suggestions`, { credentials: 'same-origin' }),
                fetch(`/api/v1/assets/${assetId}/ai_tagging_runs`, { credentials: 'same-origin' }),
            ]);
            if (!pendingRes.ok) throw new Error(await readError(pendingRes));
            const pending = await pendingRes.json();
            setSuggestions(pending?.suggestions || []);
            // The run list is context, not the point of the screen; a failure
            // to load it must not blank out a perfectly good queue.
            if (runsRes.ok) {
                const runsPayload = await runsRes.json();
                setRuns(runsPayload?.runs || []);
            }
        } catch (e) {
            setError(e.message);
        } finally {
            setLoading(false);
        }
    }, [assetId, enabled]);

    useEffect(() => { load(); }, [load]);

    const requestRun = useCallback(async (profile = 'general_subject') => {
        if (!assetId) return false;
        setRequesting(true);
        setError(null);
        try {
            const response = await fetch(`/api/v1/assets/${assetId}/ai_tagging_runs`, {
                method: 'POST',
                credentials: 'same-origin',
                headers: headers(),
                body: JSON.stringify({ profile }),
            });
            if (!response.ok) throw new Error(await readError(response));
            const run = await response.json();
            setRuns((current) => [ run, ...current ]);
            return true;
        } catch (e) {
            setError(e.message);
            return false;
        } finally {
            setRequesting(false);
        }
    }, [assetId]);

    const decide = useCallback(async (id, action) => {
        setError(null);
        try {
            const response = await fetch(`/api/v1/ai_tag_suggestions/${id}/${action}`, {
                method: 'POST',
                credentials: 'same-origin',
                headers: headers(),
            });
            if (!response.ok) throw new Error(await readError(response));
            // Decided rows leave the queue either way: the queue is what is
            // still undecided, and a row that lingered would invite a second
            // click that the server would reject.
            setSuggestions((current) => current.filter((s) => s.id !== id));
            return await response.json();
        } catch (e) {
            setError(e.message);
            return null;
        }
    }, []);

    const accept = useCallback((id) => decide(id, 'accept'), [decide]);
    const dismiss = useCallback((id) => decide(id, 'dismiss'), [decide]);

    const latestRun = runs[0] || null;

    return {
        suggestions, runs, latestRun, loading, requesting, error, setError,
        reload: load, requestRun, accept, dismiss,
    };
}
