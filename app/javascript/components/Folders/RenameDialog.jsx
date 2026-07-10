import React, { useState, useEffect } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Box, Typography, Button, TextField, IconButton, CircularProgress
} from '@mui/material';
import { DriveFileRenameOutline, CloseOutlined, Folder as FolderIcon, InsertDriveFile } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';

/**
 * Rename overlay for a single folder or a single asset, launched from the
 * Explorer "Tools" menu. Intentionally single-target only — bulk renaming
 * is out of scope (and would be ambiguous for naming conventions), so
 * callers should only allow this action when exactly one item is selected.
 */
export default function RenameDialog({
    open,
    onClose,           // (needsRefresh: boolean) => void
    targetType,        // 'folder' | 'asset'
    targetId,
    initialName,
}) {
    const { t } = useTranslation();
    const notify = useNotify();
    const [name, setName]   = useState(initialName || '');
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState('');

    useEffect(() => {
        if (open) {
            setName(initialName || '');
            setError('');
        }
    }, [open, initialName]);

    const isFolder = targetType === 'folder';
    const trimmedName = name.trim();
    const unchanged = trimmedName === (initialName || '').trim();

    const handleSave = async () => {
        if (!trimmedName) {
            setError(t('renameDialog.nameRequired'));
            return;
        }
        setSaving(true);
        setError('');
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const url = isFolder
                ? `/api/v1/folders/${encodeURIComponent(targetId)}`
                : `/api/v1/assets/${encodeURIComponent(targetId)}`;
            const body = isFolder
                ? { folder: { name: trimmedName } }
                : { asset: { title: trimmedName } };

            const res = await fetch(url, {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(body),
            });
            const data = await res.json();

            if (!res.ok) {
                throw new Error((data.errors || [ data.error ]).filter(Boolean).join(', ') || t('renameDialog.notifications.error'));
            }

            notify(
                isFolder
                    ? t('renameDialog.notifications.folderRenamed', { name: trimmedName })
                    : t('renameDialog.notifications.assetRenamed', { name: trimmedName }),
                'success'
            );
            onClose(true);
        } catch (err) {
            setError(err.message || t('renameDialog.notifications.error'));
            notify(err.message || t('renameDialog.notifications.error'), 'error');
        } finally {
            setSaving(false);
        }
    };

    return (
        <Dialog open={open} onClose={() => onClose(false)} maxWidth="xs" fullWidth
                slotProps={{ paper: { sx: { borderRadius: 3 } } }}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1.5,
                               borderBottom: '1px solid #f1f5f9', pb: 1.5, bgcolor: '#faf5ff' }}>
                <DriveFileRenameOutline sx={{ color: '#7c3aed' }} />
                <Box sx={{ flex: 1 }}>
                    <Typography fontWeight={700} sx={{ color: '#1e293b' }}>
                        {isFolder ? t('renameDialog.titleFolder') : t('renameDialog.titleAsset')}
                    </Typography>
                </Box>
                <IconButton size="small" onClick={() => onClose(false)}>
                    <CloseOutlined fontSize="small" />
                </IconButton>
            </DialogTitle>

            <DialogContent sx={{ pt: 2.5 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2, color: '#64748b' }}>
                    {isFolder ? <FolderIcon fontSize="small" /> : <InsertDriveFile fontSize="small" />}
                    <Typography variant="body2" sx={{ wordBreak: 'break-all' }}>
                        {initialName}
                    </Typography>
                </Box>

                <TextField
                    autoFocus
                    fullWidth
                    label={t('renameDialog.newNameLabel')}
                    value={name}
                    onChange={(e) => { setName(e.target.value); setError(''); }}
                    error={Boolean(error)}
                    helperText={error}
                    onKeyDown={(e) => {
                        if (e.key === 'Enter' && !saving && trimmedName && !unchanged) handleSave();
                    }}
                />
            </DialogContent>

            <DialogActions sx={{ px: 3, py: 2, borderTop: '1px solid #f1f5f9' }}>
                <Button onClick={() => onClose(false)} sx={{ textTransform: 'none', color: '#64748b' }}>
                    {t('common.cancel')}
                </Button>
                <Button
                    variant="contained"
                    onClick={handleSave}
                    disabled={!trimmedName || unchanged || saving}
                    startIcon={saving ? <CircularProgress size={16} color="inherit" /> : null}
                    sx={{ textTransform: 'none', bgcolor: '#7c3aed', '&:hover': { bgcolor: '#6d28d9' } }}
                >
                    {saving ? t('renameDialog.saving') : t('renameDialog.save')}
                </Button>
            </DialogActions>
        </Dialog>
    );
}
