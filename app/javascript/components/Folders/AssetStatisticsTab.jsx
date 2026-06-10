import React from 'react';
import { Box, Typography, Grid, Paper } from '@mui/material';
import { CloudDownloadOutlined, RemoveRedEyeOutlined, ShareOutlined } from '@mui/icons-material';

export default function AssetStatisticsTab({ asset }) {
    const statBlock = (icon, label, value) => (
        <Paper elevation={0} sx={{ p: 2, border: '1px solid #e2e8f0', borderRadius: 2, textAlign: 'center', bgcolor: '#f8fafc' }}>
            {icon}
            <Typography variant="h5" fontWeight="700" sx={{ mt: 1 }}>{value}</Typography>
            <Typography variant="caption" color="textSecondary">{label}</Typography>
        </Paper>
    );

    return (
        <Box>
            <Typography variant="subtitle1" fontWeight="700" sx={{ mb: 2 }}>Asset Statistics</Typography>
            <Grid container spacing={2}>
                <Grid item xs={4}>{statBlock(<CloudDownloadOutlined color="primary" />, "Downloads", "14")}</Grid>
                <Grid item xs={4}>{statBlock(<RemoveRedEyeOutlined color="primary" />, "CDN Views", "1,204")}</Grid>
                <Grid item xs={4}>{statBlock(<ShareOutlined color="primary" />, "Shares", "3")}</Grid>
            </Grid>
        </Box>
    );
}