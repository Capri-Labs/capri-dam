import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, Typography, IconButton, Drawer, Tab, Tabs, TextField,
    Button, Chip, Stack, CircularProgress, Paper,
    Alert, Tooltip
} from '@mui/material';
import {
    CloseOutlined, FolderOutlined, SaveOutlined, EditOutlined,
    ImageOutlined, VideoFileOutlined, SchemaOutlined, SecurityOutlined,
    LinkOffOutlined, InfoOutlined
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';
import { useTranslation } from 'react-i18next';
import { ApplyImageProfileDialog } from '../Tools/AssetConfigurations/ImageProfiles';
import { ApplyVideoProfileDialog } from '../Tools/AssetConfigurations/VideoProfiles';
import ApplySchemaDialog from './ApplySchemaDialog';
import FolderAccessTab from './FolderAccessTab';

const tr = (t, key, fallback, options = {}) => {
    const translated = t(key, options);
    if (translated === key) return fallback;
    if (options.count != null && translated === `${key}:${options.count}`) return fallback;
    return translated;
};

// ─────────────────────────────────────────────────────────────────────────────
// General Tab
// ─────────────────────────────────────────────────────────────────────────────
function GeneralTab({ folder, onUpdated }) {
    const notify = useNotify();
    const { t } = useTranslation();
    const [name,        setName]        = useState(folder?.name || '');
    const [description, setDescription] = useState(folder?.description || '');
    const [saving,      setSaving]      = useState(false);
    const [editing,     setEditing]     = useState(false);

    useEffect(() => {
        setName(folder?.name || '');
        setDescription(folder?.description || '');
        setEditing(false);
    }, [folder?.id]);

    const handleSave = async () => {
        if (!name.trim()) { notify(tr(t, 'folderInfoPanel.general.nameRequired', 'Name cannot be empty.'), 'error'); return; }
        setSaving(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch(`/api/v1/folders/${folder.id}`, {
                method:  'PATCH',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body:    JSON.stringify({ folder: { name, description } }),
            });
            const data = await res.json();
            if (!res.ok) throw new Error((data.errors || [data.error]).join(', '));
            notify(tr(t, 'folderInfoPanel.general.updated', 'Folder updated.'), 'success');
            setEditing(false);
            if (onUpdated) onUpdated(data);
        } catch (err) {
            notify(err.message, 'error');
        } finally {
            setSaving(false);
        }
    };

    return (
        <Box sx={{ p: 3 }}>
            {/* ID row */}
            <Paper variant="outlined" sx={{ p: 2, mb: 3, borderRadius: 2, bgcolor: '#f8fafc' }}>
                <Stack spacing={1.5}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                        <Typography variant="caption" fontWeight={700} sx={{ color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5 }}>{tr(t, 'folderInfoPanel.general.folderId', 'Folder ID')}</Typography>
                        <Typography variant="caption" sx={{ color: '#475569', fontFamily: 'monospace', fontSize: '0.72rem', wordBreak: 'break-all', textAlign: 'right', maxWidth: '60%' }}>
                            {folder?.id}
                        </Typography>
                    </Box>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                        <Typography variant="caption" fontWeight={700} sx={{ color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5 }}>{tr(t, 'folderInfoPanel.general.slug', 'Slug')}</Typography>
                        <Typography variant="caption" sx={{ color: '#475569', fontFamily: 'monospace' }}>{folder?.slug || '—'}</Typography>
                    </Box>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                        <Typography variant="caption" fontWeight={700} sx={{ color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5 }}>{tr(t, 'folderInfoPanel.general.created', 'Created')}</Typography>
                        <Typography variant="caption" sx={{ color: '#475569' }}>
                            {folder?.created_at ? new Date(folder.created_at).toLocaleDateString() : '—'}
                        </Typography>
                    </Box>
                </Stack>
            </Paper>

            {/* Name & Description */}
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1.5 }}>
                <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>{tr(t, 'folderInfoPanel.general.details', 'Details')}</Typography>
                {!editing && (
                    <Button size="small" startIcon={<EditOutlined />} onClick={() => setEditing(true)}
                            sx={{ textTransform: 'none', color: '#7c3aed', fontSize: '0.75rem' }}>
                        {tr(t, 'common.edit', 'Edit')}
                    </Button>
                )}
            </Box>

            <Box sx={{ mb: 2 }}>
                <Typography variant="body2" fontWeight={700} sx={{ mb: 0.5, color: '#334155', fontSize: '0.78rem' }}>{tr(t, 'folderInfoPanel.general.name', 'Name')}</Typography>
                <TextField
                    size="small" fullWidth value={name}
                    onChange={e => setName(e.target.value)}
                    disabled={!editing}
                    sx={{ '& .MuiInputBase-input': { fontSize: '0.88rem' } }}
                />
            </Box>

            <Box sx={{ mb: 3 }}>
                <Typography variant="body2" fontWeight={700} sx={{ mb: 0.5, color: '#334155', fontSize: '0.78rem' }}>{tr(t, 'folderInfoPanel.general.description', 'Description')}</Typography>
                <TextField
                    size="small" fullWidth multiline rows={3}
                    value={description}
                    onChange={e => setDescription(e.target.value)}
                    disabled={!editing}
                    placeholder={editing
                        ? tr(t, 'folderInfoPanel.general.descriptionPlaceholder', 'Add a description for this folder…')
                        : tr(t, 'folderInfoPanel.general.noDescription', 'No description')}
                    sx={{ '& .MuiInputBase-input': { fontSize: '0.85rem' } }}
                />
            </Box>

            {editing && (
                <Stack direction="row" spacing={1}>
                    <Button variant="contained" size="small" onClick={handleSave} disabled={saving}
                            startIcon={saving ? <CircularProgress size={14} color="inherit" /> : <SaveOutlined />}
                            sx={{ bgcolor: '#7c3aed', '&:hover': { bgcolor: '#6d28d9' }, textTransform: 'none' }}>
                        {saving ? tr(t, 'common.saving', 'Saving…') : tr(t, 'common.saveChanges', 'Save Changes')}
                    </Button>
                    <Button size="small" onClick={() => { setEditing(false); setName(folder?.name || ''); setDescription(folder?.description || ''); }}
                            sx={{ textTransform: 'none', color: '#64748b' }}>
                        {tr(t, 'common.cancel', 'Cancel')}
                    </Button>
                </Stack>
            )}
        </Box>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Image Profiles Tab
// ─────────────────────────────────────────────────────────────────────────────
function ImageProfilesTab({ folder, profiles, onRefresh }) {
    const notify = useNotify();
    const { t } = useTranslation();
    const [applyOpen, setApplyOpen] = useState(false);
    const [removing,  setRemoving]  = useState(false);
    const profile = profiles?.image_profile;

    const handleRemove = async () => {
        if (!profile) return;
        setRemoving(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch(`/api/v1/image_profiles/${profile.id}/remove_from_folder`, {
                method:  'DELETE',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body:    JSON.stringify({ folder_id: folder.id }),
            });
            if (!res.ok) throw new Error('Remove failed');
            notify(tr(t, 'folderInfoPanel.imageProfiles.removed', 'Image profile removed from folder.'), 'success');
            onRefresh();
        } catch {
            notify(tr(t, 'folderInfoPanel.imageProfiles.removeError', 'Failed to remove image profile.'), 'error');
        } finally {
            setRemoving(false);
        }
    };

    return (
        <Box sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <ImageOutlined sx={{ color: '#7c3aed', fontSize: 20 }} />
                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>{tr(t, 'folderInfoPanel.imageProfiles.title', 'Image Profile')}</Typography>
                </Box>
                <Button size="small" variant="outlined" onClick={() => setApplyOpen(true)}
                        sx={{ textTransform: 'none', borderColor: '#7c3aed', color: '#7c3aed', '&:hover': { bgcolor: '#faf5ff' }, fontSize: '0.75rem' }}>
                    {profile
                        ? tr(t, 'folderInfoPanel.imageProfiles.change', 'Change')
                        : tr(t, 'folderInfoPanel.imageProfiles.applyProfile', 'Apply Profile')}
                </Button>
            </Box>

            {profile ? (
                <Paper variant="outlined" sx={{ p: 2.5, borderRadius: 2, borderColor: '#ede9fe' }}>
                    <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
                        <Box>
                            <Typography variant="body1" fontWeight={700} sx={{ color: '#1e293b', mb: 0.5 }}>{profile.name}</Typography>
                            <Stack direction="row" spacing={0.75} sx={{
  flexWrap: "wrap"
}}>
                                {profile.crop_type === 'smart_crop' && (
                                    <Chip label={tr(t, 'folderInfoPanel.imageProfiles.smartCrop', 'Smart Crop')} size="small" sx={{ fontSize: '0.65rem', height: 18, bgcolor: '#ede9fe', color: '#6d28d9' }} />
                                )}
                                {profile.swatch_enabled && (
                                    <Chip label={tr(t, 'folderInfoPanel.imageProfiles.swatch', 'Swatch')} size="small" sx={{ fontSize: '0.65rem', height: 18, bgcolor: '#fce7f3', color: '#9d174d' }} />
                                )}
                                {profile.responsive_crop_enabled && (
                                    <Chip label={tr(t, 'folderInfoPanel.imageProfiles.responsiveCrop', 'Responsive Crop')} size="small" sx={{ fontSize: '0.65rem', height: 18, bgcolor: '#dbeafe', color: '#1d4ed8' }} />
                                )}
                            </Stack>
                            {profile.unsharp_mask && (
                                <Typography variant="caption" sx={{ color: '#94a3b8', display: 'block', mt: 1 }}>
                                    {tr(
                                        t,
                                        'folderInfoPanel.imageProfiles.unsharpMask',
                                        `Unsharp: amount ${profile.unsharp_mask.amount} · radius ${profile.unsharp_mask.radius}`,
                                        { amount: profile.unsharp_mask.amount, radius: profile.unsharp_mask.radius },
                                    )}
                                </Typography>
                            )}
                        </Box>
                        <Tooltip title={tr(t, 'folderInfoPanel.imageProfiles.removeTooltip', 'Remove profile from this folder')}>
                            <IconButton size="small" onClick={handleRemove} disabled={removing}
                                        sx={{ color: '#94a3b8', '&:hover': { color: '#ef4444' } }}>
                                <LinkOffOutlined fontSize="small" />
                            </IconButton>
                        </Tooltip>
                    </Box>
                </Paper>
            ) : (
                <Alert severity="info" icon={<InfoOutlined />}
                       sx={{ bgcolor: '#f0f9ff', border: '1px solid #bae6fd', fontSize: '0.8rem' }}>
                    {tr(t, 'folderInfoPanel.imageProfiles.empty', 'No image profile assigned. Images uploaded to this folder will use default processing settings.')}
                    <br />
                    <Typography variant="caption" sx={{ color: '#475569', mt: 0.5, display: 'block' }}>
                        {tr(t, 'folderInfoPanel.imageProfiles.emptyHint', 'You can configure profiles under Tools → Assets → Asset Configurations → Image Profiles.')}
                    </Typography>
                </Alert>
            )}

            <ApplyImageProfileDialog
                open={applyOpen}
                onClose={(refreshed) => { setApplyOpen(false); if (refreshed) onRefresh(); }}
                folderId={folder?.id}
                folderName={folder?.name}
            />
        </Box>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Profiles Tab
// ─────────────────────────────────────────────────────────────────────────────
function VideoProfilesTab({ folder, profiles, onRefresh }) {
    const notify = useNotify();
    const { t } = useTranslation();
    const [applyOpen, setApplyOpen] = useState(false);
    const [removing,  setRemoving]  = useState(false);
    const profile = profiles?.video_profile;

    const handleRemove = async () => {
        if (!profile) return;
        setRemoving(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch(`/api/v1/video_profiles/${profile.id}/remove_from_folder`, {
                method:  'DELETE',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body:    JSON.stringify({ folder_id: folder.id }),
            });
            if (!res.ok) throw new Error('Remove failed');
            notify(tr(t, 'folderInfoPanel.videoProfiles.removed', 'Video profile removed from folder.'), 'success');
            onRefresh();
        } catch {
            notify(tr(t, 'folderInfoPanel.videoProfiles.removeError', 'Failed to remove video profile.'), 'error');
        } finally {
            setRemoving(false);
        }
    };

    return (
        <Box sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <VideoFileOutlined sx={{ color: '#7c3aed', fontSize: 20 }} />
                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>{tr(t, 'folderInfoPanel.videoProfiles.title', 'Video Profile')}</Typography>
                </Box>
                <Button size="small" variant="outlined" onClick={() => setApplyOpen(true)}
                        sx={{ textTransform: 'none', borderColor: '#7c3aed', color: '#7c3aed', '&:hover': { bgcolor: '#faf5ff' }, fontSize: '0.75rem' }}>
                    {profile
                        ? tr(t, 'folderInfoPanel.videoProfiles.change', 'Change')
                        : tr(t, 'folderInfoPanel.videoProfiles.applyProfile', 'Apply Profile')}
                </Button>
            </Box>

            {profile ? (
                <Paper variant="outlined" sx={{ p: 2.5, borderRadius: 2, borderColor: '#ede9fe' }}>
                    <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
                        <Box>
                            <Typography variant="body1" fontWeight={700} sx={{ color: '#1e293b', mb: 0.5 }}>{profile.name}</Typography>
                            {profile.description && (
                                <Typography variant="caption" sx={{ color: '#64748b', display: 'block', mb: 0.75 }}>{profile.description}</Typography>
                            )}
                            <Stack direction="row" spacing={0.75}>
                                {profile.encode_for_adaptive_streaming
                                    ? <Chip label={tr(t, 'folderInfoPanel.videoProfiles.adaptiveStreaming', 'Adaptive Streaming')} size="small" sx={{ fontSize: '0.65rem', height: 18, bgcolor: '#ede9fe', color: '#6d28d9' }} />
                                    : <Chip label={tr(t, 'folderInfoPanel.videoProfiles.progressive', 'Progressive')} size="small" sx={{ fontSize: '0.65rem', height: 18, bgcolor: '#f1f5f9', color: '#64748b' }} />
                                }
                                <Chip label={tr(
                                    t,
                                    'folderInfoPanel.videoProfiles.presetCount',
                                    `${profile.preset_count ?? 0} preset${profile.preset_count !== 1 ? 's' : ''}`,
                                    { count: profile.preset_count ?? 0 },
                                )} size="small"
                                      sx={{ fontSize: '0.65rem', height: 18, bgcolor: '#dbeafe', color: '#1d4ed8' }} />
                            </Stack>
                        </Box>
                        <Tooltip title={tr(t, 'folderInfoPanel.videoProfiles.removeTooltip', 'Remove profile from this folder')}>
                            <IconButton size="small" onClick={handleRemove} disabled={removing}
                                        sx={{ color: '#94a3b8', '&:hover': { color: '#ef4444' } }}>
                                <LinkOffOutlined fontSize="small" />
                            </IconButton>
                        </Tooltip>
                    </Box>
                </Paper>
            ) : (
                <Alert severity="info" icon={<InfoOutlined />}
                       sx={{ bgcolor: '#f0f9ff', border: '1px solid #bae6fd', fontSize: '0.8rem' }}>
                    {tr(t, 'folderInfoPanel.videoProfiles.empty', 'No video profile assigned. Videos uploaded to this folder will not be auto-transcoded.')}
                    <br />
                    <Typography variant="caption" sx={{ color: '#475569', mt: 0.5, display: 'block' }}>
                        {tr(t, 'folderInfoPanel.videoProfiles.emptyHint', 'Configure profiles under Tools → Assets → Asset Configurations → Video Profiles.')}
                    </Typography>
                </Alert>
            )}

            <ApplyVideoProfileDialog
                open={applyOpen}
                onClose={(refreshed) => { setApplyOpen(false); if (refreshed) onRefresh(); }}
                folderId={folder?.id}
                folderName={folder?.name}
            />
        </Box>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Metadata Tab
// ─────────────────────────────────────────────────────────────────────────────
function MetadataTab({ folder, profiles, onRefresh }) {
    const notify = useNotify();
    const { t } = useTranslation();
    const [schemaOpen, setSchemaOpen] = useState(false);
    const [removing,   setRemoving]   = useState(false);
    const schema = profiles?.metadata_schema;

    const handleRemove = async () => {
        setRemoving(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch(`/api/v1/folders/${folder.id}/remove_schema`, {
                method:  'DELETE',
                headers: { 'X-CSRF-Token': csrfToken },
            });
            if (!res.ok) throw new Error('Remove failed');
            notify(tr(t, 'folderInfoPanel.metadata.removed', 'Metadata schema removed from folder.'), 'success');
            onRefresh();
        } catch {
            notify(tr(t, 'folderInfoPanel.metadata.removeError', 'Failed to remove schema.'), 'error');
        } finally {
            setRemoving(false);
        }
    };

    return (
        <Box sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <SchemaOutlined sx={{ color: '#7c3aed', fontSize: 20 }} />
                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>{tr(t, 'folderInfoPanel.metadata.title', 'Metadata Schema')}</Typography>
                </Box>
                <Button size="small" variant="outlined" onClick={() => setSchemaOpen(true)}
                        sx={{ textTransform: 'none', borderColor: '#7c3aed', color: '#7c3aed', '&:hover': { bgcolor: '#faf5ff' }, fontSize: '0.75rem' }}>
                    {schema
                        ? tr(t, 'folderInfoPanel.metadata.change', 'Change')
                        : tr(t, 'folderInfoPanel.metadata.applySchema', 'Apply Schema')}
                </Button>
            </Box>

            {schema ? (
                <Paper variant="outlined" sx={{ p: 2.5, borderRadius: 2, borderColor: '#ede9fe' }}>
                    <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
                        <Box sx={{ flex: 1 }}>
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
                                <Typography variant="body1" fontWeight={700} sx={{ color: '#1e293b' }}>{schema.name}</Typography>
                                <Chip
                                    label={schema.source === 'inherited'
                                        ? tr(t, 'folderInfoPanel.metadata.inherited', 'Inherited')
                                        : tr(t, 'folderInfoPanel.metadata.direct', 'Direct')}
                                    size="small"
                                    sx={{
                                        fontSize: '0.62rem', height: 16,
                                        bgcolor: schema.source === 'inherited' ? '#fef3c7' : '#dcfce7',
                                        color:   schema.source === 'inherited' ? '#92400e' : '#166534',
                                    }}
                                />
                            </Box>
                            {schema.description && (
                                <Typography variant="caption" sx={{ color: '#64748b', display: 'block', mb: 1 }}>{schema.description}</Typography>
                            )}
                            {schema.tabs && schema.tabs.length > 0 && (
                                <Stack direction="row" spacing={0.5} sx={{
  gap: '4px !important',
  flexWrap: "wrap"
}}>
                                    {schema.tabs.map((tab, i) => (
                                        <Chip key={i} label={tab.label || tab.name || tr(t, 'folderInfoPanel.metadata.tabLabel', `Tab ${i + 1}`, { index: i + 1 })} size="small"
                                              sx={{ fontSize: '0.62rem', height: 16, bgcolor: '#e0e7ff', color: '#3730a3' }} />
                                    ))}
                                </Stack>
                            )}
                        </Box>
                        {schema.source !== 'inherited' && (
                            <Tooltip title={tr(t, 'folderInfoPanel.metadata.removeTooltip', 'Remove schema from this folder')}>
                                <IconButton size="small" onClick={handleRemove} disabled={removing}
                                            sx={{ color: '#94a3b8', '&:hover': { color: '#ef4444' } }}>
                                    <LinkOffOutlined fontSize="small" />
                                </IconButton>
                            </Tooltip>
                        )}
                    </Box>
                </Paper>
            ) : (
                <Alert severity="info" icon={<InfoOutlined />}
                       sx={{ bgcolor: '#f0f9ff', border: '1px solid #bae6fd', fontSize: '0.8rem' }}>
                    {tr(t, 'folderInfoPanel.metadata.empty', 'No metadata schema assigned to this folder. Assets will use the default schema if one is configured.')}
                    <br />
                    <Typography variant="caption" sx={{ color: '#475569', mt: 0.5, display: 'block' }}>
                        {tr(t, 'folderInfoPanel.metadata.emptyHint', 'Configure schemas under Tools → Metadata Schemas.')}
                    </Typography>
                </Alert>
            )}

            <ApplySchemaDialog
                open={schemaOpen}
                onClose={(refreshed) => { setSchemaOpen(false); if (refreshed) onRefresh(); }}
                targetType="folder"
                targetIds={[folder?.id]}
                targetNames={[folder?.name]}
                currentFolderId={folder?.id}
            />
        </Box>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// FolderInfoPanel — main export
// ─────────────────────────────────────────────────────────────────────────────
export default function FolderInfoPanel({ folder, open, onClose, onFolderUpdated }) {
    const { t } = useTranslation();
    const [tab,      setTab]      = useState(0);
    const [profiles, setProfiles] = useState(null);
    const [loading,  setLoading]  = useState(false);

    const fetchProfiles = useCallback(async () => {
        if (!folder?.id) return;
        setLoading(true);
        try {
            const res  = await fetch(`/api/v1/folders/${folder.id}/profiles`);
            const data = await res.json();
            setProfiles(data);
        } catch { /* ignore */ }
        finally { setLoading(false); }
    }, [folder?.id]);

    useEffect(() => {
        if (open && folder?.id) {
            setTab(0);
            fetchProfiles();
        }
    }, [open, folder?.id]);

    const handleUpdated = (data) => {
        if (onFolderUpdated) onFolderUpdated(data);
    };

    const TABS = [
        { label: tr(t, 'folderInfoPanel.tabs.general', 'General'), icon: <FolderOutlined sx={{ fontSize: 16 }} /> },
        { label: tr(t, 'folderInfoPanel.tabs.imageProfiles', 'Image Profiles'), icon: <ImageOutlined sx={{ fontSize: 16 }} /> },
        { label: tr(t, 'folderInfoPanel.tabs.videoProfiles', 'Video Profiles'), icon: <VideoFileOutlined sx={{ fontSize: 16 }} /> },
        { label: tr(t, 'folderInfoPanel.tabs.metadata', 'Metadata'), icon: <SchemaOutlined sx={{ fontSize: 16 }} /> },
        { label: tr(t, 'folderInfoPanel.tabs.access', 'Access'), icon: <SecurityOutlined sx={{ fontSize: 16 }} /> },
    ];

    return (
        <Drawer
            anchor="right"
            open={open}
            onClose={onClose}
            slotProps={{
                paper: {
                    sx: {
                        width: 420,
                        boxShadow: '-4px 0 24px rgba(0,0,0,0.08)',
                        display: 'flex', flexDirection: 'column',
                    },
                },
            }}
        >
            {/* Header */}
            <Box sx={{ px: 2.5, py: 2, bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0',
                       display: 'flex', alignItems: 'center', gap: 1.5, flexShrink: 0 }}>
                <FolderOutlined sx={{ color: '#4299e1', fontSize: 22 }} />
                <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography variant="subtitle1" fontWeight={700} sx={{ color: '#1e293b', lineHeight: 1.2 }}
                                noWrap>
                        {folder?.name}
                    </Typography>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>{tr(t, 'folderInfoPanel.header.subtitle', 'Folder properties')}</Typography>
                </Box>
                <IconButton size="small" onClick={onClose}>
                    <CloseOutlined fontSize="small" />
                </IconButton>
            </Box>

            {/* Tabs */}
            <Tabs
                value={tab}
                onChange={(_, v) => setTab(v)}
                variant="scrollable"
                scrollButtons="auto"
                sx={{
                    borderBottom: '1px solid #e2e8f0', flexShrink: 0,
                    '& .MuiTab-root': {
                        minHeight: 44, py: 0, textTransform: 'none',
                        fontSize: '0.78rem', fontWeight: 500, minWidth: 'auto', px: 1.5,
                    },
                    '& .Mui-selected': { color: '#7c3aed', fontWeight: 700 },
                    '& .MuiTabs-indicator': { bgcolor: '#7c3aed' },
                }}
            >
                {TABS.map((t, i) => (
                    <Tab key={i} icon={t.icon} iconPosition="start" label={t.label} />
                ))}
            </Tabs>

            {/* Content */}
            <Box sx={{ flex: 1, overflow: 'auto' }}>
                {loading && (
                    <Box sx={{ display: 'flex', justifyContent: 'center', pt: 6 }}>
                        <CircularProgress size={28} sx={{ color: '#7c3aed' }} />
                    </Box>
                )}
                {!loading && folder && (
                    <>
                        {tab === 0 && <GeneralTab folder={folder} onUpdated={handleUpdated} />}
                        {tab === 1 && <ImageProfilesTab folder={folder} profiles={profiles} onRefresh={fetchProfiles} />}
                        {tab === 2 && <VideoProfilesTab folder={folder} profiles={profiles} onRefresh={fetchProfiles} />}
                        {tab === 3 && <MetadataTab folder={folder} profiles={profiles} onRefresh={fetchProfiles} />}
                        {tab === 4 && <FolderAccessTab folder={folder} />}
                    </>
                )}
            </Box>
        </Drawer>
    );
}
