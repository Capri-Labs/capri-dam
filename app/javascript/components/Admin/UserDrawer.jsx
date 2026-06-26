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
} from '@mui/material';
import {
  Close, Block, CheckCircleOutlined, GroupAdd, Shield,
  PersonOutlined, LockOutlined, NotificationsOutlined, PublicOutlined,
  DeleteOutlined, AddOutlined, SecurityOutlined, SupervisedUserCircle,
} from '@mui/icons-material';
import { apiFetch, formatDate } from '../../utils/adminUtils';
import AclMatrix from './AclMatrix';
import UserSearch from './UserSearch';
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
  allGroups, isAdmin, isSuperAdmin,
}) {
  const notify = useNotify();
  const [tab, setTab] = useState(0);

  const [impersonators, setImpersonators]             = useState([]);
  const [impersonatorsLoading, setImpersonatorsLoading] = useState(false);
  const [startingImpersonation, setStartingImpersonation] = useState(false);

  const [prefs, setPrefs]           = useState({ language: 'en', receive_mention_emails: true, receive_workflow_emails: true });
  const [prefsLoading, setPrefsLoading] = useState(false);
  const [prefsSaving, setPrefsSaving]   = useState(false);

  const [pwdDialogOpen, setPwdDialogOpen] = useState(false);
  const [pwdForm, setPwdForm] = useState({ new_password: '', new_password_confirmation: '', force_change: false });
  const [pwdSaving, setPwdSaving] = useState(false);

  useEffect(() => { if (open) setTab(0); }, [open, user?.id]);

  useEffect(() => { if (tab === 3 && user?.id) fetchImpersonators(); }, [tab, user?.id]);
  useEffect(() => { if (tab === 4 && user?.id) fetchPreferences();   }, [tab, user?.id]);

  const fetchImpersonators = async () => {
    setImpersonatorsLoading(true);
    try {
      const data = await apiFetch(`/admin/users/${user.id}/impersonators.json`);
      setImpersonators(data.impersonators || []);
    } finally { setImpersonatorsLoading(false); }
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
        PaperProps={{ sx: { width: { xs: '100vw', sm: 560 }, display: 'flex', flexDirection: 'column' } }}
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
                  <Stack direction="row" spacing={0.5} flexWrap="wrap">
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
              <Tab icon={<GroupAdd sx={{ fontSize: 16 }} />}       iconPosition="start" label="Groups" />
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

          {/* Tab 1: Groups */}
          {!isNew && tab === 1 && (
            <Stack spacing={2}>
              <Typography variant="body2" color="text.secondary">
                Groups this user belongs to.
              </Typography>
              <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
                {userGroups.length === 0
                  ? <Typography variant="caption" color="text.secondary">No group memberships.</Typography>
                  : userGroups.map(g => (
                    <Chip key={g.id} label={g.name} size="small"
                      icon={g.is_system ? <Shield sx={{ fontSize: 14 }} /> : undefined}
                      color={g.is_system ? 'primary' : 'default'}
                      variant={g.is_system ? 'filled' : 'outlined'} />
                  ))
                }
              </Box>
              <Alert severity="info" sx={{ borderRadius: 2 }}>
                The <strong>everyone</strong> group is automatic.
                Add users to other groups from the <em>User Groups</em> management page.
              </Alert>
            </Stack>
          )}

          {/* Tab 2: Permissions */}
          {!isNew && tab === 2 && (
            <AclMatrix groupId={user.group_ids?.[0]} readOnly isAdmin={isAdmin} />
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
                          primaryTypographyProps={{ variant: 'body2', fontWeight: 600 }}
                          secondaryTypographyProps={{ variant: 'caption' }}
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
                  <InputLabel>Interface Language</InputLabel>
                  <Select value={prefs.language || 'en'} label="Interface Language"
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
            <Stack direction="row" justifyContent="space-between">
              <Button color={user.active ? 'error' : 'success'} size="small"
                startIcon={user.active ? <Block /> : <CheckCircleOutlined />}
                onClick={async () => { await onToggleStatus(); onClose(); }}>
                {user.active ? 'Suspend Access' : 'Restore Access'}
              </Button>
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

