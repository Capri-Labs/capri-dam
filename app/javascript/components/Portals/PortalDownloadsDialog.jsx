import React, { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Dialog, DialogTitle, DialogContent, DialogActions, Button, Box,
    Table, TableHead, TableRow, TableCell, TableBody, CircularProgress,
    Typography, Alert,
} from '@mui/material';

/**
 * The distribution record for one portal: what actually left, and to whom.
 *
 * This is the answer to the question an audit asks, so it shows the guest
 * identity as recorded at download time rather than resolving it live — a
 * partner who later changes their name did not change who took the file.
 */
export default function PortalDownloadsDialog({ open, portal, fetchDownloads, onClose }) {
    const { t } = useTranslation();
    const [rows, setRows] = useState([]);
    const [total, setTotal] = useState(0);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);

    useEffect(() => {
        if (!open || !portal) return;
        setLoading(true);
        setError(null);
        fetchDownloads(portal.id)
            .then((data) => {
                setRows(data.downloads || []);
                setTotal(data.meta?.total ?? (data.downloads || []).length);
            })
            .catch((e) => setError(e.message))
            .finally(() => setLoading(false));
    }, [open, portal, fetchDownloads]);

    const formatted = (value) => (value ? new Date(value).toLocaleString() : '—');

    return (
        <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
            <DialogTitle>
                {t('portalManager.downloads.title', { name: portal?.name || '' })}
            </DialogTitle>
            <DialogContent dividers>
                {loading && (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                        <CircularProgress size={28} />
                    </Box>
                )}

                {!loading && error && <Alert severity="error">{error}</Alert>}

                {!loading && !error && rows.length === 0 && (
                    <Typography variant="body2" color="text.secondary" sx={{ py: 3, textAlign: 'center' }}>
                        {t('portalManager.downloads.empty')}
                    </Typography>
                )}

                {!loading && !error && rows.length > 0 && (
                    <>
                        <Typography variant="caption" color="text.secondary">
                            {t('portalManager.downloads.total', { count: total })}
                        </Typography>
                        <Table size="small">
                            <TableHead>
                                <TableRow>
                                    <TableCell>{t('portalManager.downloads.asset')}</TableCell>
                                    <TableCell>{t('portalManager.downloads.guest')}</TableCell>
                                    <TableCell>{t('portalManager.downloads.ip')}</TableCell>
                                    <TableCell>{t('portalManager.downloads.when')}</TableCell>
                                </TableRow>
                            </TableHead>
                            <TableBody>
                                {rows.map((row) => (
                                    <TableRow key={row.id}>
                                        <TableCell>{row.asset_title || row.asset_id}</TableCell>
                                        <TableCell>
                                            {row.guest || '—'}
                                            {row.guest_email && (
                                                <Typography variant="caption" display="block" color="text.secondary">
                                                    {row.guest_email}
                                                </Typography>
                                            )}
                                        </TableCell>
                                        <TableCell>{row.ip_address || '—'}</TableCell>
                                        <TableCell>{formatted(row.downloaded_at)}</TableCell>
                                    </TableRow>
                                ))}
                            </TableBody>
                        </Table>
                    </>
                )}
            </DialogContent>
            <DialogActions>
                <Button onClick={onClose}>{t('portalManager.close')}</Button>
            </DialogActions>
        </Dialog>
    );
}
