import React, { useState, useEffect } from 'react';
import {
    Box, Typography, Paper, Tabs, Tab, Table, TableBody, TableCell,
    TableContainer, TableHead, TableRow, Button, Avatar, Chip, CssBaseline,
    Checkbox, Stack, Tooltip, IconButton, Drawer, Grid,
} from '@mui/material';
import {
    Launch, Assignment, AdminPanelSettings, History, FactCheck,
    StopCircle, Refresh, WarningAmber, Delete, PendingActions,
    AccountTree, CheckCircle,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

import { useNotify } from '../context/NotificationContext';
import WorkflowPanel from './WorkflowPanel';
import BulkReassignModal from './Workflows/BulkReassignModal';

// ─── Small stat card ──────────────────────────────────────────────────────────
function StatCard({ icon: Icon, label, value, color, bg }) {
    return (
        <Paper elevation={0} sx={{ p: 2.5, border: '1px solid #e2e8f0', borderRadius: 3, display: 'flex', alignItems: 'center', gap: 2 }}>
            <Box sx={{ width: 44, height: 44, borderRadius: 2, bgcolor: bg, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Icon sx={{ color, fontSize: 24 }} />
            </Box>
            <Box>
                <Typography variant="h5" sx={{ fontWeight: 800, color: '#1e293b', lineHeight: 1 }}>{value}</Typography>
                <Typography variant="caption" sx={{ color: '#64748b', fontWeight: 600 }}>{label}</Typography>
            </Box>
        </Paper>
    );
}

// ─── Tab pagination controls (Prev/Next) ──────────────────────────────────────
function TabPagination({ pagination, onPageChange }) {
    if (!pagination || pagination.total_pages <= 1) return null;
    return (
        <Stack direction="row" spacing={1} sx={{ p: 2, justifyContent: 'center' }}>
            <Button size="small" disabled={pagination.page <= 1} onClick={() => onPageChange(pagination.page - 1)}>
                ← Prev
            </Button>
            <Typography variant="caption" sx={{ alignSelf: 'center', px: 1 }}>
                Page {pagination.page} of {pagination.total_pages}
            </Typography>
            <Button size="small" disabled={pagination.page >= pagination.total_pages} onClick={() => onPageChange(pagination.page + 1)}>
                Next →
            </Button>
        </Stack>
    );
}

const DEFAULT_TAB_PAGINATION = { page: 1, per_page: 10, total: 0, total_pages: 1 };


export default function WorkflowDashboard() {
    const notify = useNotify();
    const { t } = useTranslation();
    const [tab, setTab] = useState(0);
    const [data, setData] = useState({ my_tasks: [], active_workflows: [], completed_workflows: [] });
    const [tabPagination, setTabPagination] = useState({
        my_tasks: DEFAULT_TAB_PAGINATION,
        active_workflows: DEFAULT_TAB_PAGINATION,
        completed_workflows: DEFAULT_TAB_PAGINATION,
    });
    const [selectedWorkflows, setSelectedWorkflows] = useState([]);
    const [selectedAsset, setSelectedAsset] = useState(null);
    const [reassignOpen, setReassignOpen] = useState(false);
    const [users] = useState([]);
    const selectedWorkflowObjects = data.active_workflows.filter(w => selectedWorkflows.includes(w.instance_id));

    const fetchDashboardData = (pages = {}) => {
        const myTasksPage = pages.my_tasks_page || tabPagination.my_tasks.page;
        const activePage = pages.active_page || tabPagination.active_workflows.page;
        const completedPage = pages.completed_page || tabPagination.completed_workflows.page;

        const params = new URLSearchParams({
            my_tasks_page: myTasksPage,
            active_page: activePage,
            completed_page: completedPage,
        });

        fetch(`/api/v1/workflows/dashboard?${params.toString()}`)
            .then(res => res.json())
            .then(json => {
                setData({
                    my_tasks: json.my_tasks || [],
                    active_workflows: json.active_workflows || [],
                    completed_workflows: json.completed_workflows || [],
                });
                if (json.pagination) setTabPagination(json.pagination);
                setSelectedWorkflows([]);
            })
            .catch(err => notify(err.message || t('workflowOps.fetchError', { defaultValue: 'Failed to fetch dashboard data' }), 'error'));
    };

    const handleMyTasksPageChange = (page) => fetchDashboardData({ my_tasks_page: page });
    const handleActivePageChange = (page) => fetchDashboardData({ active_page: page });
    const handleCompletedPageChange = (page) => fetchDashboardData({ completed_page: page });

    useEffect(() => {
        fetchDashboardData();
        const params = new URLSearchParams(window.location.search);
        const urlAssetId = params.get('asset_id');
        if (urlAssetId) setSelectedAsset({ id: urlAssetId, thumb: null });
        // Run once on mount only; fetchDashboardData is intentionally not memoized
        // so it always reads fresh pagination state on subsequent manual calls.
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    const csrf = () => document.querySelector('[name="csrf-token"]').content;

    const isOverdue = (startedAt, deadlineDays = 2) => {
        const diffDays = Math.ceil(Math.abs(new Date() - new Date(startedAt)) / 86400000);
        return diffDays > deadlineDays;
    };

    const handleBulkReassign = async (payload) => {
        await fetch('/api/v1/workflows/bulk_reassign', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            body: JSON.stringify({ ids: selectedWorkflows, ...payload }),
        });
        fetchDashboardData();
    };

    const toggleAllWorkflows = () => {
        setSelectedWorkflows(prev =>
            prev.length === data.active_workflows.length ? [] : data.active_workflows.map(w => w.instance_id)
        );
    };

    const toggleWorkflowSelection = (id) => {
        setSelectedWorkflows(prev => prev.includes(id) ? prev.filter(s => s !== id) : [...prev, id]);
    };

    const handleBulkStop = async () => {
        if (!window.confirm(t('workflowOps.confirmBulkStop', { count: selectedWorkflows.length, defaultValue: `Stop ${selectedWorkflows.length} workflow(s)? This cancels all pending tasks.` }))) return;
        try {
            const res = await fetch('/api/v1/workflows/bulk_stop', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
                body: JSON.stringify({ ids: selectedWorkflows }),
            });
            if (res.ok) {
                notify(t('workflowOps.stopSuccess', { defaultValue: 'Workflows cancelled.' }), 'success');
                fetchDashboardData();
            } else {
                notify(t('workflowOps.stopFail', { defaultValue: 'Failed to stop workflows' }), 'error');
            }
        } catch {
            notify(t('workflowOps.networkError', { defaultValue: 'Network error occurred' }), 'error');
        }
    };

    const handleForceCancel = async (instanceId) => {
        const reason = window.prompt(t('workflowOps.cancelPrompt', { defaultValue: 'Reason for cancelling this workflow (optional):' }), '');
        if (reason === null) return;
        const res = await fetch(`/api/v1/workflow_instances/${instanceId}/force_cancel`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
            body: JSON.stringify({ reason }),
        });
        if (res.ok) {
            notify(t('workflowOps.cancelSuccess', { defaultValue: 'Workflow cancelled.' }), 'success');
            fetchDashboardData();
        } else {
            notify(t('workflowOps.cancelFail', { defaultValue: 'Failed to cancel workflow.' }), 'error');
        }
    };

    const handleDeleteInstance = async (instanceId) => {
        if (!window.confirm(t('workflowOps.confirmDelete', { defaultValue: 'Permanently delete this workflow instance? This cannot be undone.' }))) return;
        const res = await fetch(`/api/v1/workflow_instances/${instanceId}`, {
            method: 'DELETE',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
        });
        if (res.ok) {
            notify(t('workflowOps.deleteSuccess', { defaultValue: 'Workflow instance deleted.' }), 'success');
            fetchDashboardData();
        } else {
            const body = await res.json().catch(() => ({}));
            notify(body.error || t('workflowOps.deleteFail', { defaultValue: 'Failed to delete instance.' }), 'error');
        }
    };

    const handleOpenReviewPane = (assetId, assetThumb) => {
        setSelectedAsset({ id: assetId, thumb: assetThumb });
        window.history.replaceState({}, '', `/workflows/dashboard?asset_id=${assetId}`);
    };

    const handleCloseReviewPane = () => {
        setSelectedAsset(null);
        window.history.replaceState({}, '', '/workflows/dashboard');
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <Box component="main" sx={{ flexGrow: 1, p: 4, width: '100%' }}>
                <Stack direction="row" sx={{
  mb: 3,
  alignItems: "center",
  justifyContent: "space-between"
}}>
                    <Box>
                        <Typography variant="h4" sx={{ fontWeight: 800, color: '#1e293b', display: 'flex', alignItems: 'center', gap: 1.5 }}>
                            <AccountTree sx={{ color: '#5e35b1', fontSize: 34 }} />
                            {t('workflowOps.title', { defaultValue: 'Workflow Operations Center' })}
                        </Typography>
                        <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                            {t('workflowOps.subtitle', { defaultValue: 'Review your tasks, monitor active workflows, and audit completed runs.' })}
                        </Typography>
                    </Box>
                    <Button startIcon={<Refresh />} onClick={fetchDashboardData} variant="outlined">
                        {t('workflowOps.refresh', { defaultValue: 'Refresh' })}
                    </Button>
                </Stack>

                {/* Stat cards */}
                <Grid container spacing={2} sx={{ mb: 3 }}>
                    <Grid size={{ xs: 12, sm: 4 }}>
                        <StatCard icon={PendingActions} label={t('workflowOps.statPending', { defaultValue: 'My Pending Tasks' })} value={tabPagination.my_tasks.total} color="#d97706" bg="#fef3c7" />
                    </Grid>
                    <Grid size={{ xs: 12, sm: 4 }}>
                        <StatCard icon={AdminPanelSettings} label={t('workflowOps.statActive', { defaultValue: 'Active Workflows' })} value={tabPagination.active_workflows.total} color="#2563eb" bg="#dbeafe" />
                    </Grid>
                    <Grid size={{ xs: 12, sm: 4 }}>
                        <StatCard icon={CheckCircle} label={t('workflowOps.statCompleted', { defaultValue: 'Completed (recent)' })} value={tabPagination.completed_workflows.total} color="#16a34a" bg="#dcfce7" />
                    </Grid>
                </Grid>

                <Paper elevation={0} sx={{ border: '1px solid #e2e8f0', borderRadius: 3, overflow: 'hidden' }}>
                    <Tabs value={tab} onChange={(e, val) => setTab(val)} sx={{
  borderBottom: 1,
  borderColor: 'divider',
  bgcolor: '#ffffff'
}} slotProps={{
  indicator: {
    style: {
      backgroundColor: '#5e35b1'
    }
  }
}}>
                        <Tab icon={<Assignment />} iconPosition="start" label={`${t('workflowOps.tabPending', { defaultValue: 'My Pending Tasks' })} (${tabPagination.my_tasks.total})`} sx={{ '&.Mui-selected': { color: '#5e35b1' } }} />
                        <Tab icon={<AdminPanelSettings />} iconPosition="start" label={`${t('workflowOps.tabActive', { defaultValue: 'Active Workflows' })} (${tabPagination.active_workflows.total})`} sx={{ '&.Mui-selected': { color: '#5e35b1' } }} />
                        <Tab icon={<History />} iconPosition="start" label={t('workflowOps.tabAudit', { defaultValue: 'Audit History' })} sx={{ '&.Mui-selected': { color: '#5e35b1' } }} />
                    </Tabs>

                    {/* Bulk action toolbar */}
                    {tab === 1 && selectedWorkflows.length > 0 && (
                        <Box sx={{ p: 2, display: 'flex', alignItems: 'center', bgcolor: '#fff1f1', borderBottom: '1px solid #ffdede' }}>
                            <Typography sx={{ flexGrow: 1, fontWeight: 600, color: '#d32f2f' }}>
                                {t('workflowOps.selectedCount', { count: selectedWorkflows.length, defaultValue: `${selectedWorkflows.length} Workflows Selected` })}
                            </Typography>
                            <Stack direction="row" spacing={1}>
                                <Button color="primary" variant="outlined" onClick={() => setReassignOpen(true)}>{t('workflowOps.reassign', { defaultValue: 'Re-assign' })}</Button>
                                <Button color="error" variant="contained" startIcon={<StopCircle />} onClick={handleBulkStop}>{t('workflowOps.stop', { defaultValue: 'Stop' })}</Button>
                            </Stack>
                        </Box>
                    )}

                    <Box sx={{ bgcolor: '#ffffff' }}>
                        {/* TAB 0: MY TASKS */}
                        {tab === 0 && (
                            <>
                            <TableContainer>
                                <Table size="medium">
                                    <TableHead sx={{ bgcolor: '#f1f5f9' }}>
                                        <TableRow>
                                            <TableCell>{t('workflowOps.colAsset', { defaultValue: 'Asset' })}</TableCell>
                                            <TableCell>{t('workflowOps.colAssetName', { defaultValue: 'Asset Name' })}</TableCell>
                                            <TableCell>{t('workflowOps.colAction', { defaultValue: 'Required Action' })}</TableCell>
                                            <TableCell>{t('workflowOps.colAssigned', { defaultValue: 'Assigned Date' })}</TableCell>
                                            <TableCell align="right">{t('workflowOps.colActionBtn', { defaultValue: 'Action' })}</TableCell>
                                        </TableRow>
                                    </TableHead>
                                    <TableBody>
                                        {data.my_tasks.length === 0 ? (
                                            <TableRow><TableCell colSpan={5} align="center" sx={{ py: 4, color: '#94a3b8' }}>{t('workflowOps.noTasks', { defaultValue: 'You have no pending tasks.' })}</TableCell></TableRow>
                                        ) : data.my_tasks.map((task) => (
                                            <TableRow key={task.task_id} hover>
                                                <TableCell><Avatar variant="rounded" src={task.asset_thumb} /></TableCell>
                                                <TableCell sx={{ fontWeight: 500 }}>{task.asset_name}</TableCell>
                                                <TableCell><Chip label={task.step_title} color="warning" size="small" /></TableCell>
                                                <TableCell>{new Date(task.assigned_at).toLocaleDateString()}</TableCell>
                                                <TableCell align="right">
                                                    <Button variant="contained" size="small" endIcon={<Launch />} onClick={() => handleOpenReviewPane(task.asset_id, task.asset_thumb)} sx={{ bgcolor: '#5e35b1' }}>
                                                        {t('workflowOps.review', { defaultValue: 'Review' })}
                                                    </Button>
                                                </TableCell>
                                            </TableRow>
                                        ))}
                                    </TableBody>
                                </Table>
                            </TableContainer>
                            <TabPagination pagination={tabPagination.my_tasks} onPageChange={handleMyTasksPageChange} />
                            </>
                        )}

                        {/* TAB 1: ACTIVE WORKFLOWS */}
                        {tab === 1 && (
                            <>
                            <TableContainer>
                                <Table size="medium">
                                    <TableHead sx={{ bgcolor: '#f1f5f9' }}>
                                        <TableRow>
                                            <TableCell padding="checkbox"><Checkbox checked={selectedWorkflows.length > 0} indeterminate={selectedWorkflows.length > 0 && selectedWorkflows.length < data.active_workflows.length} onChange={toggleAllWorkflows} /></TableCell>
                                            <TableCell>{t('workflowOps.colBlueprint', { defaultValue: 'Blueprint' })}</TableCell>
                                            <TableCell>{t('workflowOps.colAsset', { defaultValue: 'Asset' })}</TableCell>
                                            <TableCell>{t('workflowOps.colStatus', { defaultValue: 'Current Status' })}</TableCell>
                                            <TableCell align="right">{t('workflowOps.colManage', { defaultValue: 'Manage' })}</TableCell>
                                        </TableRow>
                                    </TableHead>
                                    <TableBody>
                                        {data.active_workflows.length === 0 ? (
                                            <TableRow><TableCell colSpan={5} align="center" sx={{ py: 4, color: '#94a3b8' }}>{t('workflowOps.noActive', { defaultValue: 'No active workflows.' })}</TableCell></TableRow>
                                        ) : data.active_workflows.map((w) => (
                                            <TableRow key={w.instance_id} hover>
                                                <TableCell padding="checkbox"><Checkbox checked={selectedWorkflows.includes(w.instance_id)} onChange={() => toggleWorkflowSelection(w.instance_id)} /></TableCell>
                                                <TableCell sx={{ fontWeight: 500 }}>
                                                    {w.workflow_name}
                                                    {isOverdue(w.started_at) && <Tooltip title={t('workflowOps.slaBreached', { defaultValue: 'SLA Breached' })}><WarningAmber color="error" fontSize="small" sx={{ ml: 1, verticalAlign: 'middle' }} /></Tooltip>}
                                                </TableCell>
                                                <TableCell>{w.asset_name}</TableCell>
                                                <TableCell><Chip label={w.current_step} color={isOverdue(w.started_at) ? 'error' : 'info'} size="small" /></TableCell>
                                                <TableCell align="right">
                                                    <Stack direction="row" spacing={0.5} sx={{
  justifyContent: "flex-end"
}}>
                                                        <Tooltip title={t('workflowOps.inspect', { defaultValue: 'Inspect' })}>
                                                            <IconButton size="small" onClick={() => handleOpenReviewPane(w.asset_id, null)}><Launch fontSize="small" /></IconButton>
                                                        </Tooltip>
                                                        <Tooltip title={t('workflowOps.forceCancel', { defaultValue: 'Force-cancel workflow' })}>
                                                            <IconButton size="small" color="error" onClick={() => handleForceCancel(w.instance_id)}><StopCircle fontSize="small" /></IconButton>
                                                        </Tooltip>
                                                    </Stack>
                                                </TableCell>
                                            </TableRow>
                                        ))}
                                    </TableBody>
                                </Table>
                            </TableContainer>
                            <TabPagination pagination={tabPagination.active_workflows} onPageChange={handleActivePageChange} />
                            </>
                        )}

                        {/* TAB 2: AUDIT HISTORY */}
                        {tab === 2 && (
                            <>
                            <TableContainer>
                                <Table size="medium">
                                    <TableHead sx={{ bgcolor: '#f8fafc' }}>
                                        <TableRow>
                                            <TableCell>{t('workflowOps.colBlueprint', { defaultValue: 'Workflow Blueprint' })}</TableCell>
                                            <TableCell>{t('workflowOps.colAsset', { defaultValue: 'Target Asset' })}</TableCell>
                                            <TableCell>{t('workflowOps.colFinal', { defaultValue: 'Final Status' })}</TableCell>
                                            <TableCell>{t('workflowOps.colCompleted', { defaultValue: 'Completed Date' })}</TableCell>
                                            <TableCell align="right">{t('workflowOps.colManage', { defaultValue: 'Manage' })}</TableCell>
                                        </TableRow>
                                    </TableHead>
                                    <TableBody>
                                        {data.completed_workflows.length === 0 ? (
                                            <TableRow><TableCell colSpan={5} align="center" sx={{ py: 4, color: '#94a3b8' }}>{t('workflowOps.noHistory', { defaultValue: 'No completed workflows yet.' })}</TableCell></TableRow>
                                        ) : data.completed_workflows.map((w) => (
                                            <TableRow key={w.instance_id} hover>
                                                <TableCell sx={{ fontWeight: 500, color: '#64748b' }}>{w.workflow_name}</TableCell>
                                                <TableCell>{w.asset_name}</TableCell>
                                                <TableCell>
                                                    <Chip
                                                        label={w.status === 'completed' ? t('workflowOps.approved', { defaultValue: 'Approved' }) : w.status === 'canceled' ? t('workflowOps.cancelled', { defaultValue: 'Cancelled' }) : t('workflowOps.rejected', { defaultValue: 'Rejected' })}
                                                        color={w.status === 'completed' ? 'success' : w.status === 'canceled' ? 'default' : 'error'} size="small" />
                                                </TableCell>
                                                <TableCell>{new Date(w.completed_at).toLocaleString()}</TableCell>
                                                <TableCell align="right">
                                                    <Stack direction="row" spacing={0.5} sx={{
  justifyContent: "flex-end"
}}>
                                                        <Tooltip title={t('workflowOps.viewAudit', { defaultValue: 'View Audit' })}>
                                                            <IconButton size="small" onClick={() => handleOpenReviewPane(w.asset_id, null)}><FactCheck fontSize="small" /></IconButton>
                                                        </Tooltip>
                                                        <Tooltip title={t('workflowOps.delete', { defaultValue: 'Delete instance' })}>
                                                            <IconButton size="small" color="error" onClick={() => handleDeleteInstance(w.instance_id)}><Delete fontSize="small" /></IconButton>
                                                        </Tooltip>
                                                    </Stack>
                                                </TableCell>
                                            </TableRow>
                                        ))}
                                    </TableBody>
                                </Table>
                            </TableContainer>
                            <TabPagination pagination={tabPagination.completed_workflows} onPageChange={handleCompletedPageChange} />
                            </>
                        )}

                        <BulkReassignModal
                            open={reassignOpen}
                            onClose={() => setReassignOpen(false)}
                            selectedWorkflows={selectedWorkflowObjects}
                            onConfirm={handleBulkReassign}
                            users={users}
                        />
                    </Box>
                </Paper>
            </Box>

            <Drawer anchor="right" open={!!selectedAsset} onClose={handleCloseReviewPane} slotProps={{ paper: { sx: { width: 520, bgcolor: '#f8fafc' } } }}>
                {selectedAsset && <WorkflowPanel assetId={selectedAsset.id} assetThumb={selectedAsset.thumb} onClose={handleCloseReviewPane} onWorkflowUpdate={fetchDashboardData} />}
            </Drawer>
        </Box>
    );
}
