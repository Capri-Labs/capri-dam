import React, { useState } from 'react';
import {
    Dialog, AppBar, Toolbar, IconButton, Typography, Box, Grid,
    Button, Divider, Chip
} from '@mui/material';
import { Close, Edit, Download } from '@mui/icons-material';
import ImageEditorDialog from '../ImageEditorDialog';
import WorkflowPanel from '../WorkflowPanel';

export default function AssetViewer({ asset, open, onClose, onAssetUpdated }) {
    const [editorOpen, setEditorOpen] = useState(false);

    if (!asset) return null;

    const isImage = asset.properties?.content_type?.startsWith('image/');
    const displayName = asset.title || asset.name || "Unknown File";

    return (
        <Dialog fullScreen open={open} onClose={onClose}>
            {/* TOP NAVIGATION BAR */}
            <AppBar sx={{ position: 'relative', bgcolor: '#1e293b', boxShadow: 'none' }}>
                <Toolbar>
                    <IconButton edge="start" color="inherit" onClick={onClose} aria-label="close">
                        <Close />
                    </IconButton>
                    <Typography sx={{ ml: 2, flex: 1 }} variant="h6" component="div" noWrap>
                        {displayName}
                    </Typography>

                    {/* Action Buttons */}
                    <Button color="inherit" startIcon={<Download />} sx={{ mr: 2 }}>
                        Download Original
                    </Button>
                    {isImage && (
                        <Button
                            variant="contained"
                            color="primary"
                            startIcon={<Edit />}
                            onClick={() => setEditorOpen(true)}
                        >
                            Edit Image
                        </Button>
                    )}
                </Toolbar>
            </AppBar>

            {/* SPLIT SCREEN WORKSPACE */}
            <Grid container sx={{ height: 'calc(100vh - 64px)' }}>

                {/* LEFT PANE: Media Preview */}
                <Grid item xs={12} md={8} sx={{
                    bgcolor: '#f1f5f9',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    p: 4,
                    borderRight: '1px solid #cbd5e1'
                }}>
                    {isImage && asset.url ? (
                        <Box
                            component="img"
                            src={asset.url}
                            alt={displayName}
                            sx={{
                                maxWidth: '100%',
                                maxHeight: '100%',
                                objectFit: 'contain',
                                boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.1)'
                            }}
                        />
                    ) : (
                        <Typography color="textSecondary">Preview not available for this file type.</Typography>
                    )}
                </Grid>

                {/* RIGHT PANE: Metadata & Status */}
                <Grid item xs={12} md={4} sx={{ bgcolor: '#ffffff', overflowY: 'auto', p: 3 }}>
                    <Box sx={{ mb: 3, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                        <Typography variant="h6" fontWeight="bold">Asset Details</Typography>
                        <Chip
                            label={asset.status || 'Pending'}
                            color={asset.status === 'approved' ? 'success' : 'warning'}
                            size="small"
                        />
                    </Box>
                    <Divider sx={{ mb: 3 }} />

                    {/* 🚨 NEW: The Workflow Engine UI */}
                    <WorkflowPanel
                        assetId={asset.id}
                        onWorkflowUpdate={() => {
                            // If you passed a refresh function down from AssetExplorer, trigger it here
                            // so the asset's overall status (in_review -> approved) updates in real time
                            if (onAssetUpdated) onAssetUpdated(asset);
                        }}
                    />
                </Grid>
            </Grid>

            {/* IMAGE EDITOR MODAL */}
            {isImage && (
                <ImageEditorDialog
                    asset={asset}
                    open={editorOpen}
                    onClose={() => setEditorOpen(false)}
                    onSave={(updatedAsset) => {
                        setEditorOpen(false);
                        onAssetUpdated(updatedAsset);
                    }}
                />
            )}
        </Dialog>
    );
}