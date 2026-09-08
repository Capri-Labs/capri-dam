import { useEffect, useState } from 'react';

/**
 * Loads the server's field allow-list.
 *
 * The list is deliberately not hardcoded in the client: the same registry that
 * answers this endpoint is what the query compiler enforces, so a field offered
 * here is always a field the server will accept. A client-side copy would drift
 * the first time someone added a field to one and not the other, and the failure
 * would look like a broken query rather than a stale constant.
 */
const DEFAULT_LIMITS = { max_depth: 8, max_nodes: 100, max_list_values: 50 };

export default function useQueryFields() {
    const [fields, setFields] = useState([]);
    const [limits, setLimits] = useState(DEFAULT_LIMITS);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        let cancelled = false;

        (async () => {
            try {
                const response = await fetch('/api/v1/search/fields', { credentials: 'same-origin' });
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                const payload = await response.json();
                if (cancelled) return;
                setFields(payload.fields || []);
                setLimits({ ...DEFAULT_LIMITS, ...(payload.limits || {}) });
            } catch (e) {
                if (!cancelled) setError(e.message);
            } finally {
                if (!cancelled) setLoading(false);
            }
        })();

        return () => { cancelled = true; };
    }, []);

    const fieldsByName = Object.fromEntries(fields.map((f) => [ f.name, f ]));

    return { fields, fieldsByName, limits, loading, error };
}
