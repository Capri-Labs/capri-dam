import React from 'react';
import { Box, ImageList, ImageListItem, ImageListItemBar, Checkbox, IconButton, Tooltip, Typography } from '@mui/material';
import { PictureAsPdf, VideoFile, InsertDriveFile, PlayCircleFilled, Visibility, InfoOutlined } from '@mui/icons-material';

export default function AssetGrid({ assets, viewMode, selectedItems, toggleSelection, setSelectedAsset }) {
    const formatFileName = (name) => (!name ? "Unknown" : name.length > 15 ? `${name.substring(0, 15)}...` : name);

    return (
        <ImageList gap={16} sx={{ mb: 8, gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr)) !important', overflow: 'visible' }}>
            {assets.map((asset) => {
                const displayName = asset.name || asset.title || "Unknown File";
                let metadata = {};
                try { metadata = typeof asset.properties === 'string' ? JSON.parse(asset.properties) : (asset.properties || {}); } catch(e) {}

                const contentType = typeof metadata.content_type === 'string' ? metadata.content_type : '';
                const isImage = contentType.startsWith('image/');
                const isPdf = contentType === 'application/pdf';
                const isVideo = contentType.startsWith('video/');
                const isSelected = selectedItems.assets.includes(asset.id);

                return (
                    <ImageListItem
                        key={asset.id}
                        onClick={(e) => viewMode === 'bin' ? toggleSelection('assets', asset.id, e) : setSelectedAsset(asset)}
                        sx={{
                            cursor: 'pointer', borderRadius: '12px', overflow: 'hidden', border: isSelected ? '2px solid #4f46e5' : '1px solid #e2e8f0', bgcolor: '#ffffff', transition: 'all 0.2s ease-in-out',
                            '&:hover': { transform: 'translateY(-4px)', boxShadow: '0 12px 24px rgba(0,0,0,0.1)', borderColor: '#4f46e5', '& .media-overlay': { opacity: 1 } }
                        }}
                    >
                        <Box sx={{ position: 'absolute', top: 8, left: 8, zIndex: 10 }}>
                            <Checkbox size="small" checked={isSelected} onClick={(e) => toggleSelection('assets', asset.id, e)} sx={{ color: 'rgba(255,255,255,0.8)', bgcolor: isSelected ? 'rgba(255,255,255,0.9)' : 'rgba(0,0,0,0.2)', borderRadius: '4px', p: 0.5, '&:hover': { bgcolor: 'rgba(255,255,255,0.9)' } }} />
                        </Box>
                        <Box sx={{ position: 'relative', width: '100%', height: '200px' }}>
                            {isImage && asset.url ? (
                                <img src={`${asset.url}?w=248&fit=crop&auto=format`} alt={displayName} loading="lazy" style={{ height: '100%', width: '100%', objectFit: 'cover' }} />
                            ) : (
                                <Box sx={{ height: '100%', width: '100%', bgcolor: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                                    {isPdf && <PictureAsPdf sx={{ fontSize: 64, color: '#ef4444' }} />}
                                    {isVideo && <VideoFile sx={{ fontSize: 64, color: '#3b82f6' }} />}
                                    {!isPdf && !isVideo && <InsertDriveFile sx={{ fontSize: 64, color: '#64748b' }} />}
                                </Box>
                            )}
                            <Box className="media-overlay" sx={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, bgcolor: 'rgba(15, 23, 42, 0.4)', opacity: 0, transition: 'opacity 0.2s', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 5 }}>
                                {isVideo ? <PlayCircleFilled sx={{ fontSize: 56, color: '#ffffff' }} /> : <Visibility sx={{ fontSize: 48, color: '#ffffff' }} />}
                            </Box>
                        </Box>
                        <ImageListItemBar
                            title={<Tooltip title={displayName} placement="top-start"><Typography variant="subtitle2" sx={{ fontWeight: 600 }}>{formatFileName(displayName)}</Typography></Tooltip>}
                            actionIcon={<IconButton sx={{ color: 'rgba(255, 255, 255, 0.7)', '&:hover': { color: '#ffffff' } }} onClick={(e) => { e.stopPropagation(); setSelectedAsset(asset); }}><InfoOutlined /></IconButton>}
                        />
                    </ImageListItem>
                );
            })}
        </ImageList>
    );
}