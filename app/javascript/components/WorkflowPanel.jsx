import React, { useState, useEffect, useCallback } from 'react';
import {
  Box, Typography, TextField, Button, Stack, Chip, CircularProgress,
  IconButton, Paper, Alert, Tooltip,
} from '@mui/material';
import {
  CheckCircle, Cancel, AccessTime, Close, AccountTree, FormatListBulleted,
  StopCircle, AdminPanelSettings,
} from '@mui/icons-material';

// ─── A single workflow instance card (action box + audit trail) ───────────────

function InstanceCard({ instance, onSubmit, onForceCancel, submitting }) {
  const [comment, setComment] = useState('');
  const myPendingTask = instance.tasks?.find((t) => t.is_pending && t.is_current_user);

  const handleDecision = (decision) => {
    if (decision === 'rejected' && !comment.trim()) {
      alert('A comment is required when rejecting an asset.');
      return;
    }
    onSubmit(myPendingTask.id, decision, comment, () => setComment(''));
  };

  const statusColor = {
    in_progress: 'info',
    completed: 'success',
    rejected: 'error',
    canceled: 'default',
  }[instance.instance_status] || 'default';

  return (
    <Paper elevation={0} sx={{ mb: 3, border: '1px solid #e2e8f0', borderRadius: 2, overflow: 'hidden' }}>
      {/* Instance header */}
      <Box sx={{ px: 2.5, py: 1.5, bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <Stack direction="row" spacing={1} sx={{
  alignItems: "center"
}}>
          <AccountTree sx={{ color: '#5e35b1', fontSize: 18 }} />
          <Box>
            <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#1e293b', lineHeight: 1.2 }}>
              {instance.workflow_name}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              Instance #{instance.instance_id}
            </Typography>
          </Box>
        </Stack>

        <Stack direction="row" spacing={1} sx={{
  alignItems: "center"
}}>
          <Chip label={instance.instance_status} size="small" color={statusColor} sx={{ textTransform: 'capitalize', fontWeight: 600, height: 22 }} />
          {instance.can_force_cancel && (
            <Tooltip title="Force-cancel this workflow (admin)">
              <IconButton size="small" color="error" onClick={() => onForceCancel(instance.instance_id, instance.workflow_name)}>
                <StopCircle fontSize="small" />
              </IconButton>
            </Tooltip>
          )}
        </Stack>
      </Box>

      <Box sx={{ p: 2.5 }}>
        {/* Cancelled reason banner */}
        {instance.instance_status === 'canceled' && instance.cancel_reason && (
          <Alert severity="warning" icon={<AdminPanelSettings />} sx={{ mb: 2 }}>
            Cancelled{instance.cancelled_by ? ` by ${instance.cancelled_by}` : ''}: {instance.cancel_reason}
          </Alert>
        )}

        {/* Empty tasks warning */}
        {instance.tasks?.length === 0 && instance.instance_status === 'in_progress' && (
          <Alert severity="warning" sx={{ mb: 2 }}>
            This workflow is running but generated no tasks — the assigned users or groups may be missing.
          </Alert>
        )}

        {/* Action box — only for THIS instance's pending task for the current user */}
        {myPendingTask && (
          <Paper elevation={2} sx={{ mb: 3, p: 2.5, borderRadius: 2, borderTop: '4px solid #3b82f6' }}>
            <Typography variant="subtitle2" fontWeight="bold" sx={{ mb: 1.5, color: '#1e293b' }}>
              Action Required: {myPendingTask.step_name}
            </Typography>
            <TextField
              fullWidth multiline rows={3} size="small"
              placeholder="Add your review notes (required for rejection)…"
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              sx={{ mb: 2, bgcolor: '#f8fafc' }}
              disabled={submitting}
            />
            <Stack direction="row" spacing={2} sx={{
  justifyContent: "flex-end"
}}>
              <Button variant="outlined" color="error" startIcon={<Cancel />}
                disabled={submitting || !comment.trim()}
                onClick={() => handleDecision('rejected')}
                sx={{ textTransform: 'none', fontWeight: 600 }}>
                Decline
              </Button>
              <Button variant="contained" color="success" startIcon={<CheckCircle />}
                disabled={submitting}
                onClick={() => handleDecision('approved')}
                sx={{ textTransform: 'none', fontWeight: 600 }}>
                Approve
              </Button>
            </Stack>
          </Paper>
        )}

        {/* Audit trail timeline */}
        {instance.tasks?.length > 0 && (
          <Box>
            <Typography variant="overline" sx={{ fontWeight: 700, color: '#64748b', display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
              <FormatListBulleted fontSize="small" /> Audit Trail
            </Typography>
            <Box sx={{ pl: 2, borderLeft: '2px solid #cbd5e1', ml: 1 }}>
              {instance.tasks.map((task, index) => (
                <Box key={task.id} sx={{ position: 'relative', mb: index === instance.tasks.length - 1 ? 0 : 3.5, pl: 3 }}>
                  <Box sx={{
                    position: 'absolute', left: '-11px', top: '4px',
                    width: 20, height: 20, borderRadius: '50%',
                    bgcolor: task.status === 'approved' ? '#22c55e' : task.status === 'rejected' ? '#ef4444' : task.status === 'canceled' ? '#94a3b8' : '#cbd5e1',
                    border: '4px solid #ffffff',
                  }} />
                  <Stack direction="row" sx={{
  mb: 0.5,
  alignItems: "flex-start",
  justifyContent: "space-between"
}}>
                    <Box>
                      <Typography variant="body2" fontWeight="bold" sx={{ color: '#1e293b' }}>{task.step_name}</Typography>
                      <Typography variant="caption" sx={{ color: '#64748b' }}>Assigned to: {task.user_name}</Typography>
                    </Box>
                    <Chip label={task.status} size="small"
                      icon={task.status === 'approved' ? <CheckCircle /> : task.status === 'rejected' ? <Cancel /> : <AccessTime />}
                      color={task.status === 'approved' ? 'success' : task.status === 'rejected' ? 'error' : 'default'}
                      variant={task.status === 'pending' ? 'outlined' : 'filled'}
                      sx={{ textTransform: 'capitalize', height: 24, fontWeight: 600, '& .MuiChip-label': { px: 1, fontSize: '0.7rem' } }}
                    />
                  </Stack>
                  {task.comment && (
                    <Paper elevation={0} sx={{ mt: 1, p: 1.5, bgcolor: '#f8fafc', borderRadius: '0 8px 8px 8px', border: '1px solid #e2e8f0' }}>
                      <Typography variant="body2" sx={{ color: '#475569', fontStyle: 'italic' }}>"{task.comment}"</Typography>
                    </Paper>
                  )}
                  {task.completed_at && (
                    <Typography variant="caption" sx={{ color: '#94a3b8', display: 'block', mt: 1 }}>
                      Completed: {new Date(task.completed_at).toLocaleString()}
                    </Typography>
                  )}
                </Box>
              ))}
            </Box>
          </Box>
        )}
      </Box>
    </Paper>
  );
}

// ─── Main panel: renders EVERY workflow instance for the asset ────────────────

export default function WorkflowPanel({ assetId, assetThumb, onClose, onWorkflowUpdate }) {
  const [history, setHistory] = useState(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  const fetchHistory = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/v1/assets/${assetId}/workflow_history`);
      if (!res.ok) throw new Error('Failed to fetch data');
      const data = await res.json();
      setHistory(data);
    } catch (err) {
      setError('Could not load workflow details. Please try again.');
    } finally {
      setLoading(false);
    }
  }, [assetId]);

  useEffect(() => {
    if (assetId) fetchHistory();
  }, [assetId, fetchHistory]);

  const submitDecision = async (taskId, decision, comment, onDone) => {
    setSubmitting(true);
    try {
      const csrfToken = document.querySelector('[name="csrf-token"]').content;
      const res = await fetch(`/api/v1/workflow_tasks/${taskId}/submit`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
        body: JSON.stringify({ decision, comment }),
      });
      if (res.ok) {
        if (onDone) onDone();
        await fetchHistory();
        if (onWorkflowUpdate) onWorkflowUpdate();
      } else {
        alert('Failed to submit decision.');
      }
    } catch (err) {
      alert('Network error occurred.');
    } finally {
      setSubmitting(false);
    }
  };

  const forceCancel = async (instanceId, workflowName) => {
    const reason = window.prompt(`Cancel workflow "${workflowName}"? Enter a reason (optional):`, '');
    if (reason === null) return; // user dismissed
    try {
      const csrfToken = document.querySelector('[name="csrf-token"]').content;
      const res = await fetch(`/api/v1/workflow_instances/${instanceId}/force_cancel`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
        body: JSON.stringify({ reason }),
      });
      if (res.ok) {
        await fetchHistory();
        if (onWorkflowUpdate) onWorkflowUpdate();
      } else {
        alert('Failed to cancel workflow.');
      }
    } catch (err) {
      alert('Network error occurred.');
    }
  };

  if (loading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100%', bgcolor: '#f8fafc' }}>
        <CircularProgress size={32} sx={{ color: '#3b82f6' }} />
      </Box>
    );
  }

  if (error) {
    return <Box sx={{ p: 4, bgcolor: '#f8fafc', height: '100%' }}><Alert severity="error">{error}</Alert></Box>;
  }

  const instances = history?.instances || [];

  return (
    <Box sx={{ bgcolor: '#f8fafc', height: '100%', display: 'flex', flexDirection: 'column' }}>
      {/* Header */}
      <Box sx={{ p: 3, bgcolor: '#ffffff', borderBottom: '1px solid #e2e8f0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <Typography variant="h6" sx={{ fontWeight: 700, color: '#1e293b', display: 'flex', alignItems: 'center', gap: 1 }}>
          <AccountTree color="primary" /> Workflow Inspection
          {instances.length > 1 && (
            <Chip label={`${instances.length} workflows`} size="small" color="primary" variant="outlined" sx={{ ml: 1 }} />
          )}
        </Typography>
        {onClose && <IconButton size="small" onClick={onClose} sx={{ color: '#64748b' }}><Close /></IconButton>}
      </Box>

      {/* Scrollable content */}
      <Box sx={{ p: 3, overflowY: 'auto', flexGrow: 1 }}>
        {assetThumb && (
          <Paper elevation={0} sx={{ mb: 3, textAlign: 'center', bgcolor: '#e2e8f0', borderRadius: 1, p: 1, border: '1px solid #cbd5e1' }}>
            <img src={assetThumb} alt="Asset Preview" style={{ maxWidth: '100%', maxHeight: 200, objectFit: 'contain', borderRadius: 4 }} />
          </Paper>
        )}

        {instances.length === 0 ? (
          <Box sx={{ textAlign: 'center', py: 6 }}>
            <AccountTree sx={{ fontSize: 48, color: '#cbd5e1', mb: 2 }} />
            <Typography variant="h6" color="textSecondary">No Workflows</Typography>
            <Typography variant="body2" color="textSecondary">There is no workflow history for this asset.</Typography>
          </Box>
        ) : (
          instances.map((inst) => (
            <InstanceCard
              key={inst.instance_id}
              instance={inst}
              onSubmit={submitDecision}
              onForceCancel={forceCancel}
              submitting={submitting}
            />
          ))
        )}
      </Box>
    </Box>
  );
}
