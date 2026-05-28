import React from 'react';
import { Box, Typography, Paper, Stack } from '@mui/material';
import { Person, IntegrationInstructions, Notifications } from '@mui/icons-material';

export default function NodePalette() {
    // Standard HTML5 drag event to tell the canvas WHAT we are dropping
    const onDragStart = (event, nodeType) => {
        event.dataTransfer.setData('application/reactflow', nodeType);
        event.dataTransfer.effectAllowed = 'move';
    };

    return (
        <Box sx={{ width: 220, p: 2, borderRight: '1px solid #e2e8f0', bgcolor: '#f8fafc' }}>
            <Typography variant="overline" fontWeight="bold" color="text.secondary" sx={{ mb: 2, display: 'block' }}>
                Toolbox
            </Typography>

            <Stack spacing={2}>
                <Paper
                    elevation={0}
                    onDragStart={(event) => onDragStart(event, 'approvalNode')} draggable
                    sx={{ p: 1.5, border: '1px solid #cbd5e1', cursor: 'grab', display: 'flex', alignItems: 'center', gap: 1, '&:hover': { borderColor: '#5e35b1', bgcolor: '#f3e8ff' } }}
                >
                    <Person color="primary" fontSize="small" />
                    <Typography variant="body2" fontWeight="bold">Approval</Typography>
                </Paper>

                <Paper
                    elevation={0}
                    onDragStart={(event) => onDragStart(event, 'webhookNode')} draggable
                    sx={{ p: 1.5, border: '1px solid #cbd5e1', cursor: 'grab', display: 'flex', alignItems: 'center', gap: 1, '&:hover': { borderColor: '#0ea5e9', bgcolor: '#e0f2fe' } }}
                >
                    <IntegrationInstructions sx={{ color: '#0ea5e9' }} fontSize="small" />
                    <Typography variant="body2" fontWeight="bold">Webhook API</Typography>
                </Paper>

                <Paper
                    elevation={0}
                    onDragStart={(event) => onDragStart(event, 'notificationNode')} draggable
                    sx={{ p: 1.5, border: '1px solid #cbd5e1', cursor: 'grab', display: 'flex', alignItems: 'center', gap: 1, '&:hover': { borderColor: '#f59e0b', bgcolor: '#fef3c7' } }}
                >
                    <Notifications sx={{ color: '#f59e0b' }} fontSize="small" />
                    <Typography variant="body2" fontWeight="bold">Notification</Typography>
                </Paper>
            </Stack>
        </Box>
    );
}