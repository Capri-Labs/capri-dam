import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, Paper, Typography, Grid, TextField, MenuItem, Button,
    Table, TableHead, TableBody, TableRow, TableCell, Chip,
    CircularProgress, Stack, FormControlLabel, Checkbox, Tooltip, IconButton
} from '@mui/material';
import { History, NavigateBefore, NavigateNext, Info } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';

const EMPTY_FILTERS = {
    user_id: '',
    audit_action: '',
    auditable_type: '',
    impersonated: false,
    date_from: '',
    date_to: '',
    search: '',
};

export default function AuditLogTab() {
    const { t } = useTranslation();
    const notify = useNotify();

    const [loading, setLoading] = useState(true);
    const [logs, setLogs] = useState([]);
    const [pagination, setPagination] = useState({ page: 1, per_page: 25, total: 0, total_pages: 0 });
    const [filterOptions, setFilterOptions] = useState({ actions: [], auditable_types: [] });
    const [filters, setFilters] = useState(EMPTY_FILTERS);
    const [appliedFilters, setAppliedFilters] = useState(EMPTY_FILTERS);

    const fetchLogs = useCallback((page, activeFilters) => {
        setLoading(true);
        const params = new URLSearchParams({ page, per_page: pagination.per_page });
        Object.entries(activeFilters).forEach(([ key, value ]) => {
            if (value !== '' && value !== false) params.set(key, value);
        });

        fetch(`/admin/audit_logs?${params.toString()}`)
            .then(res => res.json())
            .then(data => {
                setLogs(data.audit_logs || []);
                setPagination(data.pagination || { page: 1, per_page: 25, total: 0, total_pages: 0 });
                setFilterOptions(data.filter_options || { actions: [], auditable_types: [] });
                setLoading(false);
            })
            .catch(() => {
                setLoading(false);
                notify(t('auditLog.loadError'), 'error');
            });
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [ pagination.per_page ]);

    useEffect(() => {
        fetchLogs(1, EMPTY_FILTERS);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    const handleApplyFilters = () => {
        setAppliedFilters(filters);
        fetchLogs(1, filters);
    };

    const handleClearFilters = () => {
        setFilters(EMPTY_FILTERS);
        setAppliedFilters(EMPTY_FILTERS);
        fetchLogs(1, EMPTY_FILTERS);
    };

    const handlePageChange = (nextPage) => {
        fetchLogs(nextPage, appliedFilters);
    };

    const from = pagination.total === 0 ? 0 : (pagination.page - 1) * pagination.per_page + 1;
    const to = Math.min(pagination.page * pagination.per_page, pagination.total);

    return (
        <Paper elevation={0} sx={{ p: 3, border: '2px solid #37474f', borderRadius: 3, bgcolor: '#f7f9fa' }}>
            <Typography variant="h6" sx={{ fontWeight: 700, mb: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
                <History color="primary" /> {t('auditLog.title')}
            </Typography>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                {t('auditLog.description')}
            </Typography>

            <Paper variant="outlined" sx={{ p: 2, mb: 3, borderRadius: 3 }}>
                <Grid container spacing={2} alignItems="center">
                    <Grid size={{ xs: 12, sm: 6, md: 3 }}>
                        <TextField
                            select
                            fullWidth
                            size="small"
                            label={t('auditLog.filters.action')}
                            value={filters.audit_action}
                            onChange={(e) => setFilters({ ...filters, audit_action: e.target.value })}
                        >
                            <MenuItem value="">{t('auditLog.filters.allActions')}</MenuItem>
                            {filterOptions.actions.map((action) => (
                                <MenuItem key={action} value={action}>{action}</MenuItem>
                            ))}
                        </TextField>
                    </Grid>

                    <Grid size={{ xs: 12, sm: 6, md: 3 }}>
                        <TextField
                            select
                            fullWidth
                            size="small"
                            label={t('auditLog.filters.resourceType')}
                            value={filters.auditable_type}
                            onChange={(e) => setFilters({ ...filters, auditable_type: e.target.value })}
                        >
                            <MenuItem value="">{t('auditLog.filters.allResourceTypes')}</MenuItem>
                            {filterOptions.auditable_types.map((type) => (
                                <MenuItem key={type} value={type}>{type}</MenuItem>
                            ))}
                        </TextField>
                    </Grid>

                    <Grid size={{ xs: 6, sm: 3, md: 2 }}>
                        <TextField
                            fullWidth
                            size="small"
                            type="date"
                            label={t('auditLog.filters.dateFrom')}
                            InputLabelProps={{ shrink: true }}
                            value={filters.date_from}
                            onChange={(e) => setFilters({ ...filters, date_from: e.target.value })}
                        />
                    </Grid>

                    <Grid size={{ xs: 6, sm: 3, md: 2 }}>
                        <TextField
                            fullWidth
                            size="small"
                            type="date"
                            label={t('auditLog.filters.dateTo')}
                            InputLabelProps={{ shrink: true }}
                            value={filters.date_to}
                            onChange={(e) => setFilters({ ...filters, date_to: e.target.value })}
                        />
                    </Grid>

                    <Grid size={{ xs: 12, md: 2 }}>
                        <FormControlLabel
                            control={
                                <Checkbox
                                    checked={filters.impersonated}
                                    onChange={(e) => setFilters({ ...filters, impersonated: e.target.checked })}
                                />
                            }
                            label={t('auditLog.filters.impersonatedOnly')}
                        />
                    </Grid>

                    <Grid size={{ xs: 12, md: 8 }}>
                        <TextField
                            fullWidth
                            size="small"
                            label={t('auditLog.filters.search')}
                            value={filters.search}
                            onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                        />
                    </Grid>

                    <Grid size={{ xs: 12, md: 4 }}>
                        <Stack direction="row" spacing={1} justifyContent="flex-end">
                            <Button variant="outlined" onClick={handleClearFilters}>
                                {t('auditLog.filters.clear')}
                            </Button>
                            <Button variant="contained" onClick={handleApplyFilters}>
                                {t('auditLog.filters.apply')}
                            </Button>
                        </Stack>
                    </Grid>
                </Grid>
            </Paper>

            {loading ? (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}><CircularProgress size={30} /></Box>
            ) : logs.length === 0 ? (
                <Typography variant="body2" color="textSecondary" sx={{ py: 4, textAlign: 'center' }}>
                    {t('auditLog.empty')}
                </Typography>
            ) : (
                <Table size="small">
                    <TableHead>
                        <TableRow>
                            <TableCell>{t('auditLog.table.timestamp')}</TableCell>
                            <TableCell>{t('auditLog.table.actor')}</TableCell>
                            <TableCell>{t('auditLog.table.action')}</TableCell>
                            <TableCell>{t('auditLog.table.resource')}</TableCell>
                            <TableCell>{t('auditLog.table.impersonated')}</TableCell>
                            <TableCell>{t('auditLog.table.ipAddress')}</TableCell>
                            <TableCell align="right">{t('auditLog.table.details')}</TableCell>
                        </TableRow>
                    </TableHead>
                    <TableBody>
                        {logs.map((log) => (
                            <TableRow key={log.id} hover>
                                <TableCell>{new Date(log.created_at).toLocaleString()}</TableCell>
                                <TableCell>
                                    {log.impersonated
                                        ? t('auditLog.impersonatedBy', { actor: log.user?.email, trueActor: log.true_user?.email })
                                        : (log.user?.email || '—')}
                                </TableCell>
                                <TableCell>
                                    <Chip label={log.action} size="small" />
                                </TableCell>
                                <TableCell>{log.auditable_type}#{log.auditable_id}</TableCell>
                                <TableCell>{log.impersonated ? '✓' : ''}</TableCell>
                                <TableCell>{log.ip_address}</TableCell>
                                <TableCell align="right">
                                    <Tooltip title={JSON.stringify(log.changes_data)}>
                                        <IconButton size="small">
                                            <Info fontSize="small" />
                                        </IconButton>
                                    </Tooltip>
                                </TableCell>
                            </TableRow>
                        ))}
                    </TableBody>
                </Table>
            )}

            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', pt: 2 }}>
                <Typography variant="caption" color="textSecondary">
                    {t('auditLog.pagination.showing', { from, to, total: pagination.total })}
                </Typography>
                <Stack direction="row" spacing={1}>
                    <Button
                        size="small"
                        startIcon={<NavigateBefore />}
                        disabled={pagination.page <= 1}
                        onClick={() => handlePageChange(pagination.page - 1)}
                    >
                        {t('auditLog.pagination.previous')}
                    </Button>
                    <Button
                        size="small"
                        endIcon={<NavigateNext />}
                        disabled={pagination.page >= pagination.total_pages}
                        onClick={() => handlePageChange(pagination.page + 1)}
                    >
                        {t('auditLog.pagination.next')}
                    </Button>
                </Stack>
            </Box>
        </Paper>
    );
}
