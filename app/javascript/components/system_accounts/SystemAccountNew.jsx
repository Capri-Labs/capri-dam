import React, { useState } from 'react';
import {
    Box, CssBaseline, Toolbar, Typography, Paper,
    TextField, Button, Stack, CircularProgress
} from '@mui/material';
import { ArrowBack, CheckCircleOutlined } from '@mui/icons-material';
import Sidebar from '../Sidebar';

export default function SystemAccountNew() {
    const [name, setName] = useState('');
    const [loading, setLoading] = useState(false);

    const handleSubmit = () => {
        setLoading(true);
        // Form will naturally POST to /admin/system_accounts
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />

            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                <Toolbar />

                <Stack spacing={3} sx={{ maxWidth: 600, mx: 'auto', mt: 4 }}>
                    <Box>
                        <Button
                            startIcon={<ArrowBack />}
                            onClick={() => window.location.href = '/settings'}
                            sx={{ color: '#5e35b1', mb: 2, textTransform: 'none' }}
                        >
                            Back to Settings
                        </Button>
                        <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                            New Service Account
                        </Typography>
                        <Typography variant="body1" color="text.secondary">
                            Generate a secure Client ID and Secret for external API integrations.
                        </Typography>
                    </Box>

                    <Paper elevation={0} sx={{ p: 4, border: '1px solid #e3e8ef', borderRadius: 4 }}>
                        {/* ACTION: /admin/system_accounts
                            METHOD: POST
                        */}
                        <form
                            action="/admin/system_accounts"
                            method="post"
                            onSubmit={handleSubmit}
                        >
                            {/* CSRF Token for Rails Security */}
                            <input
                                type="hidden"
                                name="authenticity_token"
                                value={document.querySelector('[name="csrf-token"]').content}
                            />

                            <Stack spacing={3}>
                                <TextField
                                    name="doorkeeper_application[name]"
                                    label="Application Name"
                                    placeholder="e.g. Marketing Site API"
                                    fullWidth
                                    required
                                    value={name}
                                    onChange={(e) => setName(e.target.value)}
                                    autoFocus
                                    sx={{ '& .MuiOutlinedInput-root': { borderRadius: 2 } }}
                                />

                                <Box sx={{ display: 'flex', gap: 2, pt: 2 }}>
                                    <Button
                                        type="submit"
                                        variant="contained"
                                        disabled={loading || !name}
                                        startIcon={loading ? <CircularProgress size={20} color="inherit" /> : <CheckCircleOutlined />}
                                        sx={{
                                            bgcolor: '#5e35b1',
                                            px: 4,
                                            borderRadius: 2,
                                            '&:hover': { bgcolor: '#4527a0' }
                                        }}
                                    >
                                        {loading ? 'Generating...' : 'Generate Credentials'}
                                    </Button>
                                    <Button
                                        variant="text"
                                        onClick={() => window.location.href = '/settings'}
                                        sx={{ color: 'text.secondary', textTransform: 'none' }}
                                    >
                                        Cancel
                                    </Button>
                                </Box>
                            </Stack>
                        </form>
                    </Paper>
                </Stack>
            </Box>
        </Box>
    );
}