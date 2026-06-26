import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Grid, Typography, Stack, MenuItem, Select, FormControl,
    TextField, Button, Paper, Alert, Chip, Divider,
    Skeleton, IconButton, Tooltip, Collapse
} from '@mui/material';
import {
    Refresh, Storage, Folder, WorkHistory,
    AutoAwesome, Block, Timer,
    ExpandMore, ExpandLess, Lightbulb, Warning, EmojiObjects
} from '@mui/icons-material';
import StatCard from './StatCard';
import AssetTrendChart from './charts/AssetTrendChart';
import ContentTypeDonut from './charts/ContentTypeDonut';
import StatusBreakdownChart from './charts/StatusBreakdownChart';
import TopFoldersChart from './charts/TopFoldersChart';
import WorkflowFunnelChart from './charts/WorkflowFunnelChart';
import AiCoverageChart from './charts/AiCoverageChart';
import { useNotify } from '../../../context/NotificationContext';

const DATE_RANGES = [
    { value: 'last_7_days',  label: 'Last 7 Days' },
    { value: 'last_30_days', label: 'Last 30 Days' },
    { value: 'last_90_days', label: 'Last 90 Days' },
    { value: 'this_quarter', label: 'This Quarter' },
    { value: 'this_year',    label: 'Year to Date' },
    { value: 'custom',       label: 'Custom Range…' },
];

export default function AnalyticsDashboard({ onCreateExport }) {
    const notify = useNotify();
    const [range, setRange]         = useState('last_30_days');
    const [customFrom, setCustomFrom] = useState('');
    const [customTo, setCustomTo]   = useState('');
    const [analytics, setAnalytics] = useState(null);
    const [loading, setLoading]     = useState(true);
    const [insightsOpen, setInsightsOpen] = useState(true);
    const lastRangeRef = useRef(null);

    const fetchAnalytics = useCallback(async (rangeKey = range) => {
        setLoading(true);
        try {
            let url = `/admin/reports/analytics?range=${rangeKey}`;
            if (rangeKey === 'custom' && customFrom) {
                url += `&from=${customFrom}&to=${customTo || new Date().toISOString().split('T')[0]}`;
            }
            const res  = await fetch(url, { headers: { Accept: 'application/json' } });
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const data = await res.json();
            setAnalytics(data);
            lastRangeRef.current = rangeKey;
        } catch (e) {
            notify(`Analytics error: ${e.message}`, 'error');
        } finally {
            setLoading(false);
        }
    }, [range, customFrom, customTo, notify]);

    useEffect(() => { fetchAnalytics(); }, []);

    const handleRangeChange = (newRange) => {
        setRange(newRange);
        if (newRange !== 'custom') fetchAnalytics(newRange);
    };

    const handleCustomApply = () => fetchAnalytics('custom');

    const s    = analytics?.stats || {};
    const ts   = analytics?.time_series?.combined || [];
    const bkd  = analytics?.breakdowns || {};
    const ai   = analytics?.ai_insights || {};

    const totalInsights = (ai.anomalies?.length || 0) + (ai.suggestions?.length || 0) + (ai.opportunities?.length || 0);

    return (
        <Box>
            {/* ── Toolbar ─────────────────────────────────────────────────── */}
            <Stack direction="row" sx={{ justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', mb: 3 }} gap={2}>
                <Box>
                    <Typography variant="h5" sx={{ fontWeight: 700, color: '#0f172a' }}>System Analytics</Typography>
                    <Typography variant="body2" color="textSecondary">
                        Live DAM performance metrics · {s.range_label || 'Last 30 Days'}
                    </Typography>
                </Box>

                <Stack direction="row" spacing={1.5} sx={{ alignItems: 'center', flexWrap: 'wrap' }}>
                    {/* Date range picker */}
                    <FormControl size="small" sx={{ minWidth: 160 }}>
                        <Select value={range} onChange={(e) => handleRangeChange(e.target.value)}
                            variant="outlined" sx={{ bgcolor: 'white' }}>
                            {DATE_RANGES.map(r => (
                                <MenuItem key={r.value} value={r.value}>{r.label}</MenuItem>
                            ))}
                        </Select>
                    </FormControl>

                    {range === 'custom' && (
                        <>
                            <TextField size="small" type="date" label="From" value={customFrom}
                                onChange={(e) => setCustomFrom(e.target.value)}
                                sx={{ bgcolor: 'white', width: 150 }} InputLabelProps={{ shrink: true }} />
                            <TextField size="small" type="date" label="To" value={customTo}
                                onChange={(e) => setCustomTo(e.target.value)}
                                sx={{ bgcolor: 'white', width: 150 }} InputLabelProps={{ shrink: true }} />
                            <Button variant="contained" size="small" onClick={handleCustomApply}
                                sx={{ bgcolor: '#5e35b1', textTransform: 'none' }}>Apply</Button>
                        </>
                    )}

                    <Tooltip title="Refresh"><IconButton onClick={() => fetchAnalytics()} size="small"><Refresh /></IconButton></Tooltip>
                    <Button variant="contained" size="small" onClick={onCreateExport}
                        sx={{ bgcolor: '#5e35b1', textTransform: 'none', '&:hover': { bgcolor: '#4527a0' } }}>
                        + Create Export
                    </Button>
                </Stack>
            </Stack>

            {/* ── AI Insights Panel ─────────────────────────────────────── */}
            {totalInsights > 0 && (
                <Paper elevation={0} sx={{ mb: 3, border: '1px solid #e0d7ff', bgcolor: '#faf5ff', borderRadius: 3, overflow: 'hidden' }}>
                    <Stack direction="row" alignItems="center" justifyContent="space-between"
                        sx={{ px: 2.5, py: 1.5, cursor: 'pointer' }}
                        onClick={() => setInsightsOpen(v => !v)}>
                        <Stack direction="row" alignItems="center" spacing={1}>
                            <AutoAwesome sx={{ color: '#7c3aed', fontSize: 18 }} />
                            <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#5b21b6' }}>
                                AI Insights &amp; Anomaly Detection
                            </Typography>
                            <Chip label={totalInsights} size="small" sx={{ bgcolor: '#7c3aed', color: 'white', height: 18, fontSize: 10 }} />
                        </Stack>
                        <IconButton size="small">{insightsOpen ? <ExpandLess /> : <ExpandMore />}</IconButton>
                    </Stack>
                    <Collapse in={insightsOpen}>
                        <Divider sx={{ borderColor: '#e0d7ff' }} />
                        <Box sx={{ p: 2.5, display: 'flex', flexDirection: 'column', gap: 1 }}>
                            {ai.anomalies?.map((msg, i) => (
                                <Alert key={`a${i}`} severity="warning" icon={<Warning fontSize="small" />}
                                    sx={{ py: 0.5, borderRadius: 2, '& .MuiAlert-message': { fontSize: 13 } }}>{msg}</Alert>
                            ))}
                            {ai.suggestions?.map((msg, i) => (
                                <Alert key={`s${i}`} severity="info" icon={<Lightbulb fontSize="small" />}
                                    sx={{ py: 0.5, borderRadius: 2, '& .MuiAlert-message': { fontSize: 13 } }}>{msg}</Alert>
                            ))}
                            {ai.opportunities?.map((msg, i) => (
                                <Alert key={`o${i}`} severity="success" icon={<EmojiObjects fontSize="small" />}
                                    sx={{ py: 0.5, borderRadius: 2, '& .MuiAlert-message': { fontSize: 13 } }}>{msg}</Alert>
                            ))}
                        </Box>
                    </Collapse>
                </Paper>
            )}

            {/* ── Stat Cards ────────────────────────────────────────────── */}
            <Grid container spacing={2} sx={{ mb: 3 }}>
                {[
                    { label: 'Total Assets',       value: s.total_assets?.toLocaleString(),      icon: <Storage />,    color: '#5e35b1', sub: `${s.new_in_range || 0} new this period` },
                    { label: 'Active Assets',       value: s.active_assets?.toLocaleString(),     icon: <Folder />,     color: '#0ea5e9', sub: `${s.in_trash || 0} in trash` },
                    { label: 'Pending Approvals',   value: s.pending_approvals?.toLocaleString(), icon: <WorkHistory />, color: '#f59e0b', sub: `${s.approved_in_range || 0} approved this period` },
                    { label: 'Active Workflows',    value: s.active_workflows?.toLocaleString(),  icon: <WorkHistory />, color: '#10b981' },
                    { label: 'Storage Used',        value: s.storage_used_gb != null ? `${s.storage_used_gb} GB` : null, icon: <Storage />, color: '#6366f1' },
                    { label: 'AI Coverage',         value: s.ai_embedding_coverage_pct != null ? `${s.ai_embedding_coverage_pct}%` : null, icon: <AutoAwesome />, color: '#8b5cf6', sub: `${s.ai_assets_covered || 0} assets indexed` },
                    { label: 'Avg. Approval Time',  value: s.avg_approval_hours != null ? `${s.avg_approval_hours}h` : null, icon: <Timer />, color: '#0284c7' },
                    { label: 'Duplicates Blocked',  value: s.duplicates_blocked?.toLocaleString(), icon: <Block />, color: '#dc2626' },
                ].map((card, i) => (
                    <Grid size={{ xs: 6, sm: 4, md: 3 }} key={i}>
                        <StatCard {...card} loading={loading} />
                    </Grid>
                ))}
            </Grid>

            {/* ── Charts Row 1 ──────────────────────────────────────────── */}
            <Grid container spacing={2.5} sx={{ mb: 2.5 }}>
                <Grid size={{ xs: 12, lg: 8 }}>
                    <AssetTrendChart data={ts} loading={loading} />
                </Grid>
                <Grid size={{ xs: 12, lg: 4 }}>
                    <AiCoverageChart data={ai} loading={loading} />
                </Grid>
            </Grid>

            {/* ── Charts Row 2 ──────────────────────────────────────────── */}
            <Grid container spacing={2.5} sx={{ mb: 2.5 }}>
                <Grid size={{ xs: 12, md: 4 }}>
                    <ContentTypeDonut data={bkd.by_content_type || []} loading={loading} />
                </Grid>
                <Grid size={{ xs: 12, md: 4 }}>
                    <StatusBreakdownChart data={bkd.by_status || []} loading={loading} />
                </Grid>
                <Grid size={{ xs: 12, md: 4 }}>
                    <WorkflowFunnelChart data={bkd.workflow_funnel || []} loading={loading} />
                </Grid>
            </Grid>

            {/* ── Charts Row 3 ──────────────────────────────────────────── */}
            <Grid container spacing={2.5}>
                <Grid size={{ xs: 12, md: 6 }}>
                    <TopFoldersChart data={bkd.top_folders || []} loading={loading} />
                </Grid>
                <Grid size={{ xs: 12, md: 6 }}>
                    {/* Top uploaders */}
                    <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, p: 2.5, height: '100%' }}>
                        <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 0.5 }}>Top Uploaders</Typography>
                        <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 2 }}>
                            Users by assets uploaded in period
                        </Typography>
                        {loading ? (
                            Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} variant="text" height={28} sx={{ mb: 0.5 }} />)
                        ) : (bkd.by_user || []).length === 0 ? (
                            <Typography color="textSecondary" variant="body2">No data</Typography>
                        ) : (
                            <Box>
                                {(bkd.by_user || []).slice(0, 8).map((u, i) => (
                                    <Stack key={i} direction="row" justifyContent="space-between" alignItems="center"
                                        sx={{ py: 0.8, borderBottom: '1px solid #f8fafc' }}>
                                        <Stack direction="row" alignItems="center" spacing={1}>
                                            <Box sx={{ width: 24, height: 24, borderRadius: '50%', bgcolor: '#e0d7ff',
                                                display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                                                <Typography variant="caption" sx={{ fontWeight: 700, color: '#5e35b1', fontSize: 10 }}>
                                                    {i + 1}
                                                </Typography>
                                            </Box>
                                            <Typography variant="body2" sx={{ fontWeight: 500 }}>{u.user || 'Unknown'}</Typography>
                                        </Stack>
                                        <Chip label={u.count.toLocaleString()} size="small"
                                            sx={{ bgcolor: '#f0f9ff', color: '#0369a1', fontWeight: 700, height: 20, fontSize: 11 }} />
                                    </Stack>
                                ))}
                            </Box>
                        )}
                    </Paper>
                </Grid>
            </Grid>
        </Box>
    );
}

