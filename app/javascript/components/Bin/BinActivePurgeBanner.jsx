import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
    Box, Typography, LinearProgress, Chip, IconButton, Tooltip, Collapse, Stack
} from '@mui/material';
import {
    DeleteSweepOutlined, PersonOutlined, CloseOutlined,
    ScheduleOutlined, RefreshOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

// Lightweight banner shown ON THE BIN PAGE only when a purge job is
// running or queued. Polls every 3s while active, stops automatically when
// the job finishes. Shows who triggered the run.
//
// Design rationale (per requirements):
//   • If a job is already running → show status + who triggered + poll.
//   • Otherwise → render nothing and do NOT poll (saves battery/requests).
export default function BinActivePurgeBanner({ onComplete }) {
    const { t } = useTranslation();

    const [statusData, setStatusData] = useState(null);
    const [dismissed, setDismissed]   = useState(false);
    const pollRef     = useRef(null);
    const prevStatus  = useRef(null);

    const fetchStatus = useCallback(async () => {
        try {
            const res = await fetch('/api/v1/bin/purge_status');
            if (!res.ok) return;
            const data = await res.json();
            setStatusData(data);

            // Detect completion transition → notify parent to refresh lists
            const wasActive = ['running', 'queued'].includes(prevStatus.current);
            const nowActive = ['running', 'queued'].includes(data.status);
            if (wasActive && !nowActive && onComplete) onComplete(data);
            prevStatus.current = data.status;
        } catch (_) { /* non-critical */ }
    }, [onComplete]);

    // Initial check on mount (one-shot)
    useEffect(() => { fetchStatus(); }, [fetchStatus]);

    // Start/stop polling based on active status
    const status   = statusData?.status;
    const isActive = status === 'running' || status === 'queued';

    useEffect(() => {
        if (isActive && !pollRef.current) {
            pollRef.current = setInterval(fetchStatus, 3000);
        } else if (!isActive && pollRef.current) {
            clearInterval(pollRef.current);
            pollRef.current = null;
        }
        return () => { if (pollRef.current) { clearInterval(pollRef.current); pollRef.current = null; } };
    }, [isActive, fetchStatus]);

    // Reset dismissal when a new active run starts
    useEffect(() => {
        if (isActive) setDismissed(false);
    }, [isActive]);

    // Render nothing when no active job (or dismissed)
    if (!isActive || dismissed) return null;

    const triggeredBy = statusData?.triggered_by || {};
    const isScheduled = triggeredBy.source === 'scheduled';

    return (
        <Collapse in={isActive && !dismissed}>
            <Box sx={{
                mx: 4, mt: 3, p: 2, borderRadius: 2,
                bgcolor: '#eff6ff', border: '1px solid #bfdbfe',
                display: 'flex', flexDirection: 'column', gap: 1,
            }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                    <DeleteSweepOutlined sx={{ color: '#2563eb', fontSize: 22 }} />
                    <Box sx={{ flex: 1 }}>
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e3a8a' }}>
                                {status === 'queued'
                                    ? t('bin.activePurge.queuedTitle')
                                    : t('bin.activePurge.runningTitle')}
                            </Typography>
                            <Chip
                                label={t(`bin.purge.status.${status}`)}
                                size="small"
                                sx={{ bgcolor: '#dbeafe', color: '#1d4ed8', fontWeight: 600, fontSize: '0.65rem' }}
                            />
                        </Box>

                        {/* Who triggered */}
                        <Stack direction="row" spacing={0.75} sx={{
  mt: 0.25,
  alignItems: "center"
}}>
                            {isScheduled
                                ? <ScheduleOutlined sx={{ fontSize: 13, color: '#64748b' }} />
                                : <PersonOutlined sx={{ fontSize: 13, color: '#64748b' }} />}
                            <Typography variant="caption" sx={{ color: '#475569' }}>
                                {isScheduled
                                    ? t('bin.purge.triggeredBySchedule')
                                    : t('bin.purge.triggeredBy', { name: triggeredBy.user_name || '—' })}
                                {statusData?.started_at && (
                                    <Box component="span" sx={{ color: '#94a3b8', ml: 0.5 }}>
                                        — {new Date(statusData.started_at).toLocaleTimeString()}
                                    </Box>
                                )}
                            </Typography>
                        </Stack>
                    </Box>

                    <Tooltip title={t('common.refresh')}>
                        <IconButton size="small" onClick={fetchStatus}>
                            <RefreshOutlined fontSize="small" />
                        </IconButton>
                    </Tooltip>
                    <Tooltip title={t('common.close')}>
                        <IconButton size="small" onClick={() => setDismissed(true)}>
                            <CloseOutlined fontSize="small" />
                        </IconButton>
                    </Tooltip>
                </Box>

                <LinearProgress
                    sx={{ borderRadius: 1, height: 5, bgcolor: '#dbeafe',
                          '& .MuiLinearProgress-bar': { bgcolor: '#2563eb' } }}
                />

                <Typography variant="caption" sx={{ color: '#64748b' }}>
                    {t('bin.activePurge.hint')}
                </Typography>
            </Box>
        </Collapse>
    );
}

