import React, { useState } from 'react';
import {
    Box, Drawer, Toolbar, List, Typography, Divider,
    ListItem, ListItemButton, ListItemIcon, ListItemText,
    Grid, Paper
} from '@mui/material';

import {
    Dashboard as DashIcon,
    CloudUpload,
    PhotoLibrary,
    Settings
} from '@mui/icons-material';

// Import our new components
import AssetExplorer from './AssetExplorer';
import { CssBaseline } from '@mui/material';

const drawerWidth = 240;

export default function Dashboard() {
    // State to switch between the Overview (Command Center) and the Explorer
    const [activeView, setActiveView] = useState('Dashboard');

    return (
        <Box sx={{ display: 'flex' }}>
            <CssBaseline />
            <Drawer
                variant="permanent"
                sx={{
                    width: drawerWidth,
                    flexShrink: 0,
                    [`& .MuiDrawer-paper`]: { width: drawerWidth, boxSizing: 'border-box' },
                }}
            >
                <Toolbar />
                <Box sx={{ overflow: 'auto' }}>
                    <List>
                        {/* Dashboard Link */}
                        <ListItem disablePadding>
                            <ListItemButton
                                selected={activeView === 'Dashboard'}
                                onClick={() => setActiveView('Dashboard')}
                            >
                                <ListItemIcon><DashIcon /></ListItemIcon>
                                <ListItemText primary="Dashboard" />
                            </ListItemButton>
                        </ListItem>

                        {/* All Assets (Explorer) Link */}
                        <ListItem disablePadding>
                            <ListItemButton
                                selected={activeView === 'All Assets'}
                                onClick={() => setActiveView('All Assets')}
                            >
                                <ListItemIcon><PhotoLibrary /></ListItemIcon>
                                <ListItemText primary="All Assets" />
                            </ListItemButton>
                        </ListItem>

                    </List>

                    <Divider />

                    <List>
                        <ListItem disablePadding>
                            <ListItemButton
                                component="a"
                                href="/settings"
                                sx={{ '&:hover': { bgcolor: 'rgba(25, 118, 210, 0.08)' } }}
                            >
                                <ListItemIcon><Settings color="primary" /></ListItemIcon>
                                <ListItemText primary="Settings & Profile" sx={{ color: 'primary.main', fontWeight: 'bold' }} />
                            </ListItemButton>
                        </ListItem>
                    </List>
                </Box>
            </Drawer>

            <Box component="main" sx={{ flexGrow: 1, bgcolor: '#f5f6fa', minHeight: '100vh' }}>
                <Toolbar />

                {activeView === 'Dashboard' ? (
                    /* --- VIEW 1: COMMAND CENTER (OVERVIEW) --- */
                    <Box sx={{ p: 3 }}>
                        <Typography variant="h4" sx={{ mb: 4, fontWeight: 'bold' }}>Command Center</Typography>

                        <Grid container spacing={3} sx={{ mb: 4 }}>
                            {[
                                { label: 'Total Assets', val: '1,284', color: '#556cd6' },
                                { label: 'Storage Used', val: '42.5 GB', color: '#19857b' },
                                { label: 'Pending Review', val: '12', color: '#ff9f43' }
                            ].map((stat) => (
                                <Grid key={stat.label} item xs={12} md={4}>
                                    <Paper sx={{ p: 3, textAlign: 'center', borderTop: `4px solid ${stat.color}` }}>
                                        <Typography color="textSecondary" gutterBottom>{stat.label}</Typography>
                                        <Typography variant="h3">{stat.val}</Typography>
                                    </Paper>
                                </Grid>
                            ))}
                        </Grid>

                        <Typography variant="h6" sx={{ mb: 2 }}>Recent Assets</Typography>
                        {/* We could put a "Mini" version of the explorer here later */}
                        <Paper sx={{ p: 2, textAlign: 'center', color: 'text.secondary' }}>
                            Overview metrics and charts will go here.
                        </Paper>
                    </Box>
                ) : (
                    /* --- VIEW 2: ASSET EXPLORER (HIERARCHY) --- */
                    <Box>
                        <Box sx={{ px: 3, pt: 3 }}>
                            <Typography variant="h4" sx={{ mb: 1, fontWeight: 'bold' }}>Library</Typography>
                            <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
                                Manage your hierarchical folders and asset metadata.
                            </Typography>
                        </Box>
                        <AssetExplorer />
                    </Box>
                )}
            </Box>
        </Box>
    );
}