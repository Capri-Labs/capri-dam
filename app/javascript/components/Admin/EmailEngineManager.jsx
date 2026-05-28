import React, { useState, useEffect } from 'react';
import {
    Box, Paper, Typography, Button, TextField, Table, TableBody,
    TableCell, TableHead, TableRow, Chip, Drawer, Stack, IconButton,
    Divider, Tab, Tabs, MenuItem, Tooltip, Alert, Grid, CssBaseline, Toolbar
} from '@mui/material';
import {
    SettingsEthernet, History, Replay, ContentCopy, DeleteOutlined, MailOutlined, AddCircleOutlined
} from '@mui/icons-material';
import Sidebar from "../Sidebar";
import { navigateTo } from '../../utils/globalutils';
import { useNotify } from '../../context/NotificationContext';
import RichTextEditor from '../Shared/RichTextEditor';

// Master List of System Events for the Mapping Settings
const SYSTEM_EVENTS = [
    { id: 'user_created', label: 'User Provisioned (Welcome)', variables: ['user.first_name', 'user.email', 'user.temp_password'] },
    { id: 'user_suspended', label: 'Account Suspended', variables: ['user.first_name', 'user.email'] },
    { id: 'workflow_requested', label: 'Workflow: Approval Requested', variables: ['user.first_name', 'asset.name', 'folder.name'] },
    { id: 'workflow_approved', label: 'Workflow: Asset Approved', variables: ['user.first_name', 'asset.name', 'reviewer.name'] },
    { id: 'workflow_rejected', label: 'Workflow: Asset Rejected', variables: ['user.first_name', 'asset.name', 'reviewer.notes'] }
];

export default function EmailEngineManager() {
    const notify = useNotify();
    const [currentTab, setCurrentTab] = useState(0);
    const [templates, setTemplates] = useState([]);
    const [deliveries, setDeliveries] = useState([]);
    const [loading, setLoading] = useState(true);
    const [activeView, setActiveView] = useState('Email Engine');

    // Editor State
    const [drawerOpen, setDrawerOpen] = useState(false);
    const [editForm, setEditForm] = useState({
        id: null, name: '', event_trigger: '', subject: '', html_body: '', text_body: '', active: true
    });

    useEffect(() => {
        fetchTemplates();
        fetchDeliveries();
    }, []);

    const fetchTemplates = () => {
        fetch('/admin/email_templates.json')
            .then(res => res.json())
            .then(data => setTemplates(data.email_templates || []));
    };

    const fetchDeliveries = () => {
        fetch('/admin/email_deliveries.json')
            .then(res => res.json())
            .then(data => setDeliveries(data.email_deliveries || []))
            .finally(() => setLoading(false));
    };

    // --- TEMPLATE CRUD ACTIONS ---
    const handleOpenEditor = (template = null, prefillEvent = '') => {
        if (template) {
            setEditForm({ ...template });
        } else {
            setEditForm({
                id: null, name: '', event_trigger: prefillEvent, subject: '',
                html_body: '', text_body: '', active: true
            });
        }
        setDrawerOpen(true);
    };

    const handleSaveTemplate = () => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const method = editForm.id ? 'PATCH' : 'POST';
        const url = editForm.id ? `/admin/email_templates/${editForm.id}.json` : '/admin/email_templates.json';

        fetch(url, {
            method: method,
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify({ email_template: editForm })
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify(data.message, "success");
                    setDrawerOpen(false);
                    fetchTemplates();
                } else {
                    notify(`Error: ${data.errors?.join(', ')}`, "error");
                }
            });
    };

    const handleDeleteTemplate = (id) => {
        if (!window.confirm("Are you sure? System events relying on this template will fail to send emails.")) return;

        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        fetch(`/admin/email_templates/${id}.json`, {
            method: 'DELETE',
            headers: { 'X-CSRF-Token': csrfToken }
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify(data.message, "success");
                    fetchTemplates();
                }
            });
    };

    // --- OUTBOX ACTIONS ---
    const handleRetryEmail = (id) => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        fetch(`/admin/email_deliveries/${id}/retry.json`, {
            method: 'POST',
            headers: { 'X-CSRF-Token': csrfToken }
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify(data.message, "success");
                    fetchDeliveries();
                } else {
                    notify(`Error: ${data.errors?.join(', ')}`, "error");
                }
            });
    };

    // --- UX HELPERS ---
    const getAvailableVariables = (triggerId) => {
        const event = SYSTEM_EVENTS.find(e => e.id === triggerId);
        return event ? event.variables : [];
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <Sidebar activeView={activeView} onNavigate={(v) => v === 'System' ? null : navigateTo('/dashboard')} />
            <Box component="main" sx={{ width: '100%', p: 2 }}>
                <Box sx={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    width: '100%', // Ensure it spans the full width
                }}>
                    {/* LEFT SIDE */}
                    <Box>
                        <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>Communication Engine</Typography>
                        <Typography variant="body2" color="textSecondary">Manage Liquid email templates, event mapping, and audit delivery queues.</Typography>
                    </Box>

                    {/* RIGHT SIDE */}
                    <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 2 }}>
                        {currentTab === 0 && (
                            <Button variant="contained" startIcon={<AddCircleOutlined />} onClick={() => handleOpenEditor()}>
                                Create Template
                            </Button>
                        )}
                    </Stack>
                </Box>

                <Paper variant="outlined" sx={{ borderRadius: 3, marginTop: 3, display: 'flex', flexDirection: 'column', flexGrow: 1, overflow: 'hidden' }}>
                    <Tabs value={currentTab} onChange={(e, val) => setCurrentTab(val)} sx={{ px: 2, borderBottom: '1px solid #e3e8ef', bgcolor: '#f8f9fa' }}>
                        <Tab icon={<MailOutlined fontSize="small" />} iconPosition="start" label="Email Templates" />
                        <Tab icon={<SettingsEthernet fontSize="small" />} iconPosition="start" label="Event Mapping (Settings)" />
                        <Tab icon={<History fontSize="small" />} iconPosition="start" label="Outbox & Audit Log" />
                    </Tabs>

                    <Box sx={{ flexGrow: 1, overflowY: 'auto', p: 0 }}>
                        {/* TAB 1: TEMPLATE LIST */}
                        {currentTab === 0 && (
                            <Table stickyHeader>
                                <TableHead>
                                    <TableRow>
                                        <TableCell sx={{ fontWeight: 600 }}>Template Name</TableCell>
                                        <TableCell sx={{ fontWeight: 600 }}>System Event Trigger</TableCell>
                                        <TableCell sx={{ fontWeight: 600 }}>Status</TableCell>
                                        <TableCell align="right" sx={{ fontWeight: 600 }}>Actions</TableCell>
                                    </TableRow>
                                </TableHead>
                                <TableBody>
                                    {templates.map(tpl => (
                                        <TableRow key={tpl.id} hover>
                                            <TableCell>
                                                <Typography variant="subtitle2">{tpl.name}</Typography>
                                                <Typography variant="caption" color="textSecondary">{tpl.subject}</Typography>
                                            </TableCell>
                                            <TableCell><Chip size="small" label={tpl.event_trigger} variant="outlined" /></TableCell>
                                            <TableCell>
                                                {tpl.active ? <Chip size="small" label="Active" color="success" /> : <Chip size="small" label="Inactive" color="default" />}
                                            </TableCell>
                                            <TableCell align="right">
                                                <Button size="small" onClick={() => handleOpenEditor(tpl)}>Edit</Button>
                                                <IconButton size="small" color="error" onClick={() => handleDeleteTemplate(tpl.id)}><DeleteOutlined /></IconButton>
                                            </TableCell>
                                        </TableRow>
                                    ))}
                                </TableBody>
                            </Table>
                        )}

                        {/* TAB 2: EVENT MAPPING SETTINGS */}
                        {currentTab === 1 && (
                            <Box sx={{ p: 3 }}>
                                <Alert severity="info" sx={{ mb: 3 }}>
                                    Map system events to their respective email templates. Events without an active template will fail silently.
                                </Alert>
                                <Grid container spacing={3}>
                                    {SYSTEM_EVENTS.map(event => {
                                        const mappedTemplate = templates.find(t => t.event_trigger === event.id);
                                        return (
                                            <Grid item xs={12} md={6} key={event.id}>
                                                <Paper variant="outlined" sx={{ p: 3, borderRadius: 2, height: '100%', display: 'flex', flexDirection: 'column' }}>
                                                    <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>{event.label}</Typography>
                                                    <Typography variant="caption" color="textSecondary" sx={{ mb: 2, fontFamily: 'monospace' }}>Trigger: {event.id}</Typography>

                                                    <Box sx={{ mt: 'auto', p: 2, bgcolor: mappedTemplate ? '#f0fdf4' : '#fff1f2', borderRadius: 1, border: '1px solid', borderColor: mappedTemplate ? '#bbf7d0' : '#fecdd3' }}>
                                                        {mappedTemplate ? (
                                                            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                                                <Typography variant="body2" sx={{ fontWeight: 600, color: '#166534' }}>
                                                                    Mapped to: {mappedTemplate.name}
                                                                </Typography>
                                                                <Button size="small" onClick={() => handleOpenEditor(mappedTemplate)}>Edit</Button>
                                                            </Box>
                                                        ) : (
                                                            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                                                <Typography variant="body2" sx={{ fontWeight: 600, color: '#9f1239' }}>No template assigned.</Typography>
                                                                <Button size="small" variant="outlined" color="error" onClick={() => handleOpenEditor(null, event.id)}>Create Now</Button>
                                                            </Box>
                                                        )}
                                                    </Box>
                                                </Paper>
                                            </Grid>
                                        );
                                    })}
                                </Grid>
                            </Box>
                        )}

                        {/* TAB 3: AUDIT LOG */}
                        {currentTab === 2 && (
                            <Table stickyHeader>
                                <TableHead>
                                    <TableRow>
                                        <TableCell sx={{ fontWeight: 600 }}>Date & Time</TableCell>
                                        <TableCell sx={{ fontWeight: 600 }}>Recipient</TableCell>
                                        <TableCell sx={{ fontWeight: 600 }}>Template Used</TableCell>
                                        <TableCell sx={{ fontWeight: 600 }}>Status</TableCell>
                                        <TableCell align="right" sx={{ fontWeight: 600 }}>Action</TableCell>
                                    </TableRow>
                                </TableHead>
                                <TableBody>
                                    {deliveries.map(log => (
                                        <TableRow key={log.id} hover>
                                            <TableCell><Typography variant="body2">{log.sent_at}</Typography></TableCell>
                                            <TableCell><Typography variant="body2">{log.recipient}</Typography></TableCell>
                                            <TableCell><Typography variant="body2">{log.template_name}</Typography></TableCell>
                                            <TableCell>
                                                {log.status === 'sent' && <Chip size="small" label="Sent" color="success" />}
                                                {log.status === 'pending' && <Chip size="small" label={`Pending (Retry ${log.retry_count})`} color="warning" />}
                                                {log.status === 'failed' && (
                                                    <Tooltip title={log.error_log}>
                                                        <Chip size="small" label="Failed" color="error" />
                                                    </Tooltip>
                                                )}
                                            </TableCell>
                                            <TableCell align="right">
                                                {log.status === 'failed' && (
                                                    <Button size="small" startIcon={<Replay />} onClick={() => handleRetryEmail(log.id)}>Retry</Button>
                                                )}
                                            </TableCell>
                                        </TableRow>
                                    ))}
                                </TableBody>
                            </Table>
                        )}
                    </Box>
                </Paper>

                {/* FULL-SCREEN EDITOR DRAWER */}
                <Drawer anchor="right" open={drawerOpen} onClose={() => setDrawerOpen(false)}>
                    <Box sx={{ marginTop: 6, width: '60vw', minWidth: 600, p: 4, display: 'flex', flexDirection: 'column', height: '100%' }}>
                        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
                            <Typography variant="h5" sx={{ fontWeight: 700 }}>{editForm.id ? 'Edit Template' : 'New Template'}</Typography>
                            <Button variant="contained" onClick={handleSaveTemplate} disabled={!editForm.name || !editForm.subject}>
                                Save Configuration
                            </Button>
                            <Button variant="outlined" onClick={() => setDrawerOpen(false)}>Cancel</Button>
                        </Box>

                        <Grid container spacing={4} sx={{ flexGrow: 1 }}>
                            <Grid item xs={12} md={8}>
                                <Stack spacing={3}>
                                    <TextField
                                        label="Template Name (Internal)" fullWidth required
                                        value={editForm.name} onChange={e => setEditForm({...editForm, name: e.target.value})}
                                    />
                                    <TextField
                                        select label="System Event Mapping" fullWidth required
                                        value={editForm.event_trigger} onChange={e => setEditForm({...editForm, event_trigger: e.target.value})}
                                    >
                                        {SYSTEM_EVENTS.map(ev => <MenuItem key={ev.id} value={ev.id}>{ev.label}</MenuItem>)}
                                    </TextField>
                                    <TextField
                                        label="Email Subject Line" fullWidth required
                                        value={editForm.subject} onChange={e => setEditForm({...editForm, subject: e.target.value})}
                                        helperText="You can use Liquid tags here, e.g., Welcome {{user.first_name}}!"
                                    />

                                    <Divider />
                                    <Typography variant="subtitle2">HTML Body (Liquid Supported)</Typography>
                                    {/* Note: Replace this multiline TextField with TipTap or MUI-RTE in production */}
                                    <RichTextEditor
                                        value={editForm.html_body || ''}
                                        onChange={(newHtml) => setEditForm({...editForm, html_body: newHtml})}
                                    />
                                </Stack>
                            </Grid>

                            {/* LIQUID HELPER SIDEBAR */}
                            <Grid item xs={12} md={4}>
                                <Paper variant="outlined" sx={{ p: 2, bgcolor: '#f8f9fa', borderRadius: 2 }}>
                                    <Typography variant="subtitle2" sx={{ mb: 2, fontWeight: 700 }}>Available Liquid Tags</Typography>
                                    {editForm.event_trigger ? (
                                        <Stack spacing={1}>
                                            <Typography variant="caption" color="textSecondary">Click to copy variables for <strong>{editForm.event_trigger}</strong>:</Typography>
                                            {getAvailableVariables(editForm.event_trigger).map(vr => (
                                                <Chip
                                                    key={vr} label={`{{ ${vr} }}`} size="small" variant="outlined"
                                                    icon={<ContentCopy fontSize="small" />}
                                                    onClick={() => {
                                                        navigator.clipboard.writeText(`{{ ${vr} }}`);
                                                        notify("Copied to clipboard!", "success");
                                                    }}
                                                    sx={{ justifyContent: 'flex-start', cursor: 'pointer', fontFamily: 'monospace' }}
                                                />
                                            ))}
                                        </Stack>
                                    ) : (
                                        <Alert severity="warning" icon={false} sx={{ py: 0 }}>Select a System Event Mapping to see available variables.</Alert>
                                    )}
                                </Paper>
                            </Grid>
                        </Grid>
                    </Box>
                </Drawer>
            </Box>
        </Box>
    );
}