import React, { useState, useEffect } from 'react';
import {
    Box, TextField, Typography, Button, MenuItem, Select, FormControl,
    InputLabel, Divider, Stack, Alert, Autocomplete, Switch, FormControlLabel,
    Paper, Radio, RadioGroup, Chip, Grid
} from '@mui/material';
import { Save, Shield, FolderSpecial } from '@mui/icons-material';

import { useNotify } from '../../context/NotificationContext';
import WorkflowCanvas from '../Workflows/WorkflowCanvas';

export default function WorkflowDesigner({ initialData, onSave, onCancel }) {
    const notify = useNotify();

    // 1. Meta State
    const [workflowMeta, setWorkflowMeta] = useState({
        id: initialData?.id || null,
        name: initialData?.name || '',
        description: initialData?.description || '',
        status: initialData?.status || 'active',
        trigger_type: initialData?.trigger_type || 'on_upload',
        fallback_assignee_type: initialData?.fallback_assignee_type || 'user',
        fallback_assignee_id: initialData?.fallback_assignee_id || '',
        folder_scope: initialData?.folder_scope || 'all',
        target_folders: [],
        exclude_folders: [],
    });

    // 2. Graph & System State
    const [nodes, setNodes] = useState([]);
    const [edges, setEdges] = useState([]);
    const [users, setUsers] = useState([]);
    const [groups, setGroups] = useState([]);
    const [folders, setFolders] = useState([]);
    const [status, setStatus] = useState({ loading: false });

    //  FIX PART 1: Fetch dictionaries ONLY ONCE on mount
    useEffect(() => {
        fetch('/admin/users.json')
            .then(res => res.json())
            .then(data => setUsers(data.users || []))
            .catch(() => notify("Failed to load users", "error"));

        fetch('/admin/user_groups.json')
            .then(res => res.json())
            .then(data => setGroups(data.user_groups || []))
            .catch(() => notify("Failed to load groups", "error"));

        fetch('/api/v1/folders.json')
            .then(res => res.json())
            .then(data => {
                const fetchedFolders = data.folders || data || [];
                setFolders(fetchedFolders);
            })
            .catch(() => notify("Failed to load folders", "error"));

        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    //  FIX PART 2: Hydrate UI only after folders are loaded
    useEffect(() => {
        if (!initialData) {
            setNodes([
                { id: 'start', type: 'startNode', position: { x: 300, y: 50 }, deletable: false },
                { id: 'end', type: 'endNode', position: { x: 300, y: 600 }, deletable: false }
            ]);
            return;
        }

        // --- HYDRATE FOLDERS ---
        if (folders.length > 0) {
            const targetIds = (initialData.target_folder_ids || []).map(String);
            const excludeIds = (initialData.exclude_folder_ids || []).map(String);

            setWorkflowMeta(prev => ({
                ...prev,
                target_folders: folders.filter(f => targetIds.includes(String(f.id))),
                exclude_folders: folders.filter(f => excludeIds.includes(String(f.id)))
            }));
        }

        // --- HYDRATE VISUAL CANVAS ---
        const savedGraph = initialData.graph_data || initialData.metadata?.graph_data;

        if (savedGraph && savedGraph.nodes && savedGraph.nodes.length > 0) {
            setNodes(savedGraph.nodes);
            setEdges(savedGraph.edges || []);
        } else if (initialData.workflow_steps && initialData.workflow_steps.length > 0) {
            const reconstructedNodes = [{ id: 'start', type: 'startNode', position: { x: 300, y: 50 }, deletable: false }];
            const reconstructedEdges = [];
            let lastNodeId = 'start';

            initialData.workflow_steps.forEach((step, index) => {
                const nodeId = `approval_${step.id}`;
                reconstructedNodes.push({
                    id: nodeId,
                    type: 'approvalNode',
                    position: { x: 300, y: 150 + (index * 250) },
                    data: {
                        id: nodeId,
                        step: {
                            id: step.id,
                            isNew: false,
                            title: step.title || '',
                            description: step.description || '',
                            assigneeType: step.assignee_type || 'user',
                            assigneeId: step.assignee_id || '',
                            logic: step.logic || 'any',
                            deadline_days: step.deadline_days || 2,
                            fallback_assignee_type: step.fallback_assignee_type || 'user',
                            fallback_assignee_id: step.fallback_assignee_id || ''
                        }
                    }
                });

                reconstructedEdges.push({
                    id: `edge_${lastNodeId}_${nodeId}`, source: lastNodeId, target: nodeId,
                    sourceHandle: lastNodeId === 'start' ? null : 'approved', animated: true,
                    style: { strokeWidth: 2, stroke: '#22c55e' }
                });
                lastNodeId = nodeId;
            });

            const endNodeY = 150 + (initialData.workflow_steps.length * 250);
            reconstructedNodes.push({ id: 'end', type: 'endNode', position: { x: 300, y: endNodeY }, deletable: false });
            reconstructedEdges.push({
                id: `edge_${lastNodeId}_end`, source: lastNodeId, target: 'end',
                sourceHandle: 'approved', animated: true, style: { strokeWidth: 2, stroke: '#22c55e' }
            });

            setNodes(reconstructedNodes);
            setEdges(reconstructedEdges);
        } else {
            setNodes([
                { id: 'start', type: 'startNode', position: { x: 300, y: 50 }, deletable: false },
                { id: 'end', type: 'endNode', position: { x: 300, y: 600 }, deletable: false }
            ]);
        }
    }, [initialData, folders]); // Re-runs instantly when 'folders' finish downloading

    const handleSave = async () => {
        // Interactive nodes = everything except the start/end sentinels.
        const stepNodes = nodes.filter(n => n.type !== 'startNode' && n.type !== 'endNode');
        const approvalNodes = stepNodes.filter(n => n.data?.step?.isApproval !== false && (n.type === 'approvalNode' || n.type === 'parallelApprovalNode' || n.type === 'sequentialApprovalNode'));

        // Validate: approval nodes require an assignee.
        const invalidNode = approvalNodes.find(node => !node.data.step.assigneeId);
        if (invalidNode) {
            notify("All Approval Steps must have an Assignee selected.", "error");
            return;
        }

        setStatus({ loading: true });

        // Map node-type → the WorkflowStep.node_type enum used by the backend.
        const NODE_TYPE_MAP = {
            approvalNode: 'approval',
            parallelApprovalNode: 'approval',
            sequentialApprovalNode: 'approval',
            emailNode: 'email_notification',
            inAppNotifyNode: 'in_app_notification',
            slackNode: 'slack',
            teamsNode: 'teams',
            smsNode: 'sms',
            webhookNode: 'webhook',
            secureWebhookNode: 'secure_webhook',
            apiCallNode: 'api_call',
            setStatusNode: 'set_status',
            addTagsNode: 'add_tags',
            removeTagsNode: 'remove_tags',
            moveAssetNode: 'move_asset',
            copyAssetNode: 'copy_asset',
            archiveNode: 'archive',
            publishNode: 'publish',
            metadataUpdateNode: 'update_metadata',
            aiMetadataNode: 'ai_metadata',
            generateThumbNode: 'generate_thumbnail',
            cdnSyncNode: 'cdn_sync',
            delayNode: 'delay',
            conditionNode: 'condition',
        };

        const activeStepsAttributes = stepNodes.map((node, index) => {
            const s = node.data.step;
            const isApproval = node.type === 'approvalNode' || node.type === 'parallelApprovalNode' || node.type === 'sequentialApprovalNode';
            const stepData = {
                title: s.title || `Step ${index + 1}`,
                description: s.description || '',
                position: index + 1,
                step_type: isApproval ? 'approval' : 'automated_action',
                node_type: NODE_TYPE_MAP[node.type] || 'approval',
                step_config: s.config || {},
                // Approval steps need a real assignee; automated steps default to a
                // system placeholder so the NOT NULL columns are satisfied.
                assignee_type: isApproval ? s.assigneeType : 'system',
                assignee_id: isApproval ? s.assigneeId : '0',
                logic: s.logic || 'any',
                deadline_days: s.deadline_days || 2
            };
            if (!s.isNew && s.id && typeof s.id === 'number') stepData.id = s.id;
            return stepData;
        });

        const initialStepIds = initialData?.workflow_steps?.map(s => s.id) || [];
        const currentStepIds = stepNodes.map(n => n.data.step.id).filter(id => typeof id === 'number');
        const deletedStepsAttributes = initialStepIds
            .filter(id => !currentStepIds.includes(id))
            .map(id => ({ id: id, _destroy: 1 }));

        const { target_folders, exclude_folders, id, ...cleanMeta } = workflowMeta;

        const payload = {
            workflow: {
                ...cleanMeta,
                target_folder_ids: target_folders.map(f => f.id),
                exclude_folder_ids: exclude_folders.map(f => f.id),
                workflow_steps_attributes: [...activeStepsAttributes, ...deletedStepsAttributes],
                graph_data: { nodes, edges }
            }
        };

        const url = workflowMeta.id ? `/workflows/${workflowMeta.id}` : '/workflows';
        const method = workflowMeta.id ? 'PUT' : 'POST';

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const response = await fetch(url, {
                method,
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(payload)
            });

            if (response.ok) {
                notify("Workflow published successfully!", "success");
                onSave();
            } else {
                const errorData = await response.json();
                notify(errorData.errors?.join(", ") || "Failed to save workflow.", "error");
            }
        } catch (err) {
            notify("Network error occurred.", "error");
        } finally {
            setStatus({ loading: false });
        }
    };

    return (
        <Box sx={{ p: 4, bgcolor: 'white', borderRadius: 4, border: '1px solid #e3e8ef' }}>
            <Typography variant="h5" sx={{ fontWeight: 700, mb: 3 }}>Visual Workflow Designer</Typography>

            <Stack spacing={4}>
                <Stack direction="row" spacing={2} alignItems="center">
                    <TextField
                        fullWidth label="Blueprint Name"
                        value={workflowMeta.name}
                        onChange={(e) => setWorkflowMeta({...workflowMeta, name: e.target.value})}
                    />
                    <FormControlLabel
                        control={<Switch checked={workflowMeta.status === 'active'} onChange={(e) => setWorkflowMeta({...workflowMeta, status: e.target.checked ? 'active' : 'inactive'})} color="success" />}
                        label={workflowMeta.status === 'active' ? "Active" : "Disabled"} sx={{ minWidth: 120, pl: 2 }}
                    />
                </Stack>

                <TextField
                    fullWidth multiline rows={2} label="Global Description"
                    value={workflowMeta.description}
                    onChange={(e) => setWorkflowMeta({...workflowMeta, description: e.target.value})}
                />

                <Paper variant="outlined" sx={{ p: 3, bgcolor: '#fbfcfe', borderRadius: 2, borderLeft: '4px solid #3b82f6' }}>
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 2, color: '#1e293b', display: 'flex', alignItems: 'center', gap: 1 }}>
                        <FolderSpecial fontSize="small" sx={{ color: '#3b82f6' }} /> Scope & Execution Rules
                    </Typography>

                    <Grid container spacing={3} sx={{ display: 'flex' }}>
                        <Box sx={{ minWidth: 250, pl: 3 }}>
                            <FormControl fullWidth size="small">
                                <InputLabel>Trigger Event</InputLabel>
                                <Select
                                    value={workflowMeta.trigger_type} label="Trigger Event"
                                    onChange={(e) => setWorkflowMeta({...workflowMeta, trigger_type: e.target.value})}
                                >
                                    <MenuItem value="on_upload">On Asset Upload</MenuItem>
                                    <MenuItem value="on_metadata_update">On Metadata Update</MenuItem>
                                    <MenuItem value="on_tag_added">On Tag Added</MenuItem>
                                    <MenuItem value="on_status_change">On Status Change</MenuItem>
                                    <MenuItem value="on_delete">On Asset Archival/Deletion</MenuItem>
                                    <MenuItem value="manual">Manual Trigger Only</MenuItem>
                                </Select>
                            </FormControl>
                        </Box>

                        <Box sx={{ flexGrow: 1, pl: 3, borderLeft: '1px solid #e2e8f0' }}>
                            <FormControl component="fieldset" sx={{ mb: 1 }}>
                                <RadioGroup
                                    row
                                    value={workflowMeta.folder_scope}
                                    onChange={(e) => setWorkflowMeta({
                                        ...workflowMeta,
                                        folder_scope: e.target.value,
                                        target_folders: [],
                                        exclude_folders: []
                                    })}
                                >
                                    <FormControlLabel value="all" control={<Radio size="small" />} label={<Typography variant="body2">All Folders (Global)</Typography>} />
                                    <FormControlLabel value="specific" control={<Radio size="small" />} label={<Typography variant="body2">Specific Folders Only</Typography>} />
                                </RadioGroup>
                            </FormControl>

                            {workflowMeta.folder_scope === 'all' && (
                                <Autocomplete
                                    multiple size="small"
                                    options={folders}
                                    getOptionLabel={(opt) => opt.name || 'Unknown Folder'}
                                    value={workflowMeta.exclude_folders}
                                    onChange={(e, val) => setWorkflowMeta({...workflowMeta, exclude_folders: val})}
                                    isOptionEqualToValue={(option, value) => String(option.id) === String(value.id)}
                                    renderTags={(value, getTagProps) =>
                                        value.map((option, index) => (
                                            <Chip variant="outlined" color="error" label={option.name} size="small" {...getTagProps({ index })} />
                                        ))
                                    }
                                    renderInput={(params) => <TextField {...params} label="Exclude Folders (Optional)" placeholder="Select folders to ignore..." />}
                                />
                            )}

                            {workflowMeta.folder_scope === 'specific' && (
                                <Autocomplete
                                    multiple size="small"
                                    options={folders}
                                    getOptionLabel={(opt) => opt.name || 'Unknown Folder'}
                                    value={workflowMeta.target_folders}
                                    onChange={(e, val) => setWorkflowMeta({...workflowMeta, target_folders: val})}
                                    isOptionEqualToValue={(option, value) => String(option.id) === String(value.id)}
                                    renderTags={(value, getTagProps) =>
                                        value.map((option, index) => (
                                            <Chip variant="filled" color="primary" label={option.name} size="small" {...getTagProps({ index })} />
                                        ))
                                    }
                                    renderInput={(params) => <TextField {...params} label="Target Folders (Required)" placeholder="Apply workflow only to..." />}
                                />
                            )}
                        </Box>
                    </Grid>
                </Paper>

                <Divider sx={{ my: 2 }}>Branching Logic Canvas</Divider>

                <WorkflowCanvas
                    nodes={nodes}
                    setNodes={setNodes}
                    edges={edges}
                    setEdges={setEdges}
                    users={users}
                    groups={groups}
                />

                <Alert icon={<Shield color="warning" />} severity="warning" sx={{ mt: 2, bgcolor: '#fff9f0', border: '1px solid #ffe2b7' }}>
                    <Typography variant="subtitle2" sx={{ color: '#663c00' }}>System-Wide Escalation</Typography>
                    <Typography variant="caption" display="block" sx={{ mb: 2 }}>
                        If a visual branch stalls or breaks, this entity holds master override authority.
                    </Typography>

                    <Stack direction="row" spacing={2}>
                        <FormControl size="small" sx={{ minWidth: 150, bgcolor: 'white' }}>
                            <Select
                                value={workflowMeta.fallback_assignee_type}
                                onChange={(e) => setWorkflowMeta({ ...workflowMeta, fallback_assignee_type: e.target.value, fallback_assignee_id: '' })}
                            >
                                <MenuItem value="user">Fallback User</MenuItem>
                                <MenuItem value="group">Fallback Group</MenuItem>
                            </Select>
                        </FormControl>

                        <Autocomplete
                            size="small"
                            fullWidth
                            sx={{ bgcolor: 'white' }}
                            options={workflowMeta.fallback_assignee_type === 'user' ? users : groups}
                            getOptionLabel={(option) => workflowMeta.fallback_assignee_type === 'user' ? (option.display_name || option.email) : option.name}
                            value={(workflowMeta.fallback_assignee_type === 'user' ? users : groups).find(opt => String(opt.id) === String(workflowMeta.fallback_assignee_id)) || null}
                            onChange={(event, newValue) => {
                                setWorkflowMeta({ ...workflowMeta, fallback_assignee_id: newValue ? newValue.id : '' });
                            }}
                            renderInput={(params) => (
                                <TextField {...params} label={workflowMeta.fallback_assignee_type === 'user' ? "Select Escalation User..." : "Select Escalation Group..."} />
                            )}
                        />
                    </Stack>
                </Alert>

                <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 2, mt: 2 }}>
                    <Button onClick={onCancel} disabled={status.loading}>Cancel</Button>
                    <Button
                        variant="contained"
                        startIcon={<Save />}
                        onClick={handleSave}
                        disabled={status.loading}
                        sx={{ bgcolor: '#5e35b1', px: 4 }}
                    >
                        Publish Blueprint
                    </Button>
                </Box>
            </Stack>
        </Box>
    );
}
