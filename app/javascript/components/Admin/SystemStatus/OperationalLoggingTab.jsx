import React, { useState, useEffect } from 'react';
import {
    Box, Grid, Paper, Typography, Button, Select, MenuItem,
    FormControl, InputLabel, Alert, CircularProgress, Stack, Chip
} from '@mui/material';
import { BugReport, Timer, Save, WarningAmber } from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

export default function OperationalLoggingTab() {
    const notify = useNotify();

    const [loading, setLoading] = useState(true);
    const [submitting, setSubmitting] = useState(false);
    const [statusMessage, setStatusMessage] = useState(null);

    // Current State from Server
    const [activeConfig, setActiveConfig] = useState({
        current_level: 'INFO',
        ttl_active: false,
        minutes_remaining: 0
    });

    // Form State
    const [selectedLevel, setSelectedLevel] = useState('INFO');
    const [selectedTtl, setSelectedTtl] = useState(0);

    useEffect(() => {
        fetchLoggingStatus();
    }, []);

    const fetchLoggingStatus = () => {
        setLoading(true);
        fetch('/admin/system_configurations/logging')
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    setActiveConfig(data);
                    setSelectedLevel(data.current_level);
                }
                setLoading(false);
            })
            .catch(err => {
                console.error("Failed to load logging config", err);
                setLoading(false);
                notify("Failed to retrieve logging configuration.", "error");
            });
    };

    const handleSaveConfiguration = () => {
        setSubmitting(true);
        setStatusMessage(null);

        const csrfToken = document.querySelector('[name="csrf-token"]')?.content || '';

        fetch('/admin/system_configurations/logging', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrfToken
            },
            body: JSON.stringify({
                level: selectedLevel,
                ttl_minutes: selectedTtl
            })
        })
            .then(res => res.json())
            .then(data => {
                setSubmitting(false);
                if (data.success) {
                    setStatusMessage({ type: 'success', text: data.message });
                    notify(`Log level successfully changed to ${selectedLevel}`, "success");
                    fetchLoggingStatus(); // Refresh active state
                } else {
                    setStatusMessage({ type: 'error', text: data.error || 'Failed to update logging level.' });
                    notify(data.error || "Update failed.", "error");
                }
            })
            .catch(err => {
                setSubmitting(false);
                setStatusMessage({ type: 'error', text: 'Network error while updating configuration.' });
            });
    };

    const getLevelColor = (level) => {
        switch(level) {
            case 'TRACE':
            case 'DEBUG': return 'warning';
            case 'INFO': return 'success';
            case 'WARN': return 'warning';
            case 'ERROR':
            case 'FATAL': return 'error';
            default: return 'default';
        }
    };

    return (
        <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
            <Grid container spacing={4}>

                {/* Active Status Display */}
                <Grid item xs={12} md={5}>
                    <Paper variant="outlined" sx={{ p: 3, borderRadius: 3, height: '100%', bgcolor: '#ffffff' }}>
                        <Typography variant="h6" sx={{ fontWeight: 700, mb: 2, display: 'flex', alignItems: 'center', gap: 1 }}>
                            <BugReport color="primary" /> Current Pipeline Status
                        </Typography>

                        {loading ? (
                            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}><CircularProgress size={30} /></Box>
                        ) : (
                            <Stack spacing={3}>
                                <Box>
                                    <Typography variant="body2" color="textSecondary" gutterBottom>
                                        Active Log Level
                                    </Typography>
                                    <Chip
                                        label={activeConfig.current_level}
                                        color={getLevelColor(activeConfig.current_level)}
                                        sx={{ fontWeight: 'bold', fontSize: '1.1rem', px: 2, py: 2.5 }}
                                    />
                                </Box>

                                {activeConfig.ttl_active && (
                                    <Alert severity="warning" icon={<Timer fontSize="inherit" />}>
                                        Temporary elevation active. Reverting to standard level in <strong>{activeConfig.minutes_remaining} minutes</strong>.
                                    </Alert>
                                )}

                                <Typography variant="caption" color="textSecondary">
                                    Changes made here are instantly broadcasted to all active Puma worker nodes via Redis Pub/Sub, requiring zero downtime.
                                </Typography>
                            </Stack>
                        )}
                    </Paper>
                </Grid>

                {/* Configuration Controls */}
                <Grid item xs={12} md={7}>
                    <Paper variant="outlined" sx={{ p: 3, borderRadius: 3, height: '100%' }}>
                        <Typography variant="h6" sx={{ fontWeight: 700, mb: 1 }}>
                            Adjust Log Verbosity
                        </Typography>
                        <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                            Elevate logging output to capture detailed execution traces. High verbosity levels (DEBUG, TRACE) should be used with a Time-to-Live to prevent log ingestion bloat.
                        </Typography>

                        {statusMessage && (
                            <Alert severity={statusMessage.type} sx={{ mb: 3 }}>{statusMessage.text}</Alert>
                        )}

                        <Stack spacing={3}>
                            <Grid container spacing={2}>
                                <Grid item xs={12} sm={6}>
                                    <FormControl fullWidth>
                                        <InputLabel id="log-level-label">Target Log Level</InputLabel>
                                        <Select
                                            labelId="log-level-label"
                                            value={selectedLevel}
                                            label="Target Log Level"
                                            onChange={(e) => setSelectedLevel(e.target.value)}
                                        >
                                            <MenuItem value="FATAL">FATAL (Critical Crashes Only)</MenuItem>
                                            <MenuItem value="ERROR">ERROR (Exceptions & Crashes)</MenuItem>
                                            <MenuItem value="WARN">WARN (Deprecations & Warnings)</MenuItem>
                                            <MenuItem value="INFO">INFO (Standard Operations)</MenuItem>
                                            <MenuItem value="DEBUG">DEBUG (Detailed Variables)</MenuItem>
                                            <MenuItem value="TRACE">TRACE (Maximum Verbosity)</MenuItem>
                                        </Select>
                                    </FormControl>
                                </Grid>

                                <Grid item xs={12} sm={6}>
                                    <FormControl fullWidth>
                                        <InputLabel id="ttl-label">Time-To-Live (Auto-Revert)</InputLabel>
                                        <Select
                                            labelId="ttl-label"
                                            value={selectedTtl}
                                            label="Time-To-Live (Auto-Revert)"
                                            onChange={(e) => setSelectedTtl(e.target.value)}
                                        >
                                            <MenuItem value={0}>Permanent (No Auto-Revert)</MenuItem>
                                            <MenuItem value={15}>15 Minutes</MenuItem>
                                            <MenuItem value={60}>1 Hour</MenuItem>
                                            <MenuItem value={240}>4 Hours</MenuItem>
                                        </Select>
                                    </FormControl>
                                </Grid>
                            </Grid>

                            {(selectedLevel === 'DEBUG' || selectedLevel === 'TRACE') && selectedTtl === 0 && (
                                <Alert severity="error" icon={<WarningAmber fontSize="inherit" />}>
                                    Warning: Leaving high-verbosity logs on permanently can severely impact application performance and incur massive storage costs.
                                </Alert>
                            )}

                            <Box sx={{ display: 'flex', justifyContent: 'flex-end', pt: 2 }}>
                                <Button
                                    variant="contained"
                                    color="primary"
                                    startIcon={<Save />}
                                    onClick={handleSaveConfiguration}
                                    disabled={submitting || loading}
                                    sx={{ bgcolor: '#5e35b1', px: 4 }}
                                >
                                    {submitting ? 'Broadcasting...' : 'Apply Configuration'}
                                </Button>
                            </Box>
                        </Stack>
                    </Paper>
                </Grid>
            </Grid>
        </Paper>
    );
}