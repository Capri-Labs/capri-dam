import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Typography, Paper, Button, Chip, IconButton, Tooltip,
    Table, TableBody, TableCell, TableContainer, TableHead, TableRow,
    CircularProgress, Alert, Stack, TextField, MenuItem, Select,
    FormControl, InputLabel
} from '@mui/material';
import {
    Download, Refresh, FilterList, PictureAsPdf, TableChart,
    FormatAlignLeft, CheckCircle, HourglassEmpty, Error as ErrorIcon, Loop
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

const STATUS_CONFIG = {
    completed:  { color: 'success', icon: <CheckCircle fontSize="small" />,    label: 'Ready' },
    processing: { color: 'info',    icon: <Loop fontSize="small" />,           label: 'Generating' },
    pending:    { color: 'default', icon: <HourglassEmpty fontSize="small" />, label: 'Queued' },
    failed:     { color: 'error',   icon: <ErrorIcon fontSize="small" />,      label: 'Failed' },
};

const FORMAT_ICONS = {
    PDF:  <PictureAsPdf sx={{ fontSize: 16, color: '#ef4444' }} />,
    XLSX: <TableChart sx={{ fontSize: 16, color: '#16a34a' }} />,
    CSV:  <FormatAlignLeft sx={{ fontSize: 16, color: '#0ea5e9' }} />,
};

// Auto-poll while any snapshot is in progress
const POLL_INTERVAL = 8000;

export default function DownloadCenter({ refreshTrigger }) {
    const notify = useNotify();
    const [snapshots, setSnapshots]   = useState([]);
    const [loading, setLoading]       = useState(true);
    const [statusFilter, setStatusFilter] = useState('');
    const [searchQuery, setSearchQuery]  = useState('');
    const pollRef = useRef(null);

    const fetchSnapshots = useCallback(async () => {
        try {
            const res  = await fetch('/admin/report_snapshots.json', { headers: { Accept: 'application/json' } });
            if (!res.ok) return;
            const data = await res.json();
            setSnapshots(data.snapshots || []);
        } catch {
            notify('Failed to refresh export history.', 'error');
        } finally {
            setLoading(false);
        }
    }, [notify]);

    useEffect(() => { fetchSnapshots(); }, [refreshTrigger, fetchSnapshots]);

    // Poll while any snapshot is processing/pending
    useEffect(() => {
        const hasActive = snapshots.some(s => ['processing', 'pending'].includes(s.status));
        clearInterval(pollRef.current);
        if (hasActive) {
            pollRef.current = setInterval(fetchSnapshots, POLL_INTERVAL);
        }
        return () => clearInterval(pollRef.current);
    }, [snapshots, fetchSnapshots]);

    const filtered = snapshots.filter(s => {
        if (statusFilter && s.status !== statusFilter) return false;
        if (searchQuery && !s.report_name?.toLowerCase().includes(searchQuery.toLowerCase())) return false;
        return true;
    });

    return (
        <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, overflow: 'hidden' }}>
            {/* Header */}
            <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ px: 2.5, py: 2, borderBottom: '1px solid #f1f5f9' }}>
                <Box>
                    <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>Download Center</Typography>
                    <Typography variant="caption" color="textSecondary">
                        {filtered.length} export{filtered.length !== 1 ? 's' : ''} · auto-refreshes every 8s while jobs are running
                    </Typography>
                </Box>
                <Stack direction="row" spacing={1} alignItems="center">
                    {/* Filter bar */}
                    <TextField size="small" placeholder="Search reports…" value={searchQuery}
                        onChange={(e) => setSearchQuery(e.target.value)}
                        sx={{ width: 180, bgcolor: 'white' }}
                        InputProps={{ startAdornment: <FilterList sx={{ mr: 0.5, color: '#94a3b8', fontSize: 18 }} /> }} />

                    <FormControl size="small" sx={{ minWidth: 110, bgcolor: 'white' }}>
                        <Select value={statusFilter} displayEmpty
                            onChange={(e) => setStatusFilter(e.target.value)}>
                            <MenuItem value="">All statuses</MenuItem>
                            <MenuItem value="completed">Ready</MenuItem>
                            <MenuItem value="processing">Generating</MenuItem>
                            <MenuItem value="pending">Queued</MenuItem>
                            <MenuItem value="failed">Failed</MenuItem>
                        </Select>
                    </FormControl>

                    <Tooltip title="Refresh">
                        <IconButton size="small" onClick={fetchSnapshots}>
                            <Refresh fontSize="small" />
                        </IconButton>
                    </Tooltip>
                </Stack>
            </Stack>

            {/* Table */}
            {loading ? (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
                    <CircularProgress size={28} />
                </Box>
            ) : filtered.length === 0 ? (
                <Box sx={{ py: 6, textAlign: 'center' }}>
                    <Typography color="textSecondary" variant="body2">
                        {statusFilter || searchQuery ? 'No exports match your filter.' : 'No exports yet. Create one above.'}
                    </Typography>
                </Box>
            ) : (
                <TableContainer>
                    <Table size="small">
                        <TableHead sx={{ bgcolor: '#f8fafc' }}>
                            <TableRow>
                                <TableCell sx={{ fontWeight: 600, pl: 2.5 }}>Report Name</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Format</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Status</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Requested</TableCell>
                                <TableCell sx={{ fontWeight: 600 }} align="right">Action</TableCell>
                            </TableRow>
                        </TableHead>
                        <TableBody>
                            {filtered.map((snap) => {
                                const cfg = STATUS_CONFIG[snap.status] || STATUS_CONFIG.pending;
                                return (
                                    <TableRow key={snap.id} hover sx={{ '&:last-child td': { border: 0 } }}>
                                        <TableCell sx={{ pl: 2.5 }}>
                                            <Typography variant="body2" sx={{ fontWeight: 600 }}>{snap.report_name}</Typography>
                                        </TableCell>
                                        <TableCell>
                                            <Stack direction="row" alignItems="center" spacing={0.5}>
                                                {FORMAT_ICONS[snap.format] || null}
                                                <Typography variant="caption" sx={{ fontWeight: 600 }}>{snap.format}</Typography>
                                            </Stack>
                                        </TableCell>
                                        <TableCell>
                                            <Tooltip title={snap.status === 'failed' ? snap.error_message || 'Unknown error' : ''}>
                                                <Chip
                                                    icon={cfg.icon}
                                                    label={cfg.label}
                                                    color={cfg.color}
                                                    size="small"
                                                    variant="outlined"
                                                />
                                            </Tooltip>
                                        </TableCell>
                                        <TableCell>
                                            <Typography variant="caption" color="textSecondary">{snap.created_at}</Typography>
                                        </TableCell>
                                        <TableCell align="right" sx={{ pr: 2 }}>
                                            {snap.status === 'completed' && snap.download_url ? (
                                                <Button variant="outlined" size="small" startIcon={<Download />}
                                                    href={snap.download_url} download
                                                    sx={{ textTransform: 'none', borderRadius: 2 }}>
                                                    Download
                                                </Button>
                                            ) : snap.status === 'processing' ? (
                                                <CircularProgress size={16} />
                                            ) : null}
                                        </TableCell>
                                    </TableRow>
                                );
                            })}
                        </TableBody>
                    </Table>
                </TableContainer>
            )}
        </Paper>
    );
}

