import React, { useState } from 'react';
import {
    Box, Checkbox, Tooltip, IconButton, Typography, Chip
} from '@mui/material';
import {
    FolderZipOutlined, InsertDriveFile, PictureAsPdf, VideoFile,
    AudioFile, ImageOutlined, RestoreFromTrashOutlined, DeleteForeverOutlined,
    TimerOffOutlined, ViewInArOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const CARD_SIZES = {
    small:  { width: 150, height: 130, imgHeight: 90,  titleLen: 14 },
    medium: { width: 200, height: 175, imgHeight: 125, titleLen: 18 },
    large:  { width: 260, height: 225, imgHeight: 165, titleLen: 24 },
};

const getIcon = (contentType, mediaType) => {
    if (mediaType === 'folder')   return <FolderZipOutlined sx={{ fontSize: 56, color: '#f59e0b' }} />;
    if (mediaType === 'image')    return <ImageOutlined sx={{ fontSize: 56, color: '#10b981' }} />;
    if (mediaType === 'video')    return <VideoFile sx={{ fontSize: 56, color: '#3b82f6' }} />;
    if (mediaType === 'audio')    return <AudioFile sx={{ fontSize: 56, color: '#8b5cf6' }} />;
    if (mediaType === 'document') return <PictureAsPdf sx={{ fontSize: 56, color: '#ef4444' }} />;
    if (mediaType === 'model_3d') return <ViewInArOutlined sx={{ fontSize: 56, color: '#0d9488' }} />;
    return <InsertDriveFile sx={{ fontSize: 56, color: '#64748b' }} />;
};

const BinCard = ({ item, isSelected, onToggleSelect, onRestore, onDelete, size }) => {
    const { t }   = useTranslation();
    const cfg     = CARD_SIZES[size] || CARD_SIZES.medium;
    // Prefer the web-renderable preview (e.g. a flattened PNG generated for
    // PSD/TIFF/HEIC) so non-browser-native formats still show a thumbnail,
    // mirroring the Folders/Assets grid. Fall back to the raw asset URL for
    // natively renderable images (jpg/png/gif/webp/...).
    const previewSrc = item.preview_url || item.url;
    const hasGeneratedPreview = Boolean(item.properties?.preview_storage_path);
    const isImg   = (item.media_type === 'image' || hasGeneratedPreview) && Boolean(previewSrc);
    const [imgError, setImgError] = useState(false);
    const truncate = (s, n) => s?.length > n ? s.substring(0, n) + '…' : (s || '—');
    const daysLeft = item.expires_at
        ? Math.max(0, Math.ceil((new Date(item.expires_at) - Date.now()) / 86400000))
        : null;

    return (
        <Box sx={{
            width: cfg.width, display: 'flex', flexDirection: 'column',
            border: isSelected ? '2px solid #6366f1' : '1px solid #e2e8f0',
            borderRadius: 2, bgcolor: '#fff', overflow: 'hidden',
            transition: 'box-shadow 0.15s, border-color 0.15s',
            '&:hover': { boxShadow: '0 4px 16px rgba(0,0,0,0.08)', borderColor: '#a5b4fc' },
            position: 'relative',
        }}>
            {/* Selection checkbox */}
            <Box sx={{ position: 'absolute', top: 6, left: 6, zIndex: 10 }}>
                <Checkbox
                    size="small" checked={isSelected}
                    onClick={(e) => { e.stopPropagation(); onToggleSelect(item.grid_id); }}
                    sx={{
                        color: 'rgba(255,255,255,0.8)',
                        bgcolor: isSelected ? 'rgba(255,255,255,0.9)' : 'rgba(0,0,0,0.2)',
                        borderRadius: '4px', p: 0.5,
                        '&:hover': { bgcolor: 'rgba(255,255,255,0.9)' }
                    }}
                />
            </Box>

            {/* Expiry warning badge */}
            {daysLeft !== null && daysLeft <= 7 && (
                <Box sx={{ position: 'absolute', top: 6, right: 6, zIndex: 10 }}>
                    <Chip
                        icon={<TimerOffOutlined />} size="small"
                        label={daysLeft === 0 ? t('bin.retention.expires', { days: '<1' }) : t('bin.retention.expires', { days: daysLeft })}
                        color={daysLeft <= 2 ? 'error' : 'warning'}
                        sx={{ fontWeight: 600, fontSize: '0.65rem' }}
                    />
                </Box>
            )}

            {/* Thumbnail / icon */}
            <Box sx={{ height: cfg.imgHeight, bgcolor: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
                {isImg && !imgError ? (
                    <img src={previewSrc} alt={item.name} loading="lazy"
                        onError={() => setImgError(true)}
                        style={{ width: '100%', height: '100%', objectFit: 'cover', filter: 'opacity(0.8)' }} />
                ) : (
                    getIcon(item.content_type, item.media_type)
                )}
            </Box>

            {/* Info bar */}
            <Box sx={{ p: 1.25, flexGrow: 1, display: 'flex', flexDirection: 'column', gap: 0.5 }}>
                <Tooltip title={item.name} placement="top-start">
                    <Typography variant="body2" sx={{ fontWeight: 600, lineHeight: 1.3, color: '#1e293b' }}>
                        {truncate(item.name, cfg.titleLen)}
                    </Typography>
                </Tooltip>
                <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                    {item.size_human || (item.item_type === 'folder' ? t('bin.item.folder') : '—')}
                </Typography>
                <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                    {new Date(item.deleted_at).toLocaleDateString()}
                </Typography>
            </Box>

            {/* Actions */}
            <Box sx={{ display: 'flex', borderTop: '1px solid #f1f5f9', bgcolor: '#fafafa' }}>
                <Tooltip title={t('bin.item.restore')}>
                    <IconButton size="small" color="success" onClick={() => onRestore(item)}
                        sx={{ flexGrow: 1, borderRadius: 0, py: 0.75 }}>
                        <RestoreFromTrashOutlined fontSize="small" />
                    </IconButton>
                </Tooltip>
                <Box sx={{ width: 1, bgcolor: '#f1f5f9' }} />
                <Tooltip title={t('bin.item.deletePermanently')}>
                    <IconButton size="small" color="error" onClick={() => onDelete(item)}
                        sx={{ flexGrow: 1, borderRadius: 0, py: 0.75 }}>
                        <DeleteForeverOutlined fontSize="small" />
                    </IconButton>
                </Tooltip>
            </Box>
        </Box>
    );
};

export default function BinGrid({ items, isSelected, onToggleSelect, onRestore, onDelete, gridSize, loading }) {
    if (loading && items.length === 0) {
        // Skeleton placeholders
        return (
            <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 2 }}>
                {[...Array(8)].map((_, i) => (
                    <Box key={i} sx={{ width: CARD_SIZES[gridSize]?.width || 200, height: CARD_SIZES[gridSize]?.height || 175, bgcolor: '#e2e8f0', borderRadius: 2 }} />
                ))}
            </Box>
        );
    }

    return (
        <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 2, alignItems: 'flex-start' }}>
            {items.map(item => (
                <BinCard
                    key={item.grid_id}
                    item={item}
                    isSelected={isSelected(item.grid_id)}
                    onToggleSelect={onToggleSelect}
                    onRestore={onRestore}
                    onDelete={onDelete}
                    size={gridSize}
                />
            ))}
        </Box>
    );
}

