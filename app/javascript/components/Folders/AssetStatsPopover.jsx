import React, { useEffect, useState } from 'react';
import { Box, IconButton, Popover, Typography, Grid, Paper, Tooltip } from '@mui/material';
import { AnalyticsOutlined, CloudDownloadOutlined, RemoveRedEyeOutlined, ShareOutlined } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

// Toolbar entry point for asset usage statistics (moved out of the tabbed
// inspector so it's visible without switching tabs). Counts are real,
// app-observed numbers from GET /api/v1/assets/:id/stats — see
// Api::V1::AssetsController#track_event for how "view"/"download"/"share"
// events are recorded and why CDN-served bytes can't be counted directly.
export default function AssetStatsPopover({ asset }) {
    const { t } = useTranslation();
    const tr = (key, defaultValue) => {
        const value = t(key, { defaultValue });
        return value === key ? defaultValue : value;
    };

    const [anchorEl, setAnchorEl] = useState(null);
    const [stats, setStats] = useState({ views: 0, downloads: 0, shares: 0 });
    const open = Boolean(anchorEl);

    const fetchStats = async () => {
        if (!asset?.id) return;
        try {
            const response = await fetch(`/api/v1/assets/${asset.id}/stats`);
            if (!response.ok) return;
            const data = await response.json();
            setStats({
                views: data.views ?? 0,
                downloads: data.downloads ?? 0,
                shares: data.shares ?? 0,
            });
        } catch (error) {
            // Stats are non-critical to the viewing experience; fail silently.
        }
    };

    useEffect(() => {
        fetchStats();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [asset?.id]);

    const handleOpen = (event) => {
        setAnchorEl(event.currentTarget);
        fetchStats();
    };
    const handleClose = () => setAnchorEl(null);

    const statBlock = (icon, label, value) => (
        <Paper elevation={0} sx={{ p: 1.5, border: '1px solid #e2e8f0', borderRadius: 2, textAlign: 'center', bgcolor: '#f8fafc', flex: 1 }}>
            {icon}
            <Typography variant="h6" fontWeight="700" sx={{ mt: 0.5 }}>{value}</Typography>
            <Typography variant="caption" color="textSecondary">{label}</Typography>
        </Paper>
    );

    return (
        <>
            <Tooltip title={tr('assetStatisticsTab.title', 'Asset Statistics')}>
                <IconButton color="inherit" onClick={handleOpen} data-testid="asset-stats-toggle">
                    <AnalyticsOutlined fontSize="small" />
                </IconButton>
            </Tooltip>
            <Popover
                open={open}
                anchorEl={anchorEl}
                onClose={handleClose}
                anchorOrigin={{ vertical: 'bottom', horizontal: 'right' }}
                transformOrigin={{ vertical: 'top', horizontal: 'right' }}
            >
                <Box sx={{ p: 2, width: 320 }}>
                    <Typography variant="subtitle1" fontWeight="700" sx={{ mb: 2 }}>
                        {tr('assetStatisticsTab.title', 'Asset Statistics')}
                    </Typography>
                    <Grid container spacing={1.5}>
                        <Grid size={4}>{statBlock(<RemoveRedEyeOutlined color="primary" fontSize="small" />, tr('assetStatisticsTab.views', 'Views'), stats.views)}</Grid>
                        <Grid size={4}>{statBlock(<CloudDownloadOutlined color="primary" fontSize="small" />, tr('assetStatisticsTab.downloads', 'Downloads'), stats.downloads)}</Grid>
                        <Grid size={4}>{statBlock(<ShareOutlined color="primary" fontSize="small" />, tr('assetStatisticsTab.shares', 'Shares'), stats.shares)}</Grid>
                    </Grid>
                    <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 2 }}>
                        {tr('assetStatisticsTab.disclaimer', "Counts in-app views, downloads, and copied share links. CDN hot-link traffic isn't included.")}
                    </Typography>
                </Box>
            </Popover>
        </>
    );
}
