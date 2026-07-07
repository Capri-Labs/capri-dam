import React, { useState } from 'react';
import {
    Card, CardContent, CardMedia, Typography, Box,
    IconButton, Tooltip, Stack, Menu, MenuItem, Divider
} from '@mui/material';
import {
    PushPinOutlined, InfoOutlined, MoreVert,
    CloudDownload, DeleteOutlined, HourglassTopOutlined, BrokenImageOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

export default function AssetCard({ asset, onPin, onViewMore }) {
    const { t } = useTranslation();
    const tr = (key, defaultValue) => {
        const value = t(key, { defaultValue });
        return value === key ? defaultValue : value;
    };
    const [anchorEl, setAnchorEl] = useState(null);
    const [imgError, setImgError] = useState(false);

    const handleMenuOpen = (e) => {
        e.stopPropagation();
        setAnchorEl(e.currentTarget);
    };

    const handleMenuClose = (e) => {
        if (e) e.stopPropagation();
        setAnchorEl(null);
    };

    // Fallback for missing data
    const filename = asset.original_filename || asset.title || tr('assetCard.unknownAsset', 'Unknown Asset');
    const fileSize = asset.file_size || asset.size || tr('assetCard.unknownSize', 'Unknown Size');
    // The background worker (AssetProcessorWorker) hasn't finished yet — any
    // preview/download URL is guaranteed to 404 until it does, so we show a
    // "Processing…" placeholder instead of attempting to load a broken image.
    const isProcessing = asset.status === 'pending' || asset.status === 'processing';
    const previewSrc = asset.preview_url || asset.url;
    const showImage = Boolean(previewSrc) && !isProcessing && !imgError;

    return (
        <Card
            elevation={0}
            sx={{
                height: '100%',
                display: 'flex',
                flexDirection: 'column',
                border: '1px solid #e2e8f0',
                borderRadius: 2,
                position: 'relative',
                transition: 'all 0.2s ease-in-out',
                '&:hover': {
                    borderColor: '#94a3b8',
                    boxShadow: '0 4px 12px rgba(0,0,0,0.05)',
                    '& .asset-actions': { opacity: 1 } // Reveal actions on hover
                }
            }}
        >
            {/* Image / Thumbnail Area */}
            <Box sx={{ position: 'relative', height: 160, bgcolor: '#f1f5f9', borderBottom: '1px solid #e2e8f0' }}>
                {isProcessing ? (
                    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 0.5 }}>
                        <HourglassTopOutlined sx={{ fontSize: 32, color: '#94a3b8' }} />
                        <Typography variant="caption" color="textSecondary">{tr('assetCard.processing', 'Processing…')}</Typography>
                    </Box>
                ) : showImage ? (
                    <CardMedia
                        component="img"
                        image={previewSrc}
                        alt={filename}
                        onError={() => setImgError(true)}
                        sx={{ height: '100%', objectFit: 'cover' }}
                    />
                ) : (
                    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 0.5 }}>
                        {imgError && <BrokenImageOutlined sx={{ fontSize: 28, color: '#94a3b8' }} />}
                        <Typography variant="caption" color="textSecondary">
                            {imgError ? tr('assetCard.previewUnavailable', 'Preview unavailable') : tr('assetCard.noPreview', 'No Preview')}
                        </Typography>
                    </Box>
                )}

                {/* Floating Quick Actions (Revealed on Hover) */}
                <Stack
                    className="asset-actions"
                    direction="row"
                    spacing={0.5}
                    sx={{
                        position: 'absolute', top: 8, right: 8,
                        opacity: 0, transition: 'opacity 0.2s',
                        bgcolor: 'rgba(255,255,255,0.9)', borderRadius: 1, p: 0.5,
                        boxShadow: '0 2px 4px rgba(0,0,0,0.1)'
                    }}
                >
                    <Tooltip title={tr('assetCard.tooltips.pinToCollection', 'Pin to Collection')}>
                        <IconButton size="small" onClick={(e) => { e.stopPropagation(); onPin(asset); }} sx={{ color: '#5e35b1' }}>
                            <PushPinOutlined fontSize="small" />
                        </IconButton>
                    </Tooltip>
                    <Tooltip title={tr('assetCard.tooltips.viewDetails', 'View Details')}>
                        <IconButton size="small" onClick={(e) => { e.stopPropagation(); onViewMore(asset); }} sx={{ color: '#0ea5e9' }}>
                            <InfoOutlined fontSize="small" />
                        </IconButton>
                    </Tooltip>
                </Stack>
            </Box>

            {/* Metadata Area */}
            <CardContent sx={{ p: 2, flexGrow: 1, '&:last-child': { pb: 2 } }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <Box sx={{ overflow: 'hidden', pr: 1 }}>
                        <Typography
                            variant="subtitle2"
                            sx={{ fontWeight: 600, color: '#1e293b', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}
                            title={filename}
                        >
                            {filename}
                        </Typography>
                        <Typography variant="caption" sx={{ color: '#64748b' }}>
                            {fileSize}
                        </Typography>
                    </Box>

                    <IconButton size="small" onClick={handleMenuOpen} sx={{ mt: -0.5, mr: -1 }}>
                        <MoreVert fontSize="small" />
                    </IconButton>
                </Box>
            </CardContent>

            {/* Standard Asset Context Menu */}
            <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleMenuClose} elevation={2} slotProps={{paper: { sx: { borderRadius: 2, minWidth: 160 } } }}>
                <MenuItem onClick={(e) => { handleMenuClose(e); onViewMore(asset); }}>
                    <InfoOutlined fontSize="small" sx={{ mr: 1.5, color: '#475569' }} /> {tr('assetCard.menu.viewDetails', 'View Details')}
                </MenuItem>
                <MenuItem onClick={(e) => { handleMenuClose(e); onPin(asset); }}>
                    <PushPinOutlined fontSize="small" sx={{ mr: 1.5, color: '#5e35b1' }} /> {tr('assetCard.menu.addToCollection', 'Add to Collection')}
                </MenuItem>
                <Divider />
                <MenuItem onClick={handleMenuClose}>
                    <CloudDownload fontSize="small" sx={{ mr: 1.5, color: '#64748b' }} /> {tr('asset.url.download', 'Download')}
                </MenuItem>
                <MenuItem onClick={handleMenuClose} sx={{ color: '#d32f2f' }}>
                    <DeleteOutlined fontSize="small" sx={{ mr: 1.5 }} /> {tr('assetCard.menu.moveToTrash', 'Move to Trash')}
                </MenuItem>
            </Menu>
        </Card>
    );
}