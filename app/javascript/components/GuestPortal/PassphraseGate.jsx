import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Alert, Box, Button, Paper, Stack, TextField, Typography,
} from '@mui/material';

/**
 * The passphrase gate.
 *
 * Shown when the portal is protected and this session has not cleared it. The
 * failure message never distinguishes "wrong passphrase" from "no such link",
 * because the server does not either.
 */
export default function PassphraseGate({ onUnlock, accent }) {
    const { t } = useTranslation();
    const [passphrase, setPassphrase] = useState('');
    const [error, setError] = useState(null);
    const [busy, setBusy] = useState(false);

    const submit = async (event) => {
        event.preventDefault();
        setBusy(true);
        setError(null);
        try {
            await onUnlock(passphrase);
        } catch (e) {
            setError(e.message);
        } finally {
            setBusy(false);
        }
    };

    return (
        <Box sx={{ maxWidth: 420, mx: 'auto', mt: 10 }}>
            <Paper variant="outlined" sx={{ p: 3 }} data-testid="portal-passphrase-gate">
                <Stack spacing={2} component="form" onSubmit={submit}>
                    <Typography variant="h6" fontWeight={700}>{t('portal.passphraseTitle')}</Typography>
                    <Typography variant="body2" color="text.secondary">
                        {t('portal.passphraseHint')}
                    </Typography>

                    {error && <Alert severity="error">{error}</Alert>}

                    <TextField
                        type="password"
                        label={t('portal.passphraseLabel')}
                        value={passphrase}
                        onChange={(e) => setPassphrase(e.target.value)}
                        autoFocus
                        fullWidth
                        slotProps={{ htmlInput: { 'data-testid': 'portal-passphrase-input' } }}
                    />

                    <Button
                        type="submit"
                        variant="contained"
                        disabled={busy || !passphrase}
                        sx={{ bgcolor: accent, '&:hover': { bgcolor: accent, filter: 'brightness(0.92)' } }}
                    >
                        {t('portal.unlock')}
                    </Button>
                </Stack>
            </Paper>
        </Box>
    );
}
