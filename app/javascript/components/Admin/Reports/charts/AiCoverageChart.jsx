import React from 'react';
import { Card, CardContent, Typography, Box, LinearProgress, Chip, Skeleton } from '@mui/material';
import { AutoAwesome, CheckCircle } from '@mui/icons-material';

export default function AiCoverageChart({ data = {}, loading = false }) {
    const pct       = data?.coverage?.pct ?? 0;
    const covered   = (data?.coverage?.with_embedding ?? 0).toLocaleString();
    const uncovered = (data?.coverage?.without_embedding ?? 0).toLocaleString();

    const color = pct >= 90 ? '#16a34a' : pct >= 60 ? '#f59e0b' : '#ef4444';

    return (
        <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%' }}>
            <CardContent sx={{ p: 2.5 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
                    <AutoAwesome sx={{ color: '#8b5cf6', fontSize: 18 }} />
                    <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>AI Embedding Coverage</Typography>
                </Box>
                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 2 }}>
                    Vector embeddings for semantic search
                </Typography>

                {loading ? (
                    <Skeleton variant="rectangular" height={120} sx={{ borderRadius: 2 }} />
                ) : (
                    <>
                        {/* Big percentage */}
                        <Box sx={{ textAlign: 'center', my: 2 }}>
                            <Typography variant="h2" sx={{ fontWeight: 800, color, lineHeight: 1 }}>
                                {pct.toFixed(1)}%
                            </Typography>
                            <Typography variant="caption" color="textSecondary">of assets indexed</Typography>
                        </Box>

                        {/* Progress bar */}
                        <LinearProgress
                            variant="determinate"
                            value={pct}
                            sx={{
                                height: 10, borderRadius: 5, bgcolor: '#f1f5f9', mb: 2,
                                '& .MuiLinearProgress-bar': { borderRadius: 5, bgcolor: color }
                            }}
                        />

                        {/* Stats row */}
                        <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                            <Box sx={{ textAlign: 'center' }}>
                                <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#16a34a' }}>{covered}</Typography>
                                <Typography variant="caption" color="textSecondary">Indexed</Typography>
                            </Box>
                            <Box sx={{ textAlign: 'center' }}>
                                <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#ef4444' }}>{uncovered}</Typography>
                                <Typography variant="caption" color="textSecondary">Pending</Typography>
                            </Box>
                        </Box>

                        {pct < 80 && (
                            <Chip
                                size="small"
                                label="Run AI Enrichment to improve semantic search"
                                sx={{ mt: 2, bgcolor: '#fef3c7', color: '#92400e', fontSize: 10, height: 22, width: '100%' }}
                            />
                        )}
                        {pct >= 95 && (
                            <Chip
                                icon={<CheckCircle fontSize="small" />}
                                size="small"
                                label="Excellent coverage"
                                sx={{ mt: 2, bgcolor: '#dcfce7', color: '#15803d', fontSize: 10, height: 22, width: '100%' }}
                            />
                        )}
                    </>
                )}
            </CardContent>
        </Card>
    );
}

