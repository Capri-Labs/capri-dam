import React, { useState, useEffect } from 'react';
import {
    Box, Typography, Paper, Tabs, Tab, Table, TableBody, TableCell,
    TableContainer, TableHead, TableRow, Button, Avatar, Chip, CssBaseline,
    Toolbar, Drawer, Checkbox, Stack, Tooltip
} from '@mui/material';
import {
    Launch, Assignment, AdminPanelSettings, History, FactCheck,
    StopCircle, Refresh, WarningAmber
} from '@mui/icons-material';

import Sidebar from "./Sidebar";
import { navigateTo } from '../utils/globalutils';
import { useNotify } from '../context/NotificationContext';
import WorkflowPanel from './WorkflowPanel';

import BulkReassignModal from './Workflows/BulkReassignModal';
import BottleneckReport from './Workflows/BottleneckReport';

export default function WorkflowDashboard({ onNavigateToAsset }) {
    const notify = useNotify();
    const [tab, setTab] = useState(0);
    const [data, setData] = useState({ my_tasks: [], active_workflows: [], completed_workflows: [] });
    const [selectedWorkflows, setSelectedWorkflows] = useState([]);
    const [activeView, setActiveView] = useState('My Tasks');
    const [selectedAsset, setSelectedAsset] = useState(null);
    const [reassignOpen, setReassignOpen] = useState(false);
    const [bottleneckOpen, setBottleneckOpen] = useState(false);
    const [users, setUsers] = useState([]);
    const selectedWorkflowObjects = data.active_workflows.filter(w => selectedWorkflows.includes(w.instance_id));

    const fetchDashboardData = () => {
        fetch('/api/v1/workflows/dashboard')
            .then(res => res.json())
            .then(json => {
                setData({
                    my_tasks: json.my_tasks || [],
                    active_workflows: json.active_workflows || [],
                    completed_workflows: json.completed_workflows || []
                });
                setSelectedWorkflows([]);
            })
            .catch(err => notify(err.message || "Failed to fetch dashboard data", "error"));
    };

    const handleBulkReassign = async (payload) => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        await fetch('/api/v1/workflows/bulk_reassign', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify({ ids: selectedWorkflows, ...payload })
        });
        fetchDashboardData();
    };

    useEffect(() => {
        fetchDashboardData();
        const params = new URLSearchParams(window.location.search);
        const urlAssetId = params.get('asset_id');
        if (urlAssetId) setSelectedAsset({ id: urlAssetId, thumb: null });
    }, []);

    const isOverdue = (startedAt, deadlineDays) => {
        const start = new Date(startedAt);
        const now = new Date();
        const diffTime = Math.abs(now - start);
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        return diffDays > (deadlineDays || 2); // Assuming 2 days default
    };

    const getBottleneckStats = () => {
        const counts = {};
        data.active_workflows.forEach(w => {
            counts[w.current_step] = (counts[w.current_step] || 0) + 1;
        });
        return Object.entries(counts).sort((a,b) => b[1] - a[1]).slice(0, 3);
    };

    const toggleAllWorkflows = () => {
        if (selectedWorkflows.length === data.active_workflows.length) {
            setSelectedWorkflows([]);
        } else {
            setSelectedWorkflows(data.active_workflows.map(w => w.instance_id));
        }
    };

    const toggleWorkflowSelection = (id) => {
        setSelectedWorkflows(prev =>
            prev.includes(id) ? prev.filter(s => s !== id) : [...prev, id]
        );
    };

    const handleBulkStop = async () => {
        if (!window.confirm(`Are you sure you want to stop ${selectedWorkflows.length} workflows? This will cancel all pending tasks and archive these instances.`)) return;

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch('/api/v1/workflows/bulk_stop', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ ids: selectedWorkflows })
            });
            if (res.ok) {
                notify("Workflows successfully canceled.", "success");
                fetchDashboardData();
            } else {
                notify("Failed to stop workflows", "error");
            }
        } catch (err) {
            notify("Network error occurred", "error");
        }
    };

    const handleOpenReviewPane = (assetId, assetThumb) => {
        setSelectedAsset({ id: assetId, thumb: assetThumb });
        window.history.replaceState({}, '', `/workflows/dashboard?asset_id=${assetId}`);
    };

    const handleCloseReviewPane = () => {
        setSelectedAsset(null);
        window.history.replaceState({}, '', `/workflows/dashboard`);
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <Sidebar activeView={activeView} onNavigate={navigateTo} />

            <Box component="main" sx={{ flexGrow: 1, p: 4, width: '100%' }}>
                <Toolbar/>
                <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 3 }}>
                    <Typography variant="h5" fontWeight="bold" color="#1e293b">Workflow Operations Center</Typography>
                    <Button startIcon={<Refresh />} onClick={fetchDashboardData}>Refresh</Button>
                </Stack>

                <Paper elevation={0} sx={{ border: '1px solid #e2e8f0', borderRadius: '12px', overflow: 'hidden' }}>
                    <Tabs
                        value={tab}
                        onChange={(e, val) => setTab(val)}
                        sx={{ borderBottom: 1, borderColor: 'divider', bgcolor: '#ffffff' }}
                    >
                        <Tab icon={<Assignment />} iconPosition="start" label={`My Pending Tasks (${data.my_tasks.length})`} />
                        <Tab icon={<AdminPanelSettings />} iconPosition="start" label={`Active Workflows (${data.active_workflows.length})`} />
                        <Tab icon={<History />} iconPosition="start" label="Audit History" />
                    </Tabs>

                    {/* BULK ACTION TOOLBAR */}
                    {tab === 1 && selectedWorkflows.length > 0 && (
                        <Box sx={{ p: 2, display: 'flex', alignItems: 'center', bgcolor: '#fff1f1', borderBottom: '1px solid #ffdede' }}>
                            <Typography sx={{ flexGrow: 1, fontWeight: 600, color: '#d32f2f' }}>{selectedWorkflows.length} Workflows Selected</Typography>
                            <Stack direction="row" spacing={1}>
                                <Button color="primary" variant="outlined" onClick={() => setReassignOpen(true)}>Re-assign</Button>
                                <Button color="error" variant="contained" startIcon={<StopCircle />} onClick={handleBulkStop}>Stop</Button>
                            </Stack>

                        </Box>
                    )}

                    <Box sx={{ p: 0, bgcolor: '#ffffff' }}>
                        {/* TAB 0: MY TASKS */}
                        {tab === 0 && (
                            <TableContainer>
                                <Table size="medium">
                                    <TableHead sx={{ bgcolor: '#f1f5f9' }}>
                                        <TableRow>
                                            <TableCell>Asset</TableCell>
                                            <TableCell>Asset Name</TableCell>
                                            <TableCell>Required Action</TableCell>
                                            <TableCell>Assigned Date</TableCell>
                                            <TableCell align="right">Action</TableCell>
                                        </TableRow>
                                    </TableHead>
                                    <TableBody>
                                        {data.my_tasks.length === 0 ? (
                                            <TableRow><TableCell colSpan={5} align="center" sx={{ py: 4 }}>You have no pending tasks.</TableCell></TableRow>
                                        ) : data.my_tasks.map((task) => (
                                            <TableRow key={task.task_id} hover>
                                                <TableCell><Avatar variant="rounded" src={task.asset_thumb} /></TableCell>
                                                <TableCell sx={{ fontWeight: 500 }}>{task.asset_name}</TableCell>
                                                <TableCell><Chip label={task.step_title} color="warning" size="small" /></TableCell>
                                                <TableCell>{new Date(task.assigned_at).toLocaleDateString()}</TableCell>
                                                <TableCell align="right">
                                                    <Button variant="contained" size="small" endIcon={<Launch />} onClick={() => handleOpenReviewPane(task.asset_id, task.asset_thumb)}>
                                                        Review
                                                    </Button>
                                                </TableCell>
                                            </TableRow>
                                        ))}
                                    </TableBody>
                                </Table>
                            </TableContainer>
                        )}

                        {/* TAB 1: ADMIN OVERVIEW */}
                        {tab === 1 && (
                            <TableContainer>
                                <Table size="medium">
                                    <TableHead sx={{ bgcolor: '#f1f5f9' }}>
                                        <TableRow>
                                            <TableCell padding="checkbox"><Checkbox checked={selectedWorkflows.length > 0} indeterminate={selectedWorkflows.length > 0 && selectedWorkflows.length < data.active_workflows.length} onChange={toggleAllWorkflows} /></TableCell>
                                            <TableCell>Blueprint</TableCell>
                                            <TableCell>Asset</TableCell>
                                            <TableCell>Current Status</TableCell>
                                            <TableCell align="right">View Details</TableCell>
                                        </TableRow>
                                    </TableHead>
                                    <TableBody>
                                        {data.active_workflows.map((w) => (
                                            <TableRow key={w.instance_id} hover>
                                                <TableCell padding="checkbox">
                                                    <Checkbox checked={selectedWorkflows.includes(w.instance_id)} onChange={() => toggleWorkflowSelection(w.instance_id)} />
                                                </TableCell>
                                                <TableCell sx={{ fontWeight: 500 }}>
                                                    {w.workflow_name}
                                                    {isOverdue(w.started_at, 2) && <Tooltip title="SLA Breached"><WarningAmber color="error" fontSize="small" sx={{ ml: 1 }}/></Tooltip>}
                                                </TableCell>
                                                <TableCell>{w.asset_name}</TableCell>
                                                <TableCell><Chip label={w.current_step} color={isOverdue(w.started_at, 2) ? 'error' : 'info'} size="small" /></TableCell>
                                                <TableCell align="right">
                                                    <Button variant="outlined" size="small" onClick={() => handleOpenReviewPane(w.asset_id, null)}>Inspect</Button>
                                                </TableCell>
                                            </TableRow>
                                        ))}
                                    </TableBody>
                                </Table>
                            </TableContainer>
                        )}

                        {/* TAB 2: AUDIT HISTORY */}
                        {tab === 2 && (
                            <TableContainer>
                                <Table size="medium">
                                    <TableHead sx={{ bgcolor: '#f8fafc' }}>
                                        <TableRow>
                                            <TableCell>Workflow Blueprint</TableCell>
                                            <TableCell>Target Asset</TableCell>
                                            <TableCell>Final Status</TableCell>
                                            <TableCell>Completed Date</TableCell>
                                            <TableCell align="right">Audit Trail</TableCell>
                                        </TableRow>
                                    </TableHead>
                                    <TableBody>
                                        {data.completed_workflows.map((w) => (
                                            <TableRow key={w.instance_id} hover>
                                                <TableCell sx={{ fontWeight: 500, color: '#64748b' }}>{w.workflow_name}</TableCell>
                                                <TableCell>{w.asset_name}</TableCell>
                                                <TableCell><Chip label={w.status === 'completed' ? 'Approved' : 'Rejected'} color={w.status === 'completed' ? 'success' : 'error'} size="small" /></TableCell>
                                                <TableCell>{new Date(w.completed_at).toLocaleString()}</TableCell>
                                                <TableCell align="right">
                                                    <Button variant="text" size="small" startIcon={<FactCheck />} onClick={() => handleOpenReviewPane(w.asset_id, null)}>View Audit</Button>
                                                </TableCell>
                                            </TableRow>
                                        ))}
                                    </TableBody>
                                </Table>
                            </TableContainer>
                        )}

                        <BulkReassignModal
                            open={reassignOpen}
                            onClose={() => setReassignOpen(false)}
                            selectedWorkflows={selectedWorkflowObjects}
                            onConfirm={handleBulkReassign}
                            users={users}
                        />

                        <BottleneckReport
                            open={bottleneckOpen}
                            onClose={() => setBottleneckOpen(false)}
                            stats={getBottleneckStats()}
                            totalActive={data.active_workflows.length}
                        />
                    </Box>
                </Paper>
            </Box>

            <Drawer anchor="right" open={!!selectedAsset} onClose={handleCloseReviewPane} PaperProps={{ sx: { width: 500, bgcolor: '#f8fafc' } }}>
                {selectedAsset && <WorkflowPanel assetId={selectedAsset.id} assetThumb={selectedAsset.thumb} onClose={handleCloseReviewPane} onWorkflowUpdate={fetchDashboardData} />}
            </Drawer>
        </Box>
    );
}