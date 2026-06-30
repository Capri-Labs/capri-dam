import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
    Box, Typography, Button, IconButton, Paper, Stack, Chip,
    TextField, CircularProgress, Alert, Divider, Checkbox,
    FormControlLabel, FormGroup, Tooltip, Collapse, List,
    ListItem, ListItemText, Switch,
} from '@mui/material';
import {
    SecurityOutlined, AddOutlined, CloseOutlined, DeleteOutlined,
    InfoOutlined, SubdirectoryArrowRightOutlined, SearchOutlined,
    CheckOutlined,
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';
import { useTranslation } from 'react-i18next';

// ─── constants ────────────────────────────────────────────────────────────────

const PERMISSIONS = [
    { key: 'read_access',      label: 'Read',      hint: 'View assets & browse folder' },
    { key: 'modify_access',    label: 'Modify',    hint: 'Edit metadata & rename items' },
    { key: 'create_access',    label: 'Create',    hint: 'Upload assets & create sub-folders' },
    { key: 'delete_access',    label: 'Delete',    hint: 'Delete assets & folders' },
    { key: 'replicate_access', label: 'Replicate', hint: 'Push assets to CDN edge nodes' },
    { key: 'manage_access',    label: 'Manage',    hint: 'Manage folder access policies' },
];

const DEFAULT_PERMS = {
    read_access: false, modify_access: false, create_access: false,
    delete_access: false, replicate_access: false, manage_access: false,
    explicit_deny: false,
};

const getCsrfToken = () => document.querySelector('[name="csrf-token"]')?.content;

// ─── PermissionBadge ──────────────────────────────────────────────────────────

function PermissionBadge({ label, active, deny }) {
    return (
        <Chip label={label} size="small" sx={{
            fontSize: '0.62rem', height: 18,
            bgcolor: deny ? '#fee2e2' : active ? '#dcfce7' : '#f1f5f9',
            color:   deny ? '#991b1b' : active ? '#166534' : '#94a3b8',
            fontWeight: active || deny ? 700 : 400,
        }} />
    );
}

// ─── GroupSearch ──────────────────────────────────────────────────────────────

function GroupSearch({ onSelect }) {
    const [query,   setQuery]   = useState('');
    const [results, setResults] = useState([]);
    const [loading, setLoading] = useState(false);
    const timerRef = useRef(null);

    const search = useCallback(async (q) => {
        setLoading(true);
        try {
            const res  = await fetch(`/api/v1/user_groups?q=${encodeURIComponent(q)}&limit=20`);
            const data = await res.json();
            setResults(Array.isArray(data) ? data : []);
        } catch {
            setResults([]);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        clearTimeout(timerRef.current);
        if (query.length < 1) { setResults([]); return; }
        timerRef.current = setTimeout(() => search(query), 300);
        return () => clearTimeout(timerRef.current);
    }, [query, search]);

    return (
        <Box sx={{ position: 'relative' }}>
            <TextField
                size="small" fullWidth
                placeholder="Search groups by name…"
                value={query}
                onChange={e => setQuery(e.target.value)}
                slotProps={{
                    input: {
                        startAdornment: loading
                            ? <CircularProgress size={14} sx={{ mr: 1 }} />
                            : <SearchOutlined sx={{ fontSize: 18, color: '#94a3b8', mr: 0.5 }} />,
                    },
                }}
                sx={{ '& .MuiInputBase-input': { fontSize: '0.85rem' } }}
            />
            {results.length > 0 && (
                <Paper variant="outlined" sx={{
                    position: 'absolute', zIndex: 10, width: '100%',
                    maxHeight: 200, overflow: 'auto', borderRadius: 2, mt: 0.5,
                }}>
                    <List disablePadding>
                        {results.map(g => (
                            <ListItem
                                key={g.id}
                                component="div"
                                onClick={() => { onSelect(g); setQuery(''); setResults([]); }}
                                sx={{ cursor: 'pointer', py: 1, '&:hover': { bgcolor: '#f5f3ff' } }}
                            >
                                <ListItemText
                                    primary={g.name}
                                    secondary={g.is_system ? 'System group' : (g.description || g.slug)}
                                    slotProps={{
                                        primary:   { style: { fontSize: '0.85rem', fontWeight: 600 } },
                                        secondary: { style: { fontSize: '0.72rem' } },
                                    }}
                                />
                                {g.is_system && (
                                    <Chip label="System" size="small"
                                          sx={{ fontSize: '0.62rem', height: 16, bgcolor: '#f0f9ff', color: '#0369a1' }} />
                                )}
                            </ListItem>
                        ))}
                    </List>
                </Paper>
            )}
        </Box>
    );
}

// ─── AddPolicyForm ────────────────────────────────────────────────────────────

function AddPolicyForm({ folderId, folderName, onSaved, onCancel }) {
    const notify       = useNotify();
    const { t }        = useTranslation();
    const [group,      setGroup]   = useState(null);
    const [perms,      setPerms]   = useState(DEFAULT_PERMS);
    const [cascade,    setCascade] = useState(false);
    const [saving,     setSaving]  = useState(false);

    const togglePerm = key => setPerms(p => ({ ...p, [key]: !p[key] }));

    const handleSave = async () => {
        if (!group) { notify(t('folder.access.selectGroup'), 'error'); return; }
        setSaving(true);
        try {
            const res = await fetch(`/api/v1/folders/${folderId}/policies`, {
                method:  'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': getCsrfToken() },
                body:    JSON.stringify({ group_id: group.id, ...perms, cascade }),
            });
            const data = await res.json();
            if (!res.ok) throw new Error((data.errors || [data.error]).join(', '));
            notify(cascade ? t('folder.access.savedWithCascade') : t('folder.access.saved'), 'success');
            onSaved();
        } catch (err) {
            notify(err.message || t('folder.access.saveError'), 'error');
        } finally {
            setSaving(false);
        }
    };

    return (
        <Paper variant="outlined" sx={{
            p: 2.5, borderRadius: 2, borderColor: '#ddd6fe', bgcolor: '#faf5ff', mb: 2,
        }}>
            <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#5b21b6', mb: 1.5 }}>
                {t('folder.access.addGroup')}
            </Typography>

            {/* Group selection */}
            <Box sx={{ mb: 2 }}>
                <Typography variant="caption" fontWeight={600} sx={{ color: '#475569', display: 'block', mb: 0.5 }}>
                    {t('folder.access.group')}
                </Typography>
                {group ? (
                    <Chip
                        label={group.name}
                        size="small"
                        onDelete={() => setGroup(null)}
                        sx={{ bgcolor: '#ede9fe', color: '#5b21b6', fontWeight: 600 }}
                    />
                ) : (
                    <GroupSearch onSelect={setGroup} />
                )}
            </Box>

            {/* Permission matrix */}
            <Box sx={{ mb: 2 }}>
                <Typography variant="caption" fontWeight={600} sx={{ color: '#475569', display: 'block', mb: 0.75 }}>
                    {t('folder.access.permissions')}
                </Typography>
                <FormGroup>
                    <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 0.25 }}>
                        {PERMISSIONS.map(({ key, label, hint }) => (
                            <Tooltip key={key} title={hint} placement="right">
                                <FormControlLabel
                                    control={
                                        <Checkbox
                                            size="small"
                                            checked={perms[key]}
                                            onChange={() => togglePerm(key)}
                                            sx={{ p: 0.5, color: '#7c3aed', '&.Mui-checked': { color: '#7c3aed' } }}
                                        />
                                    }
                                    label={<Typography variant="caption" fontWeight={500}>{label}</Typography>}
                                    sx={{ m: 0 }}
                                />
                            </Tooltip>
                        ))}
                    </Box>
                    {/* Explicit Deny — separated because it overrides all grants */}
                    <FormControlLabel
                        control={
                            <Checkbox
                                size="small"
                                checked={perms.explicit_deny}
                                onChange={() => setPerms(p => ({ ...p, explicit_deny: !p.explicit_deny }))}
                                sx={{ p: 0.5, color: '#ef4444', '&.Mui-checked': { color: '#ef4444' } }}
                            />
                        }
                        label={
                            <Typography variant="caption" fontWeight={600} sx={{ color: '#ef4444' }}>
                                {t('folder.access.explicitDeny')}
                            </Typography>
                        }
                        sx={{ mt: 0.5 }}
                    />
                </FormGroup>
            </Box>

            {/* Cascade option */}
            <Box sx={{ mb: 2, p: 1.5, bgcolor: '#fff', borderRadius: 1.5, border: '1px solid #e2e8f0' }}>
                <FormControlLabel
                    control={
                        <Switch
                            size="small"
                            checked={cascade}
                            onChange={e => setCascade(e.target.checked)}
                            sx={{ '& .MuiSwitch-switchBase.Mui-checked': { color: '#7c3aed' } }}
                        />
                    }
                    label={
                        <Typography variant="caption" fontWeight={600}>
                            {t('folder.access.applyToSubfolders')}
                        </Typography>
                    }
                />
                <Collapse in={cascade}>
                    <Alert
                        severity="warning"
                        icon={<SubdirectoryArrowRightOutlined fontSize="small" />}
                        sx={{ mt: 1, fontSize: '0.78rem', py: 0.5 }}
                    >
                        {t('folder.access.cascadeWarning', { name: folderName || 'this folder' })}
                    </Alert>
                </Collapse>
            </Box>

            <Stack direction="row" spacing={1} sx={{
  justifyContent: "flex-end"
}}>
                <Button size="small" onClick={onCancel} sx={{ textTransform: 'none', color: '#64748b' }}>
                    {t('common.cancel')}
                </Button>
                <Button
                    variant="contained" size="small"
                    onClick={handleSave}
                    disabled={!group || saving}
                    startIcon={saving ? <CircularProgress size={12} color="inherit" /> : <CheckOutlined />}
                    sx={{ textTransform: 'none', bgcolor: '#7c3aed', '&:hover': { bgcolor: '#6d28d9' } }}
                >
                    {saving ? t('common.saving') : t('folder.access.savePolicy')}
                </Button>
            </Stack>
        </Paper>
    );
}

// ─── PolicyRow ────────────────────────────────────────────────────────────────

function PolicyRow({ policy, folderId, inherited, onRemoved }) {
    const notify       = useNotify();
    const { t }        = useTranslation();
    const [removing,       setRemoving]       = useState(false);
    const [cascadeRemove,  setCascadeRemove]  = useState(false);

    const handleRemove = async () => {
        setRemoving(true);
        try {
            const url = `/api/v1/folders/${folderId}/policies/${policy.group_id}` +
                        (cascadeRemove ? '?cascade=true' : '');
            const res = await fetch(url, {
                method:  'DELETE',
                headers: { 'X-CSRF-Token': getCsrfToken() },
            });
            if (!res.ok) throw new Error('Remove failed');
            notify(
                cascadeRemove ? t('folder.access.removedWithCascade') : t('folder.access.removed'),
                'success'
            );
            onRemoved();
        } catch {
            notify(t('folder.access.removeError'), 'error');
        } finally {
            setRemoving(false);
        }
    };

    return (
        <Paper variant="outlined" sx={{
            p: 1.75, borderRadius: 2,
            borderColor: policy.explicit_deny ? '#fecaca' : (inherited ? '#e0e7ff' : '#e2e8f0'),
            bgcolor:     inherited ? '#f8faff' : '#fff',
        }}>
            <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', mb: 1 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, flexWrap: 'wrap' }}>
                    <Typography variant="body2" fontWeight={700} sx={{ color: '#1e293b' }}>
                        {policy.group_name || `Group ${policy.group_id}`}
                    </Typography>
                    {inherited && (
                        <Chip
                            label={`↑ ${policy.source_folder_name || 'parent'}`}
                            size="small"
                            sx={{ fontSize: '0.6rem', height: 16, bgcolor: '#e0e7ff', color: '#3730a3' }}
                        />
                    )}
                    {policy.explicit_deny && (
                        <Chip label={t('folder.access.deny')} size="small"
                              sx={{ fontSize: '0.6rem', height: 16, bgcolor: '#fee2e2', color: '#991b1b', fontWeight: 700 }} />
                    )}
                </Box>

                {/* Remove controls — only for explicit (non-inherited) policies */}
                {!inherited && (
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, flexShrink: 0 }}>
                        <Tooltip title={t('folder.access.removeFromSubfoldersHint')}>
                            <FormControlLabel
                                control={
                                    <Checkbox
                                        size="small"
                                        checked={cascadeRemove}
                                        onChange={e => setCascadeRemove(e.target.checked)}
                                        sx={{
                                            p: 0.25,
                                            color: cascadeRemove ? '#ef4444' : undefined,
                                            '&.Mui-checked': { color: '#ef4444' },
                                        }}
                                    />
                                }
                                label={
                                    <Typography variant="caption" sx={{ fontSize: '0.65rem', color: cascadeRemove ? '#ef4444' : '#94a3b8' }}>
                                        {t('folder.access.removeFromSubfolders')}
                                    </Typography>
                                }
                                sx={{ mr: 0 }}
                            />
                        </Tooltip>
                        <Tooltip title={cascadeRemove ? t('folder.access.removeWithCascadeTooltip') : t('folder.access.removeTooltip')}>
                            <IconButton
                                size="small"
                                onClick={handleRemove}
                                disabled={removing}
                                sx={{ color: '#94a3b8', '&:hover': { color: '#ef4444' } }}
                            >
                                {removing ? <CircularProgress size={14} /> : <DeleteOutlined fontSize="small" />}
                            </IconButton>
                        </Tooltip>
                    </Box>
                )}
            </Box>

            <Stack direction="row" spacing={0.5} sx={{
  gap: '4px !important',
  flexWrap: "wrap"
}}>
                <PermissionBadge label="Read"      active={policy.read_access}      deny={policy.explicit_deny} />
                <PermissionBadge label="Modify"    active={policy.modify_access}    deny={policy.explicit_deny} />
                <PermissionBadge label="Create"    active={policy.create_access}    deny={policy.explicit_deny} />
                <PermissionBadge label="Delete"    active={policy.delete_access}    deny={policy.explicit_deny} />
                <PermissionBadge label="Replicate" active={policy.replicate_access} deny={policy.explicit_deny} />
                <PermissionBadge label="Manage"    active={policy.manage_access}    deny={policy.explicit_deny} />
            </Stack>
        </Paper>
    );
}

// ─── FolderAccessTab (main export) ────────────────────────────────────────────

export default function FolderAccessTab({ folder }) {
    const notify   = useNotify();
    const { t }    = useTranslation();
    const [loading,  setLoading]  = useState(false);
    const [policies, setPolicies] = useState({ explicit_policies: [], inherited_policies: [] });
    const [adding,   setAdding]   = useState(false);

    const fetchPolicies = useCallback(async () => {
        if (!folder?.id) return;
        setLoading(true);
        try {
            const res  = await fetch(`/api/v1/folders/${folder.id}/policies`);
            const data = await res.json();
            setPolicies({
                explicit_policies:  data.explicit_policies  || [],
                inherited_policies: data.inherited_policies || [],
            });
        } catch {
            notify(t('folder.access.loadError'), 'error');
        } finally {
            setLoading(false);
        }
    }, [folder?.id, notify, t]);

    useEffect(() => { fetchPolicies(); }, [fetchPolicies]);

    const explicit  = policies.explicit_policies;
    const inherited = policies.inherited_policies;
    const total     = explicit.length + inherited.length;

    return (
        <Box sx={{ p: 3 }}>
            {/* ── Header ──────────────────────────────────────────────────── */}
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <SecurityOutlined sx={{ color: '#7c3aed', fontSize: 20 }} />
                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>
                        {t('folder.access.title')} ({total})
                    </Typography>
                </Box>
                {adding ? (
                    <IconButton size="small" onClick={() => setAdding(false)}>
                        <CloseOutlined fontSize="small" />
                    </IconButton>
                ) : (
                    <Button
                        size="small" variant="outlined"
                        startIcon={<AddOutlined />}
                        onClick={() => setAdding(true)}
                        sx={{
                            textTransform: 'none', fontSize: '0.75rem',
                            borderColor: '#7c3aed', color: '#7c3aed',
                            '&:hover': { bgcolor: '#faf5ff' },
                        }}
                    >
                        {t('folder.access.addGroup')}
                    </Button>
                )}
            </Box>

            {/* ── Add policy form ──────────────────────────────────────────── */}
            <Collapse in={adding}>
                <AddPolicyForm
                    folderId={folder?.id}
                    folderName={folder?.name}
                    onSaved={() => { setAdding(false); fetchPolicies(); }}
                    onCancel={() => setAdding(false)}
                />
            </Collapse>

            {/* ── Loading spinner ──────────────────────────────────────────── */}
            {loading && (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                    <CircularProgress size={24} sx={{ color: '#7c3aed' }} />
                </Box>
            )}

            {/* ── Policy lists ─────────────────────────────────────────────── */}
            {!loading && (
                <>
                    {/* Explicit policies */}
                    {explicit.length > 0 ? (
                        <>
                            <Typography
                                variant="caption" fontWeight={700}
                                sx={{ color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5, display: 'block', mb: 1 }}
                            >
                                {t('folder.access.explicit')}
                            </Typography>
                            <Stack spacing={1} sx={{ mb: 2 }}>
                                {explicit.map(p => (
                                    <PolicyRow
                                        key={p.group_id}
                                        policy={p}
                                        folderId={folder?.id}
                                        inherited={false}
                                        onRemoved={fetchPolicies}
                                    />
                                ))}
                            </Stack>
                        </>
                    ) : (
                        !adding && (
                            <Alert
                                severity="info" icon={<InfoOutlined />}
                                sx={{ bgcolor: '#f0f9ff', border: '1px solid #bae6fd', fontSize: '0.8rem', mb: 2 }}
                            >
                                {t('folder.access.noPolicies')}
                                <br />
                                <Typography variant="caption" sx={{ color: '#475569', mt: 0.5, display: 'block' }}>
                                    {t('folder.access.defaultAccessNote')}
                                </Typography>
                            </Alert>
                        )
                    )}

                    {/* Inherited policies */}
                    {inherited.length > 0 && (
                        <>
                            <Divider sx={{ mb: 2 }} />
                            <Typography
                                variant="caption" fontWeight={700}
                                sx={{ color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5, display: 'block', mb: 1 }}
                            >
                                {t('folder.access.inherited')}
                            </Typography>
                            <Stack spacing={1}>
                                {inherited.map(p => (
                                    <PolicyRow
                                        key={`inherited-${p.group_id}`}
                                        policy={p}
                                        folderId={folder?.id}
                                        inherited
                                        onRemoved={fetchPolicies}
                                    />
                                ))}
                            </Stack>
                        </>
                    )}
                </>
            )}
        </Box>
    );
}

