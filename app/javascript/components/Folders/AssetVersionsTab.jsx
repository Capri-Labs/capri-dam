import React from 'react';
import { Box, Typography, Paper, List, ListItem, ListItemText, Chip } from '@mui/material';

export default function AssetVersionsTab({ asset }) {
    return (
        <Box>
            <Typography variant="subtitle1" fontWeight="700" sx={{ mb: 2 }}>Version History</Typography>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                Tracking non-destructive edits and physical file replacements.
            </Typography>

            <List sx={{ p: 0 }}>
                {/* Mocking the current version */}
                <Paper elevation={0} sx={{ p: 2, mb: 1, border: '1px solid #4f46e5', bgcolor: '#eef2ff', borderRadius: 2 }}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                        <Box>
                            <Typography variant="body2" fontWeight="700">v2.0 (Current)</Typography>
                            <Typography variant="caption" color="textSecondary">Edited by You • Just now</Typography>
                        </Box>
                        <Chip label="Active" size="small" sx={{ bgcolor: '#4f46e5', color: '#fff' }} />
                    </Box>
                </Paper>

                <Paper elevation={0} sx={{ p: 2, mb: 1, border: '1px solid #e2e8f0', bgcolor: '#f8fafc', borderRadius: 2 }}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                        <Box>
                            <Typography variant="body2" fontWeight="700">v1.0 (Original)</Typography>
                            <Typography variant="caption" color="textSecondary">Uploaded by System • {new Date(asset.created_at).toLocaleDateString()}</Typography>
                        </Box>
                        <Typography variant="caption" color="primary" sx={{ cursor: 'pointer', fontWeight: 600 }}>Restore</Typography>
                    </Box>
                </Paper>
            </List>
        </Box>
    );
}