import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, CssBaseline, Typography, Button, IconButton, Tooltip, Chip,
    LinearProgress, Stack, Pagination
} from '@mui/material';
import {
    DeleteForeverOutlined, RestoreFromTrashOutlined, WarningAmberOutlined,
    RefreshOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

import { useNotify } from '../../context/NotificationContext';
import BinFilterBar from './BinFilterBar';
import BinStatsBar from './BinStatsBar';
import BinGrid from './BinGrid';
import BinList from './BinList';
import BinEmptyState from './BinEmptyState';
import BinConfirmDialog from './BinConfirmDialog';
import BinActivePurgeBanner from './BinActivePurgeBanner';

const getCsrfToken = () => document.querySelector('[name="csrf-token"]')?.content ?? '';

export default function BinManager() {
    const { t } = useTranslation();
    const notify = useNotify();

    // ── Data ──────────────────────────────────────────────────────────────────
    const [items, setItems]               = useState([]);
    const [stats, setStats]               = useState(null);
    const [loading, setLoading]           = useState(true);
    const [statsLoading, setStatsLoading] = useState(true);
    const [pagination, setPagination]     = useState({ total: 0, page: 1, per_page: 25, pages: 1 });

    // ── Filters & view ────────────────────────────────────────────────────────
    const [query, setQuery]               = useState('');
    const [debouncedQuery, setDebouncedQuery] = useState('');
    const [typeFilter, setTypeFilter]     = useState('all');
    const [sort, setSort]                 = useState({ field: 'deleted_at', direction: 'desc' });
    const [viewLayout, setViewLayout]     = useState('list');
    const [gridSize, setGridSize]         = useState('medium');
    const [currentPage, setCurrentPage]   = useState(1);
    const [perPage, setPerPage]           = useState(25);

    // ── Selection ─────────────────────────────────────────────────────────────
    const [selected, setSelected] = useState(new Set());

    // ── Confirm dialog ────────────────────────────────────────────────────────
    const [confirmDialog, setConfirmDialog] = useState({ open: false, variant: null, count: 0, onConfirm: null });

    const searchTimer = useRef(null);
    // Guards the filter-reset effect below so it doesn't fire (and reset the
    // page) on the very first render — only on subsequent filter changes.
    const isFirstRender = useRef(true);

    // ─────────────────────────────────────────────────────────────────────────
    // DATA FETCHING
    // ─────────────────────────────────────────────────────────────────────────

    const fetchStats = useCallback(() => {
        setStatsLoading(true);
        fetch('/api/v1/bin/stats')
            .then(r => r.json())
            .then(data => setStats(data))
            .catch(() => notify(t('bin.notifications.loadError'), 'error'))
            .finally(() => setStatsLoading(false));
    }, []);

    const fetchItems = useCallback((page = 1) => {
        setLoading(true);
        const params = new URLSearchParams({
            q:         debouncedQuery,
            type:      typeFilter,
            sort:      sort.field,
            direction: sort.direction,
            page,
            per_page:  perPage,
        });
        fetch(`/api/v1/bin?${params}`)
            .then(r => r.json())
            .then(data => {
                setItems(data.items || []);
                setPagination(data.pagination || { total: 0, page: 1, per_page: perPage, pages: 1 });
                setSelected(new Set());
            })
            .catch(() => notify(t('bin.notifications.loadError'), 'error'))
            .finally(() => setLoading(false));
    }, [debouncedQuery, typeFilter, sort, perPage]);

    // A single, memoized "refresh" so it doesn't force child components
    // (e.g. BinActivePurgeBanner) to re-run their mount effects every time
    // this component re-renders.
    const refresh = useCallback(() => {
        fetchStats();
        fetchItems(currentPage);
    }, [fetchStats, fetchItems, currentPage]);

    const handlePerPageChange = (value) => {
        setPerPage(value);
        setCurrentPage(1);
    };

    useEffect(() => { fetchStats(); }, [fetchStats]);

    // Debounce the raw search input into `debouncedQuery` (used for fetching).
    useEffect(() => {
        clearTimeout(searchTimer.current);
        searchTimer.current = setTimeout(() => setDebouncedQuery(query), query ? 300 : 0);
        return () => clearTimeout(searchTimer.current);
    }, [query]);

    // Reset back to page 1 whenever a filter changes — but not on the initial
    // mount (that would otherwise trigger a redundant extra fetch below).
    useEffect(() => {
        if (isFirstRender.current) return;
        setCurrentPage(1);
    }, [debouncedQuery, typeFilter, sort, perPage]);

    // Single source of truth for fetching the item list: fires once on
    // mount, and again whenever the page or any filter changes.
    useEffect(() => {
        fetchItems(currentPage);
        isFirstRender.current = false;
    }, [currentPage, debouncedQuery, typeFilter, sort, perPage]); // eslint-disable-line react-hooks/exhaustive-deps

    // ─────────────────────────────────────────────────────────────────────────
    // SELECTION
    // ─────────────────────────────────────────────────────────────────────────

    const toggleItem    = (gridId) => setSelected(prev => { const n = new Set(prev); n.has(gridId) ? n.delete(gridId) : n.add(gridId); return n; });
    const selectAll     = () => setSelected(new Set(items.map(i => i.grid_id)));
    const deselectAll   = () => setSelected(new Set());
    const isSelected    = (gridId) => selected.has(gridId);
    const hasSelection  = selected.size > 0;
    const allSelected   = items.length > 0 && selected.size === items.length;
    const selectedItems = () => items.filter(i => selected.has(i.grid_id)).map(i => ({ id: i.id, type: i.item_type }));

    // ─────────────────────────────────────────────────────────────────────────
    // ACTIONS
    // ─────────────────────────────────────────────────────────────────────────

    const openConfirm  = (variant, count, onConfirm) => setConfirmDialog({ open: true, variant, count, onConfirm });
    const closeConfirm = () => setConfirmDialog(prev => ({ ...prev, open: false }));

    const handleRestore         = (item) => openConfirm('restore',  1,             () => doRestore([{ id: item.id, type: item.item_type }]));
    const handlePermanentDelete = (item) => openConfirm('delete',   1,             () => doDelete([{ id: item.id, type: item.item_type }]));
    const handleBulkRestore     = ()     => openConfirm('restore',  selected.size, () => doRestore(selectedItems()));
    const handleBulkDelete      = ()     => openConfirm('delete',   selected.size, () => doDelete(selectedItems()));
    const handleEmptyBin        = ()     => openConfirm('emptyBin', stats?.total_items ?? 0, doEmptyBin);

    const doRestore = async (items) => {
        closeConfirm();
        const res  = await fetch('/api/v1/bin/bulk_restore', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCsrfToken() }, body: JSON.stringify({ items }) });
        const data = await res.json();
        // Only show a success toast when something actually got restored —
        // otherwise (e.g. the item was already purged) surface the error.
        if (data.restored > 0) {
            notify(t('bin.notifications.restored', { count: data.restored }), 'success');
        }
        if (data.errors?.length) notify(data.errors.join(', '), 'error');
        refresh();
    };

    const doDelete = async (items) => {
        closeConfirm();
        const res  = await fetch('/api/v1/bin/bulk_destroy', { method: 'DELETE', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCsrfToken() }, body: JSON.stringify({ items }) });
        const data = await res.json();
        if (data.deleted > 0) {
            notify(t('bin.notifications.deleted', { count: data.deleted }), 'warning');
        }
        if (data.errors?.length) notify(data.errors.join(', '), 'error');
        refresh();
    };

    const doEmptyBin = async () => {
        closeConfirm();
        await fetch('/api/v1/bin/empty', { method: 'DELETE', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCsrfToken() } });
        notify(t('bin.notifications.emptied'), 'warning');
        refresh();
    };

    // ─────────────────────────────────────────────────────────────────────────
    // RENDER
    // ─────────────────────────────────────────────────────────────────────────

    const isEmpty = !loading && items.length === 0 && !query && typeFilter === 'all';

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f8fafc', minHeight: '100vh' }}>
            <CssBaseline />

            <Box component="main" sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>

                {/* ── Page Header ────────────────────────────────────────── */}
                <Box sx={{
                    display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start',
                    px: 4, pt: 4, pb: 2, borderBottom: '1px solid #e2e8f0', bgcolor: '#fff',
                    flexWrap: 'wrap', gap: 2
                }}>
                    <Box>
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 0.5 }}>
                            <Box sx={{ p: 1, bgcolor: '#fef2f2', borderRadius: 2, display: 'flex' }}>
                                <DeleteForeverOutlined sx={{ color: '#ef4444', fontSize: 24 }} />
                            </Box>
                            <Typography variant="h5" sx={{ fontWeight: 800, color: '#1e293b' }}>
                                {t('bin.title')}
                            </Typography>
                            {stats && stats.total_items > 0 && (
                                <Chip label={stats.total_items} size="small"
                                    sx={{ bgcolor: '#fef2f2', color: '#ef4444', fontWeight: 700 }} />
                            )}
                        </Box>
                        <Typography variant="body2" color="text.secondary">
                            {t('bin.subtitle', { days: stats?.retention_days ?? 30 })}
                        </Typography>
                    </Box>

                    <Stack direction="row" spacing={1.5} sx={{
  alignItems: "center",
  flexWrap: "wrap"
}}>
                        <Tooltip title={t('common.refresh')}>
                            <IconButton onClick={refresh} size="small" sx={{ border: '1px solid #e2e8f0' }}>
                                <RefreshOutlined fontSize="small" />
                            </IconButton>
                        </Tooltip>

                        {hasSelection && (
                            <>
                                <Button variant="outlined" color="success" size="small"
                                    startIcon={<RestoreFromTrashOutlined />} onClick={handleBulkRestore}
                                    sx={{ textTransform: 'none', fontWeight: 600 }}>
                                    {t('bin.restoreSelected')} ({selected.size})
                                </Button>
                                <Button variant="outlined" color="error" size="small"
                                    startIcon={<DeleteForeverOutlined />} onClick={handleBulkDelete}
                                    sx={{ textTransform: 'none', fontWeight: 600 }}>
                                    {t('bin.deleteSelected')} ({selected.size})
                                </Button>
                            </>
                        )}

                        {stats?.total_items > 0 && (
                            <Button variant="contained" color="error" size="small"
                                startIcon={<WarningAmberOutlined />} onClick={handleEmptyBin}
                                disableElevation sx={{ textTransform: 'none', fontWeight: 600 }}>
                                {t('bin.emptyBin')}
                            </Button>
                        )}
                    </Stack>
                </Box>

                {/* ── Stats Bar ──────────────────────────────────────────── */}
                <BinStatsBar stats={stats} loading={statsLoading} />

                {/* ── Filter Bar ─────────────────────────────────────────── */}
                <BinFilterBar
                    query={query} onQueryChange={setQuery}
                    typeFilter={typeFilter} onTypeFilterChange={setTypeFilter}
                    sort={sort} onSortChange={setSort}
                    viewLayout={viewLayout} onViewLayoutChange={setViewLayout}
                    gridSize={gridSize} onGridSizeChange={setGridSize}
                    resultCount={pagination.total}
                    perPage={perPage} onPerPageChange={handlePerPageChange}
                    allSelected={allSelected} hasSelection={hasSelection}
                    onSelectAll={selectAll} onDeselectAll={deselectAll}
                />

                {loading && <LinearProgress sx={{ height: 2 }} />}

                {/* ── Active Purge Banner (only when a job is running) ─────── */}
                <BinActivePurgeBanner onComplete={refresh} />

                {/* ── Content ────────────────────────────────────────────── */}
                <Box sx={{ flexGrow: 1, px: 4, py: 3 }}>
                    {isEmpty ? (
                        <BinEmptyState />
                    ) : viewLayout === 'grid' ? (
                        <BinGrid items={items} isSelected={isSelected} onToggleSelect={toggleItem}
                            onRestore={handleRestore} onDelete={handlePermanentDelete}
                            gridSize={gridSize} loading={loading} />
                    ) : (
                        <BinList items={items} isSelected={isSelected} onToggleSelect={toggleItem}
                            onRestore={handleRestore} onDelete={handlePermanentDelete}
                            loading={loading} sort={sort} onSortChange={setSort} />
                    )}

                    {pagination.pages > 1 && (
                        <Box sx={{ display: 'flex', justifyContent: 'center', mt: 4, mb: 1 }}>
                            <Pagination
                                count={pagination.pages}
                                page={currentPage}
                                onChange={(_, page) => setCurrentPage(page)}
                                color="primary"
                                shape="rounded"
                                showFirstButton
                                showLastButton
                            />
                        </Box>
                    )}
                </Box>
            </Box>

            <BinConfirmDialog
                open={confirmDialog.open} variant={confirmDialog.variant}
                count={confirmDialog.count} onConfirm={confirmDialog.onConfirm}
                onClose={closeConfirm}
            />
        </Box>
    );
}
