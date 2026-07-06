/**
 * UserDrawer — full-featured right-side panel for a DAM user.
 *
 * Tabs: Properties | Groups | Permissions | Impersonators | Preferences
 *
 * Security:
 *  - Only super-admins can toggle the System Administrator switch.
 *  - SSO users have name/email fields locked.
 *  - Super-admin accounts cannot be set as impersonation targets.
 */
import React, { useState, useEffect } from 'react';
import {
  Drawer, Box, Typography, Button, TextField, Chip, Stack, IconButton,
  Divider, Alert, Avatar, Switch, FormControlLabel, Tab, Tabs,
  List, ListItem, ListItemText, ListItemAvatar, ListItemSecondaryAction,
  MenuItem, Select, FormControl, InputLabel, Tooltip, CircularProgress,
  Dialog, DialogTitle, DialogContent, DialogActions,
} from '@mui/material';import {
  Close, Block, CheckCircleOutlined, GroupAdd, Shield,
  PersonOutlined, LockOutlined, PublicOutlined,
  DeleteOutlined, AddOutlined, SecurityOutlined, SupervisedUserCircle,
} from '@mui/icons-material';
import { apiFetch, formatDate, SYSTEM_SLUGS, groupPermissions } from '../../utils/adminUtils';
import AclMatrix from './AclMatrix';
import UserSearch from './UserSearch';
import GroupSearch from './GroupSearch';
import { useNotify } from '../../context/NotificationContext';

const SUPPORTED_LANGS = [
  { value: 'en', label: 'English' }, { value: 'de', label: 'Deutsch' },
  { value: 'fr', label: 'Français' }, { value: 'es', label: 'Español' },
  { value: 'pt', label: 'Português' }, { value: 'nl', label: 'Nederlands' },
  { value: 'ja', label: '日本語' }, { value: 'zh', label: '中文' },
  { value: 'ko', label: '한국어' },
];

function TabPanel({ children, value, index }) {
  return value === index ? <Box sx={{ pt: 2 }}>{children}</Box> : null;
}

export default function UserDrawer({
  open, user, editForm, setEditForm,
  onClose, onSave, onToggleStatus,
  allGroups, isAdmin, isSuperAdmin, currentUserId,
}) {
  const notify = useNotify();
  const [tab, setTab] = useState(0);
  // eslint-disable-next-line eqeqeq -- currentUserId arrives as a string dataset attr; user.id may be numeric.
  const isSelf = user && currentUserId != null && String(user.id) === String(currentUserId);

  const [impersonators, setImpersonators]               = useState([]);
  const [impersonatorsLoading, setImpersonatorsLoading] = useState(false);
  const [startingImpersonation, setStartingImpersonation] = useState(false);

  // Groups tab state
  const [groupsData, setGroupsData]         = useState({ groups: [], all_groups: [], total: 0 });
  const [groupsLoading, setGroupsLoading]   = useState(false);
  const [groupFilter, setGroupFilter]       = useState('');
  const [groupActionId, setGroupActionId]   = useState(null);
  // Permissions tab — selected group to view ACL for
  const [permGroupId, setPermGroupId]       = useState(null);

  const [prefs, setPrefs]           = useState({ language: 'en', receive_mention_emails: true, receive_workflow_emails: true });
  const [prefsLoading, setPrefsLoading] = useState(false);
  const [prefsSaving, setPrefsSaving]   = useState(false);

  const [pwdDialogOpen, setPwdDialogOpen] = useState(false);
  const [pwdForm, setPwdForm] = useState({ new_password: '', new_password_confirmation: '', force_change: false });
  const [pwdSaving, setPwdSaving] = useState(false);

  useEffect(() => { if (open) setTab(0); }, [open, user?.id]);

  // Fetch groups data for BOTH Groups tab (1) and Permissions tab (2)
  useEffect(() => { if ((tab === 1 || tab === 2) && user?.id) fetchGroups(); }, [tab, user?.id]);
  useEffect(() => { if (tab === 3 && user?.id) fetchImpersonators(); }, [tab, user?.id]);
  useEffect(() => { if (tab === 4 && user?.id) fetchPreferences();   }, [tab, user?.id]);

  // Auto-select first group when groups data loads (for Permissions tab)
  useEffect(() => {
    if (groupsData.groups.length > 0 && !permGroupId) {
      setPermGroupId(groupsData.groups[0].id);
    }
  }, [groupsData.groups]);

  const fetchImpersonators = async () => {
    setImpersonatorsLoading(true);
    try {
      const data = await apiFetch(`/admin/users/${user.id}/impersonators.json`);
      setImpersonators(data.impersonators || []);
    } finally { setImpersonatorsLoading(false); }
  };

  const fetchGroups = async () => {
    setGroupsLoading(true);
    try {
      const data = await apiFetch(`/admin/users/${user.id}/groups.json`);
      setGroupsData({
        groups:     data.groups     || [],
        all_groups: data.all_groups || [],
        total:      data.total      || 0,
      });
      // Reset permission group selection when groups reload
      setPermGroupId(null);
    } finally { setGroupsLoading(false); }
  };

  // Immediately adds user to a group; uses the inline /add_group endpoint
  const handleAddGroupInline = async (group) => {
    if (!group?.id) return;
    setGroupActionId(group.id);
    try {
      const res = await apiFetch(`/admin/users/${user.id}/add_group`, {
        method: 'POST', body: JSON.stringify({ group_id: group.id }),
      });
      if (res.success) {
        notify(`Added to ${group.name}.`, 'success');
        await fetchGroups();
      } else notify(res.error || res.errors?.join(', ') || 'Failed.', 'error');
    } finally { setGroupActionId(null); }
  };

  // Immediately removes user from a group
  const handleRemoveGroupInline = async (group) => {
    setGroupActionId(group.id);
    try {
      const res = await apiFetch(`/admin/users/${user.id}/remove_group/${group.id}`, { method: 'DELETE' });
      if (res.success) {
        notify(`Removed from ${group.name}.`, 'success');
        await fetchGroups();
      } else notify(res.error || 'Failed.', 'error');
    } finally { setGroupActionId(null); }
  };

  const fetchPreferences = async () => {
    setPrefsLoading(true);
    try {
      const data = await apiFetch(`/admin/users/${user.id}/preferences.json`);
      if (data.preferences) setPrefs(data.preferences);
    } finally { setPrefsLoading(false); }
  };

  // Called by UserSearch autocomplete with the selected user object
  const handleAddImpersonator = async (actor) => {
    if (!actor?.id) return;
    const res = await apiFetch(`/admin/users/${user.id}/impersonators`, {
      method: 'POST', body: JSON.stringify({ impersonator_id: actor.id }),
    });
    if (res.success) { notify(res.message, 'success'); fetchImpersonators(); }
    else notify(res.errors?.join(', ') || res.error || 'Failed.', 'error');
  };

  const handleRemoveImpersonator = async (impId) => {
    const res = await apiFetch(`/admin/users/${user.id}/impersonators/${impId}`, { method: 'DELETE' });
    if (res.success) { notify('Access revoked.', 'success'); fetchImpersonators(); }
  };

  // Start impersonation — kicks off a real session and redirects to dashboard
  const handleStartImpersonation = async () => {
    setStartingImpersonation(true);
    try {
      const res = await apiFetch(`/admin/users/${user.id}/start_impersonation`, { method: 'POST' });
      if (res.success) {
        notify(res.message, 'warning');
        setTimeout(() => { window.location.href = res.redirect_to || '/dashboard'; }, 800);
      } else {
        notify(res.error || 'Could not start impersonation.', 'error');
        setStartingImpersonation(false);
      }
    } catch { setStartingImpersonation(false); }
  };

  const handleSavePreferences = async () => {
    setPrefsSaving(true);
    try {
      const data = await apiFetch(`/admin/users/${user.id}/preferences`, {
        method: 'PATCH', body: JSON.stringify({ preferences: prefs })
      });
      if (data.success) { notify('Preferences saved.', 'success'); if (data.preferences) setPrefs(data.preferences); }
      else notify(data.errors?.join(', ') || 'Save failed.', 'error');
    } finally { setPrefsSaving(false); }
  };

  const handleChangePassword = async () => {
    setPwdSaving(true);
    try {
      const data = await apiFetch(`/admin/users/${user.id}/change_password`, {
        method: 'POST', body: JSON.stringify(pwdForm)
      });
      if (data.success) { notify('Password updated.', 'success'); setPwdDialogOpen(false); }
      else notify(data.errors?.join(', ') || data.error || 'Failed.', 'error');
    } finally { setPwdSaving(false); }
  };

  if (!user) return null;
  const isNew = !user.id;
  const canEditAdmin = isSuperAdmin;
  const userGroups  = (allGroups || []).filter(g => user.group_ids?.includes(g.id));

  return (
    <>
      <Drawer
        anchor="right" open={open} onClose={onClose}
        slotProps={{ paper: { sx: { width: { xs: '100vw', sm: 560 }, display: 'flex', flexDirection: 'column' } } }}
      >
        {/* Header */}
        <Box sx={{ p: 2.5, pb: 0, borderBottom: '1px solid', borderColor: 'divider' }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 1.5 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
              <Avatar src={user.avatar_url}
                sx={{ width: 48, height: 48, bgcolor: 'primary.main', fontSize: '1.1rem' }}>
                {(user.first_name?.[0] || user.email?.[0] || '?').toUpperCase()}
              </Avatar>
              <Box>
                <Typography variant="h6" sx={{ fontWeight: 700, lineHeight: 1.2 }}>
                  {isNew ? 'Invite New User' : (user.display_name || user.email)}
                </Typography>
                {!isNew && (
                  <Stack direction="row" spacing={0.5} sx={{ flexWrap: 'wrap' }}>
                    <Typography variant="caption" color="text.secondary">{user.email}</Typography>
                    {user.sso_managed && <Chip label={user.provider} size="small" color="primary" variant="outlined" sx={{ height: 16, fontSize: '0.6rem' }} />}
                    {user.admin && <Chip label="Admin" size="small" color="warning" sx={{ height: 16, fontSize: '0.6rem' }} />}
                    <Chip label={user.active ? 'Active' : 'Suspended'} size="small"
                      color={user.active ? 'success' : 'default'} sx={{ height: 16, fontSize: '0.6rem' }} />
                  </Stack>
                )}
              </Box>
            </Box>
            <IconButton size="small" onClick={onClose}><Close fontSize="small" /></IconButton>
          </Box>

          {!isNew && (
              <Tabs value={tab} onChange={(_, v) => setTab(v)} variant="scrollable" scrollButtons="auto"
                sx={{ minHeight: 38, '& .MuiTab-root': { minHeight: 38, fontSize: '0.75rem', py: 0 } }}>
                <Tab icon={<PersonOutlined sx={{ fontSize: 16 }} />} iconPosition="start" label="Properties" />
                <Tab
                  icon={<GroupAdd sx={{ fontSize: 16 }} />}
                  iconPosition="start"
                  label={
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                      Groups
                      {groupsData.total > 0 && (
                        <Box component="span" sx={{
                          ml: 0.5, px: 0.75, py: 0.1, borderRadius: '999px',
                          bgcolor: 'primary.main', color: 'white',
                          fontSize: '0.6rem', fontWeight: 700, lineHeight: 1.6,
                        }}>
                          {groupsData.total}
                        </Box>
                      )}
                    </Box>
                  }
                />
                <Tab icon={<LockOutlined sx={{ fontSize: 16 }} />}   iconPosition="start" label="Permissions" />
                <Tab icon={<SecurityOutlined sx={{ fontSize: 16 }} />} iconPosition="start" label="Impersonators" />
                <Tab icon={<PublicOutlined sx={{ fontSize: 16 }} />} iconPosition="start" label="Preferences" />
              </Tabs>
          )}
        </Box>

        {/* Body */}
        <Box sx={{ flexGrow: 1, overflowY: 'auto', px: 2.5, py: 2 }}>
          {user.sso_managed && (
            <Alert severity="info" sx={{ mb: 2, borderRadius: 2 }}>
              Synchronized via <strong>{user.provider}</strong>. Name and email are read-only.
            </Alert>
          )}

          {/* Tab 0 / new user: Properties */}
          {(isNew || tab === 0) && (
            <Stack spacing={2.5}>
              <Box sx={{ display: 'flex', gap: 2 }}>
                <TextField label="First Name" fullWidth size="small" value={editForm.first_name || ''}
                  onChange={e => setEditForm({ ...editForm, first_name: e.target.value })}
                  disabled={user.sso_managed} />
                <TextField label="Last Name" fullWidth size="small" value={editForm.last_name || ''}
                  onChange={e => setEditForm({ ...editForm, last_name: e.target.value })}
                  disabled={user.sso_managed} />
              </Box>
              <TextField label="Email Address" fullWidth size="small" value={editForm.email || ''}
                onChange={e => setEditForm({ ...editForm, email: e.target.value })}
                disabled={user.sso_managed} />
              <Box sx={{ display: 'flex', gap: 2 }}>
                <TextField label="Department" fullWidth size="small" value={editForm.department || ''}
                  onChange={e => setEditForm({ ...editForm, department: e.target.value })} />
                <TextField label="Job Role" fullWidth size="small" value={editForm.role || ''}
                  onChange={e => setEditForm({ ...editForm, role: e.target.value })} />
              </Box>

              {/* Admin toggle — only super-admins */}
              {canEditAdmin && (
                <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                  p: 1.5, bgcolor: editForm.admin ? '#fff8e1' : '#f8f9fa', borderRadius: 2,
                  border: '1px solid', borderColor: editForm.admin ? 'warning.light' : 'divider' }}>
                  <Box>
                    <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>System Administrator</Typography>
                    <Typography variant="caption" color="text.secondary">
                      Grants full access to all settings and the admin panel.
                    </Typography>
                  </Box>
                  <Switch checked={editForm.admin || false}
                    onChange={e => setEditForm({ ...editForm, admin: e.target.checked })}
                    color="warning" />
                </Box>
              )}

              {!isNew && !user.sso_managed && (
                <Button size="small" variant="outlined" color="secondary"
                  startIcon={<LockOutlined />} onClick={() => setPwdDialogOpen(true)}
                  sx={{ alignSelf: 'flex-start' }}>
                  Change Password
                </Button>
              )}
              {!isNew && user.created_at && (
                <Typography variant="caption" color="text.secondary">
                  Member since {formatDate(user.created_at)}
                </Typography>
              )}
            </Stack>
          )}

          {/* Tab 1: Groups (enhanced) */}
          {!isNew && tab === 1 && (
            <Stack spacing={2}>

              {/* Header row: total count + search filter */}
              <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <Typography variant="subtitle2" fontWeight={700}>
                    Group Memberships
                  </Typography>
                  <Chip
                    label={groupsLoading ? '…' : groupsData.total}
                    size="small"
                    color={groupsData.total > 0 ? 'primary' : 'default'}
                    sx={{ height: 20, fontSize: '0.7rem', fontWeight: 700 }}
                  />
                </Box>
                {groupsData.total > 3 && (
                  <TextField
                    size="small"
                    placeholder="Filter groups…"
                    value={groupFilter}
                    onChange={e => setGroupFilter(e.target.value)}
                    sx={{ width: 180, '& .MuiInputBase-root': { fontSize: '0.8rem' } }}
                  />
                )}
              </Box>

              {/* Add group via autocomplete (admins only) */}
              {isAdmin && (
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ mb: 0.5, display: 'block' }}>
                    Assign to a group:
                  </Typography>
                  <GroupSearch
                    groups={groupsData.all_groups}
                    disabledIds={groupsData.groups.map(g => g.id)}
                    excludeIds={[]}
                    placeholder="Search groups to assign…"
                    onSelect={handleAddGroupInline}
                  />
                </Box>
              )}

              {/* The 'everyone' note */}
              <Alert severity="info" sx={{ borderRadius: 2, py: 0.5 }}>
                The <strong>everyone</strong> group is assigned automatically to all users.
                {!isSuperAdmin && (
                  <> <strong>administrators</strong> and <strong>super-administrators</strong> require super-admin rights.</>
                )}
              </Alert>

              {/* Loading skeleton */}
              {groupsLoading ? (
                <CircularProgress size={24} sx={{ alignSelf: 'center', my: 2 }} />
              ) : groupsData.groups.length === 0 ? (
                <Typography variant="body2" color="text.secondary">
                  No group memberships (other than everyone).
                </Typography>
              ) : (
                <Box>
                  {/* Filtered group list */}
                  {groupsData.groups
                    .filter(g =>
                      g.slug !== SYSTEM_SLUGS.EVERYONE &&
                      (!groupFilter || g.name.toLowerCase().includes(groupFilter.toLowerCase()))
                    )
                    .map(g => {
                      const isLoading = groupActionId === g.id;
                      const canRemove = isAdmin && !g.everyone && !(g.slug === 'administrators' && !isSuperAdmin);
                      const perms = groupPermissions(g, isAdmin, isSuperAdmin);

                      return (
                        <Box
                          key={g.id}
                          sx={{
                            display: 'flex', alignItems: 'center', gap: 1.5,
                            px: 1.5, py: 1, mb: 0.5,
                            borderRadius: 2,
                            border: '1px solid',
                            borderColor: g.is_system ? 'warning.light' : 'divider',
                            bgcolor: g.is_system ? '#fffbeb' : 'white',
                            transition: 'all 0.15s',
                          }}
                        >
                          {/* Icon */}
                          <Box sx={{
                            width: 32, height: 32, borderRadius: '50%',
                            bgcolor: g.is_system ? 'warning.main' : 'primary.main',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            flexShrink: 0,
                          }}>
                            {g.is_system
                              ? <Shield sx={{ fontSize: 16, color: 'white' }} />
                              : <GroupAdd sx={{ fontSize: 16, color: 'white' }} />
                            }
                          </Box>

                          {/* Group info */}
                          <Box sx={{ flexGrow: 1, minWidth: 0 }}>
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, flexWrap: 'wrap' }}>
                              <Typography variant="body2" fontWeight={600} noWrap>{g.name}</Typography>
                              {g.is_system && (
                                <Chip label="system" size="small" color="warning" variant="outlined"
                                  sx={{ height: 16, fontSize: '0.6rem' }} />
                              )}
                            </Box>
                            <Typography variant="caption" color="text.secondary">
                              {g.member_count != null ? `${g.member_count} member${g.member_count !== 1 ? 's' : ''}` : ''}
                              {g.description ? ` · ${g.description}` : ''}
                            </Typography>
                          </Box>

                          {/* Remove button */}
                          {canRemove && (
                            <Tooltip title={`Remove from ${g.name}`}>
                              <IconButton
                                size="small"
                                color="error"
                                onClick={() => handleRemoveGroupInline(g)}
                                disabled={isLoading}
                                sx={{ flexShrink: 0 }}
                              >
                                {isLoading
                                  ? <CircularProgress size={14} />
                                  : <DeleteOutlined fontSize="small" />
                                }
                              </IconButton>
                            </Tooltip>
                          )}
                          {!canRemove && g.slug !== SYSTEM_SLUGS.EVERYONE && (
                            <Tooltip title={
                              g.is_system && !isSuperAdmin
                                ? 'Only super-admins can modify this group'
                                : 'System group — managed automatically'
                            }>
                              <LockOutlined fontSize="small" sx={{ color: 'text.disabled', flexShrink: 0 }} />
                            </Tooltip>
                          )}
                        </Box>
                      );
                    })
                  }

                  {/* Show 'everyone' as read-only pill at the bottom */}
                  {groupsData.groups.some(g => g.slug === SYSTEM_SLUGS.EVERYONE) && (
                    <Chip
                      icon={<Shield sx={{ fontSize: 14 }} />}
                      label="everyone (automatic)"
                      size="small"
                      color="default"
                      variant="outlined"
                      sx={{ mt: 1, fontSize: '0.7rem', opacity: 0.7 }}
                    />
                  )}
                </Box>
              )}
            </Stack>
          )}

          {/* Tab 2: Permissions */}
          {!isNew && tab === 2 && (
            <Stack spacing={2}>
              {groupsLoading ? (
                <CircularProgress size={24} sx={{ alignSelf: 'center', my: 2 }} />
              ) : groupsData.groups.length === 0 ? (
                <Alert severity="info" sx={{ borderRadius: 2 }}>
                  This user does not belong to any groups. Assign the user to a group first
                  to view or edit folder-level permissions.
                </Alert>
              ) : (
                <>
                  {/* Group selector — shown when user belongs to more than one group */}
                  {groupsData.groups.length > 1 && (
                    <FormControl fullWidth size="small">
                      <InputLabel>View permissions for group</InputLabel>
                      <Select
                        value={permGroupId || ''}
                        label="View permissions for group"
                        onChange={e => setPermGroupId(e.target.value)}
                      >
                        {groupsData.groups.map(g => (
                          <MenuItem key={g.id} value={g.id}>
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                              {g.is_system && <Shield sx={{ fontSize: 14, color: 'warning.main' }} />}
                              {g.name}
                              <Typography variant="caption" color="text.secondary" sx={{ ml: 0.5 }}>
                                ({g.member_count} members)
                              </Typography>
                            </Box>
                          </MenuItem>
                        ))}
                      </Select>
                    </FormControl>
                  )}

                  {/* ACL matrix for the selected group */}
                  {permGroupId && (
                    <AclMatrix
                      groupId={permGroupId}
                      readOnly={!isAdmin}
                      isAdmin={isAdmin}
                    />
                  )}
                </>
              )}
            </Stack>
          )}

          {/* Tab 3: Impersonators */}
          {!isNew && tab === 3 && (
            <Stack spacing={2}>
              <Alert severity="info" sx={{ borderRadius: 2 }}>
                Users below can act as <strong>{user.display_name || user.email}</strong>.
                All their actions appear in audit logs attributed to this account.
                The <strong>true actor</strong> is always recorded separately for compliance.
              </Alert>

              {/* Super-admin guard notice */}
              {user.super_admin && (
                <Alert severity="warning" sx={{ borderRadius: 2 }}>
                  Super-admin accounts cannot be configured as impersonation targets.
                </Alert>
              )}

              {/* Grant access — UserSearch autocomplete (not a plain text field) */}
              {isAdmin && !user.super_admin && (
                <Box>
                  <Typography variant="caption" color="text.secondary" sx={{ mb: 0.5, display: 'block' }}>
                    Grant impersonation access to a user:
                  </Typography>
                  <UserSearch
                    placeholder="Search by name or email…"
                    excludeIds={[user.id, ...(impersonators.map(i => i.id))]}
                    onSelect={handleAddImpersonator}
                  />
                </Box>
              )}

              {impersonatorsLoading ? (
                <CircularProgress size={24} sx={{ alignSelf: 'center' }} />
              ) : impersonators.length === 0 ? (
                <Typography variant="body2" color="text.secondary">No impersonators configured.</Typography>
              ) : (
                <List dense sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 2 }}>
                  {impersonators.map((imp, idx) => (
                    <React.Fragment key={imp.id}>
                      {idx > 0 && <Divider />}
                      <ListItem>
                        <ListItemAvatar>
                          <Avatar src={imp.avatar_url}
                            sx={{ width: 32, height: 32, fontSize: '0.8rem', bgcolor: 'secondary.main' }}>
                            {imp.display_name?.[0]?.toUpperCase()}
                          </Avatar>
                        </ListItemAvatar>
                        <ListItemText
                          primary={imp.display_name} secondary={imp.email}
                          slotProps={{
                            primary:   { variant: 'body2', fontWeight: 600, component: 'span' },
                            secondary: { variant: 'caption', component: 'span' },
                          }}
                        />
                        {isAdmin && (
                          <ListItemSecondaryAction>
                            <Tooltip title="Revoke">
                              <IconButton size="small" color="error" onClick={() => handleRemoveImpersonator(imp.id)}>
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

              {/* "Impersonate Now" CTA — only shown when the current viewer can impersonate */}
              {isAdmin && !user.super_admin && user.id && (
                <Box sx={{ pt: 1, borderTop: '1px dashed', borderColor: 'divider' }}>
                  <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 1 }}>
                    Start an impersonation session as this user:
                  </Typography>
                  <Button
                    variant="outlined"
                    color="warning"
                    size="small"
                    startIcon={startingImpersonation
                      ? <CircularProgress size={14} />
                      : <SupervisedUserCircle fontSize="small" />
                    }
                    onClick={handleStartImpersonation}
                    disabled={startingImpersonation}
                    sx={{ fontWeight: 600 }}
                  >
                    {startingImpersonation ? 'Starting…' : `Impersonate ${user.display_name || user.email}`}
                  </Button>
                </Box>
              )}
            </Stack>
          )}

          {/* Tab 4: Preferences */}
          {!isNew && tab === 4 && (
            prefsLoading ? <CircularProgress size={24} sx={{ display: 'block', mx: 'auto', mt: 4 }} /> : (
              <Stack spacing={3}>
                <FormControl fullWidth size="small">
                  <InputLabel id="user-prefs-interface-language-label">Interface Language</InputLabel>
                  <Select labelId="user-prefs-interface-language-label" id="user-prefs-interface-language"
                    value={prefs.language || 'en'} label="Interface Language"
                    onChange={e => setPrefs({ ...prefs, language: e.target.value })}>
                    {SUPPORTED_LANGS.map(l => <MenuItem key={l.value} value={l.value}>{l.label}</MenuItem>)}
                  </Select>
                </FormControl>
                <Box>
                  <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1 }}>Email Notifications</Typography>
                  <Stack spacing={0.5}>
                    <FormControlLabel
                      control={<Switch size="small" checked={prefs.receive_mention_emails ?? true}
                        onChange={e => setPrefs({ ...prefs, receive_mention_emails: e.target.checked })} />}
                      label="@Mention notifications" />
                    <FormControlLabel
                      control={<Switch size="small" checked={prefs.receive_workflow_emails ?? true}
                        onChange={e => setPrefs({ ...prefs, receive_workflow_emails: e.target.checked })} />}
                      label="Workflow task notifications" />
                  </Stack>
                </Box>
                <Button variant="contained" onClick={handleSavePreferences}
                  disabled={prefsSaving} disableElevation>
                  {prefsSaving ? 'Saving…' : 'Save Preferences'}
                </Button>
              </Stack>
            )
          )}
        </Box>

        {/* Footer */}
        <Box sx={{ p: 2, borderTop: '1px solid', borderColor: 'divider', bgcolor: '#fafafa' }}>
          {isNew ? (
            <Button variant="contained" fullWidth onClick={onSave} disableElevation>
              Provision Local Account
            </Button>
          ) : tab === 0 ? (
            <Stack direction="row" sx={{ justifyContent: 'space-between' }}>
              <Tooltip title={isSelf ? 'You cannot suspend your own account.' : ''}>
                <span>
                  <Button color={user.active ? 'error' : 'success'} size="small"
                    disabled={isSelf && user.active}
                    startIcon={user.active ? <Block /> : <CheckCircleOutlined />}
                    onClick={async () => { await onToggleStatus(); onClose(); }}>
                    {user.active ? 'Suspend Access' : 'Restore Access'}
                  </Button>
                </span>
              </Tooltip>
              <Button variant="contained" onClick={onSave} disableElevation>Save Changes</Button>
            </Stack>
          ) : null}
        </Box>
      </Drawer>

      {/* Change Password Dialog */}
      <Dialog open={pwdDialogOpen} onClose={() => setPwdDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ fontWeight: 700 }}>Change Password</DialogTitle>
        <DialogContent dividers>
          <Stack spacing={2} sx={{ pt: 1 }}>
            <TextField label="New Password" type="password" fullWidth size="small"
              value={pwdForm.new_password}
              onChange={e => setPwdForm({ ...pwdForm, new_password: e.target.value })} />
            <TextField label="Confirm New Password" type="password" fullWidth size="small"
              value={pwdForm.new_password_confirmation}
              onChange={e => setPwdForm({ ...pwdForm, new_password_confirmation: e.target.value })} />
            <FormControlLabel
              control={<Switch size="small" checked={pwdForm.force_change}
                onChange={e => setPwdForm({ ...pwdForm, force_change: e.target.checked })} />}
              label="Force change on next login" />
          </Stack>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setPwdDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" onClick={handleChangePassword} disableElevation
            disabled={pwdSaving || !pwdForm.new_password ||
              pwdForm.new_password !== pwdForm.new_password_confirmation}>
            {pwdSaving ? 'Saving…' : 'Update Password'}
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
}

