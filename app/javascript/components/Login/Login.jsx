import React, { useState } from 'react';
import {
    Box,
    TextField,
    Button,
    Typography,
    Paper,
    Avatar,
    CssBaseline,
    Divider,
    Alert,
    Link,
} from '@mui/material';
import LockOutlinedIcon from '@mui/icons-material/LockOutlined';
import VpnKeyIcon from '@mui/icons-material/VpnKey';
import { useTranslation } from 'react-i18next';

import ForgotPassword from './ForgotPassword';
import ForcePasswordChange from './ForcePasswordChange';

const fallbackSsoPath = '/users/auth/keycloak_openid';

const getRootDataset = () => document.getElementById('root')?.dataset || {};

const getCsrfToken = () => (
    getRootDataset().csrfToken || document.querySelector('[name="csrf-token"]')?.content || ''
);

export default function Login() {
    const { t } = useTranslation();
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [errorMsg, setErrorMsg] = useState(null);
    const [loading, setLoading] = useState(false);
    const [view, setView] = useState('login');
    const [forgotModalOpen, setForgotModalOpen] = useState(false);

    const csrfToken = getCsrfToken();
    const ssoPath = getRootDataset().ssoPath || fallbackSsoPath;

    const translateLoginError = (error) => {
        if (error === 'Invalid email or password') {
            return t('login.invalidCredentials');
        }

        if (error === 'Account is deactivated.') {
            return t('login.accountDeactivated');
        }

        return error || t('login.loginFailed');
    };

    const handleSubmit = async (event) => {
        event.preventDefault();
        setErrorMsg(null);
        setLoading(true);

        try {
            const response = await fetch('/users/sign_in.json', {
                method: 'POST',
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken,
                },
                body: JSON.stringify({ user: { email, password } }),
            });

            const data = await response.json();

            if (response.ok && data.success) {
                if (data.force_password_change) {
                    setView('force_change');
                } else {
                    window.location.href = '/';
                }
            } else {
                setErrorMsg(translateLoginError(data.error));
            }
        } catch (_error) {
            setErrorMsg(t('login.networkError'));
        } finally {
            setLoading(false);
        }
    };

    const handleSSO = () => {
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = ssoPath;

        if (csrfToken) {
            const csrfInput = document.createElement('input');
            csrfInput.type = 'hidden';
            csrfInput.name = 'authenticity_token';
            csrfInput.value = csrfToken;
            form.appendChild(csrfInput);
        }

        document.body.appendChild(form);
        form.submit();
    };

    return (
        <Box component="main" sx={{ display: 'flex', height: '100vh', overflow: 'hidden' }}>
            <CssBaseline />

            <Box
                sx={{
                    width: { xs: '0%', md: '71%' },
                    display: { xs: 'none', md: 'flex' },
                    backgroundImage: 'url(https://images.unsplash.com/photo-1550751827-4bd374c3f58b?q=80&w=2670&auto=format&fit=crop)',
                    backgroundRepeat: 'no-repeat',
                    backgroundSize: 'cover',
                    backgroundPosition: 'center',
                    position: 'relative',
                }}
            >
                <Box
                    sx={{
                        position: 'absolute',
                        top: 0,
                        bottom: 0,
                        right: 0,
                        left: 0,
                        backgroundColor: 'rgba(9, 14, 35, 0.7)',
                        background: 'linear-gradient(to right, rgba(9, 14, 35, 0.8) 0%, rgba(9, 14, 35, 0.4) 100%)',
                        display: 'flex',
                        flexDirection: 'column',
                        justifyContent: 'center',
                        px: 8,
                    }}
                >
                    <Typography variant="h2" sx={{ color: 'white', fontWeight: 800, mb: 2, maxWidth: 600 }}>
                        {t('login.brandingHeadline')}
                    </Typography>
                    <Typography
                        variant="h6"
                        sx={{ color: 'rgba(255,255,255,0.8)', fontWeight: 400, maxWidth: 500, lineHeight: 1.6 }}
                    >
                        {t('login.brandingSubtitle')}
                    </Typography>
                </Box>
            </Box>

            <Box
                component={Paper}
                elevation={12}
                square
                sx={{
                    width: { xs: '100%', md: '29%' },
                    minWidth: { md: '380px' },
                    display: 'flex',
                    flexDirection: 'column',
                    justifyContent: 'center',
                    overflowY: 'auto',
                }}
            >
                <Box sx={{ my: 8, mx: { xs: 4, xl: 6 }, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                    {view === 'login' ? (
                        <>
                            <Avatar sx={{ m: 1, bgcolor: '#3b82f6', width: 56, height: 56 }}>
                                <LockOutlinedIcon fontSize="large" />
                            </Avatar>
                            <Typography component="h1" variant="h5" sx={{ fontWeight: 700, mb: 1 }}>
                                {t('login.title')}
                            </Typography>
                            <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
                                {t('login.subtitle')}
                            </Typography>

                            {errorMsg && <Alert severity="error" sx={{ width: '100%', mb: 2 }}>{errorMsg}</Alert>}

                            <Box component="form" onSubmit={handleSubmit} sx={{ width: '100%' }} aria-label={t('login.signIn')}>
                                <TextField
                                    margin="normal"
                                    required
                                    fullWidth
                                    label={t('login.emailLabel')}
                                    autoComplete="email"
                                    autoFocus
                                    value={email}
                                    onChange={(event) => setEmail(event.target.value)}
                                    disabled={loading}
                                    slotProps={{
                                        htmlInput: { 'aria-label': t('login.emailLabel') },
                                    }}
                                />
                                <TextField
                                    margin="normal"
                                    required
                                    fullWidth
                                    label={t('login.passwordLabel')}
                                    type="password"
                                    autoComplete="current-password"
                                    value={password}
                                    onChange={(event) => setPassword(event.target.value)}
                                    disabled={loading}
                                    slotProps={{
                                        htmlInput: { 'aria-label': t('login.passwordLabel') },
                                    }}
                                />

                                <Box sx={{ display: 'flex', justifyContent: 'flex-end', mt: 1 }}>
                                    <Link
                                        href="#"
                                        variant="body2"
                                        underline="hover"
                                        aria-label={t('login.forgotPassword')}
                                        onClick={(event) => {
                                            event.preventDefault();
                                            if (!loading) {
                                                setForgotModalOpen(true);
                                            }
                                        }}
                                    >
                                        {t('login.forgotPassword')}
                                    </Link>
                                </Box>

                                <Button
                                    type="submit"
                                    fullWidth
                                    variant="contained"
                                    disabled={loading}
                                    aria-label={t('login.signIn')}
                                    sx={{ mt: 3, mb: 2, py: 1.5, fontWeight: 'bold', bgcolor: '#1e293b' }}
                                >
                                    {loading ? t('login.signingIn') : t('login.signIn')}
                                </Button>

                                <Divider sx={{ my: 3 }} />

                                <Button
                                    fullWidth
                                    variant="outlined"
                                    color="primary"
                                    startIcon={<VpnKeyIcon />}
                                    onClick={handleSSO}
                                    disabled={loading}
                                    aria-label={t('login.ssoButton')}
                                    sx={{ py: 1.5, fontWeight: 'bold', textTransform: 'none' }}
                                >
                                    {t('login.ssoButton')}
                                </Button>
                            </Box>
                        </>
                    ) : (
                        <ForcePasswordChange email={email} tempPassword={password} csrfToken={csrfToken} />
                    )}
                </Box>
            </Box>

            <ForgotPassword
                open={forgotModalOpen}
                onClose={() => setForgotModalOpen(false)}
                initialEmail={email}
                csrfToken={csrfToken}
            />
        </Box>
    );
}
