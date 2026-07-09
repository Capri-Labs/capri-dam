import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, Paper, Typography, Button, Stack, Divider, Grid,
    List, ListItem, ListItemText, ListItemIcon, Card,
    CardContent, Chip, CircularProgress, Alert, LinearProgress,
    TextField, MenuItem, Tooltip, IconButton
} from '@mui/material';
import {
    ArrowBack, CheckCircle, Block, ErrorOutlined, AutoAwesome,
    FilterList, Refresh, BarChart, Sync
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

const ITEM_STATUS_CONFIG = {
    pending:           { icon: <CircularProgress size={14} />, color: 'default',   label: 'Pending AI' },
    ai_processing:     { icon: <AutoAwesome fontSize="small" sx={{ color: '#8b5cf6' }} />, color: 'secondary', label: 'AI Processing' },
    ready_for_import:  { icon: <CheckCircle fontSize="small" sx={{ color: '#16a34a' }} />, color: 'success',   label: 'Ready' },
    flagged_duplicate: { icon: <Block fontSize="small" sx={{ color: '#dc2626' }} />, color: 'error',     label: 'Duplicate' },
    flagged_error:     { icon: <ErrorOutlined fontSize="small" sx={{ color: '#d97706' }} />, color: 'warning',  label: 'Error' },
    committed:         { icon: <CheckCircle fontSize="small" sx={{ color: '#0ea5e9' }} />, color: 'info',      label: 'Committed' },
    rejected:          { icon: <Block fontSize="small" sx={{ color: '#6b7280' }} />, color: 'default',   label: 'Rejected' },
};

export default function BatchReviewWorkspace({ batchId, onBack }) {
    const notify = useNotify();
    const [batch, setBatch]         = useState(null);
    const [items, setItems]         = useState([]);
    const [meta, setMeta]           = useState({});
    const [selectedItem, setSelectedItem] = useState(null);
    const [loading, setLoading]     = useState(true);
    const [committing, setCommitting] = useState(false);
    const [statusFilter, setStatusFilter] = useState('');
    const [page, setPage]           = useState(1);
    const [report, setReport]       = useState(null);

    const fetchData = useCallback(async () => {
        try {
            const url = `/api/v1/ingestion_batches/${batchId}?page=${page}${statusFilter ? `&status=${statusFilter}` : ''}`;
            const res = await fetch(url);
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const data = await res.json();
            setBatch(data.batch);
            setItems(data.items || []);
            setMeta(data.meta || {});
            if (!selectedItem && data.items?.length > 0) setSelectedItem(data.items[0]);
        } catch (e) {
            notify(`Failed to load batch: ${e.message}`, 'error');
        } finally {
            setLoading(false);
        }
    }, [batchId, page, statusFilter, notify]);

    const fetchReport = useCallback(async () => {
        try {
            const res = await fetch(`/api/v1/ingestion_batches/${batchId}/report`);
            if (res.ok) {
                const data = await res.json();
                if (data.report && Object.keys(data.report).length > 0) setReport(data.report);
            }
        } catch { /* non-fatal */ }
    }, [batchId]);

    useEffect(() => { fetchData(); }, [fetchData]);

    useEffect(() => {
        if (batch?.status === 'committed') fetchReport();
    }, [batch?.status, fetchReport]);

    const handleCommit = async () => {
        if (!window.confirm('Approve and commit this batch to the live DAM? This will create Asset records for all ready items.')) return;
        setCommitting(true);
        try {
            const csrf = document.querySelector('[name="csrf-token"]').content;
            const res  = await fetch(`/api/v1/ingestion_batches/${batchId}/commit`, {
                method: 'POST',
                headers: { 'X-CSRF-Token': csrf, 'Content-Type': 'application/json' }
            });
            const data = await res.json();
            if (res.ok) {
                notify('✅ Commit pipeline started! You will receive an email summary when complete.', 'success');
                fetchData();
            } else {
                notify(data.error || 'Commit failed.', 'error');
            }
        } catch { notify('Network error during commit.', 'error'); }
        finally { setCommitting(false); }
    };

    const handleAbort = async () => {
        if (!window.confirm('Abort this migration batch? All staged data will be discarded.')) return;
        try {
            const csrf = document.querySelector('[name="csrf-token"]').content;
            await fetch(`/api/v1/ingestion_batches/${batchId}/abort`, {
                method: 'POST', headers: { 'X-CSRF-Token': csrf }
            });
            notify('Migration aborted.', 'info');
            onBack();
        } catch { notify('Failed to abort.', 'error'); }
    };

    if (loading) return <Box sx={{ display: 'flex', justifyContent: 'center', mt: 10 }}><CircularProgress /></Box>;
    if (!batch)  return <Alert severity="error" sx={{ m: 4 }}>Batch not found.</Alert>;

    const isReadyToCommit = batch.status === 'review_needed';
    const isCommitted     = batch.status === 'committed';

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            {/* ── Toolbar ── */}
            <Paper elevation={0} sx={{ p: 2, mb: 3, borderRadius: 2, border: '1px solid #e3e8ef' }}>
                <Stack direction="row" sx={{ alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap' }} gap={1}>
                    <Stack direction="row" spacing={1} sx={{
  alignItems: "center"
}}>
                        <Button startIcon={<ArrowBack />} onClick={onBack} color="inherit" sx={{ textTransform: 'none' }}>Back</Button>
                        <Divider orientation="vertical" flexItem />
                        <Box>
                            <Typography variant="h6" sx={{ fontWeight: 600 }}>{batch.name}</Typography>
                            <Typography variant="caption" color="textSecondary">
                                Source: {batch.source_label} &nbsp;·&nbsp;
                                {batch.total_count} total &nbsp;·&nbsp;
                                {batch.duplicate_count} duplicates blocked &nbsp;·&nbsp;
                                {batch.error_count} errors
                            </Typography>
                        </Box>
                    </Stack>
                    <Stack direction="row" spacing={1}>
                        <Tooltip title="Refresh"><IconButton onClick={fetchData} size="small"><Refresh /></IconButton></Tooltip>
                        {isReadyToCommit && (
                            <>
                                <Button variant="outlined" color="error" size="small" onClick={handleAbort} sx={{ textTransform: 'none' }}>
                                    Abort Migration
                                </Button>
                                <Button variant="contained" color="success" startIcon={committing ? <CircularProgress size={16} color="inherit" /> : <CheckCircle />}
                                    onClick={handleCommit} disabled={committing} sx={{ textTransform: 'none' }}>
                                    {committing ? 'Committing…' : 'Approve & Commit Batch'}
                                </Button>
                            </>
                        )}
                        {isCommitted && (
                            <Chip label="✅ Committed to DAM" color="success" variant="outlined" />
                        )}
                    </Stack>
                </Stack>

                {/* Progress bar */}
                <Box sx={{ mt: 2 }}>
                    <LinearProgress
                        variant="determinate"
                        value={batch.progress_pct || 0}
                        color={isCommitted ? 'success' : 'secondary'}
                        sx={{ height: 6, borderRadius: 3 }}
                    />
                    <Typography variant="caption" color="textSecondary" sx={{ mt: 0.5, display: 'block' }}>
                        {batch.processed_count}/{batch.total_count} processed · {batch.progress_pct?.toFixed(1)}% complete
                    </Typography>
                </Box>
            </Paper>

            {/* ── Migration Report (shown after commit) ── */}
            {isCommitted && report && (
                <Paper elevation={0} sx={{ p: 3, mb: 3, border: '1px solid #bbf7d0', bgcolor: '#f0fdf4', borderRadius: 3 }}>
                    <Stack direction="row" spacing={1} sx={{
  mb: 2,
  alignItems: "center"
}}>
                        <BarChart sx={{ color: '#15803d' }} />
                        <Typography variant="h6" sx={{ fontWeight: 700, color: '#15803d' }}>Migration Report</Typography>
                    </Stack>
                    <Grid container spacing={2}>
                        {[
                            { label: 'Committed', value: report.committed, color: '#15803d' },
                            { label: 'Duplicates Blocked', value: report.duplicates_blocked, color: '#d97706' },
                            { label: 'Errors', value: report.errors, color: '#dc2626' },
                            { label: 'AI Enriched', value: report.ai_enriched, color: '#7c3aed' },
                            { label: 'Storage Saved', value: `${report.duplicate_storage_saved_gb} GB`, color: '#0ea5e9' },
                            { label: 'Est. Cost Savings', value: `$${report.estimated_cost_savings_usd}/mo`, color: '#0ea5e9' },
                        ].map((stat, i) => (
                            <Grid size={{ xs: 6, sm: 4, md: 2 }} key={i}>
                                <Box sx={{ textAlign: 'center' }}>
                                    <Typography variant="h5" sx={{ fontWeight: 700, color: stat.color }}>{stat.value}</Typography>
                                    <Typography variant="caption" color="textSecondary">{stat.label}</Typography>
                                </Box>
                            </Grid>
                        ))}
                    </Grid>
                    {report.top_errors?.length > 0 && (
                        <Box sx={{ mt: 2 }}>
                            <Typography variant="caption" sx={{ fontWeight: 700 }}>Top Errors:</Typography>
                            {report.top_errors.map(([filename, err], i) => (
                                <Typography key={i} variant="caption" color="error" sx={{ display: 'block', ml: 1 }}>
                                    · {filename}: {err}
                                </Typography>
                            ))}
                        </Box>
                    )}
                </Paper>
            )}

            <Grid container spacing={3}>
                {/* ── Item Queue (left panel) ── */}
                <Grid size={{ xs: 12, md: 4 }}>
                    <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3 }}>
                        {/* Filter bar */}
                        <Box sx={{ p: 1.5, borderBottom: '1px solid #f1f5f9' }}>
                            <TextField select size="small" fullWidth value={statusFilter}
                                onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
                                label="Filter by status" slotProps={{ input: { startAdornment: <FilterList fontSize="small" sx={{ mr: 0.5, color: '#94a3b8' }} /> } }}>
                                <MenuItem value="">All Items ({meta.total || 0})</MenuItem>
                                {Object.entries(ITEM_STATUS_CONFIG).map(([k, v]) => (
                                    <MenuItem key={k} value={k}>{v.label}</MenuItem>
                                ))}
                            </TextField>
                        </Box>

                        <List sx={{ p: 0, maxHeight: '65vh', overflowY: 'auto' }}>
                            {items.map((item) => {
                                const cfg = ITEM_STATUS_CONFIG[item.status] || ITEM_STATUS_CONFIG.pending;
                                return (
                                    <ListItem key={item.id} component="div"
                                        selected={selectedItem?.id === item.id}
                                        onClick={() => setSelectedItem(item)}
                                        sx={{ borderBottom: '1px solid #f1f5f9', p: 1.5, cursor: 'pointer',
                                              '&.Mui-selected': { bgcolor: '#f0f9ff' } }}>
                                        <ListItemIcon sx={{ minWidth: 32 }}>{cfg.icon}</ListItemIcon>
                                        <ListItemText
                                            primary={item.original_filename?.split('/').pop() || item.original_filename}
                                            secondary={`${item.file_size ? `${(item.file_size / 1024 / 1024).toFixed(1)} MB · ` : ''}${cfg.label}`}
                                                            slotProps={{
                                                              primary:   { noWrap: true, variant: 'subtitle2', fontWeight: 600, component: 'span' },
                                                              secondary: { noWrap: true, component: 'span' },
                                                            }}
                                        />
                                    </ListItem>
                                );
                            })}
                            {/* Pagination */}
                            {meta.total > meta.per_page && (
                                <Box sx={{ p: 1.5, textAlign: 'center', borderTop: '1px solid #f1f5f9' }}>
                                    <Stack direction="row" spacing={1} sx={{
  justifyContent: "center"
}}>
                                        <Button size="small" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>← Prev</Button>
                                        <Typography variant="caption" sx={{ alignSelf: 'center' }}>{page} / {Math.ceil(meta.total / meta.per_page)}</Typography>
                                        <Button size="small" disabled={page >= Math.ceil(meta.total / meta.per_page)} onClick={() => setPage(p => p + 1)}>Next →</Button>
                                    </Stack>
                                </Box>
                            )}
                        </List>
                    </Paper>
                </Grid>

                {/* ── Detail Panel (right) ── */}
                <Grid size={{ xs: 12, md: 8 }}>
                    {selectedItem ? (
                        <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 3, minHeight: '70vh' }}>
                            <Typography variant="h6" sx={{ fontWeight: 600, mb: 0.5, wordBreak: 'break-all' }}>
                                {selectedItem.original_filename}
                            </Typography>
                            <Stack direction="row" spacing={1} sx={{ mb: 2, flexWrap: 'wrap' }}>
                                <Chip label={ITEM_STATUS_CONFIG[selectedItem.status]?.label || selectedItem.status}
                                    color={ITEM_STATUS_CONFIG[selectedItem.status]?.color || 'default'} size="small" />
                                {selectedItem.file_hash && (
                                    <Chip label={`SHA256: ${selectedItem.file_hash?.slice(0, 12)}…`} size="small" variant="outlined" />
                                )}
                                {selectedItem.file_size && (
                                    <Chip label={`${(selectedItem.file_size / 1024 / 1024).toFixed(2)} MB`} size="small" variant="outlined" />
                                )}
                            </Stack>

                            {selectedItem.status === 'flagged_duplicate' ? (
                                <Card elevation={0} sx={{ bgcolor: '#fdf2f2', border: '1px solid #fde2e2', mt: 2 }}>
                                    <CardContent>
                                        <Stack direction="row" spacing={2} sx={{
  alignItems: "flex-start"
}}>
                                            <Block color="error" />
                                            <Box>
                                                <Typography variant="subtitle2" color="error" sx={{ fontWeight: 600 }}>Deduplication Interception</Typography>
                                                <Typography variant="body2" color="textSecondary">
                                                    This asset's SHA-256 checksum exactly matches an asset already in the live DAM.
                                                    It will be <strong>dropped on commit</strong>, preventing storage debt.
                                                </Typography>
                                            </Box>
                                        </Stack>
                                    </CardContent>
                                </Card>
                            ) : selectedItem.status === 'flagged_error' ? (
                                <Alert severity="error" sx={{ mt: 2, borderRadius: 2 }}>
                                    <strong>Processing Error:</strong> {selectedItem.error_log || 'Unknown error.'}
                                </Alert>
                            ) : (
                                <Grid container spacing={2}>
                                    {/* Raw Legacy Metadata */}
                                    <Grid size={{ xs: 12, sm: 6 }}>
                                        <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1.5, color: '#64748b' }}>
                                            Raw Legacy Attributes
                                        </Typography>
                                        <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0', fontFamily: 'monospace', fontSize: '0.75rem', maxHeight: 300, overflowY: 'auto' }}>
                                            <pre style={{ margin: 0 }}>{JSON.stringify(selectedItem.legacy_metadata, null, 2)}</pre>
                                        </Box>
                                    </Grid>
                                    {/* AI Normalized Schema */}
                                    <Grid size={{ xs: 12, sm: 6 }}>
                                        <Stack direction="row" spacing={1} sx={{
  mb: 1.5,
  alignItems: "center"
}}>
                                            <AutoAwesome sx={{ color: '#8e24aa', fontSize: 18 }} />
                                            <Typography variant="subtitle2" sx={{ fontWeight: 600, color: '#8e24aa' }}>AI Normalized Schema</Typography>
                                        </Stack>
                                        {selectedItem.clean_properties && Object.keys(selectedItem.clean_properties).length > 0 ? (
                                            <Box sx={{ p: 2, bgcolor: '#faf5ff', borderRadius: 2, border: '1px solid #f3e8ff', maxHeight: 300, overflowY: 'auto' }}>
                                                {Object.entries(selectedItem.clean_properties).map(([k, v]) => (
                                                    <Box key={k} sx={{ mb: 1.5 }}>
                                                        <Typography variant="caption" color="textSecondary" sx={{ textTransform: 'uppercase', fontSize: '0.65rem', letterSpacing: '0.05em' }}>{k}</Typography>
                                                        <Typography variant="body2" sx={{ fontWeight: 600 }}>
                                                            {Array.isArray(v) ? v.join(', ') : String(v || '—')}
                                                        </Typography>
                                                    </Box>
                                                ))}
                                            </Box>
                                        ) : (
                                            <Alert severity="warning" sx={{ borderRadius: 2 }}>
                                                AI normalization pending or unavailable for this item.
                                            </Alert>
                                        )}
                                    </Grid>
                                    {/* Metadata — full per-asset metadata migrated from the source system's
                                        dedicated metadata endpoint (e.g. AEM's jcr:content/metadata.json),
                                        distinct from the "Raw Legacy Attributes" listing-time properties above. */}
                                    <Grid size={{ xs: 12 }}>
                                        <Stack direction="row" spacing={1} sx={{
  mb: 1.5,
  alignItems: "center"
}}>
                                            <Sync sx={{ color: '#0ea5e9', fontSize: 18 }} />
                                            <Typography variant="subtitle2" sx={{ fontWeight: 600, color: '#0ea5e9' }}>Metadata</Typography>
                                            <Typography variant="caption" color="textSecondary">
                                                — full per-asset metadata fetched from the source system (e.g. jcr:content/metadata.json)
                                            </Typography>
                                        </Stack>
                                        {selectedItem.full_metadata && Object.keys(selectedItem.full_metadata).length > 0 ? (
                                            <Box sx={{ p: 2, bgcolor: '#f0f9ff', borderRadius: 2, border: '1px solid #e0f2fe', fontFamily: 'monospace', fontSize: '0.75rem', maxHeight: 300, overflowY: 'auto' }}>
                                                <pre style={{ margin: 0 }}>{JSON.stringify(selectedItem.full_metadata, null, 2)}</pre>
                                            </Box>
                                        ) : (
                                            <Alert severity="info" sx={{ borderRadius: 2 }}>
                                                No full metadata was migrated for this item — "Migrate Metadata" was disabled for this batch, or the source system's per-asset metadata endpoint returned nothing.
                                            </Alert>
                                        )}
                                    </Grid>
                                </Grid>
                            )}
                        </Paper>
                    ) : (
                        <Paper elevation={0} sx={{ border: '1px dashed #cbd5e1', borderRadius: 3, height: '70vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                            <Typography color="textSecondary">Select an asset to inspect its payload.</Typography>
                        </Paper>
                    )}
                </Grid>
            </Grid>
        </Box>
    );
}

