import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Dialog, DialogTitle, DialogContent, DialogActions, Button, Alert,
    TextField, Stack, InputAdornment, IconButton, Tooltip, Typography,
} from '@mui/material';
import { ContentCopy, CheckOutlined } from '@mui/icons-material';

/**
 * One-time reveal of a freshly minted portal credential.
 *
 * The server stores only a digest, so this dialog is the single moment the
 * token exists in a readable form anywhere. It is deliberately modal and
 * deliberately blunt about that: a copy button the user skips past is a portal
 * they have to revoke and recreate.
 */
export default function PortalTokenDialog({ open, portal, onClose }) {
    const { t } = useTranslation();
    const [copied, setCopied] = useState(false);

    const url = portal?.url || '';

    const handleCopy = async () => {
        try {
            await navigator.clipboard.writeText(url);
            setCopied(true);
        } catch {
            // Clipboard access can be denied or simply absent (insecure origin).
            // The field is selectable, so a manual copy is always possible.
            setCopied(false);
        }
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
            <DialogTitle>{t('portalManager.token.title')}</DialogTitle>
            <DialogContent>
                <Stack spacing={2} sx={{ mt: 1 }}>
                    <Alert severity="warning">{t('portalManager.token.warning')}</Alert>

                    {portal?.name && (
                        <Typography variant="body2" color="text.secondary">
                            {portal.name}
                        </Typography>
                    )}

                    <TextField
                        label={t('portalManager.token.urlLabel')}
                        value={url}
                        fullWidth
                        multiline
                        slotProps={{
                            input: {
                                readOnly: true,
                                endAdornment: (
                                    <InputAdornment position="end">
                                        <Tooltip title={copied ? t('portalManager.token.copied') : t('portalManager.token.copy')}>
                                            <IconButton onClick={handleCopy} aria-label={t('portalManager.token.copy')}>
                                                {copied ? <CheckOutlined fontSize="small" /> : <ContentCopy fontSize="small" />}
                                            </IconButton>
                                        </Tooltip>
                                    </InputAdornment>
                                ),
                            },
                        }}
                    />
                </Stack>
            </DialogContent>
            <DialogActions>
                <Button onClick={onClose} variant="contained">{t('portalManager.token.done')}</Button>
            </DialogActions>
        </Dialog>
    );
}
