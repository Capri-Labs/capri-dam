import React, { useState } from 'react';
import {
    Box, TextField, Button, Typography, Paper, Avatar,
    CssBaseline, Divider, Alert, Link
} from '@mui/material';
import LockOutlinedIcon from '@mui/icons-material/LockOutlined';
import VpnKeyIcon from '@mui/icons-material/VpnKey';

// Import our new modular components
import ForgotPassword from './ForgotPassword';
import ForcePasswordChange from './ForcePasswordChange';

export default function Login() {
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [errorMsg, setErrorMsg] = useState(null);

    const [view, setView] = useState('login'); // 'login' or 'force_change'
    const [forgotModalOpen, setForgotModalOpen] = useState(false);

    const handleSubmit = async (event) => {
        event.preventDefault();
        setErrorMsg(null);

        const response = await fetch('/users/sign_in.json', {
            method: 'POST',
            headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
            },
            body: JSON.stringify({ user: { email, password } }),
        });

        const data = await response.json();

        if (response.ok && data.success) {
            if (data.force_password_change) {
                setView('force_change');
            } else {
                window.location.href = '/dashboard';
            }
        } else {
            setErrorMsg(data.error || 'Login failed. Please check your credentials.');
        }
    };

    const handleSSO = () => {
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = '/users/auth/keycloak_openid';

        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const csrfInput = document.createElement('input');
        csrfInput.type = 'hidden';
        csrfInput.name = 'authenticity_token';
        csrfInput.value = csrfToken;

        form.appendChild(csrfInput);
        document.body.appendChild(form);
        form.submit();
    };

    return (
        // Root container locked to exactly the viewport height. No body scrollbar.
        <Box sx={{ display: 'flex', height: '100vh', overflow: 'hidden' }}>
            <CssBaseline />

            {/* 71% LEFT SIDE: Marketing / Branding Canvas */}
            <Box
                sx={{
                    width: { xs: '0%', md: '71%' },
                    display: { xs: 'none', md: 'flex' }, // Hide entirely on mobile
                    backgroundImage: 'url(https://images.unsplash.com/photo-1550751827-4bd374c3f58b?q=80&w=2670&auto=format&fit=crop)',
                    backgroundRepeat: 'no-repeat',
                    backgroundSize: 'cover',
                    backgroundPosition: 'center',
                    position: 'relative',
                }}
            >
                <Box
                    sx={{
                        position: 'absolute', top: 0, bottom: 0, right: 0, left: 0,
                        backgroundColor: 'rgba(9, 14, 35, 0.7)',
                        background: 'linear-gradient(to right, rgba(9, 14, 35, 0.8) 0%, rgba(9, 14, 35, 0.4) 100%)',
                        display: 'flex', flexDirection: 'column', justifyContent: 'center', px: 8,
                    }}
                >
                    <Typography variant="h2" sx={{ color: 'white', fontWeight: 800, mb: 2, maxWidth: 600 }}>
                        Centralize your digital ecosystem.
                    </Typography>
                    <Typography variant="h6" sx={{ color: 'rgba(255,255,255,0.8)', fontWeight: 400, maxWidth: 500, lineHeight: 1.6 }}>
                        Manage metadata, automate approval workflows, and govern your enterprise assets securely from a single source of truth.
                    </Typography>
                </Box>
            </Box>

            {/* 29% RIGHT SIDE: Authentication Engine */}
            <Box
                component={Paper}
                elevation={12}
                square
                sx={{
                    width: { xs: '100%', md: '29%' },
                    minWidth: { md: '380px' }, // Prevents it from getting unreadably thin on awkward screen sizes
                    display: 'flex',
                    flexDirection: 'column',
                    justifyContent: 'center',
                    overflowY: 'auto' // ONLY this right panel will scroll if the form is tall
                }}
            >
                <Box sx={{ my: 8, mx: { xs: 4, xl: 6 }, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>

                    {view === 'login' ? (
                        <>
                            <Avatar sx={{ m: 1, bgcolor: '#3b82f6', width: 56, height: 56 }}>
                                <LockOutlinedIcon fontSize="large" />
                            </Avatar>
                            <Typography component="h1" variant="h5" sx={{ fontWeight: 700, mb: 1 }}>
                                Capri DAM
                            </Typography>
                            <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                                Welcome back. Please enter your details.
                            </Typography>

                            {errorMsg && <Alert severity="error" sx={{ width: '100%', mb: 2 }}>{errorMsg}</Alert>}

                            <Box component="form" onSubmit={handleSubmit} sx={{ width: '100%' }}>
                                <TextField
                                    margin="normal" required fullWidth label="Email Address"
                                    autoComplete="email" autoFocus
                                    value={email} onChange={(e) => setEmail(e.target.value)}
                                />
                                <TextField
                                    margin="normal" required fullWidth label="Password" type="password"
                                    autoComplete="current-password"
                                    value={password} onChange={(e) => setPassword(e.target.value)}
                                />

                                <Box sx={{ display: 'flex', justifyContent: 'flex-end', mt: 1 }}>
                                    <Link href="#" variant="body2" underline="hover" onClick={(e) => { e.preventDefault(); setForgotModalOpen(true); }}>
                                        Forgot password?
                                    </Link>
                                </Box>

                                <Button type="submit" fullWidth variant="contained" sx={{ mt: 3, mb: 2, py: 1.5, fontWeight: 'bold', bgcolor: '#1e293b' }}>
                                    Sign In
                                </Button>

                                <Divider sx={{ my: 3 }}><Typography variant="body2" sx={{ color: 'text.secondary' }}>OR</Typography></Divider>

                                <Button
                                    fullWidth variant="outlined" color="primary" startIcon={<VpnKeyIcon />}
                                    onClick={handleSSO} sx={{ py: 1.5, fontWeight: 'bold', textTransform: 'none' }}
                                >
                                    Sign in with Enterprise SSO
                                </Button>
                            </Box>
                        </>
                    ) : (
                        <ForcePasswordChange email={email} tempPassword={password} />
                    )}

                </Box>
            </Box>

            {/* The Floating Recovery Modal */}
            <ForgotPassword
                open={forgotModalOpen}
                onClose={() => setForgotModalOpen(false)}
                initialEmail={email}
            />
        </Box>
    );
}