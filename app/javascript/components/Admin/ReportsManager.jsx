import React, { useState, useEffect } from 'react';
import { Box, Typography, Grid, Select, MenuItem, CssBaseline, Button } from '@mui/material';
import { Add } from '@mui/icons-material';

import Sidebar from "../Sidebar";
import { ReportFilterProvider, useReportFilters } from '../../context/ReportFilterContext';
import BarChartWidget from './widgets/BarChartWidget';
import ReportExportTable from './ReportExportTable'; // We will update this next
import ReportBuilderDrawer from './ReportBuilderDrawer';
import { navigateTo } from "../../utils/globalutils";

function DashboardContent() {
    const { dateRange, setDateRange } = useReportFilters();
    const [chartData, setChartData] = useState([]);

    // Drawer State
    const [drawerOpen, setDrawerOpen] = useState(false);
    // State to force-refresh the data grid when a new export is queued
    const [refreshTrigger, setRefreshTrigger] = useState(0);

    useEffect(() => {
        // Mock analytics fetch
        setChartData([
            { date: 'Mon', assets: 40, workflows: 24 },
            { date: 'Tue', assets: 30, workflows: 13 },
            { date: 'Wed', assets: 20, workflows: 48 },
            { date: 'Thu', assets: 27, workflows: 39 },
            { date: 'Fri', assets: 18, workflows: 48 },
        ]);
    }, [dateRange]);

    return (
        <Box sx={{ flexGrow: 1, p: 3, display: 'flex', flexDirection: 'column' }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
                <Box>
                    <Typography variant="h4" sx={{ fontWeight: 700 }}>System Analytics</Typography>
                    <Typography variant="body2" color="textSecondary">Monitor DAM performance and export compliance reports.</Typography>
                </Box>

                <Box sx={{ display: 'flex', gap: 2 }}>
                    <Select
                        value={dateRange}
                        onChange={(e) => setDateRange(e.target.value)}
                        size="small"
                        sx={{ width: 200, bgcolor: 'white' }}
                    >
                        <MenuItem value="last_7_days">Last 7 Days</MenuItem>
                        <MenuItem value="last_30_days">Last 30 Days</MenuItem>
                        <MenuItem value="this_quarter">This Quarter</MenuItem>
                    </Select>

                    <Button
                        variant="contained"
                        startIcon={<Add />}
                        onClick={() => setDrawerOpen(true)}
                        sx={{ boxShadow: 'none' }}
                    >
                        Create Export
                    </Button>
                </Box>
            </Box>

            <Grid container spacing={3}>
                <Grid item xs={12} md={8}>
                    <BarChartWidget
                        title="System Throughput"
                        data={chartData}
                        dataKeyX="date"
                        dataBars={[
                            { key: 'assets', name: 'Assets Ingested', color: '#3b82f6' },
                            { key: 'workflows', name: 'Workflows Completed', color: '#10b981' }
                        ]}
                    />
                </Grid>

                <Grid item xs={12} md={4}>
                    <Box sx={{ height: '100%', bgcolor: 'white', borderRadius: 2, border: '1px solid #e2e8f0', p: 3 }}>
                        <Typography variant="subtitle2" color="textSecondary">Storage Cost Estimate (Draft)</Typography>
                        <Typography variant="h3" sx={{ mt: 2, fontWeight: 700, color: '#1e293b' }}>€412</Typography>
                        <Typography variant="body2" color="error.main" sx={{ mt: 1, fontWeight: 500 }}>+5% from dormant assets</Typography>
                    </Box>
                </Grid>

                {/* The Download Hub */}
                <Grid item xs={12}>
                    <ReportExportTable refreshTrigger={refreshTrigger} />
                </Grid>
            </Grid>

            <ReportBuilderDrawer
                open={drawerOpen}
                onClose={() => setDrawerOpen(false)}
                onExportStarted={() => setRefreshTrigger(prev => prev + 1)}
            />
        </Box>
    );
}

export default function ReportsManager() {
    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <ReportFilterProvider>
                <DashboardContent />
            </ReportFilterProvider>
        </Box>
    );
}