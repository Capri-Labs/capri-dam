/**
 * Data layer for the distribution portal management screen.
 *
 * Every call goes to `/api/v1/portals`, which scopes results to the current
 * user unless they are an administrator — the UI does no filtering of its own,
 * because a permission enforced in the browser is not enforced at all.
 */
import { useCallback, useEffect, useState } from 'react';
import { csrfToken } from '../../utils/format';

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
        // The API reports validation problems as `errors` (an array) and
        // everything else as `error`. Flattening here keeps every caller from
        // having to know which shape it is about to get.
        const message = payload?.errors?.join(', ') || payload?.error || 'Something went wrong.';
        const error = new Error(message);
        error.status = response.status;
        throw error;
    }

    return payload;
}

export default function usePortals() {
    const [portals, setPortals] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    const load = useCallback(async () => {
        setLoading(true);
        try {
            const data = await request('/api/v1/portals');
            setPortals(data.portals || []);
            setError(null);
        } catch (e) {
            setError(e.message);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => { load(); }, [load]);

    // Returns the created portal, which carries the only copy of the token
    // that will ever exist — the caller must show it before discarding it.
    const create = useCallback(async (payload) => {
        const portal = await request('/api/v1/portals', {
            method: 'POST',
            body: JSON.stringify(payload),
        });
        await load();
        return portal;
    }, [load]);

    const update = useCallback(async (id, payload) => {
        const portal = await request(`/api/v1/portals/${id}`, {
            method: 'PATCH',
            body: JSON.stringify(payload),
        });
        await load();
        return portal;
    }, [load]);

    const revoke = useCallback(async (id) => {
        await request(`/api/v1/portals/${id}`, { method: 'DELETE' });
        await load();
    }, [load]);

    // Not part of the list payload: the full asset pick list is only fetched
    // when somebody actually opens a portal to edit it.
    const fetchPortal = useCallback((id) => request(`/api/v1/portals/${id}`), []);

    const fetchDownloads = useCallback((id) => request(`/api/v1/portals/${id}/downloads`), []);

    return { portals, loading, error, reload: load, create, update, revoke, fetchPortal, fetchDownloads };
}
