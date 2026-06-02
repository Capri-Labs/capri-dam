import React, { useState } from 'react';
import { Box, CssBaseline, Typography, Grid, Paper, Chip } from '@mui/material';
import { ContentCopy } from '@mui/icons-material';
import Sidebar from '../Sidebar';
import { navigateTo } from "../../utils/globalutils";
import DuplicateResolutionModal from './DuplicateResolutionModal';
import { useNotify } from '../../context/NotificationContext';

// MOCK DATA: Simulating what the AI backend will eventually return
const MOCK_GROUPS = [
    {
        id: 'group_1',
        status: 'pending',
        assets: [
            { id: 1, name: 'Neon Photoshoot 03.jpg', upload_date: 'August 21, 2026', url: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400' },
            { id: 2, name: 'hazel-m-vincent-3276.jpg', upload_date: 'October 12, 2026', url: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400' },
            { id: 3, name: 'photo-edit-03.jpg', upload_date: 'August 23, 2026', url: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400' }
        ]
    }
];

export default function DuplicateManager() {
    const notify = useNotify();
    const [groups, setGroups] = useState(MOCK_GROUPS);
    const [selectedGroup, setSelectedGroup] = useState(null);

    const handleResolve = (groupId, action, assetIdsToDelete) => {
        if (action === 'accept') {
            notify("Collection accepted. No files were deleted.", "info");
        } else if (action === 'delete') {
            notify(`Successfully moved ${assetIdsToDelete.length} asset(s) to the bin.`, "success");
            // Here you would fire the DELETE api calls to your backend
        }

        // Remove the resolved group from the UI
        setGroups(prev => prev.filter(g => g.id !== groupId));
        setSelectedGroup(null);
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />

            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                <Box sx={{ mb: 4 }}>
                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#1e293b' }}>
                        Duplicate Manager
                    </Typography>
                    <Typography variant="body2" color="textSecondary">
                        Review AI-detected duplicate assets to optimize storage space.
                    </Typography>
                </Box>

                <Grid container spacing={3}>
                    {groups.length === 0 ? (
                        <Grid item xs={12}>
                            <Typography variant="body1" color="textSecondary">
                                No duplicate collections found. Your storage is optimized!
                            </Typography>
                        </Grid>
                    ) : (
                        groups.map(group => (
                            <Grid item xs={12} sm={6} md={4} lg={3} key={group.id}>
                                <Paper
                                    elevation={0}
                                    onClick={() => setSelectedGroup(group)}
                                    sx={{
                                        p: 3, borderRadius: 3, border: '1px solid #e2e8f0',
                                        cursor: 'pointer', transition: '0.2s',
                                        '&:hover': { borderColor: '#3b82f6', boxShadow: '0 4px 12px rgba(0,0,0,0.05)' }
                                    }}
                                >
                                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 2 }}>
                                        <Box sx={{ bgcolor: '#eff6ff', p: 1.5, borderRadius: 2, display: 'flex' }}>
                                            <ContentCopy sx={{ color: '#3b82f6' }} />
                                        </Box>
                                        <Box>
                                            <Typography variant="subtitle1" fontWeight="600">Potential Match</Typography>
                                            <Typography variant="body2" color="textSecondary">{group.assets.length} identical files</Typography>
                                        </Box>
                                    </Box>
                                    <Box sx={{ display: 'flex', gap: 1 }}>
                                        {group.assets.slice(0, 3).map(a => (
                                            <Box
                                                key={a.id}
                                                component="img"
                                                src={a.url}
                                                sx={{ width: 40, height: 40, borderRadius: 1, objectFit: 'cover' }}
                                            />
                                        ))}
                                    </Box>
                                </Paper>
                            </Grid>
                        ))
                    )}
                </Grid>
            </Box>

            <DuplicateResolutionModal
                open={Boolean(selectedGroup)}
                duplicateGroup={selectedGroup}
                onClose={() => setSelectedGroup(null)}
                onResolve={handleResolve}
            />
        </Box>
    );
}