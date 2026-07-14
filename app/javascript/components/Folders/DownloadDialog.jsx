import React, { useState, useEffect, useMemo, useRef } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Box, Typography, Button, IconButton, CircularProgress, LinearProgress,
    Alert, List, ListItem, ListItemIcon, ListItemText,
} from '@mui/material';
import {
    FileDownloadOutlined, CloseOutlined, Folder as FolderIcon,
    InsertDriveFile, CheckCircleOutlined, ErrorOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';

const POLL_INTERVAL_MS = 2000;

/**
 * Download overlay for one or more selected folders/assets, launched from
 * the Explorer "Tools" menu. Unlike {@link CopyDialog}/{@link MoveDialog}
 * there is no destination to pick — the request is submitted immediately
 * on open, `POST /api/v1/asset_downloads` enqueues `AssetDownloadWorker`
 * to build the ZIP asynchronously, and this dialog polls
 * `GET /api/v1/asset_downloads/:id` every couple of seconds to drive a
 * progress bar.
 *
 * If the server reports `queued: true` (the user already has another
 * download pending/processing), a notice is shown immediately so the user
 * knows their request is waiting in line rather than stalled.
 *
 * Once the download completes, a "Download ZIP" button appears — the user
 * doesn't have to keep this dialog open to get the file: the same link is
 * emailed to their inbox and surfaced via a bell notification (see
 * AssetDownloadWorker#notify_user), so navigating away and closing the tab
 * is always safe — they can pick up the finished ZIP later from
 * `/tools/asset_downloads` or their inbox.
 */
export default function DownloadDialog({
    open,
    onClose,             // (needsRefresh: boolean) => void
    selectedItems,       // { folders: [id, ...], assets: [id, ...] }
    itemNames,           // { folders: { [id]: name }, assets: { [id]: name } }
}) {
    const { t } = useTranslation();
    const notify = useNotify();

    const [download, setDownload] = useState(null); // latest polled AssetDownload payload
    const [submitting, setSubmitting] = useState(false);
    const [queuedNotice, setQueuedNotice] = useState(false);
    const [error, setError] = useState('');
    const [itemErrors, setItemErrors] = useState([]);
    const pollRef = useRef(null);
    const startedRef = useRef(false);

    const folderIds = selectedItems?.folders ?? [];
    const assetIds  = selectedItems?.assets ?? [];
    const totalCount = folderIds.length + assetIds.length;

    const csrfToken = () => document.querySelector('[name="csrf-token"]')?.content;

    const summaryItems = useMemo(() => {
        const folders = folderIds.map((id) => ({
            type: 'folder', id, name: itemNames?.folders?.[id] ?? `#${id}`,
        }));
        const assets = assetIds.map((id) => ({
            type: 'asset', id, name: itemNames?.assets?.[id] ?? `#${id}`,
        }));
        return [ ...folders, ...assets ];
    }, [ folderIds, assetIds, itemNames ]);

    const stopPolling = () => {
        if (pollRef.current) {
            clearInterval(pollRef.current);
            pollRef.current = null;
        }
    };

    const poll = (id) => {
        stopPolling();
        pollRef.current = setInterval(async () => {
            try {
                const res = await fetch(`/api/v1/asset_downloads/${id}`);
                if (!res.ok) return;
                const data = await res.json();
                setDownload(data);
                if (data.status === 'completed' || data.status === 'failed') {
                    stopPolling();
                    if (data.status === 'failed') {
                        notify(t('downloadDialog.notifications.failed'), 'error');
                    }
                }
            } catch {
                // transient network hiccup — keep polling until the interval is cleared
            }
        }, POLL_INTERVAL_MS);
    };

    const startDownload = async () => {
        setSubmitting(true);
        setError('');
        setItemErrors([]);
        try {
            const res = await fetch('/api/v1/asset_downloads', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
                body: JSON.stringify({ folder_ids: folderIds, asset_ids: assetIds }),
            });
            const data = await res.json();

            if (!res.ok) {
                throw new Error(data.error || t('downloadDialog.notifications.error'));
            }

            if (data.errors?.length) setItemErrors(data.errors);
            if (data.queued) {
                setQueuedNotice(true);
                notify(t('downloadDialog.notifications.queued'), 'info');
            }

            setDownload(data);
            if (data.status !== 'completed') {
                poll(data.id);
            }
        } catch (err) {
            setError(err.message || t('downloadDialog.notifications.error'));
            notify(err.message || t('downloadDialog.notifications.error'), 'error');
        } finally {
            setSubmitting(false);
        }
    };

    useEffect(() => {
        if (!open) {
            stopPolling();
            startedRef.current = false;
            setDownload(null);
            setQueuedNotice(false);
            setError('');
            setItemErrors([]);
            return;
        }
        if (!startedRef.current) {
            startedRef.current = true;
            startDownload();
        }
        return stopPolling;
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [ open ]);

    const isCompleted = download?.status === 'completed';
    const isFailed = download?.status === 'failed';
    const progressPercent = download?.progress_percent ?? 0;

    return (
        <Dialog open={open} onClose={() => onClose(isCompleted)} maxWidth="sm" fullWidth
                slotProps={{ paper: { sx: { borderRadius: 3 } } }}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1.5,
                               borderBottom: '1px solid #f1f5f9', pb: 1.5, bgcolor: '#eff6ff' }}>
                <FileDownloadOutlined sx={{ color: '#2563eb' }} />
                <Box sx={{ flex: 1 }}>
                    <Typography fontWeight={700} sx={{ color: '#1e293b' }}>
                        {t('downloadDialog.title', { count: totalCount })}
                    </Typography>
                </Box>
                <IconButton size="small" onClick={() => onClose(isCompleted)}>
                    <CloseOutlined fontSize="small" />
                </IconButton>
            </DialogTitle>

            <DialogContent sx={{ pt: 2.5 }}>
                <Typography variant="body2" sx={{ color: '#64748b', mb: 1 }}>
                    {t('downloadDialog.selectedItemsLabel')}
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

                {queuedNotice && !isCompleted && !isFailed && (
                    <Alert severity="info" sx={{ mb: 2 }} data-testid="download-queued-notice">
                        {t('downloadDialog.queuedNotice')}
                    </Alert>
                )}

                {download && !isFailed && (
                    <Box sx={{ mb: 2 }} data-testid="download-progress">
                        <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
                            <Typography variant="body2" sx={{ color: '#64748b' }}>
                                {isCompleted
                                    ? t('downloadDialog.progress.done')
                                    : t('downloadDialog.progress.inProgress', {
                                          processed: download.processed_items ?? 0,
                                          total: download.total_items ?? totalCount,
                                      })}
                            </Typography>
                            <Typography variant="body2" fontWeight={600} sx={{ color: '#2563eb' }}>
                                {progressPercent}%
                            </Typography>
                        </Box>
                        <LinearProgress
                            variant="determinate"
                            value={progressPercent}
                            color={isCompleted ? 'success' : 'primary'}
                            sx={{ height: 8, borderRadius: 4 }}
                        />
                    </Box>
                )}

                {isCompleted && (
                    <Alert
                        severity="success"
                        icon={<CheckCircleOutlined fontSize="small" />}
                        sx={{ mb: 2 }}
                        data-testid="download-ready-alert"
                    >
                        {t('downloadDialog.readyNotice')}
                    </Alert>
                )}

                {isFailed && (
                    <Alert severity="error" icon={<ErrorOutlined fontSize="small" />} sx={{ mb: 2 }}>
                        {download.error_message || t('downloadDialog.notifications.failed')}
                    </Alert>
                )}

                {itemErrors.length > 0 && (
                    <Alert severity="warning" sx={{ mb: 2 }}>
                        <Typography variant="body2" fontWeight={600}>{t('downloadDialog.partialFailureTitle')}</Typography>
                        {itemErrors.map((e, idx) => (
                            <Typography key={idx} variant="caption" component="div">
                                {(e.name || `#${e.id}`)}: {e.error}
                            </Typography>
                        ))}
                    </Alert>
                )}

                {error && (
                    <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>
                )}
            </DialogContent>

            <DialogActions sx={{ px: 3, py: 2, borderTop: '1px solid #f1f5f9' }}>
                <Button onClick={() => onClose(isCompleted)} sx={{ textTransform: 'none', color: '#64748b' }}>
                    {isCompleted ? t('common.close') : t('downloadDialog.runInBackground')}
                </Button>
                {isCompleted && download?.download_url && (
                    <Button
                        variant="contained"
                        component="a"
                        href={download.download_url}
                        startIcon={<FileDownloadOutlined />}
                        sx={{ textTransform: 'none', bgcolor: '#2563eb', '&:hover': { bgcolor: '#1d4ed8' } }}
                    >
                        {t('downloadDialog.downloadZip')}
                    </Button>
                )}
                {!isCompleted && !isFailed && submitting === false && (
                    <Button
                        variant="contained"
                        disabled
                        startIcon={<CircularProgress size={16} color="inherit" />}
                        sx={{ textTransform: 'none' }}
                    >
                        {t('downloadDialog.preparing')}
                    </Button>
                )}
            </DialogActions>
        </Dialog>
    );
}
