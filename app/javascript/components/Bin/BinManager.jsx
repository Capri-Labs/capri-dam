import React, { useState, useEffect } from 'react';
import {
    Box, CssBaseline, Typography, Button, IconButton,
    Tooltip, Chip, Dialog, DialogTitle, DialogContent,
    DialogContentText, DialogActions, Card, CardContent
} from '@mui/material';
import { DataGrid } from '@mui/x-data-grid';
import {
    Restore, DeleteForever, FolderZipOutlined,
    InsertDriveFileOutlined, ErrorOutlined
} from '@mui/icons-material';

import Sidebar from '../Sidebar';
import { navigateTo } from "../../utils/globalutils";
import { useNotify } from '../../context/NotificationContext';

export default function BinManager() {
    const notify = useNotify();
    const [items, setItems] = useState([]);
    const [loading, setLoading] = useState(true);

    // Dialog State for Permanent Deletion
    const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
    const [itemToDelete, setItemToDelete] = useState(null);

    const fetchBinContents = () => {
        setLoading(true);
        // This hits the global 'assets#bin' route defined in your routes.rb
        fetch('/api/v1/bin.json')
            .then(res => res.json())
            .then(data => {
                // Normalize folders and assets into a single array for the DataGrid
                const trashedFolders = (data.folders || []).map(f => ({ ...f, item_type: 'folder', grid_id: `folder_${f.id}` }));
                const trashedAssets = (data.assets || []).map(a => ({ ...a, item_type: 'asset', grid_id: `asset_${a.id}` }));

                setItems([...trashedFolders, ...trashedAssets]);
                setLoading(false);
            })
            .catch(err => {
                console.error(err);
                notify("Failed to load recycle bin.", "error");
                setLoading(false);
            });
    };

    useEffect(() => {
        fetchBinContents();
    }, []);

    // --- Action Handlers ---

    const handleRestore = (id, type) => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const endpoint = type === 'folder'
            ? `/api/v1/folders/${id}/restore.json`
            : `/api/v1/assets/${id}/restore.json`;

        fetch(endpoint, {
            method: 'POST',
            headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' }
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify(`${type === 'folder' ? 'Folder' : 'Asset'} restored successfully.`, "success");
                    setItems(prev => prev.filter(item => item.grid_id !== `${type}_${id}`));
                } else {
                    notify(data.errors || "Failed to restore.", "error");
                }
            });
    };

    const confirmPermanentDelete = (item) => {
        setItemToDelete(item);
        setDeleteDialogOpen(true);
    };

    const executePermanentDelete = () => {
        if (!itemToDelete) return;

        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const { id, item_type } = itemToDelete;
        const endpoint = item_type === 'folder'
            ? `/api/v1/folders/${id}/permanent.json`
            : `/api/v1/assets/${id}/permanent.json`;

        fetch(endpoint, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': csrfToken, 'Content-Type': 'application/json' }
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify("Permanently deleted.", "warning");
                    setItems(prev => prev.filter(i => i.grid_id !== `${item_type}_${id}`));
                } else {
                    notify(data.errors || "Failed to delete.", "error");
                }
            })
            .finally(() => {
                setDeleteDialogOpen(false);
                setItemToDelete(null);
            });
    };

    // --- DataGrid Columns ---

    const columns = [
        {
            field: 'item_type', headerName: 'Type', width: 130,
            renderCell: (params) => {
                const isFolder = params.value === 'folder';
                return (
                    <Chip
                        icon={isFolder ? <FolderZipOutlined /> : <InsertDriveFileOutlined />}
                        label={isFolder ? 'Folder' : 'Asset'}
                        size="small"
                        color={isFolder ? 'primary' : 'default'}
                        variant="outlined"
                    />
                );
            }
        },
        { field: 'name', headerName: 'Name / Title', flex: 1, minWidth: 200 },
        {
            field: 'deleted_at', headerName: 'Date Deleted', width: 180,
            renderCell: (params) => {
                if (!params.value) return 'Unknown';
                return new Date(params.value).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
            }
        },
        {
            field: 'actions', headerName: 'Actions', width: 180, sortable: false, align: 'right', headerAlign: 'right',
            renderCell: (params) => (
                <Box sx={{ display: 'flex', gap: 1 }}>
                    <Tooltip title="Restore Item">
                        <IconButton
                            size="small"
                            color="success"
                            onClick={() => handleRestore(params.row.id, params.row.item_type)}
                        >
                            <Restore fontSize="small" />
                        </IconButton>
                    </Tooltip>
                    <Tooltip title="Permanently Delete">
                        <IconButton
                            size="small"
                            color="error"
                            onClick={() => confirmPermanentDelete(params.row)}
                        >
                            <DeleteForever fontSize="small" />
                        </IconButton>
                    </Tooltip>
                </Box>
            )
        }
    ];

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />

            <Box component="main" sx={{ flexGrow: 1, p: 3, display: 'flex', flexDirection: 'column' }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
                    <Box>
                        <Typography variant="h4" sx={{ fontWeight: 700, color: '#1e293b' }}>
                            Recycle Bin
                        </Typography>
                        <Typography variant="body2" color="textSecondary">
                            Items here will be permanently deleted after 30 days.
                        </Typography>
                    </Box>
                </Box>

                <Card variant="outlined" sx={{ borderRadius: 2, bgcolor: 'white', flexGrow: 1 }}>
                    <CardContent sx={{ height: 600, p: 0, '&:last-child': { pb: 0 } }}>
                        <DataGrid
                            rows={items}
                            columns={columns}
                            getRowId={(row) => row.grid_id} // Use composite ID
                            loading={loading}
                            disableRowSelectionOnClick
                            sx={{ border: 'none' }}
                            initialState={{
                                pagination: { paginationModel: { pageSize: 10 } },
                            }}
                            pageSizeOptions={[10, 25, 50]}
                            emptyRowsOverlay={
                                <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%', color: '#94a3b8' }}>
                                    <Restore sx={{ fontSize: 48, mb: 1, opacity: 0.5 }} />
                                    <Typography>Your recycle bin is empty.</Typography>
                                </Box>
                            }
                        />
                    </CardContent>
                </Card>

                {/* Permanent Delete Confirmation Dialog */}
                <Dialog open={deleteDialogOpen} onClose={() => setDeleteDialogOpen(false)}>
                    <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1, color: 'error.main' }}>
                        <ErrorOutlined /> Confirm Permanent Deletion
                    </DialogTitle>
                    <DialogContent>
                        <DialogContentText>
                            Are you sure you want to permanently delete <strong>{itemToDelete?.name}</strong>?
                            This action cannot be undone and the file will be removed from storage.
                        </DialogContentText>
                    </DialogContent>
                    <DialogActions sx={{ p: 2, pt: 0 }}>
                        <Button onClick={() => setDeleteDialogOpen(false)} color="inherit">Cancel</Button>
                        <Button onClick={executePermanentDelete} color="error" variant="contained" disableElevation>
                            Permanently Delete
                        </Button>
                    </DialogActions>
                </Dialog>
            </Box>
        </Box>
    );
}