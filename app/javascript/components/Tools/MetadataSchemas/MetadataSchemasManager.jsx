import React, { useState, useEffect, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Box, Typography, CircularProgress, Button, Tooltip,
    Chip, Stack, Paper, Divider, IconButton, Alert,
    List, ListItem, ListItemButton, ListItemIcon, ListItemText,
    Collapse, Checkbox
} from '@mui/material';
import {
    AccountTree, AddOutlined, ContentCopyOutlined, DeleteOutlined,
    EditOutlined, ExpandLess, ExpandMore, FolderOpenOutlined,
    LockOutlined, SchemaOutlined, Star, SubdirectoryArrowRight
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';
import SchemaEditorDialog from './SchemaEditorDialog';
import NewSchemaDialog from './NewSchemaDialog';

const LEVEL_COLORS = { root: '#5e35b1', type: '#0288d1', subtype: '#388e3c' };
const LEVEL_LABELS = { root: 'Root', type: 'Type', subtype: 'Subtype' };

// Root schemas shown per page in the schema library tree. Only root nodes are
// paginated/selectable for bulk delete — their children (type/subtype) always
// render alongside them, mirroring the pattern used by Admin/UserGroupsManager.
const ROOT_SCHEMAS_PER_PAGE = 10;

// ── SchemaTreeNode ────────────────────────────────────────────────────────────
function SchemaTreeNode({ schema, depth = 0, selected, onSelect, canManage = false, checkedIds, onToggleCheck }) {
    const [open, setOpen] = useState(depth === 0);
    const hasChildren = schema.children && schema.children.length > 0;
    const isSelected  = selected?.id === schema.id;
    // Bulk selection only applies to root-level, non-built-in schemas (they are
    // the paginated/deletable unit; children always cascade-delete with their root).
    const checkable = depth === 0 && canManage && !schema.is_builtin;
    const isChecked  = checkable && checkedIds?.has(schema.id);

    return (
        <>
            <ListItem disablePadding>
                <ListItemButton
                    selected={isSelected}
                    onClick={() => onSelect(schema)}
                    sx={{
                        pl: checkable ? 0.5 + depth * 2.5 : 2 + depth * 2.5,
                        borderRadius: '8px',
                        mx: 0.5,
                        mb: 0.25,
                        bgcolor: isSelected ? '#ede7f6' : 'transparent',
                        '&.Mui-selected': { bgcolor: '#ede7f6', color: '#5e35b1' },
                        '&:hover': { bgcolor: '#f5f3ff' },
                    }}
                >
                    {checkable && (
                        <Checkbox
                            size="small"
                            checked={isChecked}
                            data-testid={`schema-select-${schema.id}`}
                            onClick={e => e.stopPropagation()}
                            onChange={() => onToggleCheck(schema.id)}
                            sx={{ p: 0.5, mr: 0.5 }}
                        />
                    )}
                    <ListItemIcon sx={{ minWidth: 28 }}>
                        {depth === 0
                            ? <AccountTree sx={{ fontSize: 18, color: LEVEL_COLORS.root }} />
                            : depth === 1
                                ? <SchemaOutlined sx={{ fontSize: 16, color: LEVEL_COLORS.type }} />
                                : <SubdirectoryArrowRight sx={{ fontSize: 14, color: LEVEL_COLORS.subtype }} />
                        }
                    </ListItemIcon>
                    <ListItemText
                        primary={
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75 }}>
                                <Typography variant="body2" fontWeight={isSelected ? 600 : 400}
                                            sx={{ flexGrow: 1, fontSize: depth === 0 ? '0.875rem' : '0.82rem' }}>
                                    {schema.name}
                                </Typography>
                                {schema.is_builtin && (
                                    <Tooltip title="Built-in schema">
                                        <Star sx={{ fontSize: 14, color: '#f59e0b' }} />
                                    </Tooltip>
                                )}
                                {schema.mime_segment && (
                                    <Chip label={schema.mime_segment} size="small"
                                          sx={{ fontSize: '0.65rem', height: 16, bgcolor: '#f1f5f9' }} />
                                )}
                            </Box>
                        }
                    />
                    {hasChildren && (
                        <IconButton size="small" onClick={e => { e.stopPropagation(); setOpen(p => !p); }}>
                            {open ? <ExpandLess fontSize="small" /> : <ExpandMore fontSize="small" />}
                        </IconButton>
                    )}
                </ListItemButton>
            </ListItem>

            {hasChildren && (
                <Collapse in={open} timeout="auto" unmountOnExit>
                    <List disablePadding>
                        {schema.children.map(child => (
                            <SchemaTreeNode key={child.id} schema={child} depth={depth + 1}
                                            selected={selected} onSelect={onSelect} canManage={canManage} />
                        ))}
                    </List>
                </Collapse>
            )}
        </>
    );
}

// ── SchemaDetailPanel ─────────────────────────────────────────────────────────
function SchemaDetailPanel({ schema, onEdit, onDuplicate, onDelete, canManage = true }) {
    const { t } = useTranslation();
    const [folders, setFolders] = useState([]);

    useEffect(() => {
        if (!schema) return;
        fetch(`/api/v1/metadata_schemas/${schema.id}/folders`)
            .then(r => r.ok ? r.json() : [])
            .then(setFolders)
            .catch(() => {});
    }, [schema]);

    if (!schema) {
        return (
            <Box sx={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
                       color: '#94a3b8', flexDirection: 'column', gap: 2 }}>
                <AccountTree sx={{ fontSize: 64, opacity: 0.3 }} />
                <Typography variant="body2">Select a schema from the tree to inspect or edit it</Typography>
            </Box>
        );
    }

    const levelColor = LEVEL_COLORS[schema.level] ?? '#64748b';
    const tabs       = schema.resolved_tabs ?? schema.tabs ?? [];

    return (
        <Box sx={{ flex: 1, overflow: 'auto', p: 3 }}>
            {/* Header */}
            <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 2, mb: 3 }}>
                <Box sx={{ flex: 1 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
                        <Chip label={LEVEL_LABELS[schema.level]}
                              size="small"
                              sx={{ bgcolor: levelColor, color: '#fff', fontWeight: 600, fontSize: '0.7rem' }} />
                        {schema.is_builtin && (
                            <Chip icon={<Star sx={{ fontSize: '12px !important' }} />}
                                  label="Built-in"
                                  size="small"
                                  sx={{ bgcolor: '#fef3c7', color: '#92400e', fontSize: '0.7rem' }} />
                        )}
                        {schema.mime_segment && (
                            <Chip label={`mime: ${schema.mime_segment}`}
                                  size="small" variant="outlined"
                                  sx={{ fontSize: '0.7rem', borderColor: '#e2e8f0', color: '#64748b' }} />
                        )}
                        {schema.inherits_from_name && (
                            <Chip icon={<AccountTree sx={{ fontSize: '12px !important' }} />}
                                  label={t('metadataSchemas.inheritsChip', { name: schema.inherits_from_name })}
                                  size="small"
                                  data-testid="schema-inherits-chip"
                                  sx={{ bgcolor: '#ede9fe', color: '#5b21b6', fontSize: '0.7rem' }} />
                        )}
                    </Box>
                    <Typography variant="h5" fontWeight={700} sx={{ color: '#1e293b', mb: 0.5 }}>
                        {schema.name}
                    </Typography>
                    <Typography variant="body2" sx={{ color: '#64748b' }}>
                        {schema.description || 'No description provided.'}
                    </Typography>
                </Box>
                {canManage && (
                    <Stack direction="row" spacing={1}>
                        <Tooltip title="Edit schema">
                            <span>
                                <Button variant="contained" size="small" startIcon={<EditOutlined />}
                                        onClick={() => onEdit(schema)}
                                        sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none' }}>
                                    Edit
                                </Button>
                            </span>
                        </Tooltip>
                        <Tooltip title="Duplicate as new custom schema">
                            <IconButton size="small" onClick={() => onDuplicate(schema)}
                                        sx={{ border: '1px solid #e2e8f0' }}>
                                <ContentCopyOutlined fontSize="small" />
                            </IconButton>
                        </Tooltip>
                        {!schema.is_builtin && (
                            <Tooltip title="Delete schema">
                                <IconButton size="small" onClick={() => onDelete(schema)}
                                            sx={{ border: '1px solid #fecaca', color: '#ef4444' }}>
                                    <DeleteOutlined fontSize="small" />
                                </IconButton>
                            </Tooltip>
                        )}
                    </Stack>
                )}
            </Box>

            <Divider sx={{ mb: 3 }} />

            {/* MIME resolution info */}
            {schema.level === 'root' && (
                <Paper variant="outlined" sx={{ p: 2, mb: 3, bgcolor: '#fafafa', borderRadius: 2 }}>
                    <Typography variant="caption" fontWeight={700} sx={{ color: '#475569', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                        MIME Resolution
                    </Typography>
                    <Typography variant="body2" sx={{ mt: 0.5, color: '#64748b' }}>
                        This root schema is matched when an asset's MIME type doesn't resolve to a
                        more specific type or subtype child schema below.
                    </Typography>
                    <Box sx={{ mt: 1 }}>
                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                            Applied to {schema.folder_count ?? 0} folder{schema.folder_count !== 1 ? 's' : ''}
                        </Typography>
                    </Box>
                </Paper>
            )}
            {schema.level === 'type' && (
                <Paper variant="outlined" sx={{ p: 2, mb: 3, bgcolor: '#f0f9ff', borderColor: '#bae6fd', borderRadius: 2 }}>
                    <Typography variant="caption" fontWeight={700} sx={{ color: '#0369a1', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                        MIME Type Match
                    </Typography>
                    <Typography variant="body2" sx={{ mt: 0.5, color: '#0c4a6e' }}>
                        Matches assets whose MIME type begins with <strong>{schema.mime_segment}/</strong>
                        &nbsp;(e.g. <code>{schema.mime_segment}/jpeg</code>, <code>{schema.mime_segment}/png</code>)
                        when no subtype schema matches.
                    </Typography>
                </Paper>
            )}
            {schema.level === 'subtype' && (
                <Paper variant="outlined" sx={{ p: 2, mb: 3, bgcolor: '#f0fdf4', borderColor: '#bbf7d0', borderRadius: 2 }}>
                    <Typography variant="caption" fontWeight={700} sx={{ color: '#166534', textTransform: 'uppercase', letterSpacing: 0.5 }}>
                        MIME Subtype Match
                    </Typography>
                    <Typography variant="body2" sx={{ mt: 0.5, color: '#14532d' }}>
                        Matches assets with exact MIME type <strong>{schema.parent?.mime_segment ?? '…'}/{schema.mime_segment}</strong>.
                        This is the most specific match.
                    </Typography>
                </Paper>
            )}

            {/* Tabs summary */}
            <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1.5, color: '#334155' }}>
                Schema Tabs &amp; Fields
            </Typography>
            {tabs.length === 0 ? (
                <Typography variant="body2" sx={{ color: '#94a3b8', mb: 3 }}>
                    No tabs defined. {schema.level !== 'root' ? 'This schema inherits all tabs from its parent.' : 'Click Edit to add tabs and fields.'}
                </Typography>
            ) : (
                <Stack spacing={1.5} sx={{ mb: 3 }}>
                    {tabs.map((tab, ti) => (
                        <Paper key={tab.id ?? ti} variant="outlined" sx={{ borderRadius: 2, overflow: 'hidden' }}>
                            <Box sx={{ px: 2, py: 1, bgcolor: tab.inherited ? '#f8fafc' : '#faf5ff',
                                       display: 'flex', alignItems: 'center', gap: 1 }}>
                                <Typography variant="body2" fontWeight={600} sx={{ flex: 1 }}>
                                    {tab.name}
                                </Typography>
                                {tab.inherited && (
                                    <Chip icon={<LockOutlined sx={{ fontSize: '12px !important' }} />}
                                          label={`inherited from ${tab.schema_name}`}
                                          size="small"
                                          sx={{ fontSize: '0.65rem', bgcolor: '#f1f5f9', color: '#64748b' }} />
                                )}
                                <Chip label={`${(tab.fields ?? []).length} field${(tab.fields ?? []).length !== 1 ? 's' : ''}`}
                                      size="small" sx={{ fontSize: '0.65rem', bgcolor: '#e0e7ff', color: '#3730a3' }} />
                            </Box>
                            {(tab.fields ?? []).length > 0 && (
                                <Box sx={{ px: 2, py: 1 }}>
                                    <Stack direction="row" gap={0.75} sx={{
  flexWrap: "wrap"
}}>
                                        {tab.fields.map((f, fi) => (
                                            <Chip key={f.id ?? fi}
                                                  label={f.label}
                                                  size="small"
                                                  icon={f.inherited ? <LockOutlined sx={{ fontSize: '10px !important' }} /> : undefined}
                                                  variant="outlined"
                                                  sx={{ fontSize: '0.72rem',
                                                        borderColor: f.required ? '#f87171' : '#e2e8f0',
                                                        color: f.required ? '#991b1b' : '#475569',
                                                        bgcolor: f.inherited ? '#f8fafc' : '#fff' }} />
                                        ))}
                                    </Stack>
                                </Box>
                            )}
                        </Paper>
                    ))}
                </Stack>
            )}

            {/* Applied folders */}
            {folders.length > 0 && (
                <>
                    <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1, color: '#334155' }}>
                        Applied to Folders
                    </Typography>
                    <Stack spacing={0.75}>
                        {folders.map(f => (
                            <Box key={f.id} sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                <FolderOpenOutlined sx={{ fontSize: 16, color: '#f59e0b' }} />
                                <Typography variant="body2" sx={{ color: '#475569' }}>{f.name}</Typography>
                            </Box>
                        ))}
                    </Stack>
                </>
            )}
        </Box>
    );
}

// ── MetadataSchemasManager (main) ──────────────────────────────────────────────
export default function MetadataSchemasManager({ canManageSchemas } = {}) {
    const { t } = useTranslation();
    // Dataset attributes arrive as strings ('true'/'false'); coerce to boolean,
    // matching the pattern used by Admin/UserGroupsManager.jsx.
    const canManage = canManageSchemas === true || canManageSchemas === 'true';

    const notify = useNotify();
    const [schemas,          setSchemas]          = useState([]);
    const [loading,          setLoading]          = useState(true);
    const [selected,         setSelected]         = useState(null);
    const [editorOpen,       setEditorOpen]       = useState(false);
    const [editingSchema,    setEditingSchema]    = useState(null);
    const [newDialogOpen,    setNewDialogOpen]    = useState(false);
    const [rootPage,         setRootPage]         = useState(1);
    const [checkedIds,       setCheckedIds]       = useState(new Set());
    const [bulkDeleting,     setBulkDeleting]     = useState(false);

    const fetchSchemas = useCallback(async () => {
        setLoading(true);
        try {
            const res  = await fetch('/api/v1/metadata_schemas');
            const data = await res.json();
            setSchemas(data);
            // Keep selection in sync
            if (selected) {
                const refreshed = findById(data, selected.id);
                setSelected(refreshed ?? null);
            }
        } catch {
            notify('Failed to load metadata schemas.', 'error');
        } finally {
            setLoading(false);
        }
    }, []); // eslint-disable-line react-hooks/exhaustive-deps

    useEffect(() => { fetchSchemas(); }, [fetchSchemas]);

    // Load full detail (with resolved_tabs) when selection changes
    useEffect(() => {
        if (!selected) return;
        fetch(`/api/v1/metadata_schemas/${selected.id}`)
            .then(r => r.json())
            .then(setSelected)
            .catch(() => {});
    }, [selected?.id]); // eslint-disable-line react-hooks/exhaustive-deps

    const handleEdit = (schema) => {
        setEditingSchema(schema);
        setEditorOpen(true);
    };

    const handleSave = async (id, payload) => {
        const res = await fetch(`/api/v1/metadata_schemas/${id}`, {
            method:  'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ metadata_schema: payload }),
        });
        const data = await res.json();
        if (!res.ok) {
            notify(data.errors?.join(', ') ?? 'Save failed', 'error');
            return false;
        }
        notify(`"${data.name}" saved successfully.`, 'success');
        setEditorOpen(false);
        await fetchSchemas();
        setSelected(data);
        return true;
    };

    const handleDuplicate = async (schema) => {
        const res  = await fetch(`/api/v1/metadata_schemas/${schema.id}/duplicate`, { method: 'POST' });
        const data = await res.json();
        if (!res.ok) { notify('Duplication failed.', 'error'); return; }
        notify(`"${data.name}" created. You can now customise it.`, 'success');
        await fetchSchemas();
        setSelected(data);
    };

    const handleDelete = async (schema) => {
        if (!window.confirm(`Delete schema "${schema.name}"? This will also remove all child schemas.`)) return;
        const res = await fetch(`/api/v1/metadata_schemas/${schema.id}`, { method: 'DELETE' });
        if (!res.ok) { notify('Delete failed.', 'error'); return; }
        notify(`"${schema.name}" deleted.`, 'success');
        setSelected(null);
        await fetchSchemas();
    };

    const handleToggleCheck = (id) => {
        setCheckedIds(prev => {
            const next = new Set(prev);
            if (next.has(id)) next.delete(id); else next.add(id);
            return next;
        });
    };

    const handleToggleSelectAll = (pageIds) => {
        setCheckedIds(prev => {
            const allChecked = pageIds.length > 0 && pageIds.every(id => prev.has(id));
            if (allChecked) {
                const next = new Set(prev);
                pageIds.forEach(id => next.delete(id));
                return next;
            }
            return new Set([ ...prev, ...pageIds ]);
        });
    };

    const handleBulkDelete = async () => {
        if (checkedIds.size === 0) return;
        if (!window.confirm(`Delete ${checkedIds.size} selected schema(s)? This will also remove all child schemas.`)) return;
        setBulkDeleting(true);
        try {
            const res  = await fetch('/api/v1/metadata_schemas/bulk_delete', {
                method:  'DELETE',
                headers: { 'Content-Type': 'application/json' },
                body:    JSON.stringify({ ids: Array.from(checkedIds) }),
            });
            const data = await res.json();
            if (!res.ok) { notify(data.error ?? 'Bulk delete failed.', 'error'); return; }
            notify(`${data.deleted_count} schema(s) deleted.`, 'success');
            setCheckedIds(new Set());
            setSelected(null);
            await fetchSchemas();
        } finally {
            setBulkDeleting(false);
        }
    };

    const handleCreate = async (payload) => {
        const res  = await fetch('/api/v1/metadata_schemas', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ metadata_schema: payload }),
        });
        const data = await res.json();
        if (!res.ok) { notify(data.errors?.join(', ') ?? 'Create failed.', 'error'); return false; }
        notify(`Schema "${data.name}" created.`, 'success');
        setNewDialogOpen(false);
        await fetchSchemas();
        setSelected(data);
        return true;
    };

    // Root schemas, paginated. Children always render alongside their parent
    // regardless of page (handled inside SchemaTreeNode's recursive render).
    const totalRootPages = Math.max(1, Math.ceil(schemas.length / ROOT_SCHEMAS_PER_PAGE));
    const clampedRootPage = Math.min(rootPage, totalRootPages);
    const pagedSchemas = schemas.slice(
        (clampedRootPage - 1) * ROOT_SCHEMAS_PER_PAGE,
        clampedRootPage * ROOT_SCHEMAS_PER_PAGE
    );
    const selectablePageIds = pagedSchemas.filter(s => !s.is_builtin).map(s => s.id);
    const allPageSelected = selectablePageIds.length > 0 && selectablePageIds.every(id => checkedIds.has(id));

    return (
        <Box sx={{ display: 'flex', height: '100%', bgcolor: '#f8fafc' }}>
            {/* ── Left: tree panel ── */}
            <Box sx={{ width: '25%', flexShrink: 0, bgcolor: '#fff', borderRight: '1px solid #e2e8f0',
                       display: 'flex', flexDirection: 'column' }}>
                {/* Panel header */}
                <Box sx={{ p: 2, borderBottom: '1px solid #f1f5f9' }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1 }}>
                        <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>
                            Schema Library
                        </Typography>
                        {canManage && (
                            <Tooltip title="Create new root schema">
                                <IconButton size="small" onClick={() => setNewDialogOpen(true)}
                                            data-testid="new-schema-button"
                                            sx={{ bgcolor: '#5e35b1', color: '#fff', '&:hover': { bgcolor: '#4527a0' }, width: 28, height: 28 }}>
                                    <AddOutlined fontSize="small" />
                                </IconButton>
                            </Tooltip>
                        )}
                    </Box>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        Root → Type → Subtype hierarchy
                    </Typography>
                </Box>

                {/* Legend */}
                <Box sx={{ px: 2, py: 1, bgcolor: '#fafafa', borderBottom: '1px solid #f1f5f9' }}>
                    <Stack direction="row" spacing={1.5}>
                        {Object.entries(LEVEL_LABELS).map(([lvl, lbl]) => (
                            <Box key={lvl} sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                                <Box sx={{ width: 8, height: 8, borderRadius: '50%', bgcolor: LEVEL_COLORS[lvl] }} />
                                <Typography variant="caption" sx={{ color: '#64748b', fontSize: '0.7rem' }}>{lbl}</Typography>
                            </Box>
                        ))}
                    </Stack>
                </Box>

                {/* Bulk selection toolbar */}
                {canManage && schemas.length > 0 && (
                    <Box sx={{ px: 2, py: 1, borderBottom: '1px solid #f1f5f9', display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Checkbox
                            size="small"
                            data-testid="schema-select-all"
                            checked={allPageSelected}
                            indeterminate={!allPageSelected && selectablePageIds.some(id => checkedIds.has(id))}
                            disabled={selectablePageIds.length === 0}
                            onChange={() => handleToggleSelectAll(selectablePageIds)}
                            sx={{ p: 0.5 }}
                        />
                        <Typography variant="caption" sx={{ color: '#64748b', flex: 1 }}>
                            {checkedIds.size > 0
                                ? t('common.nSelected', { count: checkedIds.size, defaultValue: `${checkedIds.size} selected` })
                                : t('common.selectAll', { defaultValue: 'Select all' })}
                        </Typography>
                        {checkedIds.size > 0 && (
                            <Tooltip title="Delete selected schemas">
                                <span>
                                    <IconButton size="small" data-testid="schema-bulk-delete-button"
                                                onClick={handleBulkDelete} disabled={bulkDeleting}
                                                sx={{ color: '#ef4444' }}>
                                        <DeleteOutlined fontSize="small" />
                                    </IconButton>
                                </span>
                            </Tooltip>
                        )}
                    </Box>
                )}

                {/* Tree */}
                <Box sx={{ flex: 1, overflow: 'auto', py: 1 }}>
                    {loading ? (
                        <Box sx={{ display: 'flex', justifyContent: 'center', pt: 4 }}>
                            <CircularProgress size={28} sx={{ color: '#5e35b1' }} />
                        </Box>
                    ) : schemas.length === 0 ? (
                        <Typography variant="body2" sx={{ p: 2, color: '#94a3b8' }}>No schemas found.</Typography>
                    ) : (
                        <List disablePadding>
                            {pagedSchemas.map(s => (
                                <SchemaTreeNode key={s.id} schema={s}
                                               selected={selected} onSelect={setSelected}
                                               canManage={canManage}
                                               checkedIds={checkedIds} onToggleCheck={handleToggleCheck} />
                            ))}
                        </List>
                    )}
                </Box>

                {/* Root-level pagination */}
                {!loading && schemas.length > 0 && totalRootPages > 1 && (
                    <Stack direction="row" spacing={1} sx={{ py: 1, borderTop: '1px solid #f1f5f9', justifyContent: 'center' }}>
                        <Button
                            size="small"
                            disabled={clampedRootPage <= 1}
                            onClick={() => setRootPage(clampedRootPage - 1)}
                        >
                            {t('common.previous', { defaultValue: 'Previous' })}
                        </Button>
                        <Typography variant="caption" sx={{ alignSelf: 'center', px: 1 }}>
                            {t('common.pageOf', { page: clampedRootPage, pages: totalRootPages, defaultValue: `Page ${clampedRootPage} of ${totalRootPages}` })}
                        </Typography>
                        <Button
                            size="small"
                            disabled={clampedRootPage >= totalRootPages}
                            onClick={() => setRootPage(clampedRootPage + 1)}
                        >
                            {t('common.next', { defaultValue: 'Next' })}
                        </Button>
                    </Stack>
                )}
            </Box>

            {/* ── Right: detail panel ── */}
            <Box sx={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
                {/* Top bar */}
                <Box sx={{ px: 3, py: 2, bgcolor: '#fff', borderBottom: '1px solid #e2e8f0',
                           display: 'flex', alignItems: 'center', gap: 2 }}>
                    <AccountTree sx={{ color: '#5e35b1', fontSize: 22 }} />
                    <Box sx={{ flex: 1 }}>
                        <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b', lineHeight: 1.2 }}>
                            Metadata Schemas
                        </Typography>
                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                            Tools › Assets › Metadata Schemas
                        </Typography>
                    </Box>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                        {schemas.length} root schema{schemas.length !== 1 ? 's' : ''}
                    </Typography>
                </Box>

                {!canManage && (
                    <Alert severity="info" data-testid="read-only-banner" sx={{ mx: 3, mt: 2, borderRadius: 2 }}>
                        {t('metadataSchemas.readOnlyBanner')}
                    </Alert>
                )}

                <SchemaDetailPanel
                    schema={selected}
                    onEdit={handleEdit}
                    onDuplicate={handleDuplicate}
                    onDelete={handleDelete}
                    canManage={canManage}
                />
            </Box>

            {/* ── Schema editor dialog ── */}
            {editorOpen && editingSchema && (
                <SchemaEditorDialog
                    schema={editingSchema}
                    onClose={() => setEditorOpen(false)}
                    onSave={handleSave}
                    rootSchemas={schemas}
                    canManage={canManage}
                />
            )}

            {/* ── New schema dialog ── */}
            {newDialogOpen && (
                <NewSchemaDialog
                    open
                    onClose={() => setNewDialogOpen(false)}
                    onCreate={handleCreate}
                    parentSchemas={schemas}
                />
            )}
        </Box>
    );
}

// Helper: find a schema node in a nested tree by id
function findById(schemas, id) {
    for (const s of schemas) {
        if (s.id === id) return s;
        if (s.children?.length) {
            const found = findById(s.children, id);
            if (found) return found;
        }
    }
    return null;
}

