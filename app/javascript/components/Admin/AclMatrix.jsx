/**
 * AclMatrix — reusable folder-level permission matrix.
 *
 * Displays all explicit + inherited folder policies for a given entity
 * (a group or a user's effective permissions).  Supports edit mode that
 * saves changes back via the folder_policies API.
 *
 * Only root folders are shown by default; each folder with children can be
 * expanded in place via a chevron toggle, keeping the tree lightweight for
 * large folder counts.  Toggling a permission on a folder cascades that value
 * onto every (currently loaded) descendant row so bulk edits are fast — any
 * descendant can still be unchecked individually afterwards.  An optional
 * "cascade to subfolders" switch also persists the change to every
 * descendant folder in the database when saving.
 *
 * Columns: Read | Modify | Create | Delete | Replicate | Manage | Explicit Deny
 */
import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Box, Typography, Table, TableHead, TableBody, TableRow, TableCell,
  Checkbox, Chip, Tooltip, IconButton, CircularProgress, Alert,
  Stack, TextField, InputAdornment, Switch, FormControlLabel,
} from '@mui/material';
import {
  SaveOutlined, SearchOutlined, LockOutlined,
  FolderOpenOutlined, FolderOutlined,
  ChevronRightOutlined, ExpandMoreOutlined,
  UnfoldMoreOutlined, UnfoldLessOutlined,
} from '@mui/icons-material';
import { apiFetch } from '../../utils/adminUtils';
import { useNotify } from '../../context/NotificationContext';

const PERMISSION_COLS = [
  { key: 'read',      labelKey: 'columns.read',      tipKey: 'tooltips.read' },
  { key: 'modify',    labelKey: 'columns.modify',    tipKey: 'tooltips.modify' },
  { key: 'create',    labelKey: 'columns.create',    tipKey: 'tooltips.create' },
  { key: 'delete',    labelKey: 'columns.delete',    tipKey: 'tooltips.delete' },
  { key: 'replicate', labelKey: 'columns.replicate', tipKey: 'tooltips.replicate' },
  { key: 'manage',    labelKey: 'columns.manage',    tipKey: 'tooltips.manage' },
];

/** Convert backend matrix keys to UI keys */
function normalizeMatrix(matrix = {}) {
  return {
    read:          matrix.read      ?? false,
    modify:        matrix.modify    ?? false,
    create:        matrix.create    ?? false,
    delete:        matrix.delete    ?? false,
    replicate:     matrix.replicate ?? false,
    manage:        matrix.manage    ?? false,
    explicit_deny: matrix.explicit_deny ?? false,
  };
}

/**
 * @param {object} props
 * @param {string|number} props.groupId   - the group ID whose policies to show
 * @param {string}        props.folderId  - optional: filter to a specific folder
 * @param {boolean}       props.readOnly  - disable checkboxes
 * @param {boolean}       props.isAdmin
 */
export default function AclMatrix({ groupId, folderId, readOnly = false, isAdmin = false }) {
  const { t } = useTranslation();
  const tm = (key, opts) => t(`aclMatrix.${key}`, opts);
  const notify = useNotify();
  const [folders, setFolders] = useState([]);
  const [policies, setPolicies] = useState({});  // folderId → matrix
  const [inherited, setInherited] = useState({}); // folderId → { matrix, source }
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(null);
  const [search, setSearch] = useState('');
  const [expanded, setExpanded] = useState({});
  const [cascadeOnSave, setCascadeOnSave] = useState({}); // folderId → bool

  const fetchData = useCallback(async () => {
    if (!groupId) return;
    setLoading(true);
    try {
      // Fetch all folders to build the tree
      const fRes = await apiFetch('/api/v1/folders.json');
      const folderList = fRes.folders || [];
      setFolders(folderList);

      // Fetch policies for each folder (or just the specified one)
      const targets = folderId
        ? folderList.filter(f => f.id === folderId)
        : folderList;

      const newPolicies = {};
      const newInherited = {};

      await Promise.all(
        targets.map(async (folder) => {
          try {
            const pRes = await apiFetch(`/admin/folders/${folder.id}/folder_policies.json`);
            const explicit = (pRes.explicit_policies || []).find(
              p => String(p.group_id) === String(groupId)
            );
            const inh = (pRes.inherited_policies || []).find(
              p => String(p.group_id) === String(groupId)
            );
            if (explicit) newPolicies[folder.id] = normalizeMatrix(explicit.matrix);
            if (inh) newInherited[folder.id] = { matrix: normalizeMatrix(inh.matrix), source: inh.source_folder };
          } catch { /* folder may have no policies */ }
        })
      );

      setPolicies(newPolicies);
      setInherited(newInherited);
    } catch (e) {
      notify(tm('notifications.loadFailed'), 'error');
    } finally {
      setLoading(false);
    }
  }, [groupId, folderId]);

  useEffect(() => { fetchData(); }, [fetchData]);

  // --- Tree helpers ---------------------------------------------------------

  const childrenByParent = useMemo(() => {
    const map = {};
    folders.forEach(f => {
      const key = f.parent_id ?? null;
      if (!map[key]) map[key] = [];
      map[key].push(f);
    });
    return map;
  }, [folders]);

  const getDescendantIds = useCallback((fId) => {
    const out = [];
    const stack = [ ...(childrenByParent[fId] || []) ];
    while (stack.length) {
      const f = stack.pop();
      out.push(f.id);
      (childrenByParent[f.id] || []).forEach(c => stack.push(c));
    }
    return out;
  }, [childrenByParent]);

  const toggleExpand = (fId) => {
    setExpanded(prev => ({ ...prev, [fId]: !prev[fId] }));
  };

  const expandAll = () => {
    const all = {};
    folders.forEach(f => { all[f.id] = true; });
    setExpanded(all);
  };

  const collapseAll = () => setExpanded({});

  const handleToggle = (fId, key) => {
    if (readOnly) return;
    setPolicies(prev => {
      const current = prev[fId] || normalizeMatrix();
      let updatedForFolder;
      // If setting explicit_deny, clear all positive perms
      if (key === 'explicit_deny') {
        updatedForFolder = !current.explicit_deny
          ? { read: false, modify: false, create: false, delete: false, replicate: false, manage: false, explicit_deny: true }
          : { ...current, explicit_deny: false };
      } else {
        updatedForFolder = { ...current, [key]: !current[key], explicit_deny: false };
      }

      const next = { ...prev, [fId]: updatedForFolder };

      // Cascade the same matrix onto every currently-loaded descendant so bulk
      // edits are fast. Descendants remain individually editable/overridable.
      if (!search) {
        getDescendantIds(fId).forEach(descId => {
          next[descId] = { ...updatedForFolder };
        });
      }

      return next;
    });
  };

  const handleSave = async (fId) => {
    setSaving(fId);
    const matrix = policies[fId] || normalizeMatrix();
    const cascade = !!cascadeOnSave[fId];
    try {
      const data = await apiFetch(`/admin/folders/${fId}/folder_policies.json`, {
        method: 'POST',
        body: JSON.stringify({
          group_id: groupId,
          cascade,
          policy: {
            read_access:      matrix.read,
            modify_access:    matrix.modify,
            create_access:    matrix.create,
            delete_access:    matrix.delete,
            replicate_access: matrix.replicate,
            manage_access:    matrix.manage,
            explicit_deny:    matrix.explicit_deny,
          }
        })
      });
      if (data.success) {
        notify(cascade ? tm('notifications.savedWithCascade') : tm('notifications.saved'), 'success');
      } else {
        notify(tm('notifications.saveFailed', { errors: data.errors?.join(', ') }), 'error');
      }
    } catch {
      notify(tm('notifications.networkError'), 'error');
    } finally {
      setSaving(null);
    }
  };

  const handleRemovePolicy = async (fId) => {
    try {
      await apiFetch(`/admin/folders/${fId}/folder_policies/${groupId}.json`, { method: 'DELETE' });
      notify(tm('notifications.removed'), 'info');
      setPolicies(prev => { const n = { ...prev }; delete n[fId]; return n; });
    } catch {
      notify(tm('notifications.removeFailed'), 'error');
    }
  };

  if (loading) return (
    <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
      <CircularProgress />
    </Box>
  );

  const matchesSearch = (f) =>
    !search || f.name?.toLowerCase().includes(search.toLowerCase()) ||
    f.path?.toLowerCase().includes(search.toLowerCase());

  // When searching, show a flat list of every match (regardless of tree
  // position). Otherwise, show only root folders plus any folder whose
  // ancestor chain is fully expanded — this is what keeps the screen light
  // for large folder trees.
  let visibleFolders;
  let depthById = {};
  if (search) {
    visibleFolders = folders.filter(matchesSearch);
  } else {
    visibleFolders = [];
    const walk = (parentKey, depth) => {
      (childrenByParent[parentKey] || []).forEach(f => {
        visibleFolders.push(f);
        depthById[f.id] = depth;
        if (expanded[f.id]) walk(f.id, depth + 1);
      });
    };
    walk(null, 0);
  }

  return (
    <Box>
      <Stack direction="row" sx={{ alignItems: 'center', justifyContent: 'space-between', mb: 2, flexWrap: 'wrap', gap: 1 }}>
        <Typography variant="subtitle2" color="text.secondary">
          {tm('title')} — {readOnly ? tm('subtitleView') : tm('subtitleEdit')}
        </Typography>
        <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
          {!search && (
            <>
              <Tooltip title={tm('expandAll')}>
                <IconButton size="small" onClick={expandAll} data-testid="acl-expand-all">
                  <UnfoldMoreOutlined fontSize="small" />
                </IconButton>
              </Tooltip>
              <Tooltip title={tm('collapseAll')}>
                <IconButton size="small" onClick={collapseAll} data-testid="acl-collapse-all">
                  <UnfoldLessOutlined fontSize="small" />
                </IconButton>
              </Tooltip>
            </>
          )}
          <TextField
            size="small" placeholder={tm('filterPlaceholder')}
            value={search} onChange={e => setSearch(e.target.value)} slotProps={{input: { startAdornment: <InputAdornment position="start"><SearchOutlined fontSize="small" /></InputAdornment> } }}
            sx={{ width: 220 }}
          />
        </Stack>
      </Stack>

      {!isAdmin && !readOnly && (
        <Alert severity="warning" sx={{ mb: 2, borderRadius: 2 }}>
          {tm('adminOnlyWarning')}
        </Alert>
      )}

      {!readOnly && isAdmin && (
        <Alert severity="info" variant="outlined" sx={{ mb: 2, borderRadius: 2 }} icon={false}>
          {tm('cascadeHint')}
        </Alert>
      )}

      <Box sx={{ overflowX: 'auto', maxHeight: 520, overflowY: 'auto', border: '1px solid #edf1f7', borderRadius: 2 }}>
        <Table size="small" stickyHeader>
          <TableHead>
            <TableRow>
              <TableCell sx={{ fontWeight: 700, minWidth: 220 }}>{tm('path')}</TableCell>
              {PERMISSION_COLS.map(col => (
                <TableCell key={col.key} align="center" sx={{ fontWeight: 700, minWidth: 80 }}>
                  <Tooltip title={tm(col.tipKey)} placement="top">
                    <span>{tm(col.labelKey)}</span>
                  </Tooltip>
                </TableCell>
              ))}
              <TableCell align="center" sx={{ fontWeight: 700, minWidth: 100, color: 'error.main' }}>
                <Tooltip title={tm('tooltips.denyAll')}>
                  <span>{tm('denyAll')}</span>
                </Tooltip>
              </TableCell>
              {!readOnly && isAdmin && <TableCell align="center" sx={{ minWidth: 140 }}>{tm('actions')}</TableCell>}
            </TableRow>
          </TableHead>
          <TableBody>
            {visibleFolders.map(folder => {
              const matrix = policies[folder.id] || normalizeMatrix();
              const inh = inherited[folder.id];
              const hasExplicit = !!policies[folder.id];
              const depth = search ? 0 : (depthById[folder.id] ?? 0);
              const childCount = (childrenByParent[folder.id] || []).length;
              const isExpanded = !!expanded[folder.id];

              return (
                <TableRow
                  key={folder.id}
                  hover
                  data-testid={`acl-row-${folder.id}`}
                  sx={{
                    opacity: hasExplicit || inh ? 1 : 0.45,
                    bgcolor: hasExplicit ? 'white' : inh ? '#fafffe' : 'transparent',
                    '&:hover': { bgcolor: '#f5f8ff' },
                  }}
                >
                  {/* Folder name */}
                  <TableCell>
                    <Stack direction="row" sx={{ alignItems: 'center' }} spacing={0.5} style={{ paddingLeft: `${depth * 20}px` }}>
                      {childCount > 0 ? (
                        <IconButton
                          size="small"
                          onClick={() => toggleExpand(folder.id)}
                          data-testid={`acl-toggle-${folder.id}`}
                          sx={{ p: 0.25 }}
                        >
                          {isExpanded ? <ExpandMoreOutlined fontSize="small" /> : <ChevronRightOutlined fontSize="small" />}
                        </IconButton>
                      ) : (
                        <Box sx={{ width: 28 }} />
                      )}
                      {hasExplicit
                        ? <FolderOpenOutlined fontSize="small" color="primary" />
                        : <FolderOutlined fontSize="small" color="disabled" />
                      }
                      <Typography variant="body2" noWrap sx={{ maxWidth: 180, fontWeight: hasExplicit ? 600 : 400 }}>
                        {folder.path || folder.name}
                      </Typography>
                      {childCount > 0 && (
                        <Chip
                          label={tm('childCount', { count: childCount })}
                          size="small" variant="outlined"
                          sx={{ fontSize: '0.65rem', height: 18 }}
                        />
                      )}
                      {inh && !hasExplicit && (
                        <Tooltip title={tm('inheritedFrom', { source: inh.source })}>
                          <Chip label={tm('inherited')} size="small" variant="outlined"
                            sx={{ fontSize: '0.65rem', height: 18 }} />
                        </Tooltip>
                      )}
                    </Stack>
                  </TableCell>

                  {/* Permission checkboxes */}
                  {PERMISSION_COLS.map(col => {
                    const effective = hasExplicit ? matrix[col.key] : (inh?.matrix[col.key] ?? false);
                    return (
                      <TableCell key={col.key} align="center" padding="checkbox">
                        <Checkbox
                          size="small"
                          checked={effective}
                          disabled={readOnly || !isAdmin || (!hasExplicit && !!inh) || matrix.explicit_deny}
                          onChange={() => handleToggle(folder.id, col.key)}
                          sx={{ color: 'primary.main' }}
                        />
                        {hasExplicit && matrix.explicit_deny && col.key !== 'explicit_deny' && (
                          <LockOutlined sx={{ fontSize: 12, color: 'error.light', verticalAlign: 'middle' }} />
                        )}
                      </TableCell>
                    );
                  })}

                  {/* Explicit deny */}
                  <TableCell align="center" padding="checkbox">
                    <Checkbox
                      size="small"
                      checked={hasExplicit ? matrix.explicit_deny : false}
                      disabled={readOnly || !isAdmin || (!hasExplicit && !!inh)}
                      onChange={() => handleToggle(folder.id, 'explicit_deny')}
                      sx={{ color: 'error.main' }}
                    />
                  </TableCell>

                  {/* Save / Remove actions */}
                  {!readOnly && isAdmin && (
                    <TableCell align="center">
                      <Stack direction="row" spacing={0.5} sx={{ justifyContent: 'center', alignItems: 'center' }}>
                        {childCount > 0 && (
                          <Tooltip title={tm('cascadeTooltip')}>
                            <FormControlLabel
                              sx={{ mr: 0 }}
                              control={
                                <Switch
                                  size="small"
                                  checked={!!cascadeOnSave[folder.id]}
                                  onChange={() => setCascadeOnSave(prev => ({ ...prev, [folder.id]: !prev[folder.id] }))}
                                  data-testid={`acl-cascade-switch-${folder.id}`}
                                />
                              }
                              label={<Typography variant="caption" sx={{ fontSize: '0.65rem' }}>{tm('cascadeLabel')}</Typography>}
                            />
                          </Tooltip>
                        )}
                        <Tooltip title={cascadeOnSave[folder.id] ? tm('saveWithCascadeTooltip') : tm('saveTooltip')}>
                          <span>
                            <IconButton size="small" color="primary" onClick={() => handleSave(folder.id)}
                              disabled={saving === folder.id} data-testid={`acl-save-${folder.id}`}>
                              {saving === folder.id
                                ? <CircularProgress size={14} />
                                : <SaveOutlined fontSize="small" />
                              }
                            </IconButton>
                          </span>
                        </Tooltip>
                        {hasExplicit && (
                          <Tooltip title={tm('removeTooltip')}>
                            <IconButton size="small" color="error" onClick={() => handleRemovePolicy(folder.id)}>
                              ✕
                            </IconButton>
                          </Tooltip>
                        )}
                      </Stack>
                    </TableCell>
                  )}
                </TableRow>
              );
            })}
            {visibleFolders.length === 0 && (
              <TableRow>
                <TableCell colSpan={9}>
                  <Typography variant="body2" color="text.secondary" align="center" sx={{ py: 4 }}>
                    {tm('noResults')}
                  </Typography>
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </Box>
    </Box>
  );
}
