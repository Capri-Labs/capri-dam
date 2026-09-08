import React, { useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Box, Typography, Button, Paper, Stack, Chip, Table, TableHead, TableRow,
    TableCell, TableBody, CircularProgress, IconButton, Tooltip, Alert,
    ToggleButton, ToggleButtonGroup, Dialog, DialogTitle, DialogContent,
    DialogContentText, DialogActions,
} from '@mui/material';
import {
    AddOutlined, RefreshOutlined, EditOutlined, BlockOutlined,
    FileDownloadOutlined, ShareOutlined,
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';
import usePortals from './usePortals';
import PortalFormDialog from './PortalFormDialog';
import PortalTokenDialog from './PortalTokenDialog';
import PortalDownloadsDialog from './PortalDownloadsDialog';

const STATUS_COLOR = { active: 'success', expired: 'warning', revoked: 'default' };

/**
 * Management screen for distribution portals.
 *
 * The list deliberately shows granted, deliverable and downloaded counts side
 * by side. A portal with twelve picks and three deliverable files is not an
 * error the system can resolve on the sender's behalf — rights outrank intent —
 * but it is something they should be able to see at a glance rather than
 * discover when the recipient writes to say files are missing.
 */
export default function PortalsManager() {
    const { t } = useTranslation();
    const notify = useNotify();
    const { portals, loading, error, reload, create, update, revoke, fetchPortal, fetchDownloads } = usePortals();

    const [statusFilter, setStatusFilter] = useState('all');
    const [collections, setCollections] = useState([]);
    const [formOpen, setFormOpen] = useState(false);
    const [editing, setEditing] = useState(null);
    const [tokenPortal, setTokenPortal] = useState(null);
    const [downloadsPortal, setDownloadsPortal] = useState(null);
    const [revoking, setRevoking] = useState(null);

    useEffect(() => {
        fetch('/api/v1/collections', { credentials: 'same-origin' })
            .then((r) => (r.ok ? r.json() : []))
            .then((data) => setCollections(Array.isArray(data) ? data : (data.collections || [])))
            .catch(() => setCollections([]));
    }, []);

    const visible = portals.filter((p) => statusFilter === 'all' || p.status === statusFilter);

    const openCreate = () => { setEditing(null); setFormOpen(true); };
    const openEdit = (portal) => { setEditing(portal); setFormOpen(true); };

    const handleSubmit = useCallback(async (payload) => {
        if (editing) {
            await update(editing.id, payload);
            notify(t('portalManager.saved'), 'success');
            setFormOpen(false);
        } else {
            const portal = await create(payload);
            setFormOpen(false);
            // The response carries the only readable copy of the token, so it
            // goes straight into the reveal dialog and nowhere else.
            setTokenPortal(portal);
        }
    }, [editing, update, create, notify, t]);

    const handleRevoke = async () => {
        try {
            await revoke(revoking.id);
            notify(t('portalManager.revoked'), 'success');
        } catch (e) {
            notify(e.message, 'error');
        } finally {
            setRevoking(null);
        }
    };

    const formatted = (value) => (value ? new Date(value).toLocaleString() : '—');

    return (
        <Box sx={{ p: 3 }}>
            <Stack direction="row" alignItems="center" spacing={2} sx={{ mb: 1 }}>
                <ShareOutlined color="primary" />
                <Box sx={{ flexGrow: 1 }}>
                    <Typography variant="h5">{t('portalManager.title')}</Typography>
                    <Typography variant="body2" color="text.secondary">
                        {t('portalManager.subtitle')}
                    </Typography>
                </Box>
                <Tooltip title={t('portalManager.refresh')}>
                    <IconButton onClick={reload} aria-label={t('portalManager.refresh')}>
                        <RefreshOutlined />
                    </IconButton>
                </Tooltip>
                <Button variant="contained" startIcon={<AddOutlined />} onClick={openCreate}>
                    {t('portalManager.create')}
                </Button>
            </Stack>

            <ToggleButtonGroup
                size="small"
                exclusive
                value={statusFilter}
                onChange={(_e, next) => next && setStatusFilter(next)}
                sx={{ mb: 2 }}
            >
                {['all', 'active', 'expired', 'revoked'].map((key) => (
                    <ToggleButton key={key} value={key}>{t(`portalManager.filter.${key}`)}</ToggleButton>
                ))}
            </ToggleButtonGroup>

            {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

            <Paper variant="outlined">
                {loading ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
                        <CircularProgress size={28} />
                    </Box>
                ) : visible.length === 0 ? (
                    <Typography variant="body2" color="text.secondary" sx={{ py: 6, textAlign: 'center' }}>
                        {t('portalManager.empty')}
                    </Typography>
                ) : (
                    <Table size="small">
                        <TableHead>
                            <TableRow>
                                <TableCell>{t('portalManager.column.name')}</TableCell>
                                <TableCell>{t('portalManager.column.target')}</TableCell>
                                <TableCell>{t('portalManager.column.status')}</TableCell>
                                <TableCell>{t('portalManager.column.grants')}</TableCell>
                                <TableCell>{t('portalManager.column.downloads')}</TableCell>
                                <TableCell>{t('portalManager.column.expires')}</TableCell>
                                <TableCell align="right">{t('portalManager.column.actions')}</TableCell>
                            </TableRow>
                        </TableHead>
                        <TableBody>
                            {visible.map((portal) => (
                                <TableRow key={portal.id}>
                                    <TableCell>
                                        {portal.name || t('portalManager.untitled')}
                                        {portal.passphrase_required && (
                                            <Chip size="small" label={t('portalManager.passphraseSet')} sx={{ ml: 1 }} variant="outlined" />
                                        )}
                                    </TableCell>
                                    <TableCell>{portal.target_label}</TableCell>
                                    <TableCell>
                                        <Chip
                                            size="small"
                                            label={t(`portalManager.status.${portal.status}`)}
                                            color={STATUS_COLOR[portal.status] || 'default'}
                                        />
                                    </TableCell>
                                    <TableCell>
                                        <Tooltip title={t('portalManager.grantsTooltip', {
                                            granted: portal.granted_count,
                                            deliverable: portal.distributable_count,
                                        })}
                                        >
                                            <span>
                                                {t('portalManager.grantsCount', {
                                                    granted: portal.granted_count,
                                                    deliverable: portal.distributable_count,
                                                })}
                                            </span>
                                        </Tooltip>
                                    </TableCell>
                                    <TableCell>{portal.download_count}</TableCell>
                                    <TableCell>{formatted(portal.expires_at)}</TableCell>
                                    <TableCell align="right">
                                        <Tooltip title={t('portalManager.action.edit')}>
                                            <span>
                                                <IconButton
                                                    size="small"
                                                    onClick={() => openEdit(portal)}
                                                    disabled={portal.status === 'revoked'}
                                                    aria-label={t('portalManager.action.edit')}
                                                >
                                                    <EditOutlined fontSize="small" />
                                                </IconButton>
                                            </span>
                                        </Tooltip>
                                        <Tooltip title={t('portalManager.action.downloads')}>
                                            <IconButton
                                                size="small"
                                                onClick={() => setDownloadsPortal(portal)}
                                                aria-label={t('portalManager.action.downloads')}
                                            >
                                                <FileDownloadOutlined fontSize="small" />
                                            </IconButton>
                                        </Tooltip>
                                        <Tooltip title={t('portalManager.action.revoke')}>
                                            <span>
                                                <IconButton
                                                    size="small"
                                                    onClick={() => setRevoking(portal)}
                                                    disabled={portal.status === 'revoked'}
                                                    aria-label={t('portalManager.action.revoke')}
                                                >
                                                    <BlockOutlined fontSize="small" />
                                                </IconButton>
                                            </span>
                                        </Tooltip>
                                    </TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                )}
            </Paper>

            <PortalFormDialog
                open={formOpen}
                portal={editing}
                collections={collections}
                fetchPortal={fetchPortal}
                onClose={() => setFormOpen(false)}
                onSubmit={handleSubmit}
            />

            <PortalTokenDialog
                open={Boolean(tokenPortal)}
                portal={tokenPortal}
                onClose={() => setTokenPortal(null)}
            />

            <PortalDownloadsDialog
                open={Boolean(downloadsPortal)}
                portal={downloadsPortal}
                fetchDownloads={fetchDownloads}
                onClose={() => setDownloadsPortal(null)}
            />

            <Dialog open={Boolean(revoking)} onClose={() => setRevoking(null)}>
                <DialogTitle>{t('portalManager.revoke.title')}</DialogTitle>
                <DialogContent>
                    <DialogContentText>{t('portalManager.revoke.body')}</DialogContentText>
                </DialogContent>
                <DialogActions>
                    <Button onClick={() => setRevoking(null)}>{t('portalManager.cancel')}</Button>
                    <Button onClick={handleRevoke} color="error" variant="contained">
                        {t('portalManager.revoke.confirm')}
                    </Button>
                </DialogActions>
            </Dialog>
        </Box>
    );
}
