import React, { useState, useEffect, useCallback, useMemo } from 'react';
import {
  Box, Typography, Paper, Button, Stack, TextField, MenuItem,
  Table, TableBody, TableCell, TableContainer, TableHead, TableRow,
  Chip, Alert, Skeleton, IconButton, Switch, FormControlLabel,
  CircularProgress,
} from '@mui/material';
import {
  VerifiedUser, SmartToy, ReportProblem, HelpOutlined, Shield,
  Refresh, Policy, RocketLaunch, History, InfoOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

// ── constants ─────────────────────────────────────────────────────────────────

const C2PA_TASKS = ['c2pa_verify', 'c2pa_sign', 'ai_disclosure_audit'];

const STATUS_COLORS = {
  unchecked:    'default',
  verified:     'success',
  ai_generated: 'warning',
  ai_modified:  'warning',
  missing:      'info',
  invalid:      'error',
  signed:       'success',
  error:        'error',
};

// Factory — new element each call to avoid React 19 reuse-across-render errors.
function statusIcon(status) {
  switch (status) {
    case 'verified':     return <VerifiedUser sx={{ fontSize: 14 }} />;
    case 'ai_generated': return <SmartToy sx={{ fontSize: 14 }} />;
    case 'ai_modified':  return <SmartToy sx={{ fontSize: 14 }} />;
    case 'invalid':      return <ReportProblem sx={{ fontSize: 14 }} />;
    case 'missing':      return <HelpOutlined sx={{ fontSize: 14 }} />;
    case 'signed':       return <Shield sx={{ fontSize: 14 }} />;
    default:             return null;
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

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

// ── Stat card ─────────────────────────────────────────────────────────────────

function StatCard({ label, value, color, icon, loading }) {
  return (
    <Paper elevation={0} sx={{ p: 2.5, border: '1px solid #e3e8ef', borderRadius: 3, height: '100%' }}>
      <Stack direction="row" spacing={1.5} sx={{ alignItems: 'center' }}>
        <Box sx={{ color, fontSize: 28 }}>{icon}</Box>
        <Box>
          {loading
            ? <Skeleton width={40} height={28} />
            : <Typography variant="h5" sx={{ fontWeight: 700, lineHeight: 1 }}>{value ?? '—'}</Typography>}
          <Typography variant="caption" color="text.secondary">{label}</Typography>
        </Box>
      </Stack>
    </Paper>
  );
}

// ── Policy form ───────────────────────────────────────────────────────────────

function PolicyPanel({ config, onSaved, t }) {
  const [form, setForm] = useState(config);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => { setForm(config); }, [config]);

  const toggle = (key) => setForm((f) => ({ ...f, [key]: !f[key] }));
  const set = (key, val) => setForm((f) => ({ ...f, [key]: val }));

  const handleSave = async () => {
    setSaving(true);
    setError(null);
    setSaved(false);
    try {
      await apiFetch('/api/v1/c2pa_configuration', {
        method: 'PATCH',
        body: JSON.stringify({ c2pa_configuration: form }),
      });
      setSaved(true);
      onSaved(form);
      setTimeout(() => setSaved(false), 3000);
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  if (!form) return <Skeleton height={200} />;

  return (
    <Stack spacing={3}>
      {error && <Alert severity="error" onClose={() => setError(null)}>{error}</Alert>}
      {saved && <Alert severity="success">{t('provenance.policy.saved')}</Alert>}

      <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 2 }}>
        <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 2, color: '#8b5cf6' }}>
          {t('provenance.policy.gatewaySection')}
        </Typography>
        <FormControlLabel
          control={<Switch checked={!!form.gateway_c2pa_enabled} onChange={() => toggle('gateway_c2pa_enabled')} color="secondary" />}
          label={t('provenance.policy.gatewayEnabled')}
        />
      </Paper>

      <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 2 }}>
        <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 2, color: '#8b5cf6' }}>
          {t('provenance.policy.ingestSection')}
        </Typography>
        <Stack spacing={1}>
          <FormControlLabel
            control={<Switch checked={!!form.auto_verify_on_ingest} onChange={() => toggle('auto_verify_on_ingest')} color="secondary" />}
            label={t('provenance.policy.autoVerify')}
          />
          <FormControlLabel
            control={<Switch checked={!!form.auto_sign_on_ingest} onChange={() => toggle('auto_sign_on_ingest')} color="secondary" />}
            label={t('provenance.policy.autoSign')}
          />
          <FormControlLabel
            control={<Switch checked={!!form.require_c2pa_on_import} onChange={() => toggle('require_c2pa_on_import')} color="secondary" />}
            label={t('provenance.policy.requireOnImport')}
          />
          <FormControlLabel
            control={<Switch checked={!!form.ai_disclosure_required} onChange={() => toggle('ai_disclosure_required')} color="secondary" />}
            label={t('provenance.policy.aiDisclosureRequired')}
          />
        </Stack>
      </Paper>

      <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 2 }}>
        <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 2, color: '#8b5cf6' }}>
          {t('provenance.policy.signingSection')}
        </Typography>
        <Stack spacing={2}>
          <TextField
            fullWidth size="small"
            label={t('provenance.policy.signingIssuerName')}
            value={form.signing_issuer_name || ''}
            onChange={(e) => set('signing_issuer_name', e.target.value)}
          />
          <TextField
            fullWidth size="small"
            label={t('provenance.policy.signingOrg')}
            value={form.signing_org || ''}
            onChange={(e) => set('signing_org', e.target.value)}
          />
          <TextField
            select fullWidth size="small"
            label={t('provenance.policy.strictness')}
            value={form.verification_strictness || 'lenient'}
            onChange={(e) => set('verification_strictness', e.target.value)}
          >
            <MenuItem value="lenient">{t('provenance.policy.lenient')}</MenuItem>
            <MenuItem value="strict">{t('provenance.policy.strict')}</MenuItem>
          </TextField>
        </Stack>
      </Paper>

      <TextField
        fullWidth multiline minRows={2}
        label={t('provenance.policy.policyNotes')}
        value={form.policy_notes || ''}
        onChange={(e) => set('policy_notes', e.target.value)}
      />

      <Button
        variant="contained" size="large"
        startIcon={saving ? <CircularProgress size={18} color="inherit" /> : <Policy />}
        onClick={handleSave}
        disabled={saving}
        sx={{ bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' }, alignSelf: 'flex-start' }}
      >
        {saving ? t('provenance.policy.saving') : t('provenance.policy.save')}
      </Button>
    </Stack>
  );
}

// ── Batch actions panel ───────────────────────────────────────────────────────

function BatchActionsPanel({ t }) {
  const [meta, setMeta] = useState({ tasks: [], scopes: [] });
  const [taskType, setTaskType] = useState('');
  const [targetScope, setTargetScope] = useState('');
  const [concurrency, setConcurrency] = useState(25);
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    apiFetch('/api/v1/ai_batch_jobs/task_types')
      .then((m) => {
        if (cancelled) return;
        const filtered = { ...m, tasks: (m.tasks || []).filter((t) => C2PA_TASKS.includes(t.key)) };
        setMeta(filtered);
        if (filtered.tasks.length) setTaskType(filtered.tasks[0].key);
        if (filtered.scopes.length) setTargetScope(filtered.scopes[0].key);
      })
      .catch((e) => { if (!cancelled) setError(e.message); });
    return () => { cancelled = true; };
  }, []);

  const selectedTask = meta.tasks.find((t) => t.key === taskType);

  const handleLaunch = async () => {
    setSubmitting(true);
    setError(null);
    setResult(null);
    try {
      const job = await apiFetch('/api/v1/ai_batch_jobs', {
        method: 'POST',
        body: JSON.stringify({ ai_batch_job: { task_type: taskType, target_scope: targetScope, concurrency: Number(concurrency) || 25 } }),
      });
      setResult(job);
    } catch (e) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Stack spacing={3}>
      {error && <Alert severity="error" onClose={() => setError(null)}>{error}</Alert>}
      {result && (
        <Alert severity="success">
          {t('provenance.batch.launched', { id: result.id, defaultValue: `Job #${result.id} queued — ${result.task_label || result.task_type}` })}
        </Alert>
      )}
      <TextField
        select fullWidth
        label={t('provenance.batch.task')}
        value={taskType}
        onChange={(e) => setTaskType(e.target.value)}
        disabled={submitting}
        helperText={selectedTask?.description}
      >
        {meta.tasks.map((t) => (
          <MenuItem key={t.key} value={t.key}>
            <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
              <span>{t.label}</span>
              <Chip size="small" label={t.cost_tier} variant="outlined" color={t.cost_tier === 'high' ? 'error' : t.cost_tier === 'medium' ? 'warning' : 'success'} />
            </Stack>
          </MenuItem>
        ))}
      </TextField>
      <TextField
        select fullWidth
        label={t('provenance.batch.scope')}
        value={targetScope}
        onChange={(e) => setTargetScope(e.target.value)}
        disabled={submitting}
      >
        {meta.scopes.map((s) => (
          <MenuItem key={s.key} value={s.key}>{s.label}</MenuItem>
        ))}
      </TextField>
      <TextField
        type="number" fullWidth
        label={t('provenance.batch.concurrency')}
        value={concurrency}
        onChange={(e) => setConcurrency(e.target.value)}
        disabled={submitting}
        slotProps={{ htmlInput: { min: 1, max: 500 } }}
      />
      <Button
        variant="contained" size="large"
        startIcon={submitting ? <CircularProgress size={18} color="inherit" /> : <RocketLaunch />}
        onClick={handleLaunch}
        disabled={submitting || !taskType || !targetScope}
        sx={{ bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' }, alignSelf: 'flex-start' }}
      >
        {submitting ? t('provenance.batch.launching') : t('provenance.batch.launch')}
      </Button>
    </Stack>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

export default function ProvenanceC2PA() {
  const { t } = useTranslation();

  const [tab, setTab] = useState(0);
  const [stats, setStats] = useState(null);
  const [records, setRecords] = useState([]);
  const [recordsTotal, setRecordsTotal] = useState(0);
  const [config, setConfig] = useState(null);
  const [statusFilter, setStatusFilter] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [refreshKey, setRefreshKey] = useState(0);

  const refresh = useCallback(() => {
    setLoading(true);
    setRefreshKey((k) => k + 1);
  }, []);

  useEffect(() => {
    let cancelled = false;

    const recordsUrl = `/api/v1/asset_provenance_records${statusFilter ? `?status=${statusFilter}` : ''}`;

    Promise.all([
      apiFetch('/api/v1/asset_provenance_records/stats'),
      apiFetch(recordsUrl),
      apiFetch('/api/v1/c2pa_configuration'),
    ])
      .then(([s, r, c]) => {
        if (cancelled) return;
        setStats(s);
        setRecords(r.records || []);
        setRecordsTotal(r.total || 0);
        setConfig(c);
        setError(null);
      })
      .catch((e) => {
        if (!cancelled) setError(e.message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => { cancelled = true; };
  }, [statusFilter, refreshKey]);


  // useMemo prevents new icon element objects on every render — avoids React 19
  // element-reuse-across-render errors (same issue the statusIcon factory solves).
  const STAT_CARDS = useMemo(() => [
    { key: 'verified',    label: t('provenance.stats.verified'),    color: '#22c55e', icon: <VerifiedUser /> },
    { key: 'ai_flagged',  label: t('provenance.stats.aiModified'),  color: '#f59e0b', icon: <SmartToy /> },
    { key: 'missing',     label: t('provenance.stats.missing'),     color: '#64748b', icon: <HelpOutlined /> },
    { key: 'invalid',     label: t('provenance.stats.invalid'),     color: '#ef4444', icon: <ReportProblem /> },
    { key: 'signed',      label: t('provenance.stats.signed'),      color: '#8b5cf6', icon: <Shield /> },
  ], [t]);

  return (
    <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
      {/* Header */}
      <Stack direction="row" sx={{ alignItems: 'flex-start', justifyContent: 'space-between', mb: 4 }}>
        <Box>
          <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', mb: 0.5, display: 'flex', alignItems: 'center', gap: 1 }}>
            <Shield sx={{ color: '#8b5cf6', fontSize: 32 }} />
            {t('provenance.title')}
          </Typography>
          <Typography variant="body2" color="textSecondary" sx={{ maxWidth: 640 }}>
            {t('provenance.subtitle')}
          </Typography>
        </Box>
        <IconButton onClick={refresh} aria-label={t('common.refresh')}>
            <Refresh />
          </IconButton>
      </Stack>

      {error && <Alert severity="error" sx={{ mb: 3 }} onClose={() => setError(null)}>{error}</Alert>}

      {/* Stats row */}
      <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', mb: 4 }}>
        {STAT_CARDS.map(({ key, label, color, icon }) => (
          <Box key={key} sx={{ flex: '1 1 160px', minWidth: 0 }}>
            <StatCard label={label} value={stats?.[key]} color={color} icon={icon} loading={loading} />
          </Box>
        ))}
      </Box>

      {/* Tabs */}
      <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, overflow: 'hidden' }}>
        {/* Custom tab bar — avoids MUI Tabs' DOM manipulation that breaks in jsdom */}
        <Stack direction="row" spacing={0} sx={{ borderBottom: '1px solid #e3e8ef', px: 2, bgcolor: '#fafbfc' }}>
          {[
            { label: t('provenance.tabs.records'), icon: <History sx={{ fontSize: 16 }} /> },
            { label: t('provenance.tabs.policy'),  icon: <Policy sx={{ fontSize: 16 }} /> },
            { label: t('provenance.tabs.batch'),   icon: <RocketLaunch sx={{ fontSize: 16 }} /> },
          ].map(({ label, icon }, i) => (
            <Button
              key={i}
              size="small"
              startIcon={icon}
              onClick={() => setTab(i)}
              sx={{
                borderRadius: 0,
                borderBottom: tab === i ? '2px solid #8b5cf6' : '2px solid transparent',
                color: tab === i ? '#8b5cf6' : 'text.secondary',
                fontWeight: tab === i ? 600 : 400,
                px: 2, py: 1.5,
              }}
            >
              {label}
            </Button>
          ))}
        </Stack>

        <Box sx={{ p: 3 }}>
          {/* Tab 0: Records */}
          {tab === 0 && (
            <Stack spacing={2}>
              <Stack direction="row" spacing={2} sx={{ alignItems: 'center' }}>
                <TextField
                  select size="small" label={t('provenance.table.filterStatus')} value={statusFilter}
                  onChange={(e) => setStatusFilter(e.target.value)} sx={{ minWidth: 200 }}
                  slotProps={{ select: { MenuProps: { disablePortal: true } } }}
                >
                  <MenuItem value="">{t('common.all', { defaultValue: 'All' })}</MenuItem>
                  {AssetProvenanceRecord_STATUSES.map((s) => (
                    <MenuItem key={s} value={s}>{t(`provenance.statusLabel.${s}`, { defaultValue: s })}</MenuItem>
                  ))}
                </TextField>
                <Typography variant="caption" color="text.secondary">
                  {t('provenance.table.total', { count: recordsTotal, defaultValue: `${recordsTotal} records` })}
                </Typography>
              </Stack>

              <TableContainer sx={{ border: '1px solid #f1f5f9', borderRadius: 2 }}>
                {loading ? (
                  <Stack spacing={1} sx={{ p: 2 }}>
                    {[1, 2, 3].map((i) => <Skeleton key={i} height={32} />)}
                  </Stack>
                ) : (
                <Table size="small">
                  <TableHead>
                    <TableRow>
                      <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }}>{t('provenance.table.asset')}</TableCell>
                      <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }}>{t('provenance.table.status')}</TableCell>
                      <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }}>{t('provenance.table.claimGenerator')}</TableCell>
                      <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }}>{t('provenance.table.aiModified')}</TableCell>
                      <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }}>{t('provenance.table.verifiedAt')}</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {records.length === 0 ? (
                      <TableRow>
                        <TableCell colSpan={5} align="center" sx={{ py: 4, color: '#94a3b8' }}>
                          <InfoOutlined sx={{ fontSize: 40, opacity: 0.5, mb: 1, display: 'block', mx: 'auto' }} />
                          {t('provenance.empty')}
                        </TableCell>
                      </TableRow>
                    ) : (
                      records.map((rec) => (
                        <TableRow key={rec.id} hover>
                          <TableCell>
                            <Typography variant="body2" sx={{ fontWeight: 600 }}>{rec.asset_title || rec.asset_uuid}</Typography>
                            <Typography variant="caption" color="text.secondary" sx={{ fontFamily: 'monospace' }}>{rec.asset_uuid}</Typography>
                          </TableCell>
                          <TableCell>
                            <Chip
                              icon={statusIcon(rec.manifest_status)}
                              label={t(`provenance.statusLabel.${rec.manifest_status}`, { defaultValue: rec.manifest_status })}
                              size="small"
                              color={STATUS_COLORS[rec.manifest_status] || 'default'}
                              variant="outlined"
                              sx={{ height: 22 }}
                            />
                          </TableCell>
                          <TableCell>
                            <Typography variant="caption">{rec.claim_generator || '—'}</Typography>
                          </TableCell>
                          <TableCell>
                            {rec.is_ai_modified
                              ? <Chip icon={<SmartToy sx={{ fontSize: 14 }} />} label="AI" size="small" color="warning" sx={{ height: 20 }} />
                              : <Typography variant="caption" color="text.secondary">—</Typography>}
                          </TableCell>
                          <TableCell>
                            <Typography variant="caption">
                              {rec.verified_at ? new Date(rec.verified_at).toLocaleDateString() : '—'}
                            </Typography>
                          </TableCell>
                        </TableRow>
                      ))
                    )}
                  </TableBody>
                </Table>
                )}
              </TableContainer>
            </Stack>
          )}

          {/* Tab 1: Policy */}
          {tab === 1 && (
            loading
              ? <Stack spacing={2}>{[1, 2, 3].map((i) => <Skeleton key={i} height={56} />)}</Stack>
              : <PolicyPanel config={config} onSaved={setConfig} t={t} />
          )}

          {/* Tab 2: Batch Actions */}
          {tab === 2 && <BatchActionsPanel t={t} />}
        </Box>
      </Paper>
    </Box>
  );
}

// Statuses for the filter dropdown (avoids importing the model constant)
const AssetProvenanceRecord_STATUSES = [
  'unchecked', 'verified', 'ai_generated', 'ai_modified',
  'missing', 'invalid', 'signed', 'error',
];

