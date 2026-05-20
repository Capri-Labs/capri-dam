import React, { useState, useEffect } from 'react';
import { Box, CssBaseline, Toolbar, Typography, Grid, Paper, Chip } from '@mui/material';
import { InsertDriveFile, SearchOff } from '@mui/icons-material';
import Sidebar from './Sidebar';
import AssetExplorer from './AssetExplorer';
import WorkflowList from './Workflows/WorkflowList';
import WorkflowDesigner from './Workflows/WorkflowDesigner';

export default function Dashboard(props) {
    const [workflowAction, setWorkflowAction] = useState('list'); // 'list' or 'create'
    const [editingWorkflow, setEditingWorkflow] = useState(null);

    const getInitialAssets = () => {
        try {
            // Check if it exists and isn't just an empty string
            if (props.assets && props.assets.trim() !== "") {
                const parsed = JSON.parse(props.assets);
                return Array.isArray(parsed) ? parsed : [];
            }
        } catch (e) {
            console.error("Dashboard: Failed to parse assets JSON", e);
        }
        return []; // Fallback to empty array
    };

    // 1. Parse assets and search term from props
    const searchAssets = getInitialAssets();
    const searchTerm = props.searchTerm || "";

    // 2. If there's a search term, default the view to 'Search Results'
    const [activeView, setActiveView] = useState(searchTerm ? 'Search Results' : 'Overview');

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
            case 'Workflows':
                if (workflowAction === 'create' || workflowAction === 'edit') {
                    return (
                        <WorkflowDesigner
                            initialData={editingWorkflow}
                            onCancel={() => { setWorkflowAction('list'); setEditingWorkflow(null); }}
                        />
                    );
                }
                return (
                    <WorkflowList
                        workflows={props.workflows ? JSON.parse(props.workflows) : []}
                        onCreate={() => setWorkflowAction('create')}
                        onEdit={(wf) => { setEditingWorkflow(wf); setWorkflowAction('edit'); }}
                        onDelete={(id) => {/* call delete API */}}
                    />
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
            case 'Search Results':
                return (
                    <Box sx={{ p: 3 }}>
                        <Box sx={{ mb: 4, display: 'flex', alignItems: 'center', gap: 2 }}>
                            <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                                Search Results
                            </Typography>
                            <Chip label={`"${searchTerm}"`} color="primary" variant="outlined" />
                        </Box>

                        {searchAssets.length > 0 ? (
                            <Grid container spacing={2}>
                                {searchAssets.map((asset) => (
                                    <Grid item xs={12} sm={6} md={3} key={asset.id}>
                                        <Paper
                                            elevation={0}
                                            sx={{
                                                p: 2,
                                                border: '1px solid #e3e8ef',
                                                borderRadius: 2,
                                                display: 'flex',
                                                alignItems: 'center',
                                                gap: 2,
                                                transition: '0.2s',
                                                '&:hover': { borderColor: '#5e35b1', bgcolor: '#f8f5ff', cursor: 'pointer' }
                                            }}
                                        >
                                            <InsertDriveFile sx={{ color: '#5e35b1' }} />
                                            <Box sx={{ overflow: 'hidden' }}>
                                                <Typography variant="subtitle2" noWrap sx={{ fontWeight: 600 }}>
                                                    {asset.name}
                                                </Typography>
                                                <Typography variant="caption" color="textSecondary">
                                                    {asset.type} • {asset.size}
                                                </Typography>
                                            </Box>
                                        </Paper>
                                    </Grid>
                                ))}
                            </Grid>
                        ) : (
                            <Box sx={{ textAlign: 'center', py: 10 }}>
                                <SearchOff sx={{ fontSize: 60, color: '#cfd8dc', mb: 2 }} />
                                <Typography variant="h6" color="textSecondary">No assets found for "{searchTerm}"</Typography>
                                <Typography variant="body2" color="textSecondary">Try checking your spelling or using fewer keywords.</Typography>
                            </Box>
                        )}
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