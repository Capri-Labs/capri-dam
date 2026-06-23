import React, { useState, useCallback } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Box, Typography, Button, TextField,
    Stack, IconButton, Chip, Tooltip, Select, MenuItem,
    FormControl, InputLabel, Switch, FormControlLabel, Divider,
    Alert
} from '@mui/material';
import {
    AddOutlined, DeleteOutlined, DragIndicator, EditOutlined,
    LockOutlined, CloseOutlined, SaveOutlined, ArrowUpward, ArrowDownward
} from '@mui/icons-material';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────
const FIELD_TYPES = [
    { value: 'text',     label: 'Text (single line)' },
    { value: 'textarea', label: 'Text Area (multi-line)' },
    { value: 'number',   label: 'Number' },
    { value: 'date',     label: 'Date' },
    { value: 'select',   label: 'Dropdown (select)' },
    { value: 'tags',     label: 'Tags (multi-value)' },
    { value: 'url',      label: 'URL' },
    { value: 'checkbox', label: 'Checkbox (boolean)' },
];

function newTab(name) {
    return { id: crypto.randomUUID(), name, position: 0, fields: [] };
}

function newField() {
    return {
        id:              crypto.randomUUID(),
        field_type:      'text',
        label:           '',
        map_to_property: '',
        position:        0,
        required:        false,
        read_only:       false,
        options:         [],
        rules:           {},
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// FieldEditor – right-hand panel that edits one field
// ─────────────────────────────────────────────────────────────────────────────
function FieldEditor({ field, onChange }) {
    if (!field) {
        return (
            <Box sx={{ p: 3, color: '#94a3b8', textAlign: 'center' }}>
                <EditOutlined sx={{ fontSize: 40, opacity: 0.3, mb: 1 }} />
                <Typography variant="body2">Select a field to edit its settings</Typography>
            </Box>
        );
    }

    const update = (key, value) => onChange({ ...field, [key]: value });

    return (
        <Box sx={{ p: 2, overflow: 'auto', height: '100%' }}>
            <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 2, color: '#334155' }}>
                Field Settings
            </Typography>

            {field.inherited && (
                <Alert severity="info" icon={<LockOutlined />} sx={{ mb: 2, py: 0.5, fontSize: '0.8rem' }}>
                    Inherited — read-only
                </Alert>
            )}

            <Stack spacing={2}>
                {/* Type */}
                <FormControl fullWidth size="small" disabled={field.inherited}>
                    <InputLabel>Field Type</InputLabel>
                    <Select value={field.field_type} label="Field Type"
                            onChange={e => update('field_type', e.target.value)}>
                        {FIELD_TYPES.map(t => (
                            <MenuItem key={t.value} value={t.value}>{t.label}</MenuItem>
                        ))}
                    </Select>
                </FormControl>

                {/* Label */}
                <TextField label="Field Label" size="small" fullWidth
                           value={field.label} disabled={field.inherited}
                           onChange={e => update('label', e.target.value)}
                           helperText="Displayed to end users" />

                {/* Map to property */}
                <TextField label="Map to Property" size="small" fullWidth
                           value={field.map_to_property} disabled={field.inherited}
                           onChange={e => update('map_to_property', e.target.value)}
                           helperText="e.g. dc:title or dam:sku. Namespaced values are written as XMP." />

                {/* Options (for select only) */}
                {field.field_type === 'select' && !field.inherited && (
                    <Box>
                        <Typography variant="caption" fontWeight={600} sx={{ mb: 0.5, display: 'block', color: '#475569' }}>
                            Options
                        </Typography>
                        {(field.options ?? []).map((opt, i) => (
                            <Box key={i} sx={{ display: 'flex', gap: 1, mb: 0.75 }}>
                                <TextField size="small" placeholder="Value"
                                           value={opt.value}
                                           onChange={e => {
                                               const opts = [...(field.options ?? [])];
                                               opts[i] = { ...opts[i], value: e.target.value };
                                               update('options', opts);
                                           }}
                                           sx={{ flex: 1 }} />
                                <TextField size="small" placeholder="Label"
                                           value={opt.label}
                                           onChange={e => {
                                               const opts = [...(field.options ?? [])];
                                               opts[i] = { ...opts[i], label: e.target.value };
                                               update('options', opts);
                                           }}
                                           sx={{ flex: 1 }} />
                                <IconButton size="small" color="error"
                                            onClick={() => update('options', field.options.filter((_, j) => j !== i))}>
                                    <DeleteOutlined fontSize="small" />
                                </IconButton>
                            </Box>
                        ))}
                        <Button size="small" startIcon={<AddOutlined />}
                                onClick={() => update('options', [...(field.options ?? []), { value: '', label: '' }])}
                                sx={{ mt: 0.5, textTransform: 'none', color: '#5e35b1' }}>
                            Add option
                        </Button>
                    </Box>
                )}

                <Divider />
                <Typography variant="caption" fontWeight={700} sx={{ color: '#475569' }}>Rules</Typography>

                <FormControlLabel
                    disabled={field.inherited}
                    control={<Switch checked={!!field.required} size="small"
                                     onChange={e => update('required', e.target.checked)} />}
                    label={<Typography variant="body2">Required</Typography>} />

                <FormControlLabel
                    disabled={field.inherited}
                    control={<Switch checked={!!field.read_only} size="small"
                                     onChange={e => update('read_only', e.target.checked)} />}
                    label={<Typography variant="body2">Read Only</Typography>} />
            </Stack>
        </Box>
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// SchemaEditorDialog
// ─────────────────────────────────────────────────────────────────────────────
export default function SchemaEditorDialog({ schema, onClose, onSave }) {
    // Clone own tabs (non-inherited) for editing
    const ownTabs = (schema.resolved_tabs ?? schema.tabs ?? []).filter(t => !t.inherited);
    const inheritedTabs = (schema.resolved_tabs ?? []).filter(t => t.inherited);

    const [tabs,          setTabs]         = useState(ownTabs.map(t => ({
        ...t,
        fields: (t.fields ?? []).filter(f => !f.inherited)
    })));
    const [activeTabIdx,  setActiveTabIdx] = useState(0);
    const [selectedField, setSelectedField] = useState(null);
    const [saving,        setSaving]       = useState(false);
    const [newTabName,    setNewTabName]   = useState('');
    const [addingTab,     setAddingTab]    = useState(false);

    const activeTab = tabs[activeTabIdx];

    // ── Tab operations ──────────────────────────────────────────────────────
    const addTab = () => {
        if (!newTabName.trim()) return;
        const tab = newTab(newTabName.trim());
        setTabs(prev => [...prev, tab]);
        setActiveTabIdx(tabs.length);
        setNewTabName('');
        setAddingTab(false);
    };

    const deleteTab = (idx) => {
        if (!window.confirm('Remove this tab? Fields on it will also be removed.')) return;
        setTabs(prev => prev.filter((_, i) => i !== idx));
        setActiveTabIdx(Math.max(0, activeTabIdx - 1));
        setSelectedField(null);
    };

    const renameTab = (idx, name) => {
        setTabs(prev => prev.map((t, i) => i === idx ? { ...t, name } : t));
    };

    // ── Field operations ─────────────────────────────────────────────────────
    const addField = () => {
        if (!activeTab) return;
        const field = newField(activeTab.id);
        const updatedFields = [...(activeTab.fields ?? []), field];
        updateTabFields(activeTabIdx, updatedFields);
        setSelectedField(field);
    };

    const updateField = useCallback((updatedField) => {
        updateTabFields(activeTabIdx,
            (activeTab.fields ?? []).map(f => f.id === updatedField.id ? updatedField : f)
        );
        setSelectedField(updatedField);
    }, [activeTabIdx, activeTab]); // eslint-disable-line react-hooks/exhaustive-deps

    const deleteField = (fieldId) => {
        updateTabFields(activeTabIdx,
            (activeTab.fields ?? []).filter(f => f.id !== fieldId)
        );
        if (selectedField?.id === fieldId) setSelectedField(null);
    };

    const moveField = (fieldId, direction) => {
        const fields = [...(activeTab.fields ?? [])];
        const idx    = fields.findIndex(f => f.id === fieldId);
        if (idx < 0) return;
        const targetIdx = direction === 'up' ? idx - 1 : idx + 1;
        if (targetIdx < 0 || targetIdx >= fields.length) return;
        [fields[idx], fields[targetIdx]] = [fields[targetIdx], fields[idx]];
        updateTabFields(activeTabIdx, fields);
    };

    const updateTabFields = (tabIdx, fields) => {
        setTabs(prev => prev.map((t, i) => i === tabIdx ? { ...t, fields } : t));
    };

    // ── Save ─────────────────────────────────────────────────────────────────
    const handleSave = async () => {
        setSaving(true);
        const normalizedTabs = tabs.map((tab, ti) => ({
            ...tab,
            position: ti,
            fields: (tab.fields ?? []).map((f, fi) => ({ ...f, position: fi }))
        }));
        await onSave(schema.id, { tabs: normalizedTabs });
        setSaving(false);
    };

    return (
        <Dialog open fullWidth maxWidth="xl" onClose={onClose}
                PaperProps={{ sx: { height: '90vh', borderRadius: 3 } }}>
            {/* Title bar */}
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1.5, pb: 1,
                               borderBottom: '1px solid #f1f5f9', bgcolor: '#faf5ff' }}>
                <EditOutlined sx={{ color: '#5e35b1' }} />
                <Box sx={{ flex: 1 }}>
                    <Typography fontWeight={700} sx={{ color: '#1e293b' }}>
                        Edit Schema — {schema.name}
                    </Typography>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        Level: {schema.level}
                        {schema.mime_segment ? ` · MIME: ${schema.mime_segment}` : ''}
                    </Typography>
                </Box>
                <IconButton onClick={onClose} size="small">
                    <CloseOutlined fontSize="small" />
                </IconButton>
            </DialogTitle>

            <DialogContent sx={{ p: 0, display: 'flex', overflow: 'hidden' }}>
                {/* ── Left: tabs + fields list ── */}
                <Box sx={{ width: 380, flexShrink: 0, display: 'flex', flexDirection: 'column',
                           borderRight: '1px solid #e2e8f0' }}>
                    {/* Tab bar */}
                    <Box sx={{ borderBottom: '1px solid #e2e8f0', bgcolor: '#f8fafc', px: 1, pt: 1 }}>
                        {/* Inherited tabs (read-only labels) */}
                        {inheritedTabs.length > 0 && (
                            <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5, mb: 0.5 }}>
                                {inheritedTabs.map(t => (
                                    <Chip key={t.id}
                                          icon={<LockOutlined sx={{ fontSize: '12px !important' }} />}
                                          label={t.name}
                                          size="small"
                                          sx={{ bgcolor: '#f1f5f9', color: '#64748b', fontSize: '0.72rem' }} />
                                ))}
                            </Box>
                        )}
                        {/* Own tabs */}
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, flexWrap: 'wrap' }}>
                            {tabs.map((tab, i) => (
                                <Box key={tab.id} sx={{ display: 'flex', alignItems: 'center' }}>
                                    <Chip
                                        label={tab.name}
                                        size="small"
                                        onClick={() => { setActiveTabIdx(i); setSelectedField(null); }}
                                        onDelete={() => deleteTab(i)}
                                        deleteIcon={<CloseOutlined sx={{ fontSize: '12px !important' }} />}
                                        sx={{
                                            cursor: 'pointer',
                                            bgcolor: activeTabIdx === i ? '#5e35b1' : '#e0e7ff',
                                            color:   activeTabIdx === i ? '#fff' : '#3730a3',
                                            fontWeight: activeTabIdx === i ? 700 : 400,
                                            fontSize: '0.75rem',
                                            '& .MuiChip-deleteIcon': {
                                                color: activeTabIdx === i ? '#c4b5fd' : '#6366f1'
                                            }
                                        }}
                                    />
                                </Box>
                            ))}
                            {addingTab ? (
                                <Box sx={{ display: 'flex', gap: 0.5, alignItems: 'center' }}>
                                    <TextField size="small" placeholder="Tab name" autoFocus
                                               value={newTabName} onChange={e => setNewTabName(e.target.value)}
                                               onKeyDown={e => { if (e.key === 'Enter') addTab(); if (e.key === 'Escape') setAddingTab(false); }}
                                               sx={{ width: 110, '& input': { fontSize: '0.8rem', py: '4px' } }} />
                                    <Button size="small" variant="contained" onClick={addTab}
                                            sx={{ minWidth: 0, px: 1, py: 0.25, fontSize: '0.75rem', bgcolor: '#5e35b1' }}>
                                        Add
                                    </Button>
                                </Box>
                            ) : (
                                <Tooltip title="Add tab">
                                    <IconButton size="small" onClick={() => setAddingTab(true)}
                                                sx={{ bgcolor: '#f0f4ff', width: 24, height: 24 }}>
                                        <AddOutlined sx={{ fontSize: 14 }} />
                                    </IconButton>
                                </Tooltip>
                            )}
                        </Box>
                    </Box>

                    {/* Fields list for active tab */}
                    <Box sx={{ flex: 1, overflow: 'auto' }}>
                        {/* Inherited fields from ancestor tabs */}
                        {inheritedTabs.flatMap(t => (t.fields ?? []).filter(f => f.inherited)).length > 0 && (
                            <Box sx={{ px: 1.5, py: 1, bgcolor: '#f8fafc', borderBottom: '1px solid #f1f5f9' }}>
                                <Typography variant="caption" sx={{ color: '#94a3b8', textTransform: 'uppercase', letterSpacing: 0.5, fontWeight: 700 }}>
                                    Inherited Fields
                                </Typography>
                                {inheritedTabs.flatMap(t =>
                                    (t.fields ?? []).filter(f => f.inherited).map(f => (
                                        <Box key={f.id}
                                             sx={{ display: 'flex', alignItems: 'center', gap: 1, py: 0.75,
                                                   borderRadius: 1, px: 1, color: '#94a3b8' }}>
                                            <LockOutlined sx={{ fontSize: 14 }} />
                                            <Typography variant="body2" sx={{ flex: 1, fontSize: '0.82rem' }}>{f.label}</Typography>
                                            <Chip label={f.field_type} size="small"
                                                  sx={{ fontSize: '0.65rem', bgcolor: '#f1f5f9', color: '#94a3b8' }} />
                                        </Box>
                                    ))
                                )}
                            </Box>
                        )}

                        {/* Own fields */}
                        {!activeTab ? (
                            <Box sx={{ p: 2, color: '#94a3b8', textAlign: 'center' }}>
                                <Typography variant="body2">Add a tab first</Typography>
                            </Box>
                        ) : (
                            <>
                                <Box sx={{ px: 1.5, pt: 1.5, pb: 0.5, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                                    <Typography variant="caption" sx={{ color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5, fontWeight: 700 }}>
                                        {activeTab.name} Fields
                                    </Typography>
                                    <Button size="small" startIcon={<AddOutlined />}
                                            onClick={addField}
                                            sx={{ textTransform: 'none', fontSize: '0.75rem', color: '#5e35b1' }}>
                                        Add Field
                                    </Button>
                                </Box>
                                {(activeTab.fields ?? []).length === 0 ? (
                                    <Box sx={{ px: 2, py: 2, color: '#94a3b8', textAlign: 'center' }}>
                                        <Typography variant="caption">No fields yet. Click Add Field to start.</Typography>
                                    </Box>
                                ) : (
                                    (activeTab.fields ?? []).map((field, fi) => {
                                        const isSelected = selectedField?.id === field.id;
                                        return (
                                            <Box key={field.id}
                                                 onClick={() => setSelectedField(field)}
                                                 sx={{
                                                     display: 'flex', alignItems: 'center', gap: 1,
                                                     px: 1.5, py: 1, mx: 0.5, mb: 0.25, borderRadius: 1,
                                                     cursor: 'pointer',
                                                     bgcolor: isSelected ? '#ede7f6' : 'transparent',
                                                     border: isSelected ? '1px solid #d8b4fe' : '1px solid transparent',
                                                     '&:hover': { bgcolor: '#f5f3ff' }
                                                 }}>
                                                <DragIndicator sx={{ fontSize: 16, color: '#cbd5e1', cursor: 'grab' }} />
                                                <Box sx={{ flex: 1, minWidth: 0 }}>
                                                    <Typography variant="body2" fontWeight={isSelected ? 600 : 400}
                                                                noWrap sx={{ fontSize: '0.82rem' }}>
                                                        {field.label || <em style={{ color: '#94a3b8' }}>Untitled</em>}
                                                    </Typography>
                                                    <Typography variant="caption" sx={{ color: '#94a3b8', fontSize: '0.7rem' }} noWrap>
                                                        {field.map_to_property || 'no property mapped'}
                                                    </Typography>
                                                </Box>
                                                <Stack direction="row" spacing={0.25}>
                                                    <Chip label={field.field_type} size="small"
                                                          sx={{ fontSize: '0.65rem', bgcolor: '#f0f4ff', color: '#3730a3' }} />
                                                    {field.required && (
                                                        <Chip label="req" size="small"
                                                              sx={{ fontSize: '0.65rem', bgcolor: '#fee2e2', color: '#991b1b' }} />
                                                    )}
                                                </Stack>
                                                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
                                                    <IconButton size="small" onClick={e => { e.stopPropagation(); moveField(field.id, 'up'); }}>
                                                        <ArrowUpward sx={{ fontSize: 12 }} />
                                                    </IconButton>
                                                    <IconButton size="small" onClick={e => { e.stopPropagation(); moveField(field.id, 'down'); }}>
                                                        <ArrowDownward sx={{ fontSize: 12 }} />
                                                    </IconButton>
                                                </Box>
                                                <IconButton size="small" color="error"
                                                            onClick={e => { e.stopPropagation(); deleteField(field.id); }}>
                                                    <DeleteOutlined sx={{ fontSize: 14 }} />
                                                </IconButton>
                                            </Box>
                                        );
                                    })
                                )}
                            </>
                        )}
                    </Box>
                </Box>

                {/* ── Right: field settings ── */}
                <Box sx={{ flex: 1, overflow: 'auto' }}>
                    <FieldEditor
                        field={selectedField}
                        onChange={updateField}
                    />
                </Box>
            </DialogContent>

            <DialogActions sx={{ px: 3, py: 2, borderTop: '1px solid #f1f5f9' }}>
                <Button onClick={onClose} sx={{ textTransform: 'none', color: '#64748b' }}>
                    Cancel
                </Button>
                <Button variant="contained" onClick={handleSave} disabled={saving}
                        startIcon={<SaveOutlined />}
                        sx={{ textTransform: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                    {saving ? 'Saving…' : 'Save Schema'}
                </Button>
            </DialogActions>
        </Dialog>
    );
}

