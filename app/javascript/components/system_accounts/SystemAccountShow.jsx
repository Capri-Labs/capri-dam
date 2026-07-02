import React from 'react';
import { Box, CssBaseline,
    Toolbar, Typography, Paper,
    TextField, Button, Stack,
    Alert, AlertTitle, IconButton,
    InputAdornment, Tooltip } from '@mui/material';
import { Key, ArrowBack, DeleteForever, ContentCopy, Check } from '@mui/icons-material';
import Sidebar from '../Sidebar';

export default function SystemAccountShow(props) {
    const app = JSON.parse(props.appJson || '{}');
    const [copiedUid, setCopiedUid] = React.useState(false);
    const [copiedSecret, setCopiedSecret] = React.useState(false);

    const handleRevoke = () => {
        if (window.confirm("Are you sure? This will immediately disable this Client ID and Secret. This action cannot be undone.")) {
            // Standard Rails UJS/Turbo delete request via JS
            const form = document.createElement('form');
            form.method = 'POST';
            form.action = `/admin/system_accounts/${app.id}`;
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

    const handleCopy = (text, type) => {
        if (!text) return;
        navigator.clipboard.writeText(text);

        if (type === 'uid') {
            setCopiedUid(true);
            setTimeout(() => setCopiedUid(false), 2000);
        } else {
            setCopiedSecret(true);
            setTimeout(() => setCopiedSecret(false), 2000);
        }
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />

            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                <Toolbar />

                <Stack spacing={3} sx={{ maxWidth: 800, mx: 'auto' }}>
                    <Typography variant="h4" sx={{ fontWeight: 700, display: 'flex', alignItems: 'center', gap: 1.5 }}>
                        <Key sx={{ color: '#5e35b1' }} /> Application Credentials
                    </Typography>

                    <Alert severity="error" variant="outlined" sx={{ borderRadius: 2, bgcolor: '#fff5f5' }}>
                        <AlertTitle sx={{ fontWeight: 700 }}>Security Warning</AlertTitle>
                        Please copy and store the secret in a secure vault immediately.
                    </Alert>

                    <Paper elevation={0} sx={{ p: 4, border: '1px solid #e3e8ef', borderRadius: 4 }}>
                        <Stack spacing={3}>
                            <Box>
                                <Typography variant="caption" sx={{ fontWeight: 700, color: 'text.secondary', textTransform: 'uppercase' }}>
                                    Application Name
                                </Typography>
                                <Typography variant="h6" sx={{ color: '#121926' }}>{app.name}</Typography>
                            </Box>

                            <Stack spacing={3}>
                                <TextField
                                    label="Client ID (UID)"
                                    value={app.uid || ''}
                                    fullWidth
                                    variant="filled" slotProps={{input: {
                                        readOnly: true,
                                        endAdornment: (
                                            <InputAdornment position="end">
                                                <Tooltip title={copiedUid ? "Copied!" : "Copy UID"}>
                                                    <IconButton onClick={() => handleCopy(app.uid, 'uid')} edge="end">
                                                        {copiedUid ? <Check color="success" fontSize="small" /> : <ContentCopy fontSize="small" />}
                                                    </IconButton>
                                                </Tooltip>
                                            </InputAdornment>
                                        ),
                                    } }}
                                />

                                {/* CLIENT SECRET FIELD */}
                                <TextField
                                    label="Client Secret"
                                    value={app.secret || ''}
                                    fullWidth
                                    variant="outlined"
                                    color="warning"
                                    focused slotProps={{input: {
                                        readOnly: true,
                                        sx: { fontFamily: 'monospace', bgcolor: '#fffde7' },
                                        endAdornment: (
                                            <InputAdornment position="end">
                                                <Tooltip title={copiedSecret ? "Copied!" : "Copy Secret"}>
                                                    <IconButton onClick={() => handleCopy(app.secret, 'secret')} edge="end">
                                                        {copiedSecret ? <Check color="success" fontSize="small" /> : <ContentCopy fontSize="small" />}
                                                    </IconButton>
                                                </Tooltip>
                                            </InputAdornment>
                                        ),
                                    } }}
                                />
                            </Stack>
                        </Stack>
                    </Paper>

                    <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                        <Button
                            startIcon={<ArrowBack />}
                            onClick={() => window.location.href = '/settings'}
                            sx={{ color: '#5e35b1' }}
                        >
                            Back to Settings
                        </Button>

                        <Button
                            variant="outlined"
                            color="error"
                            startIcon={<DeleteForever />}
                            onClick={handleRevoke}
                            sx={{ borderRadius: 2 }}
                        >
                            Revoke Credentials
                        </Button>
                    </Box>
                </Stack>
            </Box>
        </Box>
    );
}