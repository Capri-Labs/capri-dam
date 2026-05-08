import React, { useState } from 'react';
import { Box, CssBaseline, Toolbar, Typography, Grid, Paper } from '@mui/material';
import Sidebar from './Sidebar';
import AssetExplorer from './AssetExplorer';

export default function Dashboard() {
    // Default to 'Overview' (the original Command Center)
    const [activeView, setActiveView] = useState('Overview');

    const renderView = () => {
        switch (activeView) {
            case 'Overview':
                return (
                    <Box sx={{ p: 3 }}>
                        <Typography variant="h4" sx={{ mb: 4, fontWeight: 700, color: '#121926' }}>Command Center</Typography>
                        <Grid container spacing={3}>
                            {[
                                { label: 'Total Assets', val: '1,284', color: '#5e35b1' },
                                { label: 'Storage Used', val: '42.5 GB', color: '#00c853' },
                                { label: 'Pending Review', val: '12', color: '#ffc107' }
                            ].map((stat) => (
                                <Grid key={stat.label} item xs={12} md={4}>
                                    <Paper elevation={0} sx={{ p: 3, textAlign: 'center', border: '1px solid #e3e8ef', borderRadius: 3 }}>
                                        <Typography color="textSecondary" variant="subtitle2" gutterBottom>{stat.label}</Typography>
                                        <Typography variant="h4" sx={{ color: stat.color, fontWeight: 700 }}>{stat.val}</Typography>
                                    </Paper>
                                </Grid>
                            ))}
                        </Grid>
                    </Box>
                );
            case 'All Assets':
                return (
                    <Box>
                        <Box sx={{ px: 3, pt: 3 }}>
                            <Typography variant="h4" sx={{ mb: 1, fontWeight: 700 }}>Library</Typography>
                        </Box>
                        <AssetExplorer />
                    </Box>
                );
            default:
                return (
                    <Box sx={{ p: 10, textAlign: 'center' }}>
                        <Typography variant="h5" color="textSecondary">{activeView} Module Coming Soon</Typography>
                    </Box>
                );
        }
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />

            {/* Our Global Sidebar */}
            <Sidebar activeView={activeView} onNavigate={setActiveView} />

            <Box component="main" sx={{ flexGrow: 1 }}>
                <Toolbar />
                {renderView()}
            </Box>
        </Box>
    );
}