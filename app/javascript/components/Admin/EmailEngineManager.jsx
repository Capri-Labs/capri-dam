import React, { useEffect, useMemo, useState } from 'react';
import {
    Alert,
    Box,
    Button,
    Card,
    CardContent,
    Chip,
    CircularProgress,
    Dialog,
    DialogContent,
    DialogTitle,
    Divider,
    Drawer,
    Grid,
    IconButton,
    MenuItem,
    Paper,
    Stack,
    Tab,
    Tabs,
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableRow,
    TextField,
    Tooltip,
    Typography,
} from '@mui/material';
import {
    AddCircleOutlined,
    AutoAwesome,
    ContentCopy,
    DeleteOutlined,
    History,
    MailOutlined,
    Preview,
    Replay,
    Send,
    SettingsEthernet,
    Brush,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';
import RichTextEditor from '../Shared/RichTextEditor';

const SYSTEM_EVENTS = [
    { id: 'user_created', label: 'User Provisioned (Welcome)', category: 'transactional', variables: ['user.first_name', 'user.last_name', 'user.email', 'user.temp_password', 'user.role', 'login_url'] },
    { id: 'user_suspended', label: 'Account Suspended', category: 'transactional', variables: ['user.first_name', 'user.email', 'suspended_by.name', 'suspension_reason'] },
    { id: 'workflow_requested', label: 'Workflow: Approval Requested', category: 'notification', variables: ['user.first_name', 'asset.name', 'folder.name', 'workflow.name', 'workflow.due_date', 'workflow.url', 'requester.name'] },
    { id: 'workflow_approved', label: 'Workflow: Asset Approved', category: 'notification', variables: ['user.first_name', 'asset.name', 'reviewer.name', 'reviewer.notes', 'asset.url'] },
    { id: 'workflow_rejected', label: 'Workflow: Asset Rejected', category: 'notification', variables: ['user.first_name', 'asset.name', 'reviewer.name', 'reviewer.notes', 'asset.url'] },
    { id: 'user_mentioned', label: 'User @Mentioned', category: 'mention', variables: ['recipient.first_name', 'sender.name', 'mention.text', 'context.name', 'context.url'] },
    { id: 'asset_published', label: 'Asset Published', category: 'notification', variables: ['asset.name', 'asset.url', 'asset.thumbnail_url', 'published_by.name'] },
    { id: 'asset_uploaded', label: 'Asset Uploaded to Folder', category: 'notification', variables: ['asset.name', 'asset.url', 'folder.name', 'folder.url', 'uploaded_by.name'] },
    { id: 'collection_shared', label: 'Collection Shared With You', category: 'announcement', variables: ['collection.name', 'collection.url', 'collection.item_count', 'shared_by.name'] },
    { id: 'report_ready', label: 'Report Generation Complete', category: 'system', variables: ['report.name', 'report.download_url', 'report.format', 'generated_at'] },
    { id: 'storage_warning', label: 'Storage Quota Warning', category: 'system', variables: ['used_gb', 'quota_gb', 'percent_used', 'upgrade_url'] },
    { id: 'system_maintenance', label: 'Scheduled Maintenance', category: 'announcement', variables: ['maintenance_start', 'maintenance_end', 'message', 'status_page_url'] },
];

// Always-available tokens (company/app branding, dates, support contact) --
// mirrors GlobalTemplateVariables::NAMES on the backend. Shown in the
// Template Variables picker regardless of the selected event trigger.
const GLOBAL_VARIABLES = [
    'company.name', 'company.support_email', 'company.address',
    'app.name', 'app.url', 'recipient.email',
    'current_year', 'current_date', 'unsubscribe_url',
];

const DEFAULT_FORM = {
    id: null,
    name: '',
    description: '',
    category: 'transactional',
    event_trigger: '',
    subject: '',
    html_body: '',
    text_body: '',
    active: true,
    variables: {},
    preview_data: {},
};

function renderTemplate(template = '', previewData = {}) {
    return template.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (_, key) => {
        const trimmed = key.trim();
        const fallback = trimmed.split('.').pop();
        return previewData[trimmed] || previewData[fallback] || `{{${trimmed}}}`;
    });
}

export default function EmailEngineManager() {
    const { t } = useTranslation();
    const notify = useNotify();
    const [currentTab, setCurrentTab] = useState(0);
    const [templates, setTemplates] = useState([]);
    const [deliveries, setDeliveries] = useState([]);
    const [stats, setStats] = useState({ total: 0, sent: 0, failed: 0, pending: 0, today: 0, this_week: 0 });
    const [suggestions, setSuggestions] = useState([]);
    const [loading, setLoading] = useState(true);
    const [drawerOpen, setDrawerOpen] = useState(false);
    const [previewTab, setPreviewTab] = useState(0);
    const [editForm, setEditForm] = useState(DEFAULT_FORM);
    const [filters, setFilters] = useState({ status: '', search: '', date_from: '', date_to: '', page: 1, per_page: 25 });
    const [deliveryPagination, setDeliveryPagination] = useState({ page: 1, total_pages: 1, total: 0 });
    const [eventMappings, setEventMappings] = useState(SYSTEM_EVENTS);
    const [globalVariables, setGlobalVariables] = useState(GLOBAL_VARIABLES);
    const [templatesPage, setTemplatesPage] = useState(1);
    const [designGalleryOpen, setDesignGalleryOpen] = useState(false);
    const [designTemplates, setDesignTemplates] = useState([]);
    const [pendingEventTrigger, setPendingEventTrigger] = useState('');
    const [brandSettings, setBrandSettings] = useState({ custom_css: '', primary_color: '#1a56db', font_family: 'Arial, Helvetica, sans-serif', preview_style_block: '' });
    const [brandSettingsSaving, setBrandSettingsSaving] = useState(false);
    const TEMPLATES_PER_PAGE = 10;

    const csrfToken = document.querySelector('[name="csrf-token"]')?.content;

    const fetchTemplates = () => fetch('/admin/email_templates.json')
        .then(response => response.json())
        .then(data => setTemplates(data.email_templates || []));

    const fetchMappings = () => fetch('/admin/email_templates/event_triggers.json')
        .then(response => response.json())
        .then(data => {
            setEventMappings(data.events || SYSTEM_EVENTS);
            setGlobalVariables(data.global_variables || GLOBAL_VARIABLES);
        })
        .catch(() => {
            setEventMappings(SYSTEM_EVENTS);
            setGlobalVariables(GLOBAL_VARIABLES);
        });

    const fetchDesignTemplates = () => fetch('/admin/email_templates/design_templates.json')
        .then(response => response.json())
        .then(data => setDesignTemplates(data.designs || []))
        .catch(() => setDesignTemplates([]));

    const fetchBrandSettings = () => fetch('/admin/email_templates/brand_settings.json')
        .then(response => response.json())
        .then(data => setBrandSettings(prev => ({ ...prev, ...(data.brand_settings || {}) })))
        .catch(() => {});

    const fetchDeliveries = () => {
        const params = new URLSearchParams();
        Object.entries(filters).forEach(([key, value]) => {
            if (value !== '' && value !== null && value !== undefined) params.set(key, value);
        });

        return fetch(`/admin/email_deliveries.json?${params.toString()}`)
            .then(response => response.json())
            .then(data => {
                setDeliveries(data.email_deliveries || []);
                setDeliveryPagination(data.pagination || { page: 1, total_pages: 1, total: 0 });
            });
    };

    const fetchStats = () => fetch('/admin/email_deliveries/stats.json')
        .then(response => response.json())
        .then(data => setStats(data));

    const fetchSuggestions = () => fetch('/api/v1/ai/template_suggestions')
        .then(response => response.json())
        .then(data => setSuggestions(data.suggestions || []))
        .catch(() => setSuggestions([]));

    useEffect(() => {
        Promise.all([fetchTemplates(), fetchMappings(), fetchDeliveries(), fetchStats(), fetchSuggestions(), fetchDesignTemplates(), fetchBrandSettings()])
            .finally(() => setLoading(false));
    }, []);

    useEffect(() => {
        fetchDeliveries();
    }, [filters.page, filters.per_page, filters.status, filters.search, filters.date_from, filters.date_to]);

    const availableVariables = useMemo(() => {
        const event = eventMappings.find(item => item.id === editForm.event_trigger);
        const eventVariables = event?.variables || [];
        return [...new Set([...globalVariables, ...eventVariables])];
    }, [editForm.event_trigger, eventMappings, globalVariables]);

    const previewHtml = useMemo(
        () => `${brandSettings.preview_style_block || ''}${renderTemplate(editForm.html_body || '', editForm.preview_data || {})}`,
        [editForm.html_body, editForm.preview_data, brandSettings.preview_style_block]
    );

    // Client-side pagination for the Templates tab. `templates` itself stays
    // as the full list because Event Mapping (tab index 1) needs to look up
    // any template by event_trigger regardless of the Templates tab's page.
    const templatesTotalPages = Math.max(1, Math.ceil(templates.length / TEMPLATES_PER_PAGE));
    const clampedTemplatesPage = Math.min(templatesPage, templatesTotalPages);
    const pagedTemplates = templates.slice(
        (clampedTemplatesPage - 1) * TEMPLATES_PER_PAGE,
        clampedTemplatesPage * TEMPLATES_PER_PAGE
    );

    const openEditor = (template = null, prefillEvent = '', design = null) => {
        if (template) {
            setEditForm({ ...DEFAULT_FORM, ...template });
        } else {
            const event = eventMappings.find(item => item.id === prefillEvent);
            setEditForm({
                ...DEFAULT_FORM,
                event_trigger: prefillEvent,
                category: design?.category || event?.category || 'transactional',
                subject: design?.subject || '',
                html_body: design?.html_body || '',
                text_body: design?.text_body || '',
                variables: Object.fromEntries((event?.variables || []).map(variable => [variable, ''])),
                preview_data: Object.fromEntries((event?.variables || []).map(variable => [variable, variable.split('.').pop()])),
            });
        }
        setPreviewTab(0);
        setDrawerOpen(true);
    };

    // "New Template" opens a gallery of predefined designs first; "Start
    // from Blank" (or picking a design) proceeds into the normal editor.
    const openNewTemplateFlow = (prefillEvent = '') => {
        setPendingEventTrigger(prefillEvent);
        setDesignGalleryOpen(true);
    };

    const chooseDesign = design => {
        setDesignGalleryOpen(false);
        openEditor(null, pendingEventTrigger, design);
    };

    const startBlankTemplate = () => {
        setDesignGalleryOpen(false);
        openEditor(null, pendingEventTrigger);
    };

    const saveTemplate = () => {
        const method = editForm.id ? 'PATCH' : 'POST';
        const url = editForm.id ? `/admin/email_templates/${editForm.id}.json` : '/admin/email_templates.json';
        fetch(url, {
            method,
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrfToken,
            },
            body: JSON.stringify({ email_template: editForm }),
        })
            .then(response => response.json())
            .then(data => {
                if (!data.success) throw new Error(data.errors?.join(', ') || 'save_failed');
                notify(data.message, 'success');
                setDrawerOpen(false);
                fetchTemplates();
            })
            .catch(error => notify(`Error: ${error.message}`, 'error'));
    };

    const deleteTemplate = id => {
        if (!window.confirm('Delete this template?')) return;
        fetch(`/admin/email_templates/${id}.json`, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': csrfToken },
        })
            .then(response => response.json())
            .then(data => {
                if (!data.success) throw new Error((data.errors || []).join(', '));
                notify(data.message, 'success');
                fetchTemplates();
            })
            .catch(error => notify(`Error: ${error.message}`, 'error'));
    };

    const sendTestEmail = () => {
        if (!editForm.id) {
            notify('Save the template before sending a test email.', 'warning');
            return;
        }
        fetch(`/admin/email_templates/${editForm.id}/send_test.json`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrfToken,
            },
            body: JSON.stringify({ payload: editForm.preview_data }),
        })
            .then(response => response.json())
            .then(data => {
                if (!data.success) throw new Error(data.errors?.join(', ') || 'send_failed');
                notify(data.message, 'success');
                fetchDeliveries();
                fetchStats();
            })
            .catch(error => notify(`Error: ${error.message}`, 'error'));
    };

    const retryDelivery = id => {
        fetch(`/admin/email_deliveries/${id}/retry.json`, {
            method: 'POST',
            headers: { 'X-CSRF-Token': csrfToken },
        })
            .then(response => response.json())
            .then(data => {
                if (!data.success) throw new Error(data.errors?.join(', ') || 'retry_failed');
                notify(data.message, 'success');
                fetchDeliveries();
                fetchStats();
            })
            .catch(error => notify(`Error: ${error.message}`, 'error'));
    };

    const retryFailed = () => {
        fetch('/admin/email_deliveries/bulk_retry_failed.json', {
            method: 'POST',
            headers: { 'X-CSRF-Token': csrfToken },
        })
            .then(response => response.json())
            .then(data => {
                notify(`Retried ${data.retried_count || 0} deliveries.`, 'success');
                fetchDeliveries();
                fetchStats();
            })
            .catch(() => notify('Error retrying failed deliveries.', 'error'));
    };

    const insertVariable = variable => {
        const token = `{{${variable}}}`;
        setEditForm(prev => ({ ...prev, html_body: `${prev.html_body || ''}${token}`, text_body: `${prev.text_body || ''}${token}` }));
    };

    // "Communication Engine" tab -- saves the org-wide CSS injected into
    // every outbound email by EmailDispatcherWorker (see EmailBrandSettings).
    const saveBrandSettings = () => {
        setBrandSettingsSaving(true);
        fetch('/admin/email_templates/brand_settings.json', {
            method: 'PATCH',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-Token': csrfToken,
            },
            body: JSON.stringify({
                brand_settings: {
                    custom_css: brandSettings.custom_css,
                    primary_color: brandSettings.primary_color,
                    font_family: brandSettings.font_family,
                },
            }),
        })
            .then(response => response.json())
            .then(data => {
                if (!data.success) throw new Error((data.errors || []).join(', ') || 'save_failed');
                setBrandSettings(prev => ({ ...prev, ...data.brand_settings }));
                notify(data.message, 'success');
            })
            .catch(error => notify(`Error: ${error.message}`, 'error'))
            .finally(() => setBrandSettingsSaving(false));
    };

    const failureRate = stats.total ? `${Math.round((stats.failed / stats.total) * 100)}%` : '0%';

    if (loading) {
        return (
            <Stack sx={{ minHeight: '60vh', alignItems: 'center', justifyContent: 'center' }}>
                <CircularProgress />
            </Stack>
        );
    }

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <Box component="main" sx={{ width: '100%', p: 2 }}>
                <Stack direction="row" sx={{ justifyContent: 'space-between', alignItems: 'center' }}>
                    <Box>
                        <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                            {t('emailEngine.title', { defaultValue: 'Communication Engine' })}
                        </Typography>
                        <Typography variant="body2" color="text.secondary">
                            Manage inbox delivery, Liquid templates, event mappings, and email audit queues.
                        </Typography>
                    </Box>
                    {currentTab === 0 && (
                        <Button variant="contained" startIcon={<AddCircleOutlined />} onClick={() => openNewTemplateFlow()}>
                            {t('emailEngine.newTemplate', { defaultValue: 'New Template' })}
                        </Button>
                    )}
                </Stack>

                <Paper variant="outlined" sx={{ borderRadius: 3, mt: 3, overflow: 'hidden' }}>
                    <Tabs value={currentTab} onChange={(_, value) => setCurrentTab(value)} sx={{ px: 2, borderBottom: '1px solid #e3e8ef', bgcolor: '#f8f9fa' }}>
                        <Tab icon={<MailOutlined fontSize="small" />} iconPosition="start" label={t('emailEngine.templates', { defaultValue: 'Templates' })} />
                        <Tab icon={<SettingsEthernet fontSize="small" />} iconPosition="start" label={t('emailEngine.eventMapping', { defaultValue: 'Event Mapping' })} />
                        <Tab icon={<History fontSize="small" />} iconPosition="start" label={t('emailEngine.outbox', { defaultValue: 'Outbox' })} />
                        <Tab icon={<AutoAwesome fontSize="small" />} iconPosition="start" label={t('emailEngine.aiSuggestions', { defaultValue: 'AI Suggestions' })} />
                        <Tab icon={<Brush fontSize="small" />} iconPosition="start" label={t('emailEngine.communicationEngine.tab', { defaultValue: 'Global CSS for Emails' })} />
                    </Tabs>

                    <Box sx={{ p: 3 }}>
                        {currentTab === 0 && (
                            <>
                            <Table stickyHeader>
                                <TableHead>
                                    <TableRow>
                                        <TableCell>{t('emailEngine.templateName', { defaultValue: 'Template Name' })}</TableCell>
                                        <TableCell>{t('emailEngine.eventTrigger', { defaultValue: 'Event Trigger' })}</TableCell>
                                        <TableCell>{t('emailEngine.templates', { defaultValue: 'Templates' })}</TableCell>
                                        <TableCell>{t('common.actions', { defaultValue: 'Actions' })}</TableCell>
                                    </TableRow>
                                </TableHead>
                                <TableBody>
                                    {pagedTemplates.map(template => (
                                        <TableRow key={template.id} hover>
                                            <TableCell>
                                                <Typography variant="subtitle2">{template.name}</Typography>
                                                <Typography variant="caption" color="text.secondary">{template.description || template.subject}</Typography>
                                            </TableCell>
                                            <TableCell>
                                                <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                                                    <Chip size="small" label={template.event_trigger} variant="outlined" />
                                                    <Chip size="small" label={t(`emailEngine.category.${template.category}`, { defaultValue: template.category })} />
                                                </Stack>
                                            </TableCell>
                                            <TableCell>
                                                <Typography variant="body2">{template.variable_names?.join(', ') || Object.keys(template.variables || {}).join(', ') || '—'}</Typography>
                                            </TableCell>
                                            <TableCell>
                                                <Button size="small" onClick={() => openEditor(template)}>Edit</Button>
                                                <IconButton size="small" color="error" onClick={() => deleteTemplate(template.id)}><DeleteOutlined /></IconButton>
                                            </TableCell>
                                        </TableRow>
                                    ))}
                                </TableBody>
                            </Table>
                            {templatesTotalPages > 1 && (
                                <Stack direction="row" spacing={1} sx={{ mt: 2, justifyContent: 'center', alignItems: 'center' }}>
                                    <Button
                                        size="small"
                                        disabled={clampedTemplatesPage <= 1}
                                        onClick={() => setTemplatesPage(clampedTemplatesPage - 1)}
                                    >
                                        {t('common.previous', { defaultValue: 'Previous' })}
                                    </Button>
                                    <Typography variant="body2" color="text.secondary">
                                        {t('common.pageOf', { defaultValue: `Page ${clampedTemplatesPage} of ${templatesTotalPages}` })}
                                    </Typography>
                                    <Button
                                        size="small"
                                        disabled={clampedTemplatesPage >= templatesTotalPages}
                                        onClick={() => setTemplatesPage(clampedTemplatesPage + 1)}
                                    >
                                        {t('common.next', { defaultValue: 'Next' })}
                                    </Button>
                                </Stack>
                            )}
                            </>
                        )}

                        {currentTab === 1 && (
                            <Stack spacing={2}>
                                <Alert severity="info">{t('emailEngine.eventMapping', { defaultValue: 'Event Mapping' })} keeps every system event wired to a template.</Alert>
                                <Grid container spacing={2}>
                                    {eventMappings.map(event => {
                                        const mappedTemplate = templates.find(template => template.event_trigger === event.id);
                                        return (
                                            <Grid xs={12} md={6} key={event.id}>
                                                <Paper variant="outlined" sx={{ p: 2, borderRadius: 2, height: '100%' }}>
                                                    <Stack spacing={1}>
                                                        <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>{event.label}</Typography>
                                                        <Stack direction="row" spacing={1}>
                                                            <Chip size="small" label={event.id} variant="outlined" />
                                                            <Chip size="small" label={t(`emailEngine.category.${event.category}`, { defaultValue: event.category })} />
                                                        </Stack>
                                                        <Typography variant="body2" color="text.secondary">
                                                            {event.variables.join(', ')}
                                                        </Typography>
                                                        <Divider />
                                                        {mappedTemplate ? (
                                                            <Stack direction="row" sx={{ justifyContent: 'space-between', alignItems: 'center' }}>
                                                                <Chip size="small" color={mappedTemplate.active ? 'success' : 'default'} label={mappedTemplate.active ? t('emailEngine.active', { defaultValue: 'Active' }) : t('emailEngine.inactive', { defaultValue: 'Inactive' })} />
                                                                <Button size="small" onClick={() => openEditor(mappedTemplate)}>Edit</Button>
                                                            </Stack>
                                                        ) : (
                                                            <Button size="small" variant="outlined" onClick={() => openNewTemplateFlow(event.id)}>Create</Button>
                                                        )}
                                                    </Stack>
                                                </Paper>
                                            </Grid>
                                        );
                                    })}
                                </Grid>
                            </Stack>
                        )}

                        {currentTab === 2 && (
                            <Stack spacing={3}>
                                <Grid container spacing={2}>
                                    {[
                                        { label: t('emailEngine.stats.sentToday', { defaultValue: 'Sent Today' }), value: stats.today },
                                        { label: t('emailEngine.stats.sentThisWeek', { defaultValue: 'Sent This Week' }), value: stats.this_week },
                                        { label: t('emailEngine.stats.failureRate', { defaultValue: 'Failure Rate' }), value: failureRate },
                                        { label: t('emailEngine.stats.pending', { defaultValue: 'Pending' }), value: stats.pending },
                                    ].map(card => (
                                        <Grid xs={12} md={3} key={card.label}>
                                            <Card variant="outlined">
                                                <CardContent>
                                                    <Typography variant="body2" color="text.secondary">{card.label}</Typography>
                                                    <Typography variant="h5" sx={{ fontWeight: 700 }}>{card.value}</Typography>
                                                </CardContent>
                                            </Card>
                                        </Grid>
                                    ))}
                                </Grid>

                                <Stack direction={{ xs: 'column', md: 'row' }} spacing={2}>
                                    <TextField label={t('common.search', { defaultValue: 'Search' })} value={filters.search} onChange={event => setFilters(prev => ({ ...prev, search: event.target.value, page: 1 }))} />
                                    <TextField select label={t('common.status', { defaultValue: 'Status' })} value={filters.status} onChange={event => setFilters(prev => ({ ...prev, status: event.target.value, page: 1 }))} sx={{ minWidth: 180 }}>
                                        <MenuItem value="">All</MenuItem>
                                        <MenuItem value="pending">Pending</MenuItem>
                                        <MenuItem value="sent">Sent</MenuItem>
                                        <MenuItem value="failed">Failed</MenuItem>
                                    </TextField>
                                    <TextField type="date" label="From" value={filters.date_from} onChange={event => setFilters(prev => ({ ...prev, date_from: event.target.value, page: 1 }))} slotProps={{ inputLabel: { shrink: true } }} />
                                    <TextField type="date" label="To" value={filters.date_to} onChange={event => setFilters(prev => ({ ...prev, date_to: event.target.value, page: 1 }))} slotProps={{ inputLabel: { shrink: true } }} />
                                    <Button variant="outlined" startIcon={<Replay />} onClick={retryFailed}>Bulk Retry Failed</Button>
                                </Stack>

                                <Table stickyHeader>
                                    <TableHead>
                                        <TableRow>
                                            <TableCell>Date</TableCell>
                                            <TableCell>Recipient</TableCell>
                                            <TableCell>Template</TableCell>
                                            <TableCell>Status</TableCell>
                                            <TableCell align="right">Action</TableCell>
                                        </TableRow>
                                    </TableHead>
                                    <TableBody>
                                        {deliveries.map(delivery => (
                                            <TableRow key={delivery.id} hover>
                                                <TableCell>{delivery.sent_at}</TableCell>
                                                <TableCell>{delivery.recipient}</TableCell>
                                                <TableCell>{delivery.template_name}</TableCell>
                                                <TableCell>
                                                    <Tooltip title={delivery.error_log || ''}>
                                                        <Chip size="small" label={delivery.status} color={delivery.status === 'failed' ? 'error' : delivery.status === 'sent' ? 'success' : 'warning'} />
                                                    </Tooltip>
                                                </TableCell>
                                                <TableCell align="right">
                                                    {delivery.status === 'failed' && <Button size="small" startIcon={<Replay />} onClick={() => retryDelivery(delivery.id)}>Retry</Button>}
                                                </TableCell>
                                            </TableRow>
                                        ))}
                                    </TableBody>
                                </Table>

                                <Stack direction="row" sx={{ justifyContent: 'space-between', alignItems: 'center' }}>
                                    <Typography variant="body2" color="text.secondary">{deliveryPagination.total} deliveries</Typography>
                                    <Stack direction="row" spacing={1}>
                                        <Button disabled={filters.page <= 1} onClick={() => setFilters(prev => ({ ...prev, page: prev.page - 1 }))}>Previous</Button>
                                        <Button disabled={filters.page >= deliveryPagination.total_pages} onClick={() => setFilters(prev => ({ ...prev, page: prev.page + 1 }))}>Next</Button>
                                    </Stack>
                                </Stack>
                            </Stack>
                        )}

                        {currentTab === 3 && (
                            <Stack spacing={2}>
                                {suggestions.map(suggestion => (
                                    <Paper variant="outlined" key={suggestion.id} sx={{ p: 2 }}>
                                        <Stack direction="row" spacing={2} sx={{ justifyContent: 'space-between' }}>
                                            <Box>
                                                <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>{suggestion.title}</Typography>
                                                <Typography variant="body2" color="text.secondary">{suggestion.summary}</Typography>
                                            </Box>
                                            <Chip label={suggestion.severity} />
                                        </Stack>
                                    </Paper>
                                ))}
                                {suggestions.length === 0 && <Alert severity="info">No AI suggestions available.</Alert>}
                            </Stack>
                        )}

                        {currentTab === 4 && (
                            <Stack spacing={3} sx={{ maxWidth: 720 }}>
                                <Typography variant="h6" sx={{ fontWeight: 700 }}>
                                    {t('emailEngine.communicationEngine.pageTitle', { defaultValue: 'Global CSS for Emails' })}
                                </Typography>
                                <Alert severity="info">
                                    {t('emailEngine.communicationEngine.explainer', {
                                        defaultValue:
                                            'This CSS is applied to every outgoing email across the whole system (Templates, Event Mapping notifications, and one-off test sends) -- not just the template you\'re currently editing. Use it for brand-wide colors, fonts, and link styling. Note: many webmail clients (Gmail, Outlook.com) strip <style> blocks entirely and only honor inline styles, so this CSS is best-effort theming for clients that do support it (Apple Mail, Outlook desktop, most modern mail apps) -- it is not a substitute for well-designed, inline-styled templates.',
                                    })}
                                </Alert>

                                <Stack direction={{ xs: 'column', md: 'row' }} spacing={2}>
                                    <TextField
                                        label={t('emailEngine.communicationEngine.primaryColor', { defaultValue: 'Primary Brand Color' })}
                                        type="color"
                                        value={brandSettings.primary_color}
                                        onChange={event => setBrandSettings(prev => ({ ...prev, primary_color: event.target.value }))}
                                        sx={{ width: 160 }}
                                    />
                                    <TextField
                                        label={t('emailEngine.communicationEngine.fontFamily', { defaultValue: 'Font Family' })}
                                        value={brandSettings.font_family}
                                        onChange={event => setBrandSettings(prev => ({ ...prev, font_family: event.target.value }))}
                                        fullWidth
                                    />
                                </Stack>

                                <TextField
                                    label={t('emailEngine.communicationEngine.customCss', { defaultValue: 'Global Email CSS' })}
                                    value={brandSettings.custom_css}
                                    onChange={event => setBrandSettings(prev => ({ ...prev, custom_css: event.target.value }))}
                                    placeholder="a { color: #1a56db; }\nh1, h2 { font-family: Georgia, serif; }"
                                    fullWidth
                                    multiline
                                    minRows={10}
                                />

                                <Button
                                    variant="contained"
                                    startIcon={<Brush />}
                                    onClick={saveBrandSettings}
                                    disabled={brandSettingsSaving}
                                    sx={{ alignSelf: 'flex-start' }}
                                >
                                    {t('emailEngine.communicationEngine.save', { defaultValue: 'Save Global CSS' })}
                                </Button>
                            </Stack>
                        )}
                    </Box>
                </Paper>

                <Drawer anchor="right" open={drawerOpen} onClose={() => setDrawerOpen(false)}>
                    <Box sx={{ mt: 6, width: '60vw', minWidth: 640, p: 4, height: '100%', overflowY: 'auto' }}>
                        <Stack direction="row" sx={{ mb: 3, justifyContent: 'space-between', alignItems: 'center' }}>
                            <Typography variant="h5" sx={{ fontWeight: 700 }}>{editForm.id ? 'Edit Template' : 'New Template'}</Typography>
                            <Stack direction="row" spacing={1}>
                                <Button variant="outlined" startIcon={<Send />} onClick={sendTestEmail}>Send Test</Button>
                                <Button variant="contained" onClick={saveTemplate} disabled={!editForm.name || !editForm.subject}>Save</Button>
                            </Stack>
                        </Stack>

                        <Stack spacing={2}>
                            <TextField label={t('emailEngine.templateName', { defaultValue: 'Template Name' })} value={editForm.name} onChange={event => setEditForm(prev => ({ ...prev, name: event.target.value }))} fullWidth />
                            <TextField label="Description" value={editForm.description} onChange={event => setEditForm(prev => ({ ...prev, description: event.target.value }))} fullWidth />
                            <Stack direction={{ xs: 'column', md: 'row' }} spacing={2}>
                                <TextField select label={t('emailEngine.eventTrigger', { defaultValue: 'Event Trigger' })} value={editForm.event_trigger} onChange={event => setEditForm(prev => ({ ...prev, event_trigger: event.target.value }))} fullWidth>
                                    {eventMappings.map(event => <MenuItem key={event.id} value={event.id}>{event.label}</MenuItem>)}
                                </TextField>
                                <TextField select label={t('emailEngine.category.transactional', { defaultValue: 'Category' })} value={editForm.category} onChange={event => setEditForm(prev => ({ ...prev, category: event.target.value }))} fullWidth>
                                    {['transactional', 'notification', 'mention', 'announcement', 'system'].map(category => (
                                        <MenuItem key={category} value={category}>{t(`emailEngine.category.${category}`, { defaultValue: category })}</MenuItem>
                                    ))}
                                </TextField>
                            </Stack>
                            <TextField label={t('emailEngine.subject', { defaultValue: 'Subject' })} value={editForm.subject} onChange={event => setEditForm(prev => ({ ...prev, subject: event.target.value }))} fullWidth />

                            <Paper variant="outlined" sx={{ p: 2 }}>
                                <Stack spacing={1}>
                                    <Typography variant="subtitle2">{t('emailEngine.variables', { defaultValue: 'Template Variables' })}</Typography>
                                    <Stack direction="row" spacing={1} useFlexGap sx={{ flexWrap: 'wrap' }}>
                                        {availableVariables.map(variable => (
                                            <Chip
                                                key={variable}
                                                size="small"
                                                label={`{{${variable}}}`}
                                                icon={<ContentCopy fontSize="small" />}
                                                onClick={() => insertVariable(variable)}
                                                onDelete={() => navigator.clipboard.writeText(`{{${variable}}}`)}
                                            />
                                        ))}
                                    </Stack>
                                </Stack>
                            </Paper>

                            <Tabs value={previewTab} onChange={(_, value) => setPreviewTab(value)}>
                                <Tab icon={<MailOutlined fontSize="small" />} iconPosition="start" label={t('emailEngine.htmlBody', { defaultValue: 'HTML Body' })} />
                                <Tab icon={<Preview fontSize="small" />} iconPosition="start" label={t('emailEngine.preview', { defaultValue: 'Preview' })} />
                            </Tabs>

                            {previewTab === 0 ? (
                                <Stack spacing={2}>
                                    <Typography variant="subtitle2">{t('emailEngine.htmlBody', { defaultValue: 'HTML Body' })}</Typography>
                                    <RichTextEditor
                                        value={editForm.html_body}
                                        onChange={html => setEditForm(prev => ({ ...prev, html_body: html }))}
                                    />
                                    <TextField label={t('emailEngine.textBody', { defaultValue: 'Plain Text' })} value={editForm.text_body} onChange={event => setEditForm(prev => ({ ...prev, text_body: event.target.value }))} fullWidth multiline minRows={6} />
                                </Stack>
                            ) : (
                                <Paper variant="outlined" sx={{ p: 0, minHeight: 240, overflow: 'hidden' }}>
                                    {/* Rendered in a sandboxed iframe (not dangerouslySetInnerHTML) so the
                                        template's own <style> block and inline styles apply exactly as
                                        they will in a real inbox, isolated from the admin UI's own CSS. */}
                                    <iframe
                                        title={t('emailEngine.preview', { defaultValue: 'Preview' })}
                                        srcDoc={previewHtml || '<p>No preview content.</p>'}
                                        sandbox=""
                                        style={{ width: '100%', minHeight: 400, border: 'none', display: 'block' }}
                                    />
                                </Paper>
                            )}
                        </Stack>
                    </Box>
                </Drawer>

                <Dialog open={designGalleryOpen} onClose={() => setDesignGalleryOpen(false)} maxWidth="md" fullWidth>
                    <DialogTitle sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        {t('emailEngine.chooseDesign.title', { defaultValue: 'Choose a Template Design' })}
                        <Button size="small" onClick={startBlankTemplate}>
                            {t('emailEngine.chooseDesign.startBlank', { defaultValue: 'Start from Blank' })}
                        </Button>
                    </DialogTitle>
                    <DialogContent>
                        {designTemplates.length === 0 ? (
                            <Alert severity="info">
                                {t('emailEngine.chooseDesign.empty', { defaultValue: 'No predefined designs available. Start from blank instead.' })}
                            </Alert>
                        ) : (
                            <Grid container spacing={2} sx={{ pb: 2 }}>
                                {designTemplates.map(design => (
                                    <Grid xs={12} sm={6} md={4} key={design.id}>
                                        <Paper
                                            variant="outlined"
                                            role="button"
                                            aria-label={design.name}
                                            onClick={() => chooseDesign(design)}
                                            sx={{ p: 2, borderRadius: 2, height: '100%', cursor: 'pointer', '&:hover': { borderColor: 'primary.main' } }}
                                        >
                                            <Stack spacing={1}>
                                                <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>{design.name}</Typography>
                                                <Chip size="small" label={t(`emailEngine.category.${design.category}`, { defaultValue: design.category })} sx={{ alignSelf: 'flex-start' }} />
                                                <Typography variant="body2" color="text.secondary">{design.description}</Typography>
                                            </Stack>
                                        </Paper>
                                    </Grid>
                                ))}
                            </Grid>
                        )}
                    </DialogContent>
                </Dialog>
            </Box>
        </Box>
    );
}
