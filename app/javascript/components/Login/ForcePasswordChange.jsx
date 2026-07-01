import React, { useMemo, useState } from 'react';
import {
    Box,
    TextField,
    Button,
    Typography,
    Avatar,
    Alert,
    LinearProgress,
} from '@mui/material';
import LockResetIcon from '@mui/icons-material/LockReset';
import { useTranslation } from 'react-i18next';

const getFallbackCsrfToken = () => document.querySelector('[name="csrf-token"]')?.content || '';

export default function ForcePasswordChange({ email, tempPassword, csrfToken }) {
    const { t } = useTranslation();
    const [newPassword, setNewPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    const [errorMsg, setErrorMsg] = useState(null);
    const [loading, setLoading] = useState(false);

    const passwordChecks = useMemo(() => ({
        hasMinimumLength: newPassword.length >= 8,
        hasUppercase: /[A-Z]/.test(newPassword),
        hasNumber: /\d/.test(newPassword),
    }), [newPassword]);

    const passwordStrength = (Object.values(passwordChecks).filter(Boolean).length / 3) * 100;
    const isPasswordStrong = Object.values(passwordChecks).every(Boolean);

    const handleSubmit = async (event) => {
        event.preventDefault();
        setErrorMsg(null);

        if (newPassword !== confirmPassword) {
            setErrorMsg(t('login.passwordMismatch'));
            return;
        }

        if (!isPasswordStrong) {
            setErrorMsg(t('login.passwordTooWeak'));
            return;
        }

        setLoading(true);

        try {
            const response = await fetch('/users/force_password_update.json', {
                method: 'POST',
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken || getFallbackCsrfToken(),
                },
                body: JSON.stringify({
                    email,
                    current_password: tempPassword,
                    new_password: newPassword,
                    new_password_confirmation: confirmPassword,
                }),
            });

            const data = await response.json();

            if (response.ok && data.success) {
                window.location.href = '/';
            } else {
                setErrorMsg(data.error || t('login.loginFailed'));
            }
        } catch (_error) {
            setErrorMsg(t('login.networkError'));
        } finally {
            setLoading(false);
        }
    };

    return (
        <>
            <Avatar sx={{ m: 1, bgcolor: '#f59e0b', width: 56, height: 56 }}>
                <LockResetIcon fontSize="large" />
            </Avatar>
            <Typography component="h1" variant="h5" align="center" sx={{ fontWeight: 700, mb: 1 }}>
                {t('login.forceTitle')}
            </Typography>
            <Typography variant="body2" align="center" color="text.secondary" sx={{ mb: 3 }}>
                {t('login.forceSubtitle')}
            </Typography>

            {errorMsg && <Alert severity="error" sx={{ width: '100%', mb: 2 }}>{errorMsg}</Alert>}

            <Box component="form" onSubmit={handleSubmit} sx={{ width: '100%' }} aria-label={t('login.updatePassword')}>
                <TextField
                    margin="normal"
                    fullWidth
                    label={t('login.tempPassword')}
                    type="password"
                    value={tempPassword}
                    disabled
                    slotProps={{
                        htmlInput: { 'aria-label': t('login.tempPassword') },
                    }}
                />
                <TextField
                    margin="normal"
                    required
                    fullWidth
                    label={t('login.newPassword')}
                    type="password"
                    autoComplete="new-password"
                    autoFocus
                    value={newPassword}
                    onChange={(event) => setNewPassword(event.target.value)}
                    disabled={loading}
                    error={Boolean(newPassword) && !isPasswordStrong}
                    helperText={Boolean(newPassword) && !isPasswordStrong ? t('login.passwordTooWeak') : ' '}
                    slotProps={{
                        htmlInput: { 'aria-label': t('login.newPassword') },
                    }}
                />
                <LinearProgress
                    variant="determinate"
                    value={passwordStrength}
                    color={isPasswordStrong ? 'success' : 'warning'}
                    aria-label={t('login.passwordTooWeak')}
                    sx={{ mt: 1, mb: 2, height: 8, borderRadius: 999 }}
                />
                <TextField
                    margin="normal"
                    required
                    fullWidth
                    label={t('login.confirmPassword')}
                    type="password"
                    autoComplete="new-password"
                    value={confirmPassword}
                    onChange={(event) => setConfirmPassword(event.target.value)}
                    disabled={loading}
                    error={Boolean(confirmPassword) && confirmPassword !== newPassword}
                    helperText={Boolean(confirmPassword) && confirmPassword !== newPassword ? t('login.passwordMismatch') : ' '}
                    slotProps={{
                        htmlInput: { 'aria-label': t('login.confirmPassword') },
                    }}
                />
                <Button
                    type="submit"
                    fullWidth
                    variant="contained"
                    color="warning"
                    disabled={loading}
                    aria-label={t('login.updatePassword')}
                    sx={{ mt: 3, mb: 2, py: 1.5, fontWeight: 'bold' }}
                >
                    {loading ? t('login.updating') : t('login.updatePassword')}
                </Button>
            </Box>
        </>
    );
}
