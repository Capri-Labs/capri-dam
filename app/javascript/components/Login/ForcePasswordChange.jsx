import React, { useState } from 'react';
import { Box, TextField, Button, Typography, Avatar, Alert } from '@mui/material';
import LockResetIcon from '@mui/icons-material/LockReset';

export default function ForcePasswordChange({ email, tempPassword }) {
    const [newPassword, setNewPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    const [errorMsg, setErrorMsg] = useState(null);
    const [loading, setLoading] = useState(false);

    const handleSubmit = async (event) => {
        event.preventDefault();
        setErrorMsg(null);

        if (newPassword !== confirmPassword) {
            setErrorMsg("New passwords do not match.");
            return;
        }

        setLoading(true);

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const response = await fetch('/users/force_password_update.json', {
                method: 'POST',
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken,
                },
                body: JSON.stringify({
                    email: email,
                    current_password: tempPassword,
                    new_password: newPassword,
                    new_password_confirmation: confirmPassword
                }),
            });

            const data = await response.json();

            if (response.ok && data.success) {
                // Backend signs us in automatically on success
                window.location.href = '/dashboard';
            } else {
                setErrorMsg(data.error || "Failed to update password.");
            }
        } catch (err) {
            setErrorMsg("A network error occurred.");
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
                Action Required
            </Typography>
            <Typography variant="body2" align="center" color="textSecondary" sx={{ mb: 3 }}>
                This is your first time logging in. For security reasons, you must change your temporary password.
            </Typography>

            {errorMsg && <Alert severity="error" sx={{ width: '100%', mb: 2 }}>{errorMsg}</Alert>}

            <Box component="form" onSubmit={handleSubmit} sx={{ width: '100%' }}>
                <TextField
                    margin="normal" fullWidth label="Temporary Password" type="password"
                    value={tempPassword} disabled
                />
                <TextField
                    margin="normal" required fullWidth label="New Password" type="password" autoFocus
                    value={newPassword} onChange={(e) => setNewPassword(e.target.value)} disabled={loading}
                />
                <TextField
                    margin="normal" required fullWidth label="Confirm New Password" type="password"
                    value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} disabled={loading}
                />
                <Button type="submit" fullWidth variant="contained" color="warning" disabled={loading} sx={{ mt: 4, mb: 2, py: 1.5, fontWeight: 'bold' }}>
                    {loading ? 'Updating...' : 'Update Password & Sign In'}
                </Button>
            </Box>
        </>
    );
}