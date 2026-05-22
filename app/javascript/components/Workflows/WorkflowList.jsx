import React from 'react';
import {
    Box, Typography, Button, Table, TableBody, TableCell,
    TableHead, TableRow, Chip, IconButton, Paper, Tooltip
} from '@mui/material';
import {
    Add, Edit, Delete, ToggleOn, ToggleOff,
    History, AccountTree
} from '@mui/icons-material';

export default function WorkflowList({ workflows = [], onCreate, onEdit, onToggleStatus, onDelete }) {

    const handleDelete = async (id) => {
        // 1. Ask for confirmation
        if (!window.confirm("Are you sure you want to delete this workflow? This action cannot be undone.")) {
            return;
        }

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const response = await fetch(`/workflows/${id}`, {
                method: 'DELETE',
                headers: {
                    'X-CSRF-Token': csrfToken,
                    'Content-Type': 'application/json'
                }
            });

            if (response.ok) {
                console.log("Workflow deleted successfully");
            } else {
                const data = await response.json();
                alert(`Error: ${data.errors || 'Could not delete workflow'}`);
            }
        } catch (error) {
            console.error("Delete request failed:", error);
        }
    };

    return (
        <Box sx={{ p: 3 }}>
            {/* Header Section */}
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 4 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    <AccountTree sx={{ fontSize: 32, color: '#5e35b1' }} />
                    <Box>
                        <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                            Approval Workflows
                        </Typography>
                        <Typography variant="body2" color="textSecondary">
                            Define and manage the sequence of approvals for your assets.
                        </Typography>
                    </Box>
                </Box>
                <Button
                    variant="contained"
                    startIcon={<Add />}
                    onClick={onCreate}
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, borderRadius: 2, px: 3 }}
                >
                    Create New Workflow
                </Button>
            </Box>

            {/* Workflows Table */}
            <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, overflow: 'hidden' }}>
                <Table>
                    <TableHead sx={{ bgcolor: '#f8f9fa' }}>
                        <TableRow>
                            <TableCell sx={{ fontWeight: 700 }}>Workflow Details</TableCell>
                            <TableCell sx={{ fontWeight: 700 }}>Trigger</TableCell>
                            <TableCell sx={{ fontWeight: 700 }}>Steps</TableCell>
                            <TableCell sx={{ fontWeight: 700 }}>Status</TableCell>
                            <TableCell sx={{ fontWeight: 700 }}>Last Modified</TableCell>
                            <TableCell align="right" sx={{ fontWeight: 700 }}>Actions</TableCell>
                        </TableRow>
                    </TableHead>
                    <TableBody>
                        {workflows.length > 0 ? workflows.map((wf) => (
                            <TableRow key={wf.id} hover>
                                <TableCell>
                                    <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>{wf.name}</Typography>
                                    <Typography variant="caption" color="textSecondary" sx={{ display: 'block' }}>
                                        {wf.description || "No description provided."}
                                    </Typography>
                                </TableCell>
                                <TableCell>
                                    <Chip label={wf.trigger_type || 'on_upload'} size="small" variant="outlined" />
                                </TableCell>
                                <TableCell>
                                    <Typography variant="body2">{wf.step_count || 0} Steps</Typography>
                                </TableCell>
                                <TableCell>
                                    <Chip
                                        label={wf.status === 'active' ? "Active" : "Inactive"}
                                        color={wf.status === 'active' ? "success" : "default"}
                                        size="small"
                                        icon={wf.status === 'active' ? <ToggleOn /> : <ToggleOff />}
                                    />
                                </TableCell>
                                <TableCell>
                                    <Box sx={{ display: 'flex', flexDirection: 'column' }}>
                                        <Typography variant="body2" sx={{ fontWeight: 500 }}>
                                            {wf.last_modified_by || "System"}
                                        </Typography>
                                        <Typography variant="caption" color="textSecondary">
                                            {wf.updated_at}
                                        </Typography>
                                    </Box>
                                </TableCell>
                                <TableCell align="right">
                                    <Tooltip title="Edit Workflow">
                                        <IconButton size="small" onClick={() => onEdit(wf)}>
                                            <Edit fontSize="small" />
                                        </IconButton>
                                    </Tooltip>
                                    <Tooltip title="View History">
                                        <IconButton size="small">
                                            <History fontSize="small" />
                                        </IconButton>
                                    </Tooltip>
                                    <Tooltip title="Delete">
                                        <IconButton size="small" color="error" onClick={() => handleDelete(wf.id)}>
                                            <Delete fontSize="small" />
                                        </IconButton>
                                    </Tooltip>
                                </TableCell>
                            </TableRow>
                        )) : (
                            <TableRow>
                                <TableCell colSpan={6} align="center" sx={{ py: 8 }}>
                                    <Typography color="textSecondary">No workflows created yet. Start by creating your first approval process.</Typography>
                                </TableCell>
                            </TableRow>
                        )}
                    </TableBody>
                </Table>
            </Paper>
        </Box>
    );
}