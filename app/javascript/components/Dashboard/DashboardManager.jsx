import React from 'react';
import { Box, CssBaseline, Typography, Grid, Paper } from '@mui/material';
import Sidebar from '../Sidebar';
import SearchResults from './SearchResults';
import { navigateTo } from "../../utils/globalutils";

export default function DashboardManager(props) {
    const searchTerm = props.searchTerm || "";

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            {/* Hardcode the active view so the Sidebar knows what to highlight */}
            <Sidebar activeView="Overview" onNavigate={(v) => navigateTo(v)} />

            <Box component="main" sx={{ flexGrow: 1 }}>
                {searchTerm ? (
                    <SearchResults searchTerm={searchTerm} rawAssets={props.assets} />
                ) : (
                    <Box sx={{ p: 3 }}>
                        <Typography variant="h4" sx={{ mb: 4, fontWeight: 700, color: '#121926' }}>
                            Command Center
                        </Typography>
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
                )}
            </Box>
        </Box>
    );
}