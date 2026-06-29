import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Grid, Card, CardContent, Typography, LinearProgress,
    Button, Chip, Paper, Stack, IconButton, Tooltip,
    CircularProgress, Alert, Tabs, Tab, Divider, Badge,
    Table, TableBody, TableCell, TableContainer, TableHead,
    TableRow, List, ListItem, ListItemText, ListItemIcon,
    Collapse
} from '@mui/material';
import {
    HealthAndSafety, Storage, TrendingDown, CheckCircle,
    Refresh, LinkOutlined,
    AutoGraph, CloudSync, ManageSearch, BuildCircle,
    LayersClear, Gavel, Archive, ArrowForward,
    QueryStats, RocketLaunch, FiberManualRecord,
    ContentCopy, AutoFixHigh
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';
import { DAM_PROVIDERS } from './ConnectorDialog';

// ── Helpers ──────────────────────────────────────────────────────────────────
const getProviderLabel = (type) =>
    DAM_PROVIDERS[type?.toLowerCase()]?.label || type || 'Unknown';

function healthScoreColor(score) {
    if (score === null || score === undefined) return '#94a3b8';
    if (score >= 80) return '#16a34a';
    if (score >= 50) return '#f59e0b';
    return '#dc2626';
}

function impactColor(impact) {
    if (impact === 'Critical') return 'error';
    if (impact === 'High')     return 'error';
    if (impact === 'Medium')   return 'warning';
    return 'default';
}

// ── Tab Panel wrapper ─────────────────────────────────────────────────────────
function TabPanel({ children, value, index }) {
    return value === index ? <Box sx={{ pt: 3 }}>{children}</Box> : null;
}

// ── Health Score Circle ───────────────────────────────────────────────────────
function HealthScoreCircle({ score, size = 44 }) {
    const color = healthScoreColor(score);
    if (score === null || score === undefined) {
        return (
            <Box sx={{ width: size, height: size, borderRadius: '50%', bgcolor: '#f1f5f9', border: '2px solid #e2e8f0', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Typography variant="caption" sx={{ color: '#94a3b8', fontWeight: 700, fontSize: '0.6rem' }}>N/A</Typography>
            </Box>
        );
    }
    return (
        <Box sx={{ position: 'relative', width: size, height: size }}>
            <CircularProgress
                variant="determinate"
                value={score}
                size={size}
                sx={{ color, position: 'absolute', top: 0, left: 0 }}
            />
            <CircularProgress
                variant="determinate"
                value={100}
                size={size}
                sx={{ color: '#f1f5f9', position: 'absolute', top: 0, left: 0 }}
            />
            <CircularProgress
                variant="determinate"
                value={score}
                size={size}
                sx={{ color, position: 'absolute', top: 0, left: 0 }}
            />
            <Box sx={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Typography sx={{ fontSize: '0.68rem', fontWeight: 700, color, lineHeight: 1 }}>{score}</Typography>
            </Box>
        </Box>
    );
}

// ── Metric Card ───────────────────────────────────────────────────────────────
function MetricCard({ label, value, sub, icon, color, loading, onClick }) {
    return (
        <Card
            elevation={0}
            onClick={onClick}
            sx={{
                border: '1px solid #e3e8ef', borderRadius: 3, height: '100%',
                cursor: onClick ? 'pointer' : 'default',
                transition: 'box-shadow 0.15s',
                '&:hover': onClick ? { boxShadow: '0 4px 16px rgba(0,0,0,0.08)' } : {},
            }}
        >
            <CardContent>
                <Stack direction="row" justifyContent="space-between" alignItems="flex-start">
                    <Box>
                        <Typography color="textSecondary" variant="caption"
                            sx={{ fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.06em' }}>
                            {label}
                        </Typography>
                        {loading ? (
                            <Box sx={{ mt: 1.5 }}><CircularProgress size={20} sx={{ color }} /></Box>
                        ) : (
                            <Typography variant="h4" sx={{ fontWeight: 700, mt: 0.5, color, lineHeight: 1.1 }}>
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

// ── Storage Composition Bar ───────────────────────────────────────────────────
function StorageCompositionBar({ storage }) {
    const { active_used_tb = 0, orphaned_wasted_tb = 0, duplicates_prevented_tb = 0 } = storage || {};
    const totalKnown = active_used_tb + orphaned_wasted_tb + duplicates_prevented_tb;
    const allocated  = Math.max(totalKnown, 1);

    const activePct   = (active_used_tb / allocated * 100).toFixed(1);
    const orphanPct   = (orphaned_wasted_tb / allocated * 100).toFixed(1);
    const preventPct  = (duplicates_prevented_tb / allocated * 100).toFixed(1);

    const segments = [
        { label: `Active (${active_used_tb.toFixed(2)} TB)`,     pct: activePct,   color: '#5e35b1' },
        { label: `Orphaned (${orphaned_wasted_tb.toFixed(2)} TB)`, pct: orphanPct,  color: '#ef4444' },
        { label: `Dedup Saved (${duplicates_prevented_tb.toFixed(4)} TB)`, pct: preventPct, color: '#16a34a' },
    ];

    return (
        <Box>
            <Box sx={{ height: 28, width: '100%', display: 'flex', borderRadius: 1, overflow: 'hidden', border: '1px solid #e2e8f0', mb: 2 }}>
                {segments.map(seg => (
                    <Tooltip key={seg.label} title={seg.label}>
                        <Box sx={{ width: `${seg.pct}%`, bgcolor: seg.color, minWidth: parseFloat(seg.pct) > 0 ? 2 : 0 }} />
                    </Tooltip>
                ))}
                <Tooltip title="Free / Untracked">
                    <Box sx={{ flexGrow: 1, bgcolor: '#f1f5f9' }} />
                </Tooltip>
            </Box>
            <Stack direction="row" spacing={3} flexWrap="wrap" gap={1}>
                {segments.map(seg => (
                    <Stack key={seg.label} direction="row" spacing={0.5} alignItems="center">
                        <FiberManualRecord sx={{ fontSize: 10, color: seg.color }} />
                        <Typography variant="caption" color="textSecondary">{seg.label}</Typography>
                    </Stack>
                ))}
                <Stack direction="row" spacing={0.5} alignItems="center">
                    <FiberManualRecord sx={{ fontSize: 10, color: '#f1f5f9', border: '1px solid #cbd5e1', borderRadius: '50%' }} />
                    <Typography variant="caption" color="textSecondary">Free</Typography>
                </Stack>
            </Stack>
        </Box>
    );
}

// ── Connector Health Row ──────────────────────────────────────────────────────
function ConnectorHealthTableRow({ conn, onPreFlight, preFlight }) {
    const notify = useNotify();
    const report = conn.analysis_report;

    const copyWebhook = () => {
        const url = `${window.location.origin}/api/v1/webhooks/connectors/${conn.id}/receive`;
        navigator.clipboard.writeText(url);
        notify('Webhook URL copied', 'success');
    };

    return (
        <TableRow hover>
            <TableCell>
                <Stack direction="row" spacing={1.5} alignItems="center">
                    <HealthScoreCircle score={conn.health_score} size={38} />
                    <Box>
                        <Typography variant="subtitle2" sx={{ fontWeight: 700, lineHeight: 1.2 }}>{conn.name}</Typography>
                        <Typography variant="caption" color="textSecondary">{getProviderLabel(conn.provider_type)}</Typography>
                    </Box>
                </Stack>
            </TableCell>
            <TableCell>
                <Chip
                    label={conn.status?.toUpperCase()}
                    size="small"
                    color={conn.status === 'active' ? 'success' : conn.status === 'disabled' ? 'error' : 'warning'}
                    sx={{ height: 20, fontSize: '0.62rem', fontWeight: 700 }}
                />
            </TableCell>
            <TableCell>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>{conn.assets_imported.toLocaleString()}</Typography>
                <Typography variant="caption" color="textSecondary">{conn.batches_count} batch(es)</Typography>
            </TableCell>
            <TableCell>
                <Typography variant="caption" color="textSecondary">
                    {conn.last_sync ? new Date(conn.last_sync).toLocaleDateString() : '—'}
                </Typography>
            </TableCell>
            <TableCell>
                {report ? (
                    <Box sx={{ bgcolor: '#f0fdf4', border: '1px solid #bbf7d0', borderRadius: 1.5, p: 1 }}>
                        <Typography variant="caption" sx={{ fontWeight: 700, color: '#166534', display: 'block' }}>
                            {report.total_found?.toLocaleString()} assets found
                        </Typography>
                        {report.missing_tags > 0 && (
                            <Typography variant="caption" color="error">
                                {report.missing_tags?.toLocaleString()} missing tags
                            </Typography>
                        )}
                        {report.estimated_size_gb && (
                            <Typography variant="caption" color="textSecondary" sx={{ display: 'block' }}>
                                ~{report.estimated_size_gb} GB
                            </Typography>
                        )}
                    </Box>
                ) : (
                    <Typography variant="caption" color="textSecondary">No report yet</Typography>
                )}
            </TableCell>
            <TableCell>
                {conn.tdm_sanitation ? (
                    <Chip icon={<AutoFixHigh sx={{ fontSize: '0.8rem' }} />} label="Active" size="small"
                        sx={{ height: 18, fontSize: '0.6rem', bgcolor: '#f3e8ff', color: '#7e22ce' }} />
                ) : (
                    <Chip label="Bypassed" size="small" variant="outlined" sx={{ height: 18, fontSize: '0.6rem' }} />
                )}
            </TableCell>
            <TableCell align="right">
                <Stack direction="row" spacing={0.5} justifyContent="flex-end">
                    <Tooltip title="Run Pre-Flight Analysis">
                        <IconButton size="small" onClick={() => onPreFlight(conn.id)}
                            disabled={preFlight === conn.id}>
                            {preFlight === conn.id
                                ? <CircularProgress size={16} />
                                : <QueryStats fontSize="small" sx={{ color: '#64748b' }} />}
                        </IconButton>
                    </Tooltip>
                    <Tooltip title="Configure Connector">
                        <IconButton size="small" href="/admin/migrations/connectors" component="a">
                            <BuildCircle fontSize="small" sx={{ color: '#64748b' }} />
                        </IconButton>
                    </Tooltip>
                    <Tooltip title="Copy Webhook URL">
                        <IconButton size="small" onClick={copyWebhook}>
                            <ContentCopy fontSize="small" sx={{ color: '#64748b' }} />
                        </IconButton>
                    </Tooltip>
                    {conn.status === 'active' && (
                        <Tooltip title="Start Migration">
                            <IconButton size="small" href="/admin/migrations/ingestion" component="a"
                                sx={{ color: '#5e35b1' }}>
                                <RocketLaunch fontSize="small" />
                            </IconButton>
                        </Tooltip>
                    )}
                </Stack>
            </TableCell>
        </TableRow>
    );
}

// ── Debt Flag Row ─────────────────────────────────────────────────────────────
function DebtFlagRow({ flag, onRemediate, isRemediating }) {
    const impactSeverity = flag.impact === 'None' ? 'success' : impactColor(flag.impact);

    return (
        <ListItem sx={{ px: 3, py: 2.5, display: 'flex', alignItems: 'flex-start', gap: 2 }}
            divider>
            <ListItemIcon sx={{ mt: 0.5, minWidth: 36 }}>
                {flag.type === 'duplicates' && <LayersClear color={flag.count > 0 ? 'error' : 'disabled'} />}
                {flag.type === 'missing_metadata' && <ManageSearch color="warning" />}
                {flag.type === 'copyright' && <Gavel color={flag.impact === 'Critical' ? 'error' : 'warning'} />}
                {flag.type === 'review_pipeline' && <Archive color={flag.count > 0 ? 'warning' : 'disabled'} />}
            </ListItemIcon>
            <ListItemText
                primary={
                    <Stack direction="row" alignItems="center" spacing={1.5} sx={{ mb: 0.5 }} flexWrap="wrap">
                        <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>{flag.title}</Typography>
                        {flag.impact !== 'None' && (
                            <Chip label={`${flag.impact} Impact`} size="small"
                                color={impactSeverity}
                                sx={{ height: 18, fontSize: '0.62rem', fontWeight: 700 }} />
                        )}
                        {flag.count > 0 && (
                            <Chip label={flag.count.toLocaleString()} size="small" variant="outlined"
                                sx={{ height: 18, fontSize: '0.62rem' }} />
                        )}
                    </Stack>
                }
                secondary={flag.description}
                slotProps={{ secondary: { variant: 'body2', color: 'textSecondary' } }}
            />
            <Box sx={{ ml: 'auto', flexShrink: 0 }}>
                <Stack direction="row" spacing={1}>
                    {flag.can_automate && (
                        <Button
                            variant="outlined"
                            size="small"
                            startIcon={isRemediating === flag.type
                                ? <CircularProgress size={14} /> : <BuildCircle />}
                            disabled={isRemediating === flag.type || !flag.actionable}
                            onClick={() => onRemediate(flag.type)}
                            sx={{ textTransform: 'none', borderRadius: '6px', color: '#475569', borderColor: '#cbd5e1' }}
                        >
                            {isRemediating === flag.type ? 'Running…' : 'Auto-Remediate'}
                        </Button>
                    )}
                    <Button
                        variant={flag.actionable ? 'contained' : 'outlined'}
                        size="small"
                        endIcon={<ArrowForward />}
                        href={flag.action_link}
                        disabled={!flag.actionable}
                        sx={{
                            textTransform: 'none', borderRadius: '6px', boxShadow: 'none',
                            ...(flag.actionable ? { bgcolor: '#121926', '&:hover': { bgcolor: '#334155' } } : {}),
                        }}
                    >
                        {flag.action_label}
                    </Button>
                </Stack>
            </Box>
        </ListItem>
    );
}

// ── Main Dashboard ────────────────────────────────────────────────────────────
export default function DataHealthDashboard() {
    const { t }  = useTranslation();
    const notify = useNotify();

    const [overview, setOverview]           = useState(null);
    const [connectors, setConnectors]       = useState([]);
    const [loading, setLoading]             = useState(true);
    const [connsLoading, setConnsLoading]   = useState(true);
    const [activeTab, setActiveTab]         = useState(0);
    const [isRemediating, setIsRemediating] = useState(null);
    const [preFlight, setPreFlight]         = useState(null);    // connector_id being scanned
    const pollRef = useRef(null);

    const fetchOverview = useCallback(async () => {
        try {
            const res  = await fetch('/api/v1/data_health/overview');
            if (!res.ok) return;
            const data = await res.json();
            setOverview(data);
        } catch { /* non-fatal */ }
        finally { setLoading(false); }
    }, []);

    const fetchConnectors = useCallback(async () => {
        try {
            const res  = await fetch('/api/v1/data_health/connectors');
            if (!res.ok) return;
            const data = await res.json();
            setConnectors(Array.isArray(data) ? data : []);
        } catch { /* non-fatal */ }
        finally { setConnsLoading(false); }
    }, []);

    const refreshAll = useCallback(() => {
        fetchOverview();
        if (activeTab === 1) fetchConnectors();
    }, [fetchOverview, fetchConnectors, activeTab]);

    useEffect(() => { fetchOverview(); }, [fetchOverview]);

    useEffect(() => {
        if (activeTab === 1 && connectors.length === 0) fetchConnectors();
    }, [activeTab, connectors.length, fetchConnectors]);

    // Poll while a duplicate scan is running
    useEffect(() => {
        const scanStatus = overview?.scan?.status;
        clearInterval(pollRef.current);
        if (scanStatus === 'running' || scanStatus === 'queued') {
            pollRef.current = setInterval(fetchOverview, 5000);
        }
        return () => clearInterval(pollRef.current);
    }, [overview?.scan?.status, fetchOverview]);

    const handlePreFlight = async (connectorId) => {
        setPreFlight(connectorId);
        try {
            const csrf = document.querySelector('[name="csrf-token"]').content;
            const res  = await fetch('/api/v1/system_connectors/pre_flight_analysis', {
                method:  'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
                body:    JSON.stringify({ id: connectorId }),
            });
            if (res.ok) {
                notify(t('dataHealth.preFlight.queued'), 'success');
                setTimeout(() => { fetchConnectors(); setPreFlight(null); }, 3000);
            } else {
                notify(t('dataHealth.preFlight.failed'), 'error');
                setPreFlight(null);
            }
        } catch {
            notify(t('dataHealth.preFlight.failed'), 'error');
            setPreFlight(null);
        }
    };

    const handleRemediate = async (debtType) => {
        setIsRemediating(debtType);
        try {
            const csrf = document.querySelector('[name="csrf-token"]').content;
            const res  = await fetch('/api/v1/data_health/remediate', {
                method:  'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
                body:    JSON.stringify({ debt_type: debtType }),
            });
            const data = await res.json();
            if (res.ok) {
                notify(data.message, 'success');
                setTimeout(refreshAll, 2000);
            } else {
                notify(data.error || t('dataHealth.remediate.failed'), 'error');
            }
        } catch {
            notify(t('dataHealth.remediate.failed'), 'error');
        } finally {
            setIsRemediating(null);
        }
    };

    const handleTriggerScan = async () => {
        try {
            const csrf = document.querySelector('[name="csrf-token"]').content;
            const res  = await fetch('/api/v1/duplicate_manager_settings/trigger_scan', {
                method:  'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
            });
            const data = await res.json();
            if (res.ok) { notify(data.message, 'success'); fetchOverview(); }
            else notify(data.error || t('dataHealth.scan.failed'), 'error');
        } catch { notify(t('dataHealth.scan.failed'), 'error'); }
    };

    const scan     = overview?.scan;
    const storage  = overview?.storage;
    const dupes    = overview?.duplicates;
    const batches  = overview?.batches;
    const debt     = overview?.debt_flags || [];
    const connsMeta = overview?.connectors;

    const scanRunning = scan?.status === 'running' || scan?.status === 'queued';
    const scanPct     = scan?.progress?.total > 0
        ? Math.round((scan.progress.processed / scan.progress.total) * 100) : 0;

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>

            {/* ── Page Header ── */}
            <Stack direction="row" justifyContent="space-between" alignItems="flex-start" sx={{ mb: 4 }} flexWrap="wrap" gap={2}>
                <Box>
                    <Stack direction="row" spacing={0.5} alignItems="center" sx={{ mb: 0.5 }}>
                        <Typography variant="caption" color="textSecondary">Data &amp; Migrations</Typography>
                        <Typography variant="caption" color="textSecondary">›</Typography>
                        <Typography component="a" href="/admin/migrations/connectors" variant="caption"
                            sx={{ color: '#0ea5e9', textDecoration: 'none', '&:hover': { textDecoration: 'underline' } }}>
                            Legacy Connectors
                        </Typography>
                        <Typography variant="caption" color="textSecondary">›</Typography>
                        <Typography variant="caption" color="textSecondary">{t('dataHealth.title')}</Typography>
                    </Stack>

                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', display: 'flex', alignItems: 'center', gap: 1 }}>
                        <HealthAndSafety sx={{ color: '#5e35b1', fontSize: 32 }} />
                        {t('dataHealth.title')}
                    </Typography>
                    <Typography variant="body2" color="textSecondary">{t('dataHealth.subtitle')}</Typography>
                </Box>

                <Stack direction="row" spacing={1.5} flexWrap="wrap">
                    <Button variant="outlined" startIcon={<LinkOutlined />} href="/admin/migrations/connectors"
                        sx={{ textTransform: 'none', borderRadius: '8px', color: '#475569', borderColor: '#cbd5e1', bgcolor: 'white' }}>
                        {t('dataHealth.manageConnectors')}
                    </Button>
                    <Button variant="outlined" startIcon={<Refresh />} onClick={refreshAll}
                        sx={{ textTransform: 'none', borderRadius: '8px', color: '#475569', borderColor: '#cbd5e1', bgcolor: 'white' }}>
                        {t('common.refresh')}
                    </Button>
                    <Button variant="outlined" startIcon={<ManageSearch />}
                        disabled={scanRunning}
                        onClick={handleTriggerScan}
                        sx={{ textTransform: 'none', borderRadius: '8px', color: '#475569', borderColor: '#cbd5e1', bgcolor: 'white' }}>
                        {scanRunning ? t('dataHealth.scan.running') : t('dataHealth.scan.trigger')}
                    </Button>
                    <Button variant="contained" startIcon={<AutoGraph />}
                        href="/admin/migrations/ingestion"
                        sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                        {t('dataHealth.viewPipeline')}
                    </Button>
                </Stack>
            </Stack>

            {/* ── Scan Status Banner ── */}
            <Collapse in={scanRunning}>
                <Alert severity="info" sx={{ mb: 3, borderRadius: 2 }}
                    icon={<CircularProgress size={20} color="inherit" />}
                    action={
                        <Typography variant="caption" sx={{ alignSelf: 'center', mr: 1 }}>
                            {scan?.status === 'running' && scan?.progress?.total > 0
                                ? `${scanPct}% (${scan.progress.processed}/${scan.progress.total})`
                                : scan?.status === 'queued' ? 'Queued…' : ''}
                        </Typography>
                    }
                >
                    <strong>{t('dataHealth.scan.inProgress')}</strong> — {t('dataHealth.scan.inProgressSub')}
                    {scan?.progress?.total > 0 && (
                        <Box sx={{ mt: 1 }}>
                            <LinearProgress variant="determinate" value={scanPct} sx={{ height: 4, borderRadius: 2 }} />
                        </Box>
                    )}
                </Alert>
            </Collapse>

            {/* ── Metric Cards ── */}
            <Grid container spacing={3} sx={{ mb: 4 }}>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('dataHealth.metrics.pendingDuplicates')}
                        value={dupes?.pending ?? '—'}
                        sub={`${dupes?.resolved ?? 0} resolved · ${dupes?.dismissed ?? 0} dismissed`}
                        icon={<LayersClear sx={{ color: '#f59e0b', fontSize: 28 }} />}
                        color={dupes?.pending > 0 ? '#f59e0b' : '#16a34a'}
                        loading={loading}
                        onClick={() => window.location.href = '/admin/duplicates'}
                    />
                </Grid>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('dataHealth.metrics.storageSaved')}
                        value={`${storage?.duplicates_prevented_tb?.toFixed(4) ?? '0.0000'} TB`}
                        sub="Prevented at ingestion edge"
                        icon={<TrendingDown sx={{ color: '#8b5cf6', fontSize: 28 }} />}
                        color="#8b5cf6"
                        loading={loading}
                    />
                </Grid>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('dataHealth.metrics.costSavings')}
                        value={`$${storage?.estimated_savings_usd_mo?.toFixed(2) ?? '0.00'}/mo`}
                        sub="Cloud egress & storage overhead"
                        icon={<CheckCircle sx={{ color: '#16a34a', fontSize: 28 }} />}
                        color="#16a34a"
                        loading={loading}
                    />
                </Grid>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('dataHealth.metrics.activeConnectors')}
                        value={connsMeta?.active ?? '—'}
                        sub={`${connsMeta?.total ?? 0} total · ${connsMeta?.idle ?? 0} idle`}
                        icon={<CloudSync sx={{ color: '#0ea5e9', fontSize: 28 }} />}
                        color="#0ea5e9"
                        loading={loading}
                        onClick={() => setActiveTab(1)}
                    />
                </Grid>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('dataHealth.metrics.batchesMigrated')}
                        value={batches?.completed ?? '—'}
                        sub={`${batches?.active ?? 0} active · ${batches?.failed ?? 0} failed`}
                        icon={<Storage sx={{ color: '#64748b', fontSize: 28 }} />}
                        color="#121926"
                        loading={loading}
                        onClick={() => window.location.href = '/admin/migrations/ingestion'}
                    />
                </Grid>
                <Grid size={{ xs: 12, sm: 6, md: 2 }}>
                    <MetricCard
                        label={t('dataHealth.metrics.lastScan')}
                        value={scan?.last_scan_at ? new Date(scan.last_scan_at).toLocaleDateString() : 'Never'}
                        sub={scan?.status ? `Status: ${scan.status}` : 'No scan history'}
                        icon={<ManageSearch sx={{ color: scan?.status === 'completed' ? '#16a34a' : '#64748b', fontSize: 28 }} />}
                        color={scan?.status === 'completed' ? '#16a34a' : '#121926'}
                        loading={loading}
                    />
                </Grid>
            </Grid>

            {/* ── Tabbed Content ── */}
            <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, overflow: 'hidden' }}>
                <Tabs
                    value={activeTab}
                    onChange={(_, v) => setActiveTab(v)}
                    sx={{ px: 2, borderBottom: '1px solid #e3e8ef', bgcolor: '#f8fafc' }}
                    TabIndicatorProps={{ style: { backgroundColor: '#5e35b1' } }}
                >
                    <Tab label={t('dataHealth.tabs.storage')}   sx={{ textTransform: 'none', fontWeight: 600 }} />
                    <Tab label={
                        <Badge badgeContent={connsMeta?.active || 0} color="info" sx={{ '& .MuiBadge-badge': { fontSize: '0.6rem' } }}>
                            <span style={{ paddingRight: 8 }}>{t('dataHealth.tabs.connectors')}</span>
                        </Badge>
                    } sx={{ textTransform: 'none', fontWeight: 600 }} />
                    <Tab label={
                        <Badge badgeContent={debt.filter(f => f.count > 0 && f.impact !== 'None').length || null} color="error"
                            sx={{ '& .MuiBadge-badge': { fontSize: '0.6rem' } }}>
                            <span style={{ paddingRight: 8 }}>{t('dataHealth.tabs.debt')}</span>
                        </Badge>
                    } sx={{ textTransform: 'none', fontWeight: 600 }} />
                </Tabs>

                <Box sx={{ p: 3 }}>
                    {/* ── Tab 0: Storage Overview ── */}
                    <TabPanel value={activeTab} index={0}>
                        {loading ? (
                            <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}><CircularProgress /></Box>
                        ) : (
                            <Grid container spacing={3}>
                                {/* Storage Composition */}
                                <Grid size={{ xs: 12, md: 7 }}>
                                    <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 2 }}>
                                        <CardContent>
                                            <Typography variant="caption" sx={{ fontWeight: 700, textTransform: 'uppercase', color: '#64748b', letterSpacing: '0.06em', display: 'block', mb: 2 }}>
                                                {t('dataHealth.storage.compositionTitle')}
                                            </Typography>
                                            <StorageCompositionBar storage={storage} />
                                            <Divider sx={{ my: 2 }} />
                                            <Grid container spacing={2}>
                                                {[
                                                    { label: 'Active Storage', value: `${storage?.active_used_tb?.toFixed(4)} TB` },
                                                    { label: 'Orphaned Assets', value: `${storage?.orphaned_wasted_tb?.toFixed(4)} TB`, warn: storage?.orphaned_wasted_tb > 0.01 },
                                                    { label: 'Dedup Prevented', value: `${storage?.duplicates_prevented_tb?.toFixed(4)} TB`, green: true },
                                                    { label: 'Assets Committed', value: (storage?.total_assets_committed || 0).toLocaleString() },
                                                    { label: 'Assets Staged', value: (storage?.total_assets_staged || 0).toLocaleString() },
                                                    { label: 'Dupes Blocked', value: (storage?.total_duplicates_blocked || 0).toLocaleString() },
                                                ].map(({ label, value, warn, green }) => (
                                                    <Grid size={{ xs: 6, sm: 4 }} key={label}>
                                                        <Box sx={{ textAlign: 'center', p: 1, bgcolor: '#f8fafc', borderRadius: 1.5 }}>
                                                            <Typography variant="body2" sx={{ fontWeight: 700, color: green ? '#16a34a' : warn ? '#ef4444' : '#121926' }}>
                                                                {value}
                                                            </Typography>
                                                            <Typography variant="caption" color="textSecondary">{label}</Typography>
                                                        </Box>
                                                    </Grid>
                                                ))}
                                            </Grid>
                                        </CardContent>
                                    </Card>
                                </Grid>

                                {/* Migration Pipeline Summary */}
                                <Grid size={{ xs: 12, md: 5 }}>
                                    <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 2, height: '100%' }}>
                                        <CardContent>
                                            <Typography variant="caption" sx={{ fontWeight: 700, textTransform: 'uppercase', color: '#64748b', letterSpacing: '0.06em', display: 'block', mb: 2 }}>
                                                {t('dataHealth.storage.pipelineTitle')}
                                            </Typography>
                                            {[
                                                { label: 'Active Migrations',    value: batches?.active,    color: '#0ea5e9' },
                                                { label: 'Completed Migrations', value: batches?.completed, color: '#16a34a' },
                                                { label: 'Failed Migrations',    value: batches?.failed,    color: '#ef4444' },
                                                { label: 'Total Batches',        value: batches?.total,     color: '#121926' },
                                            ].map(({ label, value, color }) => (
                                                <Stack key={label} direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 1.5 }}>
                                                    <Typography variant="body2" color="textSecondary">{label}</Typography>
                                                    <Typography variant="body2" sx={{ fontWeight: 700, color }}>{value ?? '—'}</Typography>
                                                </Stack>
                                            ))}
                                            <Divider sx={{ my: 2 }} />
                                            <Stack direction="row" spacing={1}>
                                                <Button variant="outlined" size="small" href="/admin/migrations/ingestion"
                                                    endIcon={<ArrowForward />}
                                                    sx={{ textTransform: 'none', flex: 1 }}>
                                                    View Pipeline
                                                </Button>
                                                <Button variant="outlined" size="small" href="/admin/migrations/connectors"
                                                    endIcon={<ArrowForward />}
                                                    sx={{ textTransform: 'none', flex: 1 }}>
                                                    Connectors
                                                </Button>
                                            </Stack>
                                        </CardContent>
                                    </Card>
                                </Grid>

                                {/* Cost Savings Banner */}
                                <Grid size={{ xs: 12 }}>
                                    <Paper elevation={0} sx={{ p: 2.5, border: '1px solid #bbf7d0', bgcolor: '#f0fdf4', borderRadius: 2 }}>
                                        <Stack direction="row" spacing={2} alignItems="center" flexWrap="wrap">
                                            <TrendingDown sx={{ color: '#15803d', fontSize: 32 }} />
                                            <Box>
                                                <Typography variant="subtitle1" sx={{ fontWeight: 700, color: '#15803d' }}>
                                                    Estimated Monthly Savings: <strong>${storage?.estimated_savings_usd_mo?.toFixed(2) ?? '0.00'}</strong>
                                                </Typography>
                                                <Typography variant="body2" color="textSecondary">
                                                    {storage?.estimated_savings_gb?.toFixed(2) ?? '0.00'} GB deduplication savings at $0.023/GB/mo (AWS S3 Standard).
                                                    {storage?.total_duplicates_blocked > 0 && ` ${storage.total_duplicates_blocked.toLocaleString()} duplicate uploads blocked at ingestion.`}
                                                </Typography>
                                            </Box>
                                        </Stack>
                                    </Paper>
                                </Grid>
                            </Grid>
                        )}
                    </TabPanel>

                    {/* ── Tab 1: Connector Health ── */}
                    <TabPanel value={activeTab} index={1}>
                        {connsLoading ? (
                            <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}><CircularProgress /></Box>
                        ) : connectors.length === 0 ? (
                            <Paper elevation={0} sx={{ p: 6, textAlign: 'center', border: '1px dashed #cbd5e1', borderRadius: 2 }}>
                                <CloudSync sx={{ fontSize: 48, color: '#cbd5e1', mb: 2, display: 'block', mx: 'auto' }} />
                                <Typography color="textSecondary" sx={{ mb: 2 }}>{t('dataHealth.connectors.none')}</Typography>
                                <Button variant="contained" href="/admin/migrations/connectors"
                                    sx={{ textTransform: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, boxShadow: 'none' }}>
                                    {t('dataHealth.manageConnectors')}
                                </Button>
                            </Paper>
                        ) : (
                            <>
                                <Alert severity="info" sx={{ mb: 2, borderRadius: 2 }}>
                                    <strong>Health Score</strong> = 100 − penalties for inactive status (−40), no recent sync (−20), stale sync &gt;7 days (−20), poor metadata quality (−20), no pre-flight report (−10).
                                </Alert>
                                <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 2 }}>
                                    <Table>
                                        <TableHead sx={{ bgcolor: '#f8fafc' }}>
                                            <TableRow>
                                                <TableCell sx={{ fontWeight: 600 }}>Connector</TableCell>
                                                <TableCell sx={{ fontWeight: 600 }}>Status</TableCell>
                                                <TableCell sx={{ fontWeight: 600 }}>Assets</TableCell>
                                                <TableCell sx={{ fontWeight: 600 }}>Last Sync</TableCell>
                                                <TableCell sx={{ fontWeight: 600 }}>Pre-Flight Report</TableCell>
                                                <TableCell sx={{ fontWeight: 600 }}>AI/TDM</TableCell>
                                                <TableCell align="right" sx={{ fontWeight: 600 }}>Actions</TableCell>
                                            </TableRow>
                                        </TableHead>
                                        <TableBody>
                                            {connectors.map(conn => (
                                                <ConnectorHealthTableRow
                                                    key={conn.id}
                                                    conn={conn}
                                                    onPreFlight={handlePreFlight}
                                                    preFlight={preFlight}
                                                />
                                            ))}
                                        </TableBody>
                                    </Table>
                                </TableContainer>
                            </>
                        )}
                    </TabPanel>

                    {/* ── Tab 2: Debt Remediation ── */}
                    <TabPanel value={activeTab} index={2}>
                        {loading ? (
                            <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}><CircularProgress /></Box>
                        ) : (
                            <>
                                <Alert severity="warning" sx={{ mb: 3, borderRadius: 2 }}>
                                    <strong>Debt Remediation Centre</strong> — Live counts are fetched from the database.
                                    Auto-remediate actions queue Sidekiq workers. Irreversible changes are never automated;
                                    all workers log their actions for audit purposes.
                                </Alert>
                                <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 2 }}>
                                    <List sx={{ p: 0 }}>
                                        {debt.map((flag) => (
                                            <React.Fragment key={flag.type}>
                                                <DebtFlagRow
                                                    flag={flag}
                                                    onRemediate={handleRemediate}
                                                    isRemediating={isRemediating}
                                                />
                                            </React.Fragment>
                                        ))}
                                    </List>
                                </Paper>
                            </>
                        )}
                    </TabPanel>
                </Box>
            </Paper>

        </Box>
    );
}

