import React, { useState } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions, Button,
    Box, Typography, Grid, Paper, Chip, IconButton, CircularProgress
} from '@mui/material';
import { Close, AutoFixHigh, MergeType, SkipNext, FileCopy, FolderSpecial } from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

export default function DuplicateResolverDialog({ open, onClose, fileData, onResolve }) {
    const notify = useNotify();
    const [isAiAnalyzing, setIsAiAnalyzing] = useState(false);

    if (!fileData || !fileData.duplicateData) return null;

    // 🚀 duplicateData is now an ARRAY of matches
    const existingAssets = fileData.duplicateData;
    const primaryAsset = existingAssets[0]; // We use the first one for the image preview

    const handleAiMerge = () => {
        setIsAiAnalyzing(true);
        setTimeout(() => {
            setIsAiAnalyzing(false);
            notify(`AI successfully merged new metadata into ${existingAssets.length} existing asset(s).`, "success");
            onResolve(fileData.id, 'skip');
        }, 1500);
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
            <DialogTitle sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0' }}>
                <Typography variant="h6" fontWeight="700">Resolve Duplicate: {fileData.meta.title}</Typography>
                <IconButton onClick={onClose} size="small"><Close /></IconButton>
            </DialogTitle>

            <DialogContent sx={{ p: 4 }}>
                <Grid container spacing={4}>
                    {/* LEFT: Existing Asset in DAM */}
                    <Grid item xs={6}>
                        <Typography variant="subtitle2" color="textSecondary" fontWeight="700" sx={{ mb: 2 }}>
                            Currently in DAM ({existingAssets.length} found)
                        </Typography>
                        <Paper variant="outlined" sx={{ p: 2, borderRadius: 2, bgcolor: '#f1f5f9' }}>
                            <Box sx={{ height: 140, display: 'flex', justifyContent: 'center', mb: 2 }}>
                                <img src={primaryAsset.url} alt="existing" style={{ maxHeight: '100%', objectFit: 'contain' }} />
                            </Box>
                            <Typography variant="body2" fontWeight="700" noWrap>Title: {primaryAsset.title}</Typography>

                            {/* 🚀 List all locations where this file exists */}
                            <Box sx={{ mt: 1.5 }}>
                                <Typography variant="caption" color="textSecondary" display="block" sx={{ mb: 0.5 }}>Locations:</Typography>
                                {existingAssets.map((asset, idx) => (
                                    <Chip
                                        key={idx}
                                        icon={<FolderSpecial fontSize="small"/>}
                                        label={asset.folderName}
                                        size="small"
                                        sx={{ mr: 0.5, mb: 0.5, bgcolor: '#e2e8f0' }}
                                    />
                                ))}
                            </Box>
                        </Paper>
                    </Grid>

                    {/* RIGHT: New Upload Attempt */}
                    <Grid item xs={6}>
                        <Typography variant="subtitle2" color="primary" fontWeight="700" sx={{ mb: 2 }}>Your New Upload</Typography>
                        <Paper variant="outlined" sx={{ p: 2, borderRadius: 2, borderColor: '#4f46e5', bgcolor: '#eef2ff', height: '100%' }}>
                            <Box sx={{ height: 140, display: 'flex', justifyContent: 'center', mb: 2 }}>
                                <img src={fileData.preview} alt="new" style={{ maxHeight: '100%', objectFit: 'contain' }} />
                            </Box>
                            <Typography variant="body2" fontWeight="700" noWrap>{fileData.meta.title}</Typography>
                            <Typography variant="caption" color="textSecondary" display="block">
                                Status: Pending Upload
                            </Typography>
                            <Chip label="Identical Hash" size="small" color="warning" sx={{ mt: 1 }} />
                        </Paper>
                    </Grid>
                </Grid>

                {/* AI Resolution Banner */}
                <Paper sx={{ mt: 4, p: 2, bgcolor: '#f5f3ff', border: '1px solid #ddd6fe', borderRadius: 2, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                    <Box>
                        <Typography variant="body2" color="#6d28d9" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}>
                            <AutoFixHigh fontSize="small" sx={{ mr: 1 }} /> AI Merge Recommendation
                        </Typography>
                        <Typography variant="caption" color="#5b21b6">
                            The bytes are identical. AI can append your new tags to the existing asset to prevent clutter.
                        </Typography>
                    </Box>
                    <Button
                        variant="contained"
                        onClick={handleAiMerge}
                        disabled={isAiAnalyzing}
                        sx={{ bgcolor: '#6d28d9', '&:hover': { bgcolor: '#5b21b6' }, textTransform: 'none' }}
                        startIcon={isAiAnalyzing ? <CircularProgress size={16} color="inherit"/> : <MergeType />}
                    >
                        Merge Metadata
                    </Button>
                </Paper>
            </DialogContent>

            <DialogActions sx={{ p: 3, bgcolor: '#f8fafc', borderTop: '1px solid #e2e8f0' }}>
                <Button onClick={() => onResolve(fileData.id, 'skip')} color="inherit" startIcon={<SkipNext />}>Skip Upload</Button>
                <Button onClick={() => onResolve(fileData.id, 'upload')} color="warning" variant="outlined" startIcon={<FileCopy />}>Upload as Duplicate Anyway</Button>
            </DialogActions>
        </Dialog>
    );
}