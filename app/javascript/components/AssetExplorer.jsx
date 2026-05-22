import React, { useState, useEffect } from 'react';
import {
    Box, Grid, Typography, Breadcrumbs, Link, Paper, Stack, IconButton,
    Button, Dialog, DialogTitle, DialogContent, DialogActions, TextField, Tooltip, Divider,
    ImageList, ImageListItem, ImageListItemBar, Checkbox, FormControlLabel // <-- Added Checkbox
} from '@mui/material';
import {
    Folder as FolderIcon, InsertDriveFile, InfoOutlined,
    Home, CreateNewFolder, CloudUpload, DeleteOutlined, // <-- Added Delete Icon
    PictureAsPdf, VideoFile
} from '@mui/icons-material';
import AssetViewer from './AssetViewer';

export default function AssetExplorer({ initialTargetAssetId }) {
    const [viewData, setViewData] = useState({ folders: [], assets: [], breadcrumbs: [] });
    const [currentId, setCurrentId] = useState('root');

    const [viewMode, setViewMode] = useState('active');

    // Viewer & Dialog States
    const [selectedAsset, setSelectedAsset] = useState(null);
    const [openFolderDialog, setOpenFolderDialog] = useState(false);
    const [newFolderName, setNewFolderName] = useState('');

    // NEW: Bulk Selection States
    const [selectedItems, setSelectedItems] = useState({ folders: [], assets: [] });

    // 🚨 NEW: Listen for routing requests from the Workflow Dashboard
    useEffect(() => {
        if (initialTargetAssetId) {
            // Find the asset in the currently loaded view data
            const targetAsset = viewData.assets?.find(a => a.id === initialTargetAssetId);

            if (targetAsset) {
                // If it's already in the current folder, just open it!
                setSelectedAsset(targetAsset);
            } else {
                // Advanced: If it's in a different folder, you would fetch it directly from the API
                // using /api/v1/assets/${initialTargetAssetId} and then call setSelectedAsset
                fetch(`/api/v1/assets/${initialTargetAssetId}`)
                    .then(res => res.json())
                    .then(data => setSelectedAsset(data));
            }
        }
    }, [initialTargetAssetId, viewData.assets]);

    const loadContent = () => {
        if (viewMode === 'bin') {
            fetch('/api/v1/bin') // The new endpoint we just made
                .then(res => res.json())
                .then(data => {
                    setViewData(data);
                    setSelectedItems({ folders: [], assets: [] });
                });
        } else {
            fetch(`/api/v1/folders/${currentId}`)
                .then(res => res.json())
                .then(data => {
                    setViewData(data);
                    setSelectedItems({ folders: [], assets: [] });
                });
        }
    };

    useEffect(() => { loadContent(); }, [currentId, viewMode]);

    // New action for restoring items
    const handleRestoreSelected = async () => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const headers = { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken };

        const assetPromises = selectedItems.assets.map(id => fetch(`/api/v1/assets/${id}/restore`, { method: 'POST', headers }));
        const folderPromises = selectedItems.folders.map(id => fetch(`/api/v1/folders/${id}/restore`, { method: 'POST', headers }));

        await Promise.all([...assetPromises, ...folderPromises]);
        loadContent();
    };

    // New action for permanent destruction
    const handlePermanentDelete = async () => {
        if (!window.confirm("WARNING: This will permanently delete these files from the server. This cannot be undone!")) return;

        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const headers = { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken };

        const assetPromises = selectedItems.assets.map(id => fetch(`/api/v1/assets/${id}/permanent`, { method: 'DELETE', headers }));
        const folderPromises = selectedItems.folders.map(id => fetch(`/api/v1/folders/${id}/permanent`, { method: 'DELETE', headers }));

        await Promise.all([...assetPromises, ...folderPromises]);
        loadContent();
    };

    // --- BULK SELECTION LOGIC ---
    const handleSelectAll = (event) => {
        if (event.target.checked) {
            setSelectedItems({
                folders: viewData.folders.map(f => f.id),
                assets: viewData.assets.map(a => a.id)
            });
        } else {
            setSelectedItems({ folders: [], assets: [] });
        }
    };

    const toggleSelection = (type, id, event) => {
        event.stopPropagation(); // Prevent opening folders/viewers when clicking the checkbox
        setSelectedItems(prev => {
            const list = prev[type];
            if (list.includes(id)) {
                return { ...prev, [type]: list.filter(itemId => itemId !== id) };
            } else {
                return { ...prev, [type]: [...list, id] };
            }
        });
    };

    const isAllSelected = (viewData.folders?.length > 0 || viewData.assets?.length > 0) &&
        selectedItems.folders.length === (viewData.folders?.length || 0) &&
        selectedItems.assets.length === (viewData.assets?.length || 0);

    const hasSelection = selectedItems.folders.length > 0 || selectedItems.assets.length > 0;

    // --- DELETE LOGIC ---
    const handleDeleteSelected = async () => {
        const totalCount = selectedItems.folders.length + selectedItems.assets.length;
        if (!window.confirm(`Are you sure you want to delete ${totalCount} selected item(s)? This cannot be undone.`)) {
            return;
        }

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const headers = { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken };

            // 1. Delete Selected Assets
            const assetPromises = selectedItems.assets.map(id =>
                fetch(`/api/v1/assets/${id}`, { method: 'DELETE', headers })
            );

            // 2. Delete Selected Folders
            const folderPromises = selectedItems.folders.map(id =>
                fetch(`/api/v1/folders/${id}`, { method: 'DELETE', headers })
            );

            // Wait for all delete requests to finish
            await Promise.all([...assetPromises, ...folderPromises]);

            // Refresh view
            loadContent();
        } catch (error) {
            console.error("Bulk delete failed:", error);
            alert("An error occurred during deletion.");
        }
    };

    // --- CREATE & UPLOAD LOGIC ---
    const handleCreateFolder = async () => {
        const response = await fetch('/api/v1/folders', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content },
            body: JSON.stringify({ folder: { name: newFolderName, parent_id: currentId === 'root' ? null : currentId } })
        });

        if (response.ok) {
            setOpenFolderDialog(false);
            setNewFolderName('');
            loadContent();
        }
    };

    const handleFileUpload = async (event) => {
        const file = event.target.files[0];
        if (!file) return;

        const formData = new FormData();
        formData.append('file', file);
        formData.append('title', file.name);
        formData.append('folder_id', currentId === 'root' ? '' : currentId);

        try {
            const csrfMetaTag = document.querySelector('[name="csrf-token"]');
            const response = await fetch('/api/v1/assets', {
                method: 'POST',
                headers: { 'Accept': 'application/json', 'X-CSRF-Token': csrfMetaTag.content },
                body: formData
            });

            if (response.ok) loadContent();
        } catch (error) {
            console.error("Upload error:", error);
        } finally {
            event.target.value = null;
        }
    };

    // --- UI HELPERS ---
    const formatFileName = (name) => {
        if (!name) return "Unknown";
        return name.length > 10 ? `${name.substring(0, 10)}...` : name;
    };

    return (
        <Box sx={{ width: '100%', p: 4, bgcolor: '#f8fafc', minHeight: '100vh' }}>
            {/* --- TOP BAR --- */}
            <Box sx={{
                display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 2,
                width: '100%', mb: 4, pb: 2, borderBottom: '1px solid #e2e8f0'
            }}>
                <Box>
                    <Breadcrumbs aria-label="breadcrumb">
                        <Link
                            underline="hover" color={currentId === 'root' ? "text.primary" : "inherit"}
                            onClick={() => setCurrentId('root')}
                            sx={{ cursor: 'pointer', display: 'flex', alignItems: 'center', fontWeight: currentId === 'root' ? 700 : 400 }}
                        >
                            <Home sx={{ mr: 0.5 }} fontSize="small" /> Home
                        </Link>
                        {viewData.breadcrumbs && viewData.breadcrumbs.filter(c => c.id !== 'root').map((crumb, index, arr) => (
                            <Link
                                key={crumb.id} underline="hover"
                                color={index === arr.length - 1 ? "text.primary" : "inherit"}
                                onClick={() => setCurrentId(crumb.id)}
                                sx={{ cursor: 'pointer', fontWeight: index === arr.length - 1 ? 700 : 400 }}
                            >
                                {crumb.name}
                            </Link>
                        ))}
                    </Breadcrumbs>
                </Box>

                <Stack direction="row" spacing={2} alignItems="center">
                    {/* SELECT ALL CHECKBOX */}
                    {(viewData.folders?.length > 0 || viewData.assets?.length > 0) && (
                        <FormControlLabel
                            control={<Checkbox size="small" checked={isAllSelected} onChange={handleSelectAll} />}
                            label={<Typography variant="body2" sx={{ fontWeight: 600 }}>Select All</Typography>}
                            sx={{ mr: 1 }}
                        />
                    )}

                    {/* View Mode Toggle Button */}
                    <Button
                        variant={viewMode === 'bin' ? 'contained' : 'outlined'}
                        color={viewMode === 'bin' ? 'warning' : 'inherit'}
                        onClick={() => {
                            setViewMode(viewMode === 'active' ? 'bin' : 'active');
                            setCurrentId('root'); // Reset to root when swapping views
                        }}
                        sx={{ textTransform: 'none', borderRadius: '8px', bgcolor: viewMode === 'active' ? 'white' : '' }}
                    >
                        {viewMode === 'active' ? 'View Trash Bin' : 'Back to Active Files'}
                    </Button>

                    {/* --- DYNAMIC ACTION BUTTONS --- */}

                    {/* ACTIVE MODE: Move to Bin */}
                    {hasSelection && viewMode === 'active' && (
                        <Button
                            variant="outlined" color="error" startIcon={<DeleteOutlined />} onClick={handleDeleteSelected}
                        >
                            Move to Bin ({selectedItems.folders.length + selectedItems.assets.length})
                        </Button>
                    )}

                    {/* BIN MODE: Restore & Permanent Delete */}
                    {hasSelection && viewMode === 'bin' && (
                        <>
                            <Button variant="contained" color="success" onClick={handleRestoreSelected}>
                                Restore
                            </Button>
                            <Button variant="contained" color="error" startIcon={<DeleteOutlined />} onClick={handlePermanentDelete}>
                                Delete Forever
                            </Button>
                        </>
                    )}

                    {/* STANDARD CREATION BUTTONS (Only show in Active Mode) */}
                    {viewMode === 'active' && (
                        <>
                            <Button
                                variant="outlined" startIcon={<CreateNewFolder />} onClick={() => setOpenFolderDialog(true)}
                                sx={{ textTransform: 'none', borderRadius: '8px', bgcolor: 'white' }}
                            >
                                New Folder
                            </Button>
                            <Button
                                variant="contained" startIcon={<CloudUpload />} component="label"
                                sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' } }}
                            >
                                Upload Asset
                                <input type="file" hidden onChange={handleFileUpload} />
                            </Button>
                        </>
                    )}
                </Stack>
            </Box>

            {/* --- FOLDERS SECTION --- */}
            {viewData.folders && viewData.folders.length > 0 && (
                <Box sx={{ mb: 5 }}>
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.05em', mb: 2 }}>Folders</Typography>
                    <Grid container spacing={2}>
                        {viewData.folders.map(folder => (
                            <Grid item xs={6} sm={4} md={3} lg={2} key={folder.id}>
                                <Paper
                                    elevation={0}
                                    onClick={(e) => {
                                        if (viewMode === 'bin') {
                                            // In Bin mode, clicking the card just checks the item
                                            toggleSelection('folders', folder.id, e);
                                        } else {
                                            // In normal mode, navigate deeper
                                            setCurrentId(folder.id);
                                        }
                                    }}
                                    sx={{
                                        position: 'relative', p: 2, height: 80,
                                        display: 'flex', alignItems: 'center', gap: 1.5,
                                        border: selectedItems.folders.includes(folder.id) ? '2px solid #4f46e5' : '1px solid #e2e8f0',
                                        bgcolor: selectedItems.folders.includes(folder.id) ? '#eef2ff' : '#ffffff',
                                        borderRadius: '12px', cursor: 'pointer',
                                        transition: 'all 0.2s',
                                        '&:hover': { borderColor: '#4f46e5', boxShadow: '0 4px 12px rgba(0,0,0,0.05)' }
                                    }}
                                >
                                    <Checkbox
                                        size="small"
                                        checked={selectedItems.folders.includes(folder.id)}
                                        onClick={(e) => toggleSelection('folders', folder.id, e)}
                                        sx={{ position: 'absolute', top: 4, right: 4, p: 0.5 }}
                                    />
                                    <FolderIcon sx={{  fontSize: 48, minWidth: 60, minHeight: 60, color: '#4299e1' }} />
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
            )}

            {viewData.folders?.length > 0 && viewData.assets?.length > 0 && <Divider sx={{ my: 4, borderColor: '#e2e8f0' }} />}

            {/* --- ASSETS SECTION --- */}
            <Box>
                {viewData.assets && viewData.assets.length > 0 && (
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.05em', mb: 2 }}>Media & Files</Typography>
                )}

                {viewData.assets && viewData.assets.length > 0 && (
                    <ImageList gap={16} sx={{ mb: 8, gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr)) !important', overflow: 'visible' }}>
                        {viewData.assets.map((asset) => {
                            const displayName = asset.name || asset.title || "Unknown File";

                            let metadata = {};
                            if (typeof asset.properties === 'string') {
                                try {
                                    metadata = JSON.parse(asset.properties);
                                } catch (e) {
                                    console.warn("Could not parse properties string for asset:", asset.id);
                                }
                            } else if (asset.properties) {
                                metadata = asset.properties;
                            } else if (asset.metadata) {
                                metadata = asset.metadata; // Fallback
                            }

                            const rawContentType = metadata.content_type || '';
                            const contentType = typeof rawContentType === 'string' ? rawContentType : '';

                            const isImage = contentType.startsWith('image/');
                            const isPdf = contentType === 'application/pdf';
                            const isVideo = contentType.startsWith('video/');
                            const isSelected = selectedItems.assets.includes(asset.id);

                            return (
                                <ImageListItem
                                    key={asset.id}
                                    onClick={(e) => {
                                        if (viewMode === 'bin') {
                                            // In Bin mode, clicking the card checks the box for bulk actions
                                            toggleSelection('assets', asset.id, e);
                                        } else {
                                            // In normal mode, it opens the full-screen Asset Viewer
                                            setSelectedAsset(asset);
                                        }
                                    }}
                                    sx={{
                                        cursor: 'pointer', borderRadius: '12px', overflow: 'hidden',
                                        border: isSelected ? '2px solid #4f46e5' : '1px solid #e2e8f0',
                                        bgcolor: '#ffffff', transition: 'all 0.2s',
                                        '&:hover': { transform: 'translateY(-4px)', boxShadow: '0 12px 24px rgba(0,0,0,0.1)', borderColor: '#4f46e5' }
                                    }}
                                >
                                    {/* TOP LEFT ABSOLUTE CHECKBOX */}
                                    <Box sx={{ position: 'absolute', top: 8, left: 8, zIndex: 10 }}>
                                        <Checkbox
                                            size="small"
                                            checked={isSelected}
                                            onClick={(e) => toggleSelection('assets', asset.id, e)}
                                            sx={{
                                                color: 'rgba(255,255,255,0.8)',
                                                bgcolor: isSelected ? 'rgba(255,255,255,0.9)' : 'rgba(0,0,0,0.2)',
                                                borderRadius: '4px', p: 0.5,
                                                '&:hover': { bgcolor: 'rgba(255,255,255,0.9)' }
                                            }}
                                        />
                                    </Box>

                                    {isImage && asset.url ? (
                                        <img
                                            srcSet={`${asset.url}?w=248&fit=crop&auto=format&dpr=2 2x`}
                                            src={`${asset.url}?w=248&fit=crop&auto=format`}
                                            alt={displayName} loading="lazy" style={{ height: '200px', objectFit: 'cover' }}
                                        />
                                    ) : (
                                        <Box sx={{ height: '200px', bgcolor: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                                            {isPdf && <PictureAsPdf sx={{ fontSize: 64, color: '#ef4444' }} />}
                                            {isVideo && <VideoFile sx={{ fontSize: 64, color: '#3b82f6' }} />}
                                            {!isPdf && !isVideo && <InsertDriveFile sx={{ fontSize: 64, color: '#64748b' }} />}
                                        </Box>

                                    )}

                                    <ImageListItemBar
                                        title={
                                            <Tooltip title={displayName} placement="top-start">
                                                <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>{formatFileName(displayName)}</Typography>
                                            </Tooltip>
                                        }
                                        actionIcon={
                                            <IconButton sx={{ color: 'rgba(255, 255, 255, 0.7)', '&:hover': { color: '#ffffff' } }} onClick={(e) => { e.stopPropagation(); setSelectedAsset(asset); }}>
                                                <InfoOutlined />
                                            </IconButton>
                                        }
                                    />
                                </ImageListItem>
                            );
                        })}
                    </ImageList>
                )}
            </Box>

            {/* --- DIALOGS --- */}
            <Dialog open={openFolderDialog} onClose={() => setOpenFolderDialog(false)}>
                <DialogTitle>Create New Folder</DialogTitle>
                <DialogContent>
                    <TextField autoFocus margin="dense" label="Folder Name" fullWidth variant="standard" value={newFolderName} onChange={(e) => setNewFolderName(e.target.value)} />
                </DialogContent>
                <DialogActions>
                    <Button onClick={() => setOpenFolderDialog(false)}>Cancel</Button>
                    <Button onClick={handleCreateFolder} variant="contained" disabled={!newFolderName.trim()}>Create</Button>
                </DialogActions>
            </Dialog>

            <AssetViewer asset={selectedAsset} open={Boolean(selectedAsset)} onClose={() => setSelectedAsset(null)} onAssetUpdated={(updatedAsset) => { setSelectedAsset(updatedAsset); loadContent(); }} />
        </Box>
    );
}