import React, { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import {
    Box, Grid, Card, CardContent, Typography, LinearProgress,
    Button, Chip, Table, TableBody, TableCell, TableContainer,
    TableHead, TableRow, Paper, Stack, IconButton, Tooltip,
    CircularProgress, Alert, TextField, MenuItem, Badge,
    Collapse, Divider, InputAdornment
} from '@mui/material';
import {
    Storage, TrendingDown, Visibility, Refresh,
    CheckCircle, PauseCircle, AutoAwesome,
    RocketLaunch, Search, FilterList, DeleteForever,
    LinkOutlined, BarChart, ViewTimeline, LayersClear
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';
import BatchReviewWorkspace from './BatchReviewWorkspace';
import BatchPipelineTimeline from './BatchPipelineTimeline';
import NewMigrationDialog from './NewMigrationDialog';

// ── Status configuration ────────────────────────────────────────────────────
const STATUS_CONFIG = {
    initializing:  { label: 'Initializing',      color: 'default',   dot: '#64748b' },
    extracting:    { label: 'Extracting Files',   color: 'info',      dot: '#0ea5e9' },
    transforming:  { label: 'AI Transforming',    color: 'secondary', dot: '#8b5cf6' },
    review_needed: { label: 'Needs Review',       color: 'warning',   dot: '#f59e0b' },
    committed:     { label: 'Committed',          color: 'success',   dot: '#16a34a' },
    failed:        { label: 'Failed',             color: 'error',     dot: '#dc2626' },
};

const IN_PROGRESS_STATUSES = [ 'initializing', 'extracting', 'transforming' ];
const ALL_STATUSES         = Object.keys(STATUS_CONFIG);

// ── Stat metric card ────────────────────────────────────────────────────────
function MetricCard({ label, value, sub, icon, color, loading }) {
    return (
        <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%' }}>
            <CardContent>
                <Stack direction="row" justifyContent="space-between" alignItems="flex-start">
                    <Box>
                        <Typography color="textSecondary" variant="caption" sx={{ fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.06em' }}>
                            {label}
                        </Typography>
                        {loading ? (
                            <Box sx={{ mt: 1.5 }}><CircularProgress size={22} sx={{ color }} /></Box>
                        ) : (
                            <Typography variant="h4" sx={{ fontWeight: 700, mt: 0.5, color }}>
                                {value}
                            </Typography>
                        )}
                    </Box>
                    <Box sx={{ p: 1, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0', display: 'flex' }}>
                        {icon}
                    </Box>
                </Stack>
                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1 }}>{sub}</Typography>
            </CardContent>
        </Card>
    );
}

// ── Active batch card ───────────────────────────────────────────────────────
function ActiveBatchCard({ batch, onAudit, onAbort }) {
    const progress = batch.total_count > 0
        ? (batch.processed_count / batch.total_count) * 100
        : 0;
    const cfg = STATUS_CONFIG[batch.status] || STATUS_CONFIG.initializing;
    const isReview = batch.status === 'review_needed';

    return (
        <Paper elevation={0} sx={{ border: `1px solid ${isReview ? '#fde68a' : '#e3e8ef'}`, borderRadius: 3, p: 2.5, bgcolor: isReview ? '#fffbeb' : 'white' }}>
            <Stack direction="row" justifyContent="space-between" alignItems="flex-start" sx={{ mb: 1.5 }}>
                <Box>
                    <Stack direction="row" spacing={1} alignItems="center">
                        <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>{batch.name}</Typography>
                        <Chip label={cfg.label} color={cfg.color} size="small" variant="outlined"
                            sx={{ height: 20, fontSize: '0.65rem', fontWeight: 700 }} />
                    </Stack>
                    <Typography variant="caption" color="textSecondary">
                        {batch.source_label || batch.source_type?.toUpperCase()}
                        {batch.connector_name && ` · ${batch.connector_name}`}
                        {batch.started_at && ` · Started ${new Date(batch.started_at).toLocaleString()}`}
                    </Typography>
                </Box>
                <Stack direction="row" spacing={0.5}>
                    {isReview && (
                        <Button variant="contained" size="small" startIcon={<Visibility />}
                            onClick={() => onAudit(batch.id)}
                            sx={{ textTransform: 'none', bgcolor: '#f59e0b', '&:hover': { bgcolor: '#d97706' }, boxShadow: 'none' }}>
                            Audit Batch
                        </Button>
                    )}
                    <Tooltip title="Abort migration">
                        <IconButton size="small" color="error" onClick={() => onAbort(batch.id)}>
                            <PauseCircle fontSize="small" />
                        </IconButton>
                    </Tooltip>
                </Stack>
            </Stack>

            {/* Pipeline stepper */}
            <BatchPipelineTimeline status={batch.status} />

            {/* Progress bar */}
            {batch.total_count > 0 && (
                <Box sx={{ mt: 1.5 }}>
                    <Stack direction="row" justifyContent="space-between" sx={{ mb: 0.5 }}>
                        <Typography variant="caption" color="textSecondary">
                            {batch.processed_count}/{batch.total_count} processed
                        </Typography>
                        <Stack direction="row" spacing={1}>
                            {batch.duplicate_count > 0 && (
                                <Chip label={`${batch.duplicate_count} dupes blocked`} size="small" color="warning" variant="outlined" sx={{ height: 18, fontSize: '0.6rem' }} />
                            )}
                            {batch.error_count > 0 && (
                                <Chip label={`${batch.error_count} errors`} size="small" color="error" variant="outlined" sx={{ height: 18, fontSize: '0.6rem' }} />
                            )}
                        </Stack>
                    </Stack>
                    <LinearProgress
                        variant={IN_PROGRESS_STATUSES.includes(batch.status) ? 'indeterminate' : 'determinate'}
                        value={progress}
                        color={batch.status === 'transforming' ? 'secondary' : 'primary'}
                        sx={{ height: 5, borderRadius: 2 }}
                    />
                </Box>
            )}
        </Paper>
    );
}

// ── Main Dashboard ──────────────────────────────────────────────────────────
export default function IngestionDashboard() {
    const { t }  = useTranslation();
    const notify = useNotify();

    const [batches, setBatches]               = useState([]);
    const [batchMeta, setBatchMeta]           = useState({});
    const [stats, setStats]                   = useState(null);
    const [loading, setLoading]               = useState(true);
    const [statsLoading, setStatsLoading]     = useState(true);
    const [selectedBatchId, setSelectedBatchId] = useState(null);
    const [wizardOpen, setWizardOpen]         = useState(false);

    // Filters
    const [statusFilter, setStatusFilter]     = useState('');
    const [searchQuery, setSearchQuery]       = useState('');
    const [page, setPage]                     = useState(1);

    const pollRef   = useRef(null);
    const searchRef = useRef(null);

    // ── Data fetching ──────────────────────────────────────────────────────
    const fetchStats = useCallback(async () => {
        try {
            const res  = await fetch('/api/v1/ingestion_batches/stats');
            if (!res.ok) return;
            const data = await res.json();
            setStats(data);
        } catch { /* non-fatal */ }
        finally { setStatsLoading(false); }
    }, []);

    const fetchBatches = useCallback(async () => {
        const params = new URLSearchParams({ page });
        if (statusFilter) params.append('status', statusFilter);
        if (searchQuery)  params.append('search', searchQuery);
        try {
            const res  = await fetch(`/api/v1/ingestion_batches?${params}`);
            const data = await res.json();
            if (!res.ok) {
                notify(`${t('ingestion.fetchError')}: ${data.error || res.status}`, 'error');
            } else {
                setBatches(data.batches || []);
                setBatchMeta(data.meta   || {});
            }
        } catch (e) {
            notify(`${t('ingestion.fetchError')}: ${e.message}`, 'error');
        } finally {
            setLoading(false);
        }
    }, [page, statusFilter, searchQuery, notify, t]);

    const refreshAll = useCallback(() => {
        fetchBatches();
        fetchStats();
    }, [fetchBatches, fetchStats]);

    useEffect(() => { fetchBatches(); }, [fetchBatches]);
    useEffect(() => { fetchStats(); },  [fetchStats]);

    // Auto-poll when any batch is in-progress
    useEffect(() => {
        const hasActive = batches.some(b => IN_PROGRESS_STATUSES.includes(b.status));
        clearInterval(pollRef.current);
        if (hasActive) {
            pollRef.current = setInterval(refreshAll, 6000);
        }
        return () => clearInterval(pollRef.current);
    }, [batches, refreshAll]);

    // Debounced search
    useEffect(() => {
        clearTimeout(searchRef.current);
        searchRef.current = setTimeout(() => {
            setPage(1);
            fetchBatches();
        }, 350);
        return () => clearTimeout(searchRef.current);
    }, [searchQuery]); // eslint-disable-line react-hooks/exhaustive-deps

    // ── Actions ───────────────────────────────────────────────────────────
    const handleAbort = async (batchId) => {
        if (!window.confirm(t('ingestion.batch.abortConfirm'))) return;
        try {
            const csrf = document.querySelector('[name="csrf-token"]').content;
            const res  = await fetch(`/api/v1/ingestion_batches/${batchId}/abort`, {
                method:  'POST',
                headers: { 'X-CSRF-Token': csrf, 'Content-Type': 'application/json' },
            });
            if (res.ok) { notify(t('ingestion.batch.abortSuccess'), 'info'); refreshAll(); }
        } catch { notify(t('ingestion.batch.abortFail'), 'error'); }
    };

    const handleDelete = async (batchId) => {
        if (!window.confirm(t('ingestion.batch.deleteConfirm'))) return;
        try {
            const csrf = document.querySelector('[name="csrf-token"]').content;
            const res  = await fetch(`/api/v1/ingestion_batches/${batchId}`, {
                method:  'DELETE',
                headers: { 'X-CSRF-Token': csrf },
            });
            if (res.ok) { notify(t('ingestion.batch.deleteSuccess'), 'success'); refreshAll(); }
        } catch { notify(t('ingestion.batch.deleteFail'), 'error'); }
    };

    // ── Derived data ──────────────────────────────────────────────────────
    const activeBatches = useMemo(() => batches.filter(b => [ ...IN_PROGRESS_STATUSES, 'review_needed' ].includes(b.status)), [batches]);

    // ── Drill-down to batch review workspace ───────────────────────────────
    if (selectedBatchId) {
        return (
            <BatchReviewWorkspace
                batchId={selectedBatchId}
                onBack={() => { setSelectedBatchId(null); refreshAll(); }}
            />
        );
    }

    const totalPages = batchMeta.total ? Math.ceil(batchMeta.total / (batchMeta.per_page || 50)) : 1;

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>

            {/* ── Page header ── */}
            <Stack direction="row" justifyContent="space-between" alignItems="flex-start" sx={{ mb: 4 }} flexWrap="wrap" gap={2}>
                <Box>
                    {/* Breadcrumb */}
                    <Stack direction="row" spacing={0.5} alignItems="center" sx={{ mb: 0.5 }}>
                        <Typography variant="caption" color="textSecondary">Data &amp; Migrations</Typography>
                        <Typography variant="caption" color="textSecondary">›</Typography>
                        <Typography
                            component="a"
                            href="/admin/migrations/connectors"
                            variant="caption"
                            sx={{ color: '#0ea5e9', textDecoration: 'none', '&:hover': { textDecoration: 'underline' } }}
                        >
                            Legacy Connectors
                        </Typography>
                        <Typography variant="caption" color="textSecondary">›</Typography>
                        <Typography variant="caption" color="textSecondary">Migration Pipeline</Typography>
                    </Stack>

                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', display: 'flex', alignItems: 'center', gap: 1 }}>
                        <ViewTimeline sx={{ color: '#5e35b1', fontSize: 32 }} />
                        {t('ingestion.title')}
                    </Typography>
                    <Typography variant="body2" color="textSecondary">{t('ingestion.subtitle')}</Typography>
                </Box>

                <Stack direction="row" spacing={1.5} alignItems="center" flexWrap="wrap">
                    <Button
                        variant="outlined"
                        startIcon={<LinkOutlined />}
                        href="/admin/migrations/connectors"
                        sx={{ textTransform: 'none', borderRadius: '8px', color: '#475569', borderColor: '#cbd5e1', bgcolor: 'white' }}
                    >
                        {t('ingestion.manageConnectors')}
                    </Button>
                    <Button
                        variant="outlined"
                        startIcon={<Refresh />}
                        onClick={refreshAll}
                        sx={{ textTransform: 'none', borderRadius: '8px', color: '#475569', borderColor: '#cbd5e1', bgcolor: 'white' }}
                    >
                        {t('common.refresh')}
                    </Button>
                    <Button
                        variant="contained"
                        startIcon={<RocketLaunch />}
                        onClick={() => setWizardOpen(true)}
                        sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                    >
                        {t('ingestion.startMigration')}
                    </Button>
                </Stack>
            </Stack>

            {/* ── Metrics row ── */}
            <Grid container spacing={3} sx={{ mb: 4 }}>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('ingestion.stats.totalBatches')}
                        value={stats?.total_batches ?? '—'}
                        sub={`${stats?.active_batches ?? 0} active · ${stats?.failed_batches ?? 0} failed`}
                        icon={<BarChart sx={{ color: '#64748b', fontSize: 28 }} />}
                        color="#121926"
                        loading={statsLoading}
                    />
                </Grid>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('ingestion.stats.completed')}
                        value={stats?.completed_batches ?? '—'}
                        sub="Fully committed to DAM"
                        icon={<CheckCircle sx={{ color: '#16a34a', fontSize: 28 }} />}
                        color="#16a34a"
                        loading={statsLoading}
                    />
                </Grid>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('ingestion.stats.assetsCommitted')}
                        value={(stats?.total_assets_committed ?? 0).toLocaleString()}
                        sub={`${(stats?.total_assets_staged ?? 0).toLocaleString()} staged total`}
                        icon={<Storage sx={{ color: '#0ea5e9', fontSize: 28 }} />}
                        color="#0ea5e9"
                        loading={statsLoading}
                    />
                </Grid>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('ingestion.stats.duplicatesBlocked')}
                        value={(stats?.total_duplicates_blocked ?? 0).toLocaleString()}
                        sub="Prevented at ingestion edge"
                        icon={<LayersClear sx={{ color: '#f59e0b', fontSize: 28 }} />}
                        color="#f59e0b"
                        loading={statsLoading}
                    />
                </Grid>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('ingestion.stats.storageSaved')}
                        value={`${stats?.estimated_storage_saved_gb ?? '0.00'} GB`}
                        sub="Estimated storage debt prevented"
                        icon={<TrendingDown sx={{ color: '#8b5cf6', fontSize: 28 }} />}
                        color="#8b5cf6"
                        loading={statsLoading}
                    />
                </Grid>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('ingestion.stats.costSavings')}
                        value={`$${stats?.estimated_cost_savings_usd ?? '0.00'}/mo`}
                        sub="Cloud storage & egress savings"
                        icon={<AutoAwesome sx={{ color: '#16a34a', fontSize: 28 }} />}
                        color="#16a34a"
                        loading={statsLoading}
                    />
                </Grid>
            </Grid>

            {/* ── Pipeline phases info banner ── */}
            <Alert severity="info" sx={{ mb: 4, borderRadius: 2 }}>
                <strong>{t('ingestion.phaseBanner.title')}</strong> &nbsp;
                <strong>1. Audit &amp; Cleanse</strong> — purge ROT assets before migrating. &nbsp;
                <strong>2. Metadata Normalization</strong> — AI maps legacy tags to canonical schema. &nbsp;
                <strong>3. Human Review</strong> — approve or reject staged batches. &nbsp;
                <strong>4. Commit</strong> — assets committed, single summary email sent.
            </Alert>

            {/* ── Active / in-progress batches ── */}
            <Collapse in={activeBatches.length > 0}>
                <Box sx={{ mb: 4 }}>
                    <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
                        <Typography variant="h6" sx={{ fontWeight: 700 }}>
                            {t('ingestion.activeBatches')}
                        </Typography>
                        <Badge badgeContent={activeBatches.length} color="warning" />
                    </Stack>
                    <Stack spacing={2}>
                        {activeBatches.map(batch => (
                            <ActiveBatchCard
                                key={batch.id}
                                batch={batch}
                                onAudit={id => setSelectedBatchId(id)}
                                onAbort={handleAbort}
                            />
                        ))}
                    </Stack>
                    <Divider sx={{ mt: 4 }} />
                </Box>
            </Collapse>

            {/* ── Batch history table ── */}
            <Box>
                <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 2 }} flexWrap="wrap" gap={1}>
                    <Typography variant="h6" sx={{ fontWeight: 700 }}>
                        {t('ingestion.allBatches')}
                        {batchMeta.total > 0 && (
                            <Typography component="span" variant="body2" color="textSecondary" sx={{ ml: 1 }}>
                                ({batchMeta.total} total)
                            </Typography>
                        )}
                    </Typography>
                    <Stack direction="row" spacing={1} flexWrap="wrap">
                        <TextField
                            size="small"
                            placeholder={t('common.search')}
                            value={searchQuery}
                            onChange={e => setSearchQuery(e.target.value)}
                            slotProps={{ input: { startAdornment: <InputAdornment position="start"><Search fontSize="small" /></InputAdornment> } }}
                            sx={{ width: 200 }}
                        />
                        <TextField
                            select size="small" label="Status" value={statusFilter}
                            onChange={e => { setStatusFilter(e.target.value); setPage(1); }}
                            sx={{ width: 165 }}
                            slotProps={{ input: { startAdornment: <FilterList fontSize="small" sx={{ mr: 0.5, color: '#94a3b8' }} /> } }}
                        >
                            <MenuItem value="">All Statuses</MenuItem>
                            {ALL_STATUSES.map(s => (
                                <MenuItem key={s} value={s}>{STATUS_CONFIG[s].label}</MenuItem>
                            ))}
                        </TextField>
                    </Stack>
                </Stack>

                {loading ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 8 }}>
                        <CircularProgress />
                    </Box>
                ) : batches.length === 0 ? (
                    <Paper elevation={0} sx={{ p: 8, textAlign: 'center', border: '1px dashed #cbd5e1', borderRadius: 3 }}>
                        <RocketLaunch sx={{ fontSize: 48, color: '#cbd5e1', mb: 2, display: 'block', mx: 'auto' }} />
                        <Typography variant="h6" color="textSecondary" sx={{ mb: 1 }}>{t('ingestion.noBatches')}</Typography>
                        <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                            {t('ingestion.noBatchesSub')}
                        </Typography>
                        <Stack direction="row" spacing={1.5} justifyContent="center">
                            <Button variant="outlined" href="/admin/migrations/connectors" sx={{ textTransform: 'none' }}>
                                {t('ingestion.goToConnectors')}
                            </Button>
                            <Button variant="contained" startIcon={<RocketLaunch />} onClick={() => setWizardOpen(true)}
                                sx={{ textTransform: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, boxShadow: 'none' }}>
                                {t('ingestion.startMigration')}
                            </Button>
                        </Stack>
                    </Paper>
                ) : (
                    <>
                        <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3 }}>
                            <Table>
                                <TableHead sx={{ bgcolor: '#f8fafc' }}>
                                    <TableRow>
                                        <TableCell sx={{ fontWeight: 600 }}>{t('ingestion.batch.name')}</TableCell>
                                        <TableCell sx={{ fontWeight: 600 }}>{t('ingestion.batch.source')}</TableCell>
                                        <TableCell sx={{ fontWeight: 600 }}>{t('ingestion.batch.status')}</TableCell>
                                        <TableCell sx={{ fontWeight: 600, width: '18%' }}>{t('ingestion.batch.progress')}</TableCell>
                                        <TableCell sx={{ fontWeight: 600 }}>{t('ingestion.batch.duplicates')}</TableCell>
                                        <TableCell sx={{ fontWeight: 600 }}>{t('ingestion.batch.errors')}</TableCell>
                                        <TableCell align="right" sx={{ fontWeight: 600 }}>{t('common.actions')}</TableCell>
                                    </TableRow>
                                </TableHead>
                                <TableBody>
                                    {batches.map(batch => {
                                        const progress  = batch.total_count > 0
                                            ? (batch.processed_count / batch.total_count) * 100
                                            : 0;
                                        const isActive  = IN_PROGRESS_STATUSES.includes(batch.status);
                                        const cfg       = STATUS_CONFIG[batch.status] || STATUS_CONFIG.initializing;

                                        return (
                                            <TableRow key={batch.id} hover>
                                                <TableCell>
                                                    <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>{batch.name}</Typography>
                                                    <Typography variant="caption" color="textSecondary">
                                                        {batch.created_at?.slice(0, 10)}
                                                        {batch.connector_name && ` · ${batch.connector_name}`}
                                                    </Typography>
                                                </TableCell>
                                                <TableCell>
                                                    <Chip label={batch.source_label || batch.source_type?.toUpperCase()} size="small" variant="outlined" />
                                                </TableCell>
                                                <TableCell>
                                                    <Chip
                                                        label={cfg.label}
                                                        color={cfg.color}
                                                        size="small"
                                                        variant="outlined"
                                                        icon={isActive ? <CircularProgress size={10} sx={{ ml: 0.5 }} /> : undefined}
                                                    />
                                                </TableCell>
                                                <TableCell>
                                                    <Stack direction="row" alignItems="center" spacing={1}>
                                                        <Box sx={{ flex: 1 }}>
                                                            <LinearProgress
                                                                variant={isActive ? 'indeterminate' : 'determinate'}
                                                                value={progress}
                                                                color={
                                                                    batch.status === 'transforming' ? 'secondary'
                                                                    : batch.status === 'committed' ? 'success'
                                                                    : batch.status === 'failed' ? 'error'
                                                                    : 'primary'
                                                                }
                                                                sx={{ height: 5, borderRadius: 2 }}
                                                            />
                                                        </Box>
                                                        <Typography variant="caption" color="textSecondary" noWrap>
                                                            {batch.processed_count}/{batch.total_count}
                                                        </Typography>
                                                    </Stack>
                                                </TableCell>
                                                <TableCell>
                                                    <Chip label={batch.duplicate_count || 0} size="small" color={batch.duplicate_count > 0 ? 'warning' : 'default'} variant="outlined" />
                                                </TableCell>
                                                <TableCell>
                                                    <Chip label={batch.error_count || 0} size="small" color={batch.error_count > 0 ? 'error' : 'default'} variant="outlined" />
                                                </TableCell>
                                                <TableCell align="right">
                                                    <Stack direction="row" spacing={0.5} justifyContent="flex-end">
                                                        {batch.status === 'review_needed' && (
                                                            <Button variant="contained" size="small" startIcon={<Visibility />}
                                                                onClick={() => setSelectedBatchId(batch.id)}
                                                                sx={{ bgcolor: '#f59e0b', '&:hover': { bgcolor: '#d97706' }, textTransform: 'none', boxShadow: 'none' }}>
                                                                {t('ingestion.batch.audit')}
                                                            </Button>
                                                        )}
                                                        {batch.status === 'committed' && (
                                                            <Button variant="outlined" size="small"
                                                                onClick={() => setSelectedBatchId(batch.id)}
                                                                sx={{ textTransform: 'none' }}>
                                                                {t('ingestion.batch.viewReport')}
                                                            </Button>
                                                        )}
                                                        {(isActive || batch.status === 'review_needed') && (
                                                            <Tooltip title={t('ingestion.batch.abort')}>
                                                                <IconButton size="small" color="error" onClick={() => handleAbort(batch.id)}>
                                                                    <PauseCircle fontSize="small" />
                                                                </IconButton>
                                                            </Tooltip>
                                                        )}
                                                        {batch.status === 'failed' && (
                                                            <Tooltip title={t('ingestion.batch.delete')}>
                                                                <IconButton size="small" color="error" onClick={() => handleDelete(batch.id)}>
                                                                    <DeleteForever fontSize="small" />
                                                                </IconButton>
                                                            </Tooltip>
                                                        )}
                                                    </Stack>
                                                </TableCell>
                                            </TableRow>
                                        );
                                    })}
                                </TableBody>
                            </Table>
                        </TableContainer>

                        {/* Pagination */}
                        {totalPages > 1 && (
                            <Stack direction="row" justifyContent="center" spacing={1} sx={{ mt: 2 }}>
                                <Button size="small" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>← Prev</Button>
                                <Typography variant="caption" sx={{ alignSelf: 'center', px: 1 }}>
                                    Page {page} of {totalPages}
                                </Typography>
                                <Button size="small" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>Next →</Button>
                            </Stack>
                        )}
                    </>
                )}
            </Box>

            {/* ── New Migration Wizard ── */}
            <NewMigrationDialog
                open={wizardOpen}
                onClose={() => setWizardOpen(false)}
                onSuccess={() => {
                    setWizardOpen(false);
                    refreshAll();
                    notify(t('ingestion.wizard.launchSuccessGeneric'), 'success');
                }}
            />
        </Box>
    );
}




