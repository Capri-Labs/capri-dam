import React, { useState, useEffect } from 'react';
import { Box, Grid, Paper, Typography, Button, CircularProgress, Stack, Alert } from '@mui/material';
import { Sync, CheckCircle, Cancel, Warning, RestartAlt } from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

export default function ObservabilityTab() {
    const notify = useNotify();
    const [diagnostics, setDiagnostics] = useState(null);
    const [loadingHealth, setLoadingHealth] = useState(true);
    const [restartMessage, setRestartMessage] = useState(null);
    const [restartLoading, setRestartLoading] = useState(false);

    useEffect(() => {
        fetchHealthData();
    }, []);

    const fetchHealthData = () => {
        setLoadingHealth(true);
        fetch('/admin/system_status.json')
            .then(res => res.json())
            .then(data => {
                setDiagnostics(data);
                setLoadingHealth(false);
                notify("Infrastructure matrices refreshed successfully.", "success", 2000);
            })
            .catch(err => {
                console.error("Failed to load health reports", err);
                setLoadingHealth(false);
                notify("Failed to retrieve diagnostics. Check application server logs.", "error");
            });
    };

    const handleRestartServer = () => {
        if (!window.confirm("Trigger rolling soft reload of the Puma Web Server? Existing traffic will process uninterrupted.")) return;

        setRestartLoading(true);
        setRestartMessage(null);
        const csrfToken = document.querySelector('[name="csrf-token"]').content;

        fetch('/admin/system_status/restart_server', {
            method: 'POST',
            headers: { 'X-CSRF-Token': csrfToken }
        })
            .then(res => res.json())
            .then(data => {
                setRestartLoading(false);
                setRestartMessage({ type: 'success', text: data.message });
            })
            .catch(err => {
                setRestartLoading(false);
                setRestartMessage({ type: 'error', text: 'Error dispatching restart command.' });
            });
    };

    const getStatusIcon = (status) => {
        switch(status) {
            case 'healthy': return <CheckCircle sx={{ color: '#2e7d32' }} />;
            case 'degraded': return <Warning sx={{ color: '#ed6c02' }} />;
            default: return <Cancel sx={{ color: '#d32f2f' }} />;
        }
    };

    return (
        <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
            <Box sx={{ display: 'flex', justifyContent: 'flex-end', mb: 3 }}>
                <Button variant="outlined" startIcon={<Sync />} onClick={fetchHealthData} disabled={loadingHealth}>
                    Refresh Vitals
                </Button>
            </Box>

            <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 3 }}>
                {loadingHealth ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', width: '100%', py: 8 }}><CircularProgress /></Box>
                ) : (
                    <Grid container spacing={3}>
                        {/* App Server */}
                        <Grid item xs={12} sm={6} md={3}>
                            <Paper variant="outlined" sx={{ p: 3, borderRadius: 3 }}>
                                <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 2 }}>
                                    <Typography variant="subtitle2" color="textSecondary">Application Node</Typography>
                                    {getStatusIcon(diagnostics?.app_server?.status)}
                                </Box>
                                <Typography variant="h5" sx={{ fontWeight: 700 }}>Puma Rack</Typography>
                                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1 }}>
                                    Ruby {diagnostics?.app_server?.ruby_version} • Rails {diagnostics?.app_server?.rails_version}
                                </Typography>
                            </Paper>
                        </Grid>

                        {/* Database Card */}
                        <Grid item xs={12} sm={6} md={3}>
                            <Paper variant="outlined" sx={{ p: 3, borderRadius: 3 }}>
                                <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 2 }}>
                                    <Typography variant="subtitle2" color="textSecondary">PostgreSQL</Typography>
                                    {getStatusIcon(diagnostics?.database?.status)}
                                </Box>
                                <Typography variant="h5" sx={{ fontWeight: 700 }}>
                                    {diagnostics?.database?.status === 'healthy' ? `${diagnostics.database.latency_ms} ms` : 'Offline'}
                                </Typography>
                                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1 }}>
                                    Pool: {diagnostics?.database?.pool_size} • Active: {diagnostics?.database?.active_connections}
                                </Typography>
                            </Paper>
                        </Grid>

                        {/* Background Queue Cache Card */}
                        <Grid item xs={12} sm={6} md={3}>
                            <Paper variant="outlined" sx={{ p: 3, borderRadius: 3 }}>
                                <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 2 }}>
                                    <Typography variant="subtitle2" color="textSecondary">Redis & Sidekiq</Typography>
                                    {getStatusIcon(diagnostics?.cache_queue?.status)}
                                </Box>
                                <Typography variant="h5" sx={{ fontWeight: 700 }}>
                                    {diagnostics?.cache_queue?.active_workers} Workers Active
                                </Typography>
                                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1 }}>
                                    Queue Depth: {diagnostics?.cache_queue?.queue_depth} • Latency: {diagnostics?.cache_queue?.latency_ms} ms
                                </Typography>
                            </Paper>
                        </Grid>

                        {/* Storage Driver Card */}
                        <Grid item xs={12} sm={6} md={3}>
                            <Paper variant="outlined" sx={{ p: 3, borderRadius: 3 }}>
                                <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 2 }}>
                                    <Typography variant="subtitle2" color="textSecondary">ActiveStorage</Typography>
                                    {getStatusIcon(diagnostics?.storage_backend?.status)}
                                </Box>
                                <Typography variant="h5" sx={{ fontWeight: 700 }}>
                                    {diagnostics?.storage_backend?.status === 'healthy' ? `${diagnostics.storage_backend.latency_ms} ms` : 'Unreachable'}
                                </Typography>
                                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1 }}>
                                    Driver: {diagnostics?.storage_backend?.provider}
                                </Typography>
                            </Paper>
                        </Grid>
                    </Grid>
                )}
            </Stack>

            <Paper variant="outlined" sx={{ p: 3, borderRadius: 3 }}>
                <Typography variant="h6" sx={{ fontWeight: 700, mb: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
                    <RestartAlt /> Server Engineering Controls
                </Typography>
                <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                    Perform hot-reloads of runtime processes or restart background engines without dropping clients.
                </Typography>

                {restartMessage && (
                    <Alert severity={restartMessage.type} sx={{ mb: 3 }}>{restartMessage.text}</Alert>
                )}

                <Grid container spacing={3}>
                    <Grid item xs={12} md={6}>
                        <Paper elevation={0} sx={{ p: 2, bgcolor: '#f8f9fa', border: '1px solid #e3e8ef', borderRadius: 2 }}>
                            <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Restart Application Server</Typography>
                            <Typography variant="caption" color="textSecondary" display="block" sx={{ mb: 2 }}>
                                Signals Passenger/Puma using restart.txt to cycle current container processes gracefully.
                            </Typography>
                            <Button variant="contained" color="error" onClick={handleRestartServer} disabled={restartLoading}>
                                {restartLoading ? 'Signalling reload...' : 'Initiate Application Reload'}
                            </Button>
                        </Paper>
                    </Grid>
                </Grid>
            </Paper>
        </Paper>
    );
}