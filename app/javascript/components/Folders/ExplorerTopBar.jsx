import React, { useState } from 'react';
import {
    Box, Breadcrumbs, Link, Stack, Button, IconButton,
    Tooltip, Checkbox, FormControlLabel, Typography,
    Menu, MenuItem, ListItemIcon, ListItemText, Divider, Dialog
} from '@mui/material';
import {
    Home, ContentCopy, DeleteOutlined, CreateNewFolder,
    CloudUpload, AutoAwesome, AccountTree,
    Psychology, Translate, Security, Difference, Style,
    CloudSync, Publish, DeleteSweep, BuildOutlined, SchemaOutlined, ImageOutlined, VideoFileOutlined
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';
import UploadWorkspace from './UploadWorkspace';
import ApplySchemaDialog from './ApplySchemaDialog';
import { ApplyImageProfileDialog } from '../Tools/AssetConfigurations/ImageProfiles';
import { ApplyVideoProfileDialog } from '../Tools/AssetConfigurations/VideoProfiles';

export default function ExplorerTopBar({
                                           currentId, viewData, viewMode, setViewMode, handleNavigate, handleCopyPath,
                                           isAllSelected, handleSelectAll, hasSelection, handleDeleteSelected,
                                           handleRestoreSelected, handlePermanentDelete, setOpenFolderDialog,
                                           onUploadSuccess, selectedItems, onSchemaApplied
                                       }) {
    const notify = useNotify();

    const [uploadWorkspaceOpen, setUploadWorkspaceOpen] = useState(false);

    // Dropdown Anchors
    const [smartMenuAnchor,    setSmartMenuAnchor]    = useState(null);
    const [workflowMenuAnchor, setWorkflowMenuAnchor] = useState(null);
    const [toolsMenuAnchor,    setToolsMenuAnchor]    = useState(null);
    const [edgeMenuAnchor,     setEdgeMenuAnchor]     = useState(null);

    // Schema dialog
    const [schemaDialogOpen,  setSchemaDialogOpen]  = useState(false);
    const [schemaTargetType,  setSchemaTargetType]  = useState('folder');
    const [schemaTargetIds,   setSchemaTargetIds]   = useState([]);
    const [schemaTargetNames, setSchemaTargetNames] = useState([]);

    // Image Profile dialog
    const [profileDialogOpen, setProfileDialogOpen] = useState(false);
    // Video Profile dialog
    const [videoProfileDialogOpen, setVideoProfileDialogOpen] = useState(false);

    // AI Handlers
    const handleAiMenuClose = () => setSmartMenuAnchor(null);
    const handleAutoEnrich  = () => { handleAiMenuClose(); notify("Assets queued for LangChain semantic enrichment.", "info"); };
    const handleTdmScan     = () => { handleAiMenuClose(); notify("Scanning for visual and cryptographic duplicates...", "warning"); };
    const handleSmartOrganize = () => { handleAiMenuClose(); notify("AI is analyzing vectors to cluster items into sub-folders.", "info"); };

    // Edge Operations Handlers
    const handleEdgeMenuClose = () => setEdgeMenuAnchor(null);

    const handleForceSync = () => {
        handleEdgeMenuClose();
        fetch('/api/v1/edge_operations/sync', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                folders: viewData.selectedItems?.folders || [],
                assets:  viewData.selectedItems?.assets  || []
            })
        })
            .then(res => res.json())
            .then(data => { if (data.success) notify("Metadata force-sync to Edge KV initiated.", "success"); });
    };

    const handleForcePurge = () => {
        handleEdgeMenuClose();
        fetch('/api/v1/edge_operations/purge', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                folders: viewData.selectedItems?.folders || [],
                assets:  viewData.selectedItems?.assets  || []
            })
        })
            .then(res => res.json())
            .then(data => { if (data.success) notify("Edge cache invalidation queued for selected items.", "warning"); });
    };

    // ── Schema application helpers ──────────────────────────────────────────
    const openSchemaForFolders = () => {
        setToolsMenuAnchor(null);
        const ids   = selectedItems?.folders ?? [];
        const names = (viewData.folders ?? []).filter(f => ids.includes(f.id)).map(f => f.name);
        setSchemaTargetType('folder');
        setSchemaTargetIds(ids.length > 0 ? ids : [currentId]);
        setSchemaTargetNames(names.length > 0 ? names : [viewData.breadcrumbs?.slice(-1)[0]?.name ?? 'Current Folder']);
        setSchemaDialogOpen(true);
    };

    const openSchemaForAssets = () => {
        setToolsMenuAnchor(null);
        const ids   = selectedItems?.assets ?? [];
        const names = (viewData.assets ?? []).filter(a => ids.includes(a.id)).map(a => a.title ?? a.name);
        setSchemaTargetType('assets');
        setSchemaTargetIds(ids);
        setSchemaTargetNames(names);
        setSchemaDialogOpen(true);
    };

    const hasFolderSelection = (selectedItems?.folders?.length ?? 0) > 0;
    const hasAssetSelection  = (selectedItems?.assets?.length  ?? 0) > 0;

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
            <Stack direction="row" spacing={1.5} sx={{
  alignItems: "center"
}}>

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

                {hasSelection && viewMode === 'active' && (
                    <>
                        {/* ── Tools Menu (always visible on selection) ── */}
                        <Button
                            variant="outlined"
                            onClick={(e) => setToolsMenuAnchor(e.currentTarget)}
                            startIcon={<BuildOutlined />}
                            sx={{ textTransform: 'none', borderRadius: '8px', color: '#7c3aed',
                                 borderColor: '#ddd6fe', bgcolor: '#faf5ff',
                                 '&:hover': { bgcolor: '#f5f3ff' } }}
                        >
                            Tools
                        </Button>
                        <Menu
                            anchorEl={toolsMenuAnchor}
                            open={Boolean(toolsMenuAnchor)}
                            onClose={() => setToolsMenuAnchor(null)}
                            PaperProps={{ elevation: 3, sx: { mt: 1, minWidth: 260, borderRadius: 2 } }}
                        >
                            <MenuItem disabled sx={{ opacity: 1 }}>
                                <Typography variant="caption" fontWeight={700} sx={{ color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                                    Metadata Schema
                                </Typography>
                            </MenuItem>
                            <MenuItem
                                onClick={openSchemaForFolders}
                                disabled={!hasFolderSelection && currentId === 'root'}
                            >
                                <ListItemIcon><SchemaOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                <ListItemText
                                    primary="Apply Schema to Folder"
                                    secondary={hasFolderSelection
                                        ? `${selectedItems.folders.length} folder${selectedItems.folders.length > 1 ? 's' : ''} selected`
                                        : "Apply to current folder"}
                                />
                            </MenuItem>
                            {hasAssetSelection && (
                                <MenuItem onClick={openSchemaForAssets}>
                                    <ListItemIcon><SchemaOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                    <ListItemText
                                        primary="Apply Schema to Assets"
                                        secondary={`${selectedItems.assets.length} asset${selectedItems.assets.length > 1 ? 's' : ''} selected`}
                                    />
                                </MenuItem>
                            )}
                            <Divider />
                            <MenuItem disabled sx={{ opacity: 1 }}>
                                <Typography variant="caption" fontWeight={700} sx={{ color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                                    Image Processing
                                </Typography>
                            </MenuItem>
                            <MenuItem
                                onClick={() => { setToolsMenuAnchor(null); setProfileDialogOpen(true); }}
                                disabled={currentId === 'root'}
                            >
                                <ListItemIcon><ImageOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                <ListItemText
                                    primary="Apply Image Profile"
                                    secondary="Set processing profile for this folder"
                                />
                            </MenuItem>
                            <MenuItem
                                onClick={() => { setToolsMenuAnchor(null); setVideoProfileDialogOpen(true); }}
                                disabled={currentId === 'root'}
                            >
                                <ListItemIcon><VideoFileOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                <ListItemText
                                    primary="Apply Video Profile"
                                    secondary="Set video encoding profile for this folder"
                                />
                            </MenuItem>
                        </Menu>

                        {/* Edge CDN Ops */}
                        <Button
                            variant="outlined"
                            onClick={(e) => setEdgeMenuAnchor(e.currentTarget)}
                            startIcon={<CloudSync />}
                            sx={{ textTransform: 'none', borderRadius: '8px', color: '#059669', borderColor: '#a7f3d0', bgcolor: '#ecfdf5', '&:hover': { bgcolor: '#d1fae5' } }}
                        >
                            Edge CDN Ops
                        </Button>
                        <Menu
                            anchorEl={edgeMenuAnchor}
                            open={Boolean(edgeMenuAnchor)}
                            onClose={handleEdgeMenuClose}
                            PaperProps={{ elevation: 3, sx: { mt: 1, minWidth: 260, borderRadius: 2 } }}
                        >
                            <MenuItem onClick={handleForceSync}>
                                <ListItemIcon><Publish fontSize="small" sx={{ color: '#059669' }} /></ListItemIcon>
                                <ListItemText primary="Sync Metadata to CDN" secondary="Force push JSON to Edge KV" />
                            </MenuItem>
                            <Divider />
                            <MenuItem onClick={handleForcePurge}>
                                <ListItemIcon><DeleteSweep fontSize="small" sx={{ color: '#ea580c' }} /></ListItemIcon>
                                <ListItemText primary="Purge Edge Cache" secondary="Invalidate delivery nodes globally" />
                            </MenuItem>
                        </Menu>

                        {/* Workflow Menu */}
                        <Button
                            variant="outlined"
                            onClick={(e) => setWorkflowMenuAnchor(e.currentTarget)}
                            startIcon={<Psychology />}
                            sx={{ textTransform: 'none', borderRadius: '8px', color: '#4f46e5', borderColor: '#c7d2fe' }}
                        >
                            Workflow
                        </Button>
                        <Menu
                            anchorEl={workflowMenuAnchor}
                            open={Boolean(workflowMenuAnchor)}
                            onClose={() => setWorkflowMenuAnchor(null)}
                            PaperProps={{ elevation: 3, sx: { mt: 1, minWidth: 260, borderRadius: 2 } }}
                        >
                            <MenuItem onClick={() => { setWorkflowMenuAnchor(null); notify("Localization agent triggered.", "info"); }}>
                                <ListItemIcon><Translate fontSize="small" color="primary" /></ListItemIcon>
                                <ListItemText primary="Global Localization" secondary="Auto-translate copy & metadata" />
                            </MenuItem>
                            <MenuItem onClick={() => { setWorkflowMenuAnchor(null); notify("Brand safety check initialized.", "warning"); }}>
                                <ListItemIcon><Security fontSize="small" sx={{ color: '#10b981' }} /></ListItemIcon>
                                <ListItemText primary="Brand & License Guard" secondary="Validate usage terms & signatures" />
                            </MenuItem>
                        </Menu>

                        {/* Smart Actions */}
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
                            open={Boolean(smartMenuAnchor)}
                            onClose={handleAiMenuClose}
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

                {hasSelection && viewMode === 'bin' && (
                    <>
                        <Button variant="contained" color="success" onClick={handleRestoreSelected}>Restore</Button>
                        <Button variant="contained" color="error" startIcon={<DeleteOutlined />} onClick={handlePermanentDelete}>Delete Forever</Button>
                    </>
                )}

                {!hasSelection && viewMode === 'active' && (
                    <>
                        {/* Tools button even without selection — for current folder */}
                        {currentId !== 'root' && (
                            <>
                                <Button
                                    variant="outlined"
                                    onClick={(e) => setToolsMenuAnchor(e.currentTarget)}
                                    startIcon={<BuildOutlined />}
                                    sx={{ textTransform: 'none', borderRadius: '8px', color: '#7c3aed',
                                         borderColor: '#ddd6fe', bgcolor: '#faf5ff',
                                         '&:hover': { bgcolor: '#f5f3ff' } }}
                                >
                                    Tools
                                </Button>
                                <Menu
                                    anchorEl={toolsMenuAnchor}
                                    open={Boolean(toolsMenuAnchor)}
                                    onClose={() => setToolsMenuAnchor(null)}
                                    PaperProps={{ elevation: 3, sx: { mt: 1, minWidth: 260, borderRadius: 2 } }}
                                >
                                    <MenuItem onClick={openSchemaForFolders}>
                                        <ListItemIcon><SchemaOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                        <ListItemText primary="Apply Metadata Schema" secondary="Set schema for this folder" />
                                    </MenuItem>
                                    <Divider />
                                    <MenuItem onClick={() => { setToolsMenuAnchor(null); setProfileDialogOpen(true); }}>
                                        <ListItemIcon><ImageOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                        <ListItemText primary="Apply Image Profile" secondary="Set processing profile for this folder" />
                                    </MenuItem>
                                    <MenuItem onClick={() => { setToolsMenuAnchor(null); setVideoProfileDialogOpen(true); }}>
                                        <ListItemIcon><VideoFileOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                        <ListItemText primary="Apply Video Profile" secondary="Set video encoding profile for this folder" />
                                    </MenuItem>
                                </Menu>
                            </>
                        )}

                        <Button variant="outlined" startIcon={<CreateNewFolder />} onClick={() => setOpenFolderDialog(true)} sx={{ textTransform: 'none', borderRadius: '8px', bgcolor: 'white' }}>
                            New Folder
                        </Button>
                        <Button
                            variant="contained"
                            startIcon={<CloudUpload />}
                            onClick={() => setUploadWorkspaceOpen(true)}
                            sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' } }}
                        >
                            Upload Asset
                        </Button>
                    </>
                )}
            </Stack>

            <Dialog fullScreen open={uploadWorkspaceOpen} onClose={() => setUploadWorkspaceOpen(false)}>
                <UploadWorkspace
                    folderId={currentId === 'root' ? null : currentId}
                    onClose={() => setUploadWorkspaceOpen(false)}
                    onUploadComplete={() => {
                        setUploadWorkspaceOpen(false);
                        if (onUploadSuccess) onUploadSuccess();
                    }}
                />
            </Dialog>

            {/* ── Apply Schema Dialog ── */}
            <ApplySchemaDialog
                open={schemaDialogOpen}
                onClose={(needsRefresh) => {
                    setSchemaDialogOpen(false);
                    if (needsRefresh && onSchemaApplied) onSchemaApplied();
                }}
                targetType={schemaTargetType}
                targetIds={schemaTargetIds}
                targetNames={schemaTargetNames}
                currentFolderId={currentId}
            />

            {/* ── Apply Image Profile Dialog ── */}
            <ApplyImageProfileDialog
                open={profileDialogOpen}
                onClose={(needsRefresh) => {
                    setProfileDialogOpen(false);
                    if (needsRefresh && onSchemaApplied) onSchemaApplied();
                }}
                folderId={currentId}
                folderName={viewData.breadcrumbs?.slice(-1)[0]?.name ?? 'Current Folder'}
            />

            {/* ── Apply Video Profile Dialog ── */}
            <ApplyVideoProfileDialog
                open={videoProfileDialogOpen}
                onClose={(needsRefresh) => {
                    setVideoProfileDialogOpen(false);
                    if (needsRefresh && onSchemaApplied) onSchemaApplied();
                }}
                folderId={currentId}
                folderName={viewData.breadcrumbs?.slice(-1)[0]?.name ?? 'Current Folder'}
            />
        </Box>
    );
}