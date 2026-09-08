import { useEffect, useRef, useState } from 'react';

/**
 * Live result count for the query as it currently stands.
 *
 * Debounced because the count is recomputed on every keystroke in a value box,
 * and an un-debounced version would issue a `COUNT(*)` per character. The
 * in-flight request is abandoned when a newer one starts, so a slow early
 * response cannot overwrite the count for a query the user has since changed —
 * the classic race that makes a live count show the wrong number and stay there.
 */
const DEBOUNCE_MS = 400;

export default function useQueryCount(ast, { enabled = true } = {}) {
    const [count, setCount] = useState(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const requestId = useRef(0);

    const serialised = JSON.stringify(ast ?? null);

    useEffect(() => {
        if (!enabled) return undefined;

        const id = ++requestId.current;
        const timer = setTimeout(async () => {
            setLoading(true);
            setError(null);
            try {
                const response = await fetch('/api/v1/search/count', {
                    method: 'POST',
                    credentials: 'same-origin',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content,
                    },
                    body: JSON.stringify({ query: JSON.parse(serialised) }),
                });
                const payload = await response.json().catch(() => ({}));
                if (id !== requestId.current) return;

                if (!response.ok) {
                    setError(payload.error || `HTTP ${response.status}`);
                    setCount(null);
                } else {
                    setCount(payload.count);
                }
            } catch (e) {
                if (id === requestId.current) setError(e.message);
            } finally {
                if (id === requestId.current) setLoading(false);
            }
        }, DEBOUNCE_MS);

        return () => clearTimeout(timer);
    }, [serialised, enabled]);

    return { count, loading, error };
}
