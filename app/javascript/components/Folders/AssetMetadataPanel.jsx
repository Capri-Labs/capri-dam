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
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';
import { mapEmbeddedMetadata } from '../../utils/embeddedMetadataMapper';

const interpolate = (template, values = {}) => template.replace(/\{\{(\w+)\}\}/g, (_, key) => values[key] ?? '');

// ── Field Renderer ─────────────────────────────────────────────────────────────
function MetadataField({ field, value, onChange, t }) {
    const isLocked = !!field.read_only;
    const label    = (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
            {field.label}
            {field.required && <span style={{ color: '#ef4444' }}>*</span>}
            {isLocked && (
                <Tooltip title={t('assetMetadataPanel.field.readOnlyField', 'This field is read-only')}>
                    <LockOutlined sx={{ fontSize: 12, color: '#94a3b8' }} data-testid="field-readonly-icon" />
                </Tooltip>
            )}
            {field.inherited && !isLocked && (
                <Tooltip title={t('assetMetadataPanel.field.inheritedFromSchema', 'Inherited from {{schema}} schema', { schema: field.schema_name })}>
                    <SchemaOutlined sx={{ fontSize: 12, color: '#a78bfa' }} data-testid="field-inherited-icon" />
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
                           value={value ?? ''} onChange={e => onChange(e.target.value)} slotProps={{inputLabel: { shrink: true } }}
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
                            displayEmpty size="small" disabled={isLocked || field.cascade_locked}>
                        <MenuItem value=""><em>{t('assetMetadataPanel.field.selectPlaceholder', '— select —')}</em></MenuItem>
                        {(field.options ?? []).map(opt => (
                            <MenuItem key={opt.value} value={opt.value}>{opt.label}</MenuItem>
                        ))}
                    </Select>
                    <Typography variant="caption" sx={{ color: field.cascade_locked ? '#f59e0b' : '#94a3b8', mt: 0.25 }}>
                        {field.cascade_locked
                            ? t('assetMetadataPanel.field.cascadeSelectParentFirst', 'Select {{parent}} first', { parent: field.cascade_parent_label })
                            : field.map_to_property}
                    </Typography>
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
                <Autocomplete multiple freeSolo size="small" disabled={isLocked} value={Array.isArray(value) ? value : value ? [value] : []} onChange={(_, newVal) => onChange(newVal)} options={[]} renderValue={(val, getTagProps) => val.map((opt, i) => {
  const { key, ...tagProps } = getTagProps({ index: i });
  return <Chip key={key ?? i} label={opt} size="small" {...tagProps} />;
})} renderInput={params => <TextField {...params} label={label} helperText={`${field.map_to_property}${t('assetMetadataPanel.field.tagsHelperSuffix')}`} sx={{
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

// Builds the editable `{ map_to_property: value }` map for a schema. When the
// schema was resolved by the asset-scoped API each field already carries an
// authoritative `value` (saved edits merged over embedded-metadata defaults);
// those win. For schemas fetched via the generic endpoints (no per-field value)
// we fall back to mapping the asset's own embedded metadata on the client.
function extractSchemaValues(schema, asset) {
    const props = asset?.properties ?? {};
    const base  = { ...mapEmbeddedMetadata(props), ...props };
    const tabs  = schema?.resolved_tabs ?? schema?.tabs ?? [];
    for (const tab of tabs) {
        for (const field of (tab.fields ?? [])) {
            if (field?.map_to_property && field.value !== undefined && field.value !== null) {
                base[field.map_to_property] = field.value;
            }
        }
    }
    return base;
}

// Flattens every field across every tab of a schema — used to resolve
// cascading dropdowns' parent fields, which may live on a different tab.
function flattenFields(schema) {
    const tabs = schema?.resolved_tabs ?? schema?.tabs ?? [];
    return tabs.flatMap(tab => tab.fields ?? []);
}

// Resolves all three contextual metadata rule types set by the Metadata
// Schema editor (`field.rules`) against the current form `values`:
//
//  - Choices  (`rules.cascade`)     — narrows a `select` field's `options` to
//                                     those mapped from the parent's value.
//  - Requirement (`rules.requirement`) — marks the field required (in
//                                     addition to its static `required` flag)
//                                     when the parent's value is one of a
//                                     configured set.
//  - Visibility (`rules.visibility`)  — hides the field entirely unless the
//                                     parent's value is one of a configured
//                                     set; fields with no visibility rule are
//                                     always visible.
//
// Returns the field annotated with: `options`, `cascade_locked`,
// `cascade_parent_label` (Choices); `required`, `dynamic_required`
// (Requirement); `visible`, `visibility_parent_label` (Visibility).
function resolveFieldRules(field, allFields, values) {
    let resolved = { ...field, visible: true };

    const cascade = field.rules?.cascade;
    if (field.field_type === 'select' && cascade?.parent_field_id) {
        const parentField = allFields.find(f => f.id === cascade.parent_field_id);
        const parentValue  = parentField ? values[parentField.map_to_property] : undefined;
        const allowed      = parentValue ? (cascade.map?.[parentValue] ?? []) : [];
        resolved = {
            ...resolved,
            options:              (field.options ?? []).filter(o => allowed.includes(o.value)),
            cascade_locked:       !parentValue,
            cascade_parent_label: parentField?.label,
        };
    }

    const requirement = field.rules?.requirement;
    if (requirement?.parent_field_id) {
        const parentField     = allFields.find(f => f.id === requirement.parent_field_id);
        const parentValue     = parentField ? values[parentField.map_to_property] : undefined;
        const dynamicRequired = (requirement.values ?? []).includes(parentValue);
        resolved = {
            ...resolved,
            required:         !!resolved.required || dynamicRequired,
            dynamic_required: dynamicRequired,
        };
    }

    const visibility = field.rules?.visibility;
    if (visibility?.parent_field_id) {
        const parentField = allFields.find(f => f.id === visibility.parent_field_id);
        const parentValue  = parentField ? values[parentField.map_to_property] : undefined;
        resolved = {
            ...resolved,
            visible:                  (visibility.values ?? []).includes(parentValue),
            visibility_parent_label:  parentField?.label,
        };
    }

    return resolved;
}

// Empty-value check shared by required-field validation.
function isEmptyValue(v) {
    return v === undefined || v === null || v === '' || (Array.isArray(v) && v.length === 0);
}

export default function AssetMetadataPanel({ asset, onAssetUpdated }) {
    const { t } = useTranslation();
    const translate = (key, defaultValue, options = {}) => {
        const result = t(key, options);
        if (result === key || (options.count != null && result === `${key}:${options.count}`)) {
            return interpolate(defaultValue, options);
        }
        return result;
    };
    const notify = useNotify();
    const [schema,    setSchema]    = useState(null);
    const [loading,   setLoading]   = useState(false);
    const [dirty,     setDirty]     = useState(false);
    const [saving,    setSaving]    = useState(false);
    const [activeTab, setActiveTab] = useState(0);
    // Local copy of metadata values being edited
    const [values,    setValues]    = useState({});

    // Fetch the resolved schema for this asset, pre-filled server-side with the
    // values mapped from the asset's own embedded metadata (EXIF/IPTC/XMP). Each
    // field carries a `value`; saved edits take precedence over mapped defaults.
    const fetchSchema = useCallback(async () => {
        if (!asset) return;
        setLoading(true);
        try {
            // 1. Preferred: asset-scoped schema resolved + pre-filled by the API.
            const assetKey = asset.uuid || asset.id;
            if (assetKey) {
                const res  = await fetch(`/api/v1/assets/${assetKey}/metadata_schema`);
                if (res.ok) {
                    const data = await res.json();
                    setSchema(data);
                    setValues(extractSchemaValues(data, asset));
                    setDirty(false);
                    setActiveTab(0);
                    setLoading(false);
                    return;
                }
            }
            // 2. Fall back to the schema stored on the asset itself.
            const schemaId = asset.properties?.applied_schema_id;
            if (schemaId) {
                const res  = await fetch(`/api/v1/metadata_schemas/${schemaId}`);
                const data = await res.json();
                if (res.ok) {
                    setSchema(data);
                    setValues(extractSchemaValues(data, asset));
                    setLoading(false);
                    return;
                }
            }
            // 3. Fall back to folder schema.
            if (asset.folder_id) {
                const res  = await fetch(`/api/v1/folders/${asset.folder_id}/schema`);
                const data = await res.json();
                if (res.ok && data.schema) {
                    setSchema(data.schema);
                    setValues(extractSchemaValues(data.schema, asset));
                    setLoading(false);
                    return;
                }
            }
            // 4. Fall back to Default builtin schema.
            const res  = await fetch('/api/v1/metadata_schemas?slug=default');
            const data = await res.json();
            if (res.ok && Array.isArray(data) && data.length > 0) {
                // fetch full detail with resolved_tabs
                const detail = await fetch(`/api/v1/metadata_schemas/${data[0].id}`);
                const schemaData = await detail.json();
                setSchema(schemaData);
                setValues(extractSchemaValues(schemaData, asset));
            }
        } catch {
            // silent — schema section just won't render
        } finally {
            setLoading(false);
        }
    }, [asset?.id, asset?.uuid, asset?.properties?.applied_schema_id, asset?.folder_id]);

    useEffect(() => {
        fetchSchema();
        setDirty(false);
        setActiveTab(0);
    }, [asset?.id]);

    const handleChange = (field, newValue) => {
        setValues(prev => {
            const next = { ...prev, [field.map_to_property]: newValue };
            // Clear any dependent (Choices-cascading) child fields whose current
            // value is no longer among the allowed options for the new parent value.
            const allFields = flattenFields(schema);
            allFields.forEach(f => {
                const cascade = f.rules?.cascade;
                if (!cascade || cascade.parent_field_id !== field.id || !f.map_to_property) return;
                const allowed = cascade.map?.[newValue] ?? [];
                const currentChildValue = next[f.map_to_property];
                if (currentChildValue && !allowed.includes(currentChildValue)) {
                    next[f.map_to_property] = Array.isArray(currentChildValue) ? [] : '';
                }
            });
            return next;
        });
        setDirty(true);
    };

    // Validates required fields (static `required` plus any dynamic
    // Requirement rule) across every visible field in every tab — not just
    // the active tab — so a hidden required field on another tab still
    // blocks save. Returns the list of `{ field, tabIndex }` still missing a
    // value; empty array means the form is valid to save.
    const validateRequiredFields = (currentSchema, currentValues) => {
        const allTabs   = currentSchema?.resolved_tabs ?? currentSchema?.tabs ?? [];
        const allFields = allTabs.flatMap(tab => tab.fields ?? []);
        const missing   = [];
        allTabs.forEach((tab, tabIndex) => {
            (tab.fields ?? []).forEach(field => {
                const resolved = resolveFieldRules(field, allFields, currentValues);
                if (!resolved.visible || !resolved.required) return;
                if (isEmptyValue(currentValues[field.map_to_property])) {
                    missing.push({ field: resolved, tabIndex });
                }
            });
        });
        return missing;
    };

    const handleSave = async () => {
        const missing = validateRequiredFields(schema, values);
        if (missing.length > 0) {
            const fieldLabels = missing.map(m => m.field.label).join(', ');
            notify(
                translate('assetMetadataPanel.errors.missingRequiredFields',
                          'Please fill in required fields: {{fields}}', { fields: fieldLabels }),
                'error'
            );
            setActiveTab(missing[0].tabIndex);
            return;
        }
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
            if (!res.ok) throw new Error(data.error ?? translate('assetMetadataPanel.errors.saveFailed', 'Save failed'));
            notify(translate('assetMetadataPanel.notifications.metadataSavedSuccessfully', 'Metadata saved successfully.'), 'success');
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
                    {translate('assetMetadataPanel.noSchema.line1', 'No metadata schema applied to this asset yet.')}{' '}
                    {translate('assetMetadataPanel.noSchema.line2Prefix', 'Use')} <strong>{translate('assetMetadataPanel.noSchema.action', 'Tools → Apply Metadata Schema')}</strong> {translate('assetMetadataPanel.noSchema.line2Suffix', 'from the folder view to assign one.')}
                </Alert>
            </Box>
        );
    }

    const tabs = schema.resolved_tabs ?? schema.tabs ?? [];
    const allFields = tabs.flatMap(t => t.fields ?? []);
    // Tabs marked `conditional` (Camera/EXIF, XMP, Photoshop, ICC Profile) only
    // render when the asset actually has at least one resolved value for one of
    // their fields — i.e. the embedded metadata of that kind genuinely exists.
    // Non-conditional tabs (Basic, IPTC, custom tabs) keep the existing behavior.
    const hasAnyValue = (tab) => (tab.fields ?? []).some(f => {
        const v = values[f.map_to_property];
        return v !== undefined && v !== null && v !== '' && !(Array.isArray(v) && v.length === 0);
    });
    const activeTabs = tabs.filter(t => {
        if (t.conditional) return hasAnyValue(t);
        return (t.fields ?? []).length > 0 || !t.inherited;
    });

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
                        <Chip label={translate('assetMetadataPanel.builtIn', 'Built-in')} size="small"
                              sx={{ ml: 1, height: 16, fontSize: '0.62rem', bgcolor: '#fef3c7', color: '#92400e' }} />
                    )}
                    <Typography variant="caption" sx={{ display: 'block', color: '#7c3aed' }}>
                        {translate('assetMetadataPanel.schemaSummary', '{{count}} tabs · MIME-resolved schema', { count: tabs.length })}
                    </Typography>
                </Box>
                <Tooltip title={translate('assetMetadataPanel.reloadSchema', 'Reload schema')}>
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
                               {saving ? translate('assetMetadataPanel.saving', 'Saving…') : translate('assetMetadataPanel.saveChanges', 'Save Changes')}
                           </Button>
                       }>
                    {translate('assetMetadataPanel.unsavedMetadataChanges', 'Unsaved metadata changes')}
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
                {activeTabs[activeTab] && (activeTabs[activeTab].fields ?? [])
                    .map(field => resolveFieldRules(field, allFields, values))
                    .filter(field => field.visible)
                    .map(field => (
                        <MetadataField
                            key={field.id}
                            field={field}
                            value={values[field.map_to_property]}
                            onChange={val => handleChange(field, val)}
                            t={translate}
                        />
                    ))}
                {(!activeTabs[activeTab]?.fields?.length) && (
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        {translate('assetMetadataPanel.noFieldsDefined', 'No fields defined for this tab.')}
                    </Typography>
                )}
            </Box>

            {/* Save button at bottom */}
            {dirty && (
                <Box sx={{ mt: 2, display: 'flex', justifyContent: 'flex-end' }}>
                    <Button variant="contained" onClick={handleSave} disabled={saving}
                            startIcon={<SaveOutlined />}
                            sx={{ textTransform: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                        {saving ? translate('assetMetadataPanel.saving', 'Saving…') : translate('assetMetadataPanel.saveMetadata', 'Save Metadata')}
                    </Button>
                </Box>
            )}
        </Box>
    );
}
