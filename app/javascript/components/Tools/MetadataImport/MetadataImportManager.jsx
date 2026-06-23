import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Typography, Button, IconButton, Tooltip, Chip, Stack, Paper,
    Table, TableHead, TableRow, TableCell, TableBody, CircularProgress,
    Dialog, DialogTitle, DialogContent, DialogActions, TextField,
    FormControlLabel, Checkbox, RadioGroup, Radio, FormControl, FormLabel,
    Autocomplete, Divider, Link, Alert, Grid
} from '@mui/material';
import {
    UploadFileOutlined, AddOutlined, RefreshOutlined, DeleteOutlined,
    DescriptionOutlined, DownloadOutlined, ScheduleOutlined, InsertDriveFileOutlined,
    CheckCircleOutlined, ErrorOutlined, HourglassEmptyOutlined, FileDownloadOutlined
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';
import { humanFileSize, csrfToken, parseCsvHeader } from '../../../utils/format';

const STATUS_META = {
    pending:    { label: 'Queued',     color: '#f59e0b', icon: <HourglassEmptyOutlined sx={{ fontSize: 16 }} /> },
    processing: { label: 'Processing', color: '#0288d1', icon: <CircularProgress size={14} /> },
    completed:  { label: 'Completed',  color: '#16a34a', icon: <CheckCircleOutlined sx={{ fontSize: 16 }} /> },
    failed:     { label: 'Failed',     color: '#dc2626', icon: <ErrorOutlined sx={{ fontSize: 16 }} /> },
};

function humanSize(bytes) {
    return humanFileSize(bytes);
}

// ── New import dialog ───────────────────────────────────────────────────────────
function ImportDialog({ open, onClose, onCreate }) {
    const notify = useNotify();
    const [file, setFile]                     = useState(null);
    const [headers, setHeaders]               = useState([]);
    const [batchSize, setBatchSize]           = useState(50);
    const [fieldSeparator, setFieldSeparator] = useState(',');
    const [multiDelimiter, setMultiDelimiter] = useState('|');
    const [launchWorkflows, setLaunchWf]      = useState(false);
    const [assetPathColumn, setAssetPathCol]  = useState('asset_path');
    const [ignoredColumns, setIgnoredCols]    = useState([]);
    const [schedule, setSchedule]             = useState('now');
    const [scheduledAt, setScheduledAt]       = useState('');
    const [submitting, setSubmitting]         = useState(false);
    const fileInputRef = useRef(null);

    const reset = () => {
        setFile(null); setHeaders([]); setBatchSize(50); setFieldSeparator(',');
        setMultiDelimiter('|'); setLaunchWf(false); setAssetPathCol('asset_path');
        setIgnoredCols([]); setSchedule('now'); setScheduledAt('');
    };

    // Parse the header row client-side to power the column pickers.
    const handleFile = (selected) => {
        if (!selected) return;
        setFile(selected);
        const reader = new FileReader();
        reader.onload = (e) => {
            const firstLine = String(e.target.result || '').split(/\r?\n/)[0] || '';
            const cols = parseCsvHeader(firstLine, fieldSeparator);
            setHeaders(cols);
            if (cols.length && !cols.includes(assetPathColumn)) {
                setAssetPathCol(cols[0]);
            }
        };
        reader.readAsText(selected.slice(0, 64 * 1024));
    };

    const handleSubmit = async () => {
        if (!file) { notify('Please select a CSV file.', 'warning'); return; }
        const size = parseInt(batchSize, 10);
        if (Number.isNaN(size) || size < 1 || size > 100) {
            notify('Batch size must be between 1 and 100.', 'warning'); return;
        }
        if (schedule === 'later' && !scheduledAt) { notify('Please pick a date & time.', 'warning'); return; }

        const fd = new FormData();
        fd.append('metadata_import[source_file]', file);
        fd.append('metadata_import[name]', file.name);
        fd.append('metadata_import[batch_size]', size);
        fd.append('metadata_import[field_separator]', fieldSeparator || ',');
        fd.append('metadata_import[multi_value_delimiter]', multiDelimiter || '|');
        fd.append('metadata_import[launch_workflows]', launchWorkflows);
        fd.append('metadata_import[asset_path_column]', assetPathColumn || 'asset_path');
        ignoredColumns.forEach(c => fd.append('metadata_import[ignored_columns][]', c));
        if (schedule === 'later') fd.append('metadata_import[scheduled_at]', scheduledAt);

        setSubmitting(true);
        const ok = await onCreate(fd);
        setSubmitting(false);
        if (ok) { reset(); onClose(); }
    };

    const ignorableColumns = headers.filter(h => h !== assetPathColumn);

    return (
        <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
            <DialogTitle sx={{ fontWeight: 700, display: 'flex', alignItems: 'center', gap: 1 }}>
                <UploadFileOutlined sx={{ color: '#5e35b1' }} /> Metadata Import
            </DialogTitle>
            <DialogContent dividers>
                <Stack spacing={2.5} sx={{ mt: 0.5 }}>
                    {/* File select */}
                    <Box>
                        <input ref={fileInputRef} type="file" accept=".csv,text/csv" hidden
                               onChange={e => handleFile(e.target.files?.[0])} />
                        <Button variant="outlined" startIcon={<InsertDriveFileOutlined />}
                                onClick={() => fileInputRef.current?.click()}
                                sx={{ textTransform: 'none', borderColor: '#cbd5e1', color: '#475569' }}>
                            Select File
                        </Button>
                        {file && (
                            <Typography variant="caption" sx={{ ml: 1.5, color: '#16a34a' }}>
                                {file.name} ({humanSize(file.size)})
                            </Typography>
                        )}
                    </Box>

                    {headers.length > 0 && (
                        <Alert severity="info" sx={{ py: 0.5 }}>
                            Detected {headers.length} column{headers.length !== 1 ? 's' : ''} in the header row.
                        </Alert>
                    )}

                    <Grid container spacing={2}>
                        <Grid item xs={6}>
                            <TextField label="Batch size" type="number" size="small" fullWidth
                                value={batchSize} onChange={e => setBatchSize(e.target.value)}
                                inputProps={{ min: 1, max: 100 }} helperText="Default 50, max 100" />
                        </Grid>
                        <Grid item xs={6}>
                            <Autocomplete
                                freeSolo size="small" options={headers} value={assetPathColumn}
                                onInputChange={(_, v) => setAssetPathCol(v)}
                                onChange={(_, v) => setAssetPathCol(v || 'asset_path')}
                                renderInput={(params) => (
                                    <TextField {...params} label="Asset path column" helperText="Default asset_path" />
                                )}
                            />
                        </Grid>
                        <Grid item xs={6}>
                            <TextField label="Field separator" size="small" fullWidth
                                value={fieldSeparator} onChange={e => setFieldSeparator(e.target.value)}
                                inputProps={{ maxLength: 3 }} helperText="Default ," />
                        </Grid>
                        <Grid item xs={6}>
                            <TextField label="Multi-value delimiter" size="small" fullWidth
                                value={multiDelimiter} onChange={e => setMultiDelimiter(e.target.value)}
                                inputProps={{ maxLength: 3 }} helperText="Default |" />
                        </Grid>
                    </Grid>

                    <Autocomplete
                        multiple freeSolo size="small" options={ignorableColumns} value={ignoredColumns}
                        onChange={(_, v) => setIgnoredCols(v)}
                        renderInput={(params) => (
                            <TextField {...params} label="Columns to ignore"
                                placeholder="Add columns to skip"
                                helperText="These columns will not be written to assets." />
                        )}
                    />

                    <FormControlLabel
                        control={<Checkbox checked={launchWorkflows} onChange={e => setLaunchWf(e.target.checked)} />}
                        label={
                            <Box>
                                <Typography variant="body2">Launch workflows</Typography>
                                <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                    Runs the DAM Metadata WriteBack workflow. Slows the system down.
                                </Typography>
                            </Box>
                        }
                    />

                    <Divider />

                    <FormControl>
                        <FormLabel sx={{ fontSize: '0.85rem', fontWeight: 600 }}>When to import</FormLabel>
                        <RadioGroup row value={schedule} onChange={e => setSchedule(e.target.value)}>
                            <FormControlLabel value="now" control={<Radio size="small" />} label="Now" />
                            <FormControlLabel value="later" control={<Radio size="small" />} label="Later" />
                        </RadioGroup>
                    </FormControl>
                    {schedule === 'later' && (
                        <TextField type="datetime-local" label="Scheduled date & time" size="small"
                            InputLabelProps={{ shrink: true }} value={scheduledAt}
                            onChange={e => setScheduledAt(e.target.value)} />
                    )}
                </Stack>
            </DialogContent>
            <DialogActions sx={{ px: 3, py: 2 }}>
                <Button onClick={onClose} sx={{ textTransform: 'none' }}>Cancel</Button>
                <Button variant="contained" onClick={handleSubmit} disabled={submitting}
                    startIcon={submitting ? <CircularProgress size={16} color="inherit" /> : <UploadFileOutlined />}
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none' }}>
                    Import
                </Button>
            </DialogActions>
        </Dialog>
    );
}

// ── Main manager ────────────────────────────────────────────────────────────────
export default function MetadataImportManager() {
    const notify = useNotify();
    const [imports, setImports] = useState([]);
    const [loading, setLoading] = useState(true);
    const [dialogOpen, setDialog] = useState(false);
    const pollRef = useRef(null);

    const fetchImports = useCallback(async () => {
        try {
            const res = await fetch('/api/v1/metadata_imports');
            const data = await res.json();
            setImports(Array.isArray(data) ? data : []);
        } catch {
            notify('Failed to load imports.', 'error');
        } finally {
            setLoading(false);
        }
    }, []); // eslint-disable-line react-hooks/exhaustive-deps

    useEffect(() => { fetchImports(); }, [fetchImports]);

    useEffect(() => {
        const inFlight = imports.some(i => i.status === 'pending' || i.status === 'processing');
        clearInterval(pollRef.current);
        if (inFlight) pollRef.current = setInterval(fetchImports, 4000);
        return () => clearInterval(pollRef.current);
    }, [imports, fetchImports]);

    const handleCreate = async (formData) => {
        try {
            const res = await fetch('/api/v1/metadata_imports', {
                method: 'POST',
                headers: { 'X-CSRF-Token': csrfToken() },
                body: formData,
            });
            const data = await res.json();
            if (!res.ok) { notify(data.errors?.join(', ') || 'Import failed to start.', 'error'); return false; }
            notify('Metadata import started. You will be notified when it is complete.', 'success');
            await fetchImports();
            return true;
        } catch {
            notify('Import failed to start.', 'error');
            return false;
        }
    };

    const handleDelete = async (imp) => {
        if (!window.confirm(`Delete import "${imp.name}" and its files?`)) return;
        const res = await fetch(`/api/v1/metadata_imports/${imp.id}`, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': csrfToken() },
        });
        if (!res.ok) { notify('Delete failed.', 'error'); return; }
        notify('Import deleted.', 'success');
        await fetchImports();
    };

    return (
        <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', bgcolor: '#f8fafc' }}>
            {/* Top bar */}
            <Box sx={{ px: 3, py: 2, bgcolor: '#fff', borderBottom: '1px solid #e2e8f0',
                       display: 'flex', alignItems: 'center', gap: 2 }}>
                <UploadFileOutlined sx={{ color: '#5e35b1', fontSize: 24 }} />
                <Box sx={{ flex: 1 }}>
                    <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b', lineHeight: 1.2 }}>
                        Metadata Import
                    </Typography>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        Tools › Assets › Metadata Import
                    </Typography>
                </Box>
                <Tooltip title="Refresh">
                    <IconButton size="small" onClick={fetchImports} sx={{ border: '1px solid #e2e8f0' }}>
                        <RefreshOutlined fontSize="small" />
                    </IconButton>
                </Tooltip>
                <Button variant="contained" startIcon={<AddOutlined />} onClick={() => setDialog(true)}
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none' }}>
                    New Import
                </Button>
            </Box>

            {/* Body */}
            <Box sx={{ flex: 1, overflow: 'auto', p: 3 }}>
                {/* Template helper */}
                <Paper variant="outlined" sx={{ p: 2, mb: 3, borderRadius: 2, bgcolor: '#faf5ff',
                                                display: 'flex', alignItems: 'center', gap: 2 }}>
                    <DownloadOutlined sx={{ color: '#5e35b1' }} />
                    <Box sx={{ flex: 1 }}>
                        <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#5e35b1' }}>
                            Start with the template
                        </Typography>
                        <Typography variant="caption" sx={{ color: '#64748b' }}>
                            Download the fixed-column starter CSV (asset_path + standard metadata). The first column
                            is the asset's absolute DAM path; leave a cell empty to skip that property.
                        </Typography>
                    </Box>
                    <Button variant="outlined" size="small" startIcon={<FileDownloadOutlined />}
                        href="/api/v1/metadata_imports/template"
                        sx={{ textTransform: 'none', borderColor: '#5e35b1', color: '#5e35b1' }}>
                        Download template
                    </Button>
                </Paper>

                <Paper variant="outlined" sx={{ borderRadius: 2, overflow: 'hidden' }}>
                    <Box sx={{ px: 2, py: 1.5, bgcolor: '#faf5ff', borderBottom: '1px solid #f1f5f9' }}>
                        <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#5e35b1' }}>
                            Import history
                        </Typography>
                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                            Source and results files are available for 30 days, then automatically removed.
                        </Typography>
                    </Box>

                    {loading ? (
                        <Box sx={{ display: 'flex', justifyContent: 'center', p: 5 }}>
                            <CircularProgress size={28} sx={{ color: '#5e35b1' }} />
                        </Box>
                    ) : imports.length === 0 ? (
                        <Box sx={{ p: 5, textAlign: 'center', color: '#94a3b8' }}>
                            <DescriptionOutlined sx={{ fontSize: 48, opacity: 0.3 }} />
                            <Typography variant="body2" sx={{ mt: 1 }}>
                                No imports yet. Click “New Import” to upload a metadata CSV.
                            </Typography>
                        </Box>
                    ) : (
                        <Table size="small">
                            <TableHead>
                                <TableRow sx={{ '& th': { fontWeight: 700, color: '#475569', bgcolor: '#fff' } }}>
                                    <TableCell>File</TableCell>
                                    <TableCell>Status</TableCell>
                                    <TableCell>Results</TableCell>
                                    <TableCell>Created by</TableCell>
                                    <TableCell>Date</TableCell>
                                    <TableCell>Expires</TableCell>
                                    <TableCell align="right">Files</TableCell>
                                    <TableCell align="right"></TableCell>
                                </TableRow>
                            </TableHead>
                            <TableBody>
                                {imports.map(imp => {
                                    const meta = STATUS_META[imp.status] || STATUS_META.pending;
                                    return (
                                        <TableRow key={imp.id} hover>
                                            <TableCell>
                                                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                                    <DescriptionOutlined sx={{ fontSize: 18, color: '#5e35b1' }} />
                                                    <Box>
                                                        <Typography variant="body2" fontWeight={600}>{imp.name}</Typography>
                                                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                                            batch {imp.batch_size} · sep “{imp.field_separator}” · path “{imp.asset_path_column}”
                                                            {imp.launch_workflows ? ' · workflows' : ''}
                                                        </Typography>
                                                        {imp.scheduled_at && imp.status === 'pending' && (
                                                            <Typography variant="caption" sx={{ color: '#94a3b8', display: 'flex', alignItems: 'center', gap: 0.5 }}>
                                                                <ScheduleOutlined sx={{ fontSize: 12 }} /> {imp.scheduled_at}
                                                            </Typography>
                                                        )}
                                                        {imp.status === 'failed' && imp.error_message && (
                                                            <Typography variant="caption" sx={{ color: '#dc2626' }}>{imp.error_message}</Typography>
                                                        )}
                                                    </Box>
                                                </Box>
                                            </TableCell>
                                            <TableCell>
                                                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, color: meta.color }}>
                                                    {meta.icon}
                                                    <Typography variant="body2" fontWeight={600} sx={{ color: meta.color }}>
                                                        {meta.label}
                                                    </Typography>
                                                </Box>
                                            </TableCell>
                                            <TableCell>
                                                {imp.status === 'completed' ? (
                                                    <Stack direction="row" spacing={0.5}>
                                                        <Chip label={`${imp.success_count} ok`} size="small"
                                                              sx={{ height: 20, fontSize: '0.7rem', bgcolor: '#dcfce7', color: '#166534' }} />
                                                        {imp.failure_count > 0 && (
                                                            <Chip label={`${imp.failure_count} fail`} size="small"
                                                                  sx={{ height: 20, fontSize: '0.7rem', bgcolor: '#fee2e2', color: '#991b1b' }} />
                                                        )}
                                                    </Stack>
                                                ) : (
                                                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>—</Typography>
                                                )}
                                            </TableCell>
                                            <TableCell>
                                                <Typography variant="body2" sx={{ color: '#475569' }}>{imp.created_by}</Typography>
                                            </TableCell>
                                            <TableCell>
                                                <Typography variant="caption" sx={{ color: '#64748b' }}>{imp.created_at}</Typography>
                                            </TableCell>
                                            <TableCell>
                                                <Typography variant="caption" sx={{ color: '#64748b' }}>{imp.expires_at || '—'}</Typography>
                                            </TableCell>
                                            <TableCell align="right">
                                                <Stack direction="row" spacing={1} justifyContent="flex-end">
                                                    {imp.source_file && (
                                                        <Link href={imp.source_file.download_url} underline="hover"
                                                              sx={{ fontSize: '0.8rem', color: '#5e35b1', display: 'flex', alignItems: 'center', gap: 0.3 }}>
                                                            <FileDownloadOutlined sx={{ fontSize: 15 }} /> Input
                                                        </Link>
                                                    )}
                                                    {imp.result_file && (
                                                        <Link href={imp.result_file.download_url} underline="hover"
                                                              sx={{ fontSize: '0.8rem', color: '#16a34a', display: 'flex', alignItems: 'center', gap: 0.3 }}>
                                                            <FileDownloadOutlined sx={{ fontSize: 15 }} /> Results
                                                        </Link>
                                                    )}
                                                </Stack>
                                            </TableCell>
                                            <TableCell align="right">
                                                <Tooltip title="Delete">
                                                    <IconButton size="small" onClick={() => handleDelete(imp)} sx={{ color: '#ef4444' }}>
                                                        <DeleteOutlined fontSize="small" />
                                                    </IconButton>
                                                </Tooltip>
                                            </TableCell>
                                        </TableRow>
                                    );
                                })}
                            </TableBody>
                        </Table>
                    )}
                </Paper>
            </Box>

            <ImportDialog open={dialogOpen} onClose={() => setDialog(false)} onCreate={handleCreate} />
        </Box>
    );
}

