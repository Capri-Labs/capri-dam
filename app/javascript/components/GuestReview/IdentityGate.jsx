import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Box, Button, Dialog, DialogActions, DialogContent, DialogContentText,
    DialogTitle, Stack, TextField,
} from '@mui/material';

/**
 * Asks an external reviewer who they are before they comment.
 *
 * This is an *identity prompt, not a login*. Nothing is verified and nothing
 * is authorised on the answer — the link is the credential. It exists so that
 * feedback arrives as "Priya at the client" rather than "Anonymous", which is
 * the difference between actionable review notes and a list of unattributable
 * complaints.
 *
 * It is therefore deliberately dismissible when the link does not require it:
 * blocking a reviewer who just wants to read would be gatekeeping for no
 * security benefit.
 */
export default function IdentityGate({ open, required, onIdentify, onSkip }) {
    const { t } = useTranslation();
    const [email, setEmail] = useState('');
    const [name, setName] = useState('');
    const [error, setError] = useState(null);
    const [saving, setSaving] = useState(false);

    const submit = async (event) => {
        event.preventDefault();
        setSaving(true);
        setError(null);
        try {
            await onIdentify({ email: email.trim(), name: name.trim() });
        } catch (e) {
            setError(e.message);
        } finally {
            setSaving(false);
        }
    };

    return (
        <Dialog
            open={open}
            maxWidth="xs"
            fullWidth
            // A required prompt cannot be dismissed by clicking away, or the
            // reviewer would land in a state where every comment is rejected
            // with no visible explanation.
            onClose={required ? undefined : onSkip}
            slotProps={{ paper: { component: 'form', onSubmit: submit } }}
        >
            <DialogTitle>{t('guestReview.identity.title')}</DialogTitle>
            <DialogContent>
                <DialogContentText sx={{ mb: 2, fontSize: '0.875rem' }}>
                    {t('guestReview.identity.description')}
                </DialogContentText>
                <Stack spacing={2}>
                    <TextField
                        autoFocus
                        required
                        type="email"
                        label={t('guestReview.identity.email')}
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        error={Boolean(error)}
                        helperText={error}
                        fullWidth
                        size="small"
                    />
                    <TextField
                        label={t('guestReview.identity.name')}
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        fullWidth
                        size="small"
                    />
                </Stack>
            </DialogContent>
            <DialogActions sx={{ px: 3, pb: 2 }}>
                {!required && (
                    <Button onClick={onSkip} color="inherit">
                        {t('guestReview.identity.skip')}
                    </Button>
                )}
                <Box sx={{ flex: 1 }} />
                <Button type="submit" variant="contained" disabled={saving || !email.trim()}>
                    {t('guestReview.identity.continue')}
                </Button>
            </DialogActions>
        </Dialog>
    );
}
