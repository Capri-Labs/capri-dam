import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Typography, Button, TextField, IconButton, Paper, Divider,
    CircularProgress, Tooltip, Chip, Stack, Switch, Tab, Tabs,
    Select, MenuItem, Dialog, DialogTitle, DialogContent, DialogActions,
    List, ListItemButton, ListItemText, Alert, InputAdornment, Collapse,
    FormControlLabel, Checkbox
} from '@mui/material';
import {
    AddOutlined, DeleteOutlined, EditOutlined, SaveOutlined,
    CloseOutlined, VideoFileOutlined, CheckCircleOutlined, InfoOutlined,
    FolderOpenOutlined, ContentCopyOutlined, WarningAmberOutlined,
    ExpandMoreOutlined, ExpandLessOutlined, TuneOutlined, SpeedOutlined
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const DEFAULT_ADAPTIVE_PRESETS = [
    { name: '360p',  height: 360,  video_bitrate_kbps: 730,  frame_rate_fps: 30, audio_codec: 'he_aac', audio_bitrate_kbps: 128, keep_aspect_ratio: true,  video_format_codec: 'h264', two_pass_encoding: false, constant_bitrate: false, h264_profile: null, audio_sampling_rate: null, advanced_params: {} },
    { name: '540p',  height: 540,  video_bitrate_kbps: 2000, frame_rate_fps: 30, audio_codec: 'he_aac', audio_bitrate_kbps: 128, keep_aspect_ratio: true,  video_format_codec: 'h264', two_pass_encoding: false, constant_bitrate: false, h264_profile: null, audio_sampling_rate: null, advanced_params: {} },
    { name: '720p',  height: 720,  video_bitrate_kbps: 3000, frame_rate_fps: 30, audio_codec: 'he_aac', audio_bitrate_kbps: 128, keep_aspect_ratio: true,  video_format_codec: 'h264', two_pass_encoding: false, constant_bitrate: false, h264_profile: null, audio_sampling_rate: null, advanced_params: {} },
];

const EMPTY_PRESET = {
    name: '', video_format_codec: 'h264', width: null, height: 480,
    keep_aspect_ratio: true, video_bitrate_kbps: 1500, frame_rate_fps: 30,
    audio_codec: 'he_aac', audio_bitrate_kbps: 128,
    two_pass_encoding: false, constant_bitrate: false,
    h264_profile: null, audio_sampling_rate: null,
    advanced_params: {},
};

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────
function NumInput({ label, value, onChange, min = 0, step = 1, suffix, nullable = false, helperText }) {
    const display = value === null || value === undefined ? '' : value;
    return (
        <Box>
            {label && (
                <Typography variant="body2" fontWeight={700} sx={{ mb: 0.5, color: '#334155', fontSize: '0.78rem' }}>
                    {label}
                </Typography>
            )}
            <TextField
                size="small"
                value={display}
                placeholder={nullable ? 'auto' : String(min)}
                onChange={e => {
                    const v = e.target.value;
                    if (nullable && v === '') { onChange(null); return; }
                    const n = Number(v);
                    if (!isNaN(n)) onChange(n);
                }}
                InputProps={{
                    endAdornment: suffix
                        ? <InputAdornment position="end"><Typography variant="caption" sx={{ color: '#94a3b8' }}>{suffix}</Typography></InputAdornment>
                        : undefined
                }}
                sx={{ width: '100%', '& .MuiInputBase-input': { fontSize: '0.82rem' } }}
            />
            {helperText && (
                <Typography variant="caption" sx={{ color: '#94a3b8', fontSize: '0.68rem' }}>{helperText}</Typography>
            )}
        </Box>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Single Encoding Preset Editor (inline row expanded from the presets table)
// ─────────────────────────────────────────────────────────────────────────────
function PresetRow({ preset, idx, onChange, onRemove }) {
    const [expanded, setExpanded]     = useState(false);
    const [activeTab, setActiveTab]   = useState(0);

    const up = (field, val) => onChange(idx, { ...preset, [field]: val });

    return (
        <Paper variant="outlined" sx={{ mb: 1.5, borderRadius: 2, overflow: 'hidden' }}>
            {/* Row header */}
            <Box
                onClick={() => setExpanded(e => !e)}
                sx={{
                    display: 'flex', alignItems: 'center', gap: 1.5,
                    px: 2, py: 1, bgcolor: expanded ? '#f5f3ff' : '#fafafa',
                    cursor: 'pointer', borderBottom: expanded ? '1px solid #e2e8f0' : 'none',
                }}
            >
                <VideoFileOutlined sx={{ fontSize: 18, color: expanded ? '#7c3aed' : '#94a3b8' }} />
                <Box sx={{ flex: 1 }}>
                    <Typography variant="body2" fontWeight={600} sx={{ color: '#1e293b', lineHeight: 1.2 }}>
                        {preset.name || `Preset ${idx + 1}`}
                    </Typography>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        {preset.video_format_codec?.toUpperCase()} · {preset.width ?? 'auto'} × {preset.height}px ·{' '}
                        {preset.video_bitrate_kbps} Kbps · {preset.frame_rate_fps} fps · {preset.audio_codec?.toUpperCase()} {preset.audio_bitrate_kbps} Kbps
                    </Typography>
                </Box>
                <Tooltip title="Remove preset">
                    <IconButton
                        size="small"
                        onClick={e => { e.stopPropagation(); onRemove(idx); }}
                        sx={{ color: '#94a3b8', '&:hover': { color: '#ef4444' }, mr: 0.5 }}
                    >
                        <DeleteOutlined fontSize="small" />
                    </IconButton>
                </Tooltip>
                {expanded ? <ExpandLessOutlined sx={{ color: '#94a3b8', fontSize: 18 }} /> : <ExpandMoreOutlined sx={{ color: '#94a3b8', fontSize: 18 }} />}
            </Box>

            {/* Expanded body */}
            <Collapse in={expanded}>
                <Box sx={{ p: 2 }}>
                    <Tabs value={activeTab} onChange={(_, v) => setActiveTab(v)} sx={{ mb: 2, minHeight: 36, '& .MuiTab-root': { minHeight: 36, py: 0, textTransform: 'none', fontSize: '0.8rem' } }}>
                        <Tab label="Basic" />
                        <Tab label="Advanced" />
                    </Tabs>

                    {activeTab === 0 && (
                        <>
                            {/* Name */}
                            <Box sx={{ mb: 2 }}>
                                <Typography variant="body2" fontWeight={700} sx={{ mb: 0.5, color: '#334155', fontSize: '0.78rem' }}>
                                    Preset Name <Typography component="span" color="error">*</Typography>
                                </Typography>
                                <TextField
                                    size="small" fullWidth value={preset.name}
                                    onChange={e => up('name', e.target.value)}
                                    placeholder="e.g. 720p HD"
                                    sx={{ '& .MuiInputBase-input': { fontSize: '0.82rem' } }}
                                />
                            </Box>

                            {/* Video codec */}
                            <Box sx={{ mb: 2 }}>
                                <Typography variant="body2" fontWeight={700} sx={{ mb: 0.5, color: '#334155', fontSize: '0.78rem' }}>
                                    Video Format Codec
                                </Typography>
                                <Select size="small" fullWidth value={preset.video_format_codec}
                                        onChange={e => up('video_format_codec', e.target.value)}
                                        sx={{ fontSize: '0.82rem' }}>
                                    <MenuItem value="h264">MP4 H.264 (.mp4)</MenuItem>
                                </Select>
                            </Box>

                            {/* Size */}
                            <Box sx={{ mb: 2 }}>
                                <Typography variant="body2" fontWeight={700} sx={{ mb: 1, color: '#334155', fontSize: '0.78rem' }}>
                                    Video Size
                                </Typography>
                                <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 2 }}>
                                    <NumInput label="Width (px)" value={preset.width} onChange={v => up('width', v)}
                                              nullable helperText="Leave blank for auto-scale" />
                                    <NumInput label="Height (px)" value={preset.height} onChange={v => up('height', v)}
                                              min={1} helperText="e.g. 360, 540, 720" />
                                </Box>
                                <FormControlLabel
                                    control={
                                        <Checkbox size="small" checked={preset.keep_aspect_ratio}
                                                  onChange={e => up('keep_aspect_ratio', e.target.checked)}
                                                  sx={{ color: '#7c3aed', '&.Mui-checked': { color: '#7c3aed' } }} />
                                    }
                                    label={<Typography variant="caption" sx={{ color: '#334155' }}>Keep Aspect Ratio</Typography>}
                                    sx={{ mt: 0.5 }}
                                />
                            </Box>

                            {/* Video bitrate + fps */}
                            <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 2, mb: 2 }}>
                                <NumInput label="Video Bitrate" value={preset.video_bitrate_kbps} onChange={v => up('video_bitrate_kbps', v)}
                                          min={1} suffix="Kbps" helperText="e.g. 730, 2000, 3000" />
                                <NumInput label="Frame Rate" value={preset.frame_rate_fps} onChange={v => up('frame_rate_fps', v)}
                                          min={1} suffix="fps" helperText="e.g. 24, 30, 60" />
                            </Box>

                            {/* Audio */}
                            <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 2 }}>
                                <Box>
                                    <Typography variant="body2" fontWeight={700} sx={{ mb: 0.5, color: '#334155', fontSize: '0.78rem' }}>
                                        Audio Codec
                                    </Typography>
                                    <Select size="small" fullWidth value={preset.audio_codec}
                                            onChange={e => up('audio_codec', e.target.value)}
                                            sx={{ fontSize: '0.82rem' }}>
                                        <MenuItem value="he_aac">Dolby HE-AAC</MenuItem>
                                        <MenuItem value="aac">AAC</MenuItem>
                                        <MenuItem value="mp3">MP3</MenuItem>
                                    </Select>
                                </Box>
                                <NumInput label="Audio Bitrate" value={preset.audio_bitrate_kbps} onChange={v => up('audio_bitrate_kbps', v)}
                                          min={1} suffix="Kbps" helperText="Default: 128" />
                            </Box>
                        </>
                    )}

                    {activeTab === 1 && (
                        <>
                            <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 2, mb: 2 }}>
                                <FormControlLabel
                                    control={
                                        <Checkbox size="small" checked={preset.two_pass_encoding}
                                                  onChange={e => up('two_pass_encoding', e.target.checked)}
                                                  sx={{ color: '#7c3aed', '&.Mui-checked': { color: '#7c3aed' } }} />
                                    }
                                    label={<Typography variant="caption" sx={{ color: '#334155' }}>Two Pass Encoding</Typography>}
                                />
                                <FormControlLabel
                                    control={
                                        <Checkbox size="small" checked={preset.constant_bitrate}
                                                  onChange={e => up('constant_bitrate', e.target.checked)}
                                                  sx={{ color: '#7c3aed', '&.Mui-checked': { color: '#7c3aed' } }} />
                                    }
                                    label={<Typography variant="caption" sx={{ color: '#334155' }}>Constant Bitrate</Typography>}
                                />
                            </Box>

                            <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 2, mb: 2 }}>
                                <Box>
                                    <Typography variant="body2" fontWeight={700} sx={{ mb: 0.5, color: '#334155', fontSize: '0.78rem' }}>
                                        H264 Profile
                                    </Typography>
                                    <Select size="small" fullWidth
                                            value={preset.h264_profile ?? ''}
                                            onChange={e => up('h264_profile', e.target.value || null)}
                                            sx={{ fontSize: '0.82rem' }}>
                                        <MenuItem value="">None (auto)</MenuItem>
                                        <MenuItem value="baseline">Baseline</MenuItem>
                                        <MenuItem value="main">Main</MenuItem>
                                        <MenuItem value="high">High</MenuItem>
                                    </Select>
                                </Box>
                                <NumInput label="Audio Sampling Rate" value={preset.audio_sampling_rate}
                                          onChange={v => up('audio_sampling_rate', v)}
                                          nullable helperText="e.g. 44100, 48000" />
                            </Box>

                            <Divider sx={{ mb: 2 }} />
                            <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1.5, color: '#334155', display: 'flex', alignItems: 'center', gap: 0.75 }}>
                                <TuneOutlined sx={{ fontSize: 16 }} />
                                Custom Encoding Parameters
                            </Typography>

                            {[
                                { key: 'h264Level',          label: 'h264Level',          hint: '10 × h264 level, e.g. "30" for 3.0' },
                                { key: 'keyframe',           label: 'keyframe',            hint: 'Keyframe interval in frames (HLS/DASH: 60–90)' },
                                { key: 'minBitrate',         label: 'minBitrate',          hint: 'Min variable bitrate in Kbps' },
                                { key: 'maxBitrate',         label: 'maxBitrate',          hint: 'Max variable bitrate in Kbps (rec: 2× encoding bitrate)' },
                                { key: 'audioBitrateCustom', label: 'audioBitrateCustom',  hint: '"true" / "false" — force constant audio bitrate' },
                            ].map(({ key, label, hint }) => (
                                <Box key={key} sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 2, mb: 1.5 }}>
                                    <Box>
                                        <Typography variant="body2" fontWeight={600} sx={{ mb: 0.5, color: '#475569', fontSize: '0.75rem', fontFamily: 'monospace' }}>
                                            {label}
                                        </Typography>
                                        <Typography variant="caption" sx={{ color: '#94a3b8', fontSize: '0.68rem' }}>{hint}</Typography>
                                    </Box>
                                    <TextField
                                        size="small"
                                        placeholder="(not set)"
                                        value={preset.advanced_params?.[key] ?? ''}
                                        onChange={e => up('advanced_params', { ...(preset.advanced_params || {}), [key]: e.target.value || undefined })}
                                        sx={{ '& .MuiInputBase-input': { fontSize: '0.82rem', fontFamily: 'monospace' } }}
                                    />
                                </Box>
                            ))}
                        </>
                    )}
                </Box>
            </Collapse>
        </Paper>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Profile Edit Dialog
// ─────────────────────────────────────────────────────────────────────────────
function VideoProfileEditDialog({ open, profile, onClose, onSaved }) {
    const notify = useNotify();
    const isNew  = !profile?.id;

    const [name,                setName]                = useState('');
    const [description,         setDescription]         = useState('');
    const [adaptive,            setAdaptive]            = useState(true);
    const [smartCropRatios,     setSmartCropRatios]     = useState([]);
    const [presets,             setPresets]             = useState([]);
    const [saving,              setSaving]              = useState(false);
    const [activeTab,           setActiveTab]           = useState(0);

    useEffect(() => {
        if (!open) return;
        if (profile) {
            setName(profile.name || '');
            setDescription(profile.description || '');
            setAdaptive(profile.encode_for_adaptive_streaming !== false);
            setSmartCropRatios(profile.smart_crop_ratios || []);
            setPresets((profile.encoding_presets || []).map(p => ({ ...p })));
        } else {
            setName(''); setDescription(''); setAdaptive(true);
            setSmartCropRatios([]);
            setPresets(DEFAULT_ADAPTIVE_PRESETS.map(p => ({ ...p })));
        }
        setActiveTab(0);
    }, [open, profile]);

    const handlePresetChange = (idx, updated) =>
        setPresets(prev => prev.map((p, i) => i === idx ? updated : p));

    const handlePresetRemove = (idx) =>
        setPresets(prev => prev.filter((_, i) => i !== idx));

    const handleAddPreset = () =>
        setPresets(prev => [...prev, { ...EMPTY_PRESET, position: prev.length }]);

    const handleSave = async () => {
        if (!name.trim()) { notify('Profile name is required.', 'error'); return; }
        setSaving(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;

            // Strip internal _id keys for new sub-items
            const cleanedPresets = presets.map((p, i) => {
                const { id, ...rest } = p;
                return { ...rest, position: i, ...(id ? { id } : {}) };
            });

            const payload = {
                video_profile: {
                    name,
                    description,
                    encode_for_adaptive_streaming: adaptive,
                    smart_crop_ratios:             smartCropRatios,
                    encoding_presets_attributes:   cleanedPresets,
                }
            };

            const url    = isNew ? '/api/v1/video_profiles' : `/api/v1/video_profiles/${profile.id}`;
            const method = isNew ? 'POST' : 'PATCH';

            const res  = await fetch(url, {
                method,
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(payload),
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

    const warnings = adaptive && presets.length >= 2 ? (() => {
        const fields = ['video_format_codec','audio_codec','audio_bitrate_kbps','keep_aspect_ratio','two_pass_encoding','constant_bitrate','h264_profile','audio_sampling_rate'];
        return fields.flatMap(f => {
            const vals = [...new Set(presets.map(p => JSON.stringify(p[f])))];
            return vals.length > 1 ? [`Presets have different '${f}' values. Adaptive streaming may not be possible.`] : [];
        });
    })() : [];

    return (
        <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth
                PaperProps={{ sx: { borderRadius: 3, height: '92vh' } }}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                               bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0', py: 1.5 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <VideoFileOutlined sx={{ color: '#7c3aed' }} />
                    <Typography fontWeight={700}>
                        {isNew ? 'Create Video Profile' : 'Edit Video Profile'}
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

            <DialogContent sx={{ overflow: 'auto', p: 0 }}>
                <Tabs value={activeTab} onChange={(_, v) => setActiveTab(v)}
                      sx={{ borderBottom: '1px solid #e2e8f0', px: 2,
                            '& .MuiTab-root': { textTransform: 'none', fontWeight: 600, fontSize: '0.85rem' } }}>
                    <Tab label="General" />
                    <Tab label={`Encoding Presets (${presets.length})`} />
                    <Tab label="Smart Crop" />
                </Tabs>

                <Box sx={{ p: 3 }}>
                    {/* ── General Tab ── */}
                    {activeTab === 0 && (
                        <>
                            <Box sx={{ mb: 2.5 }}>
                                <Typography variant="body2" fontWeight={700} sx={{ mb: 0.75, color: '#334155' }}>
                                    Name <Typography component="span" color="error">*</Typography>
                                </Typography>
                                <TextField fullWidth size="small" value={name} onChange={e => setName(e.target.value)}
                                           placeholder="e.g. Adaptive HD Streaming" />
                            </Box>

                            <Box sx={{ mb: 2.5 }}>
                                <Typography variant="body2" fontWeight={700} sx={{ mb: 0.75, color: '#334155' }}>
                                    Description
                                </Typography>
                                <TextField fullWidth size="small" multiline rows={2} value={description}
                                           onChange={e => setDescription(e.target.value)}
                                           placeholder="Optional description of this profile's purpose" />
                            </Box>

                            <Divider sx={{ mb: 2.5 }} />

                            <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', mb: 1 }}>
                                <Box>
                                    <Typography variant="body2" fontWeight={700} sx={{ color: '#334155' }}>
                                        Encode for Adaptive Streaming
                                    </Typography>
                                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                        Validates that all presets share compatible settings for HLS / DASH multi-bitrate delivery.
                                    </Typography>
                                </Box>
                                <Switch checked={adaptive} onChange={e => setAdaptive(e.target.checked)}
                                        sx={{ '& .MuiSwitch-switchBase.Mui-checked': { color: '#1d4ed8' },
                                              '& .MuiSwitch-switchBase.Mui-checked + .MuiSwitch-track': { bgcolor: '#1d4ed8' } }} />
                            </Box>

                            {adaptive && (
                                <Alert severity="info" icon={<InfoOutlined />}
                                       sx={{ mb: 2, bgcolor: '#f0f9ff', border: '1px solid #bae6fd', fontSize: '0.8rem' }}>
                                    Best practice presets for adaptive streaming: <strong>360p (730 Kbps)</strong>,{' '}
                                    <strong>540p (2000 Kbps)</strong>, <strong>720p (3000 Kbps)</strong> — all at 30 fps / HE-AAC 128 Kbps.
                                </Alert>
                            )}

                            {warnings.length > 0 && (
                                <Alert severity="warning" icon={<WarningAmberOutlined />}
                                       sx={{ bgcolor: '#fffbeb', border: '1px solid #fde68a', fontSize: '0.78rem' }}>
                                    <Typography variant="body2" fontWeight={700} sx={{ mb: 0.5 }}>Adaptive Streaming Warnings:</Typography>
                                    {warnings.map((w, i) => <div key={i}>• {w}</div>)}
                                </Alert>
                            )}
                        </>
                    )}

                    {/* ── Encoding Presets Tab ── */}
                    {activeTab === 1 && (
                        <>
                            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
                                <Box>
                                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>
                                        Encoding Presets
                                    </Typography>
                                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                        {adaptive ? 'Adaptive streaming requires 2+ presets.' : 'Single-bitrate progressive delivery.'}
                                    </Typography>
                                </Box>
                                <Button variant="outlined" size="small" startIcon={<AddOutlined />} onClick={handleAddPreset}
                                        sx={{ textTransform: 'none', borderColor: '#7c3aed', color: '#7c3aed',
                                              '&:hover': { bgcolor: '#faf5ff' } }}>
                                    Add Preset
                                </Button>
                            </Box>

                            {presets.length === 0 ? (
                                <Box sx={{ textAlign: 'center', py: 4, color: '#94a3b8' }}>
                                    <VideoFileOutlined sx={{ fontSize: 48, opacity: 0.3, mb: 1 }} />
                                    <Typography variant="body2">No presets yet. Add one above.</Typography>
                                </Box>
                            ) : (
                                presets.map((preset, idx) => (
                                    <PresetRow
                                        key={idx}
                                        preset={preset}
                                        idx={idx}
                                        onChange={handlePresetChange}
                                        onRemove={handlePresetRemove}
                                    />
                                ))
                            )}
                        </>
                    )}

                    {/* ── Smart Crop Tab ── */}
                    {activeTab === 2 && (
                        <>
                            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
                                <Box>
                                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>
                                        Smart Crop Ratios
                                    </Typography>
                                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                        Add aspect ratios for automatic video smart crop processing.
                                    </Typography>
                                </Box>
                                <Button variant="outlined" size="small" startIcon={<AddOutlined />}
                                        onClick={() => setSmartCropRatios(prev => [...prev, { name: '', crop_ratio: '16:9' }])}
                                        sx={{ textTransform: 'none', borderColor: '#7c3aed', color: '#7c3aed', '&:hover': { bgcolor: '#faf5ff' } }}>
                                    Add Ratio
                                </Button>
                            </Box>

                            {smartCropRatios.length === 0 ? (
                                <Typography variant="body2" sx={{ color: '#94a3b8', textAlign: 'center', py: 3 }}>
                                    No smart crop ratios defined.
                                </Typography>
                            ) : (
                                <>
                                    <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr auto', gap: 1.5, mb: 1, px: 0.5 }}>
                                        <Typography variant="caption" fontWeight={700} sx={{ color: '#64748b' }}>Name</Typography>
                                        <Typography variant="caption" fontWeight={700} sx={{ color: '#64748b' }}>Crop Ratio</Typography>
                                        <Box />
                                    </Box>
                                    {smartCropRatios.map((ratio, idx) => (
                                        <Box key={idx} sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr auto', gap: 1.5, mb: 1.5, alignItems: 'center' }}>
                                            <TextField size="small" value={ratio.name}
                                                       onChange={e => setSmartCropRatios(prev => prev.map((r, i) => i === idx ? { ...r, name: e.target.value } : r))}
                                                       placeholder="e.g. Widescreen"
                                                       sx={{ '& .MuiInputBase-input': { fontSize: '0.82rem' } }} />
                                            <Select size="small" value={ratio.crop_ratio}
                                                    onChange={e => setSmartCropRatios(prev => prev.map((r, i) => i === idx ? { ...r, crop_ratio: e.target.value } : r))}
                                                    sx={{ fontSize: '0.82rem' }}>
                                                {['16:9','4:3','1:1','9:16','21:9','3:4','2:1'].map(r => (
                                                    <MenuItem key={r} value={r}>{r}</MenuItem>
                                                ))}
                                            </Select>
                                            <Tooltip title="Remove">
                                                <IconButton size="small"
                                                            onClick={() => setSmartCropRatios(prev => prev.filter((_, i) => i !== idx))}
                                                            sx={{ color: '#94a3b8', '&:hover': { color: '#ef4444' } }}>
                                                    <DeleteOutlined fontSize="small" />
                                                </IconButton>
                                            </Tooltip>
                                        </Box>
                                    ))}
                                </>
                            )}
                        </>
                    )}
                </Box>
            </DialogContent>
        </Dialog>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Apply Video Profile Dialog (exported for Folders context menu)
// ─────────────────────────────────────────────────────────────────────────────
export function ApplyVideoProfileDialog({ open, onClose, folderId, folderName }) {
    const notify        = useNotify();
    const [profiles, setProfiles] = useState([]);
    const [loading,  setLoading]  = useState(false);
    const [selected, setSelected] = useState(null);
    const [applying, setApplying] = useState(false);

    useEffect(() => {
        if (!open) return;
        setLoading(true);
        setSelected(null);
        fetch('/api/v1/video_profiles')
            .then(r => r.json())
            .then(data => setProfiles(Array.isArray(data) ? data : []))
            .catch(() => notify('Failed to load video profiles.', 'error'))
            .finally(() => setLoading(false));
    }, [open]);

    const handleApply = async () => {
        if (!selected) return;
        setApplying(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch(`/api/v1/video_profiles/${selected.id}/apply_to_folder`, {
                method:  'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body:    JSON.stringify({ folder_id: folderId }),
            });
            if (!res.ok) throw new Error('Apply failed');
            notify(`"${selected.name}" video profile applied to folder "${folderName}".`, 'success');
            onClose(true);
        } catch {
            notify('Failed to apply video profile.', 'error');
        } finally {
            setApplying(false);
        }
    };

    return (
        <Dialog open={open} onClose={() => onClose(false)} maxWidth="sm" fullWidth
                PaperProps={{ sx: { borderRadius: 3 } }}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1.5,
                               borderBottom: '1px solid #f1f5f9', py: 1.5, bgcolor: '#faf5ff' }}>
                <VideoFileOutlined sx={{ color: '#7c3aed' }} />
                <Box sx={{ flex: 1 }}>
                    <Typography fontWeight={700}>Apply Video Profile</Typography>
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
                    Applying a video profile will automatically transcode videos uploaded to this folder using the defined encoding presets.
                </Alert>

                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1.5, color: '#334155' }}>
                    Available Video Profiles
                </Typography>

                {loading ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 3 }}>
                        <CircularProgress size={24} sx={{ color: '#7c3aed' }} />
                    </Box>
                ) : profiles.length === 0 ? (
                    <Typography variant="body2" sx={{ color: '#94a3b8' }}>
                        No video profiles available. Create one under Tools → Assets → Asset Configurations → Video Profiles.
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
                                            {p.encode_for_adaptive_streaming && (
                                                <Chip label="Adaptive" size="small"
                                                      sx={{ fontSize: '0.65rem', height: 18, bgcolor: '#ede9fe', color: '#6d28d9' }} />
                                            )}
                                        </Box>
                                    }
                                    secondary={p.description || `${p.folder_count ?? 0} folder assignment${p.folder_count !== 1 ? 's' : ''}`}
                                    secondaryTypographyProps={{ sx: { fontSize: '0.72rem' } }}
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

// ─────────────────────────────────────────────────────────────────────────────
// Profile Detail Panel
// ─────────────────────────────────────────────────────────────────────────────
function VideoProfileDetailPanel({ profile, onEdit, onDelete, onCopy }) {
    const [folders,  setFolders]  = useState([]);
    const [fullData, setFullData] = useState(null);

    useEffect(() => {
        if (!profile) { setFolders([]); setFullData(null); return; }
        fetch(`/api/v1/video_profiles/${profile.id}`)
            .then(r => r.ok ? r.json() : null)
            .then(data => { if (data) setFullData(data); })
            .catch(() => {});
        fetch(`/api/v1/video_profiles/${profile.id}/folders`)
            .then(r => r.ok ? r.json() : [])
            .then(setFolders)
            .catch(() => {});
    }, [profile?.id]);

    if (!profile) {
        return (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
                       color: '#94a3b8', flexDirection: 'column', gap: 2 }}>
                <VideoFileOutlined sx={{ fontSize: 64, opacity: 0.3 }} />
                <Typography variant="body2">Select a profile to inspect, edit, or manage it</Typography>
            </Box>
        );
    }

    const data     = fullData || profile;
    const presets  = data.encoding_presets || [];
    const warnings = data.adaptive_streaming_warnings || [];

    return (
        <Box sx={{ flex: 1, overflow: 'auto', p: 3 }}>
            {/* Header */}
            <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', mb: 3 }}>
                <Box>
                    <Typography variant="h5" fontWeight={700} sx={{ color: '#1e293b', mb: 0.5 }}>
                        {profile.name}
                    </Typography>
                    {data.description && (
                        <Typography variant="body2" sx={{ color: '#64748b', mb: 1 }}>{data.description}</Typography>
                    )}
                    <Stack direction="row" spacing={1} flexWrap="wrap">
                        {data.encode_for_adaptive_streaming
                            ? <Chip label="Adaptive Streaming" size="small" sx={{ bgcolor: '#ede9fe', color: '#6d28d9', fontSize: '0.7rem' }} />
                            : <Chip label="Progressive" size="small" sx={{ bgcolor: '#f1f5f9', color: '#64748b', fontSize: '0.7rem' }} />
                        }
                        <Chip label={`${presets.length} preset${presets.length !== 1 ? 's' : ''}`} size="small"
                              sx={{ bgcolor: '#dbeafe', color: '#1d4ed8', fontSize: '0.7rem' }} />
                        <Chip label={`${profile.folder_count ?? 0} folder${profile.folder_count !== 1 ? 's' : ''}`} size="small"
                              sx={{ bgcolor: '#f1f5f9', color: '#64748b', fontSize: '0.7rem' }} />
                    </Stack>
                </Box>
                <Stack direction="row" spacing={1}>
                    <Tooltip title="Copy profile">
                        <IconButton size="small" onClick={() => onCopy(profile)}
                                    sx={{ border: '1px solid #e2e8f0', color: '#64748b' }}>
                            <ContentCopyOutlined fontSize="small" />
                        </IconButton>
                    </Tooltip>
                    <Button variant="contained" size="small" startIcon={<EditOutlined />} onClick={() => onEdit(data)}
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

            {/* Adaptive warnings */}
            {warnings.length > 0 && (
                <Alert severity="warning" icon={<WarningAmberOutlined />}
                       sx={{ mb: 3, bgcolor: '#fffbeb', border: '1px solid #fde68a', fontSize: '0.78rem' }}>
                    {warnings.map((w, i) => <div key={i}>• {w}</div>)}
                </Alert>
            )}

            {/* Encoding Presets table */}
            <Paper variant="outlined" sx={{ mb: 3, borderRadius: 2, overflow: 'hidden' }}>
                <Box sx={{ px: 2, py: 1.25, bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0',
                           display: 'flex', alignItems: 'center', gap: 0.75 }}>
                    <SpeedOutlined sx={{ fontSize: 15, color: '#475569' }} />
                    <Typography variant="caption" fontWeight={700} sx={{ color: '#475569', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                        Encoding Presets
                    </Typography>
                </Box>
                {presets.length === 0 ? (
                    <Box sx={{ p: 2, textAlign: 'center', color: '#94a3b8' }}>
                        <Typography variant="body2">No presets defined.</Typography>
                    </Box>
                ) : (
                    <Box sx={{ overflowX: 'auto' }}>
                        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.78rem' }}>
                            <thead>
                                <tr style={{ background: '#f8fafc' }}>
                                    {['Name','Codec','Size','Bitrate','FPS','Audio Codec','Audio Kbps'].map(h => (
                                        <th key={h} style={{ padding: '6px 12px', textAlign: 'left', color: '#64748b', fontWeight: 600, borderBottom: '1px solid #e2e8f0', whiteSpace: 'nowrap' }}>{h}</th>
                                    ))}
                                </tr>
                            </thead>
                            <tbody>
                                {presets.map((p, i) => (
                                    <tr key={i} style={{ borderBottom: '1px solid #f1f5f9' }}>
                                        <td style={{ padding: '8px 12px', fontWeight: 600, color: '#1e293b' }}>{p.name}</td>
                                        <td style={{ padding: '8px 12px', color: '#475569', fontFamily: 'monospace' }}>MP4 H.264</td>
                                        <td style={{ padding: '8px 12px', color: '#475569', fontFamily: 'monospace' }}>{p.size_label || `${p.width ?? 'auto'} × ${p.height}`}</td>
                                        <td style={{ padding: '8px 12px', color: '#475569' }}>{p.video_bitrate_kbps} Kbps</td>
                                        <td style={{ padding: '8px 12px', color: '#475569' }}>{p.frame_rate_fps} fps</td>
                                        <td style={{ padding: '8px 12px', color: '#475569', textTransform: 'uppercase', fontSize: '0.7rem' }}>{p.audio_codec}</td>
                                        <td style={{ padding: '8px 12px', color: '#475569' }}>{p.audio_bitrate_kbps} Kbps</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </Box>
                )}
            </Paper>

            {/* Smart Crop Ratios */}
            {(data.smart_crop_ratios || []).length > 0 && (
                <Paper variant="outlined" sx={{ p: 2, mb: 3, borderRadius: 2 }}>
                    <Typography variant="caption" fontWeight={700} sx={{ color: '#475569', textTransform: 'uppercase', letterSpacing: 0.5, mb: 1.5, display: 'block' }}>
                        Smart Crop Ratios
                    </Typography>
                    <Stack direction="row" spacing={1} flexWrap="wrap">
                        {data.smart_crop_ratios.map((r, i) => (
                            <Chip key={i} label={`${r.name} (${r.crop_ratio})`} size="small"
                                  sx={{ bgcolor: '#ede9fe', color: '#6d28d9', fontFamily: 'monospace', fontSize: '0.72rem' }} />
                        ))}
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

// ─────────────────────────────────────────────────────────────────────────────
// Copy Profile Dialog
// ─────────────────────────────────────────────────────────────────────────────
function CopyProfileDialog({ open, profile, onClose, onCopied }) {
    const notify = useNotify();
    const [name,    setName]    = useState('');
    const [copying, setCopying] = useState(false);

    useEffect(() => {
        if (open && profile) setName(`${profile.name} (copy)`);
    }, [open, profile]);

    const handleCopy = async () => {
        setCopying(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch(`/api/v1/video_profiles/${profile.id}/copy`, {
                method:  'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body:    JSON.stringify({ name }),
            });
            const data = await res.json();
            if (!res.ok) throw new Error((data.errors || [data.error]).join(', '));
            notify(`Profile copied as "${data.name}".`, 'success');
            onCopied(data);
        } catch (err) {
            notify(err.message, 'error');
        } finally {
            setCopying(false);
        }
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="xs" fullWidth PaperProps={{ sx: { borderRadius: 3 } }}>
            <DialogTitle sx={{ py: 1.5, display: 'flex', alignItems: 'center', gap: 1, bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0' }}>
                <ContentCopyOutlined sx={{ color: '#7c3aed', fontSize: 20 }} />
                <Typography fontWeight={700}>Copy Profile</Typography>
            </DialogTitle>
            <DialogContent sx={{ pt: 2.5 }}>
                <Typography variant="body2" fontWeight={700} sx={{ mb: 0.75, color: '#334155' }}>New Name</Typography>
                <TextField fullWidth size="small" value={name} onChange={e => setName(e.target.value)} autoFocus />
            </DialogContent>
            <DialogActions sx={{ px: 2.5, pb: 2 }}>
                <Button onClick={onClose} sx={{ textTransform: 'none', color: '#64748b' }}>Cancel</Button>
                <Button variant="contained" onClick={handleCopy} disabled={!name.trim() || copying}
                        sx={{ bgcolor: '#7c3aed', '&:hover': { bgcolor: '#6d28d9' }, textTransform: 'none' }}>
                    {copying ? 'Copying…' : 'Copy'}
                </Button>
            </DialogActions>
        </Dialog>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// VideoProfilesManager — main export (default)
// ─────────────────────────────────────────────────────────────────────────────
export default function VideoProfilesManager() {
    const notify = useNotify();
    const [profiles,       setProfiles]       = useState([]);
    const [loading,        setLoading]        = useState(true);
    const [selected,       setSelected]       = useState(null);
    const [dialogOpen,     setDialogOpen]     = useState(false);
    const [editingProfile, setEditingProfile] = useState(null);
    const [copyTarget,     setCopyTarget]     = useState(null);
    const [copyOpen,       setCopyOpen]       = useState(false);

    const fetchProfiles = useCallback(async () => {
        setLoading(true);
        try {
            const res  = await fetch('/api/v1/video_profiles');
            const data = await res.json();
            setProfiles(Array.isArray(data) ? data : []);
            if (selected) {
                const refreshed = (Array.isArray(data) ? data : []).find(p => p.id === selected.id);
                setSelected(refreshed ?? null);
            }
        } catch {
            notify('Failed to load video profiles.', 'error');
        } finally {
            setLoading(false);
        }
    }, []); // eslint-disable-line

    useEffect(() => { fetchProfiles(); }, [fetchProfiles]);

    const handleEdit   = (profile) => { setEditingProfile(profile); setDialogOpen(true); };
    const handleNew    = () => { setEditingProfile(null); setDialogOpen(true); };
    const handleCopy   = (profile) => { setCopyTarget(profile); setCopyOpen(true); };

    const handleSaved = async (savedProfile) => {
        setDialogOpen(false);
        await fetchProfiles();
        setSelected(savedProfile);
    };

    const handleCopied = async (newProfile) => {
        setCopyOpen(false);
        await fetchProfiles();
        setSelected(newProfile);
    };

    const handleDelete = async (profile) => {
        if (!window.confirm(`Delete video profile "${profile.name}"? This will also remove all folder assignments.`)) return;
        const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
        const res = await fetch(`/api/v1/video_profiles/${profile.id}`, {
            method:  'DELETE',
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
                        <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>Video Profiles</Typography>
                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                            {profiles.length} profile{profiles.length !== 1 ? 's' : ''}
                        </Typography>
                    </Box>
                    <Tooltip title="Create new video profile">
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
                            <VideoFileOutlined sx={{ fontSize: 40, color: '#e2e8f0', mb: 1 }} />
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
                                                <VideoFileOutlined sx={{ fontSize: 15, color: selected?.id === p.id ? '#7c3aed' : '#94a3b8' }} />
                                                <Typography variant="body2" fontWeight={selected?.id === p.id ? 600 : 400}>
                                                    {p.name}
                                                </Typography>
                                            </Box>
                                        }
                                        secondary={
                                            <Stack direction="row" spacing={0.5} sx={{ mt: 0.25, flexWrap: 'wrap', gap: 0.25 }}>
                                                {p.encode_for_adaptive_streaming && (
                                                    <Chip label="Adaptive" size="small"
                                                          sx={{ fontSize: '0.6rem', height: 14, bgcolor: '#ede9fe', color: '#6d28d9' }} />
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
                    <VideoFileOutlined sx={{ color: '#7c3aed', fontSize: 22 }} />
                    <Box sx={{ flex: 1 }}>
                        <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b', lineHeight: 1.2 }}>
                            Video Profiles
                        </Typography>
                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                            Tools › Assets › Asset Configurations › Video Profiles
                        </Typography>
                    </Box>
                    <Button variant="contained" size="small" startIcon={<AddOutlined />} onClick={handleNew}
                            sx={{ bgcolor: '#7c3aed', '&:hover': { bgcolor: '#6d28d9' }, textTransform: 'none' }}>
                        Create Profile
                    </Button>
                </Box>

                <Box sx={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
                    <VideoProfileDetailPanel
                        profile={selected}
                        onEdit={handleEdit}
                        onDelete={handleDelete}
                        onCopy={handleCopy}
                    />
                </Box>
            </Box>

            {/* Dialogs */}
            <VideoProfileEditDialog
                open={dialogOpen}
                profile={editingProfile}
                onClose={() => setDialogOpen(false)}
                onSaved={handleSaved}
            />
            <CopyProfileDialog
                open={copyOpen}
                profile={copyTarget}
                onClose={() => setCopyOpen(false)}
                onCopied={handleCopied}
            />
        </Box>
    );
}

