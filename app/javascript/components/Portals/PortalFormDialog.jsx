import React, { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Dialog, DialogTitle, DialogContent, DialogActions, Button, TextField,
    Stack, FormControl, InputLabel, Select, MenuItem, FormControlLabel,
    Switch, Divider, Typography, CircularProgress, Box, Alert,
} from '@mui/material';
import PortalGrantsPanel from './PortalGrantsPanel';

const EMPTY_BRANDING = { accent: '', headline: '', message: '', logo_url: '' };

// <input type="datetime-local"> wants a local, second-less value; the API
// speaks ISO 8601. These two keep that translation in one place.
function toLocalInput(iso) {
    if (!iso) return '';
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return '';
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function fromLocalInput(value) {
    if (!value) return null;
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function grantsFromAssets(assets) {
    const map = {};
    (assets || []).forEach((asset) => {
        map[String(asset.id)] = asset.granted ? (asset.permission || 'view') : 'none';
    });
    return map;
}

/**
 * Create or reconfigure a portal.
 *
 * The target is only choosable at creation. Re-pointing a live portal at a
 * different collection would hand an outsider material they were never shown
 * while the URL in their inbox looks unchanged, so the API refuses it and the
 * UI does not offer it.
 */
export default function PortalFormDialog({ open, portal, collections, onClose, onSubmit, fetchPortal }) {
    const { t } = useTranslation();
    const editing = Boolean(portal);

    const [name, setName] = useState('');
    const [collectionId, setCollectionId] = useState('');
    const [expiresAt, setExpiresAt] = useState('');
    const [requireEmail, setRequireEmail] = useState(false);
    const [passphrase, setPassphrase] = useState('');
    const [branding, setBranding] = useState(EMPTY_BRANDING);
    const [assets, setAssets] = useState([]);
    const [grants, setGrants] = useState({});
    const [loading, setLoading] = useState(false);
    const [submitting, setSubmitting] = useState(false);
    const [error, setError] = useState(null);

    useEffect(() => {
        if (!open) return;

        setError(null);
        setPassphrase('');

        if (!editing) {
            setName('');
            setCollectionId('');
            setExpiresAt('');
            setRequireEmail(false);
            setBranding(EMPTY_BRANDING);
            setAssets([]);
            setGrants({});
            return;
        }

        setName(portal.name || '');
        setCollectionId(portal.collection_id ? String(portal.collection_id) : '');
        setExpiresAt(toLocalInput(portal.expires_at));
        setRequireEmail(Boolean(portal.require_email));
        setBranding({ ...EMPTY_BRANDING, ...(portal.branding || {}) });

        // The pick list is not part of the index payload — fetch it only when
        // somebody actually opens a portal to edit.
        setLoading(true);
        fetchPortal(portal.id)
            .then((full) => {
                setAssets(full.assets || []);
                setGrants(grantsFromAssets(full.assets));
            })
            .catch((e) => setError(e.message))
            .finally(() => setLoading(false));
    }, [open, editing, portal, fetchPortal]);

    const updateBranding = (key, value) => setBranding((prev) => ({ ...prev, [key]: value }));

    const handleSubmit = async () => {
        if (!editing && !collectionId) {
            setError(t('portalManager.form.targetRequired'));
            return;
        }

        const payload = {
            name: name.trim(),
            expires_at: fromLocalInput(expiresAt),
            require_email: requireEmail,
            branding: {
                accent: branding.accent || '',
                headline: branding.headline || '',
                message: branding.message || '',
                logo_url: branding.logo_url || '',
            },
        };

        if (!editing) payload.collection_id = collectionId;

        // Sending an empty passphrase on edit would clear the one already set;
        // blank means "leave it alone", which is what the helper text promises.
        if (passphrase.trim()) payload.passphrase = passphrase.trim();

        if (editing) {
            payload.grants = Object.entries(grants)
                .filter(([, permission]) => permission && permission !== 'none')
                .map(([asset_id, permission]) => ({ asset_id, permission }));
        }

        setSubmitting(true);
        setError(null);
        try {
            await onSubmit(payload);
        } catch (e) {
            setError(e.message);
        } finally {
            setSubmitting(false);
        }
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
            <DialogTitle>
                {editing ? t('portalManager.form.editTitle') : t('portalManager.form.createTitle')}
            </DialogTitle>
            <DialogContent dividers>
                <Stack spacing={2} sx={{ mt: 1 }}>
                    {error && <Alert severity="error">{error}</Alert>}

                    <TextField
                        label={t('portalManager.form.name')}
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        fullWidth
                    />

                    {!editing && (
                        <FormControl fullWidth>
                            <InputLabel id="portal-target-label">{t('portalManager.form.collection')}</InputLabel>
                            <Select
                                labelId="portal-target-label"
                                label={t('portalManager.form.collection')}
                                value={collectionId}
                                onChange={(e) => setCollectionId(e.target.value)}
                            >
                                {(collections || []).map((collection) => (
                                    <MenuItem key={collection.id} value={String(collection.id)}>
                                        {collection.name || collection.slug}
                                    </MenuItem>
                                ))}
                            </Select>
                        </FormControl>
                    )}

                    {editing && (
                        <Typography variant="body2" color="text.secondary">
                            {t('portalManager.form.targetLocked', { target: portal.target_label || '' })}
                        </Typography>
                    )}

                    <TextField
                        label={t('portalManager.form.expiresAt')}
                        type="datetime-local"
                        value={expiresAt}
                        onChange={(e) => setExpiresAt(e.target.value)}
                        fullWidth
                        slotProps={{ inputLabel: { shrink: true } }}
                    />

                    <TextField
                        label={t('portalManager.form.passphrase')}
                        type="password"
                        value={passphrase}
                        onChange={(e) => setPassphrase(e.target.value)}
                        helperText={editing ? t('portalManager.form.passphraseKeep') : t('portalManager.form.passphraseHelp')}
                        fullWidth
                    />

                    <FormControlLabel
                        control={<Switch checked={requireEmail} onChange={(e) => setRequireEmail(e.target.checked)} />}
                        label={t('portalManager.form.requireEmail')}
                    />

                    <Divider />
                    <Typography variant="subtitle2">{t('portalManager.branding.title')}</Typography>
                    <Typography variant="caption" color="text.secondary">
                        {t('portalManager.branding.help')}
                    </Typography>

                    <Stack direction="row" spacing={2}>
                        <TextField
                            label={t('portalManager.branding.accent')}
                            value={branding.accent}
                            onChange={(e) => updateBranding('accent', e.target.value)}
                            placeholder="#2563eb"
                            fullWidth
                        />
                        <TextField
                            label={t('portalManager.branding.logoUrl')}
                            value={branding.logo_url}
                            onChange={(e) => updateBranding('logo_url', e.target.value)}
                            fullWidth
                        />
                    </Stack>

                    <TextField
                        label={t('portalManager.branding.headline')}
                        value={branding.headline}
                        onChange={(e) => updateBranding('headline', e.target.value)}
                        fullWidth
                    />

                    <TextField
                        label={t('portalManager.branding.message')}
                        value={branding.message}
                        onChange={(e) => updateBranding('message', e.target.value)}
                        multiline
                        minRows={2}
                        fullWidth
                    />

                    {editing && (
                        <>
                            <Divider />
                            <Typography variant="subtitle2">{t('portalManager.grants.title')}</Typography>
                            {loading ? (
                                <Box sx={{ display: 'flex', justifyContent: 'center', py: 3 }}>
                                    <CircularProgress size={24} />
                                </Box>
                            ) : (
                                <PortalGrantsPanel
                                    assets={assets}
                                    value={grants}
                                    onChange={setGrants}
                                    disabled={submitting}
                                />
                            )}
                        </>
                    )}

                    {!editing && (
                        <Alert severity="info">{t('portalManager.form.grantsAfterCreate')}</Alert>
                    )}
                </Stack>
            </DialogContent>
            <DialogActions>
                <Button onClick={onClose} disabled={submitting}>{t('portalManager.cancel')}</Button>
                <Button onClick={handleSubmit} variant="contained" disabled={submitting}>
                    {editing ? t('portalManager.save') : t('portalManager.form.createSubmit')}
                </Button>
            </DialogActions>
        </Dialog>
    );
}
