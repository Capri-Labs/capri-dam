import React, { useState } from 'react';
import {
    Box, Drawer, List, ListItem, ListItemIcon, ListItemText,
    Typography, AppBar, Toolbar, CssBaseline, Divider, Avatar
} from '@mui/material';
import { FolderCopy, Assignment, Settings, Notifications } from '@mui/icons-material';

// Import your existing components
import AssetExplorer from '../components/Folders/AssetExplorer';
import WorkflowDashboard from './WorkflowDashboard';

const drawerWidth = 260;

export default function App() {
    // Determine which main page to show
    const [currentView, setCurrentView] = useState('explorer'); // 'explorer' or 'workflows'

    // Pass this down so the dashboard can force the explorer to open a specific file
    const [targetAssetId, setTargetAssetId] = useState(null);

    // The hand-off function
    const navigateToAsset = (assetId) => {
        setTargetAssetId(assetId);
        setCurrentView('explorer');
    };

    return (
        <Box sx={{ display: 'flex', height: '100vh', bgcolor: '#f8fafc' }}>
            <CssBaseline />

            {/* TOP NAVIGATION BAR */}
            <AppBar position="fixed" sx={{ width: `calc(100% - ${drawerWidth}px)`, ml: `${drawerWidth}px`, bgcolor: '#ffffff', color: '#1e293b', boxShadow: '0 1px 3px 0 rgb(0 0 0 / 0.1)' }}>
                <Toolbar sx={{ justifyContent: 'space-between' }}>
                    <Typography variant="h6" noWrap component="div" sx={{ fontWeight: 700 }}>
                        {currentView === 'explorer' ? 'Digital Asset Manager' : 'Workflow Operations'}
                    </Typography>

                    {/* User Profile & Notification Stub */}
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                        {/* We will wire up the badge counter here in Step 4! */}
                        <Notifications sx={{ color: '#64748b', cursor: 'pointer' }} />
                        <Avatar sx={{ width: 32, height: 32, bgcolor: '#4f46e5', fontSize: '0.875rem' }}>A</Avatar>
                    </Box>
                </Toolbar>
            </AppBar>

            {/* SIDEBAR MENU */}
            <Drawer
                sx={{
                    width: drawerWidth,
                    flexShrink: 0,
                    '& .MuiDrawer-paper': { width: drawerWidth, boxSizing: 'border-box', bgcolor: '#0f172a', color: '#f8fafc' },
                }}
                variant="permanent"
                anchor="left"
            >
                <Toolbar>
                    <Typography variant="h6" sx={{ fontWeight: 800, letterSpacing: '1px' }}>
                        HEADLESS DAM
                    </Typography>
                </Toolbar>
                <Divider sx={{ borderColor: 'rgba(255,255,255,0.1)' }} />

                <List sx={{ px: 2, pt: 2 }}>
                    <ListItem
                        button
                        onClick={() => { setCurrentView('explorer'); setTargetAssetId(null); }}
                        sx={{
                            borderRadius: '8px', mb: 1,
                            bgcolor: currentView === 'explorer' ? 'rgba(255,255,255,0.1)' : 'transparent',
                            '&:hover': { bgcolor: 'rgba(255,255,255,0.15)' }
                        }}
                    >
                        <ListItemIcon sx={{ color: currentView === 'explorer' ? '#38bdf8' : '#94a3b8', minWidth: '40px' }}>
                            <FolderCopy />
                        </ListItemIcon>
                        <ListItemText primary="Asset Explorer" slotProps={{ primary: { fontWeight: currentView === 'explorer' ? 600 : 400 } }} />
                    </ListItem>

                    <ListItem
                        button
                        onClick={() => setCurrentView('workflows')}
                        sx={{
                            borderRadius: '8px', mb: 1,
                            bgcolor: currentView === 'workflows' ? 'rgba(255,255,255,0.1)' : 'transparent',
                            '&:hover': { bgcolor: 'rgba(255,255,255,0.15)' }
                        }}
                    >
                        <ListItemIcon sx={{ color: currentView === 'workflows' ? '#38bdf8' : '#94a3b8', minWidth: '40px' }}>
                            <Assignment />
                        </ListItemIcon>
                        <ListItemText primary="Workflows" slotProps={{ primary: { fontWeight: currentView === 'workflows' ? 600 : 400 } }} />
                    </ListItem>
                </List>

                <Box sx={{ flexGrow: 1 }} />

                <List sx={{ px: 2, pb: 2 }}>
                    <ListItem button sx={{ borderRadius: '8px', '&:hover': { bgcolor: 'rgba(255,255,255,0.1)' } }}>
                        <ListItemIcon sx={{ color: '#94a3b8', minWidth: '40px' }}><Settings /></ListItemIcon>
                        <ListItemText primary="Settings" />
                    </ListItem>
                </List>
            </Drawer>

            {/* MAIN CONTENT AREA */}
            <Box component="main" sx={{ flexGrow: 1, bgcolor: '#f8fafc', p: 0, pt: 8 }}>
                {currentView === 'explorer' && (
                    <AssetExplorer initialTargetAssetId={targetAssetId} />
                )}
                {currentView === 'workflows' && (
                    <WorkflowDashboard onNavigateToAsset={navigateToAsset} />
                )}
            </Box>
        </Box>
    );
}
