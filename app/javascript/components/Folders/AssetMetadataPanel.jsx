import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, Typography, Tabs, Tab, TextField, Select, MenuItem,
    FormControl, FormControlLabel, Switch, Chip, Stack,
    Button, CircularProgress, Tooltip, Divider, Alert, Paper,
    IconButton, Autocomplete
} from '@mui/material';
import {
    SchemaOutlined, EditOutlined, SaveOutlined, LockOutlined,
    CheckCircleOutlined, WarningAmberOutlined, RefreshOutlined
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

// ── Field Renderer ─────────────────────────────────────────────────────────────
function MetadataField({ field, value, onChange, readOnly }) {
    const isLocked = field.inherited || field.read_only || readOnly;
    const label    = (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
            {field.label}
            {field.required && <span style={{ color: '#ef4444' }}>*</span>}
            {field.inherited && (
                <Tooltip title="Inherited from parent schema — read only">
                    <LockOutlined sx={{ fontSize: 12, color: '#94a3b8' }} />
                </Tooltip>
            )}
        </Box>
    );

    const commonProps = {
        size:     'small',
        fullWidth: true,
        disabled: isLocked,
        sx:       { mb: 2 }
    };

    switch (field.field_type) {
        case 'textarea':
            return (
                <TextField {...commonProps} label={label} multiline rows={3}
                           value={value ?? ''} onChange={e => onChange(e.target.value)}
                           helperText={field.map_to_property} />
            );

        case 'number':
            return (
                <TextField {...commonProps} type="number" label={label}
                           value={value ?? ''} onChange={e => onChange(e.target.value)}
                           helperText={field.map_to_property} />
            );

        case 'date':
            return (
                <TextField {...commonProps} type="date" label={label}
                           value={value ?? ''} onChange={e => onChange(e.target.value)}
                           InputLabelProps={{ shrink: true }}
                           helperText={field.map_to_property} />
            );

        case 'url':
            return (
                <TextField {...commonProps} type="url" label={label}
                           value={value ?? ''} onChange={e => onChange(e.target.value)}
                           helperText={field.map_to_property} />
            );

        case 'select':
            return (
                <FormControl {...commonProps}>
                    <Box component="label" sx={{ fontSize: '0.75rem', color: '#475569', mb: 0.5, display: 'block' }}>
                        {label}
                    </Box>
                    <Select value={value ?? ''} onChange={e => onChange(e.target.value)}
                            displayEmpty size="small" disabled={isLocked}>
                        <MenuItem value=""><em>— select —</em></MenuItem>
                        {(field.options ?? []).map(opt => (
                            <MenuItem key={opt.value} value={opt.value}>{opt.label}</MenuItem>
                        ))}
                    </Select>
                    <Typography variant="caption" sx={{ color: '#94a3b8', mt: 0.25 }}>{field.map_to_property}</Typography>
                </FormControl>
            );

        case 'checkbox':
            return (
                <FormControlLabel
                    sx={{ mb: 2, width: '100%' }}
                    disabled={isLocked}
                    control={<Switch size="small" checked={!!value} onChange={e => onChange(e.target.checked)} />}
                    label={<Typography variant="body2">{label}</Typography>}
                />
            );

        case 'tags':
            return (
                <Autocomplete multiple freeSolo size="small" disabled={isLocked} value={Array.isArray(value) ? value : value ? [value] : []} onChange={(_, newVal) => onChange(newVal)} options={[]} renderValue={(val, getTagProps) => val.map((opt, i) => <Chip label={opt} size="small" {...getTagProps({
  index: i
})} key={i} />)} renderInput={params => <TextField {...params} label={label} helperText={`${field.map_to_property} — press Enter to add`} sx={{
  mb: 2
}} />} />
            );

        default: // text
            return (
                <TextField {...commonProps} label={label}
                           value={value ?? ''} onChange={e => onChange(e.target.value)}
                           helperText={field.map_to_property} />
            );
    }
}

// ── AssetMetadataPanel ─────────────────────────────────────────────────────────
export default function AssetMetadataPanel({ asset, onAssetUpdated }) {
    const notify = useNotify();
    const [schema,    setSchema]    = useState(null);
    const [loading,   setLoading]   = useState(false);
    const [dirty,     setDirty]     = useState(false);
    const [saving,    setSaving]    = useState(false);
    const [activeTab, setActiveTab] = useState(0);
    // Local copy of metadata values being edited
    const [values,    setValues]    = useState({});

    // Fetch the resolved schema for this asset
    const fetchSchema = useCallback(async () => {
        if (!asset) return;
        setLoading(true);
        try {
            // 1. Try schema stored on the asset itself
            const schemaId = asset.properties?.applied_schema_id;
            if (schemaId) {
                const res  = await fetch(`/api/v1/metadata_schemas/${schemaId}`);
                const data = await res.json();
                if (res.ok) {
                    setSchema(data);
                    setLoading(false);
                    return;
                }
            }
            // 2. Fall back to folder schema
            if (asset.folder_id) {
                const res  = await fetch(`/api/v1/folders/${asset.folder_id}/schema`);
                const data = await res.json();
                if (res.ok && data.schema) {
                    setSchema(data.schema);
                    setLoading(false);
                    return;
                }
            }
            // 3. Fall back to Default builtin schema
            const res  = await fetch('/api/v1/metadata_schemas?slug=default');
            const data = await res.json();
            if (res.ok && Array.isArray(data) && data.length > 0) {
                // fetch full detail with resolved_tabs
                const detail = await fetch(`/api/v1/metadata_schemas/${data[0].id}`);
                const schemaData = await detail.json();
                setSchema(schemaData);
            }
        } catch {
            // silent — schema section just won't render
        } finally {
            setLoading(false);
        }
    }, [asset?.id, asset?.properties?.applied_schema_id, asset?.folder_id]);

    useEffect(() => {
        fetchSchema();
        // Initialise values from asset properties
        setValues(asset?.properties ?? {});
        setDirty(false);
        setActiveTab(0);
    }, [asset?.id]);

    const handleChange = (property, newValue) => {
        setValues(prev => ({ ...prev, [property]: newValue }));
        setDirty(true);
    };

    const handleSave = async () => {
        setSaving(true);
        try {
            const res  = await fetch(`/api/v1/assets/${asset.id}/metadata`, {
                method:  'PATCH',
                headers: { 'Content-Type': 'application/json' },
                body:    JSON.stringify({
                    schema_id: schema?.id,
                    metadata:  values
                }),
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.error ?? 'Save failed');
            notify('Metadata saved successfully.', 'success');
            setDirty(false);
            if (onAssetUpdated) onAssetUpdated(data);
        } catch (e) {
            notify(e.message, 'error');
        } finally {
            setSaving(false);
        }
    };

    if (loading) {
        return (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                <CircularProgress size={24} sx={{ color: '#5e35b1' }} />
            </Box>
        );
    }

    if (!schema) {
        return (
            <Box sx={{ py: 2 }}>
                <Alert severity="info" icon={<SchemaOutlined />}>
                    No metadata schema applied to this asset yet.
                    Use <strong>Tools → Apply Metadata Schema</strong> from the folder view
                    to assign one.
                </Alert>
            </Box>
        );
    }

    const tabs = schema.resolved_tabs ?? schema.tabs ?? [];
    const activeTabs = tabs.filter(t => (t.fields ?? []).length > 0 || !t.inherited);

    return (
        <Box>
            {/* Schema banner */}
            <Paper variant="outlined" sx={{ p: 1.5, mb: 2, borderRadius: 2, bgcolor: '#faf5ff',
                                            borderColor: '#ddd6fe', display: 'flex', alignItems: 'center', gap: 1 }}>
                <SchemaOutlined sx={{ fontSize: 16, color: '#5e35b1' }} />
                <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography variant="caption" fontWeight={700} sx={{ color: '#5e35b1' }}>
                        {schema.name}
                    </Typography>
                    {schema.is_builtin && (
                        <Chip label="Built-in" size="small"
                              sx={{ ml: 1, height: 16, fontSize: '0.62rem', bgcolor: '#fef3c7', color: '#92400e' }} />
                    )}
                    <Typography variant="caption" sx={{ display: 'block', color: '#7c3aed' }}>
                        {tabs.length} tab{tabs.length !== 1 ? 's' : ''} · MIME-resolved schema
                    </Typography>
                </Box>
                <Tooltip title="Reload schema">
                    <IconButton size="small" onClick={fetchSchema} sx={{ color: '#7c3aed' }}>
                        <RefreshOutlined sx={{ fontSize: 16 }} />
                    </IconButton>
                </Tooltip>
            </Paper>

            {/* Dirty-state save bar */}
            {dirty && (
                <Alert severity="warning" icon={<WarningAmberOutlined />}
                       sx={{ mb: 2, py: 0.5, fontSize: '0.8rem' }}
                       action={
                           <Button size="small" variant="contained" onClick={handleSave} disabled={saving}
                                   startIcon={<SaveOutlined sx={{ fontSize: 14 }} />}
                                   sx={{ textTransform: 'none', fontSize: '0.75rem',
                                        bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                               {saving ? 'Saving…' : 'Save Changes'}
                           </Button>
                       }>
                    Unsaved metadata changes
                </Alert>
            )}

            {/* Tab navigation */}
            {activeTabs.length > 1 && (
                <Tabs value={activeTab} onChange={(_, v) => setActiveTab(v)}
                      variant="scrollable" scrollButtons="auto"
                      sx={{ mb: 2, borderBottom: '1px solid #f1f5f9',
                            '& .MuiTab-root': { textTransform: 'none', minWidth: 'auto', px: 1.5, py: 1, fontSize: '0.8rem' } }}>
                    {activeTabs.map((tab, i) => (
                        <Tab key={tab.id ?? i}
                             label={
                                 <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                                     {tab.name}
                                     {tab.inherited && (
                                         <LockOutlined sx={{ fontSize: 11, color: '#94a3b8' }} />
                                     )}
                                 </Box>
                             } />
                    ))}
                </Tabs>
            )}

            {/* Fields for current tab */}
            <Box>
                {activeTabs[activeTab] && (activeTabs[activeTab].fields ?? []).map(field => (
                    <MetadataField
                        key={field.id}
                        field={field}
                        value={values[field.map_to_property]}
                        onChange={val => handleChange(field.map_to_property, val)}
                        readOnly={field.inherited && !field.required}
                    />
                ))}
                {(!activeTabs[activeTab]?.fields?.length) && (
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        No fields defined for this tab.
                    </Typography>
                )}
            </Box>

            {/* Save button at bottom */}
            {dirty && (
                <Box sx={{ mt: 2, display: 'flex', justifyContent: 'flex-end' }}>
                    <Button variant="contained" onClick={handleSave} disabled={saving}
                            startIcon={<SaveOutlined />}
                            sx={{ textTransform: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                        {saving ? 'Saving…' : 'Save Metadata'}
                    </Button>
                </Box>
            )}
        </Box>
    );
}

