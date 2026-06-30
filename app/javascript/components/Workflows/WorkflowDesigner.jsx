import React, { useState, useEffect, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Box, TextField, Typography, Button, MenuItem, Select, FormControl,
    InputLabel, Stack, Switch, FormControlLabel, Paper, Radio, RadioGroup,
    Chip, Autocomplete, Divider, Tooltip, CircularProgress,
} from '@mui/material';
import {
    Save, BoltOutlined, FolderSpecial, AccountTree,
    RadioButtonChecked, CheckCircleOutlined,
} from '@mui/icons-material';

import { useNotify } from '../../context/NotificationContext';
import WorkflowCanvas from '../Workflows/WorkflowCanvas';

// ── Node-type → backend type map (source of truth for the save payload) ───────
const NODE_TYPE_MAP = {
    approvalNode:            'approval',
    parallelApprovalNode:    'approval',
    sequentialApprovalNode:  'approval',
    emailNode:               'email_notification',
    inAppNotifyNode:         'in_app_notification',
    slackNode:               'slack',
    teamsNode:               'teams',
    smsNode:                 'sms',
    webhookNode:             'webhook',
    secureWebhookNode:       'secure_webhook',
    apiCallNode:             'api_call',
    setStatusNode:           'set_status',
    addTagsNode:             'add_tags',
    removeTagsNode:          'remove_tags',
    moveAssetNode:           'move_asset',
    copyAssetNode:           'copy_asset',
    archiveNode:             'archive',
    publishNode:             'publish',
    metadataUpdateNode:      'update_metadata',
    aiMetadataNode:          'ai_metadata',
    generateThumbNode:       'generate_thumbnail',
    cdnSyncNode:             'cdn_sync',
    delayNode:               'delay',
    conditionNode:           'condition',
};

const APPROVAL_NODE_TYPES = new Set(['approvalNode', 'parallelApprovalNode', 'sequentialApprovalNode']);

// ── Trigger event catalogue ────────────────────────────────────────────────────
const TRIGGER_OPTIONS = [
    { value: 'on_upload',          icon: '⬆️', labelKey: 'triggerOnUpload' },
    { value: 'on_metadata_update', icon: '✏️', labelKey: 'triggerOnMetadataUpdate' },
    { value: 'on_tag_added',       icon: '🏷️', labelKey: 'triggerOnTagAdded' },
    { value: 'on_status_change',   icon: '🔄', labelKey: 'triggerOnStatusChange' },
    { value: 'on_delete',          icon: '🗑️', labelKey: 'triggerOnDelete' },
    { value: 'manual',             icon: '▶️', labelKey: 'triggerManual' },
];

export default function WorkflowDesigner({ initialData, onSave, onCancel }) {
    const { t } = useTranslation();
    const notify = useNotify();
    const isEditing = !!initialData?.id;

    // ── Blueprint meta state ─────────────────────────────────────────────────
    const [meta, setMeta] = useState({
        id:            initialData?.id           || null,
        name:          initialData?.name         || '',
        description:   initialData?.description  || '',
        status:        initialData?.status       || 'active',
        trigger_type:  initialData?.trigger_type || 'on_upload',
        folder_scope:  initialData?.folder_scope || 'all',
        target_folders:  [],
        exclude_folders: [],
    });

    // ── Graph & dictionary state ─────────────────────────────────────────────
    const [nodes, setNodes] = useState([]);
    const [edges, setEdges] = useState([]);
    const [users,   setUsers]   = useState([]);
    const [groups,  setGroups]  = useState([]);
    const [folders, setFolders] = useState([]);
    const [saving, setSaving] = useState(false);

    // ── Derived step count (excludes start/end sentinels) ────────────────────
    const stepCount = useMemo(
        () => nodes.filter(n => n.type !== 'startNode' && n.type !== 'endNode').length,
        [nodes],
    );

    // ── Fetch dictionaries once on mount ────────────────────────────────────
    useEffect(() => {
        fetch('/admin/users.json')
            .then(r => r.json())
            .then(d => setUsers(d.users || []))
            .catch(() => notify(t('workflowDesigner.loadUsersError'), 'error'));

        fetch('/admin/user_groups.json')
            .then(r => r.json())
            .then(d => setGroups(d.user_groups || []))
            .catch(() => notify(t('workflowDesigner.loadGroupsError'), 'error'));

        fetch('/api/v1/folders.json')
            .then(r => r.json())
            .then(d => setFolders(d.folders || d || []))
            .catch(() => notify(t('workflowDesigner.loadFoldersError'), 'error'));
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    // ── Hydrate canvas and folder selections after dictionaries arrive ───────
    useEffect(() => {
        if (!initialData) {
            setNodes([
                { id: 'start', type: 'startNode', position: { x: 300, y: 50  }, deletable: false },
                { id: 'end',   type: 'endNode',   position: { x: 300, y: 600 }, deletable: false },
            ]);
            return;
        }

        // Hydrate folder chips once the folders list is available
        if (folders.length > 0) {
            const targetIds  = (initialData.target_folder_ids  || []).map(String);
            const excludeIds = (initialData.exclude_folder_ids || []).map(String);
            setMeta(prev => ({
                ...prev,
                target_folders:  folders.filter(f => targetIds.includes(String(f.id))),
                exclude_folders: folders.filter(f => excludeIds.includes(String(f.id))),
            }));
        }

        // Hydrate canvas from saved graph_data …
        const savedGraph = initialData.graph_data || initialData.metadata?.graph_data;
        if (savedGraph?.nodes?.length) {
            setNodes(savedGraph.nodes);
            setEdges(savedGraph.edges || []);
            return;
        }

        // … or reconstruct from flat workflow_steps (legacy format)
        if (initialData.workflow_steps?.length) {
            const rNodes = [{ id: 'start', type: 'startNode', position: { x: 300, y: 50 }, deletable: false }];
            const rEdges = [];
            let lastId   = 'start';

            initialData.workflow_steps.forEach((step, i) => {
                const nodeId = `approval_${step.id}`;
                rNodes.push({
                    id:   nodeId,
                    type: 'approvalNode',
                    position: { x: 300, y: 150 + i * 250 },
                    data: {
                        id: nodeId,
                        step: {
                            id:                     step.id,
                            isNew:                  false,
                            title:                  step.title                    || '',
                            description:            step.description              || '',
                            assigneeType:           step.assignee_type            || 'user',
                            assigneeId:             step.assignee_id              || '',
                            fallback_assignee_type: step.fallback_assignee_type   || 'user',
                            fallback_assignee_id:   step.fallback_assignee_id     || '',
                            logic:                  step.logic                    || 'any',
                            deadline_days:          step.deadline_days            || 2,
                            config:                 step.step_config              || {},
                        },
                    },
                });
                rEdges.push({
                    id: `edge_${lastId}_${nodeId}`,
                    source: lastId,
                    target: nodeId,
                    sourceHandle: lastId === 'start' ? null : 'approved',
                    animated: true,
                    style: { strokeWidth: 2, stroke: '#22c55e' },
                });
                lastId = nodeId;
            });

            const endY = 150 + initialData.workflow_steps.length * 250;
            rNodes.push({ id: 'end', type: 'endNode', position: { x: 300, y: endY }, deletable: false });
            rEdges.push({
                id: `edge_${lastId}_end`,
                source: lastId, target: 'end',
                sourceHandle: 'approved', animated: true,
                style: { strokeWidth: 2, stroke: '#22c55e' },
            });

            setNodes(rNodes);
            setEdges(rEdges);
            return;
        }

        // Empty blueprint fallback
        setNodes([
            { id: 'start', type: 'startNode', position: { x: 300, y: 50  }, deletable: false },
            { id: 'end',   type: 'endNode',   position: { x: 300, y: 600 }, deletable: false },
        ]);
    }, [initialData, folders]); // eslint-disable-line react-hooks/exhaustive-deps

    // ── Save ─────────────────────────────────────────────────────────────────
    const handleSave = async () => {
        if (!meta.name.trim()) {
            notify(t('workflowDesigner.validationNoName'), 'error');
            return;
        }

        const stepNodes    = nodes.filter(n => n.type !== 'startNode' && n.type !== 'endNode');
        const approvalNodes = stepNodes.filter(n => APPROVAL_NODE_TYPES.has(n.type));

        const invalidApproval = approvalNodes.find(n => !n.data?.step?.assigneeId);
        if (invalidApproval) {
            notify(t('workflowDesigner.validationNoAssignee'), 'error');
            return;
        }

        setSaving(true);

        const activeStepsAttributes = stepNodes.map((node, index) => {
            const s          = node.data.step || {};
            const isApproval = APPROVAL_NODE_TYPES.has(node.type);

            const stepData = {
                title:                  s.title       || `Step ${index + 1}`,
                description:            s.description || '',
                position:               index + 1,
                step_type:              isApproval ? 'approval' : 'automated_action',
                node_type:              NODE_TYPE_MAP[node.type] || 'approval',
                step_config:            s.config      || {},
                assignee_type:          isApproval ? (s.assigneeType || 'user') : 'system',
                assignee_id:            isApproval ? (s.assigneeId   || '0')    : '0',
                // Per-step escalation path — now properly persisted
                fallback_assignee_type: s.fallback_assignee_type || 'user',
                fallback_assignee_id:   s.fallback_assignee_id   || '',
                logic:                  s.logic         || 'any',
                deadline_days:          s.deadline_days || 2,
            };

            // Include the DB id to trigger an UPDATE rather than INSERT
            if (!s.isNew && s.id && typeof s.id === 'number') {
                stepData.id = s.id;
            }

            return stepData;
        });

        // Detect deleted steps (present in initialData but removed from canvas)
        const initialStepIds = initialData?.workflow_steps?.map(s => s.id) || [];
        const currentStepIds = stepNodes.map(n => n.data.step?.id).filter(id => typeof id === 'number');
        const deletedStepsAttributes = initialStepIds
            .filter(id => !currentStepIds.includes(id))
            .map(id => ({ id, _destroy: 1 }));

        const { target_folders, exclude_folders, id, ...cleanMeta } = meta;

        const payload = {
            workflow: {
                ...cleanMeta,
                target_folder_ids:        target_folders.map(f => f.id),
                exclude_folder_ids:       exclude_folders.map(f => f.id),
                workflow_steps_attributes: [...activeStepsAttributes, ...deletedStepsAttributes],
                graph_data:               { nodes, edges },
            },
        };

        const url    = meta.id ? `/workflows/${meta.id}` : '/workflows';
        const method = meta.id ? 'PUT' : 'POST';

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const response  = await fetch(url, {
                method,
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(payload),
            });

            if (response.ok) {
                notify(
                    isEditing
                        ? t('workflowDesigner.updatedSuccess')
                        : t('workflowDesigner.savedSuccess'),
                    'success',
                );
                onSave();
            } else {
                const err = await response.json();
                notify(err.errors?.join(', ') || t('workflowDesigner.savedError'), 'error');
            }
        } catch {
            notify(t('workflowDesigner.networkError'), 'error');
        } finally {
            setSaving(false);
        }
    };

    // ── Shared meta setter helper ─────────────────────────────────────────────
    const setField = (field, value) => setMeta(prev => ({ ...prev, [field]: value }));

    // ── Render ────────────────────────────────────────────────────────────────
    return (
        <Box sx={{ display: 'flex', flexDirection: 'column', height: '100%', bgcolor: '#f8fafc', minHeight: '100vh' }}>

            {/* ── Sticky top bar ─────────────────────────────────────────── */}
            <Box sx={{
                position: 'sticky', top: 0, zIndex: 10,
                bgcolor: 'white',
                borderBottom: '1px solid #e2e8f0',
                px: 3, py: 1.5,
                display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                boxShadow: '0 1px 4px 0 rgb(0 0 0 / 0.06)',
            }}>
                <Stack direction="row" spacing={1.5} sx={{
  alignItems: "center"
}}>
                    <AccountTree sx={{ color: '#5e35b1', fontSize: 22 }} />
                    <Typography variant="h6" sx={{ fontWeight: 700, color: '#1e293b', fontSize: '1rem' }}>
                        {isEditing ? t('workflowDesigner.editTitle') : t('workflowDesigner.title')}
                    </Typography>
                    {meta.name && (
                        <Typography variant="body2" sx={{ color: '#64748b', fontStyle: 'italic' }}>
                            — {meta.name}
                        </Typography>
                    )}
                </Stack>

                <Stack direction="row" spacing={1.5} sx={{
  alignItems: "center"
}}>
                    {/* Live step-count badge */}
                    {stepCount > 0 && (
                        <Chip
                            icon={<CheckCircleOutlined sx={{ fontSize: 14 }} />}
                            label={t('workflowDesigner.canvasStepCount_other', { count: stepCount })}
                            size="small"
                            color="success"
                            variant="outlined"
                            sx={{ fontWeight: 700 }}
                        />
                    )}

                    {/* Active toggle */}
                    <Tooltip title={meta.status === 'active' ? t('workflowDesigner.active') : t('workflowDesigner.inactive')} arrow>
                        <FormControlLabel
                            sx={{ m: 0 }}
                            control={
                                <Switch
                                    size="small"
                                    checked={meta.status === 'active'}
                                    onChange={e => setField('status', e.target.checked ? 'active' : 'inactive')}
                                    color="success"
                                />
                            }
                            label={
                                <Typography variant="caption" sx={{ fontWeight: 700, color: meta.status === 'active' ? '#15803d' : '#94a3b8' }}>
                                    {meta.status === 'active' ? t('workflowDesigner.active') : t('workflowDesigner.inactive')}
                                </Typography>
                            }
                        />
                    </Tooltip>

                    <Button onClick={onCancel} disabled={saving} size="small" sx={{ color: '#64748b' }}>
                        {t('common.cancel')}
                    </Button>
                    <Button
                        variant="contained"
                        size="small"
                        startIcon={saving ? <CircularProgress size={14} color="inherit" /> : <Save fontSize="small" />}
                        onClick={handleSave}
                        disabled={saving}
                        sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, px: 2.5 }}
                    >
                        {isEditing ? t('workflowDesigner.saveChanges') : t('workflowDesigner.publishBlueprint')}
                    </Button>
                </Stack>
            </Box>

            {/* ── Page body ──────────────────────────────────────────────── */}
            <Box sx={{ flex: 1, overflowY: 'auto', p: 3 }}>
                <Stack spacing={2.5}>

                    {/* ── Section 1: Blueprint Definition ──────────────── */}
                    <Paper variant="outlined" sx={{ p: 2.5, borderRadius: 2 }}>
                        <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#475569', mb: 2, fontSize: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.06em' }}>
                            {t('workflowDesigner.blueprintSection')}
                        </Typography>
                        <Stack spacing={2}>
                            <TextField
                                fullWidth
                                label={t('workflowDesigner.blueprintName')}
                                placeholder={t('workflowDesigner.blueprintNamePlaceholder')}
                                value={meta.name}
                                onChange={e => setField('name', e.target.value)}
                                required
                                error={meta.name === '' && saving}
                                helperText={meta.name === '' && saving ? t('workflowDesigner.validationNoName') : undefined}
                            />
                            <TextField
                                fullWidth
                                multiline
                                rows={2}
                                label={t('workflowDesigner.globalDescription')}
                                value={meta.description}
                                onChange={e => setField('description', e.target.value)}
                            />
                        </Stack>
                    </Paper>

                    {/* ── Section 2: Trigger & Scope ───────────────────── */}
                    <Paper variant="outlined" sx={{ p: 2.5, borderRadius: 2, borderLeft: '3px solid #3b82f6' }}>
                        <Stack direction="row" spacing={1} sx={{
  mb: 2,
  alignItems: "center"
}}>
                            <BoltOutlined sx={{ color: '#3b82f6', fontSize: 18 }} />
                            <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#475569', fontSize: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.06em' }}>
                                {t('workflowDesigner.triggerScopeSection')}
                            </Typography>
                        </Stack>

                        <Stack direction={{ xs: 'column', md: 'row' }} spacing={2.5}>
                            {/* Trigger event */}
                            <Box sx={{ minWidth: 240 }}>
                                <FormControl fullWidth size="small">
                                    <InputLabel>{t('workflowDesigner.triggerEvent')}</InputLabel>
                                    <Select
                                        value={meta.trigger_type}
                                        label={t('workflowDesigner.triggerEvent')}
                                        onChange={e => setField('trigger_type', e.target.value)}
                                    >
                                        {TRIGGER_OPTIONS.map(opt => (
                                            <MenuItem key={opt.value} value={opt.value}>
                                                <Stack direction="row" spacing={1} sx={{
  alignItems: "center"
}}>
                                                    <span>{opt.icon}</span>
                                                    <span>{t(`workflowDesigner.${opt.labelKey}`)}</span>
                                                </Stack>
                                            </MenuItem>
                                        ))}
                                    </Select>
                                </FormControl>
                            </Box>

                            {/* Folder scope */}
                            <Box sx={{ flexGrow: 1, pl: { md: 2 }, borderLeft: { md: '1px solid #e2e8f0' } }}>
                                <Stack direction="row" spacing={1} sx={{
  mb: 1,
  alignItems: "center"
}}>
                                    <FolderSpecial sx={{ color: '#64748b', fontSize: 16 }} />
                                    <Typography variant="caption" sx={{ color: '#64748b', fontWeight: 600 }}>
                                        {t('workflowDesigner.folderScopeLabel')}
                                    </Typography>
                                </Stack>
                                <FormControl component="fieldset">
                                    <RadioGroup
                                        row
                                        value={meta.folder_scope}
                                        onChange={e => setMeta(prev => ({
                                            ...prev,
                                            folder_scope:    e.target.value,
                                            target_folders:  [],
                                            exclude_folders: [],
                                        }))}
                                    >
                                        <FormControlLabel
                                            value="all"
                                            control={<Radio size="small" />}
                                            label={<Typography variant="body2">{t('workflowDesigner.allFolders')}</Typography>}
                                        />
                                        <FormControlLabel
                                            value="specific"
                                            control={<Radio size="small" />}
                                            label={<Typography variant="body2">{t('workflowDesigner.specificFolders')}</Typography>}
                                        />
                                    </RadioGroup>
                                </FormControl>

                                {meta.folder_scope === 'all' && (
                                    <Autocomplete multiple size="small" sx={{
  mt: 1
}} options={folders} getOptionLabel={opt => opt.name || 'Unknown'} value={meta.exclude_folders} onChange={(_, val) => setField('exclude_folders', val)} isOptionEqualToValue={(o, v) => String(o.id) === String(v.id)} renderValue={(value, getTagProps) => value.map((opt, i) => <Chip key={opt.id} variant="outlined" color="error" label={opt.name} size="small" {...getTagProps({
  index: i
})} />)} renderInput={params => <TextField {...params} label={t('workflowDesigner.excludeFolders')} placeholder={t('workflowDesigner.excludeFoldersPlaceholder')} />} />
                                )}

                                {meta.folder_scope === 'specific' && (
                                    <Autocomplete multiple size="small" sx={{
  mt: 1
}} options={folders} getOptionLabel={opt => opt.name || 'Unknown'} value={meta.target_folders} onChange={(_, val) => setField('target_folders', val)} isOptionEqualToValue={(o, v) => String(o.id) === String(v.id)} renderValue={(value, getTagProps) => value.map((opt, i) => <Chip key={opt.id} variant="filled" color="primary" label={opt.name} size="small" {...getTagProps({
  index: i
})} />)} renderInput={params => <TextField {...params} label={t('workflowDesigner.targetFolders')} placeholder={t('workflowDesigner.targetFoldersPlaceholder')} />} />
                                )}
                            </Box>
                        </Stack>
                    </Paper>

                    {/* ── Section 3: Canvas ─────────────────────────────── */}
                    <Box>
                        <Divider sx={{ mb: 1.5 }}>
                            <Stack direction="row" spacing={1} sx={{
  alignItems: "center"
}}>
                                <RadioButtonChecked sx={{ fontSize: 14, color: '#94a3b8' }} />
                                <Typography variant="caption" sx={{ fontWeight: 700, color: '#94a3b8', letterSpacing: '0.08em', textTransform: 'uppercase' }}>
                                    {t('workflowDesigner.canvasSectionLabel')}
                                    {stepCount > 0 && (
                                        <Box component="span" sx={{ ml: 1, color: '#5e35b1' }}>
                                            ({t('workflowDesigner.canvasStepCount_other', { count: stepCount })})
                                        </Box>
                                    )}
                                </Typography>
                            </Stack>
                        </Divider>

                        <WorkflowCanvas
                            nodes={nodes}
                            setNodes={setNodes}
                            edges={edges}
                            setEdges={setEdges}
                            users={users}
                            groups={groups}
                        />
                    </Box>

                </Stack>
            </Box>
        </Box>
    );
}
