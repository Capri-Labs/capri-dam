/**
 * AclMatrix — reusable folder-level permission matrix.
 *
 * Displays all explicit + inherited folder policies for a given entity
 * (a group or a user's effective permissions).  Supports edit mode that
 * saves changes back via the folder_policies API.
 *
 * Columns: Read | Modify | Create | Delete | Replicate | Manage | Explicit Deny
 */
import React, { useState, useEffect, useCallback } from 'react';
import {
  Box, Typography, Table, TableHead, TableBody, TableRow, TableCell,
  Checkbox, Chip, Tooltip, IconButton, CircularProgress, Alert,
  Button, Stack, TextField, InputAdornment,
} from '@mui/material';
import {
  SaveOutlined, SearchOutlined, LockOutlined, InfoOutlined,
  FolderOpenOutlined, FolderOutlined,
} from '@mui/icons-material';
import { apiFetch } from '../../utils/adminUtils';
import { useNotify } from '../../context/NotificationContext';

const PERMISSION_COLS = [
  { key: 'read',      label: 'Read',      tip: 'View assets and child folders' },
  { key: 'modify',    label: 'Modify',    tip: 'Edit existing asset metadata / rename folders' },
  { key: 'create',    label: 'Create',    tip: 'Upload assets or create sub-folders' },
  { key: 'delete',    label: 'Delete',    tip: 'Delete assets and folders' },
  { key: 'replicate', label: 'Replicate', tip: 'Push assets to CDN' },
  { key: 'manage',    label: 'Manage',    tip: 'Admin-level folder configuration' },
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
  const notify = useNotify();
  const [folders, setFolders] = useState([]);
  const [policies, setPolicies] = useState({});  // folderId → matrix
  const [inherited, setInherited] = useState({}); // folderId → { matrix, source }
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(null);
  const [search, setSearch] = useState('');
  const [expanded, setExpanded] = useState({});

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
      notify('Failed to load folder policies.', 'error');
    } finally {
      setLoading(false);
    }
  }, [groupId, folderId]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const handleToggle = (fId, key) => {
    if (readOnly) return;
    setPolicies(prev => {
      const current = prev[fId] || normalizeMatrix();
      // If setting explicit_deny, clear all positive perms
      if (key === 'explicit_deny') {
        return {
          ...prev,
          [fId]: key === 'explicit_deny' && !current.explicit_deny
            ? { read: false, modify: false, create: false, delete: false, replicate: false, manage: false, explicit_deny: true }
            : { ...current, explicit_deny: false }
        };
      }
      return { ...prev, [fId]: { ...current, [key]: !current[key], explicit_deny: false } };
    });
  };

  const handleSave = async (fId) => {
    setSaving(fId);
    const matrix = policies[fId] || normalizeMatrix();
    try {
      const data = await apiFetch(`/admin/folders/${fId}/folder_policies.json`, {
        method: 'POST',
        body: JSON.stringify({
          group_id: groupId,
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
        notify('Permissions saved.', 'success');
      } else {
        notify(`Save failed: ${data.errors?.join(', ')}`, 'error');
      }
    } catch {
      notify('Network error saving permissions.', 'error');
    } finally {
      setSaving(null);
    }
  };

  const handleRemovePolicy = async (fId) => {
    try {
      await apiFetch(`/admin/folders/${fId}/folder_policies/${groupId}.json`, { method: 'DELETE' });
      notify('Policy removed. Folder reverts to inherited rules.', 'info');
      setPolicies(prev => { const n = { ...prev }; delete n[fId]; return n; });
    } catch {
      notify('Failed to remove policy.', 'error');
    }
  };

  if (loading) return (
    <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
      <CircularProgress />
    </Box>
  );

  const visibleFolders = folders.filter(f =>
    !search || f.name?.toLowerCase().includes(search.toLowerCase()) ||
    f.path?.toLowerCase().includes(search.toLowerCase())
  );

  const hasPolicyOrInherited = (fId) => policies[fId] || inherited[fId];

  const activeFolders = visibleFolders.filter(f =>
    expanded[f.parent_id] !== false || !f.parent_id
  );

  return (
    <Box>
      <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 2 }}>
        <Typography variant="subtitle2" color="text.secondary">
          Folder-level ACL — {readOnly ? 'View only' : 'Click checkboxes to edit, then Save'}
        </Typography>
        <TextField
          size="small" placeholder="Filter folders…"
          value={search} onChange={e => setSearch(e.target.value)}
          InputProps={{ startAdornment: <InputAdornment position="start"><SearchOutlined fontSize="small" /></InputAdornment> }}
          sx={{ width: 220 }}
        />
      </Stack>

      {!isAdmin && !readOnly && (
        <Alert severity="warning" sx={{ mb: 2, borderRadius: 2 }}>
          Only administrators can modify folder permissions.
        </Alert>
      )}

      <Box sx={{ overflowX: 'auto' }}>
        <Table size="small" stickyHeader>
          <TableHead>
            <TableRow>
              <TableCell sx={{ fontWeight: 700, minWidth: 200 }}>Path</TableCell>
              {PERMISSION_COLS.map(col => (
                <TableCell key={col.key} align="center" sx={{ fontWeight: 700, minWidth: 80 }}>
                  <Tooltip title={col.tip} placement="top">
                    <span>{col.label}</span>
                  </Tooltip>
                </TableCell>
              ))}
              <TableCell align="center" sx={{ fontWeight: 700, minWidth: 100, color: 'error.main' }}>
                <Tooltip title="Deny all — overrides every positive grant for this group on this folder">
                  <span>Deny All</span>
                </Tooltip>
              </TableCell>
              {!readOnly && isAdmin && <TableCell align="center" sx={{ minWidth: 80 }}>Actions</TableCell>}
            </TableRow>
          </TableHead>
          <TableBody>
            {visibleFolders.map(folder => {
              const matrix = policies[folder.id] || normalizeMatrix();
              const inh = inherited[folder.id];
              const hasExplicit = !!policies[folder.id];
              const depth = (folder.path?.split('/').length - 2) || 0;

              return (
                <TableRow
                  key={folder.id}
                  hover
                  sx={{
                    opacity: hasExplicit || inh ? 1 : 0.45,
                    bgcolor: hasExplicit ? 'white' : inh ? '#fafffe' : 'transparent',
                    '&:hover': { bgcolor: '#f5f8ff' },
                  }}
                >
                  {/* Folder name */}
                  <TableCell>
                    <Stack direction="row" alignItems="center" spacing={0.5} sx={{ pl: depth * 2 }}>
                      {hasExplicit
                        ? <FolderOpenOutlined fontSize="small" color="primary" />
                        : <FolderOutlined fontSize="small" color="disabled" />
                      }
                      <Typography variant="body2" noWrap sx={{ maxWidth: 180, fontWeight: hasExplicit ? 600 : 400 }}>
                        {folder.path || folder.name}
                      </Typography>
                      {inh && !hasExplicit && (
                        <Tooltip title={`Inherited from: ${inh.source}`}>
                          <Chip label="inherited" size="small" variant="outlined"
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
                      <Stack direction="row" spacing={0.5} justifyContent="center">
                        <Tooltip title="Save explicit rule for this folder">
                          <span>
                            <IconButton size="small" color="primary" onClick={() => handleSave(folder.id)}
                              disabled={saving === folder.id}>
                              {saving === folder.id
                                ? <CircularProgress size={14} />
                                : <SaveOutlined fontSize="small" />
                              }
                            </IconButton>
                          </span>
                        </Tooltip>
                        {hasExplicit && (
                          <Tooltip title="Remove explicit rule (reverts to inherited)">
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
                    No folders match your filter.
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

