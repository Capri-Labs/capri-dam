import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, Typography, Button, TextField, IconButton, Paper, Divider,
    CircularProgress, Tooltip, Chip, Stack, Switch,
    Select, MenuItem, Dialog, DialogTitle, DialogContent, DialogActions,
    List, ListItemButton, ListItemText, Alert, InputAdornment
} from '@mui/material';
import {
    AddOutlined, DeleteOutlined, EditOutlined, SaveOutlined,
    CloseOutlined, AutoFixHighOutlined, CropOutlined, PaletteOutlined,
    ImageOutlined, CheckCircleOutlined, InfoOutlined, FolderOpenOutlined
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

// ── Numeric spinner input ─────────────────────────────────────────────────────
function SpinnerInput({ value, onChange, min = 0, max, step = 1, adornment }) {
    const handleStep = (dir) => {
        const next = parseFloat((parseFloat(value || 0) + dir * step).toFixed(4));
        if (min !== undefined && next < min) return;
        if (max !== undefined && next > max) return;
        onChange(next);
    };

    return (
        <Box sx={{ display: 'flex', alignItems: 'stretch', border: '1px solid #e2e8f0', borderRadius: 1, overflow: 'hidden', bgcolor: '#fff' }}>
            <Box sx={{ display: 'flex', flexDirection: 'column', borderRight: '1px solid #e2e8f0' }}>
                <IconButton size="small" onClick={() => handleStep(1)}
                            sx={{ borderRadius: 0, height: 20, py: 0, px: 0.5, color: '#64748b' }}>
                    <Box component="span" sx={{ fontSize: 10, lineHeight: 1 }}>▲</Box>
                </IconButton>
                <IconButton size="small" onClick={() => handleStep(-1)}
                            sx={{ borderRadius: 0, height: 20, py: 0, px: 0.5, color: '#64748b' }}>
                    <Box component="span" sx={{ fontSize: 10, lineHeight: 1 }}>▼</Box>
                </IconButton>
            </Box>
            <TextField
                variant="standard"
                size="small"
                value={value}
                onChange={e => onChange(e.target.value)} slotProps={{input: {
                    disableUnderline: true,
                    endAdornment: adornment
                        ? <InputAdornment position="end"><Typography variant="caption" sx={{ color: '#94a3b8' }}>{adornment}</Typography></InputAdornment>
                        : undefined,
                    sx: { px: 1, fontSize: '0.875rem' }
                } }}
                sx={{ flex: 1 }}
            />
        </Box>
    );
}

// ── Image Profile Edit Dialog ─────────────────────────────────────────────────
function ProfileEditDialog({ open, profile, onClose, onSaved }) {
    const notify = useNotify();
    const isNew  = !profile?.id;

    const [name,                setName]                = useState('');
    const [unsharpAmount,       setUnsharpAmount]       = useState(1.75);
    const [unsharpRadius,       setUnsharpRadius]       = useState(0.2);
    const [unsharpThreshold,    setUnsharpThreshold]    = useState(2);
    const [cropType,            setCropType]            = useState('none');
    const [responsiveCropEnabled, setResponsiveCropEnabled] = useState(false);
    const [responsiveCrops,     setResponsiveCrops]     = useState([]);
    const [swatchEnabled,       setSwatchEnabled]       = useState(false);
    const [swatchWidth,         setSwatchWidth]         = useState(100);
    const [swatchHeight,        setSwatchHeight]        = useState(100);
    const [saving,              setSaving]              = useState(false);

    useEffect(() => {
        if (!open) return;
        if (profile) {
            setName(profile.name || '');
            const um = profile.unsharp_mask || {};
            setUnsharpAmount(um.amount ?? 1.75);
            setUnsharpRadius(um.radius ?? 0.2);
            setUnsharpThreshold(um.threshold ?? 2);
            setCropType(profile.crop_type || 'none');
            setResponsiveCropEnabled(profile.responsive_crop_enabled || false);
            setResponsiveCrops(profile.responsive_crops || []);
            setSwatchEnabled(profile.swatch_enabled || false);
            setSwatchWidth(profile.swatch_width || 100);
            setSwatchHeight(profile.swatch_height || 100);
        } else {
            setName(''); setUnsharpAmount(1.75); setUnsharpRadius(0.2); setUnsharpThreshold(2);
            setCropType('none'); setResponsiveCropEnabled(false); setResponsiveCrops([]);
            setSwatchEnabled(false); setSwatchWidth(100); setSwatchHeight(100);
        }
    }, [open, profile]);

    const addCrop = () => setResponsiveCrops(prev => [...prev, { name: '', width: 800, height: 600 }]);

    const updateCrop = (idx, field, val) =>
        setResponsiveCrops(prev => prev.map((c, i) => i === idx ? { ...c, [field]: val } : c));

    const removeCrop = (idx) =>
        setResponsiveCrops(prev => prev.filter((_, i) => i !== idx));

    const handleSave = async () => {
        if (!name.trim()) { notify('Profile name is required.', 'error'); return; }
        setSaving(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const payload   = {
                image_profile: {
                    name,
                    unsharp_mask:            { amount: parseFloat(unsharpAmount), radius: parseFloat(unsharpRadius), threshold: parseInt(unsharpThreshold) },
                    crop_type:               cropType,
                    responsive_crop_enabled: responsiveCropEnabled,
                    responsive_crops:        responsiveCrops,
                    swatch_enabled:          swatchEnabled,
                    swatch_width:            parseInt(swatchWidth),
                    swatch_height:           parseInt(swatchHeight),
                }
            };

            const url    = isNew ? '/api/v1/image_profiles' : `/api/v1/image_profiles/${profile.id}`;
            const method = isNew ? 'POST' : 'PATCH';

            const res  = await fetch(url, {
                method,
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(payload)
            });
            const data = await res.json();
            if (!res.ok) throw new Error((data.errors || [data.error]).join(', '));

            notify(`Profile "${data.name}" ${isNew ? 'created' : 'updated'}.`, 'success');
            onSaved(data);
        } catch (err) {
            notify(err.message, 'error');
        } finally {
            setSaving(false);
        }
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth slotProps={{paper: { sx: { borderRadius: 3, height: '90vh' } } }}>
            {/* Header */}
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                               bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0', py: 1.5 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <ImageOutlined sx={{ color: '#7c3aed' }} />
                    <Typography fontWeight={700}>
                        {isNew ? 'Create Image Processing Profile' : 'Edit Image Processing Profile'}
                    </Typography>
                </Box>
                <Stack direction="row" spacing={1}>
                    <Button variant="outlined" onClick={onClose} sx={{ textTransform: 'none' }}>Cancel</Button>
                    <Button variant="contained" onClick={handleSave} disabled={saving}
                            startIcon={saving ? <CircularProgress size={16} color="inherit" /> : <SaveOutlined />}
                            sx={{ bgcolor: '#1d4ed8', textTransform: 'none', fontWeight: 700 }}>
                        {saving ? 'Saving…' : 'Save'}
                    </Button>
                </Stack>
            </DialogTitle>

            <DialogContent sx={{ overflow: 'auto', p: 4 }}>
                {/* Profile Name */}
                <Typography variant="h6" fontWeight={600} sx={{ mb: 2, color: '#1e293b' }}>
                    {isNew ? 'New Profile' : name}
                </Typography>

                <Typography variant="body2" fontWeight={700} sx={{ mb: 0.75, color: '#334155' }}>
                    Name <Typography component="span" color="error">*</Typography>
                </Typography>
                <TextField fullWidth size="small" value={name} onChange={e => setName(e.target.value)}
                           placeholder="e.g. Smart Swatches" sx={{ mb: 3 }} />

                <Divider sx={{ mb: 3 }} />

                {/* ── Unsharp Mask ── */}
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                    <AutoFixHighOutlined sx={{ color: '#7c3aed', fontSize: 20 }} />
                    <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b' }}>Unsharp Mask</Typography>
                    <Tooltip title="Applied only to downscaled renditions (>50% downsampled). Uses the same options as Photoshop's Unsharp Mask filter.">
                        <InfoOutlined sx={{ fontSize: 16, color: '#94a3b8', cursor: 'help' }} />
                    </Tooltip>
                </Box>

                <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 3, mb: 3 }}>
                    {[
                        { label: 'Amount', value: unsharpAmount, onChange: setUnsharpAmount, step: 0.25, max: 5, hint: '0–5, default 1.75' },
                        { label: 'Radius', value: unsharpRadius, onChange: setUnsharpRadius, step: 0.1,  max: 250, hint: '0–250, default 0.2' },
                        { label: 'Threshold', value: unsharpThreshold, onChange: setUnsharpThreshold, step: 1, max: 255, hint: '0–255, default 2' },
                    ].map(({ label, value, onChange, step, max, hint }) => (
                        <Box key={label}>
                            <Typography variant="body2" fontWeight={700} sx={{ mb: 0.75, color: '#334155' }}>
                                {label} <Typography component="span" color="error">*</Typography>
                            </Typography>
                            <SpinnerInput value={value} onChange={onChange} step={step} max={max} min={0} />
                            <Typography variant="caption" sx={{ color: '#94a3b8' }}>{hint}</Typography>
                        </Box>
                    ))}
                </Box>

                <Divider sx={{ mb: 3 }} />

                {/* ── Cropping Options ── */}
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                    <CropOutlined sx={{ color: '#7c3aed', fontSize: 20 }} />
                    <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b' }}>Cropping Options</Typography>
                </Box>

                <Box sx={{ mb: 3 }}>
                    <Typography variant="body2" fontWeight={700} sx={{ mb: 0.75, color: '#334155' }}>Type</Typography>
                    <Select variant="outlined" value={cropType} onChange={e => setCropType(e.target.value)}
                            fullWidth size="small" sx={{ bgcolor: '#fff' }}>
                        <MenuItem value="none">None</MenuItem>
                        <MenuItem value="smart_crop">Smart Crop</MenuItem>
                    </Select>
                </Box>

                <Divider sx={{ mb: 3 }} />

                {/* ── Responsive Image Crop ── */}
                <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <CropOutlined sx={{ color: '#7c3aed', fontSize: 20 }} />
                        <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b' }}>Responsive Image Crop</Typography>
                    </Box>
                    <Switch checked={responsiveCropEnabled} onChange={e => setResponsiveCropEnabled(e.target.checked)}
                            sx={{ '& .MuiSwitch-switchBase.Mui-checked': { color: '#1d4ed8' },
                                  '& .MuiSwitch-switchBase.Mui-checked + .MuiSwitch-track': { bgcolor: '#1d4ed8' } }} />
                </Box>

                {responsiveCropEnabled && (
                    <>
                        {responsiveCrops.length > 0 && (
                            <Box sx={{ display: 'grid', gridTemplateColumns: '1fr auto auto auto', gap: 1.5,
                                       mb: 1, px: 0.5 }}>
                                <Typography variant="caption" fontWeight={700} sx={{ color: '#64748b' }}>Name <Typography component="span" color="error">*</Typography></Typography>
                                <Typography variant="caption" fontWeight={700} sx={{ color: '#64748b' }}>Width <Typography component="span" color="error">*</Typography></Typography>
                                <Typography variant="caption" fontWeight={700} sx={{ color: '#64748b' }}>Height <Typography component="span" color="error">*</Typography></Typography>
                                <Box />
                            </Box>
                        )}

                        {responsiveCrops.map((crop, idx) => (
                            <Box key={idx} sx={{ display: 'grid', gridTemplateColumns: '1fr auto auto auto',
                                                 gap: 1.5, mb: 1.5, alignItems: 'center' }}>
                                <TextField size="small" value={crop.name}
                                           onChange={e => updateCrop(idx, 'name', e.target.value)}
                                           placeholder="e.g. Large" />
                                <SpinnerInput value={crop.width} onChange={v => updateCrop(idx, 'width', v)} min={1} step={10} />
                                <SpinnerInput value={crop.height} onChange={v => updateCrop(idx, 'height', v)} min={1} step={10} />
                                <Tooltip title="Remove crop">
                                    <IconButton size="small" onClick={() => removeCrop(idx)}
                                                sx={{ color: '#94a3b8', '&:hover': { color: '#ef4444' } }}>
                                        <DeleteOutlined fontSize="small" />
                                    </IconButton>
                                </Tooltip>
                            </Box>
                        ))}

                        <Button variant="outlined" startIcon={<AddOutlined />} onClick={addCrop}
                                sx={{ mt: 1, textTransform: 'none', color: '#475569', borderColor: '#e2e8f0',
                                      '&:hover': { bgcolor: '#f8fafc' } }}>
                            Add Crop
                        </Button>
                    </>
                )}

                <Divider sx={{ mb: 3, mt: 3 }} />

                {/* ── Color and Image Swatch ── */}
                <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <PaletteOutlined sx={{ color: '#7c3aed', fontSize: 20 }} />
                        <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b' }}>Color and Image Swatch</Typography>
                    </Box>
                    <Switch checked={swatchEnabled} onChange={e => setSwatchEnabled(e.target.checked)}
                            sx={{ '& .MuiSwitch-switchBase.Mui-checked': { color: '#1d4ed8' },
                                  '& .MuiSwitch-switchBase.Mui-checked + .MuiSwitch-track': { bgcolor: '#1d4ed8' } }} />
                </Box>

                {swatchEnabled && (
                    <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 3 }}>
                        {[
                            { label: 'Width', value: swatchWidth, onChange: setSwatchWidth },
                            { label: 'Height', value: swatchHeight, onChange: setSwatchHeight },
                        ].map(({ label, value, onChange }) => (
                            <Box key={label}>
                                <Typography variant="body2" fontWeight={700} sx={{ mb: 0.75, color: '#334155' }}>
                                    {label} <Typography component="span" color="error">*</Typography>
                                </Typography>
                                <SpinnerInput value={value} onChange={onChange} min={1} step={10} adornment="px" />
                            </Box>
                        ))}
                    </Box>
                )}

                <Alert severity="info" icon={<InfoOutlined />}
                       sx={{ mt: 3, bgcolor: '#f0f9ff', border: '1px solid #bae6fd', fontSize: '0.8rem' }}>
                    Image Profiles are <strong>not applicable</strong> to PDF, animated GIF, or INDD files.
                    The unsharp mask only applies to renditions downsampled more than 50%.
                </Alert>
            </DialogContent>
        </Dialog>
    );
}

// ── Apply Image Profile Dialog ────────────────────────────────────────────────
function ApplyImageProfileDialog({ open, onClose, folderId, folderName }) {
    const notify        = useNotify();
    const [profiles, setProfiles] = useState([]);
    const [loading,  setLoading]  = useState(false);
    const [selected, setSelected] = useState(null);
    const [applying, setApplying] = useState(false);

    useEffect(() => {
        if (!open) return;
        setLoading(true);
        setSelected(null);
        fetch('/api/v1/image_profiles')
            .then(r => r.json())
            .then(data => setProfiles(Array.isArray(data) ? data : []))
            .catch(() => notify('Failed to load image profiles.', 'error'))
            .finally(() => setLoading(false));
    }, [open]);

    const handleApply = async () => {
        if (!selected) return;
        setApplying(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch(`/api/v1/image_profiles/${selected.id}/apply_to_folder`, {
                method:  'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body:    JSON.stringify({ folder_id: folderId }),
            });
            if (!res.ok) throw new Error('Apply failed');
            notify(`"${selected.name}" profile applied to folder "${folderName}".`, 'success');
            onClose(true);
        } catch {
            notify('Failed to apply image profile.', 'error');
        } finally {
            setApplying(false);
        }
    };

    return (
        <Dialog open={open} onClose={() => onClose(false)} maxWidth="sm" fullWidth slotProps={{paper: { sx: { borderRadius: 3 } } }}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1.5,
                               borderBottom: '1px solid #f1f5f9', py: 1.5, bgcolor: '#faf5ff' }}>
                <ImageOutlined sx={{ color: '#7c3aed' }} />
                <Box sx={{ flex: 1 }}>
                    <Typography fontWeight={700}>Apply Image Profile</Typography>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        Folder: <strong>{folderName}</strong>
                    </Typography>
                </Box>
                <IconButton size="small" onClick={() => onClose(false)}>
                    <CloseOutlined fontSize="small" />
                </IconButton>
            </DialogTitle>

            <DialogContent sx={{ pt: 2.5 }}>
                <Alert severity="info" sx={{ mb: 2, fontSize: '0.8rem' }}>
                    Applying a profile will automatically crop and process images uploaded to this folder.
                    Not applicable to PDF, animated GIF, or INDD files.
                </Alert>

                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1.5, color: '#334155' }}>
                    Available Profiles
                </Typography>

                {loading ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 3 }}>
                        <CircularProgress size={24} sx={{ color: '#7c3aed' }} />
                    </Box>
                ) : profiles.length === 0 ? (
                    <Typography variant="body2" sx={{ color: '#94a3b8' }}>
                        No image profiles available. Create one under Tools → Assets → Asset Configurations → Image Profiles.
                    </Typography>
                ) : (
                    <List disablePadding>
                        {profiles.map(p => (
                            <ListItemButton
                                key={p.id}
                                selected={selected?.id === p.id}
                                onClick={() => setSelected(p)}
                                sx={{
                                    borderRadius: 2, mb: 0.75,
                                    border: selected?.id === p.id ? '2px solid #7c3aed' : '1px solid #e2e8f0',
                                    bgcolor: selected?.id === p.id ? '#faf5ff' : '#fff',
                                }}
                            >
                                <ListItemText
                                    primary={
                                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                            <Typography variant="body2" fontWeight={selected?.id === p.id ? 700 : 500}>
                                                {p.name}
                                            </Typography>
                                            {p.crop_type === 'smart_crop' && (
                                                <Chip label="Smart Crop" size="small"
                                                      sx={{ fontSize: '0.65rem', height: 18, bgcolor: '#ede9fe', color: '#6d28d9' }} />
                                            )}
                                            {p.swatch_enabled && (
                                                <Chip label="Swatch" size="small"
                                                      sx={{ fontSize: '0.65rem', height: 18, bgcolor: '#fce7f3', color: '#9d174d' }} />
                                            )}
                                            {p.responsive_crop_enabled && (
                                                <Chip label={`${(p.responsive_crops || []).length} crops`} size="small"
                                                      sx={{ fontSize: '0.65rem', height: 18, bgcolor: '#dbeafe', color: '#1d4ed8' }} />
                                            )}
                                        </Box>
                                    }
                                    secondary={`Unsharp: amount ${p.unsharp_mask?.amount ?? 1.75} · radius ${p.unsharp_mask?.radius ?? 0.2}`}
                                    slotProps={{ secondary: { sx: { fontSize: '0.72rem' } } }}
                                />
                                {selected?.id === p.id && <CheckCircleOutlined sx={{ color: '#7c3aed' }} />}
                            </ListItemButton>
                        ))}
                    </List>
                )}
            </DialogContent>

            <DialogActions sx={{ px: 3, py: 2, borderTop: '1px solid #f1f5f9' }}>
                <Button onClick={() => onClose(false)} sx={{ textTransform: 'none', color: '#64748b' }}>Cancel</Button>
                <Button variant="contained" onClick={handleApply}
                        disabled={!selected || applying}
                        sx={{ bgcolor: '#7c3aed', '&:hover': { bgcolor: '#6d28d9' }, textTransform: 'none' }}>
                    {applying ? 'Applying…' : `Apply "${selected?.name ?? ''}"`}
                </Button>
            </DialogActions>
        </Dialog>
    );
}

// ── Profile Detail Panel ──────────────────────────────────────────────────────
function ProfileDetailPanel({ profile, onEdit, onDelete }) {
    const [folders, setFolders] = useState([]);

    useEffect(() => {
        if (!profile) return;
        fetch(`/api/v1/image_profiles/${profile.id}/folders`)
            .then(r => r.ok ? r.json() : [])
            .then(setFolders)
            .catch(() => {});
    }, [profile?.id]);

    if (!profile) {
        return (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
                       color: '#94a3b8', flexDirection: 'column', gap: 2 }}>
                <ImageOutlined sx={{ fontSize: 64, opacity: 0.3 }} />
                <Typography variant="body2">Select a profile to inspect, edit, or delete it</Typography>
            </Box>
        );
    }

    const um = profile.unsharp_mask || {};

    return (
        <Box sx={{ flex: 1, overflow: 'auto', p: 3 }}>
            <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', mb: 3 }}>
                <Box>
                    <Typography variant="h5" fontWeight={700} sx={{ color: '#1e293b', mb: 0.5 }}>{profile.name}</Typography>
                    <Stack direction="row" spacing={1} sx={{
  flexWrap: "wrap"
}}>
                        {profile.crop_type === 'smart_crop' && (
                            <Chip label="Smart Crop" size="small"
                                  sx={{ bgcolor: '#ede9fe', color: '#6d28d9', fontSize: '0.7rem' }} />
                        )}
                        {profile.swatch_enabled && (
                            <Chip label="Swatch" size="small"
                                  sx={{ bgcolor: '#fce7f3', color: '#9d174d', fontSize: '0.7rem' }} />
                        )}
                        {profile.responsive_crop_enabled && (
                            <Chip label={`${(profile.responsive_crops || []).length} responsive crops`} size="small"
                                  sx={{ bgcolor: '#dbeafe', color: '#1d4ed8', fontSize: '0.7rem' }} />
                        )}
                        <Chip label={`${profile.folder_count ?? 0} folder${profile.folder_count !== 1 ? 's' : ''}`} size="small"
                              sx={{ bgcolor: '#f1f5f9', color: '#64748b', fontSize: '0.7rem' }} />
                    </Stack>
                </Box>
                <Stack direction="row" spacing={1}>
                    <Button variant="contained" size="small" startIcon={<EditOutlined />} onClick={() => onEdit(profile)}
                            sx={{ bgcolor: '#7c3aed', '&:hover': { bgcolor: '#6d28d9' }, textTransform: 'none' }}>
                        Edit
                    </Button>
                    <Tooltip title="Delete profile">
                        <IconButton size="small" onClick={() => onDelete(profile)}
                                    sx={{ border: '1px solid #fecaca', color: '#ef4444' }}>
                            <DeleteOutlined fontSize="small" />
                        </IconButton>
                    </Tooltip>
                </Stack>
            </Box>

            <Divider sx={{ mb: 3 }} />

            {/* Unsharp Mask */}
            <Paper variant="outlined" sx={{ p: 2, mb: 3, borderRadius: 2 }}>
                <Typography variant="caption" fontWeight={700} sx={{ color: '#475569', textTransform: 'uppercase', letterSpacing: 0.5, display: 'flex', alignItems: 'center', gap: 0.5 }}>
                    <AutoFixHighOutlined sx={{ fontSize: 14 }} /> Unsharp Mask
                </Typography>
                <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 2, mt: 1.5 }}>
                    {[
                        { label: 'Amount',    value: um.amount ?? 1.75,  desc: 'Contrast intensity (0–5)' },
                        { label: 'Radius',    value: um.radius ?? 0.2,   desc: 'Pixel radius (0–250)' },
                        { label: 'Threshold', value: um.threshold ?? 2,  desc: 'Contrast threshold (0–255)' },
                    ].map(({ label, value, desc }) => (
                        <Box key={label} sx={{ textAlign: 'center', p: 1.5, bgcolor: '#f8fafc', borderRadius: 1, border: '1px solid #e2e8f0' }}>
                            <Typography variant="h5" fontWeight={700} sx={{ color: '#1e293b' }}>{value}</Typography>
                            <Typography variant="caption" sx={{ color: '#64748b', fontWeight: 600 }}>{label}</Typography>
                            <Typography variant="caption" sx={{ display: 'block', color: '#94a3b8', fontSize: '0.65rem' }}>{desc}</Typography>
                        </Box>
                    ))}
                </Box>
            </Paper>

            {/* Responsive Crops */}
            {profile.responsive_crop_enabled && (profile.responsive_crops || []).length > 0 && (
                <Paper variant="outlined" sx={{ p: 2, mb: 3, borderRadius: 2 }}>
                    <Typography variant="caption" fontWeight={700} sx={{ color: '#475569', textTransform: 'uppercase', letterSpacing: 0.5, display: 'flex', alignItems: 'center', gap: 0.5, mb: 1.5 }}>
                        <CropOutlined sx={{ fontSize: 14 }} /> Responsive Crops
                    </Typography>
                    <Stack spacing={0.75}>
                        {profile.responsive_crops.map((crop, i) => (
                            <Box key={i} sx={{ display: 'flex', alignItems: 'center', gap: 2, p: 1,
                                              bgcolor: '#f8fafc', borderRadius: 1, border: '1px solid #e2e8f0' }}>
                                <Typography variant="body2" fontWeight={600} sx={{ flex: 1 }}>{crop.name}</Typography>
                                <Chip label={`${crop.width} × ${crop.height}`} size="small"
                                      sx={{ fontFamily: 'monospace', fontSize: '0.72rem', bgcolor: '#e0e7ff', color: '#3730a3' }} />
                            </Box>
                        ))}
                    </Stack>
                </Paper>
            )}

            {/* Swatch */}
            {profile.swatch_enabled && (
                <Paper variant="outlined" sx={{ p: 2, mb: 3, borderRadius: 2 }}>
                    <Typography variant="caption" fontWeight={700} sx={{ color: '#475569', textTransform: 'uppercase', letterSpacing: 0.5, mb: 1.5, display: 'flex', alignItems: 'center', gap: 0.5 }}>
                        <PaletteOutlined sx={{ fontSize: 14 }} /> Color & Image Swatch
                    </Typography>
                    <Stack direction="row" spacing={2}>
                        <Chip label={`Width: ${profile.swatch_width}px`}  size="small" sx={{ fontFamily: 'monospace', bgcolor: '#fce7f3', color: '#9d174d' }} />
                        <Chip label={`Height: ${profile.swatch_height}px`} size="small" sx={{ fontFamily: 'monospace', bgcolor: '#fce7f3', color: '#9d174d' }} />
                    </Stack>
                </Paper>
            )}

            {/* Applied Folders */}
            {folders.length > 0 && (
                <>
                    <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1, color: '#334155' }}>
                        Applied to Folders
                    </Typography>
                    <Stack spacing={0.75}>
                        {folders.map(f => (
                            <Box key={f.id} sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                <FolderOpenOutlined sx={{ fontSize: 16, color: '#f59e0b' }} />
                                <Typography variant="body2" sx={{ color: '#475569' }}>{f.name}</Typography>
                            </Box>
                        ))}
                    </Stack>
                </>
            )}
        </Box>
    );
}

// ── ImageProfilesManager (main) ───────────────────────────────────────────────
export default function ImageProfilesManager() {
    const notify = useNotify();
    const [profiles,     setProfiles]     = useState([]);
    const [loading,      setLoading]      = useState(true);
    const [selected,     setSelected]     = useState(null);
    const [dialogOpen,   setDialogOpen]   = useState(false);
    const [editingProfile, setEditingProfile] = useState(null);

    const fetchProfiles = useCallback(async () => {
        setLoading(true);
        try {
            const res  = await fetch('/api/v1/image_profiles');
            const data = await res.json();
            setProfiles(Array.isArray(data) ? data : []);
            if (selected) {
                const refreshed = (Array.isArray(data) ? data : []).find(p => p.id === selected.id);
                setSelected(refreshed ?? null);
            }
        } catch {
            notify('Failed to load image profiles.', 'error');
        } finally {
            setLoading(false);
        }
    }, []); // eslint-disable-line

    useEffect(() => { fetchProfiles(); }, [fetchProfiles]);

    const handleEdit = (profile) => { setEditingProfile(profile); setDialogOpen(true); };
    const handleNew  = () => { setEditingProfile(null); setDialogOpen(true); };

    const handleSaved = async (savedProfile) => {
        setDialogOpen(false);
        await fetchProfiles();
        setSelected(savedProfile);
    };

    const handleDelete = async (profile) => {
        if (!window.confirm(`Delete image profile "${profile.name}"? This will also remove all folder assignments.`)) return;
        const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
        const res = await fetch(`/api/v1/image_profiles/${profile.id}`, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': csrfToken },
        });
        if (!res.ok) { notify('Delete failed.', 'error'); return; }
        notify(`"${profile.name}" deleted.`, 'success');
        setSelected(null);
        await fetchProfiles();
    };

    return (
        <Box sx={{ display: 'flex', height: '100%', bgcolor: '#f8fafc' }}>
            {/* Left: profile list */}
            <Box sx={{ width: '28%', flexShrink: 0, bgcolor: '#fff', borderRight: '1px solid #e2e8f0',
                       display: 'flex', flexDirection: 'column' }}>
                <Box sx={{ p: 2, borderBottom: '1px solid #f1f5f9', display: 'flex',
                           alignItems: 'center', justifyContent: 'space-between' }}>
                    <Box>
                        <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>Image Profiles</Typography>
                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>{profiles.length} profile{profiles.length !== 1 ? 's' : ''}</Typography>
                    </Box>
                    <Tooltip title="Create new profile">
                        <IconButton size="small" onClick={handleNew}
                                    sx={{ bgcolor: '#7c3aed', color: '#fff', '&:hover': { bgcolor: '#6d28d9' }, width: 28, height: 28 }}>
                            <AddOutlined fontSize="small" />
                        </IconButton>
                    </Tooltip>
                </Box>

                <Box sx={{ flex: 1, overflow: 'auto', py: 1 }}>
                    {loading ? (
                        <Box sx={{ display: 'flex', justifyContent: 'center', pt: 4 }}>
                            <CircularProgress size={28} sx={{ color: '#7c3aed' }} />
                        </Box>
                    ) : profiles.length === 0 ? (
                        <Box sx={{ p: 2, textAlign: 'center' }}>
                            <ImageOutlined sx={{ fontSize: 40, color: '#e2e8f0', mb: 1 }} />
                            <Typography variant="body2" sx={{ color: '#94a3b8' }}>No profiles yet.</Typography>
                            <Button size="small" startIcon={<AddOutlined />} onClick={handleNew}
                                    sx={{ mt: 1, textTransform: 'none', color: '#7c3aed' }}>
                                Create Profile
                            </Button>
                        </Box>
                    ) : (
                        <List disablePadding>
                            {profiles.map(p => (
                                <ListItemButton
                                    key={p.id}
                                    selected={selected?.id === p.id}
                                    onClick={() => setSelected(p)}
                                    sx={{
                                        mx: 0.5, borderRadius: '8px', mb: 0.25,
                                        bgcolor: selected?.id === p.id ? '#f5f3ff' : 'transparent',
                                        '&.Mui-selected': { bgcolor: '#f5f3ff', color: '#7c3aed' },
                                        '&:hover': { bgcolor: '#faf5ff' },
                                    }}
                                >
                                    <ListItemText
                                        primary={
                                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75 }}>
                                                <ImageOutlined sx={{ fontSize: 15, color: selected?.id === p.id ? '#7c3aed' : '#94a3b8' }} />
                                                <Typography variant="body2" fontWeight={selected?.id === p.id ? 600 : 400}>
                                                    {p.name}
                                                </Typography>
                                            </Box>
                                        }
                                        secondary={
                                            <Stack direction="row" spacing={0.5} sx={{ mt: 0.25, flexWrap: 'wrap', gap: 0.25 }}>
                                                {p.crop_type === 'smart_crop' && (
                                                    <Chip label="Smart Crop" size="small"
                                                          sx={{ fontSize: '0.6rem', height: 14, bgcolor: '#ede9fe', color: '#6d28d9' }} />
                                                )}
                                                {p.swatch_enabled && (
                                                    <Chip label="Swatch" size="small"
                                                          sx={{ fontSize: '0.6rem', height: 14, bgcolor: '#fce7f3', color: '#9d174d' }} />
                                                )}
                                                {p.folder_count > 0 && (
                                                    <Chip label={`${p.folder_count}f`} size="small"
                                                          sx={{ fontSize: '0.6rem', height: 14, bgcolor: '#f1f5f9', color: '#64748b' }} />
                                                )}
                                            </Stack>
                                        }
                                    />
                                </ListItemButton>
                            ))}
                        </List>
                    )}
                </Box>
            </Box>

            {/* Right: detail */}
            <Box sx={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
                <Box sx={{ px: 3, py: 2, bgcolor: '#fff', borderBottom: '1px solid #e2e8f0',
                           display: 'flex', alignItems: 'center', gap: 2 }}>
                    <ImageOutlined sx={{ color: '#7c3aed', fontSize: 22 }} />
                    <Box sx={{ flex: 1 }}>
                        <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b', lineHeight: 1.2 }}>
                            Image Profiles
                        </Typography>
                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                            Tools › Assets › Asset Configurations › Image Profiles
                        </Typography>
                    </Box>
                    <Button variant="contained" size="small" startIcon={<AddOutlined />} onClick={handleNew}
                            sx={{ bgcolor: '#7c3aed', '&:hover': { bgcolor: '#6d28d9' }, textTransform: 'none' }}>
                        Create Profile
                    </Button>
                </Box>

                <ProfileDetailPanel
                    profile={selected}
                    onEdit={handleEdit}
                    onDelete={handleDelete}
                />
            </Box>

            {/* Edit / Create Dialog */}
            <ProfileEditDialog
                open={dialogOpen}
                profile={editingProfile}
                onClose={() => setDialogOpen(false)}
                onSaved={handleSaved}
            />
        </Box>
    );
}

export { ApplyImageProfileDialog };

