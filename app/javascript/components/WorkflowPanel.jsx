import React, { useState, useEffect } from 'react';
import {
    Box, Typography, TextField, Button, Stack, Chip, CircularProgress,
    IconButton, Paper, Alert
} from '@mui/material';
import {
    CheckCircle, Cancel, AccessTime, Close, AccountTree, FormatListBulleted
} from '@mui/icons-material';

export default function WorkflowPanel({ assetId, assetThumb, onClose, onWorkflowUpdate }) {
    const [history, setHistory] = useState(null);
    const [loading, setLoading] = useState(true);
    const [comment, setComment] = useState('');
    const [submitting, setSubmitting] = useState(false);
    const [error, setError] = useState(null);

    const fetchHistory = async () => {
        setLoading(true);
        setError(null);

        try {
            const res = await fetch(`/api/v1/assets/${assetId}/workflow_history`);
            if (!res.ok) throw new Error("Failed to fetch data");
            const data = await res.json();
            setHistory(data);
        } catch (err) {
            console.error("Failed to load workflow history:", err);
            setError("Could not load workflow details. Please try again.");
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        if (assetId) fetchHistory();
    }, [assetId]);

    const submitDecision = async (taskId, decision) => {
        if (!comment.trim() && decision === 'rejected') {
            alert("A comment is required when rejecting an asset.");
            return;
        }

        setSubmitting(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/workflow_tasks/${taskId}/submit`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ decision, comment })
            });

            if (res.ok) {
                setComment('');
                await fetchHistory();
                if (onWorkflowUpdate) onWorkflowUpdate(); // Tell the dashboard to refresh the task list
            } else {
                alert("Failed to submit decision.");
            }
        } catch (error) {
            console.error("Submission error:", error);
            alert("Network error occurred.");
        } finally {
            setSubmitting(false);
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
        return (
            <Box sx={{ p: 4, bgcolor: '#f8fafc', height: '100%' }}>
                <Alert severity="error">{error}</Alert>
            </Box>
        );
    }

    if (!history?.active) {
        return (
            <Box sx={{ p: 4, bgcolor: '#f8fafc', height: '100%', textAlign: 'center' }}>
                <AccountTree sx={{ fontSize: 48, color: '#cbd5e1', mb: 2 }} />
                <Typography variant="h6" color="textSecondary">No Active Workflow</Typography>
                <Typography variant="body2" color="textSecondary">
                    There is currently no workflow running for this asset.
                </Typography>
            </Box>
        );
    }

    const myPendingTask = history.tasks?.find(t => t.is_pending && t.is_current_user);

    return (
        <Box sx={{ bgcolor: '#f8fafc', height: '100%', display: 'flex', flexDirection: 'column', marginTop: '4rem' }}>

            {/* FIXED HEADER */}
            <Box sx={{ p: 3, bgcolor: '#ffffff', borderBottom: '1px solid #e2e8f0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Typography variant="h6" sx={{ fontWeight: 700, color: '#1e293b', display: 'flex', alignItems: 'center', gap: 1 }}>
                    <AccountTree color="primary" />
                    Workflow Inspection
                </Typography>
                {onClose && (
                    <IconButton size="small" onClick={onClose} sx={{ color: '#64748b' }}>
                        <Close />
                    </IconButton>
                )}
            </Box>

            {/* SCROLLABLE CONTENT */}
            <Box sx={{ p: 3, overflowY: 'auto', flexGrow: 1 }}>

                {/* Asset Preview Thumbnail */}
                {assetThumb && (
                    <Paper elevation={0} sx={{ mb: 3, textAlign: 'center', bgcolor: '#e2e8f0', borderRadius: '8px', p: 1, border: '1px solid #cbd5e1' }}>
                        <img src={assetThumb} alt="Asset Preview" style={{ maxWidth: '100%', maxHeight: '200px', objectFit: 'contain', borderRadius: '4px' }} />
                    </Paper>
                )}

                {/* SAFETY NET: Empty Tasks Warning */}
                {history.tasks?.length === 0 && (
                    <Alert severity="warning" sx={{ mb: 3 }}>
                        This workflow is running, but no tasks have been generated. This usually means the assigned users or groups could not be found.
                    </Alert>
                )}

                {/* THE ACTION CENTER (Current User's Pending Task) */}
                {myPendingTask && (
                    <Paper elevation={3} sx={{ mb: 4, p: 3, borderRadius: '8px', borderTop: '4px solid #3b82f6' }}>
                        <Typography variant="subtitle1" fontWeight="bold" sx={{ mb: 1, color: '#1e293b' }}>
                            Action Required: {myPendingTask.step_name}
                        </Typography>
                        <TextField
                            fullWidth multiline rows={3}
                            placeholder="Add your review notes here (required for rejection)..."
                            variant="outlined" size="small"
                            value={comment}
                            onChange={(e) => setComment(e.target.value)}
                            sx={{ mb: 2, bgcolor: '#f8fafc' }}
                            disabled={submitting}
                        />
                        <Stack direction="row" spacing={2} justifyContent="flex-end">
                            <Button
                                variant="outlined" color="error" startIcon={<Cancel />}
                                disabled={submitting || !comment.trim()}
                                onClick={() => submitDecision(myPendingTask.id, 'rejected')}
                                sx={{ textTransform: 'none', fontWeight: 600 }}
                            >
                                Decline
                            </Button>
                            <Button
                                variant="contained" color="success" startIcon={<CheckCircle />}
                                disabled={submitting}
                                onClick={() => submitDecision(myPendingTask.id, 'approved')}
                                sx={{ textTransform: 'none', fontWeight: 600 }}
                            >
                                Approve
                            </Button>
                        </Stack>
                    </Paper>
                )}

                {/* THE AUDIT TRAIL TIMELINE */}
                {history.tasks?.length > 0 && (
                    <Box>
                        <Typography variant="overline" sx={{ fontWeight: 700, color: '#64748b', display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                            <FormatListBulleted fontSize="small" /> Audit Trail
                        </Typography>

                        <Box sx={{ pl: 2, borderLeft: '2px solid #cbd5e1', ml: 1 }}>
                            {history.tasks.map((task, index) => (
                                <Box key={task.id} sx={{ position: 'relative', mb: index === history.tasks.length - 1 ? 0 : 4, pl: 3 }}>

                                    {/* Timeline Node Dot */}
                                    <Box sx={{
                                        position: 'absolute', left: '-11px', top: '4px',
                                        width: '20px', height: '20px', borderRadius: '50%',
                                        bgcolor: task.status === 'approved' ? '#22c55e' : task.status === 'rejected' ? '#ef4444' : '#cbd5e1',
                                        border: '4px solid #f8fafc'
                                    }} />

                                    <Stack direction="row" justifyContent="space-between" alignItems="flex-start" sx={{ mb: 0.5 }}>
                                        <Box>
                                            <Typography variant="body2" fontWeight="bold" sx={{ color: '#1e293b' }}>
                                                {task.step_name}
                                            </Typography>
                                            <Typography variant="caption" sx={{ color: '#64748b', display: 'block' }}>
                                                Assigned to: {task.user_name}
                                            </Typography>
                                        </Box>

                                        <Chip
                                            label={task.status} size="small"
                                            icon={task.status === 'approved' ? <CheckCircle /> : task.status === 'rejected' ? <Cancel /> : <AccessTime />}
                                            color={task.status === 'approved' ? 'success' : task.status === 'rejected' ? 'error' : 'default'}
                                            variant={task.status === 'pending' ? 'outlined' : 'filled'}
                                            sx={{ textTransform: 'capitalize', height: '24px', fontWeight: 600, '& .MuiChip-label': { px: 1, fontSize: '0.7rem' } }}
                                        />
                                    </Stack>

                                    {/* Comment Bubble */}
                                    {task.comment && (
                                        <Paper elevation={0} sx={{ mt: 1, p: 1.5, bgcolor: '#ffffff', borderRadius: '0px 8px 8px 8px', border: '1px solid #e2e8f0' }}>
                                            <Typography variant="body2" sx={{ color: '#475569', fontStyle: 'italic' }}>
                                                "{task.comment}"
                                            </Typography>
                                        </Paper>
                                    )}

                                    {/* Timestamp */}
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
        </Box>
    );
}