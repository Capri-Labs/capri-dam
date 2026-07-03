import React from 'react';
import { Box, Typography, Grid, Paper } from '@mui/material';
import { CloudDownloadOutlined, RemoveRedEyeOutlined, ShareOutlined } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

export default function AssetStatisticsTab({ asset }) {
    const { t } = useTranslation();
    const tr = (key, defaultValue) => {
        const value = t(key, { defaultValue });
        return value === key ? defaultValue : value;
    };
    const statBlock = (icon, label, value) => (
        <Paper elevation={0} sx={{ p: 2, border: '1px solid #e2e8f0', borderRadius: 2, textAlign: 'center', bgcolor: '#f8fafc' }}>
            {icon}
            <Typography variant="h5" fontWeight="700" sx={{ mt: 1 }}>{value}</Typography>
            <Typography variant="caption" color="textSecondary">{label}</Typography>
        </Paper>
    );

    return (
        <Box>
            <Typography variant="subtitle1" fontWeight="700" sx={{ mb: 2 }}>{tr('assetStatisticsTab.title', 'Asset Statistics')}</Typography>
            <Grid container spacing={2}>
                <Grid size={4}>{statBlock(<CloudDownloadOutlined color="primary" />, tr('assetStatisticsTab.downloads', 'Downloads'), "14")}</Grid>
                <Grid size={4}>{statBlock(<RemoveRedEyeOutlined color="primary" />, tr('assetStatisticsTab.cdnViews', 'CDN Views'), "1,204")}</Grid>
                <Grid size={4}>{statBlock(<ShareOutlined color="primary" />, tr('assetStatisticsTab.shares', 'Shares'), "3")}</Grid>
            </Grid>
        </Box>
    );
}