import React from 'react';
import { Box, Typography, Grid, Paper, Checkbox, Tooltip } from '@mui/material';
import { Folder as FolderIcon } from '@mui/icons-material';

export default function FolderGrid({ folders, viewMode, selectedItems, toggleSelection, handleNavigate }) {
    const formatFileName = (name) => (!name ? "Unknown" : name.length > 15 ? `${name.substring(0, 15)}...` : name);

    if (!folders || folders.length === 0) return null;

    return (
        <Box sx={{ mb: 5 }}>
            <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.05em', mb: 2 }}>Folders</Typography>
            <Grid container spacing={2}>
                {folders.map(folder => (
                    <Grid item xs={6} sm={4} md={3} lg={2} key={folder.id}>
                        <Paper
                            elevation={0}
                            onClick={(e) => viewMode === 'bin' ? toggleSelection('folders', folder.id, e) : handleNavigate(folder.id)}
                            sx={{
                                position: 'relative', p: 2, height: 80, display: 'flex', alignItems: 'center', gap: 1.5,
                                border: selectedItems.folders.includes(folder.id) ? '2px solid #4f46e5' : '1px solid #e2e8f0',
                                bgcolor: selectedItems.folders.includes(folder.id) ? '#eef2ff' : '#ffffff',
                                borderRadius: '12px', cursor: 'pointer', transition: 'all 0.2s',
                                '&:hover': { borderColor: '#4f46e5', boxShadow: '0 4px 12px rgba(0,0,0,0.05)' }
                            }}
                        >
                            <Checkbox size="small" checked={selectedItems.folders.includes(folder.id)} onClick={(e) => toggleSelection('folders', folder.id, e)} sx={{ position: 'absolute', top: 4, right: 4, p: 0.5 }} />
                            <FolderIcon sx={{ fontSize: 48, minWidth: 60, minHeight: 60, color: '#4299e1' }} />
                            <Tooltip title={folder.name} placement="top-start">
                                <Typography variant="body2" fontWeight="600" sx={{ color: '#1e293b' }}>
                                    {formatFileName(folder.name)}
                                </Typography>
                            </Tooltip>
                        </Paper>
                    </Grid>
                ))}
            </Grid>
        </Box>
    );
}