import React, { useState } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Box, Typography, Button, TextField, Alert, List, ListItem, ListItemText,
} from '@mui/material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';

/**
 * "Publish Later" / "Unpublish Later" scheduling dialog, launched from the
 * Explorer's "Manage Publish" menu (next to Tools — see ExplorerTopBar).
 *
 * Immediate Publish/Unpublish never opens this dialog — it fires the bulk
 * request straight away (see `handlePublishSelected`/`handleUnpublishSelected`
 * in AssetExplorer). This dialog only handles the two "…Later" options,
 * where a future date/time must be picked before the request is sent.
 *
 * Publish/Unpublish only ever applies to assets (not folders) — see
 * `POST /api/v1/assets/:id/publish` / `/unpublish`. One request is issued
 * per selected asset id; per-item failures are reported without aborting
 * the rest of the batch.
 */
export default function PublishDialog({
    open,
    onClose,       // (needsRefresh: boolean) => void
    mode,          // 'publish' | 'unpublish'
    assetIds,      // [id, ...]
    itemNames,     // { [id]: name }
}) {
    const { t } = useTranslation();
    const notify = useNotify();

    const [scheduledAt, setScheduledAt] = useState('');
    const [submitting, setSubmitting] = useState(false);
    const [error, setError] = useState('');

    const csrfToken = () => document.querySelector('[name="csrf-token"]')?.content;

    const handleClose = () => {
        if (submitting) return;
        setScheduledAt('');
        setError('');
        onClose(false);
    };

    const handleSubmit = async () => {
        if (!scheduledAt) {
            setError(t('publishDialog.pickDateTimeRequired'));
            return;
        }

        // datetime-local has no timezone; interpret in the browser's local
        // zone (matches how MetadataExportManager's "Later" scheduling works)
        // and convert to an ISO8601 string the server can parse reliably.
        const iso = new Date(scheduledAt).toISOString();

        setSubmitting(true);
        setError('');

        try {
            const results = await Promise.all(assetIds.map((id) => fetch(`/api/v1/assets/${id}/${mode}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
                body: JSON.stringify({ scheduled_at: iso }),
            }).then((res) => ({ ok: res.ok, id }))));

            const failed = results.filter((r) => !r.ok);
            if (failed.length > 0) {
                notify(t('publishDialog.someItemsFailed', { count: failed.length }), 'warning');
            } else {
                notify(
                    mode === 'publish'
                        ? t('publishDialog.publishScheduled', { count: assetIds.length })
                        : t('publishDialog.unpublishScheduled', { count: assetIds.length }),
                    'success',
                );
            }
            setScheduledAt('');
            onClose(true);
        } catch {
            setError(t('publishDialog.scheduleError'));
        } finally {
            setSubmitting(false);
        }
    };

    const titleKey = mode === 'publish' ? 'publishDialog.publishLaterTitle' : 'publishDialog.unpublishLaterTitle';

    return (
        <Dialog open={open} onClose={handleClose} maxWidth="xs" fullWidth>
            <DialogTitle>{t(titleKey)}</DialogTitle>
            <DialogContent>
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 1 }}>
                    {error && <Alert severity="error">{error}</Alert>}

                    <Typography variant="body2" color="text.secondary">
                        {t('publishDialog.itemCount', { count: assetIds.length })}
                    </Typography>

                    <List dense sx={{ maxHeight: 160, overflowY: 'auto', bgcolor: '#f8fafc', borderRadius: 1 }}>
                        {assetIds.map((id) => (
                            <ListItem key={id} disableGutters sx={{ px: 1 }}>
                                <ListItemText primary={itemNames?.[id] ?? `#${id}`} />
                            </ListItem>
                        ))}
                    </List>

                    <TextField
                        type="datetime-local"
                        label={t('publishDialog.scheduledDateTime')}
                        size="small"
                        slotProps={{ inputLabel: { shrink: true }, htmlInput: { 'data-testid': 'publish-dialog-datetime' } }}
                        value={scheduledAt}
                        onChange={(e) => setScheduledAt(e.target.value)}
                    />
                </Box>
            </DialogContent>
            <DialogActions>
                <Button onClick={handleClose} disabled={submitting}>{t('publishDialog.cancel')}</Button>
                <Button
                    variant="contained"
                    onClick={handleSubmit}
                    disabled={submitting || assetIds.length === 0}
                    data-testid="publish-dialog-submit"
                >
                    {t('publishDialog.schedule')}
                </Button>
            </DialogActions>
        </Dialog>
    );
}
