import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Typography, Button, IconButton, Tooltip, Chip, Stack, Paper,
    Table, TableHead, TableRow, TableCell, TableBody, CircularProgress,
    Dialog, DialogTitle, DialogContent, DialogActions, TextField,
    FormControl, InputLabel, Select, MenuItem, FormControlLabel, Checkbox,
    RadioGroup, Radio, FormLabel, Autocomplete, Divider, Menu
} from '@mui/material';
import {
    FileDownloadOutlined, AddOutlined, RefreshOutlined, DeleteOutlined,
    DescriptionOutlined, FolderOpenOutlined, ScheduleOutlined,
    CheckCircleOutlined, ErrorOutlined, HourglassEmptyOutlined, MoreVertOutlined
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

const STATUS_META = {
    pending:    { label: 'Queued',     color: '#f59e0b', icon: <HourglassEmptyOutlined sx={{ fontSize: 16 }} /> },
    processing: { label: 'Processing', color: '#0288d1', icon: <CircularProgress size={14} /> },
    completed:  { label: 'Completed',  color: '#16a34a', icon: <CheckCircleOutlined sx={{ fontSize: 16 }} /> },
    failed:     { label: 'Failed',     color: '#dc2626', icon: <ErrorOutlined sx={{ fontSize: 16 }} /> },
};

function csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content;
}

function humanSize(bytes) {
    if (!bytes && bytes !== 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    let value = bytes, i = 0;
    while (value >= 1024 && i < units.length - 1) { value /= 1024; i++; }
    return `${value.toFixed(value < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
}

// ── New / Edit dialog ──────────────────────────────────────────────────────────
function ExportDialog({ open, onClose, onCreate, folders }) {
    const notify = useNotify();
    const [name, setName]                         = useState('');
    const [folderId, setFolderId]                 = useState('root');
    const [includeSubfolders, setIncludeSub]      = useState(true);
    const [schedule, setSchedule]                 = useState('now');
    const [scheduledAt, setScheduledAt]           = useState('');
    const [propertyMode, setPropertyMode]         = useState('all');
    const [availableProps, setAvailableProps]     = useState([]);
    const [selectedProps, setSelectedProps]       = useState([]);
    const [loadingProps, setLoadingProps]         = useState(false);
    const [submitting, setSubmitting]             = useState(false);

    // Load property keys whenever the scope changes & user wants selective props.
    useEffect(() => {
        if (propertyMode !== 'selective') return;
        setLoadingProps(true);
        const qs = new URLSearchParams({ folder_id: folderId, include_subfolders: includeSubfolders });
        fetch(`/api/v1/metadata_exports/properties?${qs}`)
            .then(r => r.ok ? r.json() : { properties: [] })
            .then(d => setAvailableProps(d.properties || []))
            .catch(() => setAvailableProps([]))
            .finally(() => setLoadingProps(false));
    }, [propertyMode, folderId, includeSubfolders]);

    const handleSubmit = async () => {
        if (!name.trim()) { notify('Please provide a file name.', 'warning'); return; }
        if (schedule === 'later' && !scheduledAt) { notify('Please pick a date & time.', 'warning'); return; }
        if (propertyMode === 'selective' && selectedProps.length === 0) {
            notify('Select at least one property to export.', 'warning'); return;
        }
        setSubmitting(true);
        const ok = await onCreate({
            name: name.trim(),
            folder_id: folderId,
            include_subfolders: includeSubfolders,
            property_mode: propertyMode,
            selected_properties: propertyMode === 'selective' ? selectedProps : [],
            scheduled_at: schedule === 'later' ? scheduledAt : null,
        });
        setSubmitting(false);
        if (ok) onClose();
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
            <DialogTitle sx={{ fontWeight: 700, display: 'flex', alignItems: 'center', gap: 1 }}>
                <FileDownloadOutlined sx={{ color: '#5e35b1' }} /> Metadata Export
            </DialogTitle>
            <DialogContent dividers>
                <Stack spacing={2.5} sx={{ mt: 0.5 }}>
                    <TextField
                        label="CSV file name" value={name} onChange={e => setName(e.target.value)}
                        placeholder="e.g. marketing_assets" fullWidth size="small" autoFocus
                        helperText="A .csv extension is added automatically."
                    />

                    <FormControl fullWidth size="small">
                        <InputLabel>Asset folder</InputLabel>
                        <Select label="Asset folder" value={folderId} onChange={e => setFolderId(e.target.value)}>
                            <MenuItem value="root">/ (Root)</MenuItem>
                            {folders.map(f => (
                                <MenuItem key={f.id} value={f.id}>{f.name}</MenuItem>
                            ))}
                        </Select>
                    </FormControl>

                    <FormControlLabel
                        control={<Checkbox checked={includeSubfolders} onChange={e => setIncludeSub(e.target.checked)} />}
                        label="Include assets in subfolders"
                    />

                    <Divider />

                    <FormControl>
                        <FormLabel sx={{ fontSize: '0.85rem', fontWeight: 600 }}>When to export</FormLabel>
                        <RadioGroup row value={schedule} onChange={e => setSchedule(e.target.value)}>
                            <FormControlLabel value="now" control={<Radio size="small" />} label="Now" />
                            <FormControlLabel value="later" control={<Radio size="small" />} label="Later" />
                        </RadioGroup>
                    </FormControl>
                    {schedule === 'later' && (
                        <TextField
                            type="datetime-local" label="Scheduled date & time" size="small"
                            InputLabelProps={{ shrink: true }} value={scheduledAt}
                            onChange={e => setScheduledAt(e.target.value)}
                        />
                    )}

                    <Divider />

                    <FormControl>
                        <FormLabel sx={{ fontSize: '0.85rem', fontWeight: 600 }}>Properties to be exported</FormLabel>
                        <RadioGroup value={propertyMode} onChange={e => setPropertyMode(e.target.value)}>
                            <FormControlLabel value="all" control={<Radio size="small" />} label="All properties" />
                            <FormControlLabel value="selective" control={<Radio size="small" />} label="Selective properties" />
                        </RadioGroup>
                    </FormControl>
                    {propertyMode === 'selective' && (
                        <Autocomplete
                            multiple freeSolo size="small" options={availableProps} value={selectedProps}
                            loading={loadingProps}
                            onChange={(_, v) => setSelectedProps(v)}
                            renderInput={(params) => (
                                <TextField {...params} label="Properties"
                                    placeholder="Add property keys"
                                    helperText="Pick discovered keys or type custom ones." />
                            )}
                        />
                    )}
                </Stack>
            </DialogContent>
            <DialogActions sx={{ px: 3, py: 2 }}>
                <Button onClick={onClose} sx={{ textTransform: 'none' }}>Cancel</Button>
                <Button
                    variant="contained" onClick={handleSubmit} disabled={submitting}
                    startIcon={submitting ? <CircularProgress size={16} color="inherit" /> : <FileDownloadOutlined />}
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none' }}
                >
                    Export
                </Button>
            </DialogActions>
        </Dialog>
    );
}

// ── Files download menu ─────────────────────────────────────────────────────────
function DownloadCell({ exp }) {
    const [anchor, setAnchor] = useState(null);

    if (exp.status !== 'completed' || !exp.files?.length) {
        return <Typography variant="caption" sx={{ color: '#94a3b8' }}>—</Typography>;
    }

    if (exp.files.length === 1) {
        return (
            <Button size="small" startIcon={<FileDownloadOutlined fontSize="small" />}
                href={exp.files[0].download_url}
                sx={{ textTransform: 'none', color: '#5e35b1' }}>
                CSV Download
            </Button>
        );
    }

    return (
        <>
            <Button size="small" startIcon={<FileDownloadOutlined fontSize="small" />}
                endIcon={<MoreVertOutlined fontSize="small" />}
                onClick={e => setAnchor(e.currentTarget)}
                sx={{ textTransform: 'none', color: '#5e35b1' }}>
                {exp.files.length} files
            </Button>
            <Menu anchorEl={anchor} open={Boolean(anchor)} onClose={() => setAnchor(null)}>
                {exp.files.map(f => (
                    <MenuItem key={f.id} component="a" href={f.download_url} onClick={() => setAnchor(null)}>
                        <FileDownloadOutlined fontSize="small" sx={{ mr: 1, color: '#5e35b1' }} />
                        {f.filename}
                        <Typography variant="caption" sx={{ ml: 1, color: '#94a3b8' }}>{humanSize(f.byte_size)}</Typography>
                    </MenuItem>
                ))}
            </Menu>
        </>
    );
}

// ── Main manager ────────────────────────────────────────────────────────────────
export default function MetadataExportManager() {
    const notify = useNotify();
    const [exports, setExports]   = useState([]);
    const [folders, setFolders]   = useState([]);
    const [loading, setLoading]   = useState(true);
    const [dialogOpen, setDialog] = useState(false);
    const pollRef = useRef(null);

    const fetchExports = useCallback(async () => {
        try {
            const res = await fetch('/api/v1/metadata_exports');
            const data = await res.json();
            setExports(Array.isArray(data) ? data : []);
        } catch {
            notify('Failed to load exports.', 'error');
        } finally {
            setLoading(false);
        }
    }, []); // eslint-disable-line react-hooks/exhaustive-deps

    const fetchFolders = useCallback(async () => {
        try {
            const res = await fetch('/api/v1/folders');
            const data = await res.json();
            setFolders(data.folders || []);
        } catch { /* non-blocking */ }
    }, []);

    useEffect(() => { fetchExports(); fetchFolders(); }, [fetchExports, fetchFolders]);

    // Poll while any export is still in flight.
    useEffect(() => {
        const inFlight = exports.some(e => e.status === 'pending' || e.status === 'processing');
        clearInterval(pollRef.current);
        if (inFlight) {
            pollRef.current = setInterval(fetchExports, 4000);
        }
        return () => clearInterval(pollRef.current);
    }, [exports, fetchExports]);

    const handleCreate = async (payload) => {
        try {
            const res = await fetch('/api/v1/metadata_exports', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
                body: JSON.stringify({ metadata_export: payload }),
            });
            const data = await res.json();
            if (!res.ok) { notify(data.errors?.join(', ') || 'Export failed to start.', 'error'); return false; }
            notify('Metadata export started. You will be notified when it is ready.', 'success');
            await fetchExports();
            return true;
        } catch {
            notify('Export failed to start.', 'error');
            return false;
        }
    };

    const handleDelete = async (exp) => {
        if (!window.confirm(`Delete export "${exp.name}" and its files?`)) return;
        const res = await fetch(`/api/v1/metadata_exports/${exp.id}`, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': csrfToken() },
        });
        if (!res.ok) { notify('Delete failed.', 'error'); return; }
        notify('Export deleted.', 'success');
        await fetchExports();
    };

    return (
        <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', bgcolor: '#f8fafc' }}>
            {/* Top bar */}
            <Box sx={{ px: 3, py: 2, bgcolor: '#fff', borderBottom: '1px solid #e2e8f0',
                       display: 'flex', alignItems: 'center', gap: 2 }}>
                <FileDownloadOutlined sx={{ color: '#5e35b1', fontSize: 24 }} />
                <Box sx={{ flex: 1 }}>
                    <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b', lineHeight: 1.2 }}>
                        Metadata Export
                    </Typography>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        Tools › Assets › Metadata Export
                    </Typography>
                </Box>
                <Tooltip title="Refresh">
                    <IconButton size="small" onClick={fetchExports} sx={{ border: '1px solid #e2e8f0' }}>
                        <RefreshOutlined fontSize="small" />
                    </IconButton>
                </Tooltip>
                <Button variant="contained" startIcon={<AddOutlined />} onClick={() => setDialog(true)}
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none' }}>
                    New Export
                </Button>
            </Box>

            {/* Body */}
            <Box sx={{ flex: 1, overflow: 'auto', p: 3 }}>
                <Paper variant="outlined" sx={{ borderRadius: 2, overflow: 'hidden' }}>
                    <Box sx={{ px: 2, py: 1.5, bgcolor: '#faf5ff', borderBottom: '1px solid #f1f5f9' }}>
                        <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#5e35b1' }}>
                            Export history
                        </Typography>
                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                            Generated files are available for 30 days, then automatically removed.
                        </Typography>
                    </Box>

                    {loading ? (
                        <Box sx={{ display: 'flex', justifyContent: 'center', p: 5 }}>
                            <CircularProgress size={28} sx={{ color: '#5e35b1' }} />
                        </Box>
                    ) : exports.length === 0 ? (
                        <Box sx={{ p: 5, textAlign: 'center', color: '#94a3b8' }}>
                            <DescriptionOutlined sx={{ fontSize: 48, opacity: 0.3 }} />
                            <Typography variant="body2" sx={{ mt: 1 }}>
                                No exports yet. Click “New Export” to generate a metadata CSV.
                            </Typography>
                        </Box>
                    ) : (
                        <Table size="small">
                            <TableHead>
                                <TableRow sx={{ '& th': { fontWeight: 700, color: '#475569', bgcolor: '#fff' } }}>
                                    <TableCell>File</TableCell>
                                    <TableCell>Folder</TableCell>
                                    <TableCell>Properties</TableCell>
                                    <TableCell>Status</TableCell>
                                    <TableCell>Created by</TableCell>
                                    <TableCell>Date</TableCell>
                                    <TableCell>Expires</TableCell>
                                    <TableCell align="right">Download</TableCell>
                                    <TableCell align="right"></TableCell>
                                </TableRow>
                            </TableHead>
                            <TableBody>
                                {exports.map(exp => {
                                    const meta = STATUS_META[exp.status] || STATUS_META.pending;
                                    return (
                                        <TableRow key={exp.id} hover>
                                            <TableCell>
                                                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                                    <DescriptionOutlined sx={{ fontSize: 18, color: '#5e35b1' }} />
                                                    <Box>
                                                        <Typography variant="body2" fontWeight={600}>{exp.name}.csv</Typography>
                                                        {exp.status === 'completed' && (
                                                            <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                                                {exp.total_assets} asset(s) · {exp.file_count} file(s)
                                                            </Typography>
                                                        )}
                                                        {exp.status === 'failed' && exp.error_message && (
                                                            <Typography variant="caption" sx={{ color: '#dc2626' }}>
                                                                {exp.error_message}
                                                            </Typography>
                                                        )}
                                                        {exp.scheduled_at && exp.status === 'pending' && (
                                                            <Typography variant="caption" sx={{ color: '#94a3b8', display: 'flex', alignItems: 'center', gap: 0.5 }}>
                                                                <ScheduleOutlined sx={{ fontSize: 12 }} /> {exp.scheduled_at}
                                                            </Typography>
                                                        )}
                                                    </Box>
                                                </Box>
                                            </TableCell>
                                            <TableCell>
                                                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                                                    <FolderOpenOutlined sx={{ fontSize: 16, color: '#f59e0b' }} />
                                                    <Typography variant="body2">{exp.folder_name}</Typography>
                                                    {exp.include_subfolders && (
                                                        <Chip label="+ sub" size="small"
                                                              sx={{ height: 16, fontSize: '0.6rem', bgcolor: '#f1f5f9' }} />
                                                    )}
                                                </Box>
                                            </TableCell>
                                            <TableCell>
                                                <Chip
                                                    label={exp.property_mode === 'all' ? 'All' : `${exp.selected_properties?.length || 0} selected`}
                                                    size="small"
                                                    sx={{ fontSize: '0.7rem', bgcolor: '#ede7f6', color: '#5e35b1' }} />
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
                                                <Typography variant="body2" sx={{ color: '#475569' }}>{exp.created_by}</Typography>
                                            </TableCell>
                                            <TableCell>
                                                <Typography variant="caption" sx={{ color: '#64748b' }}>{exp.created_at}</Typography>
                                            </TableCell>
                                            <TableCell>
                                                <Typography variant="caption" sx={{ color: '#64748b' }}>{exp.expires_at || '—'}</Typography>
                                            </TableCell>
                                            <TableCell align="right">
                                                <DownloadCell exp={exp} />
                                            </TableCell>
                                            <TableCell align="right">
                                                <Tooltip title="Delete">
                                                    <IconButton size="small" onClick={() => handleDelete(exp)}
                                                        sx={{ color: '#ef4444' }}>
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

            <ExportDialog
                open={dialogOpen}
                onClose={() => setDialog(false)}
                onCreate={handleCreate}
                folders={folders}
            />
        </Box>
    );
}

