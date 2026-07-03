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
function MetadataField({ field, value, onChange, readOnly, t }) {
    const isLocked = field.inherited || field.read_only || readOnly;
    const label    = (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
            {field.label}
            {field.required && <span style={{ color: '#ef4444' }}>*</span>}
            {field.inherited && (
                <Tooltip title={t('assetMetadataPanel.field.inheritedReadOnly')}>
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
                            displayEmpty size="small" disabled={isLocked}>
                        <MenuItem value=""><em>{t('assetMetadataPanel.field.selectPlaceholder')}</em></MenuItem>
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
                {activeTabs[activeTab] && (activeTabs[activeTab].fields ?? []).map(field => (
                    <MetadataField
                        key={field.id}
                        field={field}
                        value={values[field.map_to_property]}
                        onChange={val => handleChange(field.map_to_property, val)}
                        readOnly={field.inherited && !field.required}
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
