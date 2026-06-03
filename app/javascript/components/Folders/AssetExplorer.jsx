import React, { useState, useEffect } from 'react';
import { Box, Divider, Typography, Dialog, DialogTitle, DialogContent, DialogActions, TextField, Button } from '@mui/material';
import { useNotify } from '../../context/NotificationContext';
import AssetViewer from './AssetViewer';
import AssetFilterBar from './AssetFilterBar';

// Import our new chunked components
import ExplorerTopBar from './ExplorerTopBar';
import FolderGrid from './FolderGrid';
import AssetGrid from './AssetGrid';
import AssetList from './AssetList';

export default function AssetExplorer({ initialTargetAssetId }) {
    const notify = useNotify();
    const [viewData, setViewData] = useState({ folders: [], assets: [], breadcrumbs: [] });
    const [viewLayout, setViewLayout] = useState('grid');
    const [viewMode, setViewMode] = useState('active');

    const [currentId, setCurrentId] = useState(() => {
        const params = new URLSearchParams(window.location.search);
        return params.get('folder') || 'root';
    });

    const [selectedAsset, setSelectedAsset] = useState(null);
    const [openFolderDialog, setOpenFolderDialog] = useState(false);
    const [newFolderName, setNewFolderName] = useState('');
    const [selectedItems, setSelectedItems] = useState({ folders: [], assets: [] });

    // --- BROWSER HISTORY & ROUTING LOGIC ---
    const handleNavigate = (folderId) => {
        setCurrentId(folderId);
        const newUrl = folderId === 'root' ? window.location.pathname : `${window.location.pathname}?folder=${folderId}`;
        window.history.pushState({ folderId }, '', newUrl);
    };

    useEffect(() => {
        const handlePopState = () => setCurrentId(new URLSearchParams(window.location.search).get('folder') || 'root');
        window.addEventListener('popstate', handlePopState);
        return () => window.removeEventListener('popstate', handlePopState);
    }, []);

    // --- DATA LOADING ---
    useEffect(() => {
        if (initialTargetAssetId) {
            const targetAsset = viewData.assets?.find(a => a.id === initialTargetAssetId);
            if (targetAsset) {
                setSelectedAsset(targetAsset);
            } else {
                fetch(`/api/v1/assets/${initialTargetAssetId}`)
                    .then(res => res.json())
                    .then(data => setSelectedAsset(data));
            }
        }
    }, [initialTargetAssetId, viewData.assets]);

    const loadContent = () => {
        const endpoint = viewMode === 'bin' ? '/api/v1/bin' : `/api/v1/folders/${currentId}`;
        fetch(endpoint).then(res => res.json()).then(data => {
            setViewData(data);
            setSelectedItems({ folders: [], assets: [] });
        });
    };

    useEffect(() => { loadContent(); }, [currentId, viewMode]);

    // --- ACTIONS ---
    const handleCopyPath = () => {
        navigator.clipboard.writeText(window.location.href)
            .then(() => notify("Folder location copied to clipboard!", "success"))
            .catch(() => notify("Failed to copy link.", "error"));
    };

    const handleRestoreSelected = async () => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const headers = { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken };
        const assetPromises = selectedItems.assets.map(id => fetch(`/api/v1/assets/${id}/restore`, { method: 'POST', headers }));
        const folderPromises = selectedItems.folders.map(id => fetch(`/api/v1/folders/${id}/restore`, { method: 'POST', headers }));
        await Promise.all([...assetPromises, ...folderPromises]);
        loadContent();
    };

    const handlePermanentDelete = async () => {
        if (!window.confirm("WARNING: This will permanently delete these files from the server. This cannot be undone!")) return;
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const headers = { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken };
        const assetPromises = selectedItems.assets.map(id => fetch(`/api/v1/assets/${id}/permanent`, { method: 'DELETE', headers }));
        const folderPromises = selectedItems.folders.map(id => fetch(`/api/v1/folders/${id}/permanent`, { method: 'DELETE', headers }));
        await Promise.all([...assetPromises, ...folderPromises]);
        loadContent();
    };

    const handleDeleteSelected = async () => {
        const totalCount = selectedItems.folders.length + selectedItems.assets.length;
        if (!window.confirm(`Are you sure you want to delete ${totalCount} selected item(s)? This cannot be undone.`)) return;

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const headers = { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken };
            const assetPromises = selectedItems.assets.map(id => fetch(`/api/v1/assets/${id}`, { method: 'DELETE', headers }));
            const folderPromises = selectedItems.folders.map(id => fetch(`/api/v1/folders/${id}`, { method: 'DELETE', headers }));
            await Promise.all([...assetPromises, ...folderPromises]);
            loadContent();
        } catch (error) {
            console.error("Bulk delete failed:", error);
            notify("An error occurred during deletion.", "error");
        }
    };

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
        event.stopPropagation();
        setSelectedItems(prev => {
            const list = prev[type];
            return list.includes(id)
                ? { ...prev, [type]: list.filter(itemId => itemId !== id) }
                : { ...prev, [type]: [...list, id] };
        });
    };

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

    const isAllSelected = (viewData.folders?.length > 0 || viewData.assets?.length > 0) &&
        selectedItems.folders.length === (viewData.folders?.length || 0) &&
        selectedItems.assets.length === (viewData.assets?.length || 0);
    const hasSelection = selectedItems.folders.length > 0 || selectedItems.assets.length > 0;

    return (
        <Box sx={{ width: '100%', p: 4, bgcolor: '#f8fafc', minHeight: '100vh' }}>

            <ExplorerTopBar
                currentId={currentId} viewData={viewData} viewMode={viewMode} setViewMode={setViewMode}
                handleNavigate={handleNavigate} handleCopyPath={handleCopyPath} isAllSelected={isAllSelected}
                handleSelectAll={handleSelectAll} hasSelection={hasSelection} handleDeleteSelected={handleDeleteSelected}
                handleRestoreSelected={handleRestoreSelected} handlePermanentDelete={handlePermanentDelete}
                setOpenFolderDialog={setOpenFolderDialog} handleFileUpload={handleFileUpload}
            />

            {viewMode === 'active' && (
                <AssetFilterBar
                    resultCount={(viewData.folders?.length || 0) + (viewData.assets?.length || 0)}
                    viewLayout={viewLayout} setViewLayout={setViewLayout}
                />
            )}

            <FolderGrid
                folders={viewData.folders} viewMode={viewMode}
                selectedItems={selectedItems} toggleSelection={toggleSelection} handleNavigate={handleNavigate}
            />

            {viewData.folders?.length > 0 && viewData.assets?.length > 0 && <Divider sx={{ my: 4, borderColor: '#e2e8f0' }} />}

            {viewData.assets && viewData.assets.length > 0 && (
                <Box>
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.05em', mb: 2 }}>Media & Files</Typography>

                    {/* THE GRID/LIST CONDITIONAL RENDER */}
                    {viewLayout === 'grid' ? (
                        <AssetGrid
                            assets={viewData.assets} viewMode={viewMode}
                            selectedItems={selectedItems} toggleSelection={toggleSelection} setSelectedAsset={setSelectedAsset}
                        />
                    ) : (
                        <AssetList
                            assets={viewData.assets} viewMode={viewMode}
                            selectedItems={selectedItems} toggleSelection={toggleSelection} setSelectedAsset={setSelectedAsset}
                        />
                    )}
                </Box>
            )}

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