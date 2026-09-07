import React, { useCallback, useEffect, useState } from 'react';
import PropTypes from 'prop-types';
import {
    Alert, Box, Button, Chip, MenuItem, Stack, TextField, Typography,
} from '@mui/material';
import { GavelOutlined } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';

/**
 * Editor for an asset's distribution rights: what it may be used for, and until
 * when.
 *
 * These two fields decide whether the asset can leave the organisation at all
 * (see Rights::DownloadPolicy on the server), so they are deliberately edited
 * here rather than through the schema-driven metadata panel. Metadata fields are
 * descriptive and free-form; these are enforced, and the set of legal values
 * comes from the server so the dropdown cannot drift from the vocabulary the
 * policy actually checks.
 */
export default function AssetRightsPanel({ asset, onAssetUpdated }) {
    const { t } = useTranslation();
    const notify = useNotify();

    const rights = asset?.rights ?? {};
    const [options, setOptions] = useState([]);
    const [usageTerms, setUsageTerms] = useState(rights.usage_terms ?? '');
    // The input is a date, the column is a timestamp. Slicing to the date part
    // is safe because the server reads a bare date as end-of-day.
    const [expiresAt, setExpiresAt] = useState((rights.license_expires_at ?? '').slice(0, 10));
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState('');

    useEffect(() => {
        setUsageTerms(asset?.rights?.usage_terms ?? '');
        setExpiresAt((asset?.rights?.license_expires_at ?? '').slice(0, 10));
    }, [asset?.id, asset?.rights?.usage_terms, asset?.rights?.license_expires_at]);

    useEffect(() => {
        let cancelled = false;
        fetch('/api/v1/rights/usage_terms', { headers: { Accept: 'application/json' } })
            .then((res) => (res.ok ? res.json() : Promise.reject(new Error('unavailable'))))
            .then((data) => { if (!cancelled) setOptions(data.usage_terms ?? []); })
            // A failed lookup must not silently offer an empty dropdown that
            // looks like "this asset has no rights options".
            .catch(() => { if (!cancelled) setError(t('assetRights.errors.optionsUnavailable')); });
        return () => { cancelled = true; };
    }, [t]);

    const dirty = usageTerms !== (rights.usage_terms ?? '')
        || expiresAt !== (rights.license_expires_at ?? '').slice(0, 10);

    const handleSave = useCallback(async () => {
        setSaving(true);
        setError('');
        try {
            const res = await fetch(`/api/v1/assets/${asset.id}`, {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
                body: JSON.stringify({
                    usage_terms: usageTerms,
                    // Empty string, not undefined: the user clearing the field
                    // means "no expiry", which has to be distinguishable from
                    // "not editing this field".
                    license_expires_at: expiresAt === '' ? null : expiresAt,
                }),
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.error ?? t('assetRights.errors.saveFailed'));

            notify(t('assetRights.notifications.saved'), 'success');
            if (onAssetUpdated) onAssetUpdated(data);
        } catch (e) {
            setError(e.message);
            notify(e.message, 'error');
        } finally {
            setSaving(false);
        }
    }, [asset?.id, usageTerms, expiresAt, notify, onAssetUpdated, t]);

    if (!asset) return null;

    return (
        <Box data-testid="asset-rights-panel" sx={{ mt: 2 }}>
            <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                <GavelOutlined fontSize="small" />
                <Typography variant="subtitle2" fontWeight={600}>
                    {t('assetRights.title')}
                </Typography>
                {rights.license_expired && (
                    <Chip
                        size="small"
                        color="error"
                        label={t('assetRights.expiredBadge')}
                        data-testid="asset-rights-expired"
                    />
                )}
                {!rights.externally_distributable && !rights.license_expired && (
                    <Chip
                        size="small"
                        color="warning"
                        label={t('assetRights.internalBadge')}
                        data-testid="asset-rights-internal"
                    />
                )}
            </Stack>

            <Typography variant="caption" color="text.secondary" component="div" sx={{ mb: 1.5 }}>
                {t('assetRights.description')}
            </Typography>

            {error && <Alert severity="error" sx={{ mb: 1.5 }}>{error}</Alert>}

            <Stack spacing={2}>
                <TextField
                    select
                    size="small"
                    fullWidth
                    label={t('assetRights.usageTermsLabel')}
                    value={usageTerms}
                    onChange={(e) => setUsageTerms(e.target.value)}
                    slotProps={{ htmlInput: { 'data-testid': 'asset-rights-usage-terms' } }}
                >
                    {options.map((option) => (
                        <MenuItem key={option.code} value={option.code}>
                            {option.label}
                            {!option.external && ` — ${t('assetRights.notDistributable')}`}
                        </MenuItem>
                    ))}
                </TextField>

                <TextField
                    type="date"
                    size="small"
                    fullWidth
                    label={t('assetRights.licenseExpiresLabel')}
                    value={expiresAt}
                    onChange={(e) => setExpiresAt(e.target.value)}
                    helperText={t('assetRights.licenseExpiresHelp')}
                    slotProps={{
                        inputLabel: { shrink: true },
                        htmlInput: { 'data-testid': 'asset-rights-expires-at' },
                    }}
                />

                <Box>
                    <Button
                        size="small"
                        variant="contained"
                        onClick={handleSave}
                        disabled={saving || !dirty}
                        data-testid="asset-rights-save"
                    >
                        {saving ? t('common.saving') : t('assetRights.save')}
                    </Button>
                </Box>
            </Stack>
        </Box>
    );
}

AssetRightsPanel.propTypes = {
    asset: PropTypes.object,
    onAssetUpdated: PropTypes.func,
};
