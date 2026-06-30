import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  Box, Typography, Grid, Card, CardContent, Paper,
  Button, Stack, Chip, Divider, List, ListItem,
  ListItemText, ListItemIcon, Switch, Tooltip, IconButton,
  Dialog, DialogTitle, DialogContent, DialogActions,
  TextField, MenuItem, CircularProgress, Alert, Skeleton,
} from '@mui/material';
import {
  Route, PlayArrow, Stop, SmartToy,
  AccountTree, Gavel, AutoFixHigh, CheckCircle,
  Sensors, Extension, Speed, History, Edit, Delete,
  Bolt, Refresh, ErrorOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

// ─── constants ────────────────────────────────────────────────────────────────

const TRIGGER_EVENTS = ['asset.staged', 'asset.updated', 'schedule.nightly', 'manual'];
const AGENT_MODELS   = ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo', 'claude-3-5-sonnet-20241022', 'llama-3-local'];
const COMMON_TOOLS   = [
  'VisualContextExtractor', 'SEOTaxonomyMapper', 'ExifReader',
  'WatermarkDetector', 'QuarantineAction', 'JsonSchemaValidator', 'DatabasePatcher',
];
const TELEMETRY_POLL_MS = 15000;

const EMPTY_FORM = {
  name: '',
  description: '',
  trigger_event: 'asset.staged',
  agent_model: 'gpt-4o-mini',
  tools_enabled: [],
  active: false,
};

// ─── helpers ──────────────────────────────────────────────────────────────────

function csrf() {
  return document.querySelector('[name="csrf-token"]')?.content;
}

async function apiFetch(url, options = {}) {
  const res = await fetch(url, {
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrf(),
      Accept: 'application/json',
      ...(options.headers || {}),
    },
    ...options,
  });
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || data.errors?.join(', ') || `HTTP ${res.status}`);
  return data;
}

function statusIcon(status) {
  switch (status) {
    case 'success': return <AutoFixHigh fontSize="small" sx={{ color: '#10b981' }} />;
    case 'warning': return <Gavel fontSize="small" sx={{ color: '#f59e0b' }} />;
    case 'failed':  return <ErrorOutlined fontSize="small" sx={{ color: '#ef4444' }} />;
    default:        return <CircularProgress size={16} sx={{ color: '#0ea5e9' }} />;
  }
}

function formatLatency(ms) {
  if (ms == null) return '—';
  return ms >= 1000 ? `${(ms / 1000).toFixed(1)}s` : `${ms}ms`;
}

// ─── Workflow form dialog ─────────────────────────────────────────────────────

function WorkflowDialog({ open, initial, onClose, onSaved, t }) {
  const [form, setForm]     = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [error, setError]   = useState(null);
  const isEdit = Boolean(initial?.id);

  useEffect(() => {
    setForm(initial ? { ...EMPTY_FORM, ...initial } : EMPTY_FORM);
    setError(null);
  }, [initial, open]);

  const handleSave = async () => {
    if (!form.name.trim()) {
      setError(t('agents.form.nameRequired', { defaultValue: 'Name is required.' }));
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const url    = isEdit ? `/api/v1/agent_workflows/${initial.id}` : '/api/v1/agent_workflows';
      const method = isEdit ? 'PATCH' : 'POST';
      const saved  = await apiFetch(url, {
        method,
        body: JSON.stringify({ agent_workflow: form }),
      });
      onSaved(saved, isEdit);
      onClose();
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  const toggleTool = (tool) => {
    setForm((f) => ({
      ...f,
      tools_enabled: f.tools_enabled.includes(tool)
        ? f.tools_enabled.filter((x) => x !== tool)
        : [...f.tools_enabled, tool],
    }));
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle sx={{ fontWeight: 700 }}>
        {isEdit
          ? t('agents.form.editTitle', { defaultValue: 'Edit Workflow' })
          : t('agents.form.createTitle', { defaultValue: 'Create New Workflow' })}
      </DialogTitle>
      <DialogContent dividers>
        {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
        <Stack spacing={2.5} sx={{ mt: 0.5 }}>
          <TextField label={t('agents.form.name', {
  defaultValue: 'Name'
})} value={form.name} onChange={e => setForm({
  ...form,
  name: e.target.value
})} fullWidth required autoFocus slotProps={{
  htmlInput: {
    maxLength: 120
  }
}} />
          <TextField
            label={t('agents.form.description', { defaultValue: 'Description' })}
            value={form.description || ''}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
            fullWidth
            multiline
            minRows={2}
          />
          <TextField
            select
            label={t('agents.form.trigger', { defaultValue: 'Trigger Event' })}
            value={form.trigger_event}
            onChange={(e) => setForm({ ...form, trigger_event: e.target.value })}
            fullWidth
          >
            {TRIGGER_EVENTS.map((ev) => (
              <MenuItem key={ev} value={ev}>
                <Typography sx={{ fontFamily: 'monospace', fontSize: '0.85rem' }}>{ev}</Typography>
              </MenuItem>
            ))}
          </TextField>
          <TextField
            select
            label={t('agents.form.model', { defaultValue: 'Agent Model' })}
            value={form.agent_model}
            onChange={(e) => setForm({ ...form, agent_model: e.target.value })}
            fullWidth
          >
            {AGENT_MODELS.map((m) => (
              <MenuItem key={m} value={m}>
                <Typography sx={{ fontFamily: 'monospace', fontSize: '0.85rem' }}>{m}</Typography>
              </MenuItem>
            ))}
          </TextField>

          <Box>
            <Typography variant="caption" sx={{ fontWeight: 600, mb: 1, display: 'block' }}>
              {t('agents.form.tools', { defaultValue: 'Capabilities (Tools)' })}
            </Typography>
            <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.75 }}>
              {COMMON_TOOLS.map((tool) => {
                const on = form.tools_enabled.includes(tool);
                return (
                  <Chip
                    key={tool}
                    label={tool}
                    size="small"
                    onClick={() => toggleTool(tool)}
                    variant={on ? 'filled' : 'outlined'}
                    color={on ? 'primary' : 'default'}
                    sx={{ cursor: 'pointer', fontSize: '0.7rem' }}
                  />
                );
              })}
            </Box>
          </Box>

          <Stack direction="row" spacing={1} sx={{
  alignItems: "center"
}}>
            <Switch
              checked={form.active}
              onChange={(e) => setForm({ ...form, active: e.target.checked })}
            />
            <Typography variant="body2">
              {t('agents.form.activeOnSave', { defaultValue: 'Activate immediately on save' })}
            </Typography>
          </Stack>
        </Stack>
      </DialogContent>
      <DialogActions sx={{ px: 3, py: 2 }}>
        <Button onClick={onClose} color="inherit">
          {t('common.cancel', { defaultValue: 'Cancel' })}
        </Button>
        <Button
          onClick={handleSave}
          variant="contained"
          disabled={saving}
          startIcon={saving ? <CircularProgress size={16} color="inherit" /> : null}
          sx={{ bgcolor: '#0ea5e9', '&:hover': { bgcolor: '#0284c7' } }}
        >
          {saving
            ? t('common.saving', { defaultValue: 'Saving…' })
            : t('common.save', { defaultValue: 'Save' })}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

// ─── Workflow card ────────────────────────────────────────────────────────────

function WorkflowCard({ wf, onToggle, onEdit, onDelete, onTrigger, busy, t }) {
  return (
    <Card
      elevation={0}
      sx={{
        border: '1px solid',
        borderColor: wf.active ? '#bae6fd' : '#e2e8f0',
        borderRadius: 3,
        transition: 'all 0.2s',
        ...(wf.active && { boxShadow: '0 4px 20px rgba(14,165,233,0.05)' }),
      }}
    >
      <CardContent sx={{ p: 3 }}>
        <Stack direction="row" sx={{
  mb: 2,
  alignItems: "flex-start",
  justifyContent: "space-between"
}}>
          <Box>
            <Stack direction="row" spacing={1.5} sx={{
  mb: 0.5,
  alignItems: "center"
}}>
              <Typography variant="h6" sx={{ fontWeight: 600 }}>{wf.name}</Typography>
              {wf.active ? (
                <Chip label={t('agents.status.listening', { defaultValue: 'Listening' })}
                  size="small" color="success" sx={{ height: 20, fontSize: '0.7rem' }}
                  icon={<PlayArrow sx={{ fontSize: '1rem' }} />} />
              ) : (
                <Chip label={t('agents.status.halted', { defaultValue: 'Halted' })}
                  size="small" sx={{ height: 20, fontSize: '0.7rem', bgcolor: '#f1f5f9' }}
                  icon={<Stop sx={{ fontSize: '1rem' }} />} />
              )}
            </Stack>
            <Typography variant="body2" color="text.secondary">{wf.description}</Typography>
          </Box>
          <Stack direction="row" spacing={0.5} sx={{
  alignItems: "center"
}}>
            {wf.trigger_event === 'manual' && (
              <Tooltip title={t('agents.triggerNow', { defaultValue: 'Trigger now' })}>
                <span>
                  <IconButton size="small" onClick={() => onTrigger(wf)} disabled={busy}
                    aria-label={t('agents.triggerNow', { defaultValue: 'Trigger now' })}>
                    <Bolt fontSize="small" sx={{ color: '#f59e0b' }} />
                  </IconButton>
                </span>
              </Tooltip>
            )}
            <Tooltip title={t('common.edit', { defaultValue: 'Edit' })}>
              <IconButton size="small" onClick={() => onEdit(wf)}
                aria-label={t('common.edit', { defaultValue: 'Edit' })}>
                <Edit fontSize="small" />
              </IconButton>
            </Tooltip>
            <Tooltip title={t('common.delete', { defaultValue: 'Delete' })}>
              <IconButton size="small" onClick={() => onDelete(wf)}
                aria-label={t('common.delete', { defaultValue: 'Delete' })}>
                <Delete fontSize="small" sx={{ color: '#ef4444' }} />
              </IconButton>
            </Tooltip>
            <Switch checked={wf.active} onChange={() => onToggle(wf)} disabled={busy} color="primary" />
          </Stack>
        </Stack>

        {/* Pipeline visualiser */}
        <Box sx={{ mt: 3, p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px dashed #cbd5e1' }}>
          <Grid container spacing={2} sx={{ alignItems: 'center' }}>
            <Grid size={3}>
              <Paper elevation={0} sx={{ p: 1.5, textAlign: 'center', border: '1px solid #e2e8f0', bgcolor: '#fff' }}>
                <Sensors sx={{ color: '#64748b', mb: 0.5 }} />
                <Typography variant="caption" sx={{ display: 'block', fontWeight: 600, color: '#475569' }}>
                  {t('agents.node.trigger', { defaultValue: 'Event Trigger' })}
                </Typography>
                <Typography variant="caption" sx={{ fontFamily: 'monospace', color: '#0ea5e9' }}>
                  {wf.trigger_event}
                </Typography>
              </Paper>
            </Grid>
            <Grid size={1} sx={{ textAlign: 'center', color: '#94a3b8' }}>➔</Grid>
            <Grid size={4}>
              <Paper elevation={0} sx={{ p: 1.5, textAlign: 'center', border: '1px solid #c7d2fe', bgcolor: '#e0e7ff' }}>
                <SmartToy sx={{ color: '#4f46e5', mb: 0.5 }} />
                <Typography variant="caption" sx={{ display: 'block', fontWeight: 600, color: '#3730a3' }}>
                  {t('agents.node.agent', { defaultValue: 'AI Agent' })}
                </Typography>
                <Typography variant="caption" sx={{ fontFamily: 'monospace', color: '#4f46e5' }}>
                  {wf.agent_model}
                </Typography>
              </Paper>
            </Grid>
            <Grid size={1} sx={{ textAlign: 'center', color: '#94a3b8' }}>➔</Grid>
            <Grid size={3}>
              <Paper elevation={0} sx={{ p: 1.5, textAlign: 'center', border: '1px solid #e2e8f0', bgcolor: '#fff' }}>
                <Extension sx={{ color: '#64748b', mb: 0.5 }} />
                <Typography variant="caption" sx={{ display: 'block', fontWeight: 600, color: '#475569' }}>
                  {t('agents.node.tools', { defaultValue: 'Capabilities' })}
                </Typography>
                <Typography variant="caption" color="text.secondary">
                  {t('agents.toolsLoaded', { count: wf.tools_enabled.length, defaultValue: `${wf.tools_enabled.length} tools` })}
                </Typography>
              </Paper>
            </Grid>
          </Grid>
        </Box>

        {/* Operational stats */}
        <Stack direction="row" spacing={4} sx={{ mt: 3, pt: 2, borderTop: '1px solid #f1f5f9' }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <CheckCircle sx={{ fontSize: 16, color: '#10b981' }} />
            <Typography variant="caption" color="text.secondary">
              {t('agents.reliability', { defaultValue: 'Reliability' })}:&nbsp;
              <strong>{wf.reliability != null ? `${wf.reliability}%` : '—'}</strong>
            </Typography>
          </Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <Speed sx={{ fontSize: 16, color: '#8b5cf6' }} />
            <Typography variant="caption" color="text.secondary">
              {t('agents.avgLatency', { defaultValue: 'Avg Latency' })}:&nbsp;
              <strong>{formatLatency(wf.avg_duration_ms)}</strong>
            </Typography>
          </Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <History sx={{ fontSize: 16, color: '#64748b' }} />
            <Typography variant="caption" color="text.secondary">
              {t('agents.runs', { count: wf.execution_count, defaultValue: `${wf.execution_count} runs` })}
            </Typography>
          </Box>
        </Stack>
      </CardContent>
    </Card>
  );
}

// ─── Main component ───────────────────────────────────────────────────────────

export default function AgentWorkflows() {
  const { t } = useTranslation();

  const [workflows, setWorkflows]   = useState([]);
  const [telemetry, setTelemetry]   = useState([]);
  const [loading, setLoading]       = useState(true);
  const [error, setError]           = useState(null);
  const [busyId, setBusyId]         = useState(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing]       = useState(null);
  const pollRef = useRef(null);

  // ── Load workflows ──
  const loadWorkflows = useCallback(async () => {
    try {
      const data = await apiFetch('/api/v1/agent_workflows');
      setWorkflows(data);
      setError(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  // ── Load recent telemetry across workflows (latest 12) ──
  const loadTelemetry = useCallback(async (wfList) => {
    const list = wfList ?? workflows;
    if (!list.length) { setTelemetry([]); return; }
    try {
      const slices = await Promise.all(
        list.slice(0, 5).map((wf) =>
          apiFetch(`/api/v1/agent_workflows/${wf.id}/executions?page=1`)
            .then((r) => (r.executions || []).map((e) => ({ ...e, workflow_name: wf.name })))
            .catch(() => []),
        ),
      );
      const merged = slices.flat()
        .sort((a, b) => new Date(b.started_at) - new Date(a.started_at))
        .slice(0, 12);
      setTelemetry(merged);
    } catch {
      /* telemetry is best-effort */
    }
  }, [workflows]);

  useEffect(() => {
    loadWorkflows();
  }, [loadWorkflows]);

  useEffect(() => {
    if (!loading && workflows.length) {
      loadTelemetry(workflows);
      pollRef.current = setInterval(() => loadTelemetry(workflows), TELEMETRY_POLL_MS);
      return () => clearInterval(pollRef.current);
    }
    return undefined;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loading, workflows]);

  // ── Handlers ──
  const handleToggle = async (wf) => {
    setBusyId(wf.id);
    setWorkflows((prev) => prev.map((w) => (w.id === wf.id ? { ...w, active: !w.active } : w)));
    try {
      await apiFetch(`/api/v1/agent_workflows/${wf.id}/toggle`, { method: 'PATCH' });
    } catch (e) {
      setWorkflows((prev) => prev.map((w) => (w.id === wf.id ? { ...w, active: wf.active } : w)));
      setError(e.message);
    } finally {
      setBusyId(null);
    }
  };

  const handleTrigger = async (wf) => {
    setBusyId(wf.id);
    try {
      await apiFetch(`/api/v1/agent_workflows/${wf.id}/trigger`, { method: 'POST' });
    } catch (e) {
      setError(e.message);
    } finally {
      setBusyId(null);
    }
  };

  const handleDelete = async (wf) => {
    // eslint-disable-next-line no-alert
    if (!window.confirm(t('agents.confirmDelete', { name: wf.name, defaultValue: `Delete "${wf.name}"?` }))) return;
    setBusyId(wf.id);
    try {
      await apiFetch(`/api/v1/agent_workflows/${wf.id}`, { method: 'DELETE' });
      setWorkflows((prev) => prev.filter((w) => w.id !== wf.id));
    } catch (e) {
      setError(e.message);
    } finally {
      setBusyId(null);
    }
  };

  const handleSaved = (saved, isEdit) => {
    setWorkflows((prev) =>
      isEdit ? prev.map((w) => (w.id === saved.id ? saved : w)) : [saved, ...prev]);
  };

  const openCreate = () => { setEditing(null); setDialogOpen(true); };
  const openEdit   = (wf) => { setEditing(wf); setDialogOpen(true); };

  return (
    <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
      <Stack direction="row" sx={{
  mb: 4,
  alignItems: "flex-end",
  justifyContent: "space-between"
}}>
        <Box>
          <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', mb: 1, display: 'flex', alignItems: 'center' }}>
            <Route sx={{ mr: 1.5, color: '#0ea5e9', fontSize: 32 }} />
            {t('agents.title', { defaultValue: 'Agent Automations' })}
          </Typography>
          <Typography variant="body2" color="text.secondary">
            {t('agents.subtitle', { defaultValue: 'Orchestrate autonomous AI agents. Map system events to AI operational workflows.' })}
          </Typography>
        </Box>
        <Button variant="contained" startIcon={<AccountTree />} onClick={openCreate}
          sx={{ bgcolor: '#0ea5e9', '&:hover': { bgcolor: '#0284c7' } }}>
          {t('agents.createNew', { defaultValue: 'Create New Workflow' })}
        </Button>
      </Stack>

      {error && (
        <Alert severity="error" sx={{ mb: 3 }} onClose={() => setError(null)}>{error}</Alert>
      )}

      <Grid container spacing={3}>
        {/* Main canvas */}
        <Grid size={{ xs: 12, lg: 8 }}>
          <Stack spacing={3}>
            {loading ? (
              [1, 2].map((i) => (
                <Skeleton key={i} variant="rounded" height={240} sx={{ borderRadius: 3 }} />
              ))
            ) : workflows.length === 0 ? (
              <Paper elevation={0} sx={{ p: 6, textAlign: 'center', border: '1px dashed #cbd5e1', borderRadius: 3 }}>
                <Route sx={{ fontSize: 48, color: '#cbd5e1', mb: 2 }} />
                <Typography variant="h6" color="text.secondary" sx={{ fontWeight: 600 }}>
                  {t('agents.emptyTitle', { defaultValue: 'No workflows yet' })}
                </Typography>
                <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5, mb: 3 }}>
                  {t('agents.emptyBody', { defaultValue: 'Create your first autonomous agent to start automating DAM operations.' })}
                </Typography>
                <Button variant="contained" startIcon={<AccountTree />} onClick={openCreate}
                  sx={{ bgcolor: '#0ea5e9', '&:hover': { bgcolor: '#0284c7' } }}>
                  {t('agents.createNew', { defaultValue: 'Create New Workflow' })}
                </Button>
              </Paper>
            ) : (
              workflows.map((wf) => (
                <WorkflowCard
                  key={wf.id}
                  wf={wf}
                  busy={busyId === wf.id}
                  onToggle={handleToggle}
                  onEdit={openEdit}
                  onDelete={handleDelete}
                  onTrigger={handleTrigger}
                  t={t}
                />
              ))
            )}
          </Stack>
        </Grid>

        {/* Telemetry sidebar */}
        <Grid size={{ xs: 12, lg: 4 }}>
          <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%', display: 'flex', flexDirection: 'column' }}>
            <Box sx={{ p: 2.5, borderBottom: '1px solid #e3e8ef', display: 'flex', alignItems: 'center', gap: 1.5 }}>
              <History sx={{ color: '#64748b' }} />
              <Typography variant="h6" sx={{ fontWeight: 600, flexGrow: 1 }}>
                {t('agents.telemetry', { defaultValue: 'Agent Telemetry' })}
              </Typography>
              <Tooltip title={t('common.refresh', { defaultValue: 'Refresh' })}>
                <IconButton size="small" onClick={() => loadTelemetry(workflows)}
                  aria-label={t('common.refresh', { defaultValue: 'Refresh' })}>
                  <Refresh fontSize="small" />
                </IconButton>
              </Tooltip>
            </Box>
            <List sx={{ flexGrow: 1, overflowY: 'auto', p: 0, maxHeight: 600 }}>
              {telemetry.length === 0 ? (
                <Box sx={{ p: 4, textAlign: 'center', color: '#94a3b8' }}>
                  <Typography variant="body2">
                    {t('agents.noTelemetry', { defaultValue: 'No agent activity yet.' })}
                  </Typography>
                </Box>
              ) : (
                telemetry.map((log, index) => (
                  <React.Fragment key={log.id}>
                    <ListItem sx={{ p: 2.5, alignItems: 'flex-start' }}>
                      <ListItemIcon sx={{ minWidth: 36, mt: 0.5 }}>
                        {statusIcon(log.status)}
                      </ListItemIcon>
                      <ListItemText
                        primary={
                          <Stack direction="row" sx={{
  mb: 0.5,
  justifyContent: "space-between"
}}>
                            <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>
                              {log.workflow_name}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              {log.started_at ? new Date(log.started_at).toLocaleTimeString() : ''}
                            </Typography>
                          </Stack>
                        }
                        secondary={log.summary || log.error_message || t(`agents.statusLabel.${log.status}`, { defaultValue: log.status })}
                        slotProps={{ secondary: { variant: 'body2', color: '#475569', component: 'span' } }}
                      />
                    </ListItem>
                    {index < telemetry.length - 1 && <Divider component="li" />}
                  </React.Fragment>
                ))
              )}
            </List>
          </Paper>
        </Grid>
      </Grid>

      <WorkflowDialog
        open={dialogOpen}
        initial={editing}
        onClose={() => setDialogOpen(false)}
        onSaved={handleSaved}
        t={t}
      />
    </Box>
  );
}
