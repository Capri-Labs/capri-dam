import React, { useState, useEffect } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions, Button,
    Box, Typography, TextField, InputAdornment, IconButton, CircularProgress, Alert
} from '@mui/material';
import { Share, ContentCopy, Check } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useCollections } from './CollectionContext';

/**
 * Mints a time-limited, signed public share link for a collection
 * (see {Collection#generate_share_token} / {Public::CollectionSharesController})
 * and lets the user copy it to their clipboard.
 */
export default function ShareCollectionDialog({ open, onClose, slug }) {
    const { t } = useTranslation();
    const { generateShareLink } = useCollections();
    const [loading, setLoading] = useState(false);
    const [shareData, setShareData] = useState(null);
    const [copied, setCopied] = useState(false);

    useEffect(() => {
        if (!open) {
            setShareData(null);
            setCopied(false);
            return;
        }
        let cancelled = false;
        setLoading(true);
        generateShareLink(slug).then((data) => {
            if (!cancelled) {
                setShareData(data);
                setLoading(false);
            }
        });
        return () => { cancelled = true; };
    }, [open, slug]);

    const handleCopy = async () => {
        if (!shareData?.url) return;
        try {
            await navigator.clipboard.writeText(shareData.url);
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
        } catch {
            // Clipboard API unavailable — user can still select & copy manually.
        }
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth data-testid="share-collection-dialog">
            <DialogTitle sx={{ fontWeight: 700, borderBottom: '1px solid #e2e8f0', pb: 2, display: 'flex', alignItems: 'center' }}>
                <Share sx={{ color: '#5e35b1', mr: 1.5 }} /> {t('collectionShare.title')}
            </DialogTitle>
            <DialogContent sx={{ p: 3, mt: 2 }}>
                {loading ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                        <CircularProgress size={28} sx={{ color: '#5e35b1' }} />
                    </Box>
                ) : shareData ? (
                    <>
                        <Typography variant="body2" color="textSecondary" sx={{ mb: 2 }}>
                            {t('collectionShare.description')}
                        </Typography>
                        <TextField
                            fullWidth
                            value={shareData.url}
                            slotProps={{
                                htmlInput: { readOnly: true, 'data-testid': 'share-collection-url-input' },
                                input: {
                                    readOnly: true,
                                    endAdornment: (
                                        <InputAdornment position="end">
                                            <IconButton onClick={handleCopy} data-testid="share-collection-copy-button" edge="end">
                                                {copied ? <Check sx={{ color: '#16a34a' }} /> : <ContentCopy />}
                                            </IconButton>
                                        </InputAdornment>
                                    ),
                                },
                            }}
                        />
                        {copied && (
                            <Alert severity="success" sx={{ mt: 2 }}>{t('collectionShare.copied')}</Alert>
                        )}
                        <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 2 }}>
                            {t('collectionShare.expiresAt', { date: new Date(shareData.expires_at).toLocaleDateString() })}
                        </Typography>
                    </>
                ) : (
                    <Alert severity="error">{t('collectionShare.error')}</Alert>
                )}
            </DialogContent>
            <DialogActions sx={{ p: 2 }}>
                <Button onClick={onClose} color="inherit">{t('collectionShare.close')}</Button>
            </DialogActions>
        </Dialog>
    );
}
