import React, { useState, useEffect, useCallback } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Box, Typography, Button, CircularProgress, Stack,
    List, ListItemButton, ListItemIcon, ListItemText,
    Chip, Divider, Alert, Switch, FormControlLabel, IconButton,
    Collapse, Tooltip
} from '@mui/material';
import {
    AccountTree, SchemaOutlined, Star, ExpandLess, ExpandMore,
    CheckCircle, CloseOutlined, SubdirectoryArrowRight, InfoOutlined
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

// ── SchemaOptionRow ────────────────────────────────────────────────────────────
function SchemaOptionRow({ schema, depth = 0, selected, onSelect }) {
    const [open, setOpen] = useState(depth === 0);
    const isSelected  = selected?.id === schema.id;
    const hasChildren = schema.children?.length > 0;

    // Only root schemas can be applied to folders/assets
    if (depth > 0) return null;

    return (
        <>
            <ListItemButton
                selected={isSelected}
                onClick={() => onSelect(schema)}
                sx={{
                    borderRadius: 2, mb: 0.5,
                    border: isSelected ? '2px solid #5e35b1' : '1px solid #e2e8f0',
                    bgcolor: isSelected ? '#f5f3ff' : '#fff',
                    '&.Mui-selected': { bgcolor: '#f5f3ff' },
                    transition: 'all 0.15s'
                }}
            >
                <ListItemIcon sx={{ minWidth: 36 }}>
                    <AccountTree sx={{ fontSize: 20, color: isSelected ? '#5e35b1' : '#94a3b8' }} />
                </ListItemIcon>
                <ListItemText
                    primary={
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75 }}>
                            <Typography variant="body2" fontWeight={isSelected ? 700 : 500}>
                                {schema.name}
                            </Typography>
                            {schema.is_builtin && (
                                <Chip icon={<Star sx={{ fontSize: '11px !important' }} />}
                                      label="Built-in" size="small"
                                      sx={{ height: 18, fontSize: '0.65rem', bgcolor: '#fef3c7', color: '#92400e' }} />
                            )}
                            <Chip label={`${schema.child_count ?? schema.children?.length ?? 0} type schemas`}
                                  size="small" sx={{ height: 18, fontSize: '0.65rem', bgcolor: '#e0e7ff', color: '#3730a3' }} />
                        </Box>
                    }
                    secondary={schema.description}
                    secondaryTypographyProps={{ sx: { fontSize: '0.75rem', mt: 0.25 } }}
                />
                {isSelected && <CheckCircle sx={{ color: '#5e35b1', ml: 1 }} />}
            </ListItemButton>
        </>
    );
}

// ── ApplySchemaDialog ─────────────────────────────────────────────────────────
export default function ApplySchemaDialog({
    open,
    onClose,
    targetType,     // 'folder' | 'assets'
    targetIds,      // array of folder/asset IDs
    targetNames,    // array of names for display
    currentFolderId // the folder context
}) {
    const notify = useNotify();
    const [schemas,    setSchemas]    = useState([]);
    const [loading,    setLoading]    = useState(false);
    const [selected,   setSelected]   = useState(null);
    const [cascade,    setCascade]    = useState(true);
    const [applying,   setApplying]   = useState(false);

    const fetchSchemas = useCallback(async () => {
        setLoading(true);
        try {
            const res  = await fetch('/api/v1/metadata_schemas');
            const data = await res.json();
            // Show only root schemas (they contain type/subtype children for auto-resolution)
            setSchemas(data.filter(s => s.level === 'root'));
        } catch {
            notify('Failed to load schemas.', 'error');
        } finally {
            setLoading(false);
        }
    }, [notify]);

    useEffect(() => {
        if (open) {
            fetchSchemas();
            setSelected(null);
        }
    }, [open, fetchSchemas]);

    const handleApply = async () => {
        if (!selected) return;
        setApplying(true);

        try {
            if (targetType === 'folder') {
                // Apply to each selected folder
                const promises = targetIds.map(folderId =>
                    fetch(`/api/v1/folders/${folderId}/apply_schema`, {
                        method:  'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body:    JSON.stringify({ schema_id: selected.id, cascade }),
                    })
                );
                await Promise.all(promises);
                notify(
                    `"${selected.name}" schema is being applied to ${targetIds.length} folder${targetIds.length > 1 ? 's' : ''}` +
                    (cascade ? ' and all sub-folders.' : '.'),
                    'success'
                );
            } else {
                // Direct per-asset schema assignment via metadata endpoint
                const promises = targetIds.map(assetId =>
                    fetch(`/api/v1/assets/${assetId}/metadata`, {
                        method:  'PATCH',
                        headers: { 'Content-Type': 'application/json' },
                        body:    JSON.stringify({ schema_id: selected.id, metadata: {} }),
                    })
                );
                await Promise.all(promises);
                notify(
                    `"${selected.name}" schema applied to ${targetIds.length} asset${targetIds.length > 1 ? 's' : ''}.`,
                    'success'
                );
            }
            onClose(true); // pass true = refresh needed
        } catch {
            notify('Failed to apply schema. Please try again.', 'error');
        } finally {
            setApplying(false);
        }
    };

    const isFolderTarget = targetType === 'folder';

    return (
        <Dialog open={open} onClose={() => onClose(false)} maxWidth="sm" fullWidth
                PaperProps={{ sx: { borderRadius: 3 } }}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1.5,
                               borderBottom: '1px solid #f1f5f9', pb: 1.5, bgcolor: '#faf5ff' }}>
                <SchemaOutlined sx={{ color: '#5e35b1' }} />
                <Box sx={{ flex: 1 }}>
                    <Typography fontWeight={700} sx={{ color: '#1e293b' }}>
                        Apply Metadata Schema
                    </Typography>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        {isFolderTarget
                            ? `Applying to ${targetIds.length} folder${targetIds.length > 1 ? 's' : ''}`
                            : `Applying to ${targetIds.length} asset${targetIds.length > 1 ? 's' : ''}`}
                    </Typography>
                </Box>
                <IconButton size="small" onClick={() => onClose(false)}>
                    <CloseOutlined fontSize="small" />
                </IconButton>
            </DialogTitle>

            <DialogContent sx={{ pt: 2.5 }}>
                {/* Target summary */}
                {targetNames?.length > 0 && (
                    <Box sx={{ mb: 2, p: 1.5, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0' }}>
                        <Typography variant="caption" sx={{ color: '#64748b', fontWeight: 600 }}>Selected items:</Typography>
                        <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5, mt: 0.5 }}>
                            {targetNames.slice(0, 5).map((name, i) => (
                                <Chip key={i} label={name} size="small" sx={{ fontSize: '0.72rem' }} />
                            ))}
                            {targetNames.length > 5 && (
                                <Chip label={`+${targetNames.length - 5} more`} size="small" sx={{ fontSize: '0.72rem', bgcolor: '#f1f5f9' }} />
                            )}
                        </Box>
                    </Box>
                )}

                {/* Folder cascade option */}
                {isFolderTarget && (
                    <Alert severity="info" sx={{ mb: 2, fontSize: '0.8rem' }}
                           icon={<InfoOutlined fontSize="small" />}>
                        <Typography variant="body2" fontWeight={600}>Schema Cascade</Typography>
                        <Typography variant="caption">
                            When applied to a folder, the schema automatically resolves to the best match
                            for each asset's MIME type (e.g. image/jpeg → JPEG subtype schema).
                        </Typography>
                        <FormControlLabel
                            sx={{ mt: 0.5, display: 'flex' }}
                            control={<Switch size="small" checked={cascade} onChange={e => setCascade(e.target.checked)} />}
                            label={
                                <Typography variant="caption" fontWeight={600}>
                                    {cascade ? 'Apply to all sub-folders too' : 'Apply to this folder only'}
                                </Typography>
                            }
                        />
                        {cascade && (
                            <Typography variant="caption" sx={{ color: '#475569', display: 'block', mt: 0.5 }}>
                                You can override the schema in any sub-folder individually afterward.
                            </Typography>
                        )}
                    </Alert>
                )}

                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1.5, color: '#334155' }}>
                    Available Schemas
                </Typography>

                {loading ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                        <CircularProgress size={28} sx={{ color: '#5e35b1' }} />
                    </Box>
                ) : schemas.length === 0 ? (
                    <Typography variant="body2" sx={{ color: '#94a3b8' }}>No schemas available.</Typography>
                ) : (
                    <List disablePadding>
                        {schemas.map(s => (
                            <SchemaOptionRow key={s.id} schema={s} selected={selected} onSelect={setSelected} />
                        ))}
                    </List>
                )}

                {selected && (
                    <Box sx={{ mt: 2, p: 1.5, bgcolor: '#f5f3ff', borderRadius: 2, border: '1px solid #ddd6fe' }}>
                        <Typography variant="caption" fontWeight={700} sx={{ color: '#5e35b1' }}>
                            Selected: {selected.name}
                        </Typography>
                        {selected.tabs?.length > 0 && (
                            <Typography variant="caption" sx={{ display: 'block', color: '#7c3aed', mt: 0.25 }}>
                                {selected.tabs.length} tab{selected.tabs.length !== 1 ? 's' : ''} •{' '}
                                {selected.tabs.reduce((n, t) => n + (t.fields?.length ?? 0), 0)} fields
                            </Typography>
                        )}
                    </Box>
                )}
            </DialogContent>

            <DialogActions sx={{ px: 3, py: 2, borderTop: '1px solid #f1f5f9' }}>
                <Button onClick={() => onClose(false)} sx={{ textTransform: 'none', color: '#64748b' }}>
                    Cancel
                </Button>
                <Button
                    variant="contained"
                    onClick={handleApply}
                    disabled={!selected || applying}
                    sx={{ textTransform: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                >
                    {applying ? 'Applying…' : `Apply "${selected?.name ?? ''}"`}
                </Button>
            </DialogActions>
        </Dialog>
    );
}

