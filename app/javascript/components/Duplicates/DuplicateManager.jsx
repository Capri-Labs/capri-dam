import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, CssBaseline, Typography, Grid, Paper, Chip,
    Button, Skeleton
} from '@mui/material';
import {
    ContentCopy, RefreshOutlined, CheckCircleOutlined, HourglassEmptyOutlined,
    SettingsOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { navigateTo } from '../../utils/globalutils';
import DuplicateResolutionModal from './DuplicateResolutionModal';
import { useNotify } from '../../context/NotificationContext';

// ---------------------------------------------------------------------------
// Stat Card
// ---------------------------------------------------------------------------
function StatCard({ label, value, color, icon }) {
    return (
        <Paper elevation={0} sx={{
            p: 2, borderRadius: 2, border: '1px solid #e2e8f0',
            display: 'flex', alignItems: 'center', gap: 1.5
        }}>
            <Box sx={{ bgcolor: `${color}15`, p: 1, borderRadius: 1.5, display: 'flex' }}>
                {React.cloneElement(icon, { sx: { color, fontSize: 20 } })}
            </Box>
            <Box>
                <Typography variant="h6" fontWeight={700} sx={{ lineHeight: 1 }}>{value}</Typography>
                <Typography variant="caption" color="textSecondary">{label}</Typography>
            </Box>
        </Paper>
    );
}

// ---------------------------------------------------------------------------
// Group Card
// ---------------------------------------------------------------------------
function GroupCard({ group, onClick }) {
    const { t } = useTranslation();
    const assets = group.assets || [];

    // Generate preview from first 3 assets (use url or placeholder)
    const previews = assets.slice(0, 3);

    return (
        <Paper
            elevation={0}
            onClick={() => onClick(group)}
            sx={{
                p: 2.5, borderRadius: 3, border: '1px solid #e2e8f0',
                cursor: 'pointer', transition: '0.2s', height: '100%',
                '&:hover': { borderColor: '#3b82f6', boxShadow: '0 4px 12px rgba(0,0,0,0.07)' }
            }}
        >
            <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 1.5, mb: 2 }}>
                <Box sx={{ bgcolor: '#eff6ff', p: 1.5, borderRadius: 2, display: 'flex', flexShrink: 0 }}>
                    <ContentCopy sx={{ color: '#3b82f6', fontSize: 20 }} />
                </Box>
                <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography variant="subtitle2" fontWeight={600} noWrap>
                        {t('duplicateManager.group.potentialMatch')}
                    </Typography>
                    <Typography variant="body2" color="textSecondary">
                        {t('duplicateManager.group.identicalFiles', { count: group.total_count })}
                    </Typography>
                </Box>
                <Chip
                    label={t(`duplicateManager.status.${group.status}`, group.status)}
                    size="small"
                    sx={{
                        bgcolor: group.status === 'pending'  ? '#fef3c7' :
                                 group.status === 'resolved' ? '#dcfce7' : '#f1f5f9',
                        color:   group.status === 'pending'  ? '#92400e' :
                                 group.status === 'resolved' ? '#15803d' : '#64748b',
                        fontWeight: 600, fontSize: '0.68rem',
                    }}
                />
            </Box>

            {/* Preview thumbnails */}
            <Box sx={{ display: 'flex', gap: 1, mb: 1.5 }}>
                {previews.map((a, i) => (
                    <Box
                        key={a.asset_id || i}
                        sx={{
                            width: 48, height: 48, borderRadius: 1.5,
                            bgcolor: '#e2e8f0', flexShrink: 0, overflow: 'hidden',
                            border: a.is_original ? '2px solid #3b82f6' : '1px solid #e2e8f0',
                        }}
                    >
                        {a.url ? (
                            <Box component="img" src={a.url} alt={a.title}
                                 sx={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                        ) : (
                            <Box sx={{
                                width: '100%', height: '100%', display: 'flex',
                                alignItems: 'center', justifyContent: 'center',
                                bgcolor: '#f1f5f9',
                            }}>
                                <ContentCopy sx={{ fontSize: 16, color: '#94a3b8' }} />
                            </Box>
                        )}
                    </Box>
                ))}
            </Box>

            {/* SHA hint */}
            <Typography variant="caption" sx={{ color: '#94a3b8', fontFamily: 'monospace', fontSize: '0.65rem' }}>
                {t('duplicateManager.group.sha256')}: {group.checksum?.slice(0, 16)}…
            </Typography>
        </Paper>
    );
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------
export default function DuplicateManager() {
    const { t }  = useTranslation();
    const notify = useNotify();

    const [groups,         setGroups]         = useState([]);
    const [stats,          setStats]          = useState(null);
    const [loading,        setLoading]        = useState(true);
    const [filter,         setFilter]         = useState('pending');
    const [selectedGroup,  setSelectedGroup]  = useState(null);
    const [detailGroup,    setDetailGroup]    = useState(null); // full detail with assets
    const [loadingDetail,  setLoadingDetail]  = useState(false);

    // ── Data fetching ──────────────────────────────────────────────────────
    const fetchStats = useCallback(async () => {
        try {
            const res  = await fetch('/api/v1/duplicate_groups/stats');
            if (res.ok) setStats(await res.json());
        } catch (_) { /* non-critical */ }
    }, []);

    const fetchGroups = useCallback(async (status = 'pending') => {
        setLoading(true);
        try {
            const res  = await fetch(`/api/v1/duplicate_groups?status=${status}`);
            if (!res.ok) throw new Error('Failed to load');
            const data = await res.json();
            setGroups(data.groups || []);
        } catch (err) {
            notify(t('duplicateManager.resolution.loading'), 'error');
        } finally {
            setLoading(false);
        }
    }, [notify, t]);

    const fetchGroupDetail = useCallback(async (group) => {
        setLoadingDetail(true);
        setSelectedGroup(group);
        try {
            const res  = await fetch(`/api/v1/duplicate_groups/${group.id}`);
            if (!res.ok) throw new Error('Failed to load group detail');
            const data = await res.json();
            setDetailGroup(data.group);
        } catch (err) {
            notify(t('common.error'), 'error');
            setSelectedGroup(null);
        } finally {
            setLoadingDetail(false);
        }
    }, [notify, t]);

    useEffect(() => { fetchGroups(filter); fetchStats(); }, [filter, fetchGroups, fetchStats]);

    // ── Resolution handler ─────────────────────────────────────────────────
    const handleResolve = useCallback(async (groupId, action, assetIdsToDelete) => {
        try {
            const res = await fetch(`/api/v1/duplicate_groups/${groupId}/resolve`, {
                method:  'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content,
                },
                body: JSON.stringify({
                    action_type:         action === 'delete' ? 'deleted_duplicates' : 'kept_all',
                    asset_ids_to_delete: assetIdsToDelete,
                }),
            });

            if (!res.ok) throw new Error('Resolution failed');

            if (action === 'accept') {
                notify(t('duplicateManager.resolution.keptAllSuccess'), 'info');
            } else {
                notify(t('duplicateManager.resolution.deletedSuccess', { count: assetIdsToDelete.length }), 'success');
            }

            // Remove resolved group from list & refresh stats
            setGroups(prev => prev.filter(g => g.id !== groupId));
            setSelectedGroup(null);
            setDetailGroup(null);
            fetchStats();
        } catch (err) {
            notify(err.message, 'error');
        }
    }, [notify, t, fetchStats]);

    const handleDismiss = useCallback(async (groupId) => {
        try {
            await fetch(`/api/v1/duplicate_groups/${groupId}/dismiss`, {
                method:  'PATCH',
                headers: { 'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content },
            });
            setGroups(prev => prev.filter(g => g.id !== groupId));
            setSelectedGroup(null);
            setDetailGroup(null);
            fetchStats();
            notify(t('duplicateManager.resolution.resolvedSuccess'), 'info');
        } catch (_) {
            notify(t('common.error'), 'error');
        }
    }, [notify, t, fetchStats]);

    // ── Render ─────────────────────────────────────────────────────────────
    const FILTERS = [
        { id: 'pending',  labelKey: 'duplicateManager.filters.pending',  count: stats?.pending },
        { id: 'resolved', labelKey: 'duplicateManager.filters.resolved', count: stats?.resolved },
        { id: 'all',      labelKey: 'duplicateManager.filters.all',      count: stats?.total },
    ];

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />

            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                {/* ── Page header ─────────────────────────────────────────── */}
                <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', mb: 3 }}>
                    <Box>
                        <Typography variant="h4" sx={{ fontWeight: 700, color: '#1e293b' }}>
                            {t('duplicateManager.title')}
                        </Typography>
                        <Typography variant="body2" color="textSecondary">
                            {t('duplicateManager.subtitle')}
                        </Typography>
                    </Box>
                    <Box sx={{ display: 'flex', gap: 1 }}>
                        <Button
                            size="small"
                            variant="outlined"
                            startIcon={<SettingsOutlined />}
                            onClick={() => navigateTo('/tools/asset_configurations')}
                            sx={{ textTransform: 'none', borderRadius: 2, fontSize: '0.8rem' }}
                        >
                            {t('duplicateManager.settings.title')}
                        </Button>
                        <Button
                            size="small"
                            variant="outlined"
                            startIcon={<RefreshOutlined />}
                            onClick={() => fetchGroups(filter)}
                            sx={{ textTransform: 'none', borderRadius: 2, fontSize: '0.8rem' }}
                        >
                            {t('common.refresh', 'Refresh')}
                        </Button>
                    </Box>
                </Box>

                {/* ── Stats row ───────────────────────────────────────────── */}
                {stats && (
                    <Grid container spacing={2} sx={{ mb: 3 }}>
                        <Grid size={{ xs: 12, sm: 4 }}>
                            <StatCard
                                label={t('duplicateManager.stats.pendingGroups')}
                                value={stats.pending}
                                color="#f59e0b"
                                icon={<HourglassEmptyOutlined />}
                            />
                        </Grid>
                        <Grid size={{ xs: 12, sm: 4 }}>
                            <StatCard
                                label={t('duplicateManager.stats.resolvedGroups')}
                                value={stats.resolved}
                                color="#22c55e"
                                icon={<CheckCircleOutlined />}
                            />
                        </Grid>
                        <Grid size={{ xs: 12, sm: 4 }}>
                            <StatCard
                                label={t('duplicateManager.stats.totalGroups')}
                                value={stats.total}
                                color="#3b82f6"
                                icon={<ContentCopy />}
                            />
                        </Grid>
                    </Grid>
                )}

                {/* ── Filter tabs ──────────────────────────────────────────── */}
                <Box sx={{ display: 'flex', gap: 1, mb: 3 }}>
                    {FILTERS.map(f => (
                        <Button
                            key={f.id}
                            size="small"
                            variant={filter === f.id ? 'contained' : 'outlined'}
                            onClick={() => setFilter(f.id)}
                            sx={{
                                textTransform: 'none', borderRadius: 2, fontSize: '0.8rem',
                                ...(filter === f.id ? { bgcolor: '#1e293b', '&:hover': { bgcolor: '#0f172a' } } : {}),
                            }}
                        >
                            {t(f.labelKey, f.id)}
                            {f.count != null && (
                                <Chip label={f.count} size="small" sx={{ ml: 0.5, height: 18, fontSize: '0.65rem',
                                    bgcolor: filter === f.id ? 'rgba(255,255,255,0.2)' : '#f1f5f9',
                                    color: filter === f.id ? '#fff' : '#475569' }} />
                            )}
                        </Button>
                    ))}
                </Box>

                {/* ── Content ──────────────────────────────────────────────── */}
                {loading ? (
                    <Grid container spacing={3}>
                        {[1, 2, 3, 4].map(i => (
                            <Grid size={{ xs: 12, sm: 6, md: 4, lg: 3 }} key={i}>
                                <Skeleton variant="rectangular" height={160} sx={{ borderRadius: 3 }} />
                            </Grid>
                        ))}
                    </Grid>
                ) : groups.length === 0 ? (
                    <Box sx={{
                        textAlign: 'center', py: 10, px: 4, borderRadius: 3,
                        bgcolor: '#fff', border: '1px dashed #e2e8f0',
                    }}>
                        <ContentCopy sx={{ fontSize: 48, color: '#94a3b8', mb: 2 }} />
                        <Typography variant="h6" color="textSecondary" fontWeight={600}>
                            {t('duplicateManager.emptyState')}
                        </Typography>
                    </Box>
                ) : (
                    <Grid container spacing={3}>
                        {groups.map(group => (
                            <Grid size={{ xs: 12, sm: 6, md: 4, lg: 3 }} key={group.id}>
                                <GroupCard
                                    group={group}
                                    onClick={fetchGroupDetail}
                                />
                            </Grid>
                        ))}
                    </Grid>
                )}
            </Box>

            {/* ── Resolution modal ─────────────────────────────────────────── */}
            <DuplicateResolutionModal
                open={Boolean(selectedGroup)}
                duplicateGroup={detailGroup}
                loading={loadingDetail}
                onClose={() => { setSelectedGroup(null); setDetailGroup(null); }}
                onResolve={handleResolve}
                onDismiss={handleDismiss}
            />
        </Box>
    );
}

