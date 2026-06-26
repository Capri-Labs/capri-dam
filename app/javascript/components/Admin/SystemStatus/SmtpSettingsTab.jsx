import React, { useState, useEffect } from 'react';
import { Box, Grid, Paper, Typography, Button, TextField, Switch, FormControlLabel, Stack, Alert, MenuItem } from '@mui/material';
import { CheckCircle, Speed, PriorityHigh } from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

export default function SmtpSettingsTab({ incomingConfigs }) {
    const notify = useNotify();

    const [smtpConfig, setSmtpConfig] = useState({
        enabled: 'false', address: '', port: '587', domain: '', user_name: '', password: '',
        authentication: 'plain', enable_starttls_auto: 'true', sender_address: '', ...incomingConfigs
    });

    const [testRecipient, setTestRecipient] = useState('');
    const [testResult, setTestResult] = useState(null);
    const [testLoading, setTestLoading] = useState(false);
    const [saveStatus, setSaveStatus] = useState(null);

    useEffect(() => {
        if (incomingConfigs) {
            setSmtpConfig(prev => ({ ...prev, ...incomingConfigs }));
        }
    }, [incomingConfigs]);

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

    return (
        <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
            <Grid container spacing={4}>
                {/* SMTP Credentials Form */}
                <Grid size={{ xs: 12, lg: 7 }}>
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
                                <Grid size={{ xs: 12, sm: 8 }}>
                                    <TextField fullWidth label="SMTP Mail Server Host" value={smtpConfig.address} onChange={(e) => handleSmtpChange('address', e.target.value)} />
                                </Grid>
                                <Grid size={{ xs: 12, sm: 4 }}>
                                    <TextField fullWidth label="Port" value={smtpConfig.port} onChange={(e) => handleSmtpChange('port', e.target.value)} />
                                </Grid>
                            </Grid>

                            <TextField fullWidth label="Sender Address (From:)" value={smtpConfig.sender_address} onChange={(e) => handleSmtpChange('sender_address', e.target.value)} />

                            <Grid container spacing={2}>
                                <Grid size={{ xs: 12, sm: 6 }}>
                                    <TextField fullWidth label="Authentication Username" value={smtpConfig.user_name} onChange={(e) => handleSmtpChange('user_name', e.target.value)} />
                                </Grid>
                                <Grid size={{ xs: 12, sm: 6 }}>
                                    <TextField fullWidth type="password" label="SMTP Password" value={smtpConfig.password} onChange={(e) => handleSmtpChange('password', e.target.value)} />
                                </Grid>
                            </Grid>

                            <Grid container spacing={2}>
                                <Grid size={{ xs: 12, sm: 6 }}>
                                    <TextField fullWidth select label="Authentication Handshake Type" value={smtpConfig.authentication} onChange={(e) => handleSmtpChange('authentication', e.target.value)}>
                                        <MenuItem value="plain">Plain Text (Standard)</MenuItem>
                                        <MenuItem value="login">Login Sequence</MenuItem>
                                        <MenuItem value="cram_md5">CRAM MD5 Hash</MenuItem>
                                    </TextField>
                                </Grid>
                                <Grid size={{ xs: 12, sm: 6 }}>
                                    <TextField fullWidth select label="Connection Security Protocol" value={smtpConfig.enable_starttls_auto} onChange={(e) => handleSmtpChange('enable_starttls_auto', e.target.value)}>
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
                <Grid size={{ xs: 12, lg: 5 }}>
                    <Paper variant="outlined" sx={{ p: 3, borderRadius: 3, borderStyle: 'dashed', bgcolor: '#fafafa' }}>
                        <Typography variant="h6" sx={{ fontWeight: 700, mb: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Speed /> Send SMTP Echo Check
                        </Typography>
                        <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                            Trigger a real-time mail dispatch payload to test connectivity, handshake verification, and secure relay.
                        </Typography>

                        <Stack spacing={3}>
                            <TextField fullWidth label="Recipient Address for Test Mail" placeholder="engineering@company.com" value={testRecipient} onChange={(e) => setTestRecipient(e.target.value)} sx={{ bgcolor: 'white' }} />

                            <Button variant="outlined" onClick={handleSendTestEmail} disabled={testLoading || !testRecipient}>
                                {testLoading ? 'Processing Relay Test...' : 'Trigger SMTP Diagnostic Run'}
                            </Button>

                            {testResult && (
                                <Paper variant="outlined" sx={{ p: 2, borderRadius: 2, bgcolor: testResult.success ? '#f6ffed' : '#fff1f0', borderColor: testResult.success ? '#b7eb8f' : '#ffccc7' }}>
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
    );
}