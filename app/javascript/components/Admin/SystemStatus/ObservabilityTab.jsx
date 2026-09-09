import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Grid, Paper, Typography, Button, CircularProgress, Alert, Chip, Divider,
    Table, TableBody, TableCell, TableContainer, TableHead, TableRow,
    LinearProgress, Tooltip, FormControlLabel, Switch,
} from '@mui/material';
import {
    Sync, CheckCircle, Cancel, Warning, RestartAlt, ErrorOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';

const REFRESH_INTERVAL_MS = 30000;

const STATUS_COLOURS = {
    healthy: '#2e7d32',
    degraded: '#ed6c02',
    offline: '#d32f2f',
    unreachable: '#d32f2f',
    error: '#d32f2f',
};

function StatusIcon({ status }) {
    const colour = STATUS_COLOURS[status] || '#d32f2f';
    if (status === 'healthy') return <CheckCircle sx={{ color: colour }} />;
    if (status === 'degraded') return <Warning sx={{ color: colour }} />;
    if (status === 'error') return <ErrorOutlined sx={{ color: colour }} />;
    return <Cancel sx={{ color: colour }} />;
}

function formatBytes(bytes) {
    if (bytes === null || bytes === undefined) return '—';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let value = Number(bytes);
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024;
        unit += 1;
    }
    return `${value.toFixed(value >= 10 || unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function formatDuration(seconds) {
    if (seconds === null || seconds === undefined) return '—';
    const total = Math.round(Number(seconds));
    if (total < 60) return `${total}s`;
    if (total < 3600) return `${Math.floor(total / 60)}m ${total % 60}s`;
    if (total < 86400) return `${Math.floor(total / 3600)}h ${Math.floor((total % 3600) / 60)}m`;
    return `${Math.floor(total / 86400)}d ${Math.floor((total % 86400) / 3600)}h`;
}

function formatTimestamp(value) {
    if (!value) return '—';
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? '—' : parsed.toLocaleString();
}

/** A labelled figure. `emphasis` marks a number that means something is wrong. */
function Metric({ label, value, hint, emphasis }) {
    const body = (
        <Box>
            <Typography variant="caption" color="textSecondary" sx={{ display: 'block' }}>{label}</Typography>
            <Typography
                variant="body1"
                sx={{ fontWeight: 600, color: emphasis ? STATUS_COLOURS.offline : 'inherit' }}
            >
                {value === null || value === undefined || value === '' ? '—' : value}
            </Typography>
        </Box>
    );
    return hint ? <Tooltip title={hint}><span>{body}</span></Tooltip> : body;
}

function Section({ title, subtitle, children }) {
    return (
        <Paper variant="outlined" sx={{ p: 3, borderRadius: 3, mb: 3 }}>
            <Typography variant="h6" sx={{ fontWeight: 700 }}>{title}</Typography>
            {subtitle && (
                <Typography variant="body2" color="textSecondary" sx={{ mb: 2 }}>{subtitle}</Typography>
            )}
            <Divider sx={{ mb: 2 }} />
            {children}
        </Paper>
    );
}

/** Renders the `{ status: 'error', error: ... }` stub a failed section returns. */
function SectionError({ data, label }) {
    if (!data || data.status !== 'error') return null;
    return <Alert severity="warning" sx={{ mb: 2 }}>{label}: {data.error}</Alert>;
}

export default function ObservabilityTab() {
    const { t } = useTranslation();
    const notify = useNotify();
    const [diagnostics, setDiagnostics] = useState(null);
    const [loadingHealth, setLoadingHealth] = useState(true);
    const [restartMessage, setRestartMessage] = useState(null);
    const [restartLoading, setRestartLoading] = useState(false);
    const [autoRefresh, setAutoRefresh] = useState(false);
    // `notify` and `t` are read through refs so that `fetchHealthData` can have
    // an empty dependency list. Neither is referentially stable — react-i18next
    // returns a fresh `t` whenever the language bundle changes — and a fetch
    // callback that changes identity on render would re-arm the mount effect
    // every render. That is an unbounded request loop against an endpoint whose
    // storage probe performs a real write, read and delete each time.
    const notifyRef = useRef(notify);
    notifyRef.current = notify;
    const tRef = useRef(t);
    tRef.current = t;

    const fetchHealthData = useCallback((announce = true) => {
        setLoadingHealth(true);
        return fetch('/admin/system_status.json', { credentials: 'same-origin' })
            .then(res => res.json())
            .then(data => {
                setDiagnostics(data);
                setLoadingHealth(false);
                if (announce) notifyRef.current(tRef.current('observability.refreshed'), 'success', 2000);
            })
            .catch(() => {
                setLoadingHealth(false);
                if (announce) notifyRef.current(tRef.current('observability.refreshFailed'), 'error');
            });
    }, []);

    useEffect(() => { fetchHealthData(false); }, [fetchHealthData]);

    // Opt-in rather than always-on: each poll runs a real write/read/delete
    // against the object store, so a tab left open on a wall display would go
    // on billing for that round-trip indefinitely.
    useEffect(() => {
        if (!autoRefresh) return undefined;
        const handle = setInterval(() => fetchHealthData(false), REFRESH_INTERVAL_MS);
        return () => clearInterval(handle);
    }, [autoRefresh, fetchHealthData]);

    const handleRestartServer = () => {
        if (!window.confirm(t('observability.restartConfirm'))) return;

        setRestartLoading(true);
        setRestartMessage(null);
        const csrfToken = document.querySelector('[name="csrf-token"]')?.content;

        fetch('/admin/system_status/restart_server', {
            method: 'POST',
            headers: { 'X-CSRF-Token': csrfToken },
        })
            .then(res => res.json())
            .then(data => {
                setRestartLoading(false);
                setRestartMessage({ type: 'success', text: data.message });
            })
            .catch(() => {
                setRestartLoading(false);
                setRestartMessage({ type: 'error', text: t('observability.restartFailed') });
            });
    };

    const app = diagnostics?.app_server;
    const db = diagnostics?.database;
    const cache = diagnostics?.cache_queue;
    const storage = diagnostics?.storage_backend;
    const runtime = diagnostics?.runtime;
    const queues = diagnostics?.queues;
    const redis = diagnostics?.redis;
    const pipeline = diagnostics?.content_pipeline;
    const preservation = diagnostics?.preservation;

    const summaryCards = [
        {
            key: 'app',
            label: t('observability.cards.appNode'),
            status: app?.status,
            headline: t('observability.cards.pumaRack'),
            detail: `Ruby ${app?.ruby_version ?? '—'} • Rails ${app?.rails_version ?? '—'}`,
        },
        {
            key: 'db',
            label: t('observability.cards.postgres'),
            status: db?.status,
            headline: db?.status === 'healthy' ? `${db.latency_ms} ms` : t('observability.cards.offline'),
            detail: t('observability.cards.poolDetail', {
                used: db?.active_connections ?? '—',
                size: db?.pool_size ?? '—',
                percent: db?.pool_utilisation_percent ?? '—',
            }),
        },
        {
            key: 'queue',
            label: t('observability.cards.redisSidekiq'),
            status: queues?.status || cache?.status,
            headline: t('observability.cards.workersActive', { count: cache?.active_workers ?? 0 }),
            detail: t('observability.cards.queueDetail', {
                depth: cache?.queue_depth ?? '—',
                retry: queues?.retry_size ?? '—',
                dead: queues?.dead_size ?? '—',
            }),
        },
        {
            key: 'storage',
            label: t('observability.cards.activeStorage'),
            status: storage?.status,
            headline: storage?.status === 'healthy' ? `${storage.latency_ms} ms` : t('observability.cards.unreachable'),
            detail: t('observability.cards.storageDetail', {
                provider: storage?.provider ?? '—',
                size: formatBytes(storage?.stored_bytes),
            }),
        },
        {
            key: 'pipeline',
            label: t('observability.cards.contentPipeline'),
            status: pipeline?.status,
            headline: t('observability.cards.assetCount', { count: pipeline?.total_assets ?? 0 }),
            detail: t('observability.cards.pipelineDetail', {
                stuck: pipeline?.stuck_processing ?? 0,
                recent: pipeline?.ingested_last_24h ?? 0,
            }),
        },
        {
            key: 'preservation',
            label: t('observability.cards.preservation'),
            status: preservation?.status,
            headline: `${preservation?.coverage_percent ?? 0}%`,
            detail: t('observability.cards.preservationDetail', {
                due: preservation?.due_now ?? 0,
                failing: preservation?.failing_last_30d ?? 0,
            }),
        },
    ];

    return (
        <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3, flexWrap: 'wrap', gap: 2 }}>
                <Typography variant="body2" color="textSecondary">
                    {t('observability.generatedAt', { time: formatTimestamp(diagnostics?.generated_at) })}
                </Typography>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    <FormControlLabel
                        control={<Switch size="small" checked={autoRefresh} onChange={e => setAutoRefresh(e.target.checked)} />}
                        label={<Typography variant="body2">{t('observability.autoRefresh')}</Typography>}
                    />
                    <Button variant="outlined" startIcon={<Sync />} onClick={() => fetchHealthData(true)} disabled={loadingHealth}>
                        {t('observability.refresh')}
                    </Button>
                </Box>
            </Box>

            {loadingHealth && !diagnostics ? (
                <Box sx={{ display: 'flex', justifyContent: 'center', width: '100%', py: 8 }}><CircularProgress /></Box>
            ) : (
                <>
                    {/* ── Summary cards ─────────────────────────────────────── */}
                    <Grid container spacing={3} sx={{ mb: 3 }}>
                        {summaryCards.map(card => (
                            <Grid size={{ xs: 12, sm: 6, md: 4, lg: 2 }} key={card.key}>
                                <Paper variant="outlined" sx={{ p: 2.5, borderRadius: 3, height: '100%' }}>
                                    <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1.5 }}>
                                        <Typography variant="subtitle2" color="textSecondary">{card.label}</Typography>
                                        <StatusIcon status={card.status} />
                                    </Box>
                                    <Typography variant="h6" sx={{ fontWeight: 700 }}>{card.headline}</Typography>
                                    <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1 }}>
                                        {card.detail}
                                    </Typography>
                                </Paper>
                            </Grid>
                        ))}
                    </Grid>

                    {/* ── Job queues ────────────────────────────────────────── */}
                    <Section
                        title={t('observability.queues.title')}
                        subtitle={t('observability.queues.subtitle')}
                    >
                        <SectionError data={queues} label={t('observability.queues.title')} />
                        <Grid container spacing={3} sx={{ mb: 2 }}>
                            <Grid size={{ xs: 6, sm: 3, md: 2 }}>
                                <Metric label={t('observability.queues.busy')} value={queues?.busy} />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 3, md: 2 }}>
                                <Metric label={t('observability.queues.scheduled')} value={queues?.scheduled_size} />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 3, md: 2 }}>
                                <Metric
                                    label={t('observability.queues.retrying')}
                                    value={queues?.retry_size}
                                    hint={t('observability.queues.retryingHint')}
                                    emphasis={queues?.retry_size > 0}
                                />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 3, md: 2 }}>
                                <Metric
                                    label={t('observability.queues.dead')}
                                    value={queues?.dead_size}
                                    hint={t('observability.queues.deadHint')}
                                    emphasis={queues?.dead_size > 0}
                                />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 3, md: 2 }}>
                                <Metric label={t('observability.queues.processed')} value={queues?.processed?.toLocaleString()} />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 3, md: 2 }}>
                                <Metric
                                    label={t('observability.queues.failed')}
                                    value={queues?.failed?.toLocaleString()}
                                    emphasis={queues?.failed > 0}
                                />
                            </Grid>
                        </Grid>

                        <TableContainer sx={{ maxHeight: 340 }}>
                            <Table size="small" stickyHeader>
                                <TableHead>
                                    <TableRow>
                                        <TableCell>{t('observability.queues.queue')}</TableCell>
                                        <TableCell align="right">{t('observability.queues.depth')}</TableCell>
                                        <TableCell align="right">{t('observability.queues.latency')}</TableCell>
                                        <TableCell align="right">{t('observability.queues.state')}</TableCell>
                                    </TableRow>
                                </TableHead>
                                <TableBody>
                                    {(queues?.queues || []).map(queue => (
                                        <TableRow key={queue.name} hover>
                                            <TableCell sx={{ fontFamily: 'monospace' }}>{queue.name}</TableCell>
                                            <TableCell align="right">{queue.size}</TableCell>
                                            <TableCell align="right" sx={{ color: queue.status === 'degraded' ? STATUS_COLOURS.offline : 'inherit' }}>
                                                {formatDuration(queue.latency_seconds)}
                                            </TableCell>
                                            <TableCell align="right">
                                                <Chip
                                                    size="small"
                                                    label={queue.paused
                                                        ? t('observability.queues.paused')
                                                        : t(`observability.status.${queue.status}`)}
                                                    color={queue.status === 'healthy' && !queue.paused ? 'success' : 'warning'}
                                                    variant="outlined"
                                                />
                                            </TableCell>
                                        </TableRow>
                                    ))}
                                    {(queues?.queues || []).length === 0 && (
                                        <TableRow>
                                            <TableCell colSpan={4} align="center">
                                                <Typography variant="body2" color="textSecondary" sx={{ py: 2 }}>
                                                    {t('observability.queues.none')}
                                                </Typography>
                                            </TableCell>
                                        </TableRow>
                                    )}
                                </TableBody>
                            </Table>
                        </TableContainer>

                        {(queues?.processes || []).length > 0 && (
                            <Box sx={{ mt: 2, display: 'flex', gap: 1, flexWrap: 'wrap' }}>
                                {queues.processes.map(process => (
                                    <Chip
                                        key={`${process.hostname}-${process.pid}`}
                                        size="small"
                                        variant="outlined"
                                        label={t('observability.queues.workerChip', {
                                            hostname: process.hostname,
                                            pid: process.pid,
                                            busy: process.busy,
                                            concurrency: process.concurrency,
                                        })}
                                    />
                                ))}
                            </Box>
                        )}
                    </Section>

                    {/* ── Fixity & preservation ─────────────────────────────── */}
                    <Section
                        title={t('observability.preservation.title')}
                        subtitle={t('observability.preservation.subtitle')}
                    >
                        <SectionError data={preservation} label={t('observability.preservation.title')} />
                        <Box sx={{ mb: 3 }}>
                            <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
                                <Typography variant="body2">{t('observability.preservation.coverage')}</Typography>
                                <Typography variant="body2" sx={{ fontWeight: 700 }}>
                                    {preservation?.coverage_percent ?? 0}%
                                </Typography>
                            </Box>
                            <LinearProgress
                                variant="determinate"
                                value={Math.min(Number(preservation?.coverage_percent) || 0, 100)}
                                color={(preservation?.coverage_percent || 0) >= 50 ? 'success' : 'warning'}
                                sx={{ height: 10, borderRadius: 5 }}
                            />
                        </Box>
                        <Grid container spacing={3}>
                            <Grid size={{ xs: 6, sm: 4, md: 2 }}>
                                <Metric label={t('observability.preservation.verifiable')} value={preservation?.verifiable} />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 2 }}>
                                <Metric
                                    label={t('observability.preservation.unverifiable')}
                                    value={preservation?.unverifiable}
                                    hint={t('observability.preservation.unverifiableHint')}
                                />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 2 }}>
                                <Metric label={t('observability.preservation.dueNow')} value={preservation?.due_now} />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 2 }}>
                                <Metric
                                    label={t('observability.preservation.failing')}
                                    value={preservation?.failing_last_30d}
                                    hint={t('observability.preservation.failingHint')}
                                    emphasis={preservation?.failing_last_30d > 0}
                                />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 2 }}>
                                <Metric label={t('observability.preservation.lastRun')} value={formatTimestamp(preservation?.last_run_at)} />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 2 }}>
                                <Metric
                                    label={t('observability.preservation.atRisk')}
                                    value={preservation?.high_risk_formats}
                                    hint={t('observability.preservation.atRiskHint')}
                                    emphasis={preservation?.high_risk_formats > 0}
                                />
                            </Grid>
                        </Grid>
                    </Section>

                    {/* ── Content pipeline ──────────────────────────────────── */}
                    <Section
                        title={t('observability.pipeline.title')}
                        subtitle={t('observability.pipeline.subtitle')}
                    >
                        <SectionError data={pipeline} label={t('observability.pipeline.title')} />
                        <Grid container spacing={3} sx={{ mb: 2 }}>
                            <Grid size={{ xs: 6, sm: 3 }}>
                                <Metric label={t('observability.pipeline.total')} value={pipeline?.total_assets?.toLocaleString()} />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 3 }}>
                                <Metric label={t('observability.pipeline.recent')} value={pipeline?.ingested_last_24h} />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 3 }}>
                                <Metric
                                    label={t('observability.pipeline.stuck')}
                                    value={pipeline?.stuck_processing}
                                    hint={t('observability.pipeline.stuckHint')}
                                    emphasis={pipeline?.stuck_processing > 0}
                                />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 3 }}>
                                <Metric label={t('observability.pipeline.quarantined')} value={pipeline?.quarantined} />
                            </Grid>
                        </Grid>
                        <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
                            {Object.entries(pipeline?.by_status || {}).map(([status, count]) => (
                                <Chip
                                    key={status}
                                    size="small"
                                    variant="outlined"
                                    color={status === 'failed' ? 'error' : 'default'}
                                    label={`${status}: ${count}`}
                                />
                            ))}
                            <Chip size="small" variant="outlined" label={`${t('observability.pipeline.inBin')}: ${pipeline?.in_bin ?? 0}`} />
                        </Box>
                    </Section>

                    {/* ── Datastores ────────────────────────────────────────── */}
                    <Section
                        title={t('observability.datastores.title')}
                        subtitle={t('observability.datastores.subtitle')}
                    >
                        <Grid container spacing={3}>
                            <Grid size={{ xs: 12, md: 6 }}>
                                <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5 }}>
                                    {t('observability.datastores.postgres')}
                                </Typography>
                                <SectionError data={db} label={t('observability.datastores.postgres')} />
                                <Grid container spacing={2}>
                                    <Grid size={6}><Metric label={t('observability.datastores.version')} value={db?.server_version} /></Grid>
                                    <Grid size={6}><Metric label={t('observability.datastores.latency')} value={db?.latency_ms ? `${db.latency_ms} ms` : null} /></Grid>
                                    <Grid size={6}>
                                        <Metric
                                            label={t('observability.datastores.pool')}
                                            value={db ? `${db.active_connections}/${db.pool_size} (${db.pool_utilisation_percent}%)` : null}
                                            hint={t('observability.datastores.poolHint')}
                                            emphasis={db?.pool_utilisation_percent >= 90}
                                        />
                                    </Grid>
                                    <Grid size={6}>
                                        <Metric
                                            label={t('observability.datastores.waiting')}
                                            value={db?.waiting}
                                            emphasis={db?.waiting > 0}
                                        />
                                    </Grid>
                                    <Grid size={6}><Metric label={t('observability.datastores.dbSize')} value={formatBytes(db?.size_bytes)} /></Grid>
                                    <Grid size={6}>
                                        <Metric
                                            label={t('observability.datastores.longestQuery')}
                                            value={formatDuration(db?.longest_query_seconds)}
                                            hint={t('observability.datastores.longestQueryHint')}
                                            emphasis={db?.longest_query_seconds > 300}
                                        />
                                    </Grid>
                                </Grid>
                            </Grid>

                            <Grid size={{ xs: 12, md: 6 }}>
                                <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5 }}>
                                    {t('observability.datastores.redis')}
                                </Typography>
                                <SectionError data={redis} label={t('observability.datastores.redis')} />
                                <Grid container spacing={2}>
                                    <Grid size={6}><Metric label={t('observability.datastores.version')} value={redis?.version} /></Grid>
                                    <Grid size={6}><Metric label={t('observability.datastores.memory')} value={redis?.used_memory} /></Grid>
                                    <Grid size={6}><Metric label={t('observability.datastores.peakMemory')} value={redis?.used_memory_peak} /></Grid>
                                    <Grid size={6}><Metric label={t('observability.datastores.clients')} value={redis?.connected_clients} /></Grid>
                                    <Grid size={6}>
                                        <Metric
                                            label={t('observability.datastores.evicted')}
                                            value={redis?.evicted_keys}
                                            hint={t('observability.datastores.evictedHint')}
                                            emphasis={redis?.evicted_keys > 0}
                                        />
                                    </Grid>
                                    <Grid size={6}><Metric label={t('observability.datastores.hitRate')} value={redis?.hit_rate_percent != null ? `${redis.hit_rate_percent}%` : null} /></Grid>
                                </Grid>

                                <Typography variant="subtitle2" sx={{ fontWeight: 700, mt: 3, mb: 1.5 }}>
                                    {t('observability.datastores.objectStorage')}
                                </Typography>
                                <Grid container spacing={2}>
                                    <Grid size={6}><Metric label={t('observability.datastores.provider')} value={storage?.provider} /></Grid>
                                    <Grid size={6}><Metric label={t('observability.datastores.blobs')} value={storage?.blob_count?.toLocaleString()} /></Grid>
                                    <Grid size={6}><Metric label={t('observability.datastores.stored')} value={formatBytes(storage?.stored_bytes)} /></Grid>
                                    <Grid size={6}><Metric label={t('observability.datastores.latency')} value={storage?.latency_ms ? `${storage.latency_ms} ms` : null} /></Grid>
                                </Grid>
                            </Grid>
                        </Grid>
                    </Section>

                    {/* ── Runtime ───────────────────────────────────────────── */}
                    <Section
                        title={t('observability.runtime.title')}
                        subtitle={t('observability.runtime.subtitle')}
                    >
                        <SectionError data={runtime} label={t('observability.runtime.title')} />
                        <Grid container spacing={3}>
                            <Grid size={{ xs: 6, sm: 4, md: 3 }}><Metric label={t('observability.runtime.host')} value={runtime?.hostname} /></Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 3 }}><Metric label={t('observability.runtime.pid')} value={runtime?.pid} /></Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 3 }}>
                                <Metric
                                    label={t('observability.runtime.uptime')}
                                    value={formatDuration(runtime?.uptime_seconds)}
                                    hint={t('observability.runtime.uptimeHint')}
                                />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 3 }}><Metric label={t('observability.runtime.environment')} value={app?.environment} /></Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 3 }}><Metric label={t('observability.runtime.revision')} value={runtime?.revision} /></Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 3 }}><Metric label={t('observability.runtime.timeZone')} value={runtime?.time_zone} /></Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 3 }}>
                                <Metric
                                    label={t('observability.runtime.heap')}
                                    value={runtime?.heap_live_objects?.toLocaleString()}
                                    hint={t('observability.runtime.heapHint')}
                                />
                            </Grid>
                            <Grid size={{ xs: 6, sm: 4, md: 3 }}><Metric label={t('observability.runtime.threads')} value={runtime?.threads} /></Grid>
                        </Grid>
                        {app?.uptime && app.uptime !== 'Unavailable' && (
                            <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 2, fontFamily: 'monospace' }}>
                                {app.uptime}
                            </Typography>
                        )}
                    </Section>
                </>
            )}

            {/* ── Controls ──────────────────────────────────────────────────── */}
            <Paper variant="outlined" sx={{ p: 3, borderRadius: 3 }}>
                <Typography variant="h6" sx={{ fontWeight: 700, mb: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
                    <RestartAlt /> {t('observability.controls.title')}
                </Typography>
                <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                    {t('observability.controls.subtitle')}
                </Typography>

                {restartMessage && (
                    <Alert severity={restartMessage.type} sx={{ mb: 3 }}>{restartMessage.text}</Alert>
                )}

                <Grid container spacing={3}>
                    <Grid size={{ xs: 12, md: 6 }}>
                        <Paper elevation={0} sx={{ p: 2, bgcolor: '#f8f9fa', border: '1px solid #e3e8ef', borderRadius: 2 }}>
                            <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>
                                {t('observability.controls.restartTitle')}
                            </Typography>
                            <Typography variant="caption" color="textSecondary" display="block" sx={{ mb: 2 }}>
                                {t('observability.controls.restartHint')}
                            </Typography>
                            <Button variant="contained" color="error" onClick={handleRestartServer} disabled={restartLoading}>
                                {restartLoading ? t('observability.controls.restarting') : t('observability.controls.restartAction')}
                            </Button>
                        </Paper>
                    </Grid>
                </Grid>
            </Paper>
        </Paper>
    );
}
