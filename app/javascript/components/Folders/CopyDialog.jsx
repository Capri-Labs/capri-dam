import React, { useState, useEffect, useMemo } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Box, Typography, Button, TextField, IconButton, CircularProgress,
    Autocomplete, Chip, Alert, List, ListItem, ListItemIcon, ListItemText,
} from '@mui/material';
import {
    ContentCopyOutlined, CloseOutlined, Folder as FolderIcon,
    InsertDriveFile, Home,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';

const ROOT_OPTION = { id: 'root', name: '/', isRoot: true };

/**
 * Copy overlay for one or more selected folders/assets, launched from the
 * Explorer "Tools" menu. Shows a searchable list of every active folder
 * (fed by `GET /api/v1/folders`, which already returns full breadcrumb
 * paths) plus a synthetic root option, and submits the batch to the
 * `POST /api/v1/copy_operations` endpoint in one request.
 *
 * Unlike {@link MoveDialog}, copying leaves the originals untouched — the
 * destination is not excluded from the folder picker (copying a folder
 * "into itself" still isn't allowed, and is rejected the same way both
 * client-side exclusion and the server's cycle guard handle Move), and
 * name collisions in the destination are resolved automatically server-side
 * (" (Copy)", " (Copy 2)", …) rather than blocking the request.
 */
export default function CopyDialog({
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
                // Copying a folder into itself is still always invalid — the
                // server rejects it (and any of its own descendants) via the
                // same cycle guard used by Move, surfaced through
                // `itemErrors` if the user picks one anyway.
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

    const handleCopy = async () => {
        if (!destination) {
            setError(t('copyDialog.destinationRequired'));
            return;
        }
        setSaving(true);
        setError('');
        setItemErrors([]);
        try {
            const res = await fetch('/api/v1/copy_operations', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
                body: JSON.stringify({
                    folder_ids: folderIds,
                    asset_ids: assetIds,
                    destination_folder_id: destination.isRoot ? 'root' : destination.id,
                }),
            });
            const data = await res.json();

            if (!res.ok && !(data.copied_folders || data.copied_assets)) {
                throw new Error(data.error || (data.errors?.[0]?.error) || t('copyDialog.notifications.error'));
            }

            const copiedCount = (data.copied_folders ?? 0) + (data.copied_assets ?? 0);
            if (data.errors?.length) {
                setItemErrors(data.errors);
            }

            if (copiedCount > 0) {
                notify(
                    t('copyDialog.notifications.copied', { count: copiedCount, destination: destination.isRoot ? '/' : destination.name }),
                    data.errors?.length ? 'warning' : 'success'
                );
                onClose(true);
            } else {
                notify(t('copyDialog.notifications.error'), 'error');
            }
        } catch (err) {
            setError(err.message || t('copyDialog.notifications.error'));
            notify(err.message || t('copyDialog.notifications.error'), 'error');
        } finally {
            setSaving(false);
        }
    };

    return (
        <Dialog open={open} onClose={() => onClose(false)} maxWidth="sm" fullWidth
                slotProps={{ paper: { sx: { borderRadius: 3 } } }}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1.5,
                               borderBottom: '1px solid #f1f5f9', pb: 1.5, bgcolor: '#eff6ff' }}>
                <ContentCopyOutlined sx={{ color: '#2563eb' }} />
                <Box sx={{ flex: 1 }}>
                    <Typography fontWeight={700} sx={{ color: '#1e293b' }}>
                        {t('copyDialog.title', { count: totalCount })}
                    </Typography>
                </Box>
                <IconButton size="small" onClick={() => onClose(false)}>
                    <CloseOutlined fontSize="small" />
                </IconButton>
            </DialogTitle>

            <DialogContent sx={{ pt: 2.5 }}>
                <Typography variant="body2" sx={{ color: '#64748b', mb: 1 }}>
                    {t('copyDialog.selectedItemsLabel')}
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
                    getOptionLabel={(option) => (option.isRoot ? t('copyDialog.rootOption') : option.name)}
                    isOptionEqualToValue={(a, b) => String(a.id) === String(b.id)}
                    renderOption={(props, option) => (
                        <Box component="li" {...props} key={option.id} sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            {option.isRoot ? <Home fontSize="small" sx={{ color: '#2563eb' }} /> : <FolderIcon fontSize="small" sx={{ color: '#2563eb' }} />}
                            {option.isRoot ? t('copyDialog.rootOption') : option.name}
                        </Box>
                    )}
                    renderInput={(params) => (
                        <TextField
                            {...params}
                            autoFocus
                            label={t('copyDialog.destinationLabel')}
                            placeholder={t('copyDialog.destinationPlaceholder')}
                            error={Boolean(error)}
                            helperText={error || (loadingFolders ? t('copyDialog.loadingFolders') : '')}
                        />
                    )}
                />

                {destination && (
                    <Chip
                        sx={{ mt: 1.5 }}
                        icon={destination.isRoot ? <Home fontSize="small" /> : <FolderIcon fontSize="small" />}
                        label={t('copyDialog.copyingTo', { destination: destination.isRoot ? '/' : destination.name })}
                        color="primary"
                        variant="outlined"
                    />
                )}

                {itemErrors.length > 0 && (
                    <Alert severity="warning" sx={{ mt: 2 }}>
                        <Typography variant="body2" fontWeight={600}>{t('copyDialog.partialFailureTitle')}</Typography>
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
                    onClick={handleCopy}
                    disabled={!destination || saving || totalCount === 0}
                    startIcon={saving ? <CircularProgress size={16} color="inherit" /> : null}
                    sx={{ textTransform: 'none', bgcolor: '#2563eb', '&:hover': { bgcolor: '#1d4ed8' } }}
                >
                    {saving ? t('copyDialog.copying') : t('copyDialog.copy')}
                </Button>
            </DialogActions>
        </Dialog>
    );
}
