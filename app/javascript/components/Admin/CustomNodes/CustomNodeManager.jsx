import React, { useCallback, useEffect, useState } from 'react';
import {
    Box,
    Button,
    Chip,
    CssBaseline,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    IconButton,
    LinearProgress,
    MenuItem,
    Paper,
    Stack,
    Table,
    TableBody,
    TableCell,
    TableContainer,
    TableHead,
    TableRow,
    TextField,
    Tooltip,
    Typography,
} from '@mui/material';
import {
    AddCircleOutlineOutlined,
    BlockOutlined,
    CheckCircleOutlined,
    DeleteOutlined,
    ExtensionOutlined,
    RefreshOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

import { useNotify } from '../../../context/NotificationContext';

const getCsrfToken = () => document.querySelector('[name="csrf-token"]')?.content ?? '';

const STATUS_COLORS = {
    enabled: 'success',
    disabled: 'default',
    draft: 'warning',
};

const BLANK_FORM = {
    key: '',
    name: '',
    description: '',
    category: 'custom',
    color: '#6366f1',
    icon: 'extension',
    status: 'draft',
    endpoint_url: '',
    timeout_ms: 5000,
    auth_type: 'hmac',
    secret: '',
    outputs: '',
    config_schema: '[\n  { "key": "quality", "type": "string", "label": "Quality" }\n]',
};

export default function CustomNodeManager() {
    const { t } = useTranslation();
    const notify = useNotify();

    const [items, setItems] = useState([]);
    const [loading, setLoading] = useState(false);
    const [dialogOpen, setDialogOpen] = useState(false);
    const [form, setForm] = useState(BLANK_FORM);
    const [saving, setSaving] = useState(false);

    const fetchItems = useCallback(async () => {
        setLoading(true);
        try {
            const response = await fetch('/api/v1/custom_node_definitions', {
                headers: { Accept: 'application/json' },
            });
            const data = await response.json();
            if (!response.ok) throw new Error(data.error || 'Failed to load custom nodes');
            setItems(data.items || []);
        } catch (error) {
            notify(error.message || t('customNodes.notifications.loadFailed'), 'error');
        } finally {
            setLoading(false);
        }
    }, [notify, t]);

    useEffect(() => { fetchItems(); }, [fetchItems]);

    const setField = (key, value) => setForm((prev) => ({ ...prev, [key]: value }));

    const openCreate = () => {
        setForm(BLANK_FORM);
        setDialogOpen(true);
    };

    const buildPayload = () => {
        let configSchema;
        try {
            configSchema = JSON.parse(form.config_schema || '[]');
        } catch {
            throw new Error(t('customNodes.notifications.invalidSchema'));
        }
        const outputs = (form.outputs || '')
            .split(',')
            .map((o) => o.trim())
            .filter(Boolean);
        return {
            custom_node_definition: {
                key: form.key,
                name: form.name,
                description: form.description,
                category: form.category,
                color: form.color,
                icon: form.icon,
                status: form.status,
                config_schema: configSchema,
                runtime: {
                    endpoint_url: form.endpoint_url,
                    timeout_ms: Number(form.timeout_ms) || 5000,
                    auth_type: form.auth_type,
                    secret: form.secret,
                    outputs,
                },
            },
        };
    };

    const submit = async () => {
        setSaving(true);
        try {
            const payload = buildPayload();
            const response = await fetch('/api/v1/custom_node_definitions', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': getCsrfToken(),
                },
                body: JSON.stringify(payload),
            });
            const data = await response.json();
            if (!response.ok) {
                throw new Error((data.errors && data.errors.join(', ')) || 'Save failed');
            }
            notify(t('customNodes.notifications.created'), 'success');
            setDialogOpen(false);
            await fetchItems();
        } catch (error) {
            notify(error.message || t('customNodes.notifications.saveFailed'), 'error');
        } finally {
            setSaving(false);
        }
    };

    const toggleStatus = async (definition) => {
        const action = definition.status === 'enabled' ? 'disable' : 'enable';
        try {
            const response = await fetch(`/api/v1/custom_node_definitions/${definition.id}/${action}`, {
                method: 'POST',
                headers: { 'X-CSRF-Token': getCsrfToken() },
            });
            const data = await response.json();
            if (!response.ok) {
                throw new Error((data.errors && data.errors.join(', ')) || 'Action failed');
            }
            notify(
                t(action === 'enable' ? 'customNodes.notifications.enabled' : 'customNodes.notifications.disabled'),
                action === 'enable' ? 'success' : 'warning',
            );
            await fetchItems();
        } catch (error) {
            notify(error.message || t('customNodes.notifications.actionFailed'), 'error');
        }
    };

    const remove = async (definition) => {
        // eslint-disable-next-line no-alert
        if (!window.confirm(t('customNodes.confirmDelete', { name: definition.name }))) return;
        try {
            const response = await fetch(`/api/v1/custom_node_definitions/${definition.id}`, {
                method: 'DELETE',
                headers: { 'X-CSRF-Token': getCsrfToken() },
            });
            if (!response.ok && response.status !== 204) {
                const data = await response.json().catch(() => ({}));
                throw new Error(data.error || 'Delete failed');
            }
            notify(t('customNodes.notifications.deleted'), 'warning');
            await fetchItems();
        } catch (error) {
            notify(error.message || t('customNodes.notifications.actionFailed'), 'error');
        }
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f8fafc', minHeight: '100vh' }}>
            <CssBaseline />
            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 3, gap: 2, flexWrap: 'wrap' }}>
                    <Box>
                        <Typography variant="h5" fontWeight={800} sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <ExtensionOutlined color="primary" /> {t('customNodes.title')}
                        </Typography>
                        <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5, maxWidth: 720 }}>
                            {t('customNodes.subtitle')}
                        </Typography>
                    </Box>
                    <Stack direction="row" spacing={1}>
                        <Button startIcon={<RefreshOutlined />} onClick={fetchItems} variant="outlined">
                            {t('customNodes.refresh')}
                        </Button>
                        <Button startIcon={<AddCircleOutlineOutlined />} onClick={openCreate} variant="contained">
                            {t('customNodes.register')}
                        </Button>
                    </Stack>
                </Box>

                {loading && <LinearProgress sx={{ mb: 2 }} />}

                <TableContainer component={Paper} variant="outlined">
                    <Table>
                        <TableHead>
                            <TableRow>
                                <TableCell>{t('customNodes.colName')}</TableCell>
                                <TableCell>{t('customNodes.colKey')}</TableCell>
                                <TableCell>{t('customNodes.colEndpoint')}</TableCell>
                                <TableCell>{t('customNodes.colStatus')}</TableCell>
                                <TableCell>{t('customNodes.colHealth')}</TableCell>
                                <TableCell align="right">{t('customNodes.colActions')}</TableCell>
                            </TableRow>
                        </TableHead>
                        <TableBody>
                            {items.length === 0 && !loading && (
                                <TableRow>
                                    <TableCell colSpan={6}>
                                        <Typography variant="body2" color="text.secondary" align="center" sx={{ py: 3 }}>
                                            {t('customNodes.empty')}
                                        </Typography>
                                    </TableCell>
                                </TableRow>
                            )}
                            {items.map((d) => (
                                <TableRow key={d.id} hover>
                                    <TableCell>
                                        <Typography variant="body2" fontWeight={700}>{d.name}</Typography>
                                        <Typography variant="caption" color="text.secondary">{d.description}</Typography>
                                    </TableCell>
                                    <TableCell><code>{d.node_type}</code></TableCell>
                                    <TableCell sx={{ maxWidth: 240, wordBreak: 'break-all' }}>
                                        <Typography variant="caption">{d.runtime?.endpoint_url}</Typography>
                                    </TableCell>
                                    <TableCell>
                                        <Chip size="small" label={t(`customNodes.status.${d.status}`)} color={STATUS_COLORS[d.status] || 'default'} />
                                    </TableCell>
                                    <TableCell>
                                        {d.circuit_open ? (
                                            <Chip size="small" color="error" label={t('customNodes.circuitOpen')} />
                                        ) : (
                                            <Typography variant="caption" color="text.secondary">
                                                {t('customNodes.failures', { count: d.failure_count || 0 })}
                                            </Typography>
                                        )}
                                    </TableCell>
                                    <TableCell align="right">
                                        <Tooltip title={d.status === 'enabled' ? t('customNodes.disable') : t('customNodes.enable')}>
                                            <IconButton size="small" onClick={() => toggleStatus(d)}>
                                                {d.status === 'enabled' ? <BlockOutlined fontSize="small" /> : <CheckCircleOutlined fontSize="small" color="success" />}
                                            </IconButton>
                                        </Tooltip>
                                        <Tooltip title={t('customNodes.delete')}>
                                            <IconButton size="small" onClick={() => remove(d)}>
                                                <DeleteOutlined fontSize="small" color="error" />
                                            </IconButton>
                                        </Tooltip>
                                    </TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                </TableContainer>
            </Box>

            <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="sm" fullWidth>
                <DialogTitle>{t('customNodes.registerTitle')}</DialogTitle>
                <DialogContent dividers>
                    <Stack spacing={2} sx={{ mt: 1 }}>
                        <TextField label={t('customNodes.fieldKey')} value={form.key} onChange={(e) => setField('key', e.target.value)} helperText={t('customNodes.fieldKeyHelp')} size="small" fullWidth />
                        <TextField label={t('customNodes.fieldName')} value={form.name} onChange={(e) => setField('name', e.target.value)} size="small" fullWidth />
                        <TextField label={t('customNodes.fieldDescription')} value={form.description} onChange={(e) => setField('description', e.target.value)} size="small" fullWidth multiline minRows={2} />
                        <TextField label={t('customNodes.fieldEndpoint')} value={form.endpoint_url} onChange={(e) => setField('endpoint_url', e.target.value)} helperText={t('customNodes.fieldEndpointHelp')} size="small" fullWidth />
                        <Stack direction="row" spacing={2}>
                            <TextField label={t('customNodes.fieldTimeout')} type="number" value={form.timeout_ms} onChange={(e) => setField('timeout_ms', e.target.value)} size="small" fullWidth />
                            <TextField label={t('customNodes.fieldAuthType')} select value={form.auth_type} onChange={(e) => setField('auth_type', e.target.value)} size="small" fullWidth>
                                <MenuItem value="hmac">HMAC-SHA256</MenuItem>
                                <MenuItem value="bearer">Bearer</MenuItem>
                                <MenuItem value="none">None</MenuItem>
                            </TextField>
                        </Stack>
                        <TextField label={t('customNodes.fieldSecret')} value={form.secret} onChange={(e) => setField('secret', e.target.value)} helperText={t('customNodes.fieldSecretHelp')} size="small" fullWidth type="password" />
                        <TextField label={t('customNodes.fieldOutputs')} value={form.outputs} onChange={(e) => setField('outputs', e.target.value)} helperText={t('customNodes.fieldOutputsHelp')} size="small" fullWidth />
                        <TextField label={t('customNodes.fieldSchema')} value={form.config_schema} onChange={(e) => setField('config_schema', e.target.value)} helperText={t('customNodes.fieldSchemaHelp')} size="small" fullWidth multiline minRows={4} sx={{ '& textarea': { fontFamily: 'monospace', fontSize: '0.78rem' } }} />
                        <TextField label={t('customNodes.fieldStatus')} select value={form.status} onChange={(e) => setField('status', e.target.value)} size="small" fullWidth>
                            <MenuItem value="draft">{t('customNodes.status.draft')}</MenuItem>
                            <MenuItem value="enabled">{t('customNodes.status.enabled')}</MenuItem>
                            <MenuItem value="disabled">{t('customNodes.status.disabled')}</MenuItem>
                        </TextField>
                    </Stack>
                </DialogContent>
                <DialogActions>
                    <Button onClick={() => setDialogOpen(false)}>{t('customNodes.cancel')}</Button>
                    <Button onClick={submit} variant="contained" disabled={saving}>{t('customNodes.save')}</Button>
                </DialogActions>
            </Dialog>
        </Box>
    );
}
