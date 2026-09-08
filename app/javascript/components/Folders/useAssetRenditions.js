import { useCallback, useEffect, useState } from 'react';

/**
 * Owns the manual-rendition state for one asset.
 *
 * Uploads here are multipart, not JSON, because the payload is a file and
 * base64-in-JSON would inflate a 200 MB print master by a third for no gain.
 * That means this hook cannot share the JSON request helper the comments hook
 * uses — the browser must be left to set its own multipart boundary, so the
 * Content-Type header is deliberately absent on create.
 */
const csrfToken = () => document.querySelector('[name="csrf-token"]')?.content;

async function readError(response) {
    let message = `HTTP ${response.status}`;
    try {
        const payload = await response.json();
        if (Array.isArray(payload?.errors) && payload.errors.length) message = payload.errors.join(', ');
        else if (payload?.error) message = payload.error;
    } catch {
        // Non-JSON body (an HTML 500 page, say) — the status is all we have.
    }
    return message;
}

export default function useAssetRenditions({ assetId, enabled = true }) {
    const [renditions, setRenditions] = useState([]);
    const [loading, setLoading] = useState(false);
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState(null);

    const base = assetId ? `/api/v1/assets/${assetId}/renditions` : null;

    const load = useCallback(async () => {
        if (!base || !enabled) return;
        setLoading(true);
        setError(null);
        try {
            const response = await fetch(base, { credentials: 'same-origin' });
            if (!response.ok) throw new Error(await readError(response));
            const payload = await response.json();
            setRenditions(payload?.renditions || []);
        } catch (e) {
            setError(e.message);
        } finally {
            setLoading(false);
        }
    }, [base, enabled]);

    useEffect(() => { load(); }, [load]);

    const upload = useCallback(async ({ file, kind }) => {
        if (!base) return false;
        setSaving(true);
        setError(null);
        try {
            const form = new FormData();
            form.append('file', file);
            form.append('kind', kind);
            const response = await fetch(base, {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'X-CSRF-Token': csrfToken() },
                body: form,
            });
            if (!response.ok) throw new Error(await readError(response));
            const created = await response.json();
            // Append locally rather than refetching: the list is small and the
            // server has already told us exactly what it stored.
            setRenditions((current) => [ ...current, created ]);
            return true;
        } catch (e) {
            setError(e.message);
            return false;
        } finally {
            setSaving(false);
        }
    }, [base]);

    const remove = useCallback(async (id) => {
        if (!base) return false;
        setSaving(true);
        setError(null);
        try {
            const response = await fetch(`${base}/${id}`, {
                method: 'DELETE',
                credentials: 'same-origin',
                headers: { 'X-CSRF-Token': csrfToken() },
            });
            if (!response.ok) throw new Error(await readError(response));
            setRenditions((current) => current.filter((r) => r.id !== id));
            return true;
        } catch (e) {
            setError(e.message);
            return false;
        } finally {
            setSaving(false);
        }
    }, [base]);

    return { renditions, loading, saving, error, setError, reload: load, upload, remove };
}
