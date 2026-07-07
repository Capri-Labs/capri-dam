import React, { useState, useEffect } from 'react';
import {
    Box, Grid, Paper, Typography, Button, Select, MenuItem,
    FormControl, InputLabel, Alert, CircularProgress, Stack, Chip
} from '@mui/material';
import { BugReport, Timer, Save, WarningAmber } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';

export default function OperationalLoggingTab() {
    const notify = useNotify();
    const { t } = useTranslation();

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
                notify(t('operationalLogging.fetchError'), "error");
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
                    notify(t('operationalLogging.updateSuccess', { level: selectedLevel }), "success");
                    fetchLoggingStatus(); // Refresh active state
                } else {
                    setStatusMessage({ type: 'error', text: data.error || t('operationalLogging.updateFailed') });
                    notify(data.error || t('operationalLogging.updateFailedGeneric'), "error");
                }
            })
            .catch(err => {
                setSubmitting(false);
                setStatusMessage({ type: 'error', text: t('operationalLogging.networkError') });
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
                <Grid size={{ xs: 12, md: 5 }}>
                    <Paper variant="outlined" sx={{ p: 3, borderRadius: 3, height: '100%', bgcolor: '#ffffff' }}>
                        <Typography variant="h6" sx={{ fontWeight: 700, mb: 2, display: 'flex', alignItems: 'center', gap: 1 }}>
                            <BugReport color="primary" /> {t('operationalLogging.pipelineStatus')}
                        </Typography>

                        {loading ? (
                            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}><CircularProgress size={30} /></Box>
                        ) : (
                            <Stack spacing={3}>
                                <Box>
                                    <Typography variant="body2" color="textSecondary" gutterBottom>
                                        {t('operationalLogging.activeLogLevel')}
                                    </Typography>
                                    <Chip
                                        label={activeConfig.current_level}
                                        color={getLevelColor(activeConfig.current_level)}
                                        sx={{ fontWeight: 'bold', fontSize: '1.1rem', px: 2, py: 2.5 }}
                                    />
                                </Box>

                                {activeConfig.ttl_active && (
                                    <Alert severity="warning" icon={<Timer fontSize="inherit" />}>
                                        {t('operationalLogging.temporaryElevation', { minutes: activeConfig.minutes_remaining })}
                                    </Alert>
                                )}

                                <Typography variant="caption" color="textSecondary">
                                    {t('operationalLogging.broadcastNotice')}
                                </Typography>
                            </Stack>
                        )}
                    </Paper>
                </Grid>

                {/* Configuration Controls */}
                <Grid size={{ xs: 12, md: 7 }}>
                    <Paper variant="outlined" sx={{ p: 3, borderRadius: 3, height: '100%' }}>
                        <Typography variant="h6" sx={{ fontWeight: 700, mb: 1 }}>
                            {t('operationalLogging.adjustVerbosity')}
                        </Typography>
                        <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                            {t('operationalLogging.adjustVerbosityDescription')}
                        </Typography>

                        {statusMessage && (
                            <Alert severity={statusMessage.type} sx={{ mb: 3 }}>{statusMessage.text}</Alert>
                        )}

                        <Stack spacing={3}>
                            <Grid container spacing={2}>
                                <Grid size={{ xs: 12, sm: 6 }}>
                                    <FormControl fullWidth>
                                        <InputLabel id="log-level-label">{t('operationalLogging.targetLogLevel')}</InputLabel>
                                        <Select
                                            labelId="log-level-label"
                                            value={selectedLevel}
                                            label={t('operationalLogging.targetLogLevel')}
                                            onChange={(e) => setSelectedLevel(e.target.value)}
                                        >
                                            <MenuItem value="FATAL">{t('operationalLogging.levels.FATAL')}</MenuItem>
                                            <MenuItem value="ERROR">{t('operationalLogging.levels.ERROR')}</MenuItem>
                                            <MenuItem value="WARN">{t('operationalLogging.levels.WARN')}</MenuItem>
                                            <MenuItem value="INFO">{t('operationalLogging.levels.INFO')}</MenuItem>
                                            <MenuItem value="DEBUG">{t('operationalLogging.levels.DEBUG')}</MenuItem>
                                            <MenuItem value="TRACE">{t('operationalLogging.levels.TRACE')}</MenuItem>
                                        </Select>
                                    </FormControl>
                                </Grid>

                                <Grid size={{ xs: 12, sm: 6 }}>
                                    <FormControl fullWidth>
                                        <InputLabel id="ttl-label">{t('operationalLogging.ttl')}</InputLabel>
                                        <Select
                                            labelId="ttl-label"
                                            value={selectedTtl}
                                            label={t('operationalLogging.ttl')}
                                            onChange={(e) => setSelectedTtl(e.target.value)}
                                        >
                                            <MenuItem value={0}>{t('operationalLogging.ttlOptions.permanent')}</MenuItem>
                                            <MenuItem value={15}>{t('operationalLogging.ttlOptions.15m')}</MenuItem>
                                            <MenuItem value={60}>{t('operationalLogging.ttlOptions.1h')}</MenuItem>
                                            <MenuItem value={240}>{t('operationalLogging.ttlOptions.4h')}</MenuItem>
                                        </Select>
                                    </FormControl>
                                </Grid>
                            </Grid>

                            {(selectedLevel === 'DEBUG' || selectedLevel === 'TRACE') && selectedTtl === 0 && (
                                <Alert severity="error" icon={<WarningAmber fontSize="inherit" />}>
                                    {t('operationalLogging.highVerbosityWarning')}
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
                                    {submitting ? t('operationalLogging.broadcasting') : t('operationalLogging.applyConfiguration')}
                                </Button>
                            </Box>
                        </Stack>
                    </Paper>
                </Grid>
            </Grid>
        </Paper>
    );
}