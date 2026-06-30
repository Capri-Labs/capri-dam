import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, Typography, Button, TextField, IconButton, Paper, Divider,
    CircularProgress, Tooltip, Chip, Stack, Switch, FormControlLabel,
    List, ListItem, ListItemText, ListItemSecondaryAction, Alert,
    Collapse
} from '@mui/material';
import {
    BlockOutlined, AddOutlined, DeleteOutlined, SaveOutlined,
    InfoOutlined, CheckCircleOutlined, ExpandMore, ExpandLess
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

const COMMON_MIME_SUGGESTIONS = [
    { label: 'All Images', value: 'image/*' },
    { label: 'JPEG', value: 'image/jpeg' },
    { label: 'PNG', value: 'image/png' },
    { label: 'GIF', value: 'image/gif' },
    { label: 'WebP', value: 'image/webp' },
    { label: 'SVG', value: 'image/svg+xml' },
    { label: 'TIFF', value: 'image/tiff' },
    { label: 'PDF', value: 'application/pdf' },
    { label: 'All Video', value: 'video/*' },
    { label: 'MP4', value: 'video/mp4' },
    { label: 'MOV', value: 'video/quicktime' },
    { label: 'All Audio', value: 'audio/*' },
    { label: 'ZIP', value: 'application/zip' },
    { label: 'Word Doc', value: 'application/msword' },
    { label: 'Excel', value: 'application/vnd.ms-excel' },
];

function MimeTypeRow({ value, onDelete, index }) {
    return (
        <ListItem
            sx={{ border: '1px solid #e2e8f0', borderRadius: '8px', mb: 1, bgcolor: '#fff',
                  '&:hover': { bgcolor: '#f8fafc' }, pr: 6 }}
        >
            <ListItemText
                primary={
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Typography variant="body2" fontFamily="monospace" sx={{ color: '#1e293b', fontWeight: 500 }}>
                            {value}
                        </Typography>
                        {value.endsWith('/*') && (
                            <Chip label="wildcard" size="small"
                                  sx={{ fontSize: '0.62rem', height: 16, bgcolor: '#dbeafe', color: '#1d4ed8' }} />
                        )}
                    </Box>
                }
            />
            <ListItemSecondaryAction>
                <Tooltip title="Remove MIME type">
                    <IconButton size="small" onClick={() => onDelete(index)}
                                sx={{ color: '#ef4444', '&:hover': { bgcolor: '#fef2f2' } }}>
                        <DeleteOutlined fontSize="small" />
                    </IconButton>
                </Tooltip>
            </ListItemSecondaryAction>
        </ListItem>
    );
}

export default function UploadRestrictionsPanel() {
    const notify = useNotify();
    const [loading,         setLoading]         = useState(true);
    const [saving,          setSaving]          = useState(false);
    const [allowedMimes,    setAllowedMimes]    = useState([]);
    const [restrictEnabled, setRestrictEnabled] = useState(false);
    const [newMimeInput,    setNewMimeInput]    = useState('');
    const [inputError,      setInputError]      = useState('');
    const [isDirty,         setIsDirty]         = useState(false);
    const [showExamples,    setShowExamples]    = useState(false);

    const loadRestrictions = useCallback(async () => {
        setLoading(true);
        try {
            const res  = await fetch('/api/v1/upload_restrictions');
            if (!res.ok) throw new Error('Failed to load');
            const data = await res.json();
            const mimes = Array.isArray(data.allowed_mime_types) ? data.allowed_mime_types : [];
            setAllowedMimes(mimes);
            setRestrictEnabled(mimes.length > 0);
        } catch {
            notify('Failed to load upload restrictions.', 'error');
        } finally {
            setLoading(false);
        }
    }, []); // eslint-disable-line

    useEffect(() => { loadRestrictions(); }, [loadRestrictions]);

    const validateMime = (value) => {
        const trimmed = value.trim();
        if (!trimmed) return 'MIME type cannot be empty.';
        const validPattern = /^[a-zA-Z0-9!#$&\-^_]+\/(\*|[a-zA-Z0-9!#$&\-^_.+]+)$/;
        if (!validPattern.test(trimmed)) return 'Invalid MIME type format. Examples: image/jpeg, image/*, application/pdf';
        if (allowedMimes.includes(trimmed)) return 'This MIME type is already in the list.';
        return '';
    };

    const handleAdd = () => {
        const trimmed = newMimeInput.trim();
        const error   = validateMime(trimmed);
        if (error) { setInputError(error); return; }
        setAllowedMimes(prev => [...prev, trimmed]);
        setNewMimeInput(''); setInputError(''); setIsDirty(true);
    };

    const handleAddSuggestion = (mime) => {
        if (allowedMimes.includes(mime)) { notify(`"${mime}" is already in the list.`, 'warning'); return; }
        setAllowedMimes(prev => [...prev, mime]); setIsDirty(true);
    };

    const handleDelete    = (index) => { setAllowedMimes(prev => prev.filter((_, i) => i !== index)); setIsDirty(true); };
    const handleKeyDown   = (e) => { if (e.key === 'Enter') handleAdd(); };

    const handleToggleRestrict = (e) => {
        setRestrictEnabled(e.target.checked); setIsDirty(true);
        if (!e.target.checked) setAllowedMimes([]);
    };

    const handleSave = async () => {
        setSaving(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const payload   = restrictEnabled ? allowedMimes : [];
            const res       = await fetch('/api/v1/upload_restrictions', {
                method:  'PUT',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body:    JSON.stringify({ allowed_mime_types: payload }),
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.error || 'Save failed');
            notify(data.message || 'Upload restrictions saved.', 'success');
            setIsDirty(false);
            setAllowedMimes(Array.isArray(data.allowed_mime_types) ? data.allowed_mime_types : payload);
            setRestrictEnabled(payload.length > 0);
        } catch (err) {
            notify(err.message, 'error');
        } finally {
            setSaving(false);
        }
    };

    if (loading) {
        return (
            <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', flex: 1, pt: 8 }}>
                <CircularProgress sx={{ color: '#5e35b1' }} />
            </Box>
        );
    }

    return (
        <Box sx={{ flex: 1, overflow: 'auto', p: 3, maxWidth: 800 }}>
            <Paper variant="outlined" sx={{ p: 3, mb: 3, borderRadius: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 2 }}>
                    <Box>
                        <Typography variant="subtitle1" fontWeight={700} sx={{ color: '#1e293b', mb: 0.5 }}>
                            Restrict Allowed File Types
                        </Typography>
                        <Typography variant="body2" sx={{ color: '#64748b', maxWidth: 560 }}>
                            By default, DAM allows users to upload assets of all MIME types.
                            Enable this setting to restrict uploads to a specific list of MIME types only.
                        </Typography>
                    </Box>
                    <FormControlLabel
                        control={
                            <Switch checked={restrictEnabled} onChange={handleToggleRestrict}
                                    sx={{ '& .MuiSwitch-switchBase.Mui-checked': { color: '#5e35b1' },
                                          '& .MuiSwitch-switchBase.Mui-checked + .MuiSwitch-track': { bgcolor: '#5e35b1' } }} />
                        }
                        label={
                            <Typography variant="body2" fontWeight={600} sx={{ color: restrictEnabled ? '#5e35b1' : '#94a3b8' }}>
                                {restrictEnabled ? 'Enabled' : 'Disabled'}
                            </Typography>
                        }
                        labelPlacement="start"
                    />
                </Box>
                {!restrictEnabled && (
                    <Alert severity="info" icon={<CheckCircleOutlined />}
                           sx={{ mt: 2, bgcolor: '#f0f9ff', border: '1px solid #bae6fd', color: '#0369a1' }}>
                        All file types are currently permitted for upload.
                    </Alert>
                )}
            </Paper>

            <Collapse in={restrictEnabled} timeout="auto" unmountOnExit>
                <Paper variant="outlined" sx={{ p: 3, mb: 3, borderRadius: 2 }}>
                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#334155', mb: 2 }}>Allowed MIME Types</Typography>
                    <Box sx={{ display: 'flex', gap: 1, mb: 1.5 }}>
                        <TextField size="small" fullWidth placeholder="e.g. image/jpeg, image/*, application/pdf" value={newMimeInput} onChange={e => {
  setNewMimeInput(e.target.value);
  setInputError('');
}} onKeyDown={handleKeyDown} error={Boolean(inputError)} helperText={inputError} sx={{
  bgcolor: '#f8fafc'
}} slotProps={{
  htmlInput: {
    style: {
      fontFamily: 'monospace',
      fontSize: '0.875rem'
    }
  }
}} />
                        <Button variant="contained" startIcon={<AddOutlined />} onClick={handleAdd}
                                sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none', whiteSpace: 'nowrap', minWidth: 90 }}>
                            Add
                        </Button>
                    </Box>

                    <Box sx={{ mb: 2.5 }}>
                        <Typography variant="caption" sx={{ color: '#94a3b8', display: 'block', mb: 1 }}>Quick add common types:</Typography>
                        <Stack direction="row" gap={0.75} sx={{
  flexWrap: "wrap"
}}>
                            {COMMON_MIME_SUGGESTIONS.map(({ label, value }) => (
                                <Chip key={value} label={label} size="small" clickable
                                      onClick={() => handleAddSuggestion(value)}
                                      disabled={allowedMimes.includes(value)}
                                      sx={{ fontSize: '0.72rem',
                                            bgcolor: allowedMimes.includes(value) ? '#f1f5f9' : '#faf5ff',
                                            color: allowedMimes.includes(value) ? '#94a3b8' : '#5e35b1',
                                            border: '1px solid',
                                            borderColor: allowedMimes.includes(value) ? '#e2e8f0' : '#ddd6fe',
                                            '&:hover': { bgcolor: '#ede9fe' } }} />
                            ))}
                        </Stack>
                    </Box>

                    <Divider sx={{ mb: 2 }} />

                    {allowedMimes.length === 0 ? (
                        <Alert severity="warning" icon={<BlockOutlined />}
                               sx={{ bgcolor: '#fffbeb', border: '1px solid #fde68a', color: '#92400e' }}>
                            No MIME types defined. Add at least one allowed type, or disable restrictions to allow all uploads.
                        </Alert>
                    ) : (
                        <>
                            <Typography variant="caption" fontWeight={600}
                                        sx={{ color: '#475569', textTransform: 'uppercase', letterSpacing: 0.5, display: 'block', mb: 1.5 }}>
                                {allowedMimes.length} allowed type{allowedMimes.length !== 1 ? 's' : ''}
                            </Typography>
                            <List disablePadding>
                                {allowedMimes.map((mime, index) => (
                                    <MimeTypeRow key={`${mime}-${index}`} value={mime} index={index} onDelete={handleDelete} />
                                ))}
                            </List>
                        </>
                    )}
                </Paper>

                <Paper variant="outlined" sx={{ borderRadius: 2, mb: 3, overflow: 'hidden' }}>
                    <Box onClick={() => setShowExamples(p => !p)}
                         sx={{ p: 2, display: 'flex', alignItems: 'center', gap: 1, cursor: 'pointer',
                               bgcolor: '#f8fafc', '&:hover': { bgcolor: '#f1f5f9' } }}>
                        <InfoOutlined sx={{ fontSize: 18, color: '#64748b' }} />
                        <Typography variant="subtitle2" fontWeight={600} sx={{ flex: 1, color: '#334155' }}>Configuration Examples</Typography>
                        {showExamples ? <ExpandLess sx={{ color: '#64748b' }} /> : <ExpandMore sx={{ color: '#64748b' }} />}
                    </Box>
                    <Collapse in={showExamples}>
                        <Box sx={{ p: 3, pt: 2 }}>
                            <Typography variant="body2" fontWeight={600} sx={{ color: '#1e293b', mb: 1 }}>Example 1: Allow all images and PDF files</Typography>
                            <Stack direction="row" gap={1} sx={{
  mb: 2,
  flexWrap: "wrap"
}}>
                                <Chip label="image/*" size="small" sx={{ fontFamily: 'monospace', bgcolor: '#f0fdf4', color: '#166534', border: '1px solid #bbf7d0' }} />
                                <Chip label="application/pdf" size="small" sx={{ fontFamily: 'monospace', bgcolor: '#f0fdf4', color: '#166534', border: '1px solid #bbf7d0' }} />
                            </Stack>
                            <Divider sx={{ mb: 2 }} />
                            <Typography variant="body2" fontWeight={600} sx={{ color: '#1e293b', mb: 1 }}>Example 2: Allow specific image formats only</Typography>
                            <Stack direction="row" gap={1} sx={{
  flexWrap: "wrap"
}}>
                                {['image/jpeg', 'image/png', 'image/gif'].map(m => (
                                    <Chip key={m} label={m} size="small" sx={{ fontFamily: 'monospace', bgcolor: '#eff6ff', color: '#1d4ed8', border: '1px solid #bfdbfe' }} />
                                ))}
                            </Stack>
                        </Box>
                    </Collapse>
                </Paper>
            </Collapse>

            <Box sx={{ display: 'flex', gap: 2, alignItems: 'center' }}>
                <Button variant="contained"
                        startIcon={saving ? <CircularProgress size={16} color="inherit" /> : <SaveOutlined />}
                        onClick={handleSave} disabled={saving || !isDirty}
                        sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none', fontWeight: 600, px: 3 }}>
                    {saving ? 'Saving…' : 'Save'}
                </Button>
                {isDirty && <Typography variant="caption" sx={{ color: '#f59e0b', fontWeight: 600 }}>Unsaved changes</Typography>}
                {!isDirty && !loading && <Typography variant="caption" sx={{ color: '#94a3b8' }}>Changes saved</Typography>}
            </Box>
        </Box>
    );
}

