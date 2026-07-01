import React, { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Drawer, Box, Typography, Button, IconButton, FormControl,
    InputLabel, Select, MenuItem, Divider, ToggleButtonGroup,
    ToggleButton, Stack, TextField, Alert, CircularProgress,
    Collapse, FormControlLabel, Checkbox,
} from '@mui/material';
import {
    Close, PictureAsPdf, TableChart, FormatAlignLeft,
    AutoAwesome, Description,
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

export default function ReportBuilderDrawer({ open, onClose, onExportStarted, preselectedReportId }) {
    const { t } = useTranslation();
    const notify = useNotify();
    const [reports, setReports]              = useState([]);
    const [selectedReportId, setSelectedReportId] = useState('');
    const [dateRange, setDateRange]          = useState('last_30_days');
    const [customFrom, setCustomFrom]        = useState('');
    const [customTo, setCustomTo]            = useState('');
    const [format, setFormat]                = useState('pdf');
    const [includeArchived, setIncludeArchived] = useState(false);
    const [isSubmitting, setIsSubmitting]    = useState(false);
    const [loading, setLoading]              = useState(false);

    const DATE_RANGES = [
        { value: 'last_7_days',  label: t('reports.date_ranges.last_7_days') },
        { value: 'last_30_days', label: t('reports.date_ranges.last_30_days') },
        { value: 'last_90_days', label: t('reports.date_ranges.last_90_days') },
        { value: 'this_quarter', label: t('reports.date_ranges.this_quarter') },
        { value: 'this_year',    label: t('reports.date_ranges.this_year') },
        { value: 'custom',       label: t('reports.date_ranges.custom') },
    ];

    useEffect(() => {
        if (open) {
            setLoading(true);
            fetch('/admin/reports.json?active=true&per_page=100', { headers: { Accept: 'application/json' } })
                .then(r => r.json())
                .then(d => {
                    setReports(d.reports || []);
                    if (preselectedReportId) {
                        setSelectedReportId(preselectedReportId);
                    }
                })
                .catch(() => notify(t('reports.builder.error_load'), 'error'))
                .finally(() => setLoading(false));
        }
    }, [open, preselectedReportId]);

    const selectedReport = reports.find(r => r.id === selectedReportId);
    const canSubmit = selectedReportId && format;

    const handleGenerate = async () => {
        if (!canSubmit) return;
        setIsSubmitting(true);
        try {
            const csrf = document.querySelector('[name="csrf-token"]')?.content || '';
            const parameters = {
                date_range:       dateRange,
                from:             customFrom || undefined,
                to:               customTo   || undefined,
                include_archived: includeArchived,
            };
            const res  = await fetch(`/admin/reports/${selectedReportId}/generate.json`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
                body: JSON.stringify({ format, parameters })
            });
            const data = await res.json();
            if (data.success) {
                notify(t('reports.builder.queued'), 'success');
                onExportStarted();
                onClose();
                resetForm();
            } else {
                notify(data.error || t('reports.builder.error_queue'), 'error');
            }
        } catch { notify(t('reports.builder.network_error'), 'error'); }
        finally { setIsSubmitting(false); }
    };

    const resetForm = () => {
        setSelectedReportId('');
        setDateRange('last_30_days');
        setFormat('pdf');
    };

    return (
        <Drawer anchor="right" open={open} onClose={onClose}
            slotProps={{ paper: { sx: { width: 440, borderRadius: '16px 0 0 16px' } } }}>
            <Box sx={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
                {/* Header */}
                <Box sx={{ px: 3, py: 2.5, borderBottom: '1px solid #e2e8f0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <Stack direction="row" spacing={1.5} alignItems="center">
                        <Description sx={{ color: '#5e35b1' }} />
                        <Box>
                            <Typography variant="h6" sx={{ fontWeight: 700, lineHeight: 1.2 }}>{t('reports.builder.title')}</Typography>
                            <Typography variant="caption" color="textSecondary">{t('reports.builder.subtitle')}</Typography>
                        </Box>
                    </Stack>
                    <IconButton onClick={onClose} size="small"><Close /></IconButton>
                </Box>

                <Box sx={{ flex: 1, overflowY: 'auto', p: 3 }}>
                    {/* Step 1 — Report Type */}
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1, color: '#374151' }}>
                        {`1. ${t('reports.builder.step_type')}`}
                    </Typography>
                    {loading ? (
                        <CircularProgress size={20} sx={{ mb: 3 }} />
                    ) : (
                        <FormControl fullWidth size="small" sx={{ mb: selectedReport ? 1 : 3 }}>
                            <InputLabel>{t('reports.builder.select_report')}</InputLabel>
                            <Select value={selectedReportId} label={t('reports.builder.select_report')}
                                onChange={(e) => setSelectedReportId(e.target.value)}>
                                {reports.map(r => (
                                    <MenuItem key={r.id} value={r.id}>{r.name}</MenuItem>
                                ))}
                            </Select>
                        </FormControl>
                    )}
                    {selectedReport && (
                        <Alert severity="info" icon={<AutoAwesome fontSize="small" />}
                            sx={{ mb: 3, py: 0.5, borderRadius: 2, '& .MuiAlert-message': { fontSize: 12 } }}>
                            {t(`reports.type_descriptions.${selectedReport.report_type}`, { defaultValue: selectedReport.description || t('reports.builder.custom_report') })}
                        </Alert>
                    )}

                    {/* Step 2 — Time Range */}
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1, color: '#374151' }}>
                        {`2. ${t('reports.builder.step_range')}`}
                    </Typography>
                    <FormControl fullWidth size="small" sx={{ mb: dateRange === 'custom' ? 1.5 : 3 }}>
                        <Select value={dateRange} onChange={(e) => setDateRange(e.target.value)}>
                            {DATE_RANGES.map(r => (
                                <MenuItem key={r.value} value={r.value}>{r.label}</MenuItem>
                            ))}
                        </Select>
                    </FormControl>
                    <Collapse in={dateRange === 'custom'}>
                        <Stack direction="row" spacing={1.5} sx={{ mb: 3 }}>
                            <TextField size="small" type="date" label={t('reports.builder.from')} fullWidth value={customFrom}
                                onChange={(e) => setCustomFrom(e.target.value)} slotProps={{ inputLabel: { shrink: true } }} />
                            <TextField size="small" type="date" label={t('reports.builder.to')} fullWidth value={customTo}
                                onChange={(e) => setCustomTo(e.target.value)} slotProps={{ inputLabel: { shrink: true } }} />
                        </Stack>
                    </Collapse>

                    {/* Step 3 — Format */}
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5, color: '#374151' }}>
                        {`3. ${t('reports.builder.step_format')}`}
                    </Typography>
                    <ToggleButtonGroup value={format} exclusive fullWidth size="small"
                        onChange={(_, v) => v && setFormat(v)} sx={{ mb: 3 }}>
                        <ToggleButton value="pdf" sx={{ textTransform: 'none', gap: 0.5 }}>
                            <PictureAsPdf sx={{ fontSize: 18 }} /> {t('reports.builder.format_pdf')}
                        </ToggleButton>
                        <ToggleButton value="xlsx" sx={{ textTransform: 'none', gap: 0.5 }}>
                            <TableChart sx={{ fontSize: 18 }} /> {t('reports.builder.format_xlsx')}
                        </ToggleButton>
                        <ToggleButton value="csv" sx={{ textTransform: 'none', gap: 0.5 }}>
                            <FormatAlignLeft sx={{ fontSize: 18 }} /> {t('reports.builder.format_csv')}
                        </ToggleButton>
                    </ToggleButtonGroup>

                    {/* Format description */}
                    <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0', mb: 3 }}>
                        <Typography variant="caption" color="textSecondary">
                            {format === 'pdf'  && `📄 ${t('reports.builder.format_pdf_desc')}`}
                            {format === 'xlsx' && `📊 ${t('reports.builder.format_xlsx_desc')}`}
                            {format === 'csv'  && `📋 ${t('reports.builder.format_csv_desc')}`}
                        </Typography>
                    </Box>

                    {/* Include archived */}
                    <FormControlLabel
                        control={<Checkbox size="small" checked={includeArchived} onChange={(e) => setIncludeArchived(e.target.checked)} />}
                        label={<Typography variant="caption">{t('reports.builder.include_archived')}</Typography>}
                        sx={{ mb: 2 }}
                    />
                </Box>

                {/* Footer Actions */}
                <Divider />
                <Box sx={{ px: 3, py: 2, bgcolor: '#f8fafc', display: 'flex', gap: 1.5 }}>
                    <Button variant="outlined" fullWidth onClick={onClose} sx={{ textTransform: 'none' }}>
                        {t('reports.types.form.cancel')}
                    </Button>
                    <Button variant="contained" fullWidth onClick={handleGenerate}
                        disabled={!canSubmit || isSubmitting}
                        startIcon={isSubmitting ? <CircularProgress size={16} color="inherit" /> : null}
                        sx={{ textTransform: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                        {isSubmitting ? t('reports.builder.generating') : t('reports.builder.generate')}
                    </Button>
                </Box>
            </Box>
        </Drawer>
    );
}
