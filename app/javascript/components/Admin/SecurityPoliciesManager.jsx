/**
 * SecurityPoliciesManager — standalone "Security Policies" admin screen.
 *
 * Lets an admin pick any user group from a searchable list and view/edit its
 * full folder-permission matrix in one place, without first having to open
 * that group's overlay from User Groups. This is a thin wrapper around two
 * already-existing, already-tested building blocks:
 *   - `GET /admin/user_groups.json` for the group list (same endpoint
 *     UserGroupsManager.jsx uses).
 *   - `AclMatrix.jsx` for the folder-tree permission editor (the same
 *     component already mounted inside GroupOverlay.jsx's Permissions tab).
 *
 * No new backend JSON API is introduced by this screen.
 */
import React, { useState, useEffect, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Box, Paper, Typography, List, ListItem, ListItemButton, ListItemText,
  ListItemIcon, Chip, TextField, InputAdornment, CircularProgress, Divider,
  CssBaseline,
} from '@mui/material';
import { SecurityOutlined, GroupWorkOutlined, SearchOutlined } from '@mui/icons-material';
import { apiFetch, isSystemGroup, SYSTEM_SLUGS } from '../../utils/adminUtils';
import { useNotify } from '../../context/NotificationContext';
import AclMatrix from './AclMatrix';

function groupColor(group) {
  if (group.slug === SYSTEM_SLUGS.SUPER_ADMINS) return 'error';
  if (group.slug === SYSTEM_SLUGS.ADMINS)       return 'warning';
  if (group.slug === SYSTEM_SLUGS.EVERYONE)     return 'info';
  return 'default';
}

export default function SecurityPoliciesManager({ isAdmin = false }) {
  const { t } = useTranslation();
  const tp = (key, opts) => t(`securityPolicies.${key}`, opts);
  const notify = useNotify();
  const isAdminBool = isAdmin === true || isAdmin === 'true';

  const [groups, setGroups] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [selectedGroup, setSelectedGroup] = useState(null);

  useEffect(() => {
    (async () => {
      setLoading(true);
      try {
        const data = await apiFetch('/admin/user_groups.json');
        const list = data.user_groups || [];
        setGroups(list);
        if (list.length > 0) setSelectedGroup(list[0]);
      } catch {
        notify(tp('notifications.loadFailed'), 'error');
      } finally {
        setLoading(false);
      }
      // eslint-disable-next-line react-hooks/exhaustive-deps
    })();
  }, []);

  const filteredGroups = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return groups;
    return groups.filter(g => g.name.toLowerCase().includes(q));
  }, [groups, search]);

  const systemGroups = filteredGroups.filter(g => isSystemGroup(g));
  const customGroups = filteredGroups.filter(g => !isSystemGroup(g));

  return (
    <Box sx={{ display: 'flex', height: '100%', bgcolor: '#f8fafc' }}>
      <CssBaseline />

      {/* Left: group picker */}
      <Paper elevation={0} sx={{ width: 320, flexShrink: 0, borderRight: '1px solid #e2e8f0', borderRadius: 0, overflowY: 'auto' }}>
        <Box sx={{ p: 2.5, borderBottom: '1px solid #e2e8f0' }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
            <SecurityOutlined sx={{ color: '#4f46e5' }} />
            <Typography variant="h6" fontWeight={700}>{tp('title', 'Security Policies')}</Typography>
          </Box>
          <Typography variant="body2" color="textSecondary">
            {tp('subtitle', 'Select a group to view or edit its folder-permission matrix.')}
          </Typography>
        </Box>

        <Box sx={{ p: 1.5 }}>
          <TextField
            fullWidth
            size="small"
            placeholder={tp('searchPlaceholder', 'Search groups…')}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            slotProps={{ input: { startAdornment: (
              <InputAdornment position="start"><SearchOutlined fontSize="small" /></InputAdornment>
            ) } }}
          />
        </Box>

        {loading ? (
          <Box sx={{ p: 4, textAlign: 'center' }}><CircularProgress size={24} /></Box>
        ) : (
          <List dense sx={{ px: 1 }}>
            {systemGroups.length > 0 && (
              <>
                <Typography variant="caption" color="textSecondary" sx={{ pl: 1.5, textTransform: 'uppercase', fontWeight: 700 }}>
                  {tp('systemGroups', 'System Groups')}
                </Typography>
                {systemGroups.map((g) => (
                  <ListItem key={g.id} disablePadding>
                    <ListItemButton
                      selected={selectedGroup?.id === g.id}
                      onClick={() => setSelectedGroup(g)}
                      sx={{ borderRadius: 1, mb: 0.25 }}
                    >
                      <ListItemIcon sx={{ minWidth: 28 }}>
                        <GroupWorkOutlined sx={{ fontSize: 18 }} color={groupColor(g)} />
                      </ListItemIcon>
                      <ListItemText primary={g.name} />
                      <Chip label={g.member_count} size="small" sx={{ height: 18, fontSize: '0.65rem' }} />
                    </ListItemButton>
                  </ListItem>
                ))}
                <Divider sx={{ my: 1 }} />
              </>
            )}

            {customGroups.length > 0 && (
              <>
                <Typography variant="caption" color="textSecondary" sx={{ pl: 1.5, textTransform: 'uppercase', fontWeight: 700 }}>
                  {tp('customGroups', 'Custom Groups')}
                </Typography>
                {customGroups.map((g) => (
                  <ListItem key={g.id} disablePadding>
                    <ListItemButton
                      selected={selectedGroup?.id === g.id}
                      onClick={() => setSelectedGroup(g)}
                      sx={{ borderRadius: 1, mb: 0.25 }}
                    >
                      <ListItemIcon sx={{ minWidth: 28 }}>
                        <GroupWorkOutlined sx={{ fontSize: 18 }} color="primary" />
                      </ListItemIcon>
                      <ListItemText primary={g.name} />
                      <Chip label={g.member_count} size="small" sx={{ height: 18, fontSize: '0.65rem' }} />
                    </ListItemButton>
                  </ListItem>
                ))}
              </>
            )}

            {!loading && filteredGroups.length === 0 && (
              <Typography variant="body2" color="textSecondary" sx={{ p: 2, textAlign: 'center' }}>
                {tp('noGroups', 'No groups match your search.')}
              </Typography>
            )}
          </List>
        )}
      </Paper>

      {/* Right: ACL matrix for the selected group */}
      <Box sx={{ flexGrow: 1, overflowY: 'auto', p: 3 }}>
        {selectedGroup ? (
          <>
            <Typography variant="subtitle1" fontWeight={700} sx={{ mb: 2 }}>
              {tp('matrixFor', { name: selectedGroup.name })}
            </Typography>
            <AclMatrix
              groupId={selectedGroup.id}
              readOnly={!isAdminBool || selectedGroup.slug === SYSTEM_SLUGS.EVERYONE}
              isAdmin={isAdminBool}
            />
          </>
        ) : (
          !loading && (
            <Typography variant="body2" color="textSecondary" sx={{ p: 4, textAlign: 'center' }}>
              {tp('noGroupSelected', 'Select a group on the left to view its permissions.')}
            </Typography>
          )
        )}
      </Box>
    </Box>
  );
}
