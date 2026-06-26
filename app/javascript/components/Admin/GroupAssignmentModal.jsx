/**
 * GroupAssignmentModal — assign users to groups with full system-group awareness.
 *
 * Security rules:
 *  - 'everyone' is hidden (auto-managed).
 *  - 'administrators' is only assignable by super-admins.
 *  - 'super-administrators' is only assignable by super-admins.
 *  - Regular admins see the above groups but cannot check them.
 */
import React, { useState, useEffect } from 'react';
import {
  Dialog, DialogTitle, DialogContent, DialogActions,
  Button, Typography, Checkbox, Box, List, ListItem, ListItemIcon,
  ListItemText, Divider, Chip, Alert, Tooltip,
} from '@mui/material';
import { Shield, LockOutlined, InfoOutlined } from '@mui/icons-material';
import { groupPermissions, SYSTEM_SLUGS, isSystemGroup } from '../../utils/adminUtils';

export default function GroupAssignmentModal({
  open, user, allGroups, onClose, onSave,
  isAdmin = false, isSuperAdmin = false,
}) {
  const [checkedGroups, setCheckedGroups] = useState([]);

  useEffect(() => {
    if (open && user) setCheckedGroups(user.group_ids || []);
  }, [open, user]);

  const getAllChildrenIds = (parentId) => {
    const children = allGroups.filter(g => g.parent_id === parentId);
    let ids = children.map(c => c.id);
    children.forEach(c => { ids = [...ids, ...getAllChildrenIds(c.id)]; });
    return ids;
  };

  const canAssign = (group) => {
    const perms = groupPermissions(group, isAdmin, isSuperAdmin);
    return perms.canAssignUser;
  };

  const handleToggle = (group) => {
    if (!canAssign(group)) return;
    const isChecked = checkedGroups.includes(group.id);
    const childrenIds = getAllChildrenIds(group.id);
    if (!isChecked) {
      setCheckedGroups(prev => [...new Set([...prev, group.id, ...childrenIds])]);
    } else {
      setCheckedGroups(prev => prev.filter(id => id !== group.id && !childrenIds.includes(id)));
    }
  };

  const buildTree = (groups, parentId = null) =>
    groups
      .filter(g => g.parent_id === parentId && g.slug !== SYSTEM_SLUGS.EVERYONE)
      .map(g => ({ ...g, children: buildTree(groups, g.id) }));

  const renderTree = (nodes, depth = 0) => nodes.map((node) => {
    const assignable = canAssign(node);
    const locked = isSystemGroup(node) && !assignable;

    return (
      <Box key={node.id}>
        <ListItem
          sx={{
            pl: 2 + depth * 2.5,
            borderRadius: 1,
            cursor: assignable ? 'pointer' : 'not-allowed',
            opacity: locked ? 0.55 : 1,
            '&:hover': { bgcolor: assignable ? 'action.hover' : 'transparent' },
          }}
          onClick={() => handleToggle(node)}
        >
          <ListItemIcon sx={{ minWidth: 36 }}>
            {locked ? (
              <Tooltip title={
                node.slug === SYSTEM_SLUGS.SUPER_ADMINS
                  ? 'Only super-admins can assign to this group'
                  : 'Only super-admins can assign to the administrators group'
              }>
                <LockOutlined fontSize="small" color="disabled" />
              </Tooltip>
            ) : (
              <Checkbox
                size="small"
                checked={checkedGroups.includes(node.id)}
                onChange={() => handleToggle(node)}
                onClick={e => e.stopPropagation()}
              />
            )}
          </ListItemIcon>
          <ListItemText
            primary={
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                {node.name}
                {node.is_system && (
                  <Chip
                    label="system"
                    size="small"
                    icon={<Shield sx={{ fontSize: 12 }} />}
                    color={node.slug === SYSTEM_SLUGS.SUPER_ADMINS ? 'error' : 'warning'}
                    variant="outlined"
                    sx={{ height: 16, fontSize: '0.6rem' }}
                  />
                )}
              </Box>
            }
            secondary={node.description}
            slotProps={{
              primary:   { variant: 'body2', fontWeight: node.is_system ? 600 : 400, component: 'div' },
              secondary: { variant: 'caption', component: 'div' },
            }}
          />
        </ListItem>
        {node.children?.length > 0 && renderTree(node.children, depth + 1)}
      </Box>
    );
  });

  const tree = buildTree(allGroups || []);

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle sx={{ fontWeight: 700 }}>
        Group Hierarchy &amp; Access
        {user && (
          <Typography variant="body2" color="text.secondary">
            Editing groups for <strong>{user.display_name || user.email}</strong>
          </Typography>
        )}
      </DialogTitle>

      <DialogContent dividers sx={{ p: 0 }}>
        {!isSuperAdmin && (
          <Alert severity="info" icon={<InfoOutlined />} sx={{ m: 2, borderRadius: 2 }}>
            <strong>administrators</strong> and <strong>super-administrators</strong> groups
            can only be assigned by super-admins.
          </Alert>
        )}
        <List sx={{ pt: 0 }}>
          {renderTree(tree)}
          {tree.length === 0 && (
            <Typography variant="body2" color="text.secondary" sx={{ p: 3, textAlign: 'center' }}>
              No groups available.
            </Typography>
          )}
        </List>
      </DialogContent>

      <DialogActions sx={{ p: 2 }}>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" disableElevation
          onClick={() => onSave(user?.id, checkedGroups)}>
          Save Group Assignments
        </Button>
      </DialogActions>
    </Dialog>
  );
}