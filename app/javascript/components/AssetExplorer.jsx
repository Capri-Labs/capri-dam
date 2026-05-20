import React, { useState, useEffect } from 'react';
import {
    Box, Grid, Typography, Breadcrumbs, Link, Paper, Stack, IconButton,
    Button, Dialog, DialogTitle, DialogContent, DialogActions, TextField
} from '@mui/material';
import {
    Folder as FolderIcon, InsertDriveFile, InfoOutlined,
    Home, CreateNewFolder, CloudUpload
} from '@mui/icons-material';
import MetadataEditor from './MetadataEditor';

export default function AssetExplorer() {
    const [viewData, setViewData] = useState({ folders: [], assets: [], breadcrumbs: [] });
    const [currentId, setCurrentId] = useState('root');
    const [selectedAsset, setSelectedAsset] = useState(null);

    // States for Folder Creation
    const [openFolderDialog, setOpenFolderDialog] = useState(false);
    const [newFolderName, setNewFolderName] = useState('');

    const loadContent = () => {
        fetch(`/api/v1/folders/${currentId}`)
            .then(res => res.json())
            .then(data => setViewData(data));
    };

    useEffect(() => { loadContent(); }, [currentId]);

    const handleCreateFolder = async () => {
        const response = await fetch('/api/v1/folders', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content },
            body: JSON.stringify({ folder: { name: newFolderName, parent_id: currentId === 'root' ? null : currentId } })
        });

        if (response.ok) {
            setOpenFolderDialog(false);
            setNewFolderName('');
            loadContent(); // Refresh view
        }
    };

    return (
        <Box sx={{ width: '100%', p: 4 }}>
            {/* --- TOP BAR: Breadcrumbs & Actions --- */}
            {/* --- TOP BAR: Breadcrumbs & Actions --- */}
            <Box sx={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                width: '100%', // Ensure it spans the full width
                mb: 4,
                pb: 2,
                borderBottom: '1px solid #e2e8f0'
            }}>
                {/* LEFT SIDE */}
                <Box>
                    <Breadcrumbs aria-label="breadcrumb">
                        <Link
                            underline="hover"
                            color={currentId === 'root' ? "text.primary" : "inherit"}
                            onClick={() => setCurrentId('root')}
                            sx={{ cursor: 'pointer', display: 'flex', alignItems: 'center', fontWeight: currentId === 'root' ? 700 : 400 }}
                        >
                            <Home sx={{ mr: 0.5 }} fontSize="small" />
                            Home
                        </Link>

                        {viewData.breadcrumbs && viewData.breadcrumbs
                            .filter(crumb => crumb.id !== 'root')
                            .map((crumb, index, filteredArray) => (
                                <Link
                                    key={crumb.id}
                                    underline="hover"
                                    color={index === filteredArray.length - 1 ? "text.primary" : "inherit"}
                                    onClick={() => setCurrentId(crumb.id)}
                                    sx={{ cursor: 'pointer', fontWeight: index === filteredArray.length - 1 ? 700 : 400 }}
                                >
                                    {crumb.name}
                                </Link>
                            ))}
                    </Breadcrumbs>
                </Box>

                {/* RIGHT SIDE */}
                <Stack direction="row" spacing={2}>
                    <Button
                        variant="outlined"
                        startIcon={<CreateNewFolder />}
                        onClick={() => setOpenFolderDialog(true)}
                        sx={{ textTransform: 'none', borderRadius: '8px' }}
                    >
                        New Folder
                    </Button>
                    <Button
                        variant="contained"
                        startIcon={<CloudUpload />}
                        component="label"
                        sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none' }}
                    >
                        Upload Asset
                        <input
                            type="file"
                            hidden
                            onChange={(e) => console.log("File selected:", e.target.files[0])}
                        />
                    </Button>
                </Stack>
            </Box>

            {/* --- CONTENT GRID --- */}
            <Grid container spacing={3}>
                {viewData.folders.map(folder => (
                    <Grid item xs={12} sm={6} md={3} lg={2} key={folder.id}>
                        <Paper
                            elevation={0}
                            onClick={() => setCurrentId(folder.id)}
                            sx={{ p: 2, textAlign: 'center', border: '1px solid #e0e6ed', cursor: 'pointer', '&:hover': { border: '1px solid #3182ce', bgcolor: '#fff' } }}
                        >
                            <FolderIcon sx={{ fontSize: 48, minWidth: 80, color: '#4299e1' }} />
                            <Typography variant="body2" fontWeight="bold" noWrap sx={{ mt: 1 }}>{folder.name}</Typography>
                        </Paper>
                    </Grid>
                ))}

                {viewData.assets.map(asset => (
                    <Grid item xs={12} sm={6} md={3} lg={2} key={asset.id}>
                        <Paper elevation={0} sx={{ p: 1, border: '1px solid #e0e6ed' }}>
                            <Box sx={{ height: 100, bgcolor: '#f8fafc', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                                <InsertDriveFile sx={{ fontSize: 40, color: '#94a3b8' }} />
                            </Box>
                            <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mt: 1 }}>
                                <Typography variant="caption" noWrap sx={{ maxWidth: '70%' }}>{asset.name}</Typography>
                                <IconButton size="small" onClick={() => setSelectedAsset(asset)}>
                                    <InfoOutlined fontSize="inherit" />
                                </IconButton>
                            </Stack>
                        </Paper>
                    </Grid>
                ))}
            </Grid>

            {/* --- NEW FOLDER DIALOG --- */}
            <Dialog open={openFolderDialog} onClose={() => setOpenFolderDialog(false)}>
                <DialogTitle>Create New Folder</DialogTitle>
                <DialogContent>
                    <TextField
                        autoFocus
                        margin="dense"
                        label="Folder Name"
                        fullWidth
                        variant="standard"
                        value={newFolderName}
                        onChange={(e) => setNewFolderName(e.target.value)}
                    />
                </DialogContent>
                <DialogActions>
                    <Button onClick={() => setOpenFolderDialog(false)}>Cancel</Button>
                    <Button onClick={handleCreateFolder} variant="contained">Create</Button>
                </DialogActions>
            </Dialog>

            <MetadataEditor asset={selectedAsset} onClose={() => setSelectedAsset(null)} />
        </Box>
    );
}