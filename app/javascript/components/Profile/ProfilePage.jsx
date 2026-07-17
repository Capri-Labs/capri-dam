/**
 * ProfilePage — self-service profile for the logged-in DAM user.
 *
 * Tabs:
 *   0 — Personal Details & Identity
 *   1 — Localization & Preferences  (theme, language, timezone)
 *   2 — Security & Access           (password reset, Personal Access Tokens)
 *   3 — My Activity                 (read-only audit log timeline)
 *
 * Receives initial data via DOM data-* attributes from the Rails view.
 */
import React, { useState, useEffect, useCallback } from 'react';
import {
  Box, Paper, Typography, Button, TextField, Chip, Stack, Avatar,
  Tabs, Tab, Alert, Divider, Switch, FormControlLabel,
  FormControl, InputLabel, Select, MenuItem, CircularProgress,
  List, ListItem, ListItemText, ListItemIcon, IconButton,
  Dialog, DialogTitle, DialogContent, DialogActions, Tooltip,
  Table, TableBody, TableCell, TableHead, TableRow, Badge,
} from '@mui/material';
import {
  PersonOutlined, PublicOutlined, LockOutlined, HistoryOutlined,
  ContentCopy, DeleteOutlined, AddOutlined, Visibility, VisibilityOff,
  CheckCircleOutlined, WarningAmber, KeyOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { changeLanguage } from '../../i18n/index';
import { apiFetch } from '../../utils/adminUtils';
import { useNotify } from '../../context/NotificationContext';

// ─── Helpers ─────────────────────────────────────────────────────────────────

const SUPPORTED_LANGS = [
  { value: 'en', label: 'English' },    { value: 'de', label: 'Deutsch' },
  { value: 'fr', label: 'Français' },   { value: 'es', label: 'Español' },
  { value: 'pt', label: 'Português' },  { value: 'nl', label: 'Nederlands' },
  { value: 'ja', label: '日本語' },       { value: 'zh', label: '中文' },
  { value: 'ko', label: '한국어' },       { value: 'ar', label: 'العربية' },
];

const SUPPORTED_THEMES = [
  { value: 'system', label: 'System Default' },
  { value: 'light',  label: 'Light' },
  { value: 'dark',   label: 'Dark' },
];


function TabPanel({ children, value, index }) {
  return value === index ? <Box role="tabpanel" sx={{ pt: 3 }}>{children}</Box> : null;
}

function ActivityIcon({ action }) {
  const map = {
    create: '✅', update: '✏️', destroy: '🗑️',
    impersonation_start: '🔍', impersonation_end: '🔓',
    pat_created: '🔑', pat_revoked: '❌',
  };
  return <span style={{ fontSize: '1rem', marginRight: 6 }}>{map[action] || '📋'}</span>;
}

// ─── Main Component ───────────────────────────────────────────────────────────

export default function ProfilePage(props) {
  const notify = useNotify();
  const { t, i18n } = useTranslation();
  const [tab, setTab] = useState(0);

  // ── Personal Details state ─────────────────────────────────────────────────
  const [form, setForm] = useState({
    first_name: props.userFirstName || '',
    last_name:  props.userLastName  || '',
    email:      props.userEmail     || '',
    department: props.userDepartment || '',
    avatar_url: props.userAvatarUrl  || '',
  });
  const [saving, setSaving] = useState(false);
  const ssoManaged = props.ssoManaged === 'true' || props.ssoManaged === true;

  // ── Preferences state ──────────────────────────────────────────────────────
  const [prefs, setPrefs] = useState(() => {
    try { return JSON.parse(props.preferences) || {}; }
    catch { return {}; }
  });
  const [prefsSaving, setPrefsSaving] = useState(false);

  // ── Password state ─────────────────────────────────────────────────────────
  const [pwdForm, setPwdForm] = useState({
    current_password: '', new_password: '', new_password_confirmation: '',
  });
  const [pwdSaving, setPwdSaving] = useState(false);
  const [showPwd, setShowPwd] = useState(false);

  // ── PAT state ──────────────────────────────────────────────────────────────
  const [tokens, setTokens]           = useState([]);
  const [tokensLoading, setTokensLoading] = useState(false);
  const [newTokenDialog, setNewTokenDialog] = useState(false);
  const [newTokenForm, setNewTokenForm]     = useState({ name: '', scopes: 'read', expires_at: '' });
  const [creatingToken, setCreatingToken]   = useState(false);
  const [revealedToken, setRevealedToken]   = useState(null); // one-time raw token

  // ── Activity state ─────────────────────────────────────────────────────────
  const [activity, setActivity]         = useState(() => {
    try { return JSON.parse(props.auditLogs) || []; }
    catch { return []; }
  });
  const [activityLoading, setActivityLoading] = useState(false);

  // ── Fetch PATs when Security tab is opened ────────────────────────────────
  useEffect(() => {
    if (tab === 2) fetchTokens();
  }, [tab]);

  const fetchTokens = async () => {
    setTokensLoading(true);
    try {
      const data = await apiFetch('/profile/personal_access_tokens.json');
      setTokens(data.tokens || []);
    } finally { setTokensLoading(false); }
  };

  const fetchActivity = useCallback(async () => {
    setActivityLoading(true);
    try {
      const data = await apiFetch('/profile/activity.json?limit=50');
      setActivity(data.activity || []);
    } finally { setActivityLoading(false); }
  }, []);

  useEffect(() => { if (tab === 3) fetchActivity(); }, [tab]);

  // ── Handlers ──────────────────────────────────────────────────────────────

  const handleSaveProfile = async () => {
    setSaving(true);
    try {
      const data = await apiFetch('/profile', {
        method: 'PATCH', body: JSON.stringify({ user: form }),
      });
      if (data.success) notify('Profile updated.', 'success');
      else notify(data.errors?.join(', ') || 'Save failed.', 'error');
    } finally { setSaving(false); }
  };

  const handleSavePreferences = async () => {
    setPrefsSaving(true);
    try {
      const data = await apiFetch('/profile/preferences', {
        method: 'PATCH', body: JSON.stringify({ preferences: prefs }),
      });
      if (data.success) {
        notify(t('common.success'), 'success');
        if (data.preferences) setPrefs(data.preferences);
        // Apply the language change instantly — zero-lag, no page reload needed.
        if (data.preferences?.language) {
          changeLanguage(data.preferences.language);
        }
      } else notify(data.errors?.join(', ') || t('common.error'), 'error');
    } finally { setPrefsSaving(false); }
  };

  const handleChangePassword = async () => {
    if (pwdForm.new_password !== pwdForm.new_password_confirmation) {
      notify('New passwords do not match.', 'error'); return;
    }
    setPwdSaving(true);
    try {
      const data = await apiFetch('/profile/password', {
        method: 'PATCH', body: JSON.stringify(pwdForm),
      });
      if (data.success) {
        notify('Password changed successfully.', 'success');
        setPwdForm({ current_password: '', new_password: '', new_password_confirmation: '' });
      } else notify(data.errors?.join(', ') || data.error || 'Failed.', 'error');
    } finally { setPwdSaving(false); }
  };

  const handleCreateToken = async () => {
    if (!newTokenForm.name.trim()) { notify('Token name is required.', 'error'); return; }
    setCreatingToken(true);
    try {
      const data = await apiFetch('/profile/personal_access_tokens', {
        method: 'POST', body: JSON.stringify({ token: newTokenForm }),
      });
      if (data.success) {
        setRevealedToken(data.token?.raw_token || data.raw_token);
        setNewTokenDialog(false);
        setNewTokenForm({ name: '', scopes: 'read', expires_at: '' });
        fetchTokens();
        notify('Token created! Copy it now — it will not be shown again.', 'warning');
      } else notify(data.errors?.join(', ') || 'Failed.', 'error');
    } finally { setCreatingToken(false); }
  };

  const handleRevokeToken = async (tokenId, tokenName) => {
    const data = await apiFetch(`/profile/personal_access_tokens/${tokenId}`, { method: 'DELETE' });
    if (data.success) { notify(`Token "${tokenName}" revoked.`, 'success'); fetchTokens(); }
    else notify('Failed to revoke token.', 'error');
  };

  const copyToClipboard = (text) => {
    navigator.clipboard.writeText(text).then(() => notify('Copied to clipboard!', 'success'));
  };

  // ─── Render ───────────────────────────────────────────────────────────────

  return (
    <Box sx={{ maxWidth: 860, mx: 'auto', p: 3 }}>

      {/* Page Header */}
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 3 }}>
        <Avatar
          src={form.avatar_url}
          sx={{ width: 64, height: 64, bgcolor: 'primary.main', fontSize: '1.4rem', fontWeight: 700 }}
        >
          {(form.first_name?.[0] || props.userEmail?.[0] || '?').toUpperCase()}
        </Avatar>
        <Box>
          <Typography variant="h5" fontWeight={700}>
            {[form.first_name, form.last_name].filter(Boolean).join(' ') || props.userEmail}
          </Typography>
          <Stack direction="row" spacing={1} sx={{
  alignItems: "center"
}}>
            <Typography variant="body2" color="text.secondary">{props.userEmail}</Typography>
            {ssoManaged && (
              <Chip label={`SSO: ${props.ssoProvider}`} size="small" color="primary" variant="outlined"
                sx={{ height: 18, fontSize: '0.65rem' }} />
            )}
            {props.isAdmin === 'true' && (
              <Chip label="Admin" size="small" color="warning" sx={{ height: 18, fontSize: '0.65rem' }} />
            )}
          </Stack>
        </Box>
      </Box>

      <Paper variant="outlined" sx={{ borderRadius: 3 }}>
        {/* Tab Navigation */}
        <Tabs
          value={tab} onChange={(_, v) => setTab(v)}
          sx={{ borderBottom: '1px solid', borderColor: 'divider', px: 2 }}
          variant="scrollable"
        >
          <Tab icon={<PersonOutlined sx={{ fontSize: 18 }} />} iconPosition="start" label={t('profile.tabs.personal')} />
          <Tab data-testid="profile-tab-localization" icon={<PublicOutlined sx={{ fontSize: 18 }} />} iconPosition="start" label={t('profile.tabs.localization')} />
          <Tab icon={<LockOutlined sx={{ fontSize: 18 }} />}   iconPosition="start" label={t('profile.tabs.security')} />
          <Tab icon={<HistoryOutlined sx={{ fontSize: 18 }} />} iconPosition="start" label={t('profile.tabs.activity')} />
        </Tabs>

        <Box sx={{ p: 3 }}>

          {/* ─── Tab 0: Personal Details ──────────────────────────────── */}
          <TabPanel value={tab} index={0}>
            {ssoManaged && (
              <Alert severity="info" sx={{ mb: 2.5, borderRadius: 2 }}>
                Your account is synced via <strong>{props.ssoProvider}</strong>.
                Name and email are read-only and managed by your identity provider.
              </Alert>
            )}
            <Stack spacing={2.5}>
              <Box sx={{ display: 'flex', gap: 2 }}>
                <TextField
                  label="First Name" fullWidth size="small"
                  value={form.first_name}
                  onChange={e => setForm({ ...form, first_name: e.target.value })}
                  disabled={ssoManaged}
                />
                <TextField
                  label="Last Name" fullWidth size="small"
                  value={form.last_name}
                  onChange={e => setForm({ ...form, last_name: e.target.value })}
                  disabled={ssoManaged}
                />
              </Box>
              <TextField
                label="Email Address" fullWidth size="small"
                value={form.email}
                onChange={e => setForm({ ...form, email: e.target.value })}
                disabled={ssoManaged}
                helperText={ssoManaged ? 'Managed by SSO provider' : 'Changing your email will require re-verification.'}
              />
              <TextField
                label="Department" fullWidth size="small"
                value={form.department}
                onChange={e => setForm({ ...form, department: e.target.value })}
              />
              <TextField
                label="Avatar URL" fullWidth size="small"
                value={form.avatar_url}
                onChange={e => setForm({ ...form, avatar_url: e.target.value })}
                helperText="Direct link to your profile picture, or upload via your storage backend."
              />
              <Box sx={{ display: 'flex', justifyContent: 'flex-end' }}>
                <Button variant="contained" onClick={handleSaveProfile}
                  disabled={saving} disableElevation>
                  {saving ? 'Saving…' : 'Save Changes'}
                </Button>
              </Box>
            </Stack>
          </TabPanel>

          {/* ─── Tab 1: Localization & Preferences ───────────────────── */}
          <TabPanel value={tab} index={1}>
            <Stack spacing={3}>
              <FormControl fullWidth size="small">
                <InputLabel>{t('profile.localization.theme')}</InputLabel>
                <Select value={prefs.theme || 'system'} label={t('profile.localization.theme')}
                  onChange={e => setPrefs({ ...prefs, theme: e.target.value })}>
                  <MenuItem value="system">{t('profile.localization.themeSystem')}</MenuItem>
                  <MenuItem value="light">{t('profile.localization.themeLight')}</MenuItem>
                  <MenuItem value="dark">{t('profile.localization.themeDark')}</MenuItem>
                </Select>
              </FormControl>

              <FormControl fullWidth size="small">
                <InputLabel>{t('profile.localization.language')}</InputLabel>
                <Select value={prefs.language || 'en'} label={t('profile.localization.language')}
                  onChange={e => setPrefs({ ...prefs, language: e.target.value })}>
                  {SUPPORTED_LANGS.map(l => (
                    <MenuItem key={l.value} value={l.value}>{l.label}</MenuItem>
                  ))}
                </Select>
              </FormControl>

              <Divider />

              <Box>
                <Typography variant="subtitle2" fontWeight={600} sx={{ mb: 1 }}>
                  {t('profile.localization.notifications')}
                </Typography>
                <Stack spacing={0.5}>
                  <FormControlLabel
                    control={
                      <Switch size="small"
                        checked={prefs.receive_mention_emails ?? true}
                        onChange={e => setPrefs({ ...prefs, receive_mention_emails: e.target.checked })}
                      />
                    }
                    label={t('profile.localization.mentions')}
                  />
                  <FormControlLabel
                    control={
                      <Switch size="small"
                        checked={prefs.receive_workflow_emails ?? true}
                        onChange={e => setPrefs({ ...prefs, receive_workflow_emails: e.target.checked })}
                      />
                    }
                    label={t('profile.localization.workflowTasks')}
                  />
                </Stack>
              </Box>

              <Box sx={{ display: 'flex', justifyContent: 'flex-end' }}>
                <Button variant="contained" onClick={handleSavePreferences}
                  disabled={prefsSaving} disableElevation data-testid="save-preferences-button">
                  {prefsSaving ? t('common.saving') : t('profile.localization.savePreferences')}
                </Button>
              </Box>
            </Stack>
          </TabPanel>

          {/* ─── Tab 2: Security & Access ─────────────────────────────── */}
          <TabPanel value={tab} index={2}>
            <Stack spacing={4}>

              {/* Password Reset */}
              {ssoManaged ? (
                <Alert severity="info" sx={{ borderRadius: 2 }}>
                  Your password is managed by <strong>{props.ssoProvider}</strong>.
                  To change it, please use your identity provider's portal.
                </Alert>
              ) : (
                <Box>
                  <Typography variant="subtitle1" fontWeight={700} sx={{ mb: 2 }}>
                    Change Password
                  </Typography>
                  <Stack spacing={2} sx={{ maxWidth: 480 }}>
                    <TextField
                      label="Current Password" type={showPwd ? 'text' : 'password'}
                      size="small" fullWidth
                      value={pwdForm.current_password}
                      onChange={e => setPwdForm({ ...pwdForm, current_password: e.target.value })} slotProps={{input: {
                        endAdornment: (
                          <IconButton size="small" onClick={() => setShowPwd(!showPwd)}>
                            {showPwd ? <VisibilityOff fontSize="small" /> : <Visibility fontSize="small" />}
                          </IconButton>
                        ),
                      } }}
                    />
                    <TextField
                      label="New Password" type="password" size="small" fullWidth
                      value={pwdForm.new_password}
                      onChange={e => setPwdForm({ ...pwdForm, new_password: e.target.value })}
                    />
                    <TextField
                      label="Confirm New Password" type="password" size="small" fullWidth
                      value={pwdForm.new_password_confirmation}
                      onChange={e => setPwdForm({ ...pwdForm, new_password_confirmation: e.target.value })}
                      error={pwdForm.new_password_confirmation &&
                        pwdForm.new_password !== pwdForm.new_password_confirmation}
                      helperText={
                        pwdForm.new_password_confirmation &&
                        pwdForm.new_password !== pwdForm.new_password_confirmation
                          ? 'Passwords do not match' : ''
                      }
                    />
                    <Button
                      variant="contained" onClick={handleChangePassword}
                      disabled={pwdSaving || !pwdForm.current_password || !pwdForm.new_password}
                      disableElevation sx={{ alignSelf: 'flex-start' }}
                    >
                      {pwdSaving ? 'Updating…' : 'Update Password'}
                    </Button>
                  </Stack>
                </Box>
              )}

              <Divider />

              {/* Personal Access Tokens */}
              <Box>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                  <Box>
                    <Typography variant="subtitle1" fontWeight={700}>Personal Access Tokens</Typography>
                    <Typography variant="body2" color="text.secondary">
                      Use PATs to authenticate CLI tools or external scripts without your password.
                      Format: <code>Authorization: Bearer dat_…</code>
                    </Typography>
                  </Box>
                  <Button variant="outlined" size="small" startIcon={<AddOutlined />}
                    onClick={() => setNewTokenDialog(true)}>
                    New Token
                  </Button>
                </Box>

                {/* One-time token reveal */}
                {revealedToken && (
                  <Alert severity="warning" sx={{ mb: 2, borderRadius: 2, fontFamily: 'monospace' }}
                    action={
                      <Button size="small" startIcon={<ContentCopy fontSize="small" />}
                        onClick={() => { copyToClipboard(revealedToken); setRevealedToken(null); }}>
                        Copy &amp; Dismiss
                      </Button>
                    }
                  >
                    <strong>Copy this token now — it will never be shown again:</strong>
                    <Box component="code" sx={{ display: 'block', mt: 0.5, wordBreak: 'break-all', fontSize: '0.8rem' }}>
                      {revealedToken}
                    </Box>
                  </Alert>
                )}

                {tokensLoading ? (
                  <CircularProgress size={24} sx={{ display: 'block', my: 2 }} />
                ) : tokens.length === 0 ? (
                  <Typography variant="body2" color="text.secondary">
                    No tokens yet. Create one to get started.
                  </Typography>
                ) : (
                  <Table size="small">
                    <TableHead>
                      <TableRow>
                        <TableCell><Typography variant="caption" fontWeight={700}>Name</Typography></TableCell>
                        <TableCell><Typography variant="caption" fontWeight={700}>Scopes</Typography></TableCell>
                        <TableCell><Typography variant="caption" fontWeight={700}>Last Four</Typography></TableCell>
                        <TableCell><Typography variant="caption" fontWeight={700}>Last Used</Typography></TableCell>
                        <TableCell><Typography variant="caption" fontWeight={700}>Expires</Typography></TableCell>
                        <TableCell><Typography variant="caption" fontWeight={700}>Status</Typography></TableCell>
                        <TableCell />
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {tokens.map(t => (
                        <TableRow key={t.id} sx={{ '&:hover': { bgcolor: '#f8fafc' } }}>
                          <TableCell>
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                              <KeyOutlined sx={{ fontSize: 14, color: 'text.secondary' }} />
                              <Typography variant="body2" fontWeight={600}>{t.name}</Typography>
                            </Box>
                          </TableCell>
                          <TableCell>
                            <Chip label={t.scopes} size="small" variant="outlined"
                              sx={{ fontSize: '0.65rem', height: 20 }} />
                          </TableCell>
                          <TableCell>
                            <Typography variant="caption" fontFamily="monospace">…{t.last_four}</Typography>
                          </TableCell>
                          <TableCell>
                            <Typography variant="caption" color="text.secondary">
                              {t.last_used_at ? new Date(t.last_used_at).toLocaleDateString() : 'Never'}
                            </Typography>
                          </TableCell>
                          <TableCell>
                            <Typography variant="caption" color={
                              t.expires_at && new Date(t.expires_at) < new Date() ? 'error.main' : 'text.secondary'
                            }>
                              {t.expires_at ? new Date(t.expires_at).toLocaleDateString() : 'Never'}
                            </Typography>
                          </TableCell>
                          <TableCell>
                            <Chip
                              label={t.active ? 'Active' : 'Revoked'}
                              size="small"
                              color={t.active ? 'success' : 'default'}
                              sx={{ fontSize: '0.65rem', height: 20 }}
                            />
                          </TableCell>
                          <TableCell align="right">
                            {t.active && (
                              <Tooltip title="Revoke token">
                                <IconButton size="small" color="error"
                                  onClick={() => handleRevokeToken(t.id, t.name)}>
                                  <DeleteOutlined fontSize="small" />
                                </IconButton>
                              </Tooltip>
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                )}
              </Box>
            </Stack>
          </TabPanel>

          {/* ─── Tab 3: My Activity ───────────────────────────────────── */}
          <TabPanel value={tab} index={3}>
            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
              Read-only timeline of your recent actions on this platform.
              Only your own activity is shown here; administrators see a broader view in the audit panel.
            </Typography>

            {activityLoading ? (
              <CircularProgress size={24} sx={{ display: 'block', my: 2 }} />
            ) : activity.length === 0 ? (
              <Typography variant="body2" color="text.secondary">No activity yet.</Typography>
            ) : (
              <List disablePadding>
                {activity.map((log, idx) => (
                  <React.Fragment key={log.id}>
                    {idx > 0 && <Divider />}
                    <ListItem alignItems="flex-start" sx={{ py: 1.5 }}>
                      <ListItemIcon sx={{ minWidth: 36, mt: 0.5 }}>
                        <ActivityIcon action={log.action} />
                      </ListItemIcon>
                      <ListItemText
                        primary={
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
                            <Typography variant="body2" fontWeight={600} sx={{ textTransform: 'capitalize' }}>
                              {log.action.replace(/_/g, ' ')}
                            </Typography>
                            {log.auditable_type && (
                              <Chip label={log.auditable_type} size="small" variant="outlined"
                                sx={{ height: 18, fontSize: '0.6rem' }} />
                            )}
                            {log.impersonated && (
                              <Chip label="Via Impersonation" size="small" color="warning"
                                sx={{ height: 18, fontSize: '0.6rem' }} />
                            )}
                          </Box>
                        }
                        secondary={
                          <Typography variant="caption" color="text.secondary">
                            {new Date(log.created_at).toLocaleString()}
                            {log.ip_address && ` · ${log.ip_address}`}
                          </Typography>
                        }
                      />
                    </ListItem>
                  </React.Fragment>
                ))}
              </List>
            )}
          </TabPanel>

        </Box>
      </Paper>

      {/* New Token Dialog */}
      <Dialog open={newTokenDialog} onClose={() => setNewTokenDialog(false)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ fontWeight: 700 }}>Create Personal Access Token</DialogTitle>
        <DialogContent dividers>
          <Stack spacing={2} sx={{ pt: 1 }}>
            <TextField
              label="Token Name" size="small" fullWidth autoFocus
              placeholder="e.g. CI/CD pipeline, Local dev script"
              value={newTokenForm.name}
              onChange={e => setNewTokenForm({ ...newTokenForm, name: e.target.value })}
            />
            <FormControl fullWidth size="small">
              <InputLabel>Scopes</InputLabel>
              <Select value={newTokenForm.scopes} label="Scopes"
                onChange={e => setNewTokenForm({ ...newTokenForm, scopes: e.target.value })}>
                <MenuItem value="read">read — read-only access</MenuItem>
                <MenuItem value="write">write — read + create/update</MenuItem>
                <MenuItem value="admin">admin — full access</MenuItem>
              </Select>
            </FormControl>
            <TextField
              label="Expiry Date (optional)" type="date" size="small" fullWidth
              value={newTokenForm.expires_at}
              onChange={e => setNewTokenForm({ ...newTokenForm, expires_at: e.target.value })} slotProps={{inputLabel: { shrink: true } }}
              helperText="Leave blank for a token that never expires."
            />
          </Stack>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setNewTokenDialog(false)}>Cancel</Button>
          <Button variant="contained" onClick={handleCreateToken}
            disabled={creatingToken || !newTokenForm.name.trim()} disableElevation>
            {creatingToken ? 'Creating…' : 'Create Token'}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

