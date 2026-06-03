import React, { useState, useEffect } from 'react';
import {
    Box, Grid, Card, CardContent, Typography, LinearProgress,
    Button, Chip, Table, TableBody, TableCell, TableContainer,
    TableHead, TableRow, Paper, Stack, IconButton
} from '@mui/material';
import {
    Storage, TrendingDown, Visibility, PlayArrow
} from '@mui/icons-material';
import BatchReviewWorkspace from './BatchReviewWorkspace';

export default function IngestionDashboard() {
    const [batches, setBatches] = useState([]);
    const [selectedBatchId, setSelectedBatchId] = useState(null);
    const [metrics, setMetrics] = useState({ totalSavedGb: 0, networkCostReduction: 0 });

    useEffect(() => {
        // Simulating polling API endpoint: GET /api/v1/ingestion_batches
        const mockBatches = [
            {
                id: "b1-uuid",
                name: "Legacy AEM Asset Archive",
                source_type: "legacy_s3",
                status: "review_needed", // State matching our Rails enum
                total_count: 1420,
                processed_count: 1420,
                duplicate_count: 312,
                error_count: 4,
                created_at: "2026-06-01"
            },
            {
                id: "b2-uuid",
                name: "Global Marketing Sharepoint Sync",
                source_type: "api_connector",
                status: "transforming",
                total_count: 5000,
                processed_count: 2150,
                duplicate_count: 410,
                error_count: 0,
                created_at: "2026-06-03"
            }
        ];
        setBatches(mockBatches);
        // Calculate TDM cost metrics (assuming average 5MB per duplicate asset asset)
        const totalSavedBytes = (312 + 410) * 5 * 1024 * 1024;
        const gbSaved = (totalSavedBytes / (1024 * 1024 * 1024)).toFixed(2);
        setMetrics({ totalSavedGb: gbSaved, networkCostReduction: (gbSaved * 0.08).toFixed(2) });
    }, [selectedBatchId]);

    const getStatusChip = (status) => {
        const config = {
            initializing: { label: 'Initializing', color: 'default' },
            extracting: { label: 'Extracting Files', color: 'info' },
            transforming: { label: 'AI Transforming', color: 'secondary' },
            review_needed: { label: 'Review Needed', color: 'warning' },
            committed: { label: 'Committed to DAM', color: 'success' },
            failed: { label: 'Pipeline Failed', color: 'error' }
        };
        const current = config[status] || config.initializing;
        return <Chip label={current.label} color={current.color} size="small" variant="outlined" />;
    };

    if (selectedBatchId) {
        return <BatchReviewWorkspace batchId={selectedBatchId} onBack={() => setSelectedBatchId(null)} />;
    }

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', mb: 1 }}>
                Batch Ingestion Engine
            </Typography>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 4 }}>
                Monitor, transform, and optimize legacy enterprise assets migrating into the Headless DAM cloud infrastructure.
            </Typography>

            {/* High-Value TDM Metrics Panel */}
            <Grid container spacing={3} sx={{ mb: 4 }}>
                <Grid item xs={12} sm={6} md={3}>
                    <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3 }}>
                        <CardContent>
                            <Stack direction="row" justifyContent="space-between" alignItems="center">
                                <Box>
                                    <Typography color="textSecondary" variant="caption" sx={{ fontWeight: 600 }}>
                                        TECHNICAL DEBT PREVENTED
                                    </Typography>
                                    <Typography variant="h4" sx={{ fontWeight: 700, mt: 1, color: '#137333' }}>
                                        {metrics.totalSavedGb} GB
                                    </Typography>
                                </Box>
                                <Storage sx={{ color: '#137333', fontSize: 32 }} />
                            </Stack>
                            <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1 }}>
                                Redundant duplicate uploads blocked at edge.
                            </Typography>
                        </CardContent>
                    </Card>
                </Grid>
                <Grid item xs={12} sm={6} md={3}>
                    <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3 }}>
                        <CardContent>
                            <Stack direction="row" justifyContent="space-between" alignItems="center">
                                <Box>
                                    <Typography color="textSecondary" variant="caption" sx={{ fontWeight: 600 }}>
                                        INFRASTRUCTURE SAVINGS
                                    </Typography>
                                    <Typography variant="h4" sx={{ fontWeight: 700, mt: 1, color: '#121926' }}>
                                        ${metrics.networkCostReduction} / mo
                                    </Typography>
                                </Box>
                                <TrendingDown sx={{ color: '#5e35b1', fontSize: 32 }} />
                            </Stack>
                            <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1 }}>
                                Saved in cloud egress and storage overhead.
                            </Typography>
                        </CardContent>
                    </Card>
                </Grid>
            </Grid>

            {/* active batches table */}
            <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3 }}>
                <Table>
                    <TableHead sx={{ bgcolor: '#f8fafc' }}>
                        <TableRow>
                            <TableCell sx={{ fontWeight: 600 }}>Batch Name</TableCell>
                            <TableCell sx={{ fontWeight: 600 }}>Source</TableCell>
                            <TableCell sx={{ fontWeight: 600 }}>Pipeline Status</TableCell>
                            <TableCell sx={{ fontWeight: 600 }}>Progress</TableCell>
                            <TableCell sx={{ fontWeight: 600 }} align="right">Actions</TableCell>
                        </TableRow>
                    </TableHead>
                    <TableBody>
                        {batches.map((batch) => {
                            const progress = (batch.processed_count / batch.total_count) * 100;
                            return (
                                <TableRow key={batch.id} hover>
                                    <TableCell>
                                        <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>{batch.name}</Typography>
                                        <Typography variant="caption" color="textSecondary">{batch.id}</Typography>
                                    </TableCell>
                                    <TableCell>
                                        <Chip label={batch.source_type.toUpperCase()} size="small" />
                                    </TableCell>
                                    <TableCell>{getStatusChip(batch.status)}</TableCell>
                                    <TableCell sx={{ width: '25%' }}>
                                        <Stack direction="row" alignItems="center" spacing={2}>
                                            <Box sx={{ width: '100%' }}>
                                                <LinearProgress variant="determinate" value={progress} color={batch.status === 'transforming' ? 'secondary' : 'primary'} />
                                            </Box>
                                            <Typography variant="caption" color="textSecondary">
                                                {batch.processed_count}/{batch.total_count}
                                            </Typography>
                                        </Stack>
                                    </TableCell>
                                    <TableCell align="right">
                                        {batch.status === 'review_needed' ? (
                                            <Button
                                                variant="contained"
                                                size="small"
                                                startIcon={<Visibility />}
                                                onClick={() => setSelectedBatchId(batch.id)}
                                                sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                                            >
                                                Audit Batch
                                            </Button>
                                        ) : (
                                            <IconButton disabled><PlayArrow /></IconButton>
                                        )}
                                    </TableCell>
                                </TableRow>
                            );
                        })}
                    </TableBody>
                </Table>
            </TableContainer>
        </Box>
    );
}