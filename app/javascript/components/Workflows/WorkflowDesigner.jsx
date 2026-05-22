import React, { useState, useEffect } from 'react';
import {
    Box, TextField, Typography, Button, Paper, IconButton,
    MenuItem, Select, FormControl, InputLabel, Divider, Stack, Alert, Autocomplete,
    Switch, FormControlLabel
} from '@mui/material';
import {
    Add, Delete, Save, Shield, ArrowUpward, ArrowDownward
} from '@mui/icons-material';

import { useNotify } from '../../context/NotificationContext';

export default function WorkflowDesigner({ initialData, onSave, onCancel }) {
    const notify = useNotify();

    const [deletedStepIds, setDeletedStepIds] = useState([]);

    const formatInitialData = (data) => {
        if (!data) return null;

        const rawSteps = data.workflow_steps || data.steps || [];
        const formattedSteps = rawSteps.map(step => ({
            id: step.id, // Keep the exact DB integer ID
            isNew: false, // Flag that this came from the database
            title: step.title || '',
            description: step.description || '',
            assigneeType: step.assignee_type || 'user',
            assigneeId: step.assignee_id || '',
            logic: step.logic || 'any',
            deadline_days: step.deadline_days || 2
        }));

        return {
            ...data,
            status: data.status || 'active',
            steps: formattedSteps.length > 0 ? formattedSteps : [{
                id: Date.now(), isNew: true, title: '', description: '',
                assigneeType: 'user', assigneeId: '', logic: 'any', deadline_days: 2
            }]
        };
    };

    const [workflow, setWorkflow] = useState(() => {
        const defaultWorkflow = {
            name: '',
            description: '',
            status: 'active',
            trigger_type: 'on_upload',
            fallback_assignee_type: 'user',
            fallback_assignee_id: '',
            steps: [{
                id: Date.now(), isNew: true, title: '', description: '',
                assigneeType: 'user', assigneeId: '', logic: 'any', deadline_days: 2
            }]
        };

        return initialData ? formatInitialData(initialData) : defaultWorkflow;
    });

    const [status, setStatus] = useState({ loading: false, error: null, msg: null });
    const [users, setUsers] = useState([]);
    const [groups, setGroups] = useState([]);

    useEffect(() => {
        fetch('/admin/users.json')
            .then(res => res.json())
            .then(data => setUsers(data.users || []))
            .catch(err => notify(err, "error", 2000));

        fetch('/admin/user_groups.json')
            .then(res => res.json())
            .then(data => setGroups(data.user_groups || []))
            .catch(err => notify(err, "error", 2000));
    }, []);

    const addStep = () => {
        setWorkflow({
            ...workflow,
            steps: [...workflow.steps, {
                id: Date.now(),
                isNew: true, // 🚨 FLAG: Tell the saver this has no DB ID yet
                title: '',
                description: '',
                assigneeType: 'user',
                assigneeId: '',
                logic: 'any',
                deadline_days: 2
            }]
        });
    };

    const updateStep = (id, field, value) => {
        const newSteps = workflow.steps.map(step =>
            step.id === id ? { ...step, [field]: value } : step
        );
        setWorkflow({ ...workflow, steps: newSteps });
    };

    const moveStep = (index, direction) => {
        const newSteps = [...workflow.steps];
        const targetIndex = direction === 'up' ? index - 1 : index + 1;
        if (targetIndex < 0 || targetIndex >= newSteps.length) return;

        [newSteps[index], newSteps[targetIndex]] = [newSteps[targetIndex], newSteps[index]];
        setWorkflow({ ...workflow, steps: newSteps });
    };

    const removeStep = (id) => {
        if (workflow.steps.length === 1) return;

        // 🚨 NEW: If we are removing a step that came from the DB, save its ID to delete later
        const stepToRemove = workflow.steps.find(s => s.id === id);
        if (stepToRemove && !stepToRemove.isNew) {
            setDeletedStepIds([...deletedStepIds, id]);
        }

        setWorkflow({ ...workflow, steps: workflow.steps.filter(s => s.id !== id) });
    };

    const handleSave = async () => {
        setStatus({ loading: true, error: null, msg: null });

        // 1. Format the active steps
        const activeStepsAttributes = workflow.steps.map((s, index) => {
            const stepData = {
                title: s.title,
                description: s.description,
                position: index + 1,
                step_type: 'approval',
                assignee_type: s.assigneeType,
                assignee_id: s.assigneeId,
                logic: s.logic,
                deadline_days: s.deadline_days // Fixed typo from deadlineDays
            };

            // Only attach the ID if it's an existing database record
            if (!s.isNew) {
                stepData.id = s.id;
            }
            return stepData;
        });

        // 2. Format the destroyed steps
        const deletedStepsAttributes = deletedStepIds.map(id => ({
            id: id,
            _destroy: 1 // 🚨 Tell Rails to DROP this row
        }));

        const payload = {
            workflow: {
                name: workflow.name,
                description: workflow.description,
                status: workflow.status,
                trigger_type: workflow.trigger_type,
                fallback_assignee_type: workflow.fallback_assignee_type,
                fallback_assignee_id: workflow.fallback_assignee_id,
                // Combine both arrays so Rails knows what to keep, update, and destroy
                workflow_steps_attributes: [...activeStepsAttributes, ...deletedStepsAttributes]
            }
        };

        const isEditing = !!workflow.id;
        const url = isEditing ? `/workflows/${workflow.id}` : '/workflows';
        const method = isEditing ? 'PUT' : 'POST';

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const response = await fetch(url, {
                method: method,
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(payload)
            });

            const data = await response.json();
            if (response.ok) {
                setStatus({ loading: false, error: null, msg: "Workflow saved successfully!" });
                setTimeout(() => onSave(data.workflow), 1000);
            } else {
                setStatus({ loading: false, error: data.errors?.join(", ") || "Failed to save.", msg: null });
            }
        } catch (err) {
            setStatus({ loading: false, error: "Network error occurred.", msg: null });
        }
    };

    return (
        <Box sx={{ p: 4, bgcolor: 'white', borderRadius: 4, border: '1px solid #e3e8ef' }}>
            <Typography variant="h5" sx={{ fontWeight: 700, mb: 1 }}>Workflow Designer</Typography>

            <Stack spacing={3}>
                <Stack direction="row" spacing={2} alignItems="center">
                    <TextField
                        fullWidth label="Workflow Title"
                        value={workflow.name}
                        onChange={(e) => setWorkflow({...workflow, name: e.target.value})}
                    />
                    <FormControl sx={{ minWidth: 250 }}>
                        <InputLabel>Trigger Event</InputLabel>
                        <Select
                            value={workflow.trigger_type}
                            label="Trigger Event"
                            onChange={(e) => setWorkflow({...workflow, trigger_type: e.target.value})}
                        >
                            <MenuItem value="on_upload">On Asset Upload</MenuItem>
                            <MenuItem value="on_metadata_change">On Metadata Update</MenuItem>
                            <MenuItem value="on_tag_added">On Specific Tag Added</MenuItem>
                            <MenuItem value="on_expiry">Near Expiration Date</MenuItem>
                            <MenuItem value="manual">Manual Trigger Only</MenuItem>
                        </Select>
                    </FormControl>

                    <FormControlLabel
                        control={
                            <Switch
                                checked={workflow.status === 'active'}
                                onChange={(e) => setWorkflow({...workflow, status: e.target.checked ? 'active' : 'inactive'})}
                                color="success"
                            />
                        }
                        label={workflow.status === 'active' ? "Active" : "Disabled"}
                        sx={{ minWidth: 120, pl: 2 }}
                    />
                </Stack>

                <TextField
                    fullWidth multiline rows={2} label="Global Description"
                    value={workflow.description}
                    onChange={(e) => setWorkflow({...workflow, description: e.target.value})}
                />

                <Divider sx={{ my: 1 }}>Sequence of Steps</Divider>

                {workflow.steps?.map((step, index) => (
                    <Paper key={step.id} variant="outlined" sx={{ p: 3, position: 'relative', bgcolor: '#fbfcfe', borderRadius: 2 }}>
                        <Box sx={{ position: 'absolute', right: 10, top: 10, display: 'flex', gap: 1 }}>
                            <IconButton size="small" disabled={index === 0} onClick={() => moveStep(index, 'up')}>
                                <ArrowUpward fontSize="small" />
                            </IconButton>
                            <IconButton size="small" disabled={index === workflow.steps.length - 1} onClick={() => moveStep(index, 'down')}>
                                <ArrowDownward fontSize="small" />
                            </IconButton>
                            <IconButton size="small" color="error" onClick={() => removeStep(step.id)}>
                                <Delete fontSize="small" />
                            </IconButton>
                        </Box>

                        <Typography variant="caption" sx={{ position: 'absolute', top: -10, left: 10, bgcolor: 'white', px: 1, fontWeight: 700, color: '#5e35b1' }}>
                            STEP {index + 1}
                        </Typography>

                        <Stack spacing={2} sx={{ mt: 1 }}>
                            <Stack direction="row" spacing={2}>
                                <TextField
                                    fullWidth size="small" label="Step Title"
                                    placeholder="e.g. Legal Review"
                                    value={step.title}
                                    onChange={(e) => updateStep(step.id, 'title', e.target.value)}
                                />
                                <TextField
                                    fullWidth size="small" label="Instructions for Reviewer"
                                    value={step.description}
                                    onChange={(e) => updateStep(step.id, 'description', e.target.value)}
                                />
                            </Stack>

                            <Stack direction="row" spacing={2} alignItems="center">
                                <FormControl size="small" sx={{ minWidth: 150 }}>
                                    <InputLabel>Assignee</InputLabel>
                                    <Select
                                        value={step.assigneeType}
                                        label="Assignee"
                                        onChange={(e) => updateStep(step.id, 'assigneeType', e.target.value)}
                                    >
                                        <MenuItem value="user">Specific User</MenuItem>
                                        <MenuItem value="group">User Group</MenuItem>
                                    </Select>
                                </FormControl>

                                <Autocomplete
                                    size="small"
                                    sx={{ flexGrow: 1 }}
                                    options={step.assigneeType === 'user' ? users : groups}
                                    getOptionLabel={(option) => step.assigneeType === 'user' ? (option.display_name || option.email) : option.name}
                                    value={(step.assigneeType === 'user' ? users : groups).find(opt => opt.id.toString() === step.assigneeId.toString()) || null}
                                    onChange={(event, newValue) => {
                                        updateStep(step.id, 'assigneeId', newValue ? newValue.id : '');
                                    }}
                                    renderInput={(params) => (
                                        <TextField {...params} label={step.assigneeType === 'user' ? "Search User..." : "Search Group..."} />
                                    )}
                                />

                                <FormControl size="small" sx={{ minWidth: 200 }}>
                                    <InputLabel>Approval Logic</InputLabel>
                                    <Select
                                        value={step.logic}
                                        label="Approval Logic"
                                        onChange={(e) => updateStep(step.id, 'logic', e.target.value)}
                                    >
                                        <MenuItem value="any">First to respond (Any)</MenuItem>
                                        <MenuItem value="all">Unanimous (All)</MenuItem>
                                    </Select>
                                </FormControl>

                                <TextField
                                    size="small" type="number" label="SLA"
                                    value={step.deadline_days}
                                    onChange={(e) => updateStep(step.id, 'deadline_days', e.target.value)}
                                    InputProps={{
                                        endAdornment: <Typography variant="caption">Days</Typography>
                                    }}
                                    sx={{ width: 120 }}
                                />
                            </Stack>
                        </Stack>
                    </Paper>
                ))}

                <Button startIcon={<Add />} variant="outlined" onClick={addStep} sx={{ borderStyle: 'dashed', py: 1.5 }}>
                    Add Another Sequential Step
                </Button>

                <Alert icon={<Shield color="warning" />} severity="warning" sx={{ mt: 2, bgcolor: '#fff9f0', border: '1px solid #ffe2b7' }}>
                    <Typography variant="subtitle2" sx={{ color: '#663c00' }}>Escalation & Safety Valve</Typography>
                    <Typography variant="caption" display="block" sx={{ mb: 2 }}>
                        If a stage stalls, the following entity is granted master approval/decline rights.
                    </Typography>
                    <Stack direction="row" spacing={2}>
                        <FormControl size="small" sx={{ minWidth: 150, bgcolor: 'white' }}>
                            <Select
                                value={workflow.fallback_assignee_type}
                                onChange={(e) => setWorkflow({...workflow, fallback_assignee_type: e.target.value})}
                            >
                                <MenuItem value="user">Fallback User</MenuItem>
                                <MenuItem value="group">Fallback Group</MenuItem>
                            </Select>
                        </FormControl>
                        <Autocomplete
                            size="small"
                            fullWidth
                            sx={{ bgcolor: 'white' }}
                            options={workflow.fallback_assignee_type === 'user' ? users : groups}
                            getOptionLabel={(option) => workflow.fallback_assignee_type === 'user' ? (option.display_name || option.email) : option.name}
                            value={(workflow.fallback_assignee_type === 'user' ? users : groups).find(opt => String(opt.id) === String(workflow.fallback_assignee_id)) || null}
                            onChange={(event, newValue) => {
                                setWorkflow({...workflow, fallback_assignee_id: newValue ? newValue.id : ''});
                            }}
                            renderInput={(params) => (
                                <TextField {...params} label={workflow.fallback_assignee_type === 'user' ? "Select Escalation User..." : "Select Escalation Group..."} />
                            )}
                        />

                        <TextField
                            fullWidth size="small"
                            label="Assignee ID"
                            value={workflow.fallback_assignee_id}
                            onChange={(e) => setWorkflow({...workflow, fallback_assignee_id: e.target.value})}
                            sx={{ bgcolor: 'white' }}
                        />
                    </Stack>
                </Alert>

                <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 2, mt: 2 }}>
                    <Button onClick={onCancel}>Cancel</Button>
                    <Button
                        variant="contained"
                        startIcon={<Save />}
                        onClick={handleSave}
                        sx={{ bgcolor: '#5e35b1', px: 4 }}
                    >
                        Save Workflow
                    </Button>
                </Box>

                {status.error && <Alert severity="error">{status.error}</Alert>}
                {status.msg && <Alert severity="success">{status.msg}</Alert>}
            </Stack>
        </Box>
    );
}