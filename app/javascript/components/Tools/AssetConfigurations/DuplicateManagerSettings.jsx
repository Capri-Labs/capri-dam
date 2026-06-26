import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Typography, Switch, Alert, Divider,
    CircularProgress, Chip, Tooltip, Button,
    LinearProgress, Paper
} from '@mui/material';
import {
    ContentCopyOutlined, NotificationsOutlined, InfoOutlined,
    CheckCircleOutlined, CancelOutlined, SecurityOutlined,
    PlayArrowOutlined, HourglassEmptyOutlined, ErrorOutlined,
    SearchOutlined, AccessTimeOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';

// ─── Scan status chip colours ────────────────────────────────────────────────
const SCAN_STATUS_META = {
    idle:      { color: '#64748b', bg: '#f1f5f9', icon: <SearchOutlined sx={{ fontSize: 14 }} /> },
    queued:    { color: '#d97706', bg: '#fef3c7', icon: <HourglassEmptyOutlined sx={{ fontSize: 14 }} /> },
    running:   { color: '#2563eb', bg: '#dbeafe', icon: <CircularProgress size={11} sx={{ color: '#2563eb' }} /> },
    completed: { color: '#15803d', bg: '#dcfce7', icon: <CheckCircleOutlined sx={{ fontSize: 14 }} /> },
    failed:    { color: '#dc2626', bg: '#fee2e2', icon: <ErrorOutlined sx={{ fontSize: 14 }} /> },
};

// ─── Scan Status Card ────────────────────────────────────────────────────────
function ScanStatusCard({ scanStatus, scanProgress, lastScanAt, onTrigger, triggeringRef, t }) {
    const meta       = SCAN_STATUS_META[scanStatus] || SCAN_STATUS_META.idle;
    const isActive   = ['queued', 'running'].includes(scanStatus);
    const percent    = scanProgress?.total > 0
        ? Math.round((scanProgress.processed / scanProgress.total) * 100)
        : (isActive ? null : 0);

    const formattedLastScan = lastScanAt
        ? new Date(lastScanAt).toLocaleString()
        : null;

    return (
        <Paper elevation={0} sx={{
            p: 2.5, borderRadius: 2, border: '1px solid #e2e8f0',
            bgcolor: isActive ? '#f0f9ff' : '#fafafa',
        }}>
            {/* Row: title + status chip + trigger button */}
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 1.5 }}>
                <SearchOutlined sx={{ color: '#5e35b1', fontSize: 20 }} />
                <Box sx={{ flex: 1 }}>
                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b', lineHeight: 1.2 }}>
                        {t('duplicateManager.scan.title')}
                    </Typography>
                    <Typography variant="caption" sx={{ color: '#64748b' }}>
                        {t('duplicateManager.scan.subtitle')}
                    </Typography>
                </Box>

                {/* Status chip */}
                <Chip
                    icon={meta.icon}
                    label={t(`duplicateManager.scan.status.${scanStatus}`, scanStatus)}
                    size="small"
                    sx={{
                        bgcolor: meta.bg, color: meta.color,
                        fontWeight: 600, fontSize: '0.68rem',
                        '& .MuiChip-icon': { color: meta.color }
                    }}
                />

                {/* Trigger button */}
                <Tooltip title={isActive ? t('duplicateManager.scan.alreadyRunning') : ''}>
                    <span>
                        <Button
                            size="small"
                            variant="outlined"
                            startIcon={<PlayArrowOutlined />}
                            onClick={onTrigger}
                            disabled={isActive || triggeringRef.current}
                            sx={{
                                textTransform: 'none', borderRadius: 2, fontSize: '0.78rem',
                                borderColor: '#5e35b1', color: '#5e35b1',
                                '&:hover': { bgcolor: '#f5f3ff', borderColor: '#4527a0' },
                            }}
                        >
                            {t('duplicateManager.scan.triggerButton')}
                        </Button>
                    </span>
                </Tooltip>
            </Box>

            {/* Progress bar (when running) */}
            {isActive && (
                <Box sx={{ mb: 1 }}>
                    {percent !== null ? (
                        <>
                            <LinearProgress
                                variant="determinate"
                                value={percent}
                                sx={{ borderRadius: 1, height: 6, bgcolor: '#dbeafe',
                                      '& .MuiLinearProgress-bar': { bgcolor: '#2563eb' } }}
                            />
                            <Typography variant="caption" sx={{ color: '#2563eb', mt: 0.5, display: 'block' }}>
                                {scanProgress.processed} / {scanProgress.total}
                                {' '}({percent}%)
                            </Typography>
                        </>
                    ) : (
                        <LinearProgress
                            sx={{ borderRadius: 1, height: 6, bgcolor: '#dbeafe',
                                  '& .MuiLinearProgress-bar': { bgcolor: '#2563eb' } }}
                        />
                    )}
                </Box>
            )}

            {/* Error message */}
            {scanStatus === 'failed' && scanProgress?.error && (
                <Alert severity="error" sx={{ mt: 1, borderRadius: 1.5, py: 0.5 }}>
                    {scanProgress.error}
                </Alert>
            )}

            {/* Last scan time */}
            {formattedLastScan && (
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mt: 1 }}>
                    <AccessTimeOutlined sx={{ fontSize: 13, color: '#94a3b8' }} />
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        {t('duplicateManager.scan.lastScan')}: {formattedLastScan}
                    </Typography>
                </Box>
            )}

            {/* Help text */}
            <Typography variant="caption" sx={{ color: '#64748b', mt: 1, display: 'block' }}>
                {t('duplicateManager.scan.description')}
            </Typography>
        </Paper>
    );
}

// ─── Main component ──────────────────────────────────────────────────────────
export default function DuplicateManagerSettings() {
    const { t }  = useTranslation();
    const notify = useNotify();

    const [loading,            setLoading]            = useState(true);
    const [saving,             setSaving]             = useState(false);
    const [enabled,            setEnabled]            = useState(false);
    const [inboxNotifications, setInboxNotifications] = useState(true);
    const [maxDisplayGroups,   setMaxDisplayGroups]   = useState(100);
    const [scanStatus,         setScanStatus]         = useState('idle');
    const [scanProgress,       setScanProgress]       = useState({});
    const [lastScanAt,         setLastScanAt]         = useState(null);

    const triggeringRef = useRef(false);
    const pollRef       = useRef(null);

    // ── Helpers ───────────────────────────────────────────────────────────────
    const csrf = () => document.querySelector('[name="csrf-token"]')?.content;

    const applySettings = useCallback((data) => {
        setEnabled(!!data.enabled);
        setInboxNotifications(data.inbox_notifications !== false);
        setMaxDisplayGroups(data.max_display_groups || 100);
        if (data.scan_status)   setScanStatus(data.scan_status);
        if (data.scan_progress) setScanProgress(data.scan_progress || {});
        if (data.last_scan_at !== undefined) setLastScanAt(data.last_scan_at);
    }, []);

    // ── Polling ───────────────────────────────────────────────────────────────
    const fetchScanStatus = useCallback(async () => {
        try {
            const res  = await fetch('/api/v1/duplicate_manager_settings/scan_status');
            if (!res.ok) return;
            const data = await res.json();
            setScanStatus(data.scan_status || 'idle');
            setScanProgress(data.scan_progress || {});
            if (data.last_scan_at !== undefined) setLastScanAt(data.last_scan_at);
        } catch (_) { /* non-critical */ }
    }, []);

    // Poll every 3 s while scan is active
    useEffect(() => {
        const isActive = ['queued', 'running'].includes(scanStatus);
        if (isActive && !pollRef.current) {
            pollRef.current = setInterval(fetchScanStatus, 3000);
        } else if (!isActive && pollRef.current) {
            clearInterval(pollRef.current);
            pollRef.current = null;
        }
        return () => {
            if (pollRef.current) { clearInterval(pollRef.current); pollRef.current = null; }
        };
    }, [scanStatus, fetchScanStatus]);

    // ── Load ──────────────────────────────────────────────────────────────────
    const loadSettings = useCallback(async () => {
        setLoading(true);
        try {
            const res  = await fetch('/api/v1/duplicate_manager_settings');
            if (!res.ok) throw new Error('Load failed');
            applySettings(await res.json());
        } catch (_) {
            notify(t('duplicateManager.settings.loadError'), 'error');
        } finally {
            setLoading(false);
        }
    }, [applySettings, notify, t]);

    useEffect(() => { loadSettings(); }, [loadSettings]);

    // ── Toggle ────────────────────────────────────────────────────────────────
    const handleToggle = async (field, value) => {
        setSaving(true);
        try {
            const body = { [field]: value };
            const res  = await fetch('/api/v1/duplicate_manager_settings', {
                method:  'PATCH',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
                body:    JSON.stringify(body),
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.error || 'Save failed');
            applySettings(data);

            if (data.scan_queued) {
                notify(t('duplicateManager.scan.autoQueued'), 'info');
            } else {
                notify(t('duplicateManager.settings.saved'), 'success');
            }
        } catch (err) {
            notify(err.message, 'error');
        } finally {
            setSaving(false);
        }
    };

    // ── Trigger scan ──────────────────────────────────────────────────────────
    const handleTriggerScan = async () => {
        if (triggeringRef.current) return;
        triggeringRef.current = true;
        try {
            const res  = await fetch('/api/v1/duplicate_manager_settings/trigger_scan', {
                method:  'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.error || 'Failed to trigger scan');
            setScanStatus('queued');
            notify(t('duplicateManager.scan.queued'), 'info');
        } catch (err) {
            notify(err.message, 'error');
        } finally {
            triggeringRef.current = false;
        }
    };

    // ── Render ────────────────────────────────────────────────────────────────
    if (loading) {
        return (
            <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', py: 8 }}>
                <CircularProgress size={28} />
            </Box>
        );
    }

    return (
        <Box sx={{ p: 3, maxWidth: 700 }}>
            {/* Header */}
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 0.5 }}>
                <ContentCopyOutlined sx={{ color: '#5e35b1', fontSize: 22 }} />
                <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b' }}>
                    {t('duplicateManager.settings.title')}
                </Typography>
                <Chip
                    icon={<SecurityOutlined sx={{ fontSize: '14px !important' }} />}
                    label={t('duplicateManager.settings.adminOnly')}
                    size="small"
                    sx={{ bgcolor: '#fef3c7', color: '#92400e', fontSize: '0.7rem', border: '1px solid #fde68a' }}
                />
            </Box>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                {t('duplicateManager.settings.subtitle')}
            </Typography>

            {/* Performance warning */}
            <Alert severity="warning" icon={<InfoOutlined />} sx={{ mb: 3, borderRadius: 2 }}>
                {t('duplicateManager.settings.performanceWarning')}
                {' '}
                {t('duplicateManager.settings.maxReported', { count: maxDisplayGroups })}
            </Alert>

            <Divider sx={{ mb: 3 }} />

            {/* Enable / Disable toggle */}
            <Box sx={{
                p: 2.5, borderRadius: 2, border: '1px solid #e2e8f0', mb: 2,
                bgcolor: enabled ? '#f0fdf4' : '#f8fafc',
                transition: 'background 0.2s',
            }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <Box sx={{ flex: 1, mr: 2 }}>
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
                            {enabled
                                ? <CheckCircleOutlined sx={{ color: '#16a34a', fontSize: 18 }} />
                                : <CancelOutlined     sx={{ color: '#94a3b8', fontSize: 18 }} />
                            }
                            <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>
                                {t('duplicateManager.settings.enableLabel')}
                            </Typography>
                            <Chip
                                label={enabled
                                    ? t('duplicateManager.settings.status.enabled')
                                    : t('duplicateManager.settings.status.disabled')}
                                size="small"
                                sx={{
                                    bgcolor: enabled ? '#dcfce7' : '#f1f5f9',
                                    color:   enabled ? '#15803d' : '#64748b',
                                    fontWeight: 600, fontSize: '0.68rem',
                                }}
                            />
                        </Box>
                        <Typography variant="caption" sx={{ color: '#64748b' }}>
                            {t('duplicateManager.settings.enableHelp')}
                        </Typography>
                    </Box>
                    <Tooltip title={saving ? t('common.saving') : ''}>
                        <span>
                            <Switch
                                checked={enabled}
                                disabled={saving}
                                onChange={e => handleToggle('enabled', e.target.checked)}
                                color="success"
                            />
                        </span>
                    </Tooltip>
                </Box>
            </Box>

            {/* Inbox notifications toggle */}
            <Box sx={{
                p: 2.5, borderRadius: 2, border: '1px solid #e2e8f0', mb: 2,
                bgcolor: '#f8fafc',
                opacity: enabled ? 1 : 0.5,
                pointerEvents: enabled ? 'auto' : 'none',
            }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <Box sx={{ flex: 1, mr: 2 }}>
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
                            <NotificationsOutlined sx={{ color: '#5e35b1', fontSize: 18 }} />
                            <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>
                                {t('duplicateManager.settings.inboxNotificationsLabel')}
                            </Typography>
                        </Box>
                        <Typography variant="caption" sx={{ color: '#64748b' }}>
                            {t('duplicateManager.settings.inboxNotificationsHelp')}
                        </Typography>
                    </Box>
                    <Tooltip title={!enabled ? t('duplicateManager.settings.enableLabel') : (saving ? t('common.saving') : '')}>
                        <span>
                            <Switch
                                checked={inboxNotifications}
                                disabled={saving || !enabled}
                                onChange={e => handleToggle('inbox_notifications', e.target.checked)}
                                color="primary"
                            />
                        </span>
                    </Tooltip>
                </Box>
            </Box>

            {/* Repository scan card */}
            <Box sx={{
                opacity: enabled ? 1 : 0.5,
                pointerEvents: enabled ? 'auto' : 'none',
            }}>
                <ScanStatusCard
                    scanStatus={scanStatus}
                    scanProgress={scanProgress}
                    lastScanAt={lastScanAt}
                    onTrigger={handleTriggerScan}
                    triggeringRef={triggeringRef}
                    t={t}
                />
            </Box>
        </Box>
    );
}

