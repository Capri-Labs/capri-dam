import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Typography, Switch, Alert, Divider, CircularProgress,
    Chip, Tooltip, Button, LinearProgress, Paper, TextField,
    MenuItem, Select, FormControl, InputLabel, FormControlLabel,
    Collapse, Stack
} from '@mui/material';
import {
    DeleteForeverOutlined, SecurityOutlined, PlayArrowOutlined,
    HourglassEmptyOutlined, ErrorOutlined, CheckCircleOutlined,
    AccessTimeOutlined, SettingsOutlined, PersonOutlined,
    ScheduleOutlined, WarningAmberOutlined, AutoAwesomeOutlined,
    InfoOutlined, StorageOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';

const getCsrf = () => document.querySelector('[name="csrf-token"]')?.content ?? '';

// ── Status chip config ────────────────────────────────────────────────────────
const STATUS_META = {
    idle:      { color: '#64748b', bg: '#f1f5f9', icon: <HourglassEmptyOutlined sx={{ fontSize: 14 }} /> },
    queued:    { color: '#d97706', bg: '#fef3c7', icon: <ScheduleOutlined sx={{ fontSize: 14 }} /> },
    running:   { color: '#2563eb', bg: '#dbeafe', icon: <CircularProgress size={11} sx={{ color: '#2563eb' }} /> },
    completed: { color: '#15803d', bg: '#dcfce7', icon: <CheckCircleOutlined sx={{ fontSize: 14 }} /> },
    failed:    { color: '#dc2626', bg: '#fee2e2', icon: <ErrorOutlined sx={{ fontSize: 14 }} /> },
};

const formatBytes = (bytes) => {
    if (!bytes || bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const exp   = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    return `${(bytes / 1024 ** exp).toFixed(1)} ${units[exp]}`;
};

// ── Sub-component: Purge status card ─────────────────────────────────────────
function PurgeStatusCard({ statusData, onTrigger, triggering, t }) {
    const { status, last_ran_at, triggered_by, last_results } = statusData || {};
    const meta    = STATUS_META[status] || STATUS_META.idle;
    const isActive = status === 'running' || status === 'queued';

    return (
        <Paper elevation={0} sx={{
            p: 2.5, borderRadius: 2, border: '1px solid #e2e8f0',
            bgcolor: isActive ? '#f0f9ff' : '#fafafa', mb: 2,
        }}>
            {/* Title + status + trigger */}
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 1.5 }}>
                <DeleteForeverOutlined sx={{ color: '#ef4444', fontSize: 20 }} />
                <Box sx={{ flex: 1 }}>
                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b', lineHeight: 1.2 }}>
                        {t('bin.purge.title')}
                    </Typography>
                    <Typography variant="caption" sx={{ color: '#64748b' }}>
                        {t('bin.purge.subtitle')}
                    </Typography>
                </Box>

                <Chip
                    icon={meta.icon}
                    label={t(`bin.purge.status.${status || 'idle'}`)}
                    size="small"
                    sx={{
                        bgcolor: meta.bg, color: meta.color,
                        fontWeight: 600, fontSize: '0.68rem',
                        '& .MuiChip-icon': { color: meta.color },
                    }}
                />

                <Tooltip title={isActive ? t('bin.purge.running') : ''}>
                    <span>
                        <Button
                            size="small"
                            variant="outlined"
                            color="error"
                            startIcon={<PlayArrowOutlined />}
                            onClick={onTrigger}
                            disabled={isActive || triggering}
                            sx={{ textTransform: 'none', borderRadius: 2, fontSize: '0.78rem' }}
                        >
                            {t('bin.purge.triggerButton')}
                        </Button>
                    </span>
                </Tooltip>
            </Box>

            {/* Active progress bar */}
            {isActive && (
                <LinearProgress sx={{ borderRadius: 1, height: 5, mb: 1.5,
                    bgcolor: '#dbeafe', '& .MuiLinearProgress-bar': { bgcolor: '#3b82f6' } }} />
            )}

            {/* Who triggered */}
            {triggered_by?.user_name && (
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, mb: 1 }}>
                    <PersonOutlined sx={{ fontSize: 13, color: '#94a3b8' }} />
                    <Typography variant="caption" sx={{ color: '#64748b' }}>
                        {triggered_by.source === 'scheduled'
                            ? t('bin.purge.triggeredBySchedule')
                            : t('bin.purge.triggeredBy', { name: triggered_by.user_name })}
                        {triggered_by.triggered_at && (
                            <Box component="span" sx={{ color: '#94a3b8', ml: 0.5 }}>
                                — {new Date(triggered_by.triggered_at).toLocaleString()}
                            </Box>
                        )}
                    </Typography>
                </Box>
            )}

            {/* Last run results */}
            {last_results?.deleted !== undefined && (
                <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', mt: 1 }}>
                    <Chip size="small" color="success" variant="outlined"
                        label={t('bin.purge.results.deleted', { count: last_results.deleted })} />
                    {last_results.skipped > 0 && (
                        <Chip size="small" color="warning" variant="outlined"
                            label={t('bin.purge.results.skipped', { count: last_results.skipped })} />
                    )}
                    {last_results.failed > 0 && (
                        <Chip size="small" color="error" variant="outlined"
                            label={t('bin.purge.results.failed', { count: last_results.failed })} />
                    )}
                    {last_results.storage_reclaimed_bytes > 0 && (
                        <Chip size="small" variant="outlined"
                            icon={<StorageOutlined sx={{ fontSize: '12px !important' }} />}
                            label={formatBytes(last_results.storage_reclaimed_bytes) + ' reclaimed'}
                            sx={{ color: '#5e35b1', borderColor: '#5e35b1' }} />
                    )}
                </Box>
            )}

            {/* Skipped warning */}
            {last_results?.skipped > 0 && (
                <Alert severity="warning" sx={{ mt: 1.5, py: 0.5, borderRadius: 1.5, fontSize: '0.78rem' }}>
                    {t('bin.purge.skippedWarning', { count: last_results.skipped })}
                    {' '}{t('bin.purge.skippedDetail')}
                </Alert>
            )}

            {/* Last ran timestamp */}
            {last_ran_at && !isActive && (
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mt: 1 }}>
                    <AccessTimeOutlined sx={{ fontSize: 13, color: '#94a3b8' }} />
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        {t('bin.purge.lastRan')} {new Date(last_ran_at).toLocaleString()}
                    </Typography>
                </Box>
            )}
        </Paper>
    );
}

// ── Sub-component: AI gateway teaser ─────────────────────────────────────────
function AiGatewayTeaser({ t }) {
    return (
        <Paper elevation={0} sx={{
            p: 2.5, borderRadius: 2,
            border: '1px dashed #c4b5fd',
            bgcolor: '#faf5ff',
        }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 1 }}>
                <AutoAwesomeOutlined sx={{ color: '#7c3aed', fontSize: 20 }} />
                <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>
                    {t('bin.ai.title')}
                </Typography>
                <Chip label={t('bin.ai.comingSoon')} size="small"
                    sx={{ bgcolor: '#ede9fe', color: '#5b21b6', fontSize: '0.65rem', fontWeight: 700 }} />
            </Box>
            <Typography variant="caption" sx={{ color: '#64748b', display: 'block', mb: 1 }}>
                {t('bin.ai.description')}
            </Typography>
            <Stack spacing={0.75}>
                {[
                    t('bin.ai.feature1'),
                    t('bin.ai.feature2'),
                    t('bin.ai.feature3'),
                ].map((feat, i) => (
                    <Box key={i} sx={{ display: 'flex', alignItems: 'flex-start', gap: 0.75 }}>
                        <Box sx={{ width: 5, height: 5, borderRadius: '50%', bgcolor: '#7c3aed', mt: 0.7, flexShrink: 0 }} />
                        <Typography variant="caption" sx={{ color: '#475569' }}>{feat}</Typography>
                    </Box>
                ))}
            </Stack>
            <Typography variant="caption" sx={{ color: '#94a3b8', display: 'block', mt: 1 }}>
                Powered by{' '}
                <Box component="a" href="https://github.com/Capri-Labs/capri-dam-ai-gateway"
                    target="_blank" rel="noopener noreferrer"
                    sx={{ color: '#7c3aed', textDecoration: 'none', '&:hover': { textDecoration: 'underline' } }}>
                    Capri AI Gateway ↗
                </Box>
            </Typography>
        </Paper>
    );
}

// ── Main component ────────────────────────────────────────────────────────────
export default function BinPurgeSettings() {
    const { t }  = useTranslation();
    const notify = useNotify();

    const [loading,      setLoading]      = useState(true);
    const [saving,       setSaving]       = useState(false);
    const [triggering,   setTriggering]   = useState(false);
    const [statusData,   setStatusData]   = useState(null);
    const [policy,       setPolicy]       = useState(null);
    const [showEditor,   setShowEditor]   = useState(false);

    const pollRef = useRef(null);

    // ── Fetch purge status ────────────────────────────────────────────────────
    const fetchStatus = useCallback(async () => {
        try {
            const res  = await fetch('/api/v1/bin/purge_status');
            if (!res.ok) return;
            const data = await res.json();
            setStatusData(data);
            if (data.policy && !policy) setPolicy(data.policy);
        } catch (_) { /* non-critical */ }
    }, [policy]);

    // Load initial data
    useEffect(() => {
        const load = async () => {
            setLoading(true);
            await fetchStatus();
            setLoading(false);
        };
        load();
    }, []); // eslint-disable-line react-hooks/exhaustive-deps

    // Poll while purge is active
    useEffect(() => {
        const isActive = statusData?.status === 'running' || statusData?.status === 'queued';
        if (isActive && !pollRef.current) {
            pollRef.current = setInterval(fetchStatus, 3000);
        } else if (!isActive && pollRef.current) {
            clearInterval(pollRef.current);
            pollRef.current = null;
        }
        return () => { if (pollRef.current) { clearInterval(pollRef.current); pollRef.current = null; } };
    }, [statusData?.status, fetchStatus]);

    // ── Trigger purge ─────────────────────────────────────────────────────────
    const handleTrigger = async () => {
        if (triggering) return;
        setTriggering(true);
        try {
            const res  = await fetch('/api/v1/bin/trigger_purge', {
                method:  'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCsrf() },
            });
            const data = await res.json();
            if (!res.ok) {
                notify(data.error || t('common.error'), 'warning');
                return;
            }
            notify(t('bin.purge.queued'), 'success');
            await fetchStatus();
        } catch (_) {
            notify(t('common.error'), 'error');
        } finally {
            setTriggering(false);
        }
    };

    // ── Save policy ───────────────────────────────────────────────────────────
    const handleSavePolicy = async () => {
        if (!policy) return;
        setSaving(true);
        try {
            const res  = await fetch('/api/v1/bin/retention_policy', {
                method:  'PUT',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCsrf() },
                body:    JSON.stringify({
                    retention_days:    policy.retention_days,
                    workflow_behavior: policy.workflow_behavior,
                    batch_size:        policy.batch_size,
                    notify_admins:     policy.notify_admins,
                }),
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.error || 'Save failed');
            setPolicy(data);
            notify(t('bin.purge.policySaved'), 'success');
        } catch (err) {
            notify(err.message, 'error');
        } finally {
            setSaving(false);
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
        <Box sx={{ p: 3, maxWidth: 720 }}>
            {/* Header */}
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 0.5 }}>
                <DeleteForeverOutlined sx={{ color: '#ef4444', fontSize: 22 }} />
                <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b' }}>
                    {t('bin.settings.title')}
                </Typography>
                <Chip
                    icon={<SecurityOutlined sx={{ fontSize: '14px !important' }} />}
                    label={t('duplicateManager.settings.adminOnly')}
                    size="small"
                    sx={{ bgcolor: '#fef3c7', color: '#92400e', fontSize: '0.7rem', border: '1px solid #fde68a' }}
                />
            </Box>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                {t('bin.settings.subtitle')}
            </Typography>

            <Alert severity="warning" icon={<InfoOutlined />} sx={{ mb: 3, borderRadius: 2 }}>
                {t('bin.settings.warningNote')}
            </Alert>

            <Divider sx={{ mb: 3 }} />

            {/* Purge status card */}
            <PurgeStatusCard
                statusData={statusData}
                onTrigger={handleTrigger}
                triggering={triggering}
                t={t}
            />

            {/* Policy editor toggle */}
            <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #e2e8f0', mb: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: showEditor ? 2 : 0 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <SettingsOutlined sx={{ color: '#5e35b1', fontSize: 20 }} />
                        <Box>
                            <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>
                                {t('bin.purge.policyTitle')}
                            </Typography>
                            <Typography variant="caption" sx={{ color: '#64748b' }}>
                                {t('bin.settings.policySubtitle', {
                                    days: policy?.retention_days ?? 30,
                                    behavior: policy?.workflow_behavior ?? 'skip',
                                })}
                            </Typography>
                        </Box>
                    </Box>
                    <Button
                        size="small"
                        variant={showEditor ? 'contained' : 'outlined'}
                        onClick={() => setShowEditor(p => !p)}
                        sx={{ textTransform: 'none', minWidth: 90 }}
                        disableElevation
                    >
                        {showEditor ? t('common.close') : t('bin.purge.policyButton')}
                    </Button>
                </Box>

                <Collapse in={showEditor}>
                    {policy && (
                        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2.5 }}>
                            <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'flex-start' }}>
                                <TextField
                                    label={t('bin.purge.policy.retentionDays')}
                                    type="number"
                                    size="small"
                                    value={policy.retention_days}
                                    onChange={e => setPolicy(p => ({ ...p, retention_days: Math.max(1, Math.min(365, parseInt(e.target.value) || 1)) }))}
                                    helperText={t('bin.purge.policy.retentionDaysHelp')}
                                    sx={{ width: 180 }}
                                    slotProps={{ htmlInput: { min: 1, max: 365 } }}
                                />

                                <FormControl size="small" sx={{ minWidth: 240 }}>
                                    <InputLabel>{t('bin.purge.policy.workflowBehavior')}</InputLabel>
                                    <Select
                                        variant="outlined"
                                        value={policy.workflow_behavior}
                                        label={t('bin.purge.policy.workflowBehavior')}
                                        onChange={e => setPolicy(p => ({ ...p, workflow_behavior: e.target.value }))}
                                    >
                                        <MenuItem value="skip">{t('bin.purge.policy.behaviorSkip')}</MenuItem>
                                        <MenuItem value="force_terminate">{t('bin.purge.policy.behaviorForceTerminate')}</MenuItem>
                                    </Select>
                                </FormControl>

                                <TextField
                                    label={t('bin.purge.policy.batchSize')}
                                    type="number"
                                    size="small"
                                    value={policy.batch_size}
                                    onChange={e => setPolicy(p => ({ ...p, batch_size: Math.max(1, Math.min(500, parseInt(e.target.value) || 50)) }))}
                                    sx={{ width: 130 }}
                                    slotProps={{ htmlInput: { min: 1, max: 500 } }}
                                />
                            </Box>

                            <FormControlLabel
                                control={
                                    <Switch
                                        checked={policy.notify_admins}
                                        onChange={e => setPolicy(p => ({ ...p, notify_admins: e.target.checked }))}
                                        size="small"
                                        color="primary"
                                    />
                                }
                                label={
                                    <Typography variant="body2">{t('bin.purge.policy.notifyAdmins')}</Typography>
                                }
                            />

                            {policy.workflow_behavior === 'force_terminate' && (
                                <Alert severity="warning" icon={<WarningAmberOutlined />} sx={{ borderRadius: 1.5 }}>
                                    {t('bin.purge.policy.forceTerminateWarning')}
                                </Alert>
                            )}

                            {policy.next_scheduled_at && (
                                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75 }}>
                                    <ScheduleOutlined sx={{ fontSize: 14, color: '#94a3b8' }} />
                                    <Typography variant="caption" sx={{ color: '#64748b' }}>
                                        {t('bin.settings.nextScheduled')}:{' '}
                                        {new Date(policy.next_scheduled_at).toLocaleString()}
                                    </Typography>
                                </Box>
                            )}

                            <Box>
                                <Button
                                    variant="contained"
                                    size="small"
                                    onClick={handleSavePolicy}
                                    disabled={saving}
                                    disableElevation
                                    sx={{ textTransform: 'none', fontWeight: 600 }}
                                >
                                    {saving ? t('common.saving') : t('common.saveChanges')}
                                </Button>
                            </Box>
                        </Box>
                    )}
                </Collapse>
            </Paper>

            {/* AI Gateway teaser */}
            <AiGatewayTeaser t={t} />
        </Box>
    );
}

