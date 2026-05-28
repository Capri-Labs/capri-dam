import React, { useState, useEffect } from 'react';
import {
    Drawer, Box, Typography, Button, IconButton,
    FormControl, InputLabel, Select, MenuItem, Divider, ToggleButtonGroup, ToggleButton
} from '@mui/material';
import { Close, PictureAsPdf, TableChart, FormatAlignLeft } from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

export default function ReportBuilderDrawer({ open, onClose, onExportStarted }) {
    const notify = useNotify();
    const [reports, setReports] = useState([]);

    // Form State
    const [selectedReportId, setSelectedReportId] = useState('');
    const [dateRange, setDateRange] = useState('last_30_days');
    const [format, setFormat] = useState('pdf');
    const [isSubmitting, setIsSubmitting] = useState(false);

    useEffect(() => {
        if (open && reports.length === 0) {
            fetch('/admin/reports.json')
                .then(res => res.json())
                .then(data => setReports(data.reports || []));
        }
    }, [open, reports.length]);

    const handleGenerate = () => {
        if (!selectedReportId) {
            notify("Please select a report type.", "warning");
            return;
        }

        setIsSubmitting(true);
        const csrfToken = document.querySelector('[name="csrf-token"]').content;

        fetch(`/admin/reports/${selectedReportId}/generate.json`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify({ format: format, parameters: { date_range: dateRange } })
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify("Report generation queued successfully.", "success");
                    onExportStarted(); // Refresh the parent table
                    onClose(); // Close the drawer
                } else {
                    notify(data.error || "Generation failed.", "error");
                }
            })
            .finally(() => setIsSubmitting(false));
    };

    return (
        <Drawer anchor="right" open={open} onClose={onClose}>
            <Box sx={{ width: 400, p: 3, display: 'flex', flexDirection: 'column', height: '100%' }}>
                {/* Header */}
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                    <Typography variant="h6" fontWeight="bold">Create Export</Typography>
                    <IconButton onClick={onClose} size="small"><Close /></IconButton>
                </Box>
                <Divider sx={{ mb: 3 }} />

                {/* Step 1: Report Type */}
                <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>1. Select Report Type</Typography>
                <FormControl fullWidth size="small" sx={{ mb: 3 }}>
                    <InputLabel>Report Definition</InputLabel>
                    <Select
                        value={selectedReportId}
                        label="Report Definition"
                        onChange={(e) => setSelectedReportId(e.target.value)}
                    >
                        {reports.map(r => (
                            <MenuItem key={r.id} value={r.id}>{r.name}</MenuItem>
                        ))}
                    </Select>
                </FormControl>

                {/* Step 2: Date Range */}
                <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>2. Time Range</Typography>
                <FormControl fullWidth size="small" sx={{ mb: 3 }}>
                    <Select value={dateRange} onChange={(e) => setDateRange(e.target.value)}>
                        <MenuItem value="last_7_days">Last 7 Days</MenuItem>
                        <MenuItem value="last_30_days">Last 30 Days</MenuItem>
                        <MenuItem value="this_quarter">This Quarter</MenuItem>
                        <MenuItem value="this_year">Year to Date</MenuItem>
                    </Select>
                </FormControl>

                {/* Step 3: Format */}
                <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>3. Output Format</Typography>
                <ToggleButtonGroup
                    value={format}
                    exclusive
                    onChange={(e, newFormat) => newFormat && setFormat(newFormat)}
                    fullWidth
                    size="small"
                    sx={{ mb: 4 }}
                >
                    <ToggleButton value="pdf"><PictureAsPdf sx={{ mr: 1, fontSize: 18 }} /> PDF</ToggleButton>
                    <ToggleButton value="xlsx"><TableChart sx={{ mr: 1, fontSize: 18 }} /> Excel</ToggleButton>
                    <ToggleButton value="csv"><FormatAlignLeft sx={{ mr: 1, fontSize: 18 }} /> CSV</ToggleButton>
                </ToggleButtonGroup>

                {/* Actions */}
                <Box sx={{ mt: 'auto', display: 'flex', gap: 2 }}>
                    <Button variant="outlined" fullWidth onClick={onClose}>Cancel</Button>
                    <Button
                        variant="contained"
                        fullWidth
                        onClick={handleGenerate}
                        disabled={isSubmitting || !selectedReportId}
                    >
                        {isSubmitting ? 'Queueing...' : 'Generate Report'}
                    </Button>
                </Box>
            </Box>
        </Drawer>
    );
}