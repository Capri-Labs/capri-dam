import React from 'react';
import {
    Box, CssBaseline, Typography, Paper, Button, Divider, Table,
    TableBody, TableCell, TableContainer, TableHead, TableRow,
    Stack, Alert
} from '@mui/material';
import { Shield, Delete as DeleteIcon } from '@mui/icons-material';
import SystemStatus from './Admin/SystemStatus';
import { navigateTo } from '../utils/globalutils';

// ─────────────────────────────────────────────────────────────
// Main Component
//
// NOTE: Storage Backend Configuration used to live on this General settings
// page. It has been moved to Settings → System → Storage & Edge → Origin
// Storage so that provider credentials live alongside the rest of the
// System Operations console (see Admin/SystemStatus/OriginStorageTab.jsx).
// System Administration (service accounts) remains here on the General page.
// ─────────────────────────────────────────────────────────────
export default function Settings(props) {
    const isAdmin = props.userIsAdmin === 'true';
    const systemApps = JSON.parse(props.systemApps || '[]');

    const smtpConfig = React.useMemo(() => {
        try { return props.smtpConfig ? JSON.parse(props.smtpConfig) : {}; }
        catch { return {}; }
    }, [props.smtpConfig]);

    const currentSubView = props.currentSubView || 'General';

    const handleDeleteAccount = (appId) => {
        if (window.confirm("Are you sure you want to revoke these credentials? This cannot be undone.")) {
            const form = document.createElement('form');
            form.method = 'POST';
            form.action = `/admin/system_accounts/${appId}`;
            const methodInput = document.createElement('input');
            methodInput.type = 'hidden'; methodInput.name = '_method'; methodInput.value = 'delete';
            const csrfInput = document.createElement('input');
            csrfInput.type = 'hidden'; csrfInput.name = 'authenticity_token';
            csrfInput.value = document.querySelector('[name="csrf-token"]').content;
            form.appendChild(methodInput); form.appendChild(csrfInput);
            document.body.appendChild(form); form.submit();
        }
    };

    if (currentSubView === 'System') {
        return (
            <SystemStatus
                incomingConfigs={smtpConfig}
                activeProvider={props.activeProvider}
                allConfigs={props.allConfigs}
            />
        );
    }

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                {isAdmin && (
                    <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff', mb: 4 }}>
                        <Stack direction="row" spacing={1} sx={{ mb: 3, alignItems: 'center' }}>
                            <Shield sx={{ color: '#5e35b1' }} />
                            <Typography variant="h6" sx={{ fontWeight: 700, color: '#5e35b1' }}>
                                System Administration
                            </Typography>
                        </Stack>
                        <Divider sx={{ my: 1 }} />
                        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', p: 1 }}>
                            <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>System Service Accounts</Typography>
                            <Button variant="contained" size="small" sx={{ bgcolor: '#5e35b1' }}
                                onClick={() => navigateTo('/admin/system_accounts/new')}>
                                + Create New Account
                            </Button>
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
                                            <TableCell><code>{app.uid ? `${app.uid.substring(0, 6)}••••••` : 'No UID'}</code></TableCell>
                                            <TableCell align="right">
                                                <Button variant="outlined" size="small" onClick={() => navigateTo(`/admin/system_accounts/${app.id}`)}>View</Button>
                                                <Button variant="outlined" startIcon={<DeleteIcon />} size="small" color="error"
                                                    onClick={() => handleDeleteAccount(app.id)} sx={{ ml: 1 }}>Revoke</Button>
                                            </TableCell>
                                        </TableRow>
                                    ))}
                                </TableBody>
                            </Table>
                        </TableContainer>
                    </Paper>
                )}

                {isAdmin && (
                    <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 3, bgcolor: '#ffffff' }}>
                        <Alert severity="info" sx={{ borderRadius: 2 }}>
                            Storage Backend Configuration has moved to
                            <strong> System Settings → Storage & Edge → Origin Storage</strong>.
                        </Alert>
                        <Box sx={{ mt: 2 }}>
                            <Button
                                variant="contained"
                                sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                                onClick={() => navigateTo('/settings/system')}
                            >
                                Go to System Settings
                            </Button>
                        </Box>
                    </Paper>
                )}
            </Box>
        </Box>
    );
}
