import React from 'react';
import { Dialog, DialogTitle, DialogContent, Typography, Box } from '@mui/material';

export default function BottleneckReport({ open, onClose, stats, totalActive }) {
    return (
        <Dialog open={open} onClose={onClose} maxWidth="xs" fullWidth>
            <DialogTitle>Workflow Bottlenecks</DialogTitle>
            <DialogContent dividers>
                <Typography variant="body2" sx={{ mb: 3 }}>
                    Currently identifying {totalActive} active assets. High-risk stages are listed below:
                </Typography>
                {stats.map(([step, count]) => (
                    <Box key={step} sx={{ mb: 3 }}>
                        <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}>
                            <Typography variant="subtitle2">{step}</Typography>
                            <Typography variant="caption" fontWeight="bold">{count} assets</Typography>
                        </Box>
                        <Box sx={{ bgcolor: '#e2e8f0', height: 10, borderRadius: 5 }}>
                            <Box sx={{ width: `${(count/totalActive)*100}%`, bgcolor: '#ef4444', height: 10, borderRadius: 5 }} />
                        </Box>
                    </Box>
                ))}
            </DialogContent>
        </Dialog>
    );
}