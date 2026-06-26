import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Grid, Card, CardContent, Typography, LinearProgress,
    Button, Chip, Table, TableBody, TableCell, TableContainer,
    TableHead, TableRow, Paper, Stack, IconButton, Tooltip,
    CircularProgress, Alert
} from '@mui/material';
import {
    Storage, TrendingDown, Visibility, PlayArrow, Refresh,
    CheckCircle, ErrorOutlined, PauseCircle, AutoAwesome
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';
import BatchReviewWorkspace from './BatchReviewWorkspace';

const STATUS_CONFIG = {
    initializing:  { label: 'Initializing',      color: 'default',   icon: <CircularProgress size={12} /> },
    extracting:    { label: 'Extracting Files',   color: 'info',      icon: <PlayArrow fontSize="small" /> },
    transforming:  { label: 'AI Transforming',    color: 'secondary', icon: <AutoAwesome fontSize="small" /> },
    review_needed: { label: 'Needs Your Review',  color: 'warning',   icon: null },
    committed:     { label: 'Committed to DAM',   color: 'success',   icon: <CheckCircle fontSize="small" /> },
    failed:        { label: 'Pipeline Failed',    color: 'error',     icon: <ErrorOutlined fontSize="small" /> },
};

const IN_PROGRESS_STATUSES = ['initializing', 'extracting', 'transforming'];

export default function IngestionDashboard() {
    const notify = useNotify();
    const [batches, setBatches] = useState([]);
    const [loading, setLoading] = useState(true);
    const [selectedBatchId, setSelectedBatchId] = useState(null);
    const pollRef = useRef(null);

    const fetchBatches = useCallback(async () => {
        try {
            const res  = await fetch('/api/v1/ingestion_batches');
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const data = await res.json();
            setBatches(data);
        } catch (e) {
            notify(`Failed to load batches: ${e.message}`, 'error');
        } finally {
            setLoading(false);
        }
    }, [notify]);

    // Auto-refresh every 5s while any batch is in progress
    useEffect(() => {
        fetchBatches();
        pollRef.current = setInterval(() => {
            const hasActive = batches.some(b => IN_PROGRESS_STATUSES.includes(b.status));
            if (hasActive) fetchBatches();
        }, 5000);
        return () => clearInterval(pollRef.current);
    }, [fetchBatches]);

    // Re-run polling check when batches change
    useEffect(() => {
        const hasActive = batches.some(b => IN_PROGRESS_STATUSES.includes(b.status));
        clearInterval(pollRef.current);
        if (hasActive) {
            pollRef.current = setInterval(fetchBatches, 5000);
        }
        return () => clearInterval(pollRef.current);
    }, [batches, fetchBatches]);

    const handleAbort = async (batchId) => {
        if (!window.confirm('Abort this migration? All staged items will be discarded.')) return;
        try {
            const csrf = document.querySelector('[name="csrf-token"]').content;
            const res  = await fetch(`/api/v1/ingestion_batches/${batchId}/abort`, {
                method: 'POST',
                headers: { 'X-CSRF-Token': csrf, 'Content-Type': 'application/json' }
            });
            if (res.ok) {
                notify('Migration aborted.', 'info');
                fetchBatches();
            }
        } catch { notify('Failed to abort migration.', 'error'); }
    };

    // Aggregate stats across all batches
    const metrics = batches.reduce((acc, b) => ({
        savedGb:        acc.savedGb + ((b.duplicate_count || 0) * 5 / 1024),
        savingsUsd:     acc.savingsUsd + ((b.duplicate_count || 0) * 5 / 1024 * 0.023),
        totalAssets:    acc.totalAssets + (b.total_count || 0),
        totalCommitted: acc.totalCommitted + (b.committed_count || 0),
    }), { savedGb: 0, savingsUsd: 0, totalAssets: 0, totalCommitted: 0 });

    const getStatusChip = (status) => {
        const cfg = STATUS_CONFIG[status] || STATUS_CONFIG.initializing;
        return <Chip icon={cfg.icon} label={cfg.label} color={cfg.color} size="small" variant="outlined" />;
    };

    if (selectedBatchId) {
        return <BatchReviewWorkspace batchId={selectedBatchId} onBack={() => { setSelectedBatchId(null); fetchBatches(); }} />;
    }

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <Stack direction="row" justifyContent="space-between" alignItems="flex-start" sx={{ mb: 1 }}>
                <Box>
                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>Migration Pipeline</Typography>
                    <Typography variant="body2" color="textSecondary">
                        Monitor, transform, and commit legacy enterprise assets into Capri DAM.
                    </Typography>
                </Box>
                <Tooltip title="Refresh"><IconButton onClick={fetchBatches}><Refresh /></IconButton></Tooltip>
            </Stack>

            {/* ── Metrics ── */}
            <Grid container spacing={3} sx={{ mb: 4, mt: 1 }}>
                {[
                    { label: 'TECHNICAL DEBT PREVENTED', value: `${metrics.savedGb.toFixed(2)} GB`, sub: 'Duplicate uploads blocked at ingestion edge', icon: <Storage sx={{ color: '#137333', fontSize: 32 }} />, color: '#137333' },
                    { label: 'ESTIMATED STORAGE SAVINGS', value: `$${metrics.savingsUsd.toFixed(2)}/mo`, sub: 'Cloud egress and storage overhead reduced', icon: <TrendingDown sx={{ color: '#5e35b1', fontSize: 32 }} />, color: '#5e35b1' },
                    { label: 'TOTAL ASSETS STAGED', value: metrics.totalAssets.toLocaleString(), sub: 'Across all active and completed batches', icon: <Storage sx={{ color: '#0ea5e9', fontSize: 32 }} />, color: '#0ea5e9' },
                    { label: 'COMMITTED TO DAM', value: metrics.totalCommitted.toLocaleString(), sub: 'Successfully migrated and indexed', icon: <CheckCircle sx={{ color: '#16a34a', fontSize: 32 }} />, color: '#16a34a' },
                ].map((m, i) => (
                    <Grid size={{ xs: 12, sm: 6, md: 3 }} key={i}>
                        <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3 }}>
                            <CardContent>
                                <Stack direction="row" justifyContent="space-between" alignItems="center">
                                    <Box>
                                        <Typography color="textSecondary" variant="caption" sx={{ fontWeight: 600 }}>{m.label}</Typography>
                                        <Typography variant="h4" sx={{ fontWeight: 700, mt: 1, color: m.color }}>{m.value}</Typography>
                                    </Box>
                                    {m.icon}
                                </Stack>
                                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1 }}>{m.sub}</Typography>
                            </CardContent>
                        </Card>
                    </Grid>
                ))}
            </Grid>

            {/* ── Migration Considerations Banner ── */}
            <Alert severity="info" sx={{ mb: 3, borderRadius: 2 }}>
                <strong>Migration Phases:</strong> &nbsp;
                <strong>1. Audit & Cleanse</strong> — purge ROT assets before migrating. &nbsp;
                <strong>2. Metadata Normalization</strong> — AI maps legacy tags to canonical schema. &nbsp;
                <strong>3. Human Review</strong> — approve or reject staged batches. &nbsp;
                <strong>4. Commit</strong> — assets are committed and you receive a single summary email.
            </Alert>

            {/* ── Batch Table ── */}
            {loading ? (
                <CircularProgress sx={{ display: 'block', mx: 'auto', mt: 6 }} />
            ) : batches.length === 0 ? (
                <Paper elevation={0} sx={{ p: 6, textAlign: 'center', border: '1px dashed #cbd5e1', borderRadius: 3 }}>
                    <Typography color="textSecondary">No migration batches yet. Start one from the Connectors tab.</Typography>
                </Paper>
            ) : (
                <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3 }}>
                    <Table>
                        <TableHead sx={{ bgcolor: '#f8fafc' }}>
                            <TableRow>
                                <TableCell sx={{ fontWeight: 600 }}>Batch Name</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Source</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Status</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Progress</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Duplicates</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Errors</TableCell>
                                <TableCell align="right" sx={{ fontWeight: 600 }}>Actions</TableCell>
                            </TableRow>
                        </TableHead>
                        <TableBody>
                            {batches.map((batch) => {
                                const progress = batch.total_count > 0
                                    ? ((batch.processed_count / batch.total_count) * 100)
                                    : 0;
                                const isActive = IN_PROGRESS_STATUSES.includes(batch.status);
                                return (
                                    <TableRow key={batch.id} hover>
                                        <TableCell>
                                            <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>{batch.name}</Typography>
                                            <Typography variant="caption" color="textSecondary">{batch.created_at?.slice(0, 10)}</Typography>
                                        </TableCell>
                                        <TableCell>
                                            <Chip label={batch.source_label || batch.source_type?.toUpperCase()} size="small" />
                                        </TableCell>
                                        <TableCell>{getStatusChip(batch.status)}</TableCell>
                                        <TableCell sx={{ width: '20%' }}>
                                            <Stack direction="row" alignItems="center" spacing={1}>
                                                <Box sx={{ width: '100%' }}>
                                                    <LinearProgress
                                                        variant={isActive ? 'indeterminate' : 'determinate'}
                                                        value={progress}
                                                        color={batch.status === 'transforming' ? 'secondary' : batch.status === 'committed' ? 'success' : 'primary'}
                                                    />
                                                </Box>
                                                <Typography variant="caption" color="textSecondary" sx={{ whiteSpace: 'nowrap' }}>
                                                    {batch.processed_count}/{batch.total_count}
                                                </Typography>
                                            </Stack>
                                        </TableCell>
                                        <TableCell>
                                            <Chip label={batch.duplicate_count || 0} size="small" color="warning" variant="outlined" />
                                        </TableCell>
                                        <TableCell>
                                            <Chip label={batch.error_count || 0} size="small" color={batch.error_count > 0 ? 'error' : 'default'} variant="outlined" />
                                        </TableCell>
                                        <TableCell align="right">
                                            <Stack direction="row" spacing={0.5} justifyContent="flex-end">
                                                {batch.status === 'review_needed' && (
                                                    <Button variant="contained" size="small" startIcon={<Visibility />}
                                                        onClick={() => setSelectedBatchId(batch.id)}
                                                        sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none' }}>
                                                        Audit
                                                    </Button>
                                                )}
                                                {batch.status === 'committed' && batch.report_snapshot_id && (
                                                    <Button variant="outlined" size="small"
                                                        onClick={() => setSelectedBatchId(batch.id)}
                                                        sx={{ textTransform: 'none' }}>
                                                        View Report
                                                    </Button>
                                                )}
                                                {(isActive || batch.status === 'review_needed') && (
                                                    <Tooltip title="Abort migration">
                                                        <IconButton size="small" color="error" onClick={() => handleAbort(batch.id)}>
                                                            <PauseCircle fontSize="small" />
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
            )}
        </Box>
    );
}