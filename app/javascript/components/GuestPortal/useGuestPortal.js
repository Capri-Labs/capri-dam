/**
 * Data layer for the distribution portal.
 *
 * WHY THIS IS NOT `useGuestReview`
 * --------------------------------
 * The two surfaces share a credential, not a job. The review hook carries
 * threads, annotations, drafts and comment permissions; a portal has none of
 * those and adds per-asset download permission instead. Merging them would
 * mean every partner collecting a logo also downloaded the annotation client,
 * and every change to one surface risked the other.
 */
import { useCallback, useEffect, useMemo, useState } from 'react';

/** @returns {string} the Rails CSRF token from the page meta tag */
function csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || '';
}

/**
 * Fetch wrapper for the portal API.
 *
 * Always sends the session cookie (passphrase clearance and guest identity
 * both live there) and always asks for JSON, so a denial renders as a JSON
 * error rather than the HTML "unavailable" page.
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
 * @param {string} token the portal link token from the page URL
 */
export default function useGuestPortal(token) {
    const base = useMemo(() => `/s/portal/${token}`, [token]);

    const [portal, setPortal] = useState(null);
    const [guest, setGuest] = useState(null);
    const [assets, setAssets] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    // Set when the link is passphrase-protected and not yet unlocked.
    const [locked, setLocked] = useState(false);

    const load = useCallback(async () => {
        setLoading(true);
        try {
            const data = await request(`${base}/assets`);
            setPortal(data.portal);
            setGuest(data.guest);
            setAssets(data.assets || []);
            setLocked(false);
            setError(null);
        } catch (e) {
            // 401 means "passphrase first", which is a state to render, not an
            // error to report.
            if (e.status === 401) {
                setLocked(true);
                setError(null);
            } else {
                setError(e.message);
            }
        } finally {
            setLoading(false);
        }
    }, [base]);

    useEffect(() => { load(); }, [load]);

    const unlock = useCallback(async (passphrase) => {
        await request(`${base}/unlock`, { method: 'POST', body: JSON.stringify({ passphrase }) });
        await load();
    }, [base, load]);

    const identify = useCallback(async ({ email, name }) => {
        const data = await request(`${base}/identify`, {
            method: 'POST',
            body: JSON.stringify({ email, name }),
        });
        setGuest(data.guest);
        // The download endpoint attributes to whoever the session says we are,
        // so the list is refetched to pick up anything gated on identity.
        await load();
        return data.guest;
    }, [base, load]);

    return { portal, guest, assets, loading, error, locked, unlock, identify, reload: load };
}
