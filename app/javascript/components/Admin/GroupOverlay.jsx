/**
 * GroupOverlay — full-width right Drawer for managing a group.
 *
 * Tabs:
 *  0 – Properties  : name, description, slug
 *  1 – Members     : user members (with search autocomplete) + child sub-groups
 *  2 – Permissions : folder ACL matrix
 *  3 – Groups      : parent group(s) this group is nested inside
 *
 * Security:
 *  - 'everyone'          : fully read-only
 *  - 'administrators'    : admins + super-admins can add/remove members
 *                          (makes target user an admin); no self-promotion
 *  - 'super-admins'      : only super-admins; no self-promotion
 *  - System groups       : cannot be deleted by anyone
 *
 * Props:
 *  open, group, onClose, onGroupUpdated
 *  allGroups           - all groups (for sub-group picker + Groups tab)
 *  isAdmin, isSuperAdmin
 *  currentUserId       - logged-in user's ID (for self-promotion guard)
 *  onCreateSubGroup    - (parentId) => void — opens the create dialog in parent
 */
import React, { useState, useEffect } from 'react';
import {
  Drawer, Box, Typography, Button, Chip, Stack, IconButton,
  Divider, Alert, Tab, Tabs, List, ListItem, ListItemText, ListItemAvatar,
  ListItemSecondaryAction, Avatar, Tooltip, CircularProgress, Dialog,
  DialogTitle, DialogContent, DialogActions, TextField,
} from '@mui/material';
import {
  Close, DeleteOutlined, Shield, LockOutlined,
  GroupWorkOutlined, SubdirectoryArrowRight, AddOutlined, CreateNewFolderOutlined,
} from '@mui/icons-material';
import { apiFetch, groupPermissions, isSystemGroup, SYSTEM_SLUGS, isSelfPromotion } from '../../utils/adminUtils';
import AclMatrix    from './AclMatrix';
import UserSearch   from './UserSearch';
import GroupSearch  from './GroupSearch';
import { useNotify } from '../../context/NotificationContext';

export default function GroupOverlay({
  open, group, onClose, onGroupUpdated,
  allGroups, isAdmin, isSuperAdmin, currentUserId,
  onCreateSubGroup,
}) {
  const notify = useNotify();
  const [tab, setTab] = useState(0);

  // Properties
  const [form, setForm]     = useState({ name: '', description: '' });
  const [saving, setSaving] = useState(false);

  // Members
  const [members, setMembers]             = useState([]);
  const [childGroups, setChildGroups]     = useState([]);
  const [membersLoading, setMembersLoading] = useState(false);

  // Delete confirm
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);

  useEffect(() => {
    if (open && group) {
      setTab(0);
      setForm({ name: group.name || '', description: group.description || '' });
    }
  }, [open, group?.id]);

  useEffect(() => {
    if (open && group?.id && tab === 1) fetchMembers();
  }, [tab, open, group?.id]);

  const fetchMembers = async () => {
    setMembersLoading(true);
    try {
      const data = await apiFetch(`/admin/user_groups/${group.id}.json`);
      setMembers(data.group?.members || []);
      setChildGroups(data.group?.child_groups || []);
    } finally { setMembersLoading(false); }
  };

  const handleSaveProperties = async () => {
    setSaving(true);
    try {
      const data = await apiFetch(`/admin/user_groups/${group.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ user_group: form })
      });
      if (data.success) { notify('Group updated.', 'success'); onGroupUpdated?.(); }
      else notify(data.errors?.join(', ') || 'Save failed.', 'error');
    } finally { setSaving(false); }
  };

  // Add user member via search autocomplete
  const handleAddUserMember = async (user) => {
    if (isSelfPromotion(group, currentUserId, user.id)) {
      notify('You cannot add yourself to a privileged group.', 'error');
      return;
    }
    const data = await apiFetch(`/admin/user_groups/${group.id}/add_member`, {
      method: 'POST',
      body: JSON.stringify({ user_id: user.id })
    });
    if (data.success) { notify(data.message, 'success'); fetchMembers(); onGroupUpdated?.(); }
    else notify(data.error || 'Failed to add member.', 'error');
  };

  const handleRemoveUserMember = async (userId) => {
    const data = await apiFetch(`/admin/user_groups/${group.id}/remove_member`, {
      method: 'DELETE',
      body: JSON.stringify({ user_id: userId })
    });
    if (data.success) { notify(data.message, 'success'); fetchMembers(); onGroupUpdated?.(); }
    else notify(data.error || 'Failed.', 'error');
  };

  // Add a child group (group-in-group)
  const handleAddSubGroup = async (childGroup) => {
    if (childGroup.id === group.id) {
      notify('A group cannot be nested inside itself.', 'error');
      return;
    }
    const data = await apiFetch(`/admin/user_groups/${group.id}/add_group_member`, {
      method: 'POST',
      body: JSON.stringify({ child_group_id: childGroup.id })
    });
    if (data.success) { notify(data.message, 'success'); fetchMembers(); onGroupUpdated?.(); }
    else notify(data.error || 'Failed.', 'error');
  };

  const handleRemoveSubGroup = async (childGroupId) => {
    const data = await apiFetch(`/admin/user_groups/${group.id}/remove_group_member`, {
      method: 'DELETE',
      body: JSON.stringify({ child_group_id: childGroupId })
    });
    if (data.success) { notify(data.message, 'success'); fetchMembers(); onGroupUpdated?.(); }
    else notify(data.error || 'Failed.', 'error');
  };

  const handleDelete = async () => {
    const data = await apiFetch(`/admin/user_groups/${group.id}`, { method: 'DELETE' });
    if (data.success) {
      notify('Group deleted.', 'success');
      setDeleteDialogOpen(false);
      onClose();
      onGroupUpdated?.();
    } else {
      notify(data.error || 'Delete failed.', 'error');
    }
  };

  if (!group) return null;

  const perms        = groupPermissions(group, isAdmin, isSuperAdmin);
  const isEveryone   = group.slug === SYSTEM_SLUGS.EVERYONE;
  const isSystemGrp  = isSystemGroup(group);

  // IDs already in this group (to exclude from search results)
  const existingMemberIds  = members.map(u => u.id);
  const existingChildIds   = childGroups.map(g => g.id);

  // Groups that can be chosen as sub-groups (exclude self, ancestors, and system)
  const availableForNesting = (allGroups || []).filter(g =>
    g.id !== group.id &&
    !existingChildIds.includes(g.id) &&
    g.slug !== SYSTEM_SLUGS.EVERYONE
  );

  return (
    <>
      <Drawer
        anchor="right" open={open} onClose={onClose}
        PaperProps={{ sx: { width: { xs: '100vw', sm: '80vw', md: 700 }, display: 'flex', flexDirection: 'column' } }}
      >
        {/* ── Header ── */}
        <Box sx={{ p: 2.5, pb: 0, borderBottom: '1px solid', borderColor: 'divider', bgcolor: '#fafafa' }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 1.5 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
              <GroupWorkOutlined color="primary" />
              <Box>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <Typography variant="h6" sx={{ fontWeight: 700, lineHeight: 1.2 }}>{group.name}</Typography>
                  {isSystemGrp && (
                    <Chip label="system" size="small" icon={<Shield sx={{ fontSize: 12 }} />}
                      color={group.slug === SYSTEM_SLUGS.SUPER_ADMINS ? 'error' : 'warning'}
                      variant="filled" sx={{ height: 18, fontSize: '0.65rem' }} />
                  )}
                </Box>
                <Typography variant="caption" color="text.secondary">
                  {group.description || 'No description.'} · {group.member_count} member{group.member_count !== 1 ? 's' : ''}
                </Typography>
              </Box>
            </Box>

            <Box sx={{ display: 'flex', gap: 0.5, alignItems: 'center' }}>
              {/* Create sub-group button */}
              {!isEveryone && (
                <Tooltip title="Create a sub-group under this group">
                  <IconButton size="small" color="primary" onClick={() => onCreateSubGroup?.(group.id)}>
                    <CreateNewFolderOutlined fontSize="small" />
                  </IconButton>
                </Tooltip>
              )}
              {perms.canDelete ? (
                <Tooltip title="Delete group">
                  <IconButton size="small" color="error" onClick={() => setDeleteDialogOpen(true)}>
                    <DeleteOutlined fontSize="small" />
                  </IconButton>
                </Tooltip>
              ) : isSystemGrp ? (
                <Tooltip title="System groups cannot be deleted">
                  <LockOutlined sx={{ fontSize: 18, color: 'text.disabled' }} />
                </Tooltip>
              ) : null}
              <IconButton size="small" onClick={onClose}><Close fontSize="small" /></IconButton>
            </Box>
          </Box>

          <Tabs value={tab} onChange={(_, v) => setTab(v)} variant="scrollable"
            sx={{ minHeight: 38, '& .MuiTab-root': { minHeight: 38, fontSize: '0.75rem', py: 0 } }}>
            <Tab label="Properties" />
            <Tab label={`Members (${group.member_count})`} />
            <Tab label="Permissions" />
            <Tab label="Groups" />
          </Tabs>
        </Box>

        {/* ── Body ── */}
        <Box sx={{ flexGrow: 1, overflowY: 'auto', px: 2.5, py: 2 }}>

          {/* Tab 0: Properties */}
          {tab === 0 && (
            <Stack spacing={2.5}>
              {isEveryone && (
                <Alert severity="warning" sx={{ borderRadius: 2 }}>
                  The <strong>everyone</strong> group is a system group. It cannot be modified or deleted.
                  All users are automatic members.
                </Alert>
              )}
              {!isEveryone && isSystemGrp && !isSuperAdmin && group.slug !== SYSTEM_SLUGS.ADMINS && (
                <Alert severity="info" sx={{ borderRadius: 2 }}>
                  Only <strong>super-administrators</strong> can modify this group's name.
                </Alert>
              )}
              {group.slug === SYSTEM_SLUGS.ADMINS && (
                <Alert severity="info" sx={{ borderRadius: 2 }}>
                  <strong>administrators</strong> — members have full access.
                  Admins and super-admins can manage membership.
                  <br />No one can delete this group.
                </Alert>
              )}
              <TextField label="Group Name" fullWidth size="small" value={form.name}
                onChange={e => setForm({ ...form, name: e.target.value })}
                disabled={isEveryone || (isSystemGrp && !isSuperAdmin)} />
              <TextField label="Description" fullWidth size="small" multiline rows={3}
                value={form.description}
                onChange={e => setForm({ ...form, description: e.target.value })}
                disabled={isEveryone} />
              {group.slug && (
                <Box sx={{ p: 1.5, bgcolor: '#f8f9fa', borderRadius: 2, border: '1px solid', borderColor: 'divider' }}>
                  <Typography variant="caption" color="text.secondary">System slug (immutable)</Typography>
                  <Typography variant="body2" sx={{ fontFamily: 'monospace', fontWeight: 600 }}>{group.slug}</Typography>
                </Box>
              )}
            </Stack>
          )}

          {/* Tab 1: Members */}
          {tab === 1 && (
            <Stack spacing={2.5}>
              {/* ── Section A: User Members ── */}
              <Box>
                <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5 }}>
                  User Members
                </Typography>

                {perms.canAddMembers ? (
                  <Stack direction="row" gap={1} sx={{ mb: 2 }}>
                    <UserSearch
                      placeholder="Search by name or email to add…"
                      excludeIds={existingMemberIds}
                      onSelect={handleAddUserMember}
                    />
                  </Stack>
                ) : (
                  <Alert severity="info" sx={{ borderRadius: 2, mb: 2 }}>
                    {isEveryone
                      ? 'All users are automatically members of this group.'
                      : 'Only super-administrators can add members to this group.'}
                  </Alert>
                )}

                {membersLoading ? (
                  <CircularProgress size={22} sx={{ display: 'block', mx: 'auto' }} />
                ) : members.length === 0 ? (
                  <Typography variant="body2" color="text.secondary">No direct user members.</Typography>
                ) : (
                  <List dense sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 2 }}>
                    {members.map((u, idx) => (
                      <React.Fragment key={u.id}>
                        {idx > 0 && <Divider />}
                        <ListItem>
                          <ListItemAvatar>
                            <Avatar src={u.avatar_url}
                              sx={{ width: 32, height: 32, fontSize: '0.75rem', bgcolor: 'primary.main' }}>
                              {u.display_name?.[0]?.toUpperCase()}
                            </Avatar>
                          </ListItemAvatar>
                          <ListItemText
                            primary={u.display_name} secondary={u.email}
                            primaryTypographyProps={{ variant: 'body2', fontWeight: 600 }}
                            secondaryTypographyProps={{ variant: 'caption' }}
                          />
                          {perms.canRemoveMembers && String(u.id) !== String(currentUserId) && (
                            <ListItemSecondaryAction>
                              <Tooltip title="Remove from group">
                                <IconButton size="small" color="error" onClick={() => handleRemoveUserMember(u.id)}>
                                  <DeleteOutlined fontSize="small" />
                                </IconButton>
                              </Tooltip>
                            </ListItemSecondaryAction>
                          )}
                          {String(u.id) === String(currentUserId) && (
                            <ListItemSecondaryAction>
                              <Tooltip title="You cannot remove yourself">
                                <LockOutlined sx={{ fontSize: 16, color: 'text.disabled' }} />
                              </Tooltip>
                            </ListItemSecondaryAction>
                          )}
                        </ListItem>
                      </React.Fragment>
                    ))}
                  </List>
                )}
              </Box>

              <Divider />

              {/* ── Section B: Sub-Groups (group-in-group) ── */}
              <Box>
                <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1.5 }}>
                  <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
                    Sub-Groups (nested groups)
                  </Typography>
                  {!isEveryone && (
                    <Tooltip title="Create a new sub-group under this group">
                      <Button size="small" variant="outlined" startIcon={<CreateNewFolderOutlined />}
                        onClick={() => onCreateSubGroup?.(group.id)}>
                        Create Sub-Group
                      </Button>
                    </Tooltip>
                  )}
                </Stack>

                {/* Add existing group as child */}
                {!isEveryone && isAdmin && availableForNesting.length > 0 && (
                  <Stack direction="row" gap={1} sx={{ mb: 2 }}>
                    <GroupSearch
                      groups={availableForNesting}
                      placeholder="Add existing group as sub-group…"
                      excludeIds={[group.id, ...existingChildIds]}
                      onSelect={handleAddSubGroup}
                    />
                  </Stack>
                )}

                {membersLoading ? null : childGroups.length === 0 ? (
                  <Typography variant="body2" color="text.secondary">
                    No sub-groups nested here. Use the search above or "Create Sub-Group" to add one.
                  </Typography>
                ) : (
                  <List dense sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 2 }}>
                    {childGroups.map((cg, idx) => (
                      <React.Fragment key={cg.id}>
                        {idx > 0 && <Divider />}
                        <ListItem>
                          <ListItemAvatar>
                            <SubdirectoryArrowRight fontSize="small" color="primary" />
                          </ListItemAvatar>
                          <ListItemText
                            primary={cg.name}
                            secondary={cg.slug || 'custom group'}
                            primaryTypographyProps={{ variant: 'body2', fontWeight: 600 }}
                            secondaryTypographyProps={{ variant: 'caption' }}
                          />
                          {isAdmin && (
                            <ListItemSecondaryAction>
                              <Tooltip title="Remove from this group">
                                <IconButton size="small" color="error"
                                  onClick={() => handleRemoveSubGroup(cg.id)}>
                                  <DeleteOutlined fontSize="small" />
                                </IconButton>
                              </Tooltip>
                            </ListItemSecondaryAction>
                          )}
                        </ListItem>
                      </React.Fragment>
                    ))}
                  </List>
                )}
              </Box>
            </Stack>
          )}

          {/* Tab 2: Permissions (ACL) */}
          {tab === 2 && (
            <AclMatrix
              groupId={group.id}
              readOnly={!isAdmin || isEveryone}
              isAdmin={isAdmin}
            />
          )}

          {/* Tab 3: Groups (parent groups) */}
          {tab === 3 && (
            <Stack spacing={2}>
              <Typography variant="body2" color="text.secondary">
                This group is nested inside the following parent groups.
                Permissions and membership cascade from parent to child.
              </Typography>
              {group.parent_id ? (
                <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
                  {(allGroups || [])
                    .filter(g => g.id === group.parent_id)
                    .map(g => (
                      <Chip key={g.id} label={g.name} size="small" variant="outlined"
                        icon={isSystemGroup(g) ? <Shield sx={{ fontSize: 12 }} /> : undefined}
                        color={isSystemGroup(g) ? 'warning' : 'default'} />
                    ))
                  }
                </Box>
              ) : (
                <Alert severity="info" sx={{ borderRadius: 2 }}>
                  This is a root-level group with no parent.
                </Alert>
              )}
            </Stack>
          )}
        </Box>

        {/* ── Footer ── */}
        {tab === 0 && !isEveryone && perms.canEdit && (
          <Box sx={{ p: 2, borderTop: '1px solid', borderColor: 'divider', bgcolor: '#fafafa' }}>
            <Button variant="contained" onClick={handleSaveProperties}
              disabled={saving || !form.name.trim()} disableElevation>
              {saving ? 'Saving…' : 'Save Changes'}
            </Button>
          </Box>
        )}
      </Drawer>

      {/* Delete confirm */}
      <Dialog open={deleteDialogOpen} onClose={() => setDeleteDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ fontWeight: 700, color: 'error.main' }}>Delete Group</DialogTitle>
        <DialogContent>
          <Typography>
            Are you sure you want to delete <strong>{group.name}</strong>?
            All memberships and folder policies will be removed.
          </Typography>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setDeleteDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" color="error" onClick={handleDelete} disableElevation>
            Delete Group
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
}

