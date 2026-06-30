import React, { useState } from 'react';
import { Box, CssBaseline, Tabs, Tab, Typography, Stack } from '@mui/material';
import { BarChart, Download, BarChartOutlined } from '@mui/icons-material';
import AnalyticsDashboard from './AnalyticsDashboard';
import DownloadCenter from './DownloadCenter';
import ReportBuilderDrawer from './ReportBuilderDrawer';

// Tab panel helper
function TabPanel({ children, value, index }) {
    return value === index ? <Box sx={{ pt: 3 }}>{children}</Box> : null;
}

export default function ReportsHub() {
    const [tab, setTab]                      = useState(0);
    const [drawerOpen, setDrawerOpen]        = useState(false);
    const [refreshTrigger, setRefreshTrigger] = useState(0);

    const handleExportStarted = () => {
        setRefreshTrigger(t => t + 1);
        setTab(1); // Switch to Download Center automatically
    };

    return (
        <Box sx={{ bgcolor: '#f4f7fb', minHeight: '100vh', p: { xs: 2, md: 3 } }}>
            <CssBaseline />

            {/* Page header */}
            <Stack direction="row" sx={{
  mb: 2,
  alignItems: "center",
  justifyContent: "space-between"
}}>
                <Box>
                    <Typography variant="h4" sx={{ fontWeight: 800, color: '#0f172a' }}>Reports & Analytics</Typography>
                    <Typography variant="body2" color="textSecondary">
                        Live system insights, AI-powered anomaly detection, and scheduled exports
                    </Typography>
                </Box>
            </Stack>

            {/* Navigation Tabs */}
            <Box sx={{ borderBottom: 1, borderColor: '#e2e8f0', mb: 0 }}>
                <Tabs value={tab} onChange={(_, v) => setTab(v)} slotProps={{
  indicator: {
    style: {
      backgroundColor: '#5e35b1'
    }
  }
}}>
                    <Tab icon={<BarChart fontSize="small" />} iconPosition="start"
                        label="Analytics Dashboard"
                        sx={{ textTransform: 'none', fontWeight: 600, minHeight: 44, gap: 0.5,
                              '&.Mui-selected': { color: '#5e35b1' } }} />
                    <Tab icon={<Download fontSize="small" />} iconPosition="start"
                        label="Download Center"
                        sx={{ textTransform: 'none', fontWeight: 600, minHeight: 44, gap: 0.5,
                              '&.Mui-selected': { color: '#5e35b1' } }} />
                </Tabs>
            </Box>

            <TabPanel value={tab} index={0}>
                <AnalyticsDashboard onCreateExport={() => setDrawerOpen(true)} />
            </TabPanel>

            <TabPanel value={tab} index={1}>
                <DownloadCenter refreshTrigger={refreshTrigger} />
            </TabPanel>

            {/* Global export builder drawer */}
            <ReportBuilderDrawer
                open={drawerOpen}
                onClose={() => setDrawerOpen(false)}
                onExportStarted={handleExportStarted}
            />
        </Box>
    );
}

