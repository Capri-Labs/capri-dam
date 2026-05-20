import React, { useState } from 'react';
import {
    Box, CssBaseline, Toolbar, Typography, Paper, TextField,
    CircularProgress, FormControlLabel, Button, Divider, Table,
    TableBody, TableCell, TableContainer, TableHead, TableRow,
    Chip, Stack, Grid, FormControl, InputLabel, Select, MenuItem, Alert
} from '@mui/material';
import { Save, Shield,
    Settings as SettingsIcon,
    Delete as DeleteIcon,
    CloudUpload } from '@mui/icons-material';
import Sidebar from './Sidebar';
import SystemStatus from './Admin/SystemStatus';
import { navigateTo } from '../utils/globalutils';

export default function Settings(props) {

    const systemApps = JSON.parse(props.systemApps || '[]');
    const isAdmin = props.userIsAdmin === 'true';
    const [loading, setLoading] = useState(false);

    const [testStatus, setTestStatus] = useState({ loading: false, msg: null, error: null });
    const [activeView, setActiveView] = useState('General');
    const parsedAllConfigs = typeof props.allConfigs === 'string'
        ? JSON.parse(props.allConfigs || '{}')
        : (props.allConfigs || {});
    const [allConfigs, setAllConfigs] = useState(parsedAllConfigs);
    const [storageProvider, setStorageProvider] = useState(props.activeProvider || 'local');
    const currentStorageConfigs = allConfigs[storageProvider] || {};

    const updateField = (field, value) => {
        setAllConfigs(prev => ({
            ...prev,
            [storageProvider]: {
                ...(prev[storageProvider] || {}),
                [field]: value
            }
        }));
    };

    const handleClear = () => {
        if (window.confirm("Clear unsaved changes for this provider?")) {
            updateField('access_key', '');
            updateField('secret_key', '');
            updateField('region', '');
            updateField('bucket', '');
            updateField('endpoint', '');
        }
    };

    const handleSaveStorage = async () => {
        setLoading(true);
        const payload = {
            storage_config: {
                provider: storageProvider,
                ...allConfigs[storageProvider]
            }
        };

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const response = await fetch('/settings/update_storage', {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(payload)
            });

            if (response.ok) {
                alert(`Configuration for ${storageProvider} saved!`);
            } else {
                const err = await response.json();
                alert(`Error: ${err.error || "Failed to save"}`);
            }
        } catch (error) {
            alert("A network error occurred.");
        } finally {
            setLoading(false);
        }
    };

    // Revoke Account Helper
    const handleDeleteAccount = (appId) => {
        if (window.confirm("Are you sure you want to revoke these credentials? This cannot be undone.")) {
            // We create a hidden form to submit the DELETE request
            // This is the most reliable way to interact with Rails controllers from React
            const form = document.createElement('form');
            form.method = 'POST';
            form.action = `/admin/system_accounts/${appId}`;

            const methodInput = document.createElement('input');
            methodInput.type = 'hidden';
            methodInput.name = '_method';
            methodInput.value = 'delete';

            const csrfInput = document.createElement('input');
            csrfInput.type = 'hidden';
            csrfInput.name = 'authenticity_token';
            csrfInput.value = document.querySelector('[name="csrf-token"]').content;

            form.appendChild(methodInput);
            form.appendChild(csrfInput);
            document.body.appendChild(form);
            form.submit();
        }
    };

    const handleTestConnection = async () => {
        setTestStatus({ loading: true, msg: null, error: null });
        const payload = {
            storage_config: {
                provider: storageProvider,
                ...allConfigs[storageProvider]
            }
        };

        try {
            const response = await fetch('/settings/test_connection', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify(payload)
            });

            const data = await response.json();
            if (response.ok) {
                setTestStatus({ loading: false, msg: data.message, error: null });
            } else {
                setTestStatus({ loading: false, msg: null, error: data.error });
            }
        } catch (err) {
            setTestStatus({ loading: false, msg: null, error: "Network error occurred." });
        }
    };

    const currentSubView = props.currentSubView || 'General';
    const smtpConfig = React.useMemo(() => {
        try {
            return props.smtpConfig ? JSON.parse(props.smtpConfig) : {};
        } catch (e) {
            console.error("Error parsing smtpConfig:", e);
            return {};
        }
    }, [props.smtpConfig]);

    if (currentSubView === 'System') {
        return (
            <SystemStatus incomingConfigs={smtpConfig} />
        );
    }

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <Sidebar activeView={activeView} onNavigate={(v) => v === 'Settings' ? null : navigateTo('/dashboard')} />

            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                <Toolbar />

                {/* ... (Personal Preferences Section stays the same) ... */}

                {isAdmin && (
                    <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
                        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 3 }}>
                            <Shield sx={{ color: '#5e35b1' }} />
                            <Typography variant="h6" sx={{ fontWeight: 700, color: '#5e35b1' }}>
                                System Administration
                            </Typography>
                        </Stack>

                        {/* Global Config Fields... */}

                        <Divider sx={{ my: 1 }} />

                        <Box sx={{ width: '100%', p: 1 }}>
                            <Box sx={{
                                display: 'flex',
                                justifyContent: 'space-between',
                                alignItems: 'center',
                                width: '100%', // Ensure it spans the full width
                            }}>
                                {/* LEFT SIDE */}
                                <Box>
                                    <Typography variant="subtitle1" sx={{ fontWeight: 700, display: 'flex' }}>System Service Accounts</Typography>
                                </Box>

                                {/* RIGHT SIDE */}
                                <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 2 }}>
                                    <Button
                                        variant="contained"
                                        size="small"
                                        sx={{ bgcolor: '#5e35b1', display: 'flex' }}
                                        onClick={() => navigateTo('/admin/system_accounts/new')}
                                    >
                                        + Create New Account
                                    </Button>
                                </Stack>
                            </Box>
                        </Box>

                        <Divider sx={{ my: 1 }} />

                        <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e3e8ef' }}>
                            <Table size="small">
                                <TableHead sx={{ bgcolor: '#f8fafc' }}>
                                    <TableRow>
                                        <TableCell sx={{ fontWeight: 700 }}>App Name</TableCell>
                                        <TableCell sx={{ fontWeight: 700 }}>Client ID</TableCell>
                                        <TableCell align="right" sx={{ fontWeight: 700 }}>Actions</TableCell>
                                    </TableRow>
                                </TableHead>
                                <TableBody>
                                    {systemApps.map((app) => (
                                        <TableRow key={app.id}>
                                            <TableCell sx={{ fontWeight: 600 }}>{app.name}</TableCell>
                                            <TableCell>
                                                <code>
                                                    {app.uid
                                                        ? `${app.uid.substring(0, 6)}******`
                                                        : 'No UID'
                                                    }
                                                </code>
                                            </TableCell>
                                            <TableCell align="right">
                                                {/* FIX 2: VIEW BUTTON */}
                                                <Button
                                                    variant="outlined"
                                                    size="small"
                                                    onClick={() => navigateTo(`/admin/system_accounts/${app.id}`)}
                                                >
                                                    View
                                                </Button>

                                                {/* FIX 3: REVOKE BUTTON */}
                                                <Button
                                                    variant="outlined"
                                                    startIcon={<DeleteIcon />}
                                                    size="small"
                                                    color="error"
                                                    onClick={() => handleDeleteAccount(app.id)}
                                                >
                                                    Revoke
                                                </Button>
                                            </TableCell>
                                        </TableRow>
                                    ))}
                                </TableBody>
                            </Table>
                        </TableContainer>
                    </Paper>
                )}

                {isAdmin && (
                    <Paper
                        elevation={0}
                        sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff', mt: 4 }}
                    >
                        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 3 }}>
                            <CloudUpload sx={{ color: '#5e35b1' }} />
                            <Typography variant="h6" sx={{ fontWeight: 700, color: '#5e35b1' }}>
                                Storage Backend Configuration
                            </Typography>
                        </Stack>

                        <Divider sx={{ my: 1 }} />

                        <Grid item xs={12} sx={{ p: 1 }}>
                            <FormControl fullWidth sx={{ bgcolor: 'white' }}>
                                <InputLabel id="storage-provider-label">Primary Storage Provider</InputLabel>
                                <Select
                                    labelId="storage-provider-label"
                                    value={storageProvider}
                                    label="Primary Storage Provider"
                                    onChange={(e) => setStorageProvider(e.target.value)}
                                >
                                    <MenuItem value="local">Local Disk (Development only)</MenuItem>
                                    <MenuItem value="aws">Amazon S3</MenuItem>
                                    <MenuItem value="cloudflare">Cloudflare R2</MenuItem>
                                    <MenuItem value="backblaze">Backblaze B2</MenuItem>
                                    <MenuItem value="wasabi">Wasabi Hot Storage</MenuItem>
                                    <MenuItem value="digitalocean">DigitalOcean Spaces</MenuItem>
                                    <MenuItem value="google">Google Cloud Storage</MenuItem>
                                </Select>
                            </FormControl>
                        </Grid>

                        <Divider sx={{ my: 1 }} />

                        {/* Credential Fields */}
                        {storageProvider !== 'local' ? (
                            <>
                                <Grid item xs={12} md={6} sx={{ p: 1 }}>
                                    <TextField
                                        label="Access Key ID"
                                        fullWidth
                                        value={currentStorageConfigs.access_key || ''}
                                        onChange={(e) => updateField('access_key', e.target.value)}
                                        sx={{ bgcolor: 'white' }}
                                    />
                                </Grid>
                                <Grid item xs={12} md={6} sx={{ p: 1 }}>
                                    <TextField
                                        label="Secret Access Key"
                                        type="password"
                                        fullWidth
                                        value={currentStorageConfigs.secret_key || ''}
                                        onChange={(e) => updateField('secret_key', e.target.value)}
                                        onFocus={(e) => currentStorageConfigs.secret_key === '********' && updateField('secret_key', '')}
                                        sx={{ bgcolor: 'white' }}
                                    />
                                </Grid>
                                <Grid item xs={12} md={4} sx={{ p: 1 }}>
                                    <TextField
                                        label="Region"
                                        fullWidth
                                        value={currentStorageConfigs.region || ''}
                                        onChange={(e) => updateField('region', e.target.value)}
                                        sx={{ bgcolor: 'white' }}
                                    />
                                </Grid>
                                <Grid item xs={12} md={8} sx={{ p: 1 }}>
                                    <TextField
                                        label="Bucket Name"
                                        fullWidth
                                        value={currentStorageConfigs.bucket || ''}
                                        onChange={(e) => updateField('bucket', e.target.value)}
                                        sx={{ bgcolor: 'white' }}
                                    />
                                </Grid>
                                <Grid item xs={12} sx={{ p: 1 }}>
                                    <TextField
                                        label="Custom Endpoint URL"
                                        fullWidth
                                        value={currentStorageConfigs.endpoint || ''}
                                        onChange={(e) => updateField('endpoint', e.target.value)}
                                        sx={{ bgcolor: 'white' }}
                                        helperText="Required for R2/Wasabi."
                                    />
                                </Grid>
                            </>
                        ) : (
                            <Grid item xs={12}>
                                <Alert severity="info">Local storage uses the <code>/storage</code> directory in your Rails root.</Alert>
                            </Grid>
                        )}

                        <Divider sx={{ my: 1 }} />

                        <Stack direction="row" spacing={2} justifyContent="flex-end" sx={{ mt: 2 }}>
                            <Button
                                variant="outlined"
                                color="primary"
                                onClick={handleTestConnection}
                                disabled={testStatus.loading || storageProvider === 'local'}
                            >
                                {testStatus.loading ? <CircularProgress size={20} /> : "Test Connection"}
                            </Button>
                            <Button
                                variant="outlined"
                                color="inherit"
                                onClick={handleClear}
                                sx={{ borderRadius: 2, textTransform: 'none' }}
                            >
                                Clear Fields
                            </Button>
                            <Button
                                variant="contained"
                                onClick={handleSaveStorage}
                                disabled={loading}
                                startIcon={loading ? <CircularProgress size={20} color="inherit" /> : <Save />}
                                sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                            >
                                Save {storageProvider.toUpperCase()} Config
                            </Button>
                        </Stack>

                        <Stack direction="row" spacing={2} sx={{ mt: 2, display: 'block' }}>
                            {/* THE ERROR MESSAGE UNDER THE BUTTON */}
                            {testStatus.error && (
                                <Alert severity="error">{testStatus.error}</Alert>
                            )}
                            {/* SUCCESS MESSAGE */}
                            {testStatus.msg && (
                                <Alert severity="success">{testStatus.msg}</Alert>
                            )}
                        </Stack>
                    </Paper>
                )}
            </Box>
        </Box>
    );
}