import React, { useState, useEffect } from 'react';
import {
    Dialog, DialogTitle, DialogContent,
    Button, Typography, Box, Chip, Card, CardMedia,
    CardContent, CircularProgress, Tooltip,
    IconButton, Alert
} from '@mui/material';
import {
    ContentCopy, Check, DeleteOutlined, FolderOutlined,
    StarOutlined, CloseOutlined,
    LaunchOutlined, HideSourceOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { navigateTo } from '../../utils/globalutils';

// ---------------------------------------------------------------------------
// Asset card within the modal
// ---------------------------------------------------------------------------
function AssetCard({ asset, isSelected, onToggle, onNavigate, onGoToFolder }) {
    const { t }  = useTranslation();
    const ext    = asset.title?.split('.').pop()?.toUpperCase() || '?';
    const sizeKB = asset.file_size ? `${(asset.file_size / 1024).toFixed(1)} KB` : null;

    return (
        <Card
            elevation={0}
            sx={{
                width: 220,
                cursor: 'pointer',
                borderRadius: 2,
                border: isSelected ? '2.5px solid #3b82f6' : '1px solid #e2e8f0',
                transition: 'all 0.2s',
                position: 'relative',
                overflow: 'visible',
                '&:hover': { boxShadow: '0 4px 16px rgba(0,0,0,0.08)' },
            }}
        >
            {/* Original badge */}
            {asset.is_original && (
                <Box sx={{
                    position: 'absolute', top: -10, left: -10, zIndex: 10,
                    bgcolor: '#f59e0b', color: '#fff', borderRadius: '50%',
                    width: 28, height: 28, display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                    <Tooltip title={t('duplicateManager.resolution.originalBadge')}>
                        <StarOutlined sx={{ fontSize: 16 }} />
                    </Tooltip>
                </Box>
            )}

            {/* Selection badge */}
            {isSelected && (
                <Box sx={{
                    position: 'absolute', top: -10, right: -10, zIndex: 10,
                    bgcolor: '#3b82f6', color: 'white', borderRadius: '50%',
                    width: 26, height: 26, display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                    <Check sx={{ fontSize: 16 }} />
                </Box>
            )}

            {/* Thumbnail area */}
            <Box
                sx={{ position: 'relative' }}
                onClick={() => onToggle(asset.asset_id)}
            >
                {asset.url && asset.content_type?.startsWith('image/') ? (
                    <CardMedia
                        component="img"
                        height="140"
                        image={asset.url}
                        alt={asset.title}
                        sx={{
                            objectFit: 'cover',
                            borderTopLeftRadius: 8, borderTopRightRadius: 8,
                            opacity: isSelected ? 0.8 : 1,
                        }}
                    />
                ) : (
                    <Box sx={{
                        height: 140, display: 'flex', alignItems: 'center', justifyContent: 'center',
                        bgcolor: '#f1f5f9', borderTopLeftRadius: 8, borderTopRightRadius: 8,
                    }}>
                        <ContentCopy sx={{ fontSize: 36, color: '#94a3b8' }} />
                    </Box>
                )}
                {/* Format chip */}
                <Chip
                    label={ext}
                    size="small"
                    sx={{
                        position: 'absolute', bottom: 6, right: 6,
                        bgcolor: 'rgba(255,255,255,0.85)', fontWeight: 700, fontSize: '0.65rem',
                    }}
                />
            </Box>

            {/* Metadata */}
            <CardContent sx={{ p: 1.5, '&:last-child': { pb: 1.5 } }}
                         onClick={() => onToggle(asset.asset_id)}>
                <Typography variant="body2" sx={{ fontWeight: 600, color: '#1e293b' }} noWrap>
                    {asset.title}
                </Typography>
                {sizeKB && (
                    <Typography variant="caption" sx={{ color: '#94a3b8', display: 'block' }}>
                        {sizeKB}
                    </Typography>
                )}
                <Typography variant="caption" sx={{ color: '#94a3b8', display: 'block' }} noWrap>
                    {asset.uploaded_at
                        ? new Date(asset.uploaded_at).toLocaleDateString()
                        : '—'
                    }
                </Typography>
            </CardContent>

            {/* Navigation row */}
            <Box sx={{ display: 'flex', borderTop: '1px solid #f1f5f9', px: 1, py: 0.5 }}>
                <Tooltip title={t('duplicateManager.resolution.navigateTo')}>
                    <IconButton
                        size="small"
                        aria-label={t('duplicateManager.resolution.navigateTo')}
                        onClick={e => { e.stopPropagation(); onNavigate(asset); }}
                        sx={{ color: '#3b82f6', '&:hover': { bgcolor: '#eff6ff' } }}
                    >
                        <LaunchOutlined sx={{ fontSize: 16 }} />
                    </IconButton>
                </Tooltip>
                <Tooltip title={t('duplicateManager.resolution.goToFolder')}>
                    <IconButton
                        size="small"
                        aria-label={t('duplicateManager.resolution.goToFolder')}
                        onClick={e => { e.stopPropagation(); onGoToFolder(asset); }}
                        sx={{ color: '#64748b', '&:hover': { bgcolor: '#f1f5f9' } }}
                    >
                        <FolderOutlined sx={{ fontSize: 16 }} />
                    </IconButton>
                </Tooltip>
                <Box sx={{ flex: 1 }} />
                <Typography variant="caption" sx={{
                    color: '#94a3b8', alignSelf: 'center', maxWidth: 80,
                    overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                }}>
                    {asset.folder_name}
                </Typography>
            </Box>
        </Card>
    );
}

// ---------------------------------------------------------------------------
// Main modal
// ---------------------------------------------------------------------------
export default function DuplicateResolutionModal({
    open, duplicateGroup, loading, onClose, onResolve, onDismiss
}) {
    const { t }          = useTranslation();
    const [selectedIds,  setSelectedIds]  = useState([]);
    const [confirming,   setConfirming]   = useState(false);

    // Reset selection when group changes
    useEffect(() => { setSelectedIds([]); setConfirming(false); }, [duplicateGroup]);

    if (!open) return null;

    const assets = duplicateGroup?.assets || [];

    const toggleSelection = (id) => {
        setSelectedIds(prev =>
            prev.includes(id) ? prev.filter(item => item !== id) : [...prev, id]
        );
    };

    const handleNavigateToAsset = (asset) => {
        navigateTo(`/assets?id=${asset.asset_id}`);
    };

    const handleGoToFolder = (asset) => {
        if (asset.folder_id) {
            // AssetExplorer reads the target folder from `?folder=`, not `?id=`
            // (see readUrlFilters() in AssetExplorer.jsx) — `?id=` is reserved
            // for deep-linking directly to an asset.
            navigateTo(`/folders?folder=${asset.folder_id}`);
        } else {
            navigateTo('/folders');
        }
    };

    const handleAccept = () => onResolve(duplicateGroup.id, 'accept', []);

    const handleDelete = () => {
        if (selectedIds.length === 0) return;
        setConfirming(true);
    };

    const confirmDelete = () => {
        onResolve(duplicateGroup.id, 'delete', selectedIds);
        setConfirming(false);
    };

    const handleDismiss = () => onDismiss?.(duplicateGroup.id);

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth="lg"
            fullWidth
            slotProps={{ paper: { sx: { borderRadius: 3, p: 0 } } }}
        >
            {/* Header */}
            <DialogTitle sx={{
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                pb: 1, borderBottom: '1px solid #f1f5f9', px: 3, pt: 2.5,
            }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    <Box sx={{ bgcolor: '#f1f5f9', p: 1, borderRadius: 2, display: 'flex' }}>
                        <ContentCopy sx={{ color: '#64748b', fontSize: 20 }} />
                    </Box>
                    <Box>
                        <Typography variant="h6" sx={{ fontWeight: 700, color: '#1e293b', lineHeight: 1.2 }}>
                            {t('duplicateManager.resolution.title')}
                        </Typography>
                        <Typography variant="body2" sx={{ color: '#64748b' }}>
                            {t('duplicateManager.resolution.subtitle', { count: duplicateGroup?.total_count || assets.length })}
                            {' '}·{' '}
                            <Box component="span" sx={{ fontFamily: 'monospace', fontSize: '0.75rem', color: '#94a3b8' }}>
                                SHA-256: {duplicateGroup?.checksum?.slice(0, 20)}…
                            </Box>
                        </Typography>
                    </Box>
                </Box>

                <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
                    {/* Keep all */}
                    <Button
                        size="small"
                        color="inherit"
                        startIcon={<Check />}
                        onClick={handleAccept}
                        disabled={loading}
                        sx={{ textTransform: 'none', color: '#475569', fontWeight: 600, borderRadius: 2 }}
                    >
                        {t('duplicateManager.resolution.accept')}
                    </Button>

                    {/* Delete selected */}
                    <Button
                        size="small"
                        color="inherit"
                        startIcon={<DeleteOutlined />}
                        onClick={handleDelete}
                        disabled={selectedIds.length === 0 || loading}
                        sx={{
                            textTransform: 'none', fontWeight: 600, borderRadius: 2,
                            color: selectedIds.length > 0 ? '#ef4444' : '#94a3b8',
                        }}
                    >
                        {t('duplicateManager.resolution.delete')}
                        {selectedIds.length > 0 && ` (${selectedIds.length})`}
                    </Button>

                    {/* Dismiss */}
                    <Tooltip title={t('duplicateManager.resolution.dismiss', 'Dismiss without action')}>
                        <IconButton
                            size="small"
                            onClick={handleDismiss}
                            disabled={loading}
                            sx={{ color: '#94a3b8', '&:hover': { color: '#475569' } }}
                        >
                            <HideSourceOutlined fontSize="small" />
                        </IconButton>
                    </Tooltip>

                    <IconButton size="small" onClick={onClose} sx={{ color: '#94a3b8' }}>
                        <CloseOutlined fontSize="small" />
                    </IconButton>
                </Box>
            </DialogTitle>

            <DialogContent sx={{ px: 3, py: 3 }}>
                {/* Confirm-delete banner */}
                {confirming && (
                    <Alert
                        severity="warning"
                        sx={{ mb: 2, borderRadius: 2 }}
                        action={
                            <Box sx={{ display: 'flex', gap: 1 }}>
                                <Button size="small" color="inherit" onClick={() => setConfirming(false)}>
                                    {t('common.cancel')}
                                </Button>
                                <Button size="small" color="error" variant="contained" onClick={confirmDelete}
                                        sx={{ textTransform: 'none', borderRadius: 1.5 }}>
                                    {t('common.confirm')}
                                </Button>
                            </Box>
                        }
                    >
                        {t('duplicateManager.resolution.confirmDeleteBody')}
                    </Alert>
                )}

                {/* Loading state */}
                {loading ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
                        <CircularProgress />
                    </Box>
                ) : (
                    <>
                        {selectedIds.length > 0 && (
                            <Typography variant="caption" sx={{ color: '#3b82f6', mb: 2, display: 'block' }}>
                                {t('duplicateManager.resolution.selectedCount', { count: selectedIds.length })}
                            </Typography>
                        )}
                        <Box sx={{ display: 'flex', gap: 2.5, flexWrap: 'wrap', justifyContent: 'flex-start' }}>
                            {assets.map(asset => (
                                <AssetCard
                                    key={asset.asset_id}
                                    asset={asset}
                                    isSelected={selectedIds.includes(asset.asset_id)}
                                    onToggle={toggleSelection}
                                    onNavigate={handleNavigateToAsset}
                                    onGoToFolder={handleGoToFolder}
                                />
                            ))}
                        </Box>
                    </>
                )}
            </DialogContent>
        </Dialog>
    );
}
