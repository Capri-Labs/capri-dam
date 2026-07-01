import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Box, CssBaseline, Tabs, Tab, Typography, Stack, Button } from '@mui/material';
import { BarChart, Download, Add, ListAlt } from '@mui/icons-material';
import AnalyticsDashboard from './AnalyticsDashboard';
import DownloadCenter from './DownloadCenter';
import ReportBuilderDrawer from './ReportBuilderDrawer';
import ReportTypesManager from './ReportTypesManager';

// Tab panel helper
function TabPanel({ children, value, index }) {
    return value === index ? <Box sx={{ pt: 3 }}>{children}</Box> : null;
}

export default function ReportsHub() {
    const { t } = useTranslation();
    const [tab, setTab]                      = useState(0);
    const [drawerOpen, setDrawerOpen]        = useState(false);
    const [preselectedReportId, setPreselectedReportId] = useState(null);
    const [refreshTrigger, setRefreshTrigger] = useState(0);

    const handleExportStarted = () => {
        setRefreshTrigger(t => t + 1);
        setTab(1); // Switch to Download Center automatically
    };

    const handleOpenBuilderForType = (reportId) => {
        setPreselectedReportId(reportId);
        setDrawerOpen(true);
    };

    return (
        <Box sx={{ bgcolor: '#f4f7fb', minHeight: '100vh', p: { xs: 2, md: 3 } }}>
            <CssBaseline />

            {/* Page header */}
            <Stack direction="row" sx={{ mb: 2, alignItems: 'center', justifyContent: 'space-between' }}>
                <Box>
                    <Typography variant="h4" sx={{ fontWeight: 800, color: '#0f172a' }}>
                        {t('reports.title')}
                    </Typography>
                    <Typography variant="body2" color="textSecondary">
                        {t('reports.subtitle')}
                    </Typography>
                </Box>
                <Button
                    variant="contained"
                    startIcon={<Add />}
                    onClick={() => { setPreselectedReportId(null); setDrawerOpen(true); }}
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none' }}>
                    {t('reports.create_export')}
                </Button>
            </Stack>

            {/* Navigation Tabs */}
            <Box sx={{ borderBottom: 1, borderColor: '#e2e8f0', mb: 0 }}>
                <Tabs value={tab} onChange={(_, v) => setTab(v)}
                    slotProps={{ indicator: { style: { backgroundColor: '#5e35b1' } } }}>
                    <Tab icon={<BarChart fontSize="small" />} iconPosition="start"
                        label={t('reports.tabs.analytics')}
                        sx={{ textTransform: 'none', fontWeight: 600, minHeight: 44, gap: 0.5,
                              '&.Mui-selected': { color: '#5e35b1' } }} />
                    <Tab icon={<Download fontSize="small" />} iconPosition="start"
                        label={t('reports.tabs.downloads')}
                        sx={{ textTransform: 'none', fontWeight: 600, minHeight: 44, gap: 0.5,
                              '&.Mui-selected': { color: '#5e35b1' } }} />
                    <Tab icon={<ListAlt fontSize="small" />} iconPosition="start"
                        label={t('reports.tabs.types')}
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

            <TabPanel value={tab} index={2}>
                <ReportTypesManager onOpenBuilder={handleOpenBuilderForType} />
            </TabPanel>

            {/* Global export builder drawer */}
            <ReportBuilderDrawer
                open={drawerOpen}
                onClose={() => { setDrawerOpen(false); setPreselectedReportId(null); }}
                onExportStarted={handleExportStarted}
                preselectedReportId={preselectedReportId}
            />
        </Box>
    );
}

