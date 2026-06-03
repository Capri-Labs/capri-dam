import React, { useState } from 'react';
import {
    Box, Breadcrumbs, Link, Stack, Button, IconButton,
    Tooltip, Checkbox, FormControlLabel, Typography,
    Menu, MenuItem, ListItemIcon, ListItemText, Divider
} from '@mui/material';
import {
    Home, ContentCopy, DeleteOutlined, CreateNewFolder,
    CloudUpload, AutoAwesome, AccountTree, CollectionsBookmark,
    Psychology, DynamicFeed, Translate, Security, Difference, Style
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

export default function ExplorerTopBar({
                                           currentId, viewData, viewMode, setViewMode, handleNavigate, handleCopyPath,
                                           isAllSelected, handleSelectAll, hasSelection, handleDeleteSelected,
                                           handleRestoreSelected, handlePermanentDelete, setOpenFolderDialog, handleFileUpload
                                       }) {
    const notify = useNotify();

    // Dropdown Anchors
    const [smartMenuAnchor, setSmartMenuAnchor] = useState(null);
    const [workflowMenuAnchor, setWorkflowMenuAnchor] = useState(null);
    const [collectionMenuAnchor, setCollectionMenuAnchor] = useState(null);

    // Placeholder handlers for the new AI features
    const [aiMenuAnchor, setAiMenuAnchor] = useState(null);
    const openAiMenu = Boolean(aiMenuAnchor);
    const handleAiMenuClick = (event) => setAiMenuAnchor(event.currentTarget);
    const handleAiMenuClose = () => setAiMenuAnchor(null);
    const handleAutoEnrich = () => {
        handleAiMenuClose();
        notify("Assets queued for LangChain semantic enrichment.", "info");
        // API call to POST /api/v1/ai/batch with selected asset IDs
    };

    const handleTdmScan = () => {
        handleAiMenuClose();
        notify("Scanning for visual and cryptographic duplicates...", "warning");
        // API call to POST /api/v1/data_health/scan
    };

    const handleSmartOrganize = () => {
        handleAiMenuClose();
        notify("AI is analyzing vectors to cluster items into sub-folders.", "info");
        // API call to trigger a LangChain agent to group assets
    };

    return (
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 2, width: '100%', pb: 2 }}>

            {/* Left Side: Navigation Context */}
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <Breadcrumbs aria-label="breadcrumb">
                    <Link underline="hover" color={currentId === 'root' ? "text.primary" : "inherit"} onClick={() => handleNavigate('root')} sx={{ cursor: 'pointer', display: 'flex', alignItems: 'center', fontWeight: currentId === 'root' ? 700 : 400 }}>
                        <Home sx={{ mr: 0.5 }} fontSize="small" /> Home
                    </Link>
                    {viewData.breadcrumbs && viewData.breadcrumbs.filter(c => c.id !== 'root').map((crumb, index, arr) => (
                        <Link key={crumb.id} underline="hover" color={index === arr.length - 1 ? "text.primary" : "inherit"} onClick={() => handleNavigate(crumb.id)} sx={{ cursor: 'pointer', fontWeight: index === arr.length - 1 ? 700 : 400 }}>
                            {crumb.name}
                        </Link>
                    ))}
                </Breadcrumbs>
                <Tooltip title="Copy Folder Link">
                    <IconButton size="small" onClick={handleCopyPath} sx={{ ml: 1, color: '#64748b' }}>
                        <ContentCopy fontSize="small" />
                    </IconButton>
                </Tooltip>
            </Box>

            {/* Right Side: Actions */}
            <Stack direction="row" spacing={1.5} alignItems="center">

                {/* Select All Toggle */}
                {(viewData.folders?.length > 0 || viewData.assets?.length > 0) && (
                    <FormControlLabel
                        control={<Checkbox size="small" checked={isAllSelected} onChange={handleSelectAll} />}
                        label={<Typography variant="body2" sx={{ fontWeight: 600 }}>Select All</Typography>}
                        sx={{ mr: 1 }}
                    />
                )}

                <Button
                    variant={viewMode === 'bin' ? 'contained' : 'outlined'}
                    color={viewMode === 'bin' ? 'warning' : 'inherit'}
                    onClick={() => { setViewMode(viewMode === 'active' ? 'bin' : 'active'); handleNavigate('root'); }}
                    sx={{ textTransform: 'none', borderRadius: '8px', bgcolor: viewMode === 'active' ? 'white' : '' }}
                >
                    {viewMode === 'active' ? 'View Trash Bin' : 'Back to Active Files'}
                </Button>

                {/* --- CONTEXTUAL SELECTION ACTIONS --- */}
                {hasSelection && viewMode === 'active' && (
                    <>
                        {/* 1. AI WORKFLOWS DROP DOWN */}
                        <Button
                            variant="outlined"
                            onClick={(e) => setWorkflowMenuAnchor(e.currentTarget)}
                            startIcon={<Psychology />}
                            sx={{ textTransform: 'none', borderRadius: '8px', color: '#4f46e5', borderColor: '#c7d2fe' }}
                        >
                            Trigger Workflow
                        </Button>
                        <Menu
                            anchorEl={workflowMenuAnchor}
                            open={Boolean(workflowMenuAnchor)}
                            onClose={() => setWorkflowMenuAnchor(null)}
                            PaperProps={{ elevation: 3, sx: { mt: 1, minWidth: 260, borderRadius: 2 } }}
                        >
                            <MenuItem onClick={() => { setWorkflowMenuAnchor(null); notify("Localization agent triggered.", "info"); }}>
                                <ListItemIcon><Translate fontSize="small" color="primary" /></ListItemIcon>
                                <ListItemText primary="Global Localization Pipeline" secondary="Auto-translate copy & metadata" />
                            </MenuItem>
                            <MenuItem onClick={() => { setWorkflowMenuAnchor(null); notify("Brand safety check initialized.", "warning"); }}>
                                <ListItemIcon><Security fontSize="small" sx={{ color: '#10b981' }} /></ListItemIcon>
                                <ListItemText primary="Brand & License Guard" secondary="Validate usage terms & watermark signatures" />
                            </MenuItem>
                        </Menu>

                        {/* 2. SMART COLLECTIONS DROP DOWN */}
                        <Button
                            variant="outlined"
                            onClick={(e) => setCollectionMenuAnchor(e.currentTarget)}
                            startIcon={<CollectionsBookmark />}
                            sx={{ textTransform: 'none', borderRadius: '8px', color: '#0ea5e9', borderColor: '#bae6fd' }}
                        >
                            Collections
                        </Button>
                        <Menu
                            anchorEl={collectionMenuAnchor}
                            open={Boolean(collectionMenuAnchor)}
                            onClose={() => setCollectionMenuAnchor(null)}
                            PaperProps={{ elevation: 3, sx: { mt: 1, minWidth: 260, borderRadius: 2 } }}
                        >
                            <MenuItem onClick={() => { setCollectionMenuAnchor(null); notify("Staged assets compiled into new collection.", "success"); }}>
                                <ListItemIcon><CollectionsBookmark fontSize="small" sx={{ color: '#0ea5e9' }} /></ListItemIcon>
                                <ListItemText primary="Add to Collection" secondary="Assign to static workspace bucket" />
                            </MenuItem>
                            <MenuItem onClick={() => { setCollectionMenuAnchor(null); notify("Smart vector sync tracking enabled.", "success"); }}>
                                <ListItemIcon><DynamicFeed fontSize="small" sx={{ color: '#8b5cf6' }} /></ListItemIcon>
                                <ListItemText primary="Create Dynamic Smart Collection" secondary="Auto-compile using vector similarity" />
                            </MenuItem>
                        </Menu>

                        {/* 3. CORE AI ACTIONS BUTTON */}
                        <Button
                            variant="contained"
                            onClick={(e) => setSmartMenuAnchor(e.currentTarget)}
                            startIcon={<AutoAwesome />}
                            sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' } }}
                        >
                            Smart Actions
                        </Button>
                        <Menu
                            anchorEl={smartMenuAnchor}
                            onClick={handleAiMenuClick}
                            open={Boolean(smartMenuAnchor)}
                            onClose={() => setSmartMenuAnchor(null)}
                            PaperProps={{ elevation: 3, sx: { mt: 1, minWidth: 220, borderRadius: 2 } }}
                        >
                            <MenuItem onClick={handleAutoEnrich}>
                                <ListItemIcon><Style fontSize="small" sx={{ color: '#8b5cf6' }} /></ListItemIcon>
                                <ListItemText primary="Auto-Tag & Enrich" secondary="Extract semantic metadata" />
                            </MenuItem>
                            <MenuItem onClick={handleSmartOrganize}>
                                <ListItemIcon><AccountTree fontSize="small" sx={{ color: '#0ea5e9' }} /></ListItemIcon>
                                <ListItemText primary="Smart Organize" secondary="Group into semantic folders" />
                            </MenuItem>
                            <Divider />
                            <MenuItem onClick={handleTdmScan}>
                                <ListItemIcon><Difference fontSize="small" sx={{ color: '#f59e0b' }} /></ListItemIcon>
                                <ListItemText primary="Scan for Duplicates" secondary="TDM payload deduplication" />
                            </MenuItem>
                        </Menu>

                        <Button variant="outlined" color="error" startIcon={<DeleteOutlined />} onClick={handleDeleteSelected}>
                            Move to Bin
                        </Button>
                    </>
                )}

                {/* TRASH BIN ACTIONS (Visible when in Bin mode and items selected) */}
                {hasSelection && viewMode === 'bin' && (
                    <>
                        <Button variant="contained" color="success" onClick={handleRestoreSelected}>Restore</Button>
                        <Button variant="contained" color="error" startIcon={<DeleteOutlined />} onClick={handlePermanentDelete}>Delete Forever</Button>
                    </>
                )}

                {/* --- DEFAULT ROOT FOLDER ACTIONS --- */}
                {!hasSelection && viewMode === 'active' && (
                    <>
                        <Button variant="outlined" startIcon={<CreateNewFolder />} onClick={() => setOpenFolderDialog(true)} sx={{ textTransform: 'none', borderRadius: '8px', bgcolor: 'white' }}>
                            New Folder
                        </Button>
                        <Button variant="contained" startIcon={<CloudUpload />} component="label" sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' } }}>
                            Upload Asset
                            <input type="file" hidden onChange={handleFileUpload} />
                        </Button>
                    </>
                )}
            </Stack>
        </Box>
    );
}