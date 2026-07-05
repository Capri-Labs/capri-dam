import React, { useEffect, useState } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Box, Typography, Button, CircularProgress, Stack,
    List, ListItemButton, ListItemIcon, ListItemText,
    Chip, Alert,
} from '@mui/material';
import { AccountTree, CheckCircle } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';

// Dialog invoked from the AssetGrid "Workflow" menu. Lets the user pick one of
// the *active* Workflow blueprints (from the Workflow Designer) and manually
// trigger it for the currently selected assets/folders via
// POST /api/v1/workflows/bulk_trigger. Folders are expanded server-side into
// every active asset they contain, recursively.
export default function TriggerWorkflowDialog({ open, onClose, selectedItems }) {
    const { t } = useTranslation();
    const notify = useNotify();
    const [workflows, setWorkflows] = useState([]);
    const [loading, setLoading] = useState(false);
    const [selected, setSelected] = useState(null);
    const [triggering, setTriggering] = useState(false);

    const assetCount = selectedItems?.assets?.length ?? 0;
    const folderCount = selectedItems?.folders?.length ?? 0;
    const totalCount = assetCount + folderCount;

    // Only re-fetch when the dialog opens — deliberately excluding `notify`/`t`
    // from the dependency array so a re-render (e.g. after selecting a
    // workflow) doesn't re-trigger the network request.
    useEffect(() => {
        if (!open) return;

        let cancelled = false;
        setSelected(null);
        setLoading(true);

        fetch('/workflows.json')
            .then((res) => res.json())
            .then((data) => {
                if (cancelled) return;
                setWorkflows((Array.isArray(data) ? data : []).filter((wf) => wf.status === 'active'));
            })
            .catch(() => {
                if (!cancelled) notify(t('triggerWorkflowDialog.loadError', 'Failed to load workflows.'), 'error');
            })
            .finally(() => {
                if (!cancelled) setLoading(false);
            });

        return () => { cancelled = true; };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [open]);

    const handleTrigger = async () => {
        if (!selected) return;
        setTriggering(true);

        const csrfToken = document.querySelector('[name="csrf-token"]')?.content;

        try {
            const res = await fetch('/api/v1/workflows/bulk_trigger', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({
                    workflow_id: selected.id,
                    asset_ids: selectedItems?.assets ?? [],
                    folder_ids: selectedItems?.folders ?? [],
                }),
            });
            const data = await res.json();

            if (!res.ok) {
                notify(data?.error || t('triggerWorkflowDialog.triggerError', 'Failed to trigger workflow.'), 'error');
                return;
            }

            notify(
                t('triggerWorkflowDialog.queued', '"{{name}}" queued for {{count}} asset(s).', {
                    name: selected.name,
                    count: data.queued ?? 0,
                }),
                'success'
            );
            onClose(true);
        } catch {
            notify(t('triggerWorkflowDialog.triggerError', 'Failed to trigger workflow.'), 'error');
        } finally {
            setTriggering(false);
        }
    };

    return (
        <Dialog open={open} onClose={() => onClose(false)} maxWidth="sm" fullWidth>
            <DialogTitle>{t('triggerWorkflowDialog.title', 'Trigger Workflow')}</DialogTitle>
            <DialogContent dividers>
                <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                    {t(
                        'triggerWorkflowDialog.description',
                        'Choose an active workflow to run for {{count}} selected item(s). Selected folders will include every asset inside them.',
                        { count: totalCount }
                    )}
                </Typography>

                {loading ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                        <CircularProgress size={28} />
                    </Box>
                ) : workflows.length === 0 ? (
                    <Alert severity="info">
                        {t('triggerWorkflowDialog.noActiveWorkflows', 'No active workflows available. Activate one in Workflow Designer first.')}
                    </Alert>
                ) : (
                    <List disablePadding data-testid="trigger-workflow-list">
                        {workflows.map((wf) => {
                            const isSelected = selected?.id === wf.id;
                            return (
                                <ListItemButton
                                    key={wf.id}
                                    selected={isSelected}
                                    onClick={() => setSelected(wf)}
                                    sx={{
                                        borderRadius: 2, mb: 0.5,
                                        border: isSelected ? '2px solid #4f46e5' : '1px solid #e2e8f0',
                                        bgcolor: isSelected ? '#eef2ff' : '#fff',
                                    }}
                                >
                                    <ListItemIcon sx={{ minWidth: 36 }}>
                                        <AccountTree sx={{ fontSize: 20, color: isSelected ? '#4f46e5' : '#94a3b8' }} />
                                    </ListItemIcon>
                                    <ListItemText
                                        primary={
                                            <Stack direction="row" spacing={1} alignItems="center">
                                                <Typography variant="body2" fontWeight={isSelected ? 700 : 500}>
                                                    {wf.name}
                                                </Typography>
                                                <Chip
                                                    size="small"
                                                    label={t('triggerWorkflowDialog.stepCount', '{{count}} step(s)', {
                                                        count: wf.workflow_steps?.length ?? 0,
                                                    })}
                                                    sx={{ height: 18, fontSize: '0.65rem', bgcolor: '#e0e7ff', color: '#3730a3' }}
                                                />
                                            </Stack>
                                        }
                                        secondary={wf.description}
                                    />
                                    {isSelected && <CheckCircle sx={{ color: '#4f46e5', ml: 1 }} />}
                                </ListItemButton>
                            );
                        })}
                    </List>
                )}
            </DialogContent>
            <DialogActions>
                <Button onClick={() => onClose(false)} disabled={triggering}>
                    {t('triggerWorkflowDialog.cancel', 'Cancel')}
                </Button>
                <Button
                    variant="contained"
                    onClick={handleTrigger}
                    disabled={!selected || triggering}
                    startIcon={triggering ? <CircularProgress size={16} color="inherit" /> : null}
                >
                    {t('triggerWorkflowDialog.trigger', 'Trigger')}
                </Button>
            </DialogActions>
        </Dialog>
    );
}
