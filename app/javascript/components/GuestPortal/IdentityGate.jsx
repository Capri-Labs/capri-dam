import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Alert, Box, Button, Dialog, DialogActions, DialogContent, DialogTitle,
    Stack, TextField, Typography,
} from '@mui/material';

/**
 * Asks a partner who they are before they collect files.
 *
 * This is attribution, not authentication — the address is self-asserted and
 * never verified. It exists so the download log reads "Priya at the agency"
 * rather than an IP address, which is the difference between an audit trail
 * somebody can act on and one they cannot.
 */
export default function IdentityGate({ open, onSubmit, onDismiss }) {
    const { t } = useTranslation();
    const [email, setEmail] = useState('');
    const [name, setName] = useState('');
    const [error, setError] = useState(null);
    const [busy, setBusy] = useState(false);

    const submit = async (event) => {
        event.preventDefault();
        setBusy(true);
        setError(null);
        try {
            await onSubmit({ email, name });
        } catch (e) {
            setError(e.message);
        } finally {
            setBusy(false);
        }
    };

    return (
        <Dialog open={open} onClose={onDismiss} maxWidth="xs" fullWidth>
            <DialogTitle>{t('portal.identityTitle')}</DialogTitle>
            <Box component="form" onSubmit={submit}>
                <DialogContent>
                    <Stack spacing={2}>
                        <Typography variant="body2" color="text.secondary">
                            {t('portal.identityHint')}
                        </Typography>

                        {error && <Alert severity="error">{error}</Alert>}

                        <TextField
                            type="email"
                            label={t('portal.email')}
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                            required
                            autoFocus
                            fullWidth
                            slotProps={{ htmlInput: { 'data-testid': 'portal-identity-email' } }}
                        />
                        <TextField
                            label={t('portal.name')}
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            fullWidth
                        />
                    </Stack>
                </DialogContent>
                <DialogActions>
                    <Button onClick={onDismiss}>{t('portal.later')}</Button>
                    <Button type="submit" variant="contained" disabled={busy || !email}>
                        {t('portal.continue')}
                    </Button>
                </DialogActions>
            </Box>
        </Dialog>
    );
}
