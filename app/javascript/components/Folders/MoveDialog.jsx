import React, { useState, useEffect, useMemo } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Box, Typography, Button, TextField, IconButton, CircularProgress,
    Autocomplete, Chip, Alert, List, ListItem, ListItemIcon, ListItemText,
} from '@mui/material';
import {
    DriveFileMoveOutlined, CloseOutlined, Folder as FolderIcon,
    InsertDriveFile, Home,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';

const ROOT_OPTION = { id: 'root', name: '/', isRoot: true };

/**
 * Move overlay for one or more selected folders/assets, launched from the
 * Explorer "Tools" menu. Shows a searchable list of every active folder
 * (fed by `GET /api/v1/folders`, which already returns full breadcrumb
 * paths) plus a synthetic root option, and submits the batch to the
 * `POST /api/v1/move_operations` endpoint in one request.
 *
 * Moving is modelled as "delete from source, create in destination", so
 * per-item permission failures are reported back by the API without
 * aborting the rest of the batch — see `errors` handling below.
 */
export default function MoveDialog({
    open,
    onClose,            // (needsRefresh: boolean) => void
    selectedItems,       // { folders: [id, ...], assets: [id, ...] }
    itemNames,           // { folders: { [id]: name }, assets: { [id]: name } }
    currentFolderId,     // id of the folder currently being browsed, or 'root'
}) {
    const { t } = useTranslation();
    const notify = useNotify();

    const [folderOptions, setFolderOptions] = useState([]);
    const [loadingFolders, setLoadingFolders] = useState(false);
    const [destination, setDestination] = useState(null);
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState('');
    const [itemErrors, setItemErrors] = useState([]);

    const folderIds = selectedItems?.folders ?? [];
    const assetIds  = selectedItems?.assets ?? [];
    const totalCount = folderIds.length + assetIds.length;

    useEffect(() => {
        if (!open) return;
        setDestination(null);
        setError('');
        setItemErrors([]);
        setLoadingFolders(true);

        fetch('/api/v1/folders')
            .then((res) => res.json())
            .then((data) => {
                // Exclude the folders being moved themselves — moving a folder
                // into itself is always invalid, and the server rejects moves
                // into a descendant too (surfaced via `itemErrors` if the user
                // still manages to pick one).
                const excluded = new Set(folderIds.map(String));
                const options = (data.folders ?? []).filter((f) => !excluded.has(String(f.id)));
                setFolderOptions([ ROOT_OPTION, ...options ]);
            })
            .catch(() => setFolderOptions([ ROOT_OPTION ]))
            .finally(() => setLoadingFolders(false));
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [ open ]);

    const summaryItems = useMemo(() => {
        const folders = folderIds.map((id) => ({
            type: 'folder', id, name: itemNames?.folders?.[id] ?? `#${id}`,
        }));
        const assets = assetIds.map((id) => ({
            type: 'asset', id, name: itemNames?.assets?.[id] ?? `#${id}`,
        }));
        return [ ...folders, ...assets ];
    }, [ folderIds, assetIds, itemNames ]);

    const csrfToken = () => document.querySelector('[name="csrf-token"]')?.content;

    const handleMove = async () => {
        if (!destination) {
            setError(t('moveDialog.destinationRequired'));
            return;
        }
        setSaving(true);
        setError('');
        setItemErrors([]);
        try {
            const res = await fetch('/api/v1/move_operations', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
                body: JSON.stringify({
                    folder_ids: folderIds,
                    asset_ids: assetIds,
                    destination_folder_id: destination.isRoot ? 'root' : destination.id,
                }),
            });
            const data = await res.json();

            if (!res.ok && !(data.moved_folders || data.moved_assets)) {
                throw new Error(data.error || (data.errors?.[0]?.error) || t('moveDialog.notifications.error'));
            }

            const movedCount = (data.moved_folders ?? 0) + (data.moved_assets ?? 0);
            if (data.errors?.length) {
                setItemErrors(data.errors);
            }

            if (movedCount > 0) {
                notify(
                    t('moveDialog.notifications.moved', { count: movedCount, destination: destination.isRoot ? '/' : destination.name }),
                    data.errors?.length ? 'warning' : 'success'
                );
                onClose(true);
            } else {
                notify(t('moveDialog.notifications.error'), 'error');
            }
        } catch (err) {
            setError(err.message || t('moveDialog.notifications.error'));
            notify(err.message || t('moveDialog.notifications.error'), 'error');
        } finally {
            setSaving(false);
        }
    };

    return (
        <Dialog open={open} onClose={() => onClose(false)} maxWidth="sm" fullWidth
                slotProps={{ paper: { sx: { borderRadius: 3 } } }}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1.5,
                               borderBottom: '1px solid #f1f5f9', pb: 1.5, bgcolor: '#eff6ff' }}>
                <DriveFileMoveOutlined sx={{ color: '#2563eb' }} />
                <Box sx={{ flex: 1 }}>
                    <Typography fontWeight={700} sx={{ color: '#1e293b' }}>
                        {t('moveDialog.title', { count: totalCount })}
                    </Typography>
                </Box>
                <IconButton size="small" onClick={() => onClose(false)}>
                    <CloseOutlined fontSize="small" />
                </IconButton>
            </DialogTitle>

            <DialogContent sx={{ pt: 2.5 }}>
                <Typography variant="body2" sx={{ color: '#64748b', mb: 1 }}>
                    {t('moveDialog.selectedItemsLabel')}
                </Typography>
                <List dense sx={{ maxHeight: 160, overflowY: 'auto', mb: 2, bgcolor: '#f8fafc', borderRadius: 1.5 }}>
                    {summaryItems.map((item) => (
                        <ListItem key={`${item.type}-${item.id}`} sx={{ py: 0.25 }}>
                            <ListItemIcon sx={{ minWidth: 32 }}>
                                {item.type === 'folder' ? <FolderIcon fontSize="small" /> : <InsertDriveFile fontSize="small" />}
                            </ListItemIcon>
                            <ListItemText primary={item.name} slotProps={{ primary: { variant: 'body2', sx: { wordBreak: 'break-all' } } }} />
                        </ListItem>
                    ))}
                </List>

                <Autocomplete
                    options={folderOptions}
                    loading={loadingFolders}
                    value={destination}
                    onChange={(_, v) => { setDestination(v); setError(''); }}
                    getOptionLabel={(option) => (option.isRoot ? t('moveDialog.rootOption') : option.name)}
                    isOptionEqualToValue={(a, b) => String(a.id) === String(b.id)}
                    renderOption={(props, option) => (
                        <Box component="li" {...props} key={option.id} sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            {option.isRoot ? <Home fontSize="small" sx={{ color: '#2563eb' }} /> : <FolderIcon fontSize="small" sx={{ color: '#2563eb' }} />}
                            {option.isRoot ? t('moveDialog.rootOption') : option.name}
                        </Box>
                    )}
                    renderInput={(params) => (
                        <TextField
                            {...params}
                            autoFocus
                            label={t('moveDialog.destinationLabel')}
                            placeholder={t('moveDialog.destinationPlaceholder')}
                            error={Boolean(error)}
                            helperText={error || (loadingFolders ? t('moveDialog.loadingFolders') : '')}
                        />
                    )}
                />

                {destination && (
                    <Chip
                        sx={{ mt: 1.5 }}
                        icon={destination.isRoot ? <Home fontSize="small" /> : <FolderIcon fontSize="small" />}
                        label={t('moveDialog.movingTo', { destination: destination.isRoot ? '/' : destination.name })}
                        color="primary"
                        variant="outlined"
                    />
                )}

                {itemErrors.length > 0 && (
                    <Alert severity="warning" sx={{ mt: 2 }}>
                        <Typography variant="body2" fontWeight={600}>{t('moveDialog.partialFailureTitle')}</Typography>
                        {itemErrors.map((e, idx) => (
                            <Typography key={idx} variant="caption" component="div">
                                {(e.name || `#${e.id}`)}: {e.error}
                            </Typography>
                        ))}
                    </Alert>
                )}
            </DialogContent>

            <DialogActions sx={{ px: 3, py: 2, borderTop: '1px solid #f1f5f9' }}>
                <Button onClick={() => onClose(false)} sx={{ textTransform: 'none', color: '#64748b' }}>
                    {t('common.cancel')}
                </Button>
                <Button
                    variant="contained"
                    onClick={handleMove}
                    disabled={!destination || saving || totalCount === 0}
                    startIcon={saving ? <CircularProgress size={16} color="inherit" /> : null}
                    sx={{ textTransform: 'none', bgcolor: '#2563eb', '&:hover': { bgcolor: '#1d4ed8' } }}
                >
                    {saving ? t('moveDialog.moving') : t('moveDialog.move')}
                </Button>
            </DialogActions>
        </Dialog>
    );
}
