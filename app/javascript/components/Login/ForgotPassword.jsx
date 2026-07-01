import React, { useState, useEffect } from 'react';
import {
    Dialog,
    DialogTitle,
    DialogContent,
    DialogContentText,
    DialogActions,
    Button,
    TextField,
    Alert,
    Box,
} from '@mui/material';
import MarkEmailReadIcon from '@mui/icons-material/MarkEmailRead';
import { useTranslation } from 'react-i18next';

const getFallbackCsrfToken = () => document.querySelector('[name="csrf-token"]')?.content || '';

export default function ForgotPassword({ open, onClose, initialEmail, csrfToken }) {
    const { t } = useTranslation();
    const [email, setEmail] = useState('');
    const [errorMsg, setErrorMsg] = useState(null);
    const [successMsg, setSuccessMsg] = useState(null);
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        if (open) {
            setEmail(initialEmail || '');
            setErrorMsg(null);
            setSuccessMsg(null);
        }
    }, [open, initialEmail]);

    const handleSubmit = async (event) => {
        event.preventDefault();
        setErrorMsg(null);
        setSuccessMsg(null);
        setLoading(true);

        try {
            const response = await fetch('/users/password.json', {
                method: 'POST',
                headers: {
                    Accept: 'application/json',
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken || getFallbackCsrfToken(),
                },
                body: JSON.stringify({ user: { email } }),
            });

            if (response.ok) {
                setSuccessMsg(t('login.forgotSuccess'));
            } else {
                setErrorMsg(t('login.forgotFailed'));
            }
        } catch (_error) {
            setErrorMsg(t('login.forgotNetworkError'));
        } finally {
            setLoading(false);
        }
    };

    const handleClose = () => {
        if (!loading) {
            onClose();
        }
    };

    return (
        <Dialog
            open={open}
            onClose={handleClose}
            maxWidth="xs"
            fullWidth
            aria-labelledby="forgot-password-dialog-title"
            aria-describedby="forgot-password-dialog-description"
        >
            <DialogTitle id="forgot-password-dialog-title" sx={{ display: 'flex', alignItems: 'center', gap: 1, fontWeight: 700 }}>
                <MarkEmailReadIcon sx={{ color: '#8b5cf6' }} />
                {t('login.forgotTitle')}
            </DialogTitle>

            <DialogContent>
                <DialogContentText id="forgot-password-dialog-description" sx={{ mb: 2, fontSize: '0.875rem' }}>
                    {t('login.forgotDescription')}
                </DialogContentText>

                {errorMsg && <Alert severity="error" sx={{ mb: 2 }}>{errorMsg}</Alert>}
                {successMsg && <Alert severity="success" sx={{ mb: 2 }}>{successMsg}</Alert>}

                {!successMsg && (
                    <Box component="form" id="forgot-password-form" onSubmit={handleSubmit}>
                        <TextField
                            required
                            fullWidth
                            autoFocus
                            label={t('login.emailLabel')}
                            type="email"
                            value={email}
                            onChange={(event) => setEmail(event.target.value)}
                            disabled={loading}
                            slotProps={{
                                htmlInput: {
                                    'aria-label': t('login.emailLabel'),
                                },
                            }}
                        />
                    </Box>
                )}
            </DialogContent>

            <DialogActions sx={{ px: 3, pb: 3 }}>
                <Button onClick={handleClose} color="inherit" disabled={loading} aria-label={t('login.close')}>
                    {t('login.close')}
                </Button>
                {!successMsg && (
                    <Button
                        type="submit"
                        form="forgot-password-form"
                        variant="contained"
                        disabled={loading}
                        aria-label={t('login.sendResetLink')}
                        sx={{ bgcolor: '#8b5cf6' }}
                    >
                        {loading ? t('common.loading') : t('login.sendResetLink')}
                    </Button>
                )}
            </DialogActions>
        </Dialog>
    );
}
