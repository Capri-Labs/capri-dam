import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
    Box,
    Button,
    Chip,
    CssBaseline,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    Grid,
    LinearProgress,
    Pagination,
    Paper,
    Stack,
    Table,
    TableBody,
    TableCell,
    TableContainer,
    TableHead,
    TableRow,
    TextField,
    Typography,
} from '@mui/material';
import {
    BlockOutlined,
    CheckCircleOutlined,
    DeleteOutlined,
    RefreshOutlined,
    RemoveRedEyeOutlined,
    RestoreOutlined,
    WarningAmberOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

import { useNotify } from '../../../context/NotificationContext';

const STATUS_FILTERS = [ 'pending_review', 'resolved', 'discarded', 'all' ];

const getCsrfToken = () => document.querySelector('[name="csrf-token"]')?.content ?? '';

function statusChipStyles(status) {
    switch (status) {
    case 'resolved':
        return { bgcolor: '#dcfce7', color: '#166534' };
    case 'discarded':
        return { bgcolor: '#fee2e2', color: '#991b1b' };
    default:
        return { bgcolor: '#fef3c7', color: '#92400e' };
    }
}

function StatCard({ icon, label, value, color }) {
    return (
        <Paper elevation={0} sx={{
            p: 2.5,
            borderRadius: 3,
            border: '1px solid #e2e8f0',
            display: 'flex',
            alignItems: 'center',
            gap: 1.5,
        }}>
            <Box sx={{ bgcolor: `${color}15`, color, p: 1.2, borderRadius: 2, display: 'flex' }}>
                {icon}
            </Box>
            <Box>
                <Typography variant="h6" fontWeight={700} sx={{ lineHeight: 1 }}>
                    {value ?? 0}
                </Typography>
                <Typography variant="caption" color="text.secondary">
                    {label}
                </Typography>
            </Box>
        </Paper>
    );
}

function StatusChip({ status, t }) {
    return (
        <Chip
            label={t(`quarantine.status.${status}`)}
            size="small"
            sx={{ fontWeight: 700, ...statusChipStyles(status) }}
        />
    );
}

function AssetPreview({ entry, t }) {
    const previewUrl = entry.asset?.preview_url || entry.asset?.url;

    if (previewUrl) {
        return (
            <Box
                component="img"
                src={previewUrl}
                alt={entry.asset?.title || t('quarantine.noPreview')}
                sx={{
                    width: 56,
                    height: 56,
                    borderRadius: 2,
                    objectFit: 'cover',
                    border: '1px solid #e2e8f0',
                }}
            />
        );
    }

    return (
        <Box sx={{
            width: 56,
            height: 56,
            borderRadius: 2,
            border: '1px dashed #cbd5e1',
            bgcolor: '#f8fafc',
            color: '#64748b',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
        }}>
            <BlockOutlined fontSize="small" />
        </Box>
    );
}

export default function QuarantineManager() {
    const { t } = useTranslation();
    const notify = useNotify();

    const [items, setItems] = useState([]);
    const [stats, setStats] = useState(null);
    const [pagination, setPagination] = useState({ total: 0, page: 1, per_page: 25, pages: 1 });
    const [loading, setLoading] = useState(true);
    const [statsLoading, setStatsLoading] = useState(true);
    const [filter, setFilter] = useState('pending_review');
    const [currentPage, setCurrentPage] = useState(1);
    const [selectedEntry, setSelectedEntry] = useState(null);
    const [detailOpen, setDetailOpen] = useState(false);
    const [detailLoading, setDetailLoading] = useState(false);
    const [actionLoading, setActionLoading] = useState(false);
    const [reviewNotes, setReviewNotes] = useState('');
    const [discardDialog, setDiscardDialog] = useState({ open: false, entry: null });

    const fetchStats = useCallback(async () => {
        setStatsLoading(true);

        try {
            const response = await fetch('/api/v1/quarantined_assets/stats');
            if (!response.ok) throw new Error('Failed to load quarantine stats');
            setStats(await response.json());
        } catch (_error) {
            notify(t('quarantine.notifications.loadError'), 'error');
        } finally {
            setStatsLoading(false);
        }
    }, [notify, t]);

    const fetchItems = useCallback(async (status = filter, page = currentPage) => {
        setLoading(true);

        try {
            const params = new URLSearchParams({
                status,
                page: String(page),
                per_page: '25',
            });
            const response = await fetch(`/api/v1/quarantined_assets?${params.toString()}`);
            if (!response.ok) throw new Error('Failed to load quarantined assets');

            const data = await response.json();
            setItems(data.items || []);
            setPagination(data.pagination || { total: 0, page: 1, per_page: 25, pages: 1 });
        } catch (_error) {
            notify(t('quarantine.notifications.loadError'), 'error');
        } finally {
            setLoading(false);
        }
    }, [currentPage, filter, notify, t]);

    useEffect(() => {
        fetchStats();
    }, [fetchStats]);

    useEffect(() => {
        fetchItems(filter, currentPage);
    }, [currentPage, fetchItems, filter]);

    const refresh = useCallback(() => {
        fetchStats();
        fetchItems(filter, currentPage);
    }, [currentPage, fetchItems, fetchStats, filter]);

    const openDetail = useCallback(async (entry) => {
        setDetailLoading(true);
        setDetailOpen(true);
        setSelectedEntry(entry);
        setReviewNotes(entry.review_notes || '');

        try {
            const response = await fetch(`/api/v1/quarantined_assets/${entry.id}`);
            if (!response.ok) throw new Error('Failed to load quarantined asset');

            const data = await response.json();
            setSelectedEntry(data.entry);
            setReviewNotes(data.entry.review_notes || '');
        } catch (_error) {
            notify(t('quarantine.notifications.loadError'), 'error');
            setDetailOpen(false);
            setSelectedEntry(null);
        } finally {
            setDetailLoading(false);
        }
    }, [notify, t]);

    const closeDetail = () => {
        setDetailOpen(false);
        setSelectedEntry(null);
        setReviewNotes('');
    };

    const submitAction = useCallback(async (entry, actionName) => {
        setActionLoading(true);

        try {
            const response = await fetch(`/api/v1/quarantined_assets/${entry.id}/${actionName}`, {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': getCsrfToken(),
                },
                body: JSON.stringify({ review_notes: reviewNotes }),
            });

            const data = await response.json();
            if (!response.ok) throw new Error(data.error || 'Action failed');

            if (detailOpen) {
                setSelectedEntry(data.entry);
            }

            notify(
                t(actionName === 'release' ? 'quarantine.notifications.released' : 'quarantine.notifications.discarded'),
                actionName === 'release' ? 'success' : 'warning'
            );

            await Promise.all([ fetchStats(), fetchItems(filter, currentPage) ]);

            if (filter === 'pending_review') {
                closeDetail();
            }
        } catch (error) {
            notify(error.message || t('quarantine.notifications.actionFailed'), 'error');
        } finally {
            setActionLoading(false);
        }
    }, [currentPage, detailOpen, fetchItems, fetchStats, filter, notify, reviewNotes, t]);

    const filterButtons = useMemo(() => STATUS_FILTERS.map((status) => ({
        id: status,
        label: t(`quarantine.filters.${status}`),
        count: status === 'all' ? stats?.total : stats?.[status],
    })), [stats, t]);

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f8fafc', minHeight: '100vh' }}>
            <CssBaseline />

            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                <Box sx={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'flex-start',
                    mb: 3,
                    gap: 2,
                    flexWrap: 'wrap',
                }}>
                    <Box>
                        <Typography variant="h4" sx={{ fontWeight: 700, color: '#1e293b' }}>
                            {t('quarantine.title')}
                        </Typography>
                        <Typography variant="body2" color="text.secondary">
                            {t('quarantine.subtitle')}
                        </Typography>
                    </Box>

                    <Button
                        variant="outlined"
                        size="small"
                        startIcon={<RefreshOutlined />}
                        onClick={refresh}
                        sx={{ textTransform: 'none', borderRadius: 2 }}
                    >
                        {t('common.refresh')}
                    </Button>
                </Box>

                <Grid container spacing={2} sx={{ mb: 3 }}>
                    <Grid size={{ xs: 12, md: 3 }}>
                        <StatCard
                            label={t('quarantine.stats.pending_review')}
                            value={statsLoading ? '—' : stats?.pending_review}
                            color="#f59e0b"
                            icon={<WarningAmberOutlined />}
                        />
                    </Grid>
                    <Grid size={{ xs: 12, md: 3 }}>
                        <StatCard
                            label={t('quarantine.stats.resolved')}
                            value={statsLoading ? '—' : stats?.resolved}
                            color="#16a34a"
                            icon={<CheckCircleOutlined />}
                        />
                    </Grid>
                    <Grid size={{ xs: 12, md: 3 }}>
                        <StatCard
                            label={t('quarantine.stats.discarded')}
                            value={statsLoading ? '—' : stats?.discarded}
                            color="#dc2626"
                            icon={<DeleteOutlined />}
                        />
                    </Grid>
                    <Grid size={{ xs: 12, md: 3 }}>
                        <StatCard
                            label={t('quarantine.stats.total')}
                            value={statsLoading ? '—' : stats?.total}
                            color="#2563eb"
                            icon={<BlockOutlined />}
                        />
                    </Grid>
                </Grid>

                <Stack direction="row" spacing={1} sx={{ mb: 3, flexWrap: 'wrap' }}>
                    {filterButtons.map((button) => (
                        <Button
                            key={button.id}
                            size="small"
                            variant={filter === button.id ? 'contained' : 'outlined'}
                            onClick={() => {
                                setFilter(button.id);
                                setCurrentPage(1);
                            }}
                            sx={{
                                textTransform: 'none',
                                borderRadius: 2,
                                ...(filter === button.id ? {
                                    bgcolor: '#1e293b',
                                    '&:hover': { bgcolor: '#0f172a' },
                                } : {}),
                            }}
                        >
                            {button.label}
                            <Chip
                                label={button.count ?? 0}
                                size="small"
                                sx={{
                                    ml: 1,
                                    height: 18,
                                    fontSize: '0.7rem',
                                    bgcolor: filter === button.id ? 'rgba(255,255,255,0.2)' : '#f1f5f9',
                                    color: filter === button.id ? '#fff' : '#475569',
                                }}
                            />
                        </Button>
                    ))}
                </Stack>

                <Paper elevation={0} sx={{ borderRadius: 3, border: '1px solid #e2e8f0', overflow: 'hidden' }}>
                    {loading && <LinearProgress />}

                    <TableContainer>
                        <Table>
                            <TableHead>
                                <TableRow>
                                    <TableCell>{t('quarantine.table.asset')}</TableCell>
                                    <TableCell>{t('quarantine.table.reason')}</TableCell>
                                    <TableCell>{t('quarantine.table.flaggedAt')}</TableCell>
                                    <TableCell>{t('quarantine.table.status')}</TableCell>
                                    <TableCell align="right">{t('common.actions')}</TableCell>
                                </TableRow>
                            </TableHead>
                            <TableBody>
                                {!loading && items.length === 0 && (
                                    <TableRow>
                                        <TableCell colSpan={5}>
                                            <Box sx={{ py: 6, textAlign: 'center', color: '#64748b' }}>
                                                <BlockOutlined sx={{ fontSize: 40, mb: 1 }} />
                                                <Typography variant="subtitle1" fontWeight={600}>
                                                    {t('quarantine.empty')}
                                                </Typography>
                                                <Typography variant="body2">
                                                    {t('quarantine.emptySubtitle')}
                                                </Typography>
                                            </Box>
                                        </TableCell>
                                    </TableRow>
                                )}

                                {items.map((entry) => (
                                    <TableRow key={entry.id} hover>
                                        <TableCell>
                                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                                                <AssetPreview entry={entry} t={t} />
                                                <Box>
                                                    <Typography variant="subtitle2" fontWeight={600}>
                                                        {entry.asset?.title}
                                                    </Typography>
                                                    <Typography variant="caption" color="text.secondary">
                                                        {entry.asset?.content_type || t('quarantine.noContentType')}
                                                    </Typography>
                                                </Box>
                                            </Box>
                                        </TableCell>
                                        <TableCell sx={{ maxWidth: 360 }}>
                                            <Typography variant="body2">
                                                {entry.rejection_reason}
                                            </Typography>
                                        </TableCell>
                                        <TableCell>
                                            <Typography variant="body2">
                                                {entry.flagged_at ? new Date(entry.flagged_at).toLocaleString() : '—'}
                                            </Typography>
                                        </TableCell>
                                        <TableCell>
                                            <StatusChip status={entry.status} t={t} />
                                        </TableCell>
                                        <TableCell align="right">
                                            <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 1 }}>
                                                <Button
                                                    size="small"
                                                    variant="outlined"
                                                    startIcon={<RemoveRedEyeOutlined />}
                                                    onClick={() => openDetail(entry)}
                                                    sx={{ textTransform: 'none' }}
                                                >
                                                    {t('quarantine.actions.view')}
                                                </Button>
                                                <Button
                                                    size="small"
                                                    variant="outlined"
                                                    color="success"
                                                    startIcon={<RestoreOutlined />}
                                                    disabled={entry.status !== 'pending_review'}
                                                    onClick={() => submitAction(entry, 'release')}
                                                    sx={{ textTransform: 'none' }}
                                                >
                                                    {t('quarantine.actions.release')}
                                                </Button>
                                                <Button
                                                    size="small"
                                                    variant="outlined"
                                                    color="error"
                                                    startIcon={<DeleteOutlined />}
                                                    disabled={entry.status !== 'pending_review'}
                                                    onClick={() => setDiscardDialog({ open: true, entry })}
                                                    sx={{ textTransform: 'none' }}
                                                >
                                                    {t('quarantine.actions.discard')}
                                                </Button>
                                            </Box>
                                        </TableCell>
                                    </TableRow>
                                ))}
                            </TableBody>
                        </Table>
                    </TableContainer>

                    {pagination.pages > 1 && (
                        <Box sx={{ display: 'flex', justifyContent: 'center', py: 2 }}>
                            <Pagination
                                count={pagination.pages}
                                page={currentPage}
                                onChange={(_event, page) => setCurrentPage(page)}
                                color="primary"
                            />
                        </Box>
                    )}
                </Paper>
            </Box>

            <Dialog open={detailOpen} onClose={closeDetail} fullWidth maxWidth="md">
                <DialogTitle>{t('quarantine.detail.title')}</DialogTitle>
                <DialogContent dividers>
                    {detailLoading || !selectedEntry ? (
                        <LinearProgress />
                    ) : (
                        <Stack spacing={3}>
                            <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
                                <AssetPreview entry={selectedEntry} t={t} />
                                <Box>
                                    <Typography variant="h6" fontWeight={700}>
                                        {selectedEntry.asset?.title}
                                    </Typography>
                                    <Typography variant="body2" color="text.secondary">
                                        {selectedEntry.asset?.content_type || t('quarantine.noContentType')}
                                    </Typography>
                                </Box>
                            </Stack>

                            <Grid container spacing={2}>
                                <Grid size={{ xs: 12, md: 6 }}>
                                    <Typography variant="caption" color="text.secondary">{t('quarantine.detail.reason')}</Typography>
                                    <Typography variant="body2">{selectedEntry.rejection_reason}</Typography>
                                </Grid>
                                <Grid size={{ xs: 12, md: 6 }}>
                                    <Typography variant="caption" color="text.secondary">{t('quarantine.detail.connector')}</Typography>
                                    <Typography variant="body2">{selectedEntry.system_connector?.name || '—'}</Typography>
                                </Grid>
                                <Grid size={{ xs: 12, md: 6 }}>
                                    <Typography variant="caption" color="text.secondary">{t('quarantine.detail.uploadedBy')}</Typography>
                                    <Typography variant="body2">{selectedEntry.asset?.uploaded_by || '—'}</Typography>
                                </Grid>
                                <Grid size={{ xs: 12, md: 6 }}>
                                    <Typography variant="caption" color="text.secondary">{t('quarantine.detail.uploadedAt')}</Typography>
                                    <Typography variant="body2">
                                        {selectedEntry.asset?.uploaded_at ? new Date(selectedEntry.asset.uploaded_at).toLocaleString() : '—'}
                                    </Typography>
                                </Grid>
                                <Grid size={{ xs: 12, md: 6 }}>
                                    <Typography variant="caption" color="text.secondary">{t('quarantine.detail.flaggedAt')}</Typography>
                                    <Typography variant="body2">
                                        {selectedEntry.flagged_at ? new Date(selectedEntry.flagged_at).toLocaleString() : '—'}
                                    </Typography>
                                </Grid>
                                <Grid size={{ xs: 12, md: 6 }}>
                                    <Typography variant="caption" color="text.secondary">{t('quarantine.detail.status')}</Typography>
                                    <Box sx={{ mt: 0.5 }}>
                                        <StatusChip status={selectedEntry.status} t={t} />
                                    </Box>
                                </Grid>
                            </Grid>

                            <TextField
                                label={t('quarantine.detail.reviewNotes')}
                                value={reviewNotes}
                                onChange={(event) => setReviewNotes(event.target.value)}
                                multiline
                                minRows={3}
                                fullWidth
                                disabled={selectedEntry.status !== 'pending_review'}
                            />

                            <Box>
                                <Typography variant="subtitle2" sx={{ mb: 1 }}>
                                    {t('quarantine.detail.originalPayload')}
                                </Typography>
                                <Box
                                    component="pre"
                                    sx={{
                                        m: 0,
                                        p: 2,
                                        borderRadius: 2,
                                        bgcolor: '#0f172a',
                                        color: '#e2e8f0',
                                        fontSize: '0.75rem',
                                        overflowX: 'auto',
                                    }}
                                >
                                    {JSON.stringify(selectedEntry.original_payload || {}, null, 2)}
                                </Box>
                            </Box>
                        </Stack>
                    )}
                </DialogContent>
                <DialogActions>
                    <Button onClick={closeDetail}>{t('common.close')}</Button>
                    <Button
                        color="error"
                        onClick={() => setDiscardDialog({ open: true, entry: selectedEntry })}
                        disabled={!selectedEntry || selectedEntry.status !== 'pending_review' || actionLoading}
                    >
                        {t('quarantine.actions.discard')}
                    </Button>
                    <Button
                        variant="contained"
                        color="success"
                        onClick={() => submitAction(selectedEntry, 'release')}
                        disabled={!selectedEntry || selectedEntry.status !== 'pending_review' || actionLoading}
                    >
                        {t('quarantine.actions.release')}
                    </Button>
                </DialogActions>
            </Dialog>

            <Dialog
                open={discardDialog.open}
                onClose={() => setDiscardDialog({ open: false, entry: null })}
                fullWidth
                maxWidth="xs"
            >
                <DialogTitle>{t('quarantine.confirmDiscard.title')}</DialogTitle>
                <DialogContent>
                    <Typography variant="body2">
                        {t('quarantine.confirmDiscard.body')}
                    </Typography>
                </DialogContent>
                <DialogActions>
                    <Button onClick={() => setDiscardDialog({ open: false, entry: null })}>
                        {t('common.cancel')}
                    </Button>
                    <Button
                        color="error"
                        variant="contained"
                        onClick={async () => {
                            const entry = discardDialog.entry;
                            setDiscardDialog({ open: false, entry: null });
                            if (entry) await submitAction(entry, 'discard');
                        }}
                    >
                        {t('quarantine.confirmDiscard.confirm')}
                    </Button>
                </DialogActions>
            </Dialog>
        </Box>
    );
}
