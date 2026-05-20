import React, { useState, useEffect } from 'react';
import {
    Box, Grid, Paper, Typography, Button, TextField, Switch, FormControlLabel,
    Divider, CircularProgress, Chip, Stack, List, ListItem, ListItemText, Alert,
    Tab, Tabs, CssBaseline, Toolbar, MenuItem
} from '@mui/material';
import {
    Dns, Email, Storage, RestartAlt, Sync, CheckCircle,
    Cancel, Warning, Speed, PriorityHigh
} from '@mui/icons-material';
import Sidebar from "../Sidebar";
import { navigateTo } from '../../utils/globalutils';
import { useNotify } from '../../context/NotificationContext';

export default function SystemStatus({ incomingConfigs }) {
    const notify = useNotify(); // Initialize the global trigger

    const isAdmin = incomingConfigs.userIsAdmin === 'true';
    const [currentTab, setCurrentTab] = useState(0);
    const [diagnostics, setDiagnostics] = useState(null);
    const [loadingHealth, setLoadingHealth] = useState(true);
    const [restartMessage, setRestartMessage] = useState(null);
    const [restartLoading, setRestartLoading] = useState(false);

    const [activeView, setActiveView] = useState('System');

    // SMTP Form Settings initialized with initial props passed from Rails
    const [smtpConfig, setSmtpConfig] = useState({
        enabled: 'false',
        address: '',
        port: '587',
        domain: '',
        user_name: '',
        password: '',
        authentication: 'plain',
        enable_starttls_auto: 'true',
        sender_address: '',
        ...incomingConfigs
    });

    const [testRecipient, setTestRecipient] = useState('');
    const [testResult, setTestResult] = useState(null);
    const [testLoading, setTestLoading] = useState(false);
    const [saveStatus, setSaveStatus] = useState(null);

    useEffect(() => {
        fetchHealthData();
        fetchSmtpConfig();
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

    const fetchSmtpConfig = () => {
        if (incomingConfigs) {
            setSmtpConfig(prev => ({
                ...prev,
                ...incomingConfigs
            }));
        }
    };

    const handleSmtpChange = (field, value) => {
        setSmtpConfig({ ...smtpConfig, [field]: value });
    };

    const handleSaveSmtp = () => {
        setSaveStatus(null);

        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        fetch('/admin/system_status/update_smtp', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify({ smtp_config: smtpConfig })
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    setSaveStatus({ type: 'success', msg: data.message });
                    notify(data.message, "success");
                } else {
                    setSaveStatus({ type: 'error', msg: data.errors?.join(', ') || 'Failed to update.' });
                    notify(data.errors?.join(', '), "error");
                }
            });
    };

    const handleSendTestEmail = () => {
        setTestLoading(true);
        setTestResult(null);

        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        fetch('/admin/system_status/test_email', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify({ test_recipient: testRecipient })
        })
            .then(res => res.json())
            .then(data => {
                setTestLoading(false);
                if (data.success) {
                    setTestResult({ success: true, message: data.message });
                    notify(`SMTP Echo success! Connection established. Email dispatched.`, "success");
                } else {
                    setTestResult({ success: false, error: data.error });
                    notify(`SMTP Handshake Aborted: ${data.error}`, "error", 5000);
                }
            })
            .catch(err => {
                setTestLoading(false);
                setTestResult({ success: false, error: 'Connection error during dispatch test.' });
                notify("SMTP relay failure: Failed to reach the mail server host.", "error");
            });
    };

    const handleRestartServer = () => {
        if (!window.confirm("Trigger rolling soft reload of the Puma Web Server? Existing traffic will process uninterrupted.")) {
            return;
        }
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
            case 'healthy':
                return <CheckCircle sx={{ color: '#2e7d32' }} />;
            case 'degraded':
                return <Warning sx={{ color: '#ed6c02' }} />;
            default:
                return <Cancel sx={{ color: '#d32f2f' }} />;
        }
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <Sidebar activeView={activeView} onNavigate={(v) => v === 'System' ? null : navigateTo('/dashboard')} />

            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                <Toolbar/>
                <Box sx={{ width: '100%', p: 1 }}>
                    <Box sx={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        width: '100%', // Ensure it spans the full width
                    }}>
                        {/* LEFT SIDE */}
                        <Box>
                            <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>System Operations</Typography>
                            <Typography variant="body2" color="textSecondary">Manage email routing credentials and monitor system runtime vitals.</Typography>
                        </Box>

                        {/* RIGHT SIDE */}
                        <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 2 }}>
                            {currentTab === 0 && (
                                <Button
                                    variant="outlined"
                                    startIcon={<Sync />}
                                    onClick={fetchHealthData}
                                    disabled={loadingHealth}
                                >
                                    Refresh Vitals
                                </Button>
                            )}
                        </Stack>
                    </Box>
                </Box>

                <Tabs value={currentTab} onChange={(e, val) => setCurrentTab(val)} sx={{ mb: 4 }}>
                    <Tab label="System Observability" icon={<Dns />} iconPosition="start" />
                    <Tab label="SMTP & Email Settings" icon={<Email />} iconPosition="start" />
                </Tabs>

                {currentTab === 0 && (
                    <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
                        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 3 }}>
                            {/* Live Services Status Row */}
                            {loadingHealth ? (
                                <Box sx={{ display: 'flex', justifyContent: 'center', py: 8 }}><CircularProgress /></Box>
                            ) : (
                                <Grid container spacing={3}>
                                    {/* App Server */}
                                    <Grid item xs={12} sm={6} md={3}>
                                        <Paper variant="outlined" sx={{ p: 3, borderRadius: 3, position: 'relative' }}>
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

                            {/* Server Administration Tools */}
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
                                            <Button
                                                variant="contained"
                                                color="error"
                                                onClick={handleRestartServer}
                                                disabled={restartLoading}
                                            >
                                                {restartLoading ? 'Signalling reload...' : 'Initiate Application Reload'}
                                            </Button>
                                        </Paper>
                                    </Grid>
                                </Grid>
                            </Paper>
                        </Stack>
                    </Paper>
                )}

                {currentTab === 1 && (
                    <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
                        <Grid container spacing={4}>
                            {/* SMTP Credentials Form */}
                            <Grid item xs={12} lg={7}>
                                <Paper variant="outlined" sx={{ p: 3, borderRadius: 3 }}>
                                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
                                        <Typography variant="h6" sx={{ fontWeight: 700 }}>SMTP Infrastructure Setup</Typography>
                                        <FormControlLabel
                                            control={
                                                <Switch
                                                    checked={smtpConfig.enabled === 'true'}
                                                    onChange={(e) => handleSmtpChange('enabled', e.target.checked ? 'true' : 'false')}
                                                />
                                            }
                                            label="Route outbound mail via SMTP"
                                        />
                                    </Box>

                                    {saveStatus && (
                                        <Alert severity={saveStatus.type} sx={{ mb: 3 }}>{saveStatus.msg}</Alert>
                                    )}

                                    <Stack spacing={3}>
                                        <Grid container spacing={2}>
                                            <Grid item xs={12} sm={8}>
                                                <TextField
                                                    fullWidth label="SMTP Mail Server Host"
                                                    placeholder="smtp.sendgrid.net"
                                                    value={smtpConfig.address}
                                                    onChange={(e) => handleSmtpChange('address', e.target.value)}
                                                />
                                            </Grid>
                                            <Grid item xs={12} sm={4}>
                                                <TextField
                                                    fullWidth label="Port"
                                                    placeholder="587"
                                                    value={smtpConfig.port}
                                                    onChange={(e) => handleSmtpChange('port', e.target.value)}
                                                />
                                            </Grid>
                                        </Grid>

                                        <TextField
                                            fullWidth label="Sender Address (From:)"
                                            placeholder="noreply@yourcompany.com"
                                            value={smtpConfig.sender_address}
                                            onChange={(e) => handleSmtpChange('sender_address', e.target.value)}
                                        />

                                        <Grid container spacing={2}>
                                            <Grid item xs={12} sm={6}>
                                                <TextField
                                                    fullWidth label="Authentication Username"
                                                    value={smtpConfig.user_name}
                                                    onChange={(e) => handleSmtpChange('user_name', e.target.value)}
                                                />
                                            </Grid>
                                            <Grid item xs={12} sm={6}>
                                                <TextField
                                                    fullWidth type="password" label="SMTP Password"
                                                    value={smtpConfig.password}
                                                    onChange={(e) => handleSmtpChange('password', e.target.value)}
                                                />
                                            </Grid>
                                        </Grid>

                                        <Grid container spacing={2}>
                                            <Grid item xs={12} sm={6}>
                                                <TextField
                                                    fullWidth select label="Authentication Handshake Type"
                                                    value={smtpConfig.authentication}
                                                    onChange={(e) => handleSmtpChange('authentication', e.target.value)}
                                                >
                                                    <MenuItem value="plain">Plain Text (Standard)</MenuItem>
                                                    <MenuItem value="login">Login Sequence</MenuItem>
                                                    <MenuItem value="cram_md5">CRAM MD5 Hash</MenuItem>
                                                </TextField>
                                            </Grid>
                                            <Grid item xs={12} sm={6}>
                                                <TextField
                                                    fullWidth select label="Connection Security Protocol"
                                                    value={smtpConfig.enable_starttls_auto}
                                                    onChange={(e) => handleSmtpChange('enable_starttls_auto', e.target.value)}
                                                >
                                                    <MenuItem value="true">Enable STARTTLS Auto (Secure)</MenuItem>
                                                    <MenuItem value="false">No Encryption / Standard Port 25</MenuItem>
                                                </TextField>
                                            </Grid>
                                        </Grid>

                                        <Box sx={{ display: 'flex', justifyContent: 'flex-end', mt: 2 }}>
                                            <Button variant="contained" sx={{ bgcolor: '#5e35b1' }} onClick={handleSaveSmtp}>
                                                Commit System Credentials
                                            </Button>
                                        </Box>
                                    </Stack>
                                </Paper>
                            </Grid>

                            {/* SMTP Real-time Diagnosis Console */}
                            <Grid item xs={12} lg={5}>
                                <Paper variant="outlined" sx={{ p: 3, borderRadius: 3, borderStyle: 'dashed', bgcolor: '#fafafa' }}>
                                    <Typography variant="h6" sx={{ fontWeight: 700, mb: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
                                        <Speed /> Send SMTP Echo Check
                                    </Typography>
                                    <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                                        Trigger a real-time mail dispatch payload to test connectivity, handshake verification, and secure relay.
                                    </Typography>

                                    <Stack spacing={3}>
                                        <TextField
                                            fullWidth label="Recipient Address for Test Mail"
                                            placeholder="engineering@company.com"
                                            value={testRecipient}
                                            onChange={(e) => setTestRecipient(e.target.value)}
                                            sx={{ bgcolor: 'white' }}
                                        />

                                        <Button
                                            variant="outlined"
                                            onClick={handleSendTestEmail}
                                            disabled={testLoading || !testRecipient}
                                        >
                                            {testLoading ? 'Processing Relay Test...' : 'Trigger SMTP Diagnostic Run'}
                                        </Button>

                                        {testResult && (
                                            <Paper
                                                variant="outlined"
                                                sx={{
                                                    p: 2,
                                                    borderRadius: 2,
                                                    bgcolor: testResult.success ? '#f6ffed' : '#fff1f0',
                                                    borderColor: testResult.success ? '#b7eb8f' : '#ffccc7'
                                                }}
                                            >
                                                <Stack direction="row" spacing={1.5} alignItems="flex-start">
                                                    {testResult.success ? <CheckCircle sx={{ color: '#389e0d' }} /> : <PriorityHigh sx={{ color: '#cf1322' }} />}
                                                    <Box>
                                                        <Typography variant="subtitle2" sx={{ color: testResult.success ? '#389e0d' : '#cf1322', fontWeight: 600 }}>
                                                            {testResult.success ? 'SMTP Connection Succeeded' : 'SMTP Handshake Aborted'}
                                                        </Typography>
                                                        <Typography variant="caption" sx={{ display: 'block', mt: 0.5, color: '#434343' }}>
                                                            {testResult.success ? testResult.message : testResult.error}
                                                        </Typography>
                                                    </Box>
                                                </Stack>
                                            </Paper>
                                        )}
                                    </Stack>
                                </Paper>
                            </Grid>
                        </Grid>
                    </Paper>
                )}
            </Box>
        </Box>
    );
}