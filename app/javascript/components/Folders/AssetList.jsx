import React from 'react';
import { TableContainer, Table, TableHead, TableRow, TableCell, TableBody, Checkbox, Box, Typography, IconButton, Paper } from '@mui/material';
import { InsertPhoto, PictureAsPdf, VideoFile, InsertDriveFile, InfoOutlined } from '@mui/icons-material';

export default function AssetList({ assets, viewMode, selectedItems, toggleSelection, setSelectedAsset }) {

    const getFileIcon = (contentType) => {
        if (!contentType) return <InsertDriveFile sx={{ color: '#64748b' }} />;
        if (contentType.startsWith('image/')) return <InsertPhoto sx={{ color: '#10b981' }} />;
        if (contentType === 'application/pdf') return <PictureAsPdf sx={{ color: '#ef4444' }} />;
        if (contentType.startsWith('video/')) return <VideoFile sx={{ color: '#3b82f6' }} />;
        return <InsertDriveFile sx={{ color: '#64748b' }} />;
    };

    return (
        <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', borderRadius: 3, mb: 8 }}>
            <Table size="small">
                <TableHead sx={{ bgcolor: '#f8fafc' }}>
                    <TableRow>
                        <TableCell padding="checkbox"></TableCell>
                        <TableCell sx={{ fontWeight: 600, color: '#475569' }}>Name</TableCell>
                        <TableCell sx={{ fontWeight: 600, color: '#475569' }}>Type</TableCell>
                        <TableCell sx={{ fontWeight: 600, color: '#475569' }}>Added</TableCell>
                        <TableCell align="right" sx={{ fontWeight: 600, color: '#475569' }}>Actions</TableCell>
                    </TableRow>
                </TableHead>
                <TableBody>
                    {assets.map((asset) => {
                        const isSelected = selectedItems.assets.includes(asset.id);
                        const displayName = asset.name || asset.title || "Unknown File";
                        let metadata = {};
                        try { metadata = typeof asset.properties === 'string' ? JSON.parse(asset.properties) : (asset.properties || {}); } catch(e) {}

                        return (
                            <TableRow
                                key={asset.id}
                                hover
                                selected={isSelected}
                                onClick={(e) => viewMode === 'bin' ? toggleSelection('assets', asset.id, e) : setSelectedAsset(asset)}
                                sx={{ cursor: 'pointer', '&.Mui-selected': { bgcolor: '#eef2ff' } }}
                            >
                                <TableCell padding="checkbox">
                                    <Checkbox size="small" checked={isSelected} onClick={(e) => toggleSelection('assets', asset.id, e)} />
                                </TableCell>
                                <TableCell>
                                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                                        {getFileIcon(metadata.content_type)}
                                        <Typography variant="body2" sx={{ fontWeight: 500 }}>{displayName}</Typography>
                                    </Box>
                                </TableCell>
                                <TableCell sx={{ color: '#64748b' }}>{metadata.content_type || 'Unknown'}</TableCell>
                                <TableCell sx={{ color: '#64748b' }}>{new Date(asset.created_at).toLocaleDateString()}</TableCell>
                                <TableCell align="right">
                                    <IconButton size="small" onClick={(e) => { e.stopPropagation(); setSelectedAsset(asset); }}>
                                        <InfoOutlined fontSize="small" />
                                    </IconButton>
                                </TableCell>
                            </TableRow>
                        );
                    })}
                </TableBody>
            </Table>
        </TableContainer>
    );
}