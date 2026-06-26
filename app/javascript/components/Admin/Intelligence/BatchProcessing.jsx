import React, { useState, useEffect } from 'react';
import {
    Box, Typography, Grid, Paper, Button, Stack,
    TextField, MenuItem, LinearProgress, Table, TableBody,
    TableCell, TableContainer, TableHead, TableRow, Chip
} from '@mui/material';
import {
    QueryStats, FilterAlt, RocketLaunch, CheckCircleOutlined,
    ErrorOutlined, PauseCircleOutlined
} from '@mui/icons-material';

export default function BatchProcessing() {
    const [isProcessing, setIsProcessing] = useState(false);
    const [progress, setProgress] = useState(0);
    const [batchResults, setBatchResults] = useState([]);

    // Form State
    const [targetDataset, setTargetDataset] = useState('missing_tags');
    const [extractionSchema, setExtractionSchema] = useState('seo_enrichment');
    const [batchSize, setBatchSize] = useState(500);

    const handleStartBatch = () => {
        setIsProcessing(true);
        setProgress(0);
        setBatchResults([]);

        // Simulating a real-time WebSocket or Server-Sent Events (SSE) stream
        // from LangChain's Runnable.batch() execution.
        let currentProgress = 0;
        const interval = setInterval(() => {
            currentProgress += Math.floor(Math.random() * 5) + 2;

            if (currentProgress >= 100) {
                currentProgress = 100;
                clearInterval(interval);
                setIsProcessing(false);
            }

            setProgress(currentProgress);

            // Populate mock results as they stream in
            if (currentProgress % 15 === 0 && currentProgress < 100) {
                setBatchResults(prev => [
                    { id: Date.now(), filename: `legacy_asset_${currentProgress}.jpg`, status: 'Success', tags_added: 4 },
                    ...prev
                ]);
            }
        }, 800);
    };

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', mb: 1, display: 'flex', alignItems: 'center' }}>
                <QueryStats sx={{ mr: 1.5, color: '#8b5cf6', fontSize: 32 }} />
                Metadata Extraction (Batch)
            </Typography>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 4 }}>
                Target legacy database segments and execute LangChain parallel extraction chains to cure structural debt.
            </Typography>

            <Grid container spacing={4}>
                {/* Configuration Panel */}
                <Grid size={{ xs: 12, md: 4 }}>
                    <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 3 }}>
                        <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 3 }}>Batch Configuration</Typography>

                        <Stack spacing={3}>
                            <TextField
                                select
                                fullWidth
                                label="Target Dataset"
                                value={targetDataset}
                                onChange={(e) => setTargetDataset(e.target.value)}
                                disabled={isProcessing}
                            >
                                <MenuItem value="missing_tags">Assets with 0 Semantic Tags</MenuItem>
                                <MenuItem value="null_campaign">Assets with Null Campaign ID</MenuItem>
                                <MenuItem value="legacy_migration_2022">Collection: Legacy Migration 2022</MenuItem>
                            </TextField>

                            <TextField
                                select
                                fullWidth
                                label="Extraction Schema (LangChain Tools)"
                                value={extractionSchema}
                                onChange={(e) => setExtractionSchema(e.target.value)}
                                disabled={isProcessing}
                            >
                                <MenuItem value="seo_enrichment">Basic SEO Tags (Fast / Low Cost)</MenuItem>
                                <MenuItem value="deep_visual">Deep Visual Context (Slower / High Cost)</MenuItem>
                                <MenuItem value="compliance_check">Copyright Policy Check</MenuItem>
                            </TextField>

                            <TextField
                                type="number"
                                fullWidth
                                label="Concurrency / Batch Size"
                                value={batchSize}
                                onChange={(e) => setBatchSize(e.target.value)}
                                disabled={isProcessing}
                                helperText="Number of IO-bound runnables to execute in parallel."
                            />

                            <Button
                                variant="contained"
                                size="large"
                                startIcon={isProcessing ? <PauseCircleOutlined /> : <RocketLaunch />}
                                onClick={handleStartBatch}
                                disabled={isProcessing}
                                sx={{ bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' }, mt: 2 }}
                            >
                                {isProcessing ? 'Processing Batch...' : 'Execute Batch Process'}
                            </Button>
                        </Stack>
                    </Paper>
                </Grid>

                {/* Execution Stream Panel */}
                <Grid size={{ xs: 12, md: 8 }}>
                    <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 3, height: '100%', display: 'flex', flexDirection: 'column' }}>
                        <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 2 }}>
                            <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>Execution Stream</Typography>
                            {isProcessing && <Chip label={`${progress}% Complete`} color="secondary" size="small" />}
                        </Stack>

                        <Box sx={{ mb: 3 }}>
                            <LinearProgress
                                variant="determinate"
                                value={progress}
                                sx={{ height: 8, borderRadius: 4, bgcolor: '#f1f5f9', '& .MuiLinearProgress-bar': { bgcolor: '#8b5cf6' } }}
                            />
                        </Box>

                        <TableContainer sx={{ flexGrow: 1, border: '1px solid #f1f5f9', borderRadius: 2 }}>
                            <Table size="small" stickyHeader>
                                <TableHead>
                                    <TableRow>
                                        <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }}>File Target</TableCell>
                                        <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }}>Status</TableCell>
                                        <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }} align="right">Entities Extracted</TableCell>
                                    </TableRow>
                                </TableHead>
                                <TableBody>
                                    {batchResults.length === 0 && !isProcessing ? (
                                        <TableRow>
                                            <TableCell colSpan={3} align="center" sx={{ py: 4, color: '#94a3b8' }}>
                                                <FilterAlt sx={{ fontSize: 40, opacity: 0.5, mb: 1, display: 'block', mx: 'auto' }} />
                                                Ready to execute metadata extraction batch.
                                            </TableCell>
                                        </TableRow>
                                    ) : (
                                        batchResults.map((row) => (
                                            <TableRow key={row.id}>
                                                <TableCell sx={{ fontFamily: 'monospace', fontSize: '0.85rem' }}>{row.filename}</TableCell>
                                                <TableCell>
                                                    <Chip icon={<CheckCircleOutlined />} label={row.status} size="small" color="success" variant="outlined" sx={{ height: 20 }} />
                                                </TableCell>
                                                <TableCell align="right">
                                                    <Typography variant="body2" sx={{ fontWeight: 600, color: '#8b5cf6' }}>+{row.tags_added} keys</Typography>
                                                </TableCell>
                                            </TableRow>
                                        ))
                                    )}
                                </TableBody>
                            </Table>
                        </TableContainer>
                    </Paper>
                </Grid>
            </Grid>
        </Box>
    );
}