import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  Box, Typography, Grid, Paper, Button, Stack,
  TextField, MenuItem, Table, TableBody, TableCell, TableContainer,
  TableHead, TableRow, Chip, Alert, Skeleton, Tooltip, IconButton,
  CircularProgress, Tab, Tabs, Switch, FormControlLabel, Dialog,
  DialogTitle, DialogContent, DialogActions, LinearProgress,
} from '@mui/material';
import {
  AutoAwesome, Add, Refresh, Delete, CheckCircleOutlined,
  ErrorOutlined, HourglassEmpty, FiberManualRecord, Sync, Star,
  StarBorder, RocketLaunch, Palette, SmartToy, HealthAndSafety,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

// ─── constants ────────────────────────────────────────────────────────────────

const POLL_MS = 5000;
const ACTIVE_STATUSES = ['queued', 'running'];

const HEALTH_COLORS = {
  healthy:   'success',
  degraded:  'warning',
  unhealthy: 'error',
  unknown:   'default',
};

const CAPABILITY_ICONS = {
  embedding:      '🔢',
  generation:     '✨',
  vision:         '👁️',
  style_transfer: '🎨',
  audio:          '🎵',
};

const STYLE_HUB_BATCH_TASKS = ['embed_regenerate', 'style_audit', 'style_tag'];

// ─── helpers ─────────────────────────────────────────────────────────────────

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

function HealthChip({ status }) {
  const { t } = useTranslation();
  return (
    <Chip
      size="small"
      icon={status === 'healthy' ? <CheckCircleOutlined /> : status === 'unhealthy' ? <ErrorOutlined /> : <HourglassEmpty />}
      label={t(`styleHub.health.${status}`, { defaultValue: status })}
      color={HEALTH_COLORS[status] || 'default'}
      variant="outlined"
    />
  );
}

// ─── sub-panels ──────────────────────────────────────────────────────────────

function ModelsPanel({ t }) {
  const [configs, setConfigs]   = useState([]);
  const [caps, setCaps]         = useState({});
  const [loading, setLoading]   = useState(true);
  const [error, setError]       = useState(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editTarget, setEditTarget] = useState(null);
  const [form, setForm] = useState({ name: '', provider: 'openai', model_id: '', capability: 'generation', enabled: true });
  const [saving, setSaving] = useState(false);
  const [pingId, setPingId]   = useState(null);

  const loadAll = useCallback(async () => {
    try {
      const [data, capData] = await Promise.all([
        apiFetch('/api/v1/ai_model_configs'),
        apiFetch('/api/v1/ai_model_configs/capabilities'),
      ]);
      setConfigs(data.configs || []);
      setCaps(capData);
      setError(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadAll(); }, [loadAll]);

  const openCreate = () => {
    setEditTarget(null);
    setForm({ name: '', provider: 'openai', model_id: '', capability: 'generation', enabled: true });
    setDialogOpen(true);
  };

  const openEdit = (cfg) => {
    setEditTarget(cfg);
    setForm({ name: cfg.name, provider: cfg.provider, model_id: cfg.model_id, capability: cfg.capability, enabled: cfg.enabled });
    setDialogOpen(true);
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      if (editTarget) {
        const updated = await apiFetch(`/api/v1/ai_model_configs/${editTarget.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ ai_model_config: form }),
        });
        setConfigs((prev) => prev.map((c) => (c.id === updated.id ? updated : c)));
      } else {
        const created = await apiFetch('/api/v1/ai_model_configs', {
          method: 'POST',
          body: JSON.stringify({ ai_model_config: form }),
        });
        setConfigs((prev) => [created, ...prev]);
      }
      setDialogOpen(false);
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (cfg) => {
    if (!window.confirm(t('styleHub.models.confirmDelete', { name: cfg.name, defaultValue: `Delete "${cfg.name}"?` }))) return;
    try {
      await apiFetch(`/api/v1/ai_model_configs/${cfg.id}`, { method: 'DELETE' });
      setConfigs((prev) => prev.filter((c) => c.id !== cfg.id));
    } catch (e) {
      setError(e.message);
    }
  };

  const handleHealthCheck = async (cfg) => {
    setPingId(cfg.id);
    try {
      await apiFetch(`/api/v1/ai_model_configs/${cfg.id}/health_check`, { method: 'POST' });
    } catch (e) {
      setError(e.message);
    } finally {
      setTimeout(() => { setPingId(null); loadAll(); }, 2000);
    }
  };

  const handleSetDefault = async (cfg) => {
    try {
      const updated = await apiFetch(`/api/v1/ai_model_configs/${cfg.id}/set_default`, { method: 'POST' });
      setConfigs((prev) => prev.map((c) => {
        if (c.capability !== updated.capability) return c;
        return { ...c, is_default: c.id === updated.id };
      }));
    } catch (e) {
      setError(e.message);
    }
  };

  return (
    <Box>
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>{error}</Alert>}
      <Stack direction="row" sx={{
  mb: 2,
  alignItems: "center",
  justifyContent: "space-between"
}}>
        <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
          {t('styleHub.models.title', { defaultValue: 'Registered AI Models' })}
        </Typography>
        <Stack direction="row" spacing={1}>
          <Tooltip title={t('common.refresh')}>
            <IconButton size="small" onClick={loadAll} aria-label={t('common.refresh')}><Refresh fontSize="small" /></IconButton>
          </Tooltip>
          <Button variant="contained" size="small" startIcon={<Add />} onClick={openCreate}
            sx={{ bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' } }}>
            {t('styleHub.models.addModel', { defaultValue: 'Add Model' })}
          </Button>
        </Stack>
      </Stack>

      <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 2 }}>
        <Table size="small">
          <TableHead>
            <TableRow>
              <TableCell sx={{ fontWeight: 600, bgcolor: '#f8fafc' }}>{t('styleHub.models.name', { defaultValue: 'Name' })}</TableCell>
              <TableCell sx={{ fontWeight: 600, bgcolor: '#f8fafc' }}>{t('styleHub.models.capability', { defaultValue: 'Capability' })}</TableCell>
              <TableCell sx={{ fontWeight: 600, bgcolor: '#f8fafc' }}>{t('styleHub.models.provider', { defaultValue: 'Provider' })}</TableCell>
              <TableCell sx={{ fontWeight: 600, bgcolor: '#f8fafc' }}>{t('styleHub.models.health', { defaultValue: 'Health' })}</TableCell>
              <TableCell sx={{ fontWeight: 600, bgcolor: '#f8fafc' }}>{t('styleHub.models.status', { defaultValue: 'Status' })}</TableCell>
              <TableCell sx={{ fontWeight: 600, bgcolor: '#f8fafc' }} align="right">{t('common.actions')}</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow><TableCell colSpan={6}><Skeleton height={32} /></TableCell></TableRow>
            ) : configs.length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} align="center" sx={{ py: 4, color: '#94a3b8' }}>
                  <SmartToy sx={{ fontSize: 40, opacity: 0.4, display: 'block', mx: 'auto', mb: 1 }} />
                  {t('styleHub.models.empty', { defaultValue: 'No models registered yet. Add your first AI model.' })}
                </TableCell>
              </TableRow>
            ) : (
              configs.map((cfg) => (
                <TableRow key={cfg.id} hover>
                  <TableCell>
                    <Stack direction="row" spacing={0.5} sx={{
  alignItems: "center"
}}>
                      {cfg.is_default && <Tooltip title={t('styleHub.models.isDefault', { defaultValue: 'Default for capability' })}><Star sx={{ fontSize: 14, color: '#f59e0b' }} /></Tooltip>}
                      <Box>
                        <Typography variant="body2" sx={{ fontWeight: 600 }}>{cfg.name}</Typography>
                        <Typography variant="caption" color="text.secondary" sx={{ fontFamily: 'monospace' }}>{cfg.model_id}</Typography>
                      </Box>
                    </Stack>
                  </TableCell>
                  <TableCell>
                    <Chip size="small" label={`${CAPABILITY_ICONS[cfg.capability] || ''} ${cfg.capability}`} variant="outlined" />
                  </TableCell>
                  <TableCell>
                    <Typography variant="body2">{cfg.provider}</Typography>
                  </TableCell>
                  <TableCell><HealthChip status={cfg.health_status} /></TableCell>
                  <TableCell>
                    <Chip size="small"
                      label={cfg.enabled ? t('common.active') : t('common.inactive')}
                      color={cfg.enabled ? 'success' : 'default'}
                      variant="outlined" />
                  </TableCell>
                  <TableCell align="right">
                    <Stack direction="row" spacing={0.5} sx={{
  justifyContent: "flex-end"
}}>
                      <Tooltip title={t('styleHub.models.setDefault', { defaultValue: 'Set as default' })}>
                        <IconButton size="small" onClick={() => handleSetDefault(cfg)} aria-label={t('styleHub.models.setDefault', { defaultValue: 'Set as default' })}>
                          {cfg.is_default ? <Star sx={{ color: '#f59e0b', fontSize: 16 }} /> : <StarBorder sx={{ fontSize: 16 }} />}
                        </IconButton>
                      </Tooltip>
                      <Tooltip title={t('styleHub.models.healthCheck', { defaultValue: 'Ping health' })}>
                        <span>
                          <IconButton size="small" onClick={() => handleHealthCheck(cfg)} disabled={pingId === cfg.id} aria-label={t('styleHub.models.healthCheck', { defaultValue: 'Ping health' })}>
                            {pingId === cfg.id ? <CircularProgress size={14} /> : <HealthAndSafety sx={{ fontSize: 16 }} />}
                          </IconButton>
                        </span>
                      </Tooltip>
                      <Tooltip title={t('common.edit')}>
                        <IconButton size="small" onClick={() => openEdit(cfg)} aria-label={t('common.edit')}><SmartToy sx={{ fontSize: 16 }} /></IconButton>
                      </Tooltip>
                      <Tooltip title={t('common.delete')}>
                        <IconButton size="small" onClick={() => handleDelete(cfg)} aria-label={t('common.delete')}><Delete sx={{ fontSize: 16, color: '#ef4444' }} /></IconButton>
                      </Tooltip>
                    </Stack>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

      {/* Add / Edit Dialog */}
      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{editTarget ? t('styleHub.models.editModel', { defaultValue: 'Edit Model' }) : t('styleHub.models.addModel', { defaultValue: 'Add Model' })}</DialogTitle>
        <DialogContent>
          <Stack spacing={2} sx={{ mt: 1 }}>
            <TextField label={t('styleHub.models.name', { defaultValue: 'Name' })} fullWidth value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
            <TextField select label={t('styleHub.models.provider', { defaultValue: 'Provider' })} fullWidth value={form.provider} onChange={(e) => setForm((f) => ({ ...f, provider: e.target.value }))}>
              {(caps.providers || AiModelConfig_PROVIDERS_FALLBACK).map((p) => <MenuItem key={p} value={p}>{p}</MenuItem>)}
            </TextField>
            <TextField label={t('styleHub.models.modelId', { defaultValue: 'Model ID' })} fullWidth value={form.model_id} onChange={(e) => setForm((f) => ({ ...f, model_id: e.target.value }))} helperText={t('styleHub.models.modelIdHelp', { defaultValue: 'e.g. gpt-4o, text-embedding-3-small, llava-1.6' })} />
            <TextField select label={t('styleHub.models.capability', { defaultValue: 'Capability' })} fullWidth value={form.capability} onChange={(e) => setForm((f) => ({ ...f, capability: e.target.value }))}>
              {(caps.capabilities || AiModelConfig_CAPABILITIES_FALLBACK).map((c) => <MenuItem key={c} value={c}>{CAPABILITY_ICONS[c]} {c}</MenuItem>)}
            </TextField>
            <FormControlLabel control={<Switch checked={form.enabled} onChange={(e) => setForm((f) => ({ ...f, enabled: e.target.checked }))} />} label={t('styleHub.models.enabled', { defaultValue: 'Enabled' })} />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>{t('common.cancel')}</Button>
          <Button variant="contained" onClick={handleSave} disabled={saving || !form.name || !form.model_id}
            sx={{ bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' } }}>
            {saving ? <CircularProgress size={18} color="inherit" /> : t('common.save')}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

// Fallbacks used before capabilities endpoint loads
const AiModelConfig_PROVIDERS_FALLBACK = ['openai', 'anthropic', 'ollama', 'huggingface', 'azure_openai', 'custom'];
const AiModelConfig_CAPABILITIES_FALLBACK = ['embedding', 'generation', 'vision', 'style_transfer', 'audio'];

// ─────────────────────────────────────────────────────────────────────────────

function StylePresetsPanel({ t }) {
  const [presets, setPresets]   = useState([]);
  const [loading, setLoading]   = useState(true);
  const [error, setError]       = useState(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editTarget, setEditTarget] = useState(null);
  const [form, setForm] = useState({ name: '', description: '', active: true, style_params: '{}' });
  const [saving, setSaving]   = useState(false);
  const [syncingId, setSyncingId] = useState(null);

  const load = useCallback(async () => {
    try {
      const data = await apiFetch('/api/v1/style_presets');
      setPresets(data.presets || []);
      setError(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const openCreate = () => {
    setEditTarget(null);
    setForm({ name: '', description: '', active: true, style_params: '{}' });
    setDialogOpen(true);
  };

  const openEdit = (preset) => {
    setEditTarget(preset);
    setForm({ name: preset.name, description: preset.description || '', active: preset.active, style_params: JSON.stringify(preset.style_params, null, 2) });
    setDialogOpen(true);
  };

  const handleSave = async () => {
    setSaving(true);
    let parsedParams = {};
    try { parsedParams = JSON.parse(form.style_params || '{}'); } catch {}
    const body = { style_preset: { name: form.name, description: form.description, active: form.active, style_params: parsedParams } };
    try {
      if (editTarget) {
        const updated = await apiFetch(`/api/v1/style_presets/${editTarget.id}`, { method: 'PATCH', body: JSON.stringify(body) });
        setPresets((prev) => prev.map((p) => (p.id === updated.id ? updated : p)));
      } else {
        const created = await apiFetch('/api/v1/style_presets', { method: 'POST', body: JSON.stringify(body) });
        setPresets((prev) => [created, ...prev]);
      }
      setDialogOpen(false);
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (preset) => {
    if (!window.confirm(t('styleHub.presets.confirmDelete', { name: preset.name, defaultValue: `Delete "${preset.name}"?` }))) return;
    try {
      await apiFetch(`/api/v1/style_presets/${preset.id}`, { method: 'DELETE' });
      setPresets((prev) => prev.filter((p) => p.id !== preset.id));
    } catch (e) {
      setError(e.message);
    }
  };

  const handleSync = async (preset) => {
    setSyncingId(preset.id);
    try {
      await apiFetch(`/api/v1/style_presets/${preset.id}/sync`, { method: 'POST' });
      setTimeout(() => { setSyncingId(null); load(); }, 1500);
    } catch (e) {
      setError(e.message);
      setSyncingId(null);
    }
  };

  const handleSetDefault = async (preset) => {
    try {
      const updated = await apiFetch(`/api/v1/style_presets/${preset.id}/set_default`, { method: 'POST' });
      setPresets((prev) => prev.map((p) => ({ ...p, is_default: p.id === updated.id })));
    } catch (e) {
      setError(e.message);
    }
  };

  return (
    <Box>
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>{error}</Alert>}
      <Stack direction="row" sx={{
  mb: 2,
  alignItems: "center",
  justifyContent: "space-between"
}}>
        <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
          {t('styleHub.presets.title', { defaultValue: 'Style Presets' })}
        </Typography>
        <Stack direction="row" spacing={1}>
          <Tooltip title={t('common.refresh')}><IconButton size="small" onClick={load} aria-label={t('common.refresh')}><Refresh fontSize="small" /></IconButton></Tooltip>
          <Button variant="contained" size="small" startIcon={<Add />} onClick={openCreate}
            sx={{ bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' } }}>
            {t('styleHub.presets.addPreset', { defaultValue: 'New Preset' })}
          </Button>
        </Stack>
      </Stack>

      {loading ? (
        <Grid container spacing={2}>
          {[1, 2, 3].map((i) => <Grid key={i} size={{ xs: 12, sm: 6, md: 4 }}><Skeleton variant="rounded" height={140} /></Grid>)}
        </Grid>
      ) : presets.length === 0 ? (
        <Paper elevation={0} sx={{ p: 6, border: '1px solid #e3e8ef', borderRadius: 2, textAlign: 'center', color: '#94a3b8' }}>
          <Palette sx={{ fontSize: 48, opacity: 0.4, mb: 1 }} />
          <Typography>{t('styleHub.presets.empty', { defaultValue: 'No style presets yet. Create your first brand style profile.' })}</Typography>
        </Paper>
      ) : (
        <Grid container spacing={2}>
          {presets.map((preset) => (
            <Grid key={preset.id} size={{ xs: 12, sm: 6, md: 4 }}>
              <Paper elevation={0} sx={{ p: 2.5, border: `1px solid ${preset.is_default ? '#8b5cf6' : '#e3e8ef'}`, borderRadius: 2, height: '100%', position: 'relative' }}>
                {preset.is_default && (
                  <Chip size="small" icon={<Star sx={{ fontSize: 12 }} />} label={t('styleHub.presets.default', { defaultValue: 'Default' })} color="primary" sx={{ position: 'absolute', top: 8, right: 8, height: 20, fontSize: 11 }} />
                )}
                <Stack direction="row" spacing={1} sx={{
  mb: 1,
  alignItems: "center"
}}>
                  <Palette sx={{ color: '#8b5cf6', fontSize: 20 }} />
                  <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>{preset.name}</Typography>
                </Stack>
                <Typography variant="caption" color="text.secondary" sx={{ fontFamily: 'monospace', display: 'block', mb: 1 }}>
                  {preset.slug}
                </Typography>
                {preset.description && (
                  <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5, fontSize: 12 }}>
                    {preset.description}
                  </Typography>
                )}
                <Stack direction="row" spacing={0.5} sx={{ mb: 1.5, flexWrap: 'wrap', gap: 0.5 }}>
                  <Chip size="small" label={preset.active ? t('common.active') : t('common.inactive')} color={preset.active ? 'success' : 'default'} variant="outlined" />
                  {preset.synced_at
                    ? <Chip size="small" icon={<FiberManualRecord sx={{ fontSize: 8 }} />} label={preset.stale ? t('styleHub.presets.stale', { defaultValue: 'Stale' }) : t('styleHub.presets.synced', { defaultValue: 'Synced' })} color={preset.stale ? 'warning' : 'success'} variant="outlined" />
                    : <Chip size="small" label={t('styleHub.presets.notSynced', { defaultValue: 'Not synced' })} color="default" variant="outlined" />
                  }
                </Stack>
                <Stack direction="row" spacing={0.5}>
                  <Tooltip title={t('styleHub.presets.syncToGateway', { defaultValue: 'Sync to Gateway' })}>
                    <span>
                      <IconButton size="small" onClick={() => handleSync(preset)} disabled={syncingId === preset.id} aria-label={t('styleHub.presets.syncToGateway', { defaultValue: 'Sync to Gateway' })}>
                        {syncingId === preset.id ? <CircularProgress size={14} /> : <Sync sx={{ fontSize: 16 }} />}
                      </IconButton>
                    </span>
                  </Tooltip>
                  <Tooltip title={t('styleHub.presets.setDefault', { defaultValue: 'Set as default' })}>
                    <IconButton size="small" onClick={() => handleSetDefault(preset)} aria-label={t('styleHub.presets.setDefault', { defaultValue: 'Set as default' })}>
                      {preset.is_default ? <Star sx={{ color: '#f59e0b', fontSize: 16 }} /> : <StarBorder sx={{ fontSize: 16 }} />}
                    </IconButton>
                  </Tooltip>
                  <Tooltip title={t('common.edit')}>
                    <IconButton size="small" onClick={() => openEdit(preset)} aria-label={t('common.edit')}><Palette sx={{ fontSize: 16 }} /></IconButton>
                  </Tooltip>
                  <Tooltip title={t('common.delete')}>
                    <IconButton size="small" onClick={() => handleDelete(preset)} aria-label={t('common.delete')}><Delete sx={{ fontSize: 16, color: '#ef4444' }} /></IconButton>
                  </Tooltip>
                </Stack>
              </Paper>
            </Grid>
          ))}
        </Grid>
      )}

      {/* Create / Edit Dialog */}
      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{editTarget ? t('styleHub.presets.editPreset', { defaultValue: 'Edit Style Preset' }) : t('styleHub.presets.addPreset', { defaultValue: 'New Style Preset' })}</DialogTitle>
        <DialogContent>
          <Stack spacing={2} sx={{ mt: 1 }}>
            <TextField label={t('styleHub.presets.name', { defaultValue: 'Name' })} fullWidth value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
            <TextField label={t('styleHub.presets.description', { defaultValue: 'Description' })} fullWidth multiline rows={2} value={form.description} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} />
            <TextField
              label={t('styleHub.presets.styleParams', { defaultValue: 'Style Parameters (JSON)' })}
              fullWidth multiline rows={5}
              value={form.style_params}
              onChange={(e) => setForm((f) => ({ ...f, style_params: e.target.value }))}
              helperText={t('styleHub.presets.styleParamsHelp', { defaultValue: 'e.g. {"tone": "editorial", "palette": ["#1a1a1a","#ffffff"], "aspect_ratio": "16:9"}' })}
              slotProps={{ htmlInput: { style: { fontFamily: 'monospace', fontSize: 12 } } }}
            />
            <FormControlLabel control={<Switch checked={form.active} onChange={(e) => setForm((f) => ({ ...f, active: e.target.checked }))} />} label={t('common.active')} />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>{t('common.cancel')}</Button>
          <Button variant="contained" onClick={handleSave} disabled={saving || !form.name}
            sx={{ bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' } }}>
            {saving ? <CircularProgress size={18} color="inherit" /> : t('common.save')}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

// ─────────────────────────────────────────────────────────────────────────────

function BatchPanel({ t }) {
  const [meta, setMeta]     = useState({ tasks: [], scopes: [] });
  const [jobs, setJobs]     = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError]   = useState(null);
  const [submitting, setSubmitting] = useState(false);
  const [taskType, setTaskType]   = useState('');
  const [targetScope, setTargetScope] = useState('');
  const [concurrency, setConcurrency] = useState(25);
  const pollRef = useRef(null);

  const loadJobs = useCallback(async () => {
    try {
      const data = await apiFetch('/api/v1/ai_batch_jobs');
      const filtered = (data.jobs || []).filter((j) => STYLE_HUB_BATCH_TASKS.includes(j.task_type));
      setJobs(filtered);
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => {
    (async () => {
      try {
        const m = await apiFetch('/api/v1/ai_batch_jobs/task_types');
        const filteredTasks = (m.tasks || []).filter((t) => STYLE_HUB_BATCH_TASKS.includes(t.key));
        const filteredScopes = (m.scopes || []).filter((s) => ['all_images_unembedded', 'style_untagged', 'all_assets', 'all_images'].includes(s.key));
        setMeta({ tasks: filteredTasks, scopes: filteredScopes });
        if (filteredTasks.length) setTaskType(filteredTasks[0].key);
        if (filteredScopes.length) setTargetScope(filteredScopes[0].key);
        await loadJobs();
      } catch (e) {
        setError(e.message);
      } finally {
        setLoading(false);
      }
    })();
  }, [loadJobs]);

  const hasActive = jobs.some((j) => ACTIVE_STATUSES.includes(j.status));
  useEffect(() => {
    if (!hasActive) return undefined;
    pollRef.current = setInterval(loadJobs, POLL_MS);
    return () => clearInterval(pollRef.current);
  }, [hasActive, loadJobs]);

  const handleLaunch = async () => {
    if (!taskType || !targetScope) return;
    setSubmitting(true);
    try {
      const job = await apiFetch('/api/v1/ai_batch_jobs', {
        method: 'POST',
        body: JSON.stringify({ ai_batch_job: { task_type: taskType, target_scope: targetScope, concurrency: Number(concurrency) || 25 } }),
      });
      setJobs((prev) => [job, ...prev]);
    } catch (e) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  };

  const activeJob = jobs.find((j) => ACTIVE_STATUSES.includes(j.status));

  return (
    <Box>
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>{error}</Alert>}
      <Grid container spacing={3}>
        <Grid size={{ xs: 12, md: 4 }}>
          <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 2 }}>
            <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 2 }}>{t('styleHub.batch.config', { defaultValue: 'Launch Batch Task' })}</Typography>
            {loading ? <Stack spacing={2}>{[1, 2, 3].map((i) => <Skeleton key={i} variant="rounded" height={56} />)}</Stack> : (
              <Stack spacing={2}>
                <TextField select fullWidth label={t('styleHub.batch.task', { defaultValue: 'Style Task' })} value={taskType} onChange={(e) => setTaskType(e.target.value)} disabled={submitting}>
                  {meta.tasks.map((t) => <MenuItem key={t.key} value={t.key}>{t.label}</MenuItem>)}
                </TextField>
                <TextField select fullWidth label={t('styleHub.batch.scope', { defaultValue: 'Target Dataset' })} value={targetScope} onChange={(e) => setTargetScope(e.target.value)} disabled={submitting}>
                  {meta.scopes.map((s) => <MenuItem key={s.key} value={s.key}>{s.label}</MenuItem>)}
                </TextField>
                <TextField type="number" fullWidth label={t('styleHub.batch.concurrency', { defaultValue: 'Concurrency' })} value={concurrency} onChange={(e) => setConcurrency(e.target.value)} disabled={submitting} slotProps={{ htmlInput: { min: 1, max: 500 } }} />
                <Button variant="contained" startIcon={submitting ? <CircularProgress size={18} color="inherit" /> : <RocketLaunch />}
                  onClick={handleLaunch} disabled={submitting || !taskType || !targetScope}
                  sx={{ bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' } }}>
                  {submitting ? t('styleHub.batch.launching', { defaultValue: 'Launching…' }) : t('styleHub.batch.launch', { defaultValue: 'Launch Task' })}
                </Button>
              </Stack>
            )}
          </Paper>
        </Grid>
        <Grid size={{ xs: 12, md: 8 }}>
          <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 2 }}>
            <Stack direction="row" sx={{
  mb: 2,
  alignItems: "center",
  justifyContent: "space-between"
}}>
              <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>{t('styleHub.batch.history', { defaultValue: 'Batch History' })}</Typography>
              <IconButton size="small" onClick={loadJobs} aria-label={t('common.refresh')}><Refresh fontSize="small" /></IconButton>
            </Stack>
            {activeJob && (
              <Box sx={{ mb: 2, p: 2, bgcolor: '#f5f3ff', borderRadius: 2, border: '1px solid #ddd6fe' }}>
                <Stack direction="row" sx={{
  mb: 1,
  justifyContent: "space-between"
}}>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>{activeJob.task_label || activeJob.task_type}</Typography>
                  <Chip label={`${activeJob.progress_percent}%`} color="secondary" size="small" />
                </Stack>
                <LinearProgress variant={activeJob.total_count > 0 ? 'determinate' : 'indeterminate'}
                  value={activeJob.progress_percent}
                  sx={{ height: 8, borderRadius: 4, bgcolor: '#ede9fe', '& .MuiLinearProgress-bar': { bgcolor: '#8b5cf6' } }} />
              </Box>
            )}
            <TableContainer sx={{ border: '1px solid #f1f5f9', borderRadius: 2 }}>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell sx={{ fontWeight: 600, bgcolor: '#f8fafc' }}>{t('styleHub.batch.taskCol', { defaultValue: 'Task' })}</TableCell>
                    <TableCell sx={{ fontWeight: 600, bgcolor: '#f8fafc' }}>{t('styleHub.batch.statusCol', { defaultValue: 'Status' })}</TableCell>
                    <TableCell sx={{ fontWeight: 600, bgcolor: '#f8fafc' }} align="right">{t('styleHub.batch.progressCol', { defaultValue: 'Progress' })}</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {loading ? (
                    <TableRow><TableCell colSpan={3}><Skeleton height={28} /></TableCell></TableRow>
                  ) : jobs.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={3} align="center" sx={{ py: 4, color: '#94a3b8' }}>
                        {t('styleHub.batch.empty', { defaultValue: 'No style batch runs yet.' })}
                      </TableCell>
                    </TableRow>
                  ) : (
                    jobs.map((job) => (
                      <TableRow key={job.id}>
                        <TableCell>
                          <Typography variant="body2" sx={{ fontWeight: 600 }}>{job.task_label || job.task_type}</Typography>
                          <Typography variant="caption" color="text.secondary">{job.target_scope}</Typography>
                        </TableCell>
                        <TableCell>
                          <Chip size="small" label={job.status} color={job.status === 'completed' ? 'success' : job.status === 'failed' ? 'error' : 'default'} variant="outlined" sx={{ height: 22 }} />
                        </TableCell>
                        <TableCell align="right">
                          <Typography variant="body2" sx={{ fontWeight: 600, color: '#8b5cf6' }}>{job.progress_percent}%</Typography>
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </TableContainer>
          </Paper>
        </Grid>
      </Grid>
    </Box>
  );
}

// ─── main component ──────────────────────────────────────────────────────────

export default function StyleModelHub() {
  const { t } = useTranslation();
  const [tab, setTab] = useState(0);

  return (
    <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
      <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', mb: 1, display: 'flex', alignItems: 'center' }}>
        <AutoAwesome sx={{ mr: 1.5, color: '#8b5cf6', fontSize: 32 }} />
        {t('styleHub.title', { defaultValue: 'Style & Model Hub' })}
      </Typography>
      <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
        {t('styleHub.subtitle', { defaultValue: 'Manage AI model endpoints, brand style presets, and launch style-related batch tasks across your asset library.' })}
      </Typography>

      <Tabs value={tab} onChange={(_, v) => setTab(v)} sx={{
  mb: 3,
  borderBottom: '1px solid #e3e8ef'
}} slotProps={{
  indicator: {
    style: {
      backgroundColor: '#8b5cf6'
    }
  }
}}>
        <Tab icon={<SmartToy fontSize="small" />} iconPosition="start" label={t('styleHub.tabs.models', { defaultValue: 'Models' })} sx={{ '&.Mui-selected': { color: '#8b5cf6' } }} />
        <Tab icon={<Palette fontSize="small" />} iconPosition="start" label={t('styleHub.tabs.styles', { defaultValue: 'Style Presets' })} sx={{ '&.Mui-selected': { color: '#8b5cf6' } }} />
        <Tab icon={<RocketLaunch fontSize="small" />} iconPosition="start" label={t('styleHub.tabs.batch', { defaultValue: 'Batch Tasks' })} sx={{ '&.Mui-selected': { color: '#8b5cf6' } }} />
      </Tabs>

      {tab === 0 && <ModelsPanel t={t} />}
      {tab === 1 && <StylePresetsPanel t={t} />}
      {tab === 2 && <BatchPanel t={t} />}
    </Box>
  );
}

