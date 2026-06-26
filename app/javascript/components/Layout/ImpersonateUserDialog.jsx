/**
 * ImpersonateUserDialog — modal launched from the top-bar that lets an admin
 * search for any user and immediately start an impersonation session.
 *
 * Security:
 *  - The component is only rendered when the viewer is an admin or super-admin.
 *  - The backend enforces the same role-hierarchy rules (super-admins only,
 *    admins cannot impersonate super-admins, etc.).
 *  - On success the banner (ImpersonationBanner) auto-appears on the next page.
 *
 * UX flow:
 *   1. User clicks "Impersonate User" in the header dropdown.
 *   2. This dialog opens → type ≥2 chars to search.
 *   3. Pick a user → see a confirmation summary.
 *   4. Click "Start Impersonation" → redirect to /dashboard with banner.
 */
import React, { useState } from 'react';
import {
  Dialog, DialogTitle, DialogContent, DialogActions,
  Button, Box, Typography, Avatar, Chip, Stack, Alert,
  CircularProgress, Divider,
} from '@mui/material';
import {
  SupervisedUserCircle, WarningAmber, PersonOutlined,
} from '@mui/icons-material';
import UserSearch from '../Admin/UserSearch';
import { apiFetch } from '../../utils/adminUtils';

export default function ImpersonateUserDialog({ open, onClose }) {
  const [selectedUser, setSelectedUser] = useState(null);
  const [loading, setLoading]           = useState(false);
  const [error, setError]               = useState(null);

  const handleClose = () => {
    setSelectedUser(null);
    setError(null);
    onClose();
  };

  const handleSelectUser = (user) => {
    setSelectedUser(user);
    setError(null);
  };

  const handleStart = async () => {
    if (!selectedUser) return;
    setLoading(true);
    setError(null);

    try {
      const res = await apiFetch(`/impersonation/start/${selectedUser.id}`, { method: 'POST' });

      if (res.success) {
        // Redirect — the ImpersonationBanner will render on the next page load
        window.location.href = '/dashboard';
      } else {
        setError(res.error || 'Failed to start impersonation.');
        setLoading(false);
      }
    } catch (e) {
      setError('Network error. Please try again.');
      setLoading(false);
    }
  };

  return (
    <Dialog
      open={open}
      onClose={handleClose}
      maxWidth="sm"
      fullWidth
      PaperProps={{ sx: { borderRadius: 3 } }}
    >
      <DialogTitle sx={{ fontWeight: 700, display: 'flex', alignItems: 'center', gap: 1.5, pb: 1 }}>
        <SupervisedUserCircle color="warning" sx={{ fontSize: 28 }} />
        Impersonate User
      </DialogTitle>

      <DialogContent dividers>
        <Stack spacing={2.5}>
          {/* Warning */}
          <Alert
            severity="warning"
            icon={<WarningAmber />}
            sx={{ borderRadius: 2 }}
          >
            <Typography variant="body2" fontWeight={600}>
              You are about to act as another user.
            </Typography>
            <Typography variant="body2" sx={{ mt: 0.5 }}>
              All actions taken during this session will affect the selected
              user's real account. Every action is audit-logged under{' '}
              <strong>both</strong> your name and theirs for full traceability.
            </Typography>
          </Alert>

          {/* Rules reminder */}
          <Box sx={{ bgcolor: '#f8fafc', borderRadius: 2, p: 1.5 }}>
            <Typography variant="caption" color="text.secondary" fontWeight={600}>
              Access rules:
            </Typography>
            <Typography variant="caption" color="text.secondary" component="ul"
              sx={{ m: 0, pl: 2, mt: 0.5 }}>
              <li>Admins can impersonate any non-super-admin user</li>
              <li>Super-admins can impersonate anyone (including admins)</li>
              <li>Super-admin accounts cannot be impersonated</li>
            </Typography>
          </Box>

          {/* User Search */}
          <Box>
            <Typography variant="body2" fontWeight={600} sx={{ mb: 1 }}>
              Search for user to impersonate:
            </Typography>
            <UserSearch
              placeholder="Type name or email…"
              onSelect={handleSelectUser}
              excludeIds={[]}
            />
          </Box>

          {/* Selected User Preview */}
          {selectedUser && (
            <Box sx={{
              display: 'flex', alignItems: 'center', gap: 2,
              p: 2, borderRadius: 2,
              border: '2px solid', borderColor: 'warning.main',
              bgcolor: '#fffbeb',
            }}>
              <Avatar
                src={selectedUser.avatar_url}
                sx={{ width: 44, height: 44, bgcolor: 'warning.main', fontSize: '1rem', fontWeight: 700 }}
              >
                {selectedUser.display_name?.[0]?.toUpperCase()}
              </Avatar>
              <Box sx={{ flexGrow: 1, minWidth: 0 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
                  <Typography variant="subtitle2" fontWeight={700}>
                    {selectedUser.display_name}
                  </Typography>
                  {selectedUser.admin && (
                    <Chip label="Admin" size="small" color="warning" sx={{ height: 18, fontSize: '0.6rem' }} />
                  )}
                  {selectedUser.sso_managed && (
                    <Chip label="SSO" size="small" color="primary" variant="outlined"
                      sx={{ height: 18, fontSize: '0.6rem' }} />
                  )}
                </Box>
                <Typography variant="caption" color="text.secondary" noWrap>
                  {selectedUser.email}
                </Typography>
                {selectedUser.department && (
                  <Typography variant="caption" color="text.secondary"> · {selectedUser.department}</Typography>
                )}
              </Box>
              <PersonOutlined color="warning" />
            </Box>
          )}

          {/* Error */}
          {error && (
            <Alert severity="error" sx={{ borderRadius: 2 }}>{error}</Alert>
          )}
        </Stack>
      </DialogContent>

      <DialogActions sx={{ p: 2, gap: 1 }}>
        <Button onClick={handleClose} disabled={loading}>Cancel</Button>
        <Button
          variant="contained"
          color="warning"
          onClick={handleStart}
          disabled={!selectedUser || loading}
          startIcon={loading ? <CircularProgress size={16} color="inherit" /> : <SupervisedUserCircle />}
          sx={{ fontWeight: 700 }}
          disableElevation
        >
          {loading ? 'Starting…' : 'Start Impersonation'}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

