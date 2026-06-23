import React from 'react';
import { Card, CardContent, Typography, Box, Skeleton, LinearProgress } from '@mui/material';

export default function TopFoldersChart({ data = [], loading = false }) {
    const maxCount = data.length > 0 ? Math.max(...data.map(d => d.count)) : 1;

    return (
        <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%' }}>
            <CardContent sx={{ p: 2.5 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 0.5 }}>Top Folders by Assets</Typography>
                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 2 }}>
                    Folders with the most active assets
                </Typography>
                {loading ? (
                    Array.from({ length: 6 }).map((_, i) => (
                        <Skeleton key={i} variant="text" height={32} sx={{ mb: 1 }} />
                    ))
                ) : data.length === 0 ? (
                    <Typography color="textSecondary" variant="body2" sx={{ mt: 2 }}>No folder data</Typography>
                ) : (
                    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
                        {data.slice(0, 8).map((folder, i) => (
                            <Box key={i}>
                                <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
                                    <Typography variant="caption" sx={{ fontWeight: 600, color: '#1e293b', maxWidth: '70%', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                                        {folder.name || 'Root'}
                                    </Typography>
                                    <Typography variant="caption" sx={{ fontWeight: 700, color: '#5e35b1' }}>
                                        {folder.count.toLocaleString()}
                                    </Typography>
                                </Box>
                                <LinearProgress
                                    variant="determinate"
                                    value={(folder.count / maxCount) * 100}
                                    sx={{
                                        height: 6, borderRadius: 3, bgcolor: '#f1f5f9',
                                        '& .MuiLinearProgress-bar': { borderRadius: 3, bgcolor: i === 0 ? '#5e35b1' : '#0ea5e9' }
                                    }}
                                />
                            </Box>
                        ))}
                    </Box>
                )}
            </CardContent>
        </Card>
    );
}

