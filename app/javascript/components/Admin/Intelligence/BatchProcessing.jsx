import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  Box, Typography, Grid, Paper, Button, Stack,
  TextField, MenuItem, LinearProgress, Table, TableBody,
  TableCell, TableContainer, TableHead, TableRow, Chip,
  Alert, Skeleton, Tooltip, IconButton, CircularProgress,
} from '@mui/material';
import {
  QueryStats, FilterAlt, RocketLaunch, CheckCircleOutlined,
  ErrorOutlined, PauseCircleOutlined, Refresh, StopCircleOutlined,
  HourglassEmpty,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

// ─── constants ──────────────────────────────────────────────────────────────

const POLL_MS = 4000;
const ACTIVE_STATUSES = ['queued', 'running', 'paused'];

const STATUS_COLORS = {
  queued: 'default',
  running: 'secondary',
  paused: 'warning',
  completed: 'success',
  failed: 'error',
  cancelled: 'default',
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

function statusChipColor(status) {
  return STATUS_COLORS[status] || 'default';
}

// ─── main component ───────────────────────────────────────────────────────────

export default function BatchProcessing() {
  const { t } = useTranslation();

  const [meta, setMeta] = useState({ tasks: [], scopes: [] });
  const [jobs, setJobs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [submitting, setSubmitting] = useState(false);
  const [busyId, setBusyId] = useState(null);
  const pollRef = useRef(null);

  // Form state
  const [taskType, setTaskType] = useState('');
  const [targetScope, setTargetScope] = useState('');
  const [concurrency, setConcurrency] = useState(25);

  const selectedTask = meta.tasks.find((task) => task.key === taskType);

  // ── Load existing jobs ──
  const loadJobs = useCallback(async () => {
    try {
      const data = await apiFetch('/api/v1/ai_batch_jobs');
      setJobs(data.jobs || []);
      setError(null);
    } catch (e) {
      setError(e.message);
    }
  }, []);

  // ── Load registry metadata + jobs on mount ──
  useEffect(() => {
    (async () => {
      try {
        const m = await apiFetch('/api/v1/ai_batch_jobs/task_types');
        setMeta(m);
        if (m.tasks?.length) setTaskType(m.tasks[0].key);
        if (m.scopes?.length) setTargetScope(m.scopes[0].key);
        await loadJobs();
      } catch (e) {
        setError(e.message);
      } finally {
        setLoading(false);
      }
    })();
  }, [loadJobs]);

  // ── Poll while any job is active ──
  const hasActive = jobs.some((j) => ACTIVE_STATUSES.includes(j.status));
  useEffect(() => {
    if (!hasActive) return undefined;
    pollRef.current = setInterval(loadJobs, POLL_MS);
    return () => clearInterval(pollRef.current);
  }, [hasActive, loadJobs]);

  // ── Handlers ──
  const handleStartBatch = async () => {
    if (!taskType || !targetScope) return;
    setSubmitting(true);
    setError(null);
    try {
      const job = await apiFetch('/api/v1/ai_batch_jobs', {
        method: 'POST',
        body: JSON.stringify({
          ai_batch_job: {
            task_type: taskType,
            target_scope: targetScope,
            concurrency: Number(concurrency) || 25,
          },
        }),
      });
      setJobs((prev) => [job, ...prev]);
    } catch (e) {
      setError(e.message);
    } finally {
      setSubmitting(false);
    }
  };

  const handleCancel = async (job) => {
    setBusyId(job.id);
    try {
      const updated = await apiFetch(`/api/v1/ai_batch_jobs/${job.id}/cancel`, { method: 'POST' });
      setJobs((prev) => prev.map((j) => (j.id === updated.id ? updated : j)));
    } catch (e) {
      setError(e.message);
    } finally {
      setBusyId(null);
    }
  };

  const activeJob = jobs.find((j) => ACTIVE_STATUSES.includes(j.status));

  return (
    <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
      <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', mb: 1, display: 'flex', alignItems: 'center' }}>
        <QueryStats sx={{ mr: 1.5, color: '#8b5cf6', fontSize: 32 }} />
        {t('aiBatch.title', { defaultValue: 'AI Batch Tasks' })}
      </Typography>
      <Typography variant="body2" color="textSecondary" sx={{ mb: 4 }}>
        {t('aiBatch.subtitle', {
          defaultValue: 'Run AI tasks across whole segments of the library. Configure once, dispatch to the AI Gateway, and track progress live.',
        })}
      </Typography>

      {error && (
        <Alert severity="error" sx={{ mb: 3 }} onClose={() => setError(null)}>{error}</Alert>
      )}

      <Grid container spacing={4}>
        {/* Configuration Panel */}
        <Grid size={{ xs: 12, md: 4 }}>
          <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 3 }}>
            <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 3 }}>
              {t('aiBatch.config.title', { defaultValue: 'Batch Configuration' })}
            </Typography>

            {loading ? (
              <Stack spacing={3}>
                {[1, 2, 3, 4].map((i) => <Skeleton key={i} variant="rounded" height={56} />)}
              </Stack>
            ) : (
              <Stack spacing={3}>
                <TextField
                  select
                  fullWidth
                  label={t('aiBatch.config.task', { defaultValue: 'AI Task' })}
                  value={taskType}
                  onChange={(e) => setTaskType(e.target.value)}
                  disabled={submitting}
                  helperText={selectedTask?.description}
                >
                  {meta.tasks.map((task) => (
                    <MenuItem key={task.key} value={task.key}>{task.label}</MenuItem>
                  ))}
                </TextField>

                {selectedTask && (
                  <Stack direction="row" spacing={1} sx={{
  mt: -1,
  alignItems: "center"
}}>
                    <Chip
                      size="small"
                      label={t(`aiBatch.cost.${selectedTask.cost_tier}`, { defaultValue: `${selectedTask.cost_tier} cost` })}
                      color={selectedTask.cost_tier === 'high' ? 'error' : selectedTask.cost_tier === 'medium' ? 'warning' : 'success'}
                      variant="outlined"
                    />
                    <Typography variant="caption" color="text.secondary" sx={{ fontFamily: 'monospace' }}>
                      {selectedTask.gateway_capability}
                    </Typography>
                  </Stack>
                )}

                <TextField
                  select
                  fullWidth
                  label={t('aiBatch.config.target', { defaultValue: 'Target Dataset' })}
                  value={targetScope}
                  onChange={(e) => setTargetScope(e.target.value)}
                  disabled={submitting}
                >
                  {meta.scopes.map((scope) => (
                    <MenuItem key={scope.key} value={scope.key}>{scope.label}</MenuItem>
                  ))}
                </TextField>

                <TextField
                  type="number"
                  fullWidth
                  label={t('aiBatch.config.concurrency', { defaultValue: 'Concurrency / Batch Size' })}
                  value={concurrency}
                  onChange={(e) => setConcurrency(e.target.value)}
                  disabled={submitting}
                  slotProps={{ htmlInput: { min: 1, max: 500 } }}
                  helperText={t('aiBatch.config.concurrencyHelp', {
                    defaultValue: 'Number of items the gateway processes in parallel (1-500).',
                  })}
                />

                <Button
                  variant="contained"
                  size="large"
                  startIcon={submitting ? <CircularProgress size={18} color="inherit" /> : <RocketLaunch />}
                  onClick={handleStartBatch}
                  disabled={submitting || !taskType || !targetScope}
                  sx={{ bgcolor: '#8b5cf6', '&:hover': { bgcolor: '#7c3aed' }, mt: 2 }}
                >
                  {submitting
                    ? t('aiBatch.config.dispatching', { defaultValue: 'Dispatching...' })
                    : t('aiBatch.config.execute', { defaultValue: 'Execute Batch Task' })}
                </Button>
              </Stack>
            )}
          </Paper>
        </Grid>

        {/* Execution / history Panel */}
        <Grid size={{ xs: 12, md: 8 }}>
          <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 3, height: '100%', display: 'flex', flexDirection: 'column' }}>
            <Stack direction="row" sx={{
  mb: 2,
  alignItems: "center",
  justifyContent: "space-between"
}}>
              <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
                {t('aiBatch.history.title', { defaultValue: 'Batch Runs' })}
              </Typography>
              <Tooltip title={t('common.refresh', { defaultValue: 'Refresh' })}>
                <IconButton size="small" onClick={loadJobs}
                  aria-label={t('common.refresh', { defaultValue: 'Refresh' })}>
                  <Refresh fontSize="small" />
                </IconButton>
              </Tooltip>
            </Stack>

            {/* Live progress for the most recent active job */}
            {activeJob && (
              <Box sx={{ mb: 3, p: 2, bgcolor: '#f5f3ff', borderRadius: 2, border: '1px solid #ddd6fe' }}>
                <Stack direction="row" sx={{
  mb: 1,
  alignItems: "center",
  justifyContent: "space-between"
}}>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {activeJob.task_label || activeJob.task_type}
                  </Typography>
                  <Chip label={`${activeJob.progress_percent}%`} color="secondary" size="small" />
                </Stack>
                <LinearProgress
                  variant={activeJob.total_count > 0 ? 'determinate' : 'indeterminate'}
                  value={activeJob.progress_percent}
                  sx={{ height: 8, borderRadius: 4, bgcolor: '#ede9fe', '& .MuiLinearProgress-bar': { bgcolor: '#8b5cf6' } }}
                />
                <Typography variant="caption" color="text.secondary" sx={{ mt: 0.5, display: 'block' }}>
                  {t('aiBatch.history.progressDetail', {
                    processed: activeJob.processed_count,
                    total: activeJob.total_count,
                    failed: activeJob.failed_count,
                    defaultValue: `${activeJob.processed_count}/${activeJob.total_count} processed, ${activeJob.failed_count} failed`,
                  })}
                </Typography>
              </Box>
            )}

            <TableContainer sx={{ flexGrow: 1, border: '1px solid #f1f5f9', borderRadius: 2 }}>
              <Table size="small" stickyHeader>
                <TableHead>
                  <TableRow>
                    <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }}>{t('aiBatch.history.task', { defaultValue: 'Task' })}</TableCell>
                    <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }}>{t('aiBatch.history.status', { defaultValue: 'Status' })}</TableCell>
                    <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }} align="right">{t('aiBatch.history.progress', { defaultValue: 'Progress' })}</TableCell>
                    <TableCell sx={{ bgcolor: '#f8fafc', fontWeight: 600 }} align="right">{t('common.actions', { defaultValue: 'Actions' })}</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {loading ? (
                    <TableRow>
                      <TableCell colSpan={4}><Skeleton height={32} /></TableCell>
                    </TableRow>
                  ) : jobs.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={4} align="center" sx={{ py: 4, color: '#94a3b8' }}>
                        <FilterAlt sx={{ fontSize: 40, opacity: 0.5, mb: 1, display: 'block', mx: 'auto' }} />
                        {t('aiBatch.history.empty', { defaultValue: 'No batch runs yet. Configure a task to begin.' })}
                      </TableCell>
                    </TableRow>
                  ) : (
                    jobs.map((job) => (
                      <TableRow key={job.id}>
                        <TableCell>
                          <Typography variant="body2" sx={{ fontWeight: 600 }}>{job.task_label || job.task_type}</Typography>
                          <Typography variant="caption" color="text.secondary" sx={{ fontFamily: 'monospace' }}>{job.target_scope}</Typography>
                        </TableCell>
                        <TableCell>
                          <Chip
                            icon={
                              job.status === 'completed' ? <CheckCircleOutlined />
                                : job.status === 'failed' ? <ErrorOutlined />
                                  : job.status === 'cancelled' ? <StopCircleOutlined />
                                    : job.status === 'queued' ? <HourglassEmpty />
                                      : <PauseCircleOutlined />
                            }
                            label={t(`aiBatch.statusLabel.${job.status}`, { defaultValue: job.status })}
                            size="small"
                            color={statusChipColor(job.status)}
                            variant="outlined"
                            sx={{ height: 22 }}
                          />
                        </TableCell>
                        <TableCell align="right">
                          <Typography variant="body2" sx={{ fontWeight: 600, color: '#8b5cf6' }}>
                            {job.progress_percent}%
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            {job.processed_count}/{job.total_count}
                          </Typography>
                        </TableCell>
                        <TableCell align="right">
                          {ACTIVE_STATUSES.includes(job.status) && (
                            <Tooltip title={t('aiBatch.history.cancel', { defaultValue: 'Cancel' })}>
                              <span>
                                <IconButton size="small" onClick={() => handleCancel(job)} disabled={busyId === job.id}
                                  aria-label={t('aiBatch.history.cancel', { defaultValue: 'Cancel' })}>
                                  <StopCircleOutlined fontSize="small" sx={{ color: '#ef4444' }} />
                                </IconButton>
                              </span>
                            </Tooltip>
                          )}
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

