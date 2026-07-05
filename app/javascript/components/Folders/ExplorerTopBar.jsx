import React, { useState } from 'react';
import {
    Box, Breadcrumbs, Link, Stack, Button, IconButton,
    Tooltip, Checkbox, FormControlLabel, Typography,
    Menu, MenuItem, ListItemIcon, ListItemText, Divider, Dialog
} from '@mui/material';
import {
    Home, ContentCopy, DeleteOutlined, CreateNewFolder,
    CloudUpload, AutoAwesome, AccountTree,
    Psychology, Difference, Style,
    CloudSync, Publish, DeleteSweep, BuildOutlined, SchemaOutlined, ImageOutlined, VideoFileOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';
import UploadWorkspace from './UploadWorkspace';
import ApplySchemaDialog from './ApplySchemaDialog';
import TriggerWorkflowDialog from './TriggerWorkflowDialog';
import { ApplyImageProfileDialog } from '../Tools/AssetConfigurations/ImageProfiles';
import { ApplyVideoProfileDialog } from '../Tools/AssetConfigurations/VideoProfiles';

export default function ExplorerTopBar({
                                           currentId, viewData, viewMode, setViewMode, handleNavigate, handleCopyPath,
                                           isAllSelected, handleSelectAll, hasSelection, handleDeleteSelected,
                                           handleRestoreSelected, handlePermanentDelete, setOpenFolderDialog,
                                           onUploadSuccess, selectedItems, onSchemaApplied
                                       }) {
    const notify = useNotify();
    const { t } = useTranslation();

    const [uploadWorkspaceOpen, setUploadWorkspaceOpen] = useState(false);

    // Dropdown Anchors
    const [smartMenuAnchor,    setSmartMenuAnchor]    = useState(null);
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

    // Trigger Workflow dialog
    const [triggerWorkflowOpen, setTriggerWorkflowOpen] = useState(false);

    // AI Handlers
    const handleAiMenuClose = () => setSmartMenuAnchor(null);
    const handleAutoEnrich  = () => { handleAiMenuClose(); notify(t('explorerTopBar.notifications.autoEnrichQueued'), "info"); };
    const handleTdmScan     = () => { handleAiMenuClose(); notify(t('explorerTopBar.notifications.duplicateScanQueued'), "warning"); };
    const handleSmartOrganize = () => { handleAiMenuClose(); notify(t('explorerTopBar.notifications.smartOrganizeQueued'), "info"); };

    // Edge Operations Handlers
    const handleEdgeMenuClose = () => setEdgeMenuAnchor(null);

    const csrfToken = () => document.querySelector('[name="csrf-token"]')?.content;

    const runEdgeOperation = (path, { successKey, successVariant, errorKey }) => {
        handleEdgeMenuClose();
        const folders = selectedItems?.folders ?? [];
        const assets = selectedItems?.assets ?? [];

        return fetch(`/api/v1/edge_operations/${path}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
            body: JSON.stringify({ folders, assets }),
        })
            .then((res) => res.json().then((data) => ({ ok: res.ok, data })))
            .then(({ ok, data }) => {
                if (ok && data.success) {
                    notify(t(successKey), successVariant);
                } else {
                    notify(data?.error || t(errorKey), 'error');
                }
            })
            .catch(() => notify(t(errorKey), 'error'));
    };

    const handleForceSync = () => runEdgeOperation('sync', {
        successKey: 'explorerTopBar.notifications.forceSyncStarted',
        successVariant: 'success',
        errorKey: 'explorerTopBar.notifications.forceSyncError',
    });

    const handleForcePurge = () => runEdgeOperation('purge', {
        successKey: 'explorerTopBar.notifications.cachePurgeQueued',
        successVariant: 'warning',
        errorKey: 'explorerTopBar.notifications.cachePurgeError',
    });

    // ── Schema application helpers ──────────────────────────────────────────
    const openSchemaForFolders = () => {
        setToolsMenuAnchor(null);
        const ids   = selectedItems?.folders ?? [];
        const names = (viewData.folders ?? []).filter(f => ids.includes(f.id)).map(f => f.name);
        setSchemaTargetType('folder');
        setSchemaTargetIds(ids.length > 0 ? ids : [currentId]);
        setSchemaTargetNames(names.length > 0 ? names : [viewData.breadcrumbs?.slice(-1)[0]?.name ?? t('explorerTopBar.currentFolder')]);
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
    const folderSelectionText = selectedItems.folders.length === 1
        ? t('explorerTopBar.folderSelected', { count: selectedItems.folders.length })
        : t('explorerTopBar.foldersSelected', { count: selectedItems.folders.length });
    const assetSelectionText = selectedItems.assets.length === 1
        ? t('explorerTopBar.assetSelected', { count: selectedItems.assets.length })
        : t('explorerTopBar.assetsSelected', { count: selectedItems.assets.length });

    return (
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 2, width: '100%', pb: 2 }}>

            {/* Left Side: Navigation Context */}
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <Breadcrumbs aria-label={t('explorerTopBar.breadcrumbLabel')}>
                    <Link underline="hover" color={currentId === 'root' ? "text.primary" : "inherit"} onClick={() => handleNavigate('root')} sx={{ cursor: 'pointer', display: 'flex', alignItems: 'center', fontWeight: currentId === 'root' ? 700 : 400 }}>
                        <Home sx={{ mr: 0.5 }} fontSize="small" /> {t('explorerTopBar.home')}
                    </Link>
                    {viewData.breadcrumbs && viewData.breadcrumbs.filter(c => c.id !== 'root').map((crumb, index, arr) => (
                        <Link key={crumb.id} underline="hover" color={index === arr.length - 1 ? "text.primary" : "inherit"} onClick={() => handleNavigate(crumb.id)} sx={{ cursor: 'pointer', fontWeight: index === arr.length - 1 ? 700 : 400 }}>
                            {crumb.name}
                        </Link>
                    ))}
                </Breadcrumbs>
                <Tooltip title={t('explorerTopBar.copyFolderLink')}>
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
                        label={<Typography variant="body2" sx={{ fontWeight: 600 }}>{t('explorerTopBar.selectAll')}</Typography>}
                        sx={{ mr: 1 }}
                    />
                )}

                <Button
                    variant={viewMode === 'bin' ? 'contained' : 'outlined'}
                    color={viewMode === 'bin' ? 'warning' : 'inherit'}
                    onClick={() => { setViewMode(viewMode === 'active' ? 'bin' : 'active'); handleNavigate('root'); }}
                    sx={{ textTransform: 'none', borderRadius: '8px', bgcolor: viewMode === 'active' ? 'white' : '' }}
                >
                    {viewMode === 'active' ? t('explorerTopBar.viewTrashBin') : t('explorerTopBar.backToActiveFiles')}
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
                            {t('explorerTopBar.tools')}
                        </Button>
                        <Menu
                            anchorEl={toolsMenuAnchor}
                            open={Boolean(toolsMenuAnchor)}
                            onClose={() => setToolsMenuAnchor(null)} slotProps={{paper: { elevation: 3, sx: { mt: 1, minWidth: 260, borderRadius: 2 } } }}
                        >
                            <MenuItem disabled sx={{ opacity: 1 }}>
                                <Typography variant="caption" fontWeight={700} sx={{ color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                                    {t('explorerTopBar.metadataSchema')}
                                </Typography>
                            </MenuItem>
                            <MenuItem
                                onClick={openSchemaForFolders}
                                disabled={!hasFolderSelection && currentId === 'root'}
                            >
                                <ListItemIcon><SchemaOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                <ListItemText
                                    primary={t('explorerTopBar.applySchemaToFolder')}
                                    secondary={hasFolderSelection
                                        ? folderSelectionText
                                        : t('explorerTopBar.applyToCurrentFolder')}
                                />
                            </MenuItem>
                            {hasAssetSelection && (
                                <MenuItem onClick={openSchemaForAssets}>
                                    <ListItemIcon><SchemaOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                    <ListItemText
                                        primary={t('explorerTopBar.applySchemaToAssets')}
                                        secondary={assetSelectionText}
                                    />
                                </MenuItem>
                            )}
                            <Divider />
                            <MenuItem disabled sx={{ opacity: 1 }}>
                                <Typography variant="caption" fontWeight={700} sx={{ color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                                    {t('explorerTopBar.imageProcessing')}
                                </Typography>
                            </MenuItem>
                            <MenuItem
                                onClick={() => { setToolsMenuAnchor(null); setProfileDialogOpen(true); }}
                                disabled={currentId === 'root'}
                            >
                                <ListItemIcon><ImageOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                <ListItemText
                                    primary={t('explorerTopBar.applyImageProfile')}
                                    secondary={t('explorerTopBar.setProcessingProfileForThisFolder')}
                                />
                            </MenuItem>
                            <MenuItem
                                onClick={() => { setToolsMenuAnchor(null); setVideoProfileDialogOpen(true); }}
                                disabled={currentId === 'root'}
                            >
                                <ListItemIcon><VideoFileOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                <ListItemText
                                    primary={t('explorerTopBar.applyVideoProfile')}
                                    secondary={t('explorerTopBar.setVideoEncodingProfileForThisFolder')}
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
                            {t('explorerTopBar.edgeCdnOps')}
                        </Button>
                        <Menu
                            anchorEl={edgeMenuAnchor}
                            open={Boolean(edgeMenuAnchor)}
                            onClose={handleEdgeMenuClose} slotProps={{paper: { elevation: 3, sx: { mt: 1, minWidth: 260, borderRadius: 2 } } }}
                        >
                            <MenuItem onClick={handleForceSync}>
                                <ListItemIcon><Publish fontSize="small" sx={{ color: '#059669' }} /></ListItemIcon>
                                <ListItemText primary={t('explorerTopBar.syncMetadataToCdn')} secondary={t('explorerTopBar.forcePushJsonToEdgeKv')} />
                            </MenuItem>
                            <Divider />
                            <MenuItem onClick={handleForcePurge}>
                                <ListItemIcon><DeleteSweep fontSize="small" sx={{ color: '#ea580c' }} /></ListItemIcon>
                                <ListItemText primary={t('explorerTopBar.purgeEdgeCache')} secondary={t('explorerTopBar.invalidateDeliveryNodesGlobally')} />
                            </MenuItem>
                        </Menu>

                        {/* Workflow */}
                        <Button
                            variant="outlined"
                            onClick={() => setTriggerWorkflowOpen(true)}
                            startIcon={<Psychology />}
                            sx={{ textTransform: 'none', borderRadius: '8px', color: '#4f46e5', borderColor: '#c7d2fe' }}
                        >
                            {t('explorerTopBar.workflow')}
                        </Button>

                        <TriggerWorkflowDialog
                            open={triggerWorkflowOpen}
                            selectedItems={selectedItems}
                            onClose={() => setTriggerWorkflowOpen(false)}
                        />

                        {/* Smart Actions */}
                        <Button
                            variant="contained"
                            onClick={(e) => setSmartMenuAnchor(e.currentTarget)}
                            startIcon={<AutoAwesome />}
                            sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' } }}
                        >
                            {t('explorerTopBar.smartActions')}
                        </Button>
                        <Menu
                            anchorEl={smartMenuAnchor}
                            open={Boolean(smartMenuAnchor)}
                            onClose={handleAiMenuClose} slotProps={{paper: { elevation: 3, sx: { mt: 1, minWidth: 220, borderRadius: 2 } } }}
                        >
                            <MenuItem onClick={handleAutoEnrich}>
                                <ListItemIcon><Style fontSize="small" sx={{ color: '#8b5cf6' }} /></ListItemIcon>
                                <ListItemText primary={t('explorerTopBar.autoTagEnrich')} secondary={t('explorerTopBar.extractSemanticMetadata')} />
                            </MenuItem>
                            <MenuItem onClick={handleSmartOrganize}>
                                <ListItemIcon><AccountTree fontSize="small" sx={{ color: '#0ea5e9' }} /></ListItemIcon>
                                <ListItemText primary={t('explorerTopBar.smartOrganize')} secondary={t('explorerTopBar.groupIntoSemanticFolders')} />
                            </MenuItem>
                            <Divider />
                            <MenuItem onClick={handleTdmScan}>
                                <ListItemIcon><Difference fontSize="small" sx={{ color: '#f59e0b' }} /></ListItemIcon>
                                <ListItemText primary={t('explorerTopBar.scanForDuplicates')} secondary={t('explorerTopBar.tdmPayloadDeduplication')} />
                            </MenuItem>
                        </Menu>

                        <Button variant="outlined" color="error" startIcon={<DeleteOutlined />} onClick={handleDeleteSelected}>
                            {t('explorerTopBar.moveToBin')}
                        </Button>
                    </>
                )}

                {hasSelection && viewMode === 'bin' && (
                    <>
                        <Button variant="contained" color="success" onClick={handleRestoreSelected}>{t('bin.item.restore')}</Button>
                        <Button variant="contained" color="error" startIcon={<DeleteOutlined />} onClick={handlePermanentDelete}>{t('explorerTopBar.deleteForever')}</Button>
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
                                    {t('explorerTopBar.tools')}
                                </Button>
                                <Menu
                                    anchorEl={toolsMenuAnchor}
                                    open={Boolean(toolsMenuAnchor)}
                                    onClose={() => setToolsMenuAnchor(null)} slotProps={{paper: { elevation: 3, sx: { mt: 1, minWidth: 260, borderRadius: 2 } } }}
                                >
                                    <MenuItem onClick={openSchemaForFolders}>
                                        <ListItemIcon><SchemaOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                        <ListItemText primary={t('explorerTopBar.applyMetadataSchema')} secondary={t('explorerTopBar.setSchemaForThisFolder')} />
                                    </MenuItem>
                                    <Divider />
                                    <MenuItem onClick={() => { setToolsMenuAnchor(null); setProfileDialogOpen(true); }}>
                                        <ListItemIcon><ImageOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                        <ListItemText primary={t('explorerTopBar.applyImageProfile')} secondary={t('explorerTopBar.setProcessingProfileForThisFolder')} />
                                    </MenuItem>
                                    <MenuItem onClick={() => { setToolsMenuAnchor(null); setVideoProfileDialogOpen(true); }}>
                                        <ListItemIcon><VideoFileOutlined fontSize="small" sx={{ color: '#7c3aed' }} /></ListItemIcon>
                                        <ListItemText primary={t('explorerTopBar.applyVideoProfile')} secondary={t('explorerTopBar.setVideoEncodingProfileForThisFolder')} />
                                    </MenuItem>
                                </Menu>
                            </>
                        )}

                        <Button variant="outlined" startIcon={<CreateNewFolder />} onClick={() => setOpenFolderDialog(true)} sx={{ textTransform: 'none', borderRadius: '8px', bgcolor: 'white' }}>
                            {t('explorerTopBar.newFolder')}
                        </Button>
                        <Button
                            variant="contained"
                            startIcon={<CloudUpload />}
                            onClick={() => setUploadWorkspaceOpen(true)}
                            sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' } }}
                        >
                            {t('header.uploadAsset')}
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
                folderName={viewData.breadcrumbs?.slice(-1)[0]?.name ?? t('explorerTopBar.currentFolder')}
            />

            {/* ── Apply Video Profile Dialog ── */}
            <ApplyVideoProfileDialog
                open={videoProfileDialogOpen}
                onClose={(needsRefresh) => {
                    setVideoProfileDialogOpen(false);
                    if (needsRefresh && onSchemaApplied) onSchemaApplied();
                }}
                folderId={currentId}
                folderName={viewData.breadcrumbs?.slice(-1)[0]?.name ?? t('explorerTopBar.currentFolder')}
            />
        </Box>
    );
}