import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, Typography, Slider, Select, MenuItem as SelectItem, FormControl,
    InputLabel, Switch, FormControlLabel, Button, CircularProgress, Alert,
    TextField, Paper, Divider, Chip
} from '@mui/material';
import {
    SaveOutlined, CollectionsBookmark, AutoAwesome, TimerOutlined,
    CloudOff, SecurityOutlined, SettingsSuggest
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';

const API_URL = '/api/v1/collection_settings';

const SECTION = ({ title, subtitle, icon, children }) => (
    <Paper elevation={0} sx={{ p: 3, mb: 3, borderRadius: 2, border: '1px solid #e2e8f0' }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 0.5 }}>
            {React.cloneElement(icon, { sx: { color: '#5e35b1', fontSize: 20 } })}
            <Typography variant="subtitle1" fontWeight={700} sx={{ color: '#1e293b' }}>{title}</Typography>
        </Box>
        <Typography variant="caption" sx={{ color: '#94a3b8', display: 'block', mb: 2 }}>{subtitle}</Typography>
        <Divider sx={{ mb: 2 }} />
        {children}
    </Paper>
);

export default function CollectionSettings() {
    const { t } = useTranslation();
    const notify = useNotify();

    const [settings, setSettings] = useState(null);
    const [loading, setLoading]   = useState(true);
    const [saving, setSaving]     = useState(false);
    const [dirty, setDirty]       = useState(false);

    const load = useCallback(async () => {
        setLoading(true);
        try {
            const res = await fetch(API_URL);
            if (res.ok) {
                const data = await res.json();
                setSettings(data);
            } else {
                notify(t('common.error', 'Failed to load settings'), 'error');
            }
        } catch {
            notify(t('common.error', 'Network error'), 'error');
        } finally {
            setLoading(false);
        }
    }, [notify, t]);

    useEffect(() => { load(); }, [load]);

    const set = (key, value) => {
        setSettings(prev => ({ ...prev, [key]: value }));
        setDirty(true);
    };

    const handleSave = async () => {
        setSaving(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch(API_URL, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken,
                },
                body: JSON.stringify({ settings }),
            });
            const data = await res.json();
            if (res.ok) {
                setSettings(data.settings);
                setDirty(false);
                notify(
                    t('tools.collectionSettings.savedSuccess', 'Collection settings saved successfully.'),
                    'success'
                );
            } else {
                notify(data.error || t('common.error', 'Failed to save'), 'error');
            }
        } catch {
            notify(t('common.error', 'Network error'), 'error');
        } finally {
            setSaving(false);
        }
    };

    if (loading) {
        return (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 8 }}>
                <CircularProgress sx={{ color: '#5e35b1' }} />
            </Box>
        );
    }

    if (!settings) return null;

    return (
        <Box sx={{ p: 3, maxWidth: 780 }}>
            {/* Header */}
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 3 }}>
                <Box>
                    <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b' }}>
                        {t('tools.collectionSettings.title', 'Collection & Workspace Settings')}
                    </Typography>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        {t('tools.collectionSettings.subtitle', 'Global defaults applied to all new collections and smart workspaces')}
                    </Typography>
                </Box>
                <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
                    {dirty && (
                        <Chip
                            label={t('common.unsavedChanges', 'Unsaved changes')}
                            size="small"
                            sx={{ bgcolor: '#fef3c7', color: '#92400e', fontSize: '0.7rem' }}
                        />
                    )}
                    <Button
                        variant="contained"
                        startIcon={saving ? <CircularProgress size={14} color="inherit" /> : <SaveOutlined />}
                        onClick={handleSave}
                        disabled={saving || !dirty}
                        sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none', borderRadius: 2 }}
                    >
                        {saving
                            ? t('common.saving', 'Saving…')
                            : t('common.saveChanges', 'Save Changes')
                        }
                    </Button>
                </Box>
            </Box>

            {/* ── Smart Rule Defaults ────────────────────────────────── */}
            <SECTION
                title={t('tools.collectionSettings.smartRules.title', 'Smart Rule Defaults')}
                subtitle={t('tools.collectionSettings.smartRules.subtitle', 'Applied when creating a new Smart (AI) Collection')}
                icon={<AutoAwesome />}
            >
                <Typography variant="body2" fontWeight={600} sx={{ mb: 1, color: '#475569' }}>
                    {t('tools.collectionSettings.smartRules.threshold', 'Default Cosine Similarity Threshold')}
                    {' — '}
                    <strong>{settings.default_similarity_threshold}</strong>
                </Typography>
                <Box sx={{ px: 1 }}>
                    <Slider
                        value={Number(settings.default_similarity_threshold)}
                        min={0.5} max={0.99} step={0.01}
                        valueLabelDisplay="auto"
                        onChange={(_, val) => set('default_similarity_threshold', val)}
                        sx={{ color: '#5e35b1' }}
                    />
                </Box>
                <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                    {t('tools.collectionSettings.smartRules.thresholdHint', 'Higher values = stricter semantic matching. 0.8 is recommended.')}
                </Typography>

                <Box sx={{ mt: 3 }}>
                    <FormControl size="small" sx={{ minWidth: 220 }}>
                        <InputLabel>
                            {t('tools.collectionSettings.smartRules.schedule', 'Re-evaluation Schedule')}
                        </InputLabel>
                        <Select
                            value={settings.smart_rule_schedule}
                            label={t('tools.collectionSettings.smartRules.schedule', 'Re-evaluation Schedule')}
                            onChange={e => set('smart_rule_schedule', e.target.value)}
                        >
                            <SelectItem value="hourly">{t('tools.collectionSettings.smartRules.scheduleHourly', 'Hourly')}</SelectItem>
                            <SelectItem value="daily">{t('tools.collectionSettings.smartRules.scheduleDaily', 'Daily')}</SelectItem>
                            <SelectItem value="weekly">{t('tools.collectionSettings.smartRules.scheduleWeekly', 'Weekly')}</SelectItem>
                            <SelectItem value="manual">{t('tools.collectionSettings.smartRules.scheduleManual', 'Manual Only')}</SelectItem>
                        </Select>
                    </FormControl>
                    <Typography variant="caption" sx={{ color: '#94a3b8', display: 'block', mt: 0.5 }}>
                        {t('tools.collectionSettings.smartRules.scheduleHint', 'How often the AI engine re-scans assets against active smart rules.')}
                    </Typography>
                </Box>
            </SECTION>

            {/* ── Access Control Defaults ────────────────────────────── */}
            <SECTION
                title={t('tools.collectionSettings.access.title', 'Access Control Defaults')}
                subtitle={t('tools.collectionSettings.access.subtitle', 'Default visibility for newly created collections')}
                icon={<SecurityOutlined />}
            >
                <FormControl size="small" sx={{ minWidth: 200 }}>
                    <InputLabel>
                        {t('tools.collectionSettings.access.visibility', 'Default Visibility')}
                    </InputLabel>
                    <Select
                        value={settings.default_visibility}
                        label={t('tools.collectionSettings.access.visibility', 'Default Visibility')}
                        onChange={e => set('default_visibility', e.target.value)}
                    >
                        <SelectItem value="public">{t('tools.collectionSettings.access.public', 'Public — accessible to all authenticated users')}</SelectItem>
                        <SelectItem value="private">{t('tools.collectionSettings.access.private', 'Private — restricted to whitelisted groups only')}</SelectItem>
                    </Select>
                </FormControl>
                <Typography variant="caption" sx={{ color: '#94a3b8', display: 'block', mt: 1 }}>
                    {t('tools.collectionSettings.access.hint', 'Individual collections can override this default in their properties.')}
                </Typography>
            </SECTION>

            {/* ── Asset Limits ───────────────────────────────────────── */}
            <SECTION
                title={t('tools.collectionSettings.limits.title', 'Asset Limits')}
                subtitle={t('tools.collectionSettings.limits.subtitle', 'Prevent oversized collections from degrading performance')}
                icon={<CollectionsBookmark />}
            >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    <TextField
                        size="small"
                        type="number"
                        label={t('tools.collectionSettings.limits.maxAssets', 'Max Assets per Collection')}
                        value={settings.max_assets_per_collection}
                        onChange={e => set('max_assets_per_collection', parseInt(e.target.value, 10) || 0)}
                        inputProps={{ min: 0, max: 10000 }}
                        sx={{ width: 220 }}
                    />
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        {t('tools.collectionSettings.limits.maxAssetsHint', '0 = unlimited. Recommended: 500.')}
                    </Typography>
                </Box>
            </SECTION>

            {/* ── TTL & Expiration ───────────────────────────────────── */}
            <SECTION
                title={t('tools.collectionSettings.ttl.title', 'TTL & Auto-Expiration')}
                subtitle={t('tools.collectionSettings.ttl.subtitle', 'Automatically archive collections after N days')}
                icon={<TimerOutlined />}
            >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    <TextField
                        size="small"
                        type="number"
                        label={t('tools.collectionSettings.ttl.defaultDays', 'Default TTL (days)')}
                        value={settings.ttl_default_days}
                        onChange={e => set('ttl_default_days', parseInt(e.target.value, 10) || 0)}
                        inputProps={{ min: 0 }}
                        sx={{ width: 200 }}
                    />
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        {t('tools.collectionSettings.ttl.hint', '0 = no default expiration. Applied at collection creation time.')}
                    </Typography>
                </Box>
            </SECTION>

            {/* ── CDN & Compliance ──────────────────────────────────── */}
            <SECTION
                title={t('tools.collectionSettings.cdn.title', 'CDN & Compliance')}
                subtitle={t('tools.collectionSettings.cdn.subtitle', 'Edge cache and automated governance settings')}
                icon={<CloudOff />}
            >
                <FormControlLabel
                    control={
                        <Switch
                            checked={Boolean(settings.auto_cdn_purge)}
                            onChange={e => set('auto_cdn_purge', e.target.checked)}
                            sx={{ '& .MuiSwitch-switchBase.Mui-checked': { color: '#5e35b1' }, '& .MuiSwitch-switchBase.Mui-checked + .MuiSwitch-track': { bgcolor: '#5e35b1' } }}
                        />
                    }
                    label={
                        <Box>
                            <Typography variant="body2" fontWeight={600}>
                                {t('tools.collectionSettings.cdn.autoPurge', 'Auto-purge CDN on collection modification')}
                            </Typography>
                            <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                {t('tools.collectionSettings.cdn.autoPurgeHint', 'Invalidates edge cache whenever assets are added, removed, or the collection is updated.')}
                            </Typography>
                        </Box>
                    }
                    sx={{ alignItems: 'flex-start', mt: 0 }}
                />

                <Box sx={{ mt: 2 }}>
                    <FormControlLabel
                        control={
                            <Switch
                                checked={Boolean(settings.enable_compliance_scan)}
                                onChange={e => set('enable_compliance_scan', e.target.checked)}
                                sx={{ '& .MuiSwitch-switchBase.Mui-checked': { color: '#5e35b1' }, '& .MuiSwitch-switchBase.Mui-checked + .MuiSwitch-track': { bgcolor: '#5e35b1' } }}
                            />
                        }
                        label={
                            <Box>
                                <Typography variant="body2" fontWeight={600}>
                                    {t('tools.collectionSettings.cdn.complianceScan', 'Enable automated TDM compliance scan')}
                                </Typography>
                                <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                    {t('tools.collectionSettings.cdn.complianceScanHint', 'Runs a usage-rights and metadata completeness check on every collection after modification.')}
                                </Typography>
                            </Box>
                        }
                        sx={{ alignItems: 'flex-start' }}
                    />
                </Box>
            </SECTION>

            {/* Info notice */}
            <Alert severity="info" sx={{ borderRadius: 2, fontSize: '0.8rem' }}>
                {t('tools.collectionSettings.adminNote', 'These settings require Admin privileges. Changes apply globally and take effect immediately for all new collections.')}
            </Alert>
        </Box>
    );
}

