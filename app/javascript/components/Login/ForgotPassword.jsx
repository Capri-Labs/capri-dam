import React, { useState, useEffect } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogContentText,
    DialogActions, Button, TextField, Alert, Box
} from '@mui/material';
import MarkEmailReadIcon from '@mui/icons-material/MarkEmailRead';

export default function ForgotPassword({ open, onClose, initialEmail }) {
    const [email, setEmail] = useState('');
    const [errorMsg, setErrorMsg] = useState(null);
    const [successMsg, setSuccessMsg] = useState(null);
    const [loading, setLoading] = useState(false);

    // Pre-fill the email if they already typed it in the login screen
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

        if (!email) {
            setErrorMsg("Please enter your email address.");
            return;
        }

        setLoading(true);

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const response = await fetch('/users/password.json', {
                method: 'POST',
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken,
                },
                body: JSON.stringify({ user: { email } }),
            });

            if (response.ok) {
                setSuccessMsg("If your email exists in our system, you will receive a password recovery link shortly.");
            } else {
                setErrorMsg("Failed to request password reset. Please try again.");
            }
        } catch (err) {
            setErrorMsg("A network error occurred.");
        } finally {
            setLoading(false);
        }
    };

    return (
        <Dialog open={open} onClose={!loading ? onClose : null} maxWidth="xs" fullWidth>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1, fontWeight: 700 }}>
                <MarkEmailReadIcon sx={{ color: '#8b5cf6' }} /> Reset Password
            </DialogTitle>

            <DialogContent>
                <DialogContentText sx={{ mb: 2, fontSize: '0.875rem' }}>
                    Enter the email associated with your account and we will send you a link to reset your password.
                </DialogContentText>

                {errorMsg && <Alert severity="error" sx={{ mb: 2 }}>{errorMsg}</Alert>}
                {successMsg && <Alert severity="success" sx={{ mb: 2 }}>{successMsg}</Alert>}

                {!successMsg && (
                    <Box component="form" id="forgot-password-form" onSubmit={handleSubmit}>
                        <TextField
                            required fullWidth autoFocus
                            label="Email Address"
                            type="email"
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                            disabled={loading}
                        />
                    </Box>
                )}
            </DialogContent>

            <DialogActions sx={{ px: 3, pb: 3 }}>
                <Button onClick={onClose} color="inherit" disabled={loading}>
                    Close
                </Button>
                {!successMsg && (
                    <Button type="submit" form="forgot-password-form" variant="contained" disabled={loading} sx={{ bgcolor: '#8b5cf6' }}>
                        Send Reset Link
                    </Button>
                )}
            </DialogActions>
        </Dialog>
    );
}