import React, { useState } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Button, Typography, Box, IconButton, Checkbox,
    Card, CardMedia, CardContent, Chip
} from '@mui/material';
import {ContentCopy, Check, PlayCircleFilled, DeleteOutlined} from '@mui/icons-material';

export default function DuplicateResolutionModal({ open, duplicateGroup, onClose, onResolve }) {
    // Track which specific asset IDs the user has selected for deletion
    const [selectedIds, setSelectedIds] = useState([]);

    if (!duplicateGroup) return null;

    const assets = duplicateGroup.assets || [];

    const toggleSelection = (id) => {
        setSelectedIds(prev =>
            prev.includes(id) ? prev.filter(item => item !== id) : [...prev, id]
        );
    };

    const handleAccept = () => {
        // "Accept" means we ignore the duplicates and keep them all
        onResolve(duplicateGroup.id, 'accept', []);
    };

    const handleDelete = () => {
        if (selectedIds.length === 0) return;
        // Pass the selected IDs up to the parent to execute the deletion
        onResolve(duplicateGroup.id, 'delete', selectedIds);
    };

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth="md"
            fullWidth
            PaperProps={{ sx: { borderRadius: 3, p: 1 } }}
        >
            {/* Custom Header matching the screenshot */}
            <DialogTitle sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', pb: 1 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    <Box sx={{ bgcolor: '#f1f5f9', p: 1, borderRadius: 2, display: 'flex' }}>
                        <ContentCopy sx={{ color: '#64748b' }} />
                    </Box>
                    <Box>
                        <Typography variant="h6" sx={{ fontWeight: 600, color: '#1e293b', lineHeight: 1.2 }}>
                            Duplicates
                        </Typography>
                        <Typography variant="body2" sx={{ color: '#64748b' }}>
                            {assets.length} assets found
                        </Typography>
                    </Box>
                </Box>

                <Box sx={{ display: 'flex', gap: 2 }}>
                    <Button
                        color="inherit"
                        startIcon={<Check />}
                        onClick={handleAccept}
                        sx={{ textTransform: 'none', color: '#475569', fontWeight: 600 }}
                    >
                        Accept
                    </Button>
                    <Button
                        color="inherit"
                        startIcon={<DeleteOutlined />}
                        onClick={handleDelete}
                        disabled={selectedIds.length === 0}
                        sx={{
                            textTransform: 'none', fontWeight: 600,
                            color: selectedIds.length > 0 ? '#ef4444' : '#94a3b8'
                        }}
                    >
                        Delete
                    </Button>
                </Box>
            </DialogTitle>

            <DialogContent sx={{ pt: 3, pb: 4 }}>
                <Box sx={{ display: 'flex', gap: 3, flexWrap: 'wrap', justifyContent: 'center' }}>
                    {assets.map((asset) => {
                        const isSelected = selectedIds.includes(asset.id);
                        const ext = asset.name.split('.').pop().toUpperCase();

                        return (
                            <Card
                                key={asset.id}
                                onClick={() => toggleSelection(asset.id)}
                                elevation={0}
                                sx={{
                                    width: 240,
                                    cursor: 'pointer',
                                    borderRadius: 2,
                                    border: isSelected ? '3px solid #3b82f6' : '1px solid #e2e8f0',
                                    transition: 'all 0.2s',
                                    position: 'relative',
                                    overflow: 'visible'
                                }}
                            >
                                {/* Selected Checkmark Badge */}
                                {isSelected && (
                                    <Box sx={{
                                        position: 'absolute', top: -10, right: -10, zIndex: 10,
                                        bgcolor: '#3b82f6', color: 'white', borderRadius: '50%',
                                        width: 24, height: 24, display: 'flex', alignItems: 'center', justifyContent: 'center'
                                    }}>
                                        <Check sx={{ fontSize: 16, strokeWidth: 2 }} />
                                    </Box>
                                )}

                                <Box sx={{ position: 'relative' }}>
                                    <CardMedia
                                        component="img"
                                        height="160"
                                        image={asset.url}
                                        alt={asset.name}
                                        sx={{
                                            objectFit: 'cover',
                                            borderTopLeftRadius: 8, borderTopRightRadius: 8,
                                            opacity: isSelected ? 0.9 : 1
                                        }}
                                    />

                                    {/* Format Badge (e.g., JPG) */}
                                    <Chip
                                        label={ext}
                                        size="small"
                                        sx={{
                                            position: 'absolute', bottom: 8, right: 8,
                                            bgcolor: 'rgba(255,255,255,0.7)', fontWeight: 600, fontSize: '0.7rem'
                                        }}
                                    />
                                </Box>

                                <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
                                    <Typography variant="body2" sx={{ fontWeight: 600, color: '#1e293b' }} noWrap>
                                        {asset.name}
                                    </Typography>
                                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                        Upload date: {asset.upload_date}
                                    </Typography>
                                </CardContent>
                            </Card>
                        );
                    })}
                </Box>
            </DialogContent>
        </Dialog>
    );
}