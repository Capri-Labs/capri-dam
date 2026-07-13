import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box,
    Typography,
    Button,
    IconButton,
    Tooltip,
    Chip,
    Stack,
    Paper,
    Table,
    TableHead,
    TableRow,
    TableCell,
    TableBody,
    CircularProgress,
    Dialog,
    DialogTitle,
    DialogContent,
    DialogActions,
    TextField,
    FormControlLabel,
    Checkbox,
    RadioGroup,
    Radio,
    FormControl,
    FormLabel,
    Autocomplete,
    Divider,
    Link,
    Alert,
    Grid,
    TablePagination,
} from '@mui/material';
import {
    UploadFileOutlined,
    AddOutlined,
    RefreshOutlined,
    DeleteOutlined,
    DescriptionOutlined,
    DownloadOutlined,
    ScheduleOutlined,
    InsertDriveFileOutlined,
    CheckCircleOutlined,
    ErrorOutlined,
    HourglassEmptyOutlined,
    FileDownloadOutlined,
    PreviewOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';
import { humanFileSize, csrfToken, parseCsvHeader } from '../../../utils/format';

const STATUS_META = {
    pending:    { label: 'Queued', color: '#f59e0b', icon: <HourglassEmptyOutlined sx={{ fontSize: 16 }} /> },
    processing: { label: 'Processing', color: '#0288d1', icon: <CircularProgress size={14} /> },
    completed:  { label: 'Completed', color: '#16a34a', icon: <CheckCircleOutlined sx={{ fontSize: 16 }} /> },
    failed:     { label: 'Failed', color: '#dc2626', icon: <ErrorOutlined sx={{ fontSize: 16 }} /> },
};

function humanSize(bytes) {
    return humanFileSize(bytes);
}

function formatPreviewValue(value) {
    if (Array.isArray(value)) return value.join(', ');
    if (value === null || value === undefined || value === '') return '—';
    if (typeof value === 'object') return JSON.stringify(value);
    return String(value);
}

// ── New import dialog ───────────────────────────────────────────────────────────
function ImportDialog({ open, onClose, onCreate, onPreview }) {
    const notify = useNotify();
    const { t } = useTranslation();
    const [file, setFile] = useState(null);
    const [headers, setHeaders] = useState([]);
    const [batchSize, setBatchSize] = useState(50);
    const [fieldSeparator, setFieldSeparator] = useState(',');
    const [multiDelimiter, setMultiDelimiter] = useState('|');
    const [launchWorkflows, setLaunchWf] = useState(false);
    const [assetPathColumn, setAssetPathCol] = useState('asset_path');
    const [ignoredColumns, setIgnoredCols] = useState([]);
    const [schedule, setSchedule] = useState('now');
    const [scheduledAt, setScheduledAt] = useState('');
    const [submitting, setSubmitting] = useState(false);
    const [previewing, setPreviewing] = useState(false);
    const [preview, setPreview] = useState(null);
    const fileInputRef = useRef(null);

    const reset = useCallback(() => {
        setFile(null);
        setHeaders([]);
        setBatchSize(50);
        setFieldSeparator(',');
        setMultiDelimiter('|');
        setLaunchWf(false);
        setAssetPathCol('asset_path');
        setIgnoredCols([]);
        setSchedule('now');
        setScheduledAt('');
        setPreview(null);
        setPreviewing(false);
        setSubmitting(false);
    }, []);

    useEffect(() => {
        setPreview(null);
    }, [file, batchSize, fieldSeparator, multiDelimiter, launchWorkflows, assetPathColumn, schedule, scheduledAt, ignoredColumns]);

    const handleDialogClose = () => {
        if (submitting || previewing) return;
        reset();
        onClose();
    };

    // Parse the header row client-side to power the column pickers.
    const handleFile = (selected) => {
        if (!selected) return;
        setFile(selected);
        const reader = new FileReader();
        reader.onload = (event) => {
            const firstLine = String(event.target.result || '').split(/\r?\n/)[0] || '';
            const cols = parseCsvHeader(firstLine, fieldSeparator);
            setHeaders(cols);
            if (cols.length && !cols.includes(assetPathColumn)) {
                setAssetPathCol(cols[0]);
            }
        };
        reader.readAsText(selected.slice(0, 64 * 1024));
    };

    const validateForm = () => {
        if (!file) {
            notify('Please select a CSV file.', 'warning');
            return null;
        }

        const size = parseInt(batchSize, 10);
        if (Number.isNaN(size) || size < 1 || size > 100) {
            notify('Batch size must be between 1 and 100.', 'warning');
            return null;
        }

        if (schedule === 'later' && !scheduledAt) {
            notify('Please pick a date & time.', 'warning');
            return null;
        }

        return size;
    };

    const buildFormData = () => {
        const size = validateForm();
        if (!size) return null;

        const fd = new FormData();
        fd.append('metadata_import[source_file]', file);
        fd.append('metadata_import[name]', file.name);
        fd.append('metadata_import[batch_size]', String(size));
        fd.append('metadata_import[field_separator]', fieldSeparator || ',');
        fd.append('metadata_import[multi_value_delimiter]', multiDelimiter || '|');
        fd.append('metadata_import[launch_workflows]', launchWorkflows ? '1' : '0');
        fd.append('metadata_import[asset_path_column]', assetPathColumn || 'asset_path');
        ignoredColumns.forEach((column) => fd.append('metadata_import[ignored_columns][]', column));
        if (schedule === 'later') fd.append('metadata_import[scheduled_at]', scheduledAt);
        return fd;
    };

    const handlePreview = async () => {
        const fd = buildFormData();
        if (!fd) return;

        setPreviewing(true);
        const data = await onPreview(fd);
        setPreviewing(false);

        if (data) {
            setPreview(data);
        }
    };

    const handleSubmit = async () => {
        const fd = buildFormData();
        if (!fd) return;

        setSubmitting(true);
        const ok = await onCreate(fd);
        setSubmitting(false);
        if (ok) {
            reset();
            onClose();
        }
    };

    const ignorableColumns = headers.filter((header) => header !== assetPathColumn);
    const previewRows = preview?.rows || [];

    return (
        <Dialog
            open={open}
            onClose={handleDialogClose}
            maxWidth="md"
            fullWidth
        >
            <DialogTitle sx={{ fontWeight: 700, display: 'flex', alignItems: 'center', gap: 1 }}>
                <UploadFileOutlined sx={{ color: '#5e35b1' }} /> Metadata Import
            </DialogTitle>
            <DialogContent dividers>
                <Stack spacing={2.5} sx={{ mt: 0.5 }}>
                    <Box>
                        <input
                            ref={fileInputRef}
                            type="file"
                            accept=".csv,text/csv"
                            hidden
                            onChange={(event) => handleFile(event.target.files?.[0])}
                        />
                        <Button
                            variant="outlined"
                            startIcon={<InsertDriveFileOutlined />}
                            onClick={() => fileInputRef.current?.click()}
                            sx={{ textTransform: 'none', borderColor: '#cbd5e1', color: '#475569' }}
                        >
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
                        <Grid size={6}>
                            <TextField
                                label="Batch size"
                                type="number"
                                size="small"
                                fullWidth
                                value={batchSize}
                                onChange={(event) => setBatchSize(event.target.value)}
                                helperText="Default 50, max 100"
                                slotProps={{ htmlInput: { min: 1, max: 100 } }}
                            />
                        </Grid>
                        <Grid size={6}>
                            <Autocomplete
                                freeSolo
                                size="small"
                                options={headers}
                                value={assetPathColumn}
                                onInputChange={(_, value) => setAssetPathCol(value)}
                                onChange={(_, value) => setAssetPathCol(value || 'asset_path')}
                                renderInput={(params) => (
                                    <TextField {...params} label="Asset path column" helperText="Default asset_path" />
                                )}
                            />
                        </Grid>
                        <Grid size={6}>
                            <TextField
                                label="Field separator"
                                size="small"
                                fullWidth
                                value={fieldSeparator}
                                onChange={(event) => setFieldSeparator(event.target.value)}
                                helperText="Default ,"
                                slotProps={{ htmlInput: { maxLength: 3 } }}
                            />
                        </Grid>
                        <Grid size={6}>
                            <TextField
                                label="Multi-value delimiter"
                                size="small"
                                fullWidth
                                value={multiDelimiter}
                                onChange={(event) => setMultiDelimiter(event.target.value)}
                                helperText="Default |"
                                slotProps={{ htmlInput: { maxLength: 3 } }}
                            />
                        </Grid>
                    </Grid>

                    <Autocomplete
                        multiple
                        freeSolo
                        size="small"
                        options={ignorableColumns}
                        value={ignoredColumns}
                        onChange={(_, value) => setIgnoredCols(value)}
                        renderInput={(params) => (
                            <TextField
                                {...params}
                                label="Columns to ignore"
                                placeholder="Add columns to skip"
                                helperText="These columns will not be written to assets."
                            />
                        )}
                    />

                    <FormControlLabel
                        control={<Checkbox checked={launchWorkflows} onChange={(event) => setLaunchWf(event.target.checked)} />}
                        label={(
                            <Box>
                                <Typography variant="body2">Launch workflows</Typography>
                                <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                    Runs the DAM Metadata WriteBack workflow. Slows the system down.
                                </Typography>
                            </Box>
                        )}
                    />

                    <Divider />

                    <FormControl>
                        <FormLabel sx={{ fontSize: '0.85rem', fontWeight: 600 }}>When to import</FormLabel>
                        <RadioGroup row value={schedule} onChange={(event) => setSchedule(event.target.value)}>
                            <FormControlLabel value="now" control={<Radio size="small" />} label="Now" />
                            <FormControlLabel value="later" control={<Radio size="small" />} label="Later" />
                        </RadioGroup>
                    </FormControl>
                    {schedule === 'later' && (
                        <TextField
                            type="datetime-local"
                            label="Scheduled date & time"
                            size="small"
                            slotProps={{ inputLabel: { shrink: true } }}
                            value={scheduledAt}
                            onChange={(event) => setScheduledAt(event.target.value)}
                        />
                    )}

                    {preview && (
                        <Paper variant="outlined" sx={{ borderRadius: 2, overflow: 'hidden' }} data-testid="metadata-import-preview-results">
                            <Box sx={{ px: 2, py: 1.5, bgcolor: '#faf5ff', borderBottom: '1px solid #ede9fe' }}>
                                <Stack
                                    direction="row"
                                    spacing={1}
                                    sx={{ alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap' }}
                                >
                                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#5e35b1' }}>
                                        {t('metadataImport.preview.title', 'Preview results')}
                                    </Typography>
                                    <Stack direction="row" spacing={0.75}>
                                        <Chip
                                            label={`${preview.success_count} success`}
                                            size="small"
                                            sx={{ height: 22, bgcolor: '#dcfce7', color: '#166534' }}
                                        />
                                        <Chip
                                            label={`${preview.failure_count} fail`}
                                            size="small"
                                            sx={{ height: 22, bgcolor: '#fee2e2', color: '#991b1b' }}
                                        />
                                    </Stack>
                                </Stack>
                            </Box>
                            <Box sx={{ p: 2 }}>
                                <Alert severity={preview.failure_count > 0 ? 'warning' : 'success'} sx={{ mb: 2 }}>
                                    {t(
                                        'metadataImport.preview.summary',
                                        '{{success}} row(s) would succeed and {{failure}} would fail out of {{total}}.',
                                        {
                                            total: preview.total_rows,
                                            success: preview.success_count,
                                            failure: preview.failure_count,
                                        }
                                    )}
                                </Alert>
                                <Box sx={{ maxHeight: 280, overflow: 'auto' }}>
                                    <Table size="small">
                                        <TableHead>
                                            <TableRow>
                                                <TableCell>{t('metadataImport.preview.row', 'Row')}</TableCell>
                                                <TableCell>{t('metadataImport.preview.asset', 'Asset')}</TableCell>
                                                <TableCell>{t('metadataImport.preview.status', 'Status')}</TableCell>
                                                <TableCell>{t('metadataImport.preview.message', 'Message')}</TableCell>
                                                <TableCell>{t('metadataImport.preview.changes', 'Changes')}</TableCell>
                                            </TableRow>
                                        </TableHead>
                                        <TableBody>
                                            {previewRows.map((row) => (
                                                <TableRow key={`${row.row_number}-${row.asset_path}`}>
                                                    <TableCell>{row.row_number}</TableCell>
                                                    <TableCell>
                                                        <Typography variant="body2" fontWeight={600}>{row.asset_path}</Typography>
                                                        {row.resolved_asset_path && row.resolved_asset_path !== row.asset_path && (
                                                            <Typography variant="caption" sx={{ color: '#64748b' }}>
                                                                {t('metadataImport.preview.resolvedAs', 'Resolved as {{path}}', {
                                                                    path: row.resolved_asset_path,
                                                                })}
                                                            </Typography>
                                                        )}
                                                    </TableCell>
                                                    <TableCell>
                                                        <Chip
                                                            label={row.status}
                                                            size="small"
                                                            sx={{
                                                                height: 22,
                                                                bgcolor: row.status === 'success' ? '#dcfce7' : '#fee2e2',
                                                                color: row.status === 'success' ? '#166534' : '#991b1b',
                                                            }}
                                                        />
                                                    </TableCell>
                                                    <TableCell>
                                                        <Typography variant="body2">{row.message}</Typography>
                                                    </TableCell>
                                                    <TableCell>
                                                        {row.changes?.length ? (
                                                            <Stack spacing={0.5}>
                                                                {row.changes.map((change) => (
                                                                    <Typography key={`${row.row_number}-${change.field}`} variant="caption" sx={{ color: '#475569' }}>
                                                                        <strong>{change.field}</strong>: {formatPreviewValue(change.from)} → {formatPreviewValue(change.to)}
                                                                    </Typography>
                                                                ))}
                                                            </Stack>
                                                        ) : (
                                                            <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                                                {t('metadataImport.preview.noChanges', 'No field changes')}
                                                            </Typography>
                                                        )}
                                                    </TableCell>
                                                </TableRow>
                                            ))}
                                        </TableBody>
                                    </Table>
                                </Box>
                            </Box>
                        </Paper>
                    )}
                </Stack>
            </DialogContent>
            <DialogActions sx={{ px: 3, py: 2 }}>
                <Button onClick={handleDialogClose} sx={{ textTransform: 'none' }} disabled={submitting || previewing}>Cancel</Button>
                <Button
                    variant="outlined"
                    onClick={handlePreview}
                    disabled={submitting || previewing}
                    startIcon={previewing ? <CircularProgress size={16} color="inherit" /> : <PreviewOutlined />}
                    sx={{ textTransform: 'none', borderColor: '#5e35b1', color: '#5e35b1' }}
                >
                    {previewing ? t('metadataImport.preview.loading', 'Previewing…') : t('metadataImport.preview.action', 'Preview')}
                </Button>
                <Button
                    variant="contained"
                    onClick={handleSubmit}
                    disabled={submitting || previewing}
                    startIcon={submitting ? <CircularProgress size={16} color="inherit" /> : <UploadFileOutlined />}
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none' }}
                >
                    Import
                </Button>
            </DialogActions>
        </Dialog>
    );
}

// ── Main manager ────────────────────────────────────────────────────────────────
export default function MetadataImportManager() {
    const notify = useNotify();
    const { t } = useTranslation();
    const [imports, setImports] = useState([]);
    const [loading, setLoading] = useState(true);
    const [dialogOpen, setDialog] = useState(false);
    const [page, setPage] = useState(0); // zero-indexed, matches MUI TablePagination
    const [perPage, setPerPage] = useState(25);
    const [total, setTotal] = useState(0);
    const [selectedIds, setSelectedIds] = useState(new Set());
    const [bulkDeleting, setBulkDeleting] = useState(false);
    const pollRef = useRef(null);

    const fetchImports = useCallback(async () => {
        try {
            const res = await fetch(`/api/v1/metadata_imports?page=${page + 1}&per_page=${perPage}`);
            const data = await res.json();
            setImports(Array.isArray(data.imports) ? data.imports : []);
            setTotal(data.meta?.total || 0);
        } catch {
            notify('Failed to load imports.', 'error');
        } finally {
            setLoading(false);
        }
    }, [notify, page, perPage]);

    useEffect(() => {
        fetchImports();
    }, [fetchImports]);

    // Selection is page-scoped — clear it whenever the underlying rows change.
    useEffect(() => { setSelectedIds(new Set()); }, [page, perPage]);

    useEffect(() => {
        const inFlight = imports.some((item) => item.status === 'pending' || item.status === 'processing');
        clearInterval(pollRef.current);
        if (inFlight) pollRef.current = setInterval(fetchImports, 4000);
        return () => clearInterval(pollRef.current);
    }, [imports, fetchImports]);

    const handlePreview = async (formData) => {
        try {
            const res = await fetch('/api/v1/metadata_imports/preview', {
                method: 'POST',
                headers: { 'X-CSRF-Token': csrfToken() },
                body: formData,
            });
            const data = await res.json();
            if (!res.ok) {
                notify(data.errors?.join(', ') || t('metadataImport.preview.previewFailed', 'Preview failed.'), 'error');
                return null;
            }
            return data;
        } catch {
            notify(t('metadataImport.preview.previewFailed', 'Preview failed.'), 'error');
            return null;
        }
    };

    const handleCreate = async (formData) => {
        try {
            const res = await fetch('/api/v1/metadata_imports', {
                method: 'POST',
                headers: { 'X-CSRF-Token': csrfToken() },
                body: formData,
            });
            const data = await res.json();
            if (!res.ok) {
                notify(data.errors?.join(', ') || 'Import failed to start.', 'error');
                return false;
            }
            notify('Metadata import started. You will be notified when it is complete.', 'success');
            if (page === 0) {
                await fetchImports();
            } else {
                setPage(0); // triggers fetchImports via the page-change effect
            }
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
        if (!res.ok) {
            notify('Delete failed.', 'error');
            return;
        }
        notify('Import deleted.', 'success');
        if (page > 0 && imports.length === 1) {
            setPage(page - 1); // last row on this page removed — step back a page
        } else {
            await fetchImports();
        }
    };

    const handleToggleSelect = (id) => {
        setSelectedIds(prev => {
            const next = new Set(prev);
            if (next.has(id)) next.delete(id); else next.add(id);
            return next;
        });
    };

    const handleToggleSelectAll = () => {
        setSelectedIds(prev => {
            const allIds = imports.map(i => i.id);
            const allSelected = allIds.length > 0 && allIds.every(id => prev.has(id));
            return allSelected ? new Set() : new Set(allIds);
        });
    };

    const handleBulkDelete = async () => {
        if (selectedIds.size === 0) return;
        if (!window.confirm(`Delete ${selectedIds.size} selected import(s) and their files?`)) return;
        setBulkDeleting(true);
        try {
            const res = await fetch('/api/v1/metadata_imports/bulk_delete', {
                method: 'DELETE',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
                body: JSON.stringify({ ids: Array.from(selectedIds) }),
            });
            const data = await res.json();
            if (!res.ok) { notify(data.error || 'Bulk delete failed.', 'error'); return; }
            notify(`${data.deleted_count} import(s) deleted.`, 'success');
            setSelectedIds(new Set());
            if (page > 0 && selectedIds.size === imports.length) {
                setPage(page - 1);
            } else {
                await fetchImports();
            }
        } finally {
            setBulkDeleting(false);
        }
    };

    const handlePageChange = (_event, newPage) => setPage(newPage);
    const handlePerPageChange = (event) => {
        setPerPage(parseInt(event.target.value, 10));
        setPage(0);
    };

    return (
        <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', bgcolor: '#f8fafc' }}>
            <Box
                sx={{
                    px: 3,
                    py: 2,
                    bgcolor: '#fff',
                    borderBottom: '1px solid #e2e8f0',
                    display: 'flex',
                    alignItems: 'center',
                    gap: 2,
                }}
            >
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
                {selectedIds.size > 0 && (
                    <Button
                        variant="outlined"
                        color="error"
                        startIcon={<DeleteOutlined />}
                        onClick={handleBulkDelete}
                        disabled={bulkDeleting}
                        data-testid="import-bulk-delete-button"
                        sx={{ textTransform: 'none' }}
                    >
                        {t('common.deleteSelected', { count: selectedIds.size, defaultValue: `Delete Selected (${selectedIds.size})` })}
                    </Button>
                )}
                <Button
                    variant="contained"
                    startIcon={<AddOutlined />}
                    onClick={() => setDialog(true)}
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none' }}
                >
                    New Import
                </Button>
            </Box>

            <Box sx={{ flex: 1, overflow: 'auto', p: 3 }}>
                <Paper
                    variant="outlined"
                    sx={{
                        p: 2,
                        mb: 3,
                        borderRadius: 2,
                        bgcolor: '#faf5ff',
                        display: 'flex',
                        alignItems: 'center',
                        gap: 2,
                    }}
                >
                    <DownloadOutlined sx={{ color: '#5e35b1' }} />
                    <Box sx={{ flex: 1 }}>
                        <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#5e35b1' }}>
                            Start with the template
                        </Typography>
                        <Typography variant="caption" sx={{ color: '#64748b' }}>
                            Download the fixed-column starter CSV (asset_path + standard metadata). The first column
                            is the asset&apos;s absolute DAM path; leave a cell empty to skip that property.
                        </Typography>
                    </Box>
                    <Button
                        variant="outlined"
                        size="small"
                        startIcon={<FileDownloadOutlined />}
                        href="/api/v1/metadata_imports/template"
                        sx={{ textTransform: 'none', borderColor: '#5e35b1', color: '#5e35b1' }}
                    >
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
                                    <TableCell padding="checkbox">
                                        <Checkbox
                                            size="small"
                                            data-testid="import-select-all"
                                            checked={imports.length > 0 && imports.every(i => selectedIds.has(i.id))}
                                            indeterminate={imports.some(i => selectedIds.has(i.id)) && !imports.every(i => selectedIds.has(i.id))}
                                            onChange={handleToggleSelectAll}
                                        />
                                    </TableCell>
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
                                {imports.map((imp) => {
                                    const meta = STATUS_META[imp.status] || STATUS_META.pending;
                                    return (
                                        <TableRow key={imp.id} hover selected={selectedIds.has(imp.id)}>
                                            <TableCell padding="checkbox">
                                                <Checkbox
                                                    size="small"
                                                    data-testid={`import-select-${imp.id}`}
                                                    checked={selectedIds.has(imp.id)}
                                                    onChange={() => handleToggleSelect(imp.id)}
                                                />
                                            </TableCell>
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
                                                        <Chip
                                                            label={`${imp.success_count} ok`}
                                                            size="small"
                                                            sx={{ height: 20, fontSize: '0.7rem', bgcolor: '#dcfce7', color: '#166534' }}
                                                        />
                                                        {imp.failure_count > 0 && (
                                                            <Chip
                                                                label={`${imp.failure_count} fail`}
                                                                size="small"
                                                                sx={{ height: 20, fontSize: '0.7rem', bgcolor: '#fee2e2', color: '#991b1b' }}
                                                            />
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
                                                <Stack direction="row" spacing={1} sx={{ justifyContent: 'flex-end' }}>
                                                    {imp.source_file && (
                                                        <Link
                                                            href={imp.source_file.download_url}
                                                            underline="hover"
                                                            sx={{ fontSize: '0.8rem', color: '#5e35b1', display: 'flex', alignItems: 'center', gap: 0.3 }}
                                                        >
                                                            <FileDownloadOutlined sx={{ fontSize: 15 }} /> Input
                                                        </Link>
                                                    )}
                                                    {imp.result_file && (
                                                        <Link
                                                            href={imp.result_file.download_url}
                                                            underline="hover"
                                                            sx={{ fontSize: '0.8rem', color: '#16a34a', display: 'flex', alignItems: 'center', gap: 0.3 }}
                                                        >
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
                    {!loading && imports.length > 0 && (
                        <TablePagination
                            component="div"
                            count={total}
                            page={page}
                            onPageChange={handlePageChange}
                            rowsPerPage={perPage}
                            onRowsPerPageChange={handlePerPageChange}
                            rowsPerPageOptions={[ 25, 50, 100 ]}
                            labelRowsPerPage={t('common.rowsPerPage', 'Rows per page:')}
                        />
                    )}
                </Paper>
            </Box>

            <ImportDialog
                open={dialogOpen}
                onClose={() => setDialog(false)}
                onCreate={handleCreate}
                onPreview={handlePreview}
            />
        </Box>
    );
}
