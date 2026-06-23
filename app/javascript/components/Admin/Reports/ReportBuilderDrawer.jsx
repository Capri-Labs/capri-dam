import React, { useState, useEffect } from 'react';
import {
    Drawer, Box, Typography, Button, IconButton, FormControl,
    InputLabel, Select, MenuItem, Divider, ToggleButtonGroup,
    ToggleButton, Stack, TextField, Chip, Alert, CircularProgress,
    Stepper, Step, StepLabel, Collapse
} from '@mui/material';
import {
    Close, PictureAsPdf, TableChart, FormatAlignLeft,
    AutoAwesome, DateRange, Description, Download
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

const REPORT_DESCRIPTIONS = {
    asset_library:      'Overview of all assets by status, type, and folder.',
    workflow_compliance:'Approval rates, review times, and SLA adherence.',
    storage_usage:      'Storage breakdown by content type, folder, and user.',
    user_activity:      'Upload frequency and workflow actions per user.',
    ai_coverage:        'Vector embedding coverage and AI enrichment ROI.',
    duplicates:         'Duplicate assets found and blocked — quantifies storage savings.',
    license_expiry:     'Assets with licenses expiring in the next 30/60/90 days.',
    collections:        'Collection performance and AI vs manual routing ratio.',
    audit_trail:        'Full immutable log of all system actions.',
    migration:          'Migration batch results and cost savings per source system.',
};

const DATE_RANGES = [
    { value: 'last_7_days',  label: 'Last 7 Days' },
    { value: 'last_30_days', label: 'Last 30 Days' },
    { value: 'last_90_days', label: 'Last 90 Days' },
    { value: 'this_quarter', label: 'This Quarter' },
    { value: 'this_year',    label: 'Year to Date' },
    { value: 'custom',       label: 'Custom Range' },
];

export default function ReportBuilderDrawer({ open, onClose, onExportStarted }) {
    const notify = useNotify();
    const [reports, setReports]              = useState([]);
    const [selectedReportId, setSelectedReportId] = useState('');
    const [dateRange, setDateRange]          = useState('last_30_days');
    const [customFrom, setCustomFrom]        = useState('');
    const [customTo, setCustomTo]            = useState('');
    const [format, setFormat]                = useState('pdf');
    const [includeArchived, setIncludeArchived] = useState(false);
    const [isSubmitting, setIsSubmitting]    = useState(false);
    const [step, setStep]                    = useState(0);

    useEffect(() => {
        if (open && reports.length === 0) {
            fetch('/admin/reports.json', { headers: { Accept: 'application/json' } })
                .then(r => r.json())
                .then(d => setReports(d.reports || []))
                .catch(() => notify('Failed to load report types.', 'error'));
        }
    }, [open]);

    const selectedReport = reports.find(r => r.id === selectedReportId);
    const canSubmit = selectedReportId && format;

    const handleGenerate = async () => {
        if (!canSubmit) return;
        setIsSubmitting(true);
        try {
            const csrf = document.querySelector('[name="csrf-token"]').content;
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
                notify('✅ Report queued. You\'ll be notified when it\'s ready.', 'success');
                onExportStarted();
                onClose();
                resetForm();
            } else {
                notify(data.error || 'Failed to queue report.', 'error');
            }
        } catch { notify('Network error.', 'error'); }
        finally { setIsSubmitting(false); }
    };

    const resetForm = () => {
        setSelectedReportId('');
        setDateRange('last_30_days');
        setFormat('pdf');
        setStep(0);
    };

    return (
        <Drawer anchor="right" open={open} onClose={onClose}
            PaperProps={{ sx: { width: 440, borderRadius: '16px 0 0 16px' } }}>
            <Box sx={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
                {/* Header */}
                <Box sx={{ px: 3, py: 2.5, borderBottom: '1px solid #e2e8f0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <Stack direction="row" spacing={1.5} alignItems="center">
                        <Description sx={{ color: '#5e35b1' }} />
                        <Box>
                            <Typography variant="h6" sx={{ fontWeight: 700, lineHeight: 1.2 }}>Create Export</Typography>
                            <Typography variant="caption" color="textSecondary">Generate a scheduled report</Typography>
                        </Box>
                    </Stack>
                    <IconButton onClick={onClose} size="small"><Close /></IconButton>
                </Box>

                <Box sx={{ flex: 1, overflowY: 'auto', p: 3 }}>
                    {/* Step 1 — Report Type */}
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1, color: '#374151' }}>
                        1. Report Type
                    </Typography>
                    <FormControl fullWidth size="small" sx={{ mb: selectedReport ? 1 : 3 }}>
                        <InputLabel>Select Report</InputLabel>
                        <Select value={selectedReportId} label="Select Report"
                            onChange={(e) => setSelectedReportId(e.target.value)}>
                            {reports.map(r => (
                                <MenuItem key={r.id} value={r.id}>{r.name}</MenuItem>
                            ))}
                        </Select>
                    </FormControl>
                    {selectedReport && (
                        <Alert severity="info" icon={<AutoAwesome fontSize="small" />}
                            sx={{ mb: 3, py: 0.5, borderRadius: 2, '& .MuiAlert-message': { fontSize: 12 } }}>
                            {REPORT_DESCRIPTIONS[selectedReport.report_type] || 'Custom report'}
                        </Alert>
                    )}

                    {/* Step 2 — Time Range */}
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1, color: '#374151' }}>
                        2. Time Range
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
                            <TextField size="small" type="date" label="From" fullWidth value={customFrom}
                                onChange={(e) => setCustomFrom(e.target.value)} InputLabelProps={{ shrink: true }} />
                            <TextField size="small" type="date" label="To" fullWidth value={customTo}
                                onChange={(e) => setCustomTo(e.target.value)} InputLabelProps={{ shrink: true }} />
                        </Stack>
                    </Collapse>

                    {/* Step 3 — Format */}
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5, color: '#374151' }}>
                        3. Output Format
                    </Typography>
                    <ToggleButtonGroup value={format} exclusive fullWidth size="small"
                        onChange={(_, v) => v && setFormat(v)} sx={{ mb: 3 }}>
                        <ToggleButton value="pdf" sx={{ textTransform: 'none', gap: 0.5 }}>
                            <PictureAsPdf sx={{ fontSize: 18 }} /> PDF
                        </ToggleButton>
                        <ToggleButton value="xlsx" sx={{ textTransform: 'none', gap: 0.5 }}>
                            <TableChart sx={{ fontSize: 18 }} /> Excel
                        </ToggleButton>
                        <ToggleButton value="csv" sx={{ textTransform: 'none', gap: 0.5 }}>
                            <FormatAlignLeft sx={{ fontSize: 18 }} /> CSV
                        </ToggleButton>
                    </ToggleButtonGroup>

                    {/* Format descriptions */}
                    <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0', mb: 3 }}>
                        {format === 'pdf'  && <Typography variant="caption" color="textSecondary">📄 <strong>PDF</strong> — Formatted for executive review. Includes charts and summary tables.</Typography>}
                        {format === 'xlsx' && <Typography variant="caption" color="textSecondary">📊 <strong>Excel</strong> — Pivot-ready data with multiple worksheets. Best for data analysis.</Typography>}
                        {format === 'csv'  && <Typography variant="caption" color="textSecondary">📋 <strong>CSV</strong> — Raw flat data. Best for import into BI tools (Power BI, Tableau).</Typography>}
                    </Box>

                    <Alert severity="warning" sx={{ py: 0.5, borderRadius: 2 }}>
                        <Typography variant="caption">
                            Report generation runs in the background. You'll be notified via email when the download is ready. Large datasets may take up to 5 minutes.
                        </Typography>
                    </Alert>
                </Box>

                {/* Footer Actions */}
                <Box sx={{ px: 3, py: 2, borderTop: '1px solid #e2e8f0', bgcolor: '#f8fafc', display: 'flex', gap: 1.5 }}>
                    <Button variant="outlined" fullWidth onClick={onClose} sx={{ textTransform: 'none' }}>Cancel</Button>
                    <Button variant="contained" fullWidth onClick={handleGenerate}
                        disabled={!canSubmit || isSubmitting}
                        startIcon={isSubmitting ? <CircularProgress size={16} color="inherit" /> : <Download />}
                        sx={{ textTransform: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                        {isSubmitting ? 'Queueing…' : 'Generate Report'}
                    </Button>
                </Box>
            </Box>
        </Drawer>
    );
}

