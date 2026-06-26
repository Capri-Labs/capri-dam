/**
 * UserGroupsManager — hierarchical group management.
 *
 * Tree panel (left): groups → child → grandchild at full depth.
 *   - System groups pinned at top (colour-coded, no "+" button).
 *   - Each custom group has a hover "+" button to create a child.
 *   - Search shows flat list so children aren't hidden by parent filter.
 *
 * Detail panel (right): GroupOverlay drawer with 4 tabs.
 *
 * Access control:
 *  - admin:       create/edit/delete custom groups; add/remove from administrators
 *  - super-admin: also modify super-administrators membership
 *  - no one:      delete system groups
 */
import React, { useState, useEffect } from 'react';
import {
  Box, Grid, Paper, Typography, Button, List, ListItem,
  ListItemButton, ListItemText, ListItemIcon, Chip, Stack,
  IconButton, Dialog, DialogTitle, DialogContent, DialogActions,
  TextField, Divider, CssBaseline, Tooltip, Alert,
} from '@mui/material';
import {
  GroupWorkOutlined, AddCircleOutlined, SubdirectoryArrowRight,
  Shield, SearchOutlined, AddOutlined,
} from '@mui/icons-material';
import { useNotify }     from '../../context/NotificationContext';
import { apiFetch, isSystemGroup, SYSTEM_SLUGS } from '../../utils/adminUtils';
import GroupOverlay from './GroupOverlay';

function groupColor(group) {
  if (group.slug === SYSTEM_SLUGS.SUPER_ADMINS) return 'error';
  if (group.slug === SYSTEM_SLUGS.ADMINS)       return 'warning';
  if (group.slug === SYSTEM_SLUGS.EVERYONE)     return 'info';
  return 'default';
}

// ── Tree node with hover "Create Child" button ─────────────────────────────
function GroupTreeNode({ group, depth, selected, onClick, onCreateChild }) {
  const [hovered, setHovered] = useState(false);
  const system = isSystemGroup(group);
  const color  = groupColor(group);

  return (
    <ListItem
      disablePadding
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      <ListItemButton
        selected={selected}
        onClick={() => onClick(group)}
        sx={{ pl: 1.5 + depth * 2, borderRadius: 1, mb: 0.25, py: 0.6, pr: 1 }}
      >
        <ListItemIcon sx={{ minWidth: 28 }}>
          {depth > 0
            ? <SubdirectoryArrowRight sx={{ fontSize: 16 }} color="disabled" />
            : <GroupWorkOutlined sx={{ fontSize: 18 }} color={system ? color : 'primary'} />
          }
        </ListItemIcon>
        <ListItemText
          primary={
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
              <Typography variant="body2" fontWeight={selected ? 700 : 500} noWrap>
                {group.name}
              </Typography>
              {system && (
                <Chip label="sys" size="small" color={color} variant="outlined"
                  sx={{ height: 14, fontSize: '0.55rem', px: 0, flexShrink: 0 }} />
              )}
            </Box>
          }
        />
        {/* Member count chip */}
        <Chip label={group.member_count} size="small"
          sx={{ height: 18, fontSize: '0.65rem', minWidth: 22, flexShrink: 0 }} />
        {/* Hover "+" button — only for non-system or system where nesting is allowed */}
        {hovered && !system && onCreateChild && (
          <Tooltip title={`Create sub-group under "${group.name}"`} placement="right">
            <IconButton
              size="small" color="primary"
              sx={{ ml: 0.5, flexShrink: 0 }}
              onClick={e => { e.stopPropagation(); onCreateChild(group.id); }}
            >
              <AddOutlined sx={{ fontSize: 14 }} />
            </IconButton>
          </Tooltip>
        )}
      </ListItemButton>
    </ListItem>
  );
}

// ── Main component ─────────────────────────────────────────────────────────
export default function UserGroupsManager({
  isAdmin      = false,
  isSuperAdmin = false,
  currentUserId,
}) {
  const notify = useNotify();

  const isAdminBool      = isAdmin === true || isAdmin === 'true';
  const isSuperAdminBool = isSuperAdmin === true || isSuperAdmin === 'true';
  const currentUserIdNum = currentUserId ? Number(currentUserId) : null;

  const [groups, setGroups]     = useState([]);
  const [loading, setLoading]   = useState(true);
  const [selectedGroup, setSelectedGroup] = useState(null);
  const [overlayOpen, setOverlayOpen]     = useState(false);
  const [search, setSearch]     = useState('');

  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [createForm, setCreateForm]             = useState({ name: '', description: '', parent_id: null });
  const [createSaving, setCreateSaving]         = useState(false);

  useEffect(() => { fetchGroups(); }, []);

  const fetchGroups = async () => {
    setLoading(true);
    try {
      const data = await apiFetch('/admin/user_groups.json');
      setGroups(data.user_groups || []);
    } catch { notify('Failed to load groups.', 'error'); }
    finally   { setLoading(false); }
  };

  const handleGroupClick = (group) => { setSelectedGroup(group); setOverlayOpen(true); };

  const handleOpenCreate = (parentId = null) => {
    setCreateForm({ name: '', description: '', parent_id: parentId });
    setCreateDialogOpen(true);
  };

  const handleCreateGroup = async () => {
    if (!createForm.name.trim()) return;
    setCreateSaving(true);
    try {
      const data = await apiFetch('/admin/user_groups.json', {
        method: 'POST',
        body: JSON.stringify({
          user_group: { name: createForm.name, description: createForm.description },
          parent_id:  createForm.parent_id,
        })
      });
      if (data.success) {
        notify('Group created.', 'success');
        setCreateDialogOpen(false);
        fetchGroups();
      } else {
        notify(data.errors?.join(', ') || 'Error.', 'error');
      }
    } finally { setCreateSaving(false); }
  };

  // ── Tree rendering ─────────────────────────────────────────────────────
  const allSystem  = groups.filter(g => isSystemGroup(g));
  const allCustom  = groups.filter(g => !isSystemGroup(g));

  // When searching: flat list of matching groups (no tree, so depth-broken children still show)
  const searchLower = search.toLowerCase();
  const filteredCustom = search
    ? allCustom.filter(g => g.name.toLowerCase().includes(searchLower))
    : allCustom;
  const filteredSystem = search
    ? allSystem.filter(g => g.name.toLowerCase().includes(searchLower))
    : allSystem;

  // Recursive tree builder — only used when NOT searching
  const renderTree = (parentId = null, depth = 0) => {
    const children = allCustom.filter(g => {
      // null == null and number == number (strict)
      const pid = g.parent_id;
      return parentId === null ? (pid === null || pid === undefined) : pid === parentId;
    });
    if (children.length === 0) return null;
    return children.map(group => (
      <React.Fragment key={group.id}>
        <GroupTreeNode
          group={group} depth={depth}
          selected={selectedGroup?.id === group.id}
          onClick={handleGroupClick}
          onCreateChild={handleOpenCreate}
        />
        {renderTree(group.id, depth + 1)}
      </React.Fragment>
    ));
  };

  const totalMembers = groups.reduce((s, g) => s + (g.member_count || 0), 0);

  return (
    <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
      <CssBaseline />
      <Box component="main" sx={{ flexGrow: 1, p: 3 }}>

        <Stack direction="row" justifyContent="space-between" alignItems="flex-start" sx={{ mb: 3 }}>
          <Box>
            <Typography variant="h4" sx={{ fontWeight: 700 }}>User Groups</Typography>
            <Typography variant="body2" color="text.secondary">
              {groups.length} groups · {totalMembers} total memberships
            </Typography>
          </Box>
          <Button variant="contained" startIcon={<AddCircleOutlined />}
            onClick={() => handleOpenCreate(null)} disableElevation>
            New Group
          </Button>
        </Stack>

        <Paper elevation={0}
          sx={{ p: 0, border: '1.5px solid #5e35b1', borderRadius: 3, bgcolor: 'white', overflow: 'hidden' }}>
          <Grid container sx={{ height: 'calc(100vh - 180px)', minHeight: 520 }}>

            {/* ── Left: hierarchy tree ── */}
            <Grid item xs={12} md={10} lg={3.5}
              sx={{ borderRight: '1px solid', borderColor: 'divider', overflowY: 'auto', width: '30%' }}>

              {/* Search */}
              <Box sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider', bgcolor: '#fafafa' }}>
                <TextField size="small" fullWidth placeholder="Search groups…"
                  value={search} onChange={e => setSearch(e.target.value)}
                  InputProps={{
                    startAdornment: <SearchOutlined sx={{ mr: 1, fontSize: 18, color: 'text.secondary' }} />
                  }}
                />
              </Box>

              {/* System groups */}
              <Box sx={{ px: 1.5, pt: 1.5 }}>
                <Typography variant="overline" sx={{ px: 1, color: 'text.secondary', fontSize: '0.62rem' }}>
                  System Groups
                </Typography>
                <List dense sx={{ pt: 0 }}>
                  {filteredSystem.map(group => (
                    <GroupTreeNode
                      key={group.id} group={group} depth={0}
                      selected={selectedGroup?.id === group.id}
                      onClick={handleGroupClick}
                      onCreateChild={null}   // no child creation for system groups
                    />
                  ))}
                  {filteredSystem.length === 0 && search && (
                    <Typography variant="caption" color="text.secondary" sx={{ px: 1 }}>
                      No system groups match.
                    </Typography>
                  )}
                </List>
              </Box>

              <Divider />

              {/* Custom groups tree */}
              <Box sx={{ px: 1.5, pt: 1 }}>
                <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ px: 1, mb: 0.5 }}>
                  <Typography variant="overline" sx={{ color: 'text.secondary', fontSize: '0.62rem' }}>
                    Custom Groups
                  </Typography>
                  <Tooltip title="Create root-level group">
                    <IconButton size="small" onClick={() => handleOpenCreate(null)}>
                      <AddCircleOutlined fontSize="small" color="primary" />
                    </IconButton>
                  </Tooltip>
                </Stack>
                <List dense sx={{ pt: 0 }}>
                  {loading ? (
                    <Typography variant="body2" color="text.secondary" sx={{ px: 1 }}>Loading…</Typography>
                  ) : search ? (
                    // Flat list when searching
                    filteredCustom.length === 0 ? (
                      <Typography variant="caption" color="text.secondary" sx={{ px: 1 }}>
                        No groups match.
                      </Typography>
                    ) : filteredCustom.map(group => (
                      <GroupTreeNode
                        key={group.id} group={group} depth={0}
                        selected={selectedGroup?.id === group.id}
                        onClick={handleGroupClick}
                        onCreateChild={handleOpenCreate}
                      />
                    ))
                  ) : (
                    // Full recursive tree when not searching
                    (() => {
                      const tree = renderTree(null, 0);
                      return tree || (
                        <Typography variant="body2" color="text.secondary" sx={{ px: 1, py: 2, textAlign: 'center' }}>
                          No custom groups yet.
                        </Typography>
                      );
                    })()
                  )}
                </List>
              </Box>
            </Grid>

            {/* ── Right: empty / hint state ── */}
            <Grid item xs={12} md={10} lg={8.5}
              sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center',
                bgcolor: '#fafbfc', borderRadius: '0 12px 12px 0', width: '70%' }}>
              {!overlayOpen && (
                <Box sx={{ textAlign: 'center', p: 4, maxWidth: 420 }}>
                  <GroupWorkOutlined sx={{ fontSize: 72, color: '#ddd', mb: 2 }} />
                  <Typography variant="h6" color="text.secondary" sx={{ fontWeight: 600 }}>
                    Select a group to manage
                  </Typography>
                  <Typography variant="body2" color="text.secondary" sx={{ mt: 1, mb: 3 }}>
                    Click any group in the left panel to open the overlay with
                    Properties, Members, Permissions, and Groups tabs.
                    Hover a custom group to see the <strong>+</strong> button for creating a child.
                  </Typography>
                  <Button variant="outlined" startIcon={<AddCircleOutlined />}
                    onClick={() => handleOpenCreate(null)}>
                    Create First Group
                  </Button>
                </Box>
              )}
            </Grid>
          </Grid>
        </Paper>
      </Box>

      {/* Group overlay */}
      <GroupOverlay
        open={overlayOpen}
        group={selectedGroup}
        onClose={() => { setOverlayOpen(false); setSelectedGroup(null); }}
        onGroupUpdated={fetchGroups}
        allGroups={groups}
        isAdmin={isAdminBool}
        isSuperAdmin={isSuperAdminBool}
        currentUserId={currentUserIdNum}
        onCreateSubGroup={(parentId) => {
          setOverlayOpen(false);
          handleOpenCreate(parentId);
        }}
      />

      {/* Create group dialog */}
      <Dialog open={createDialogOpen} onClose={() => setCreateDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 700 }}>
          {createForm.parent_id ? (
            <>Create Sub-Group under <em>{groups.find(g => g.id === createForm.parent_id)?.name}</em></>
          ) : 'Create Root Group'}
        </DialogTitle>
        <DialogContent dividers>
          <Stack spacing={2.5} sx={{ pt: 1 }}>
            {createForm.parent_id && (
              <Alert severity="info" sx={{ borderRadius: 2 }}>
                This will be nested under <strong>{groups.find(g => g.id === createForm.parent_id)?.name}</strong>.
                It will inherit all ancestor permissions.
              </Alert>
            )}
            <TextField label="Group Name *" fullWidth size="small" autoFocus
              value={createForm.name}
              onChange={e => setCreateForm({ ...createForm, name: e.target.value })}
              onKeyDown={e => e.key === 'Enter' && handleCreateGroup()}
            />
            <TextField label="Description (optional)" fullWidth size="small" multiline rows={2}
              value={createForm.description}
              onChange={e => setCreateForm({ ...createForm, description: e.target.value })} />
          </Stack>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setCreateDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" onClick={handleCreateGroup}
            disabled={createSaving || !createForm.name.trim()} disableElevation>
            {createSaving ? 'Creating…' : 'Create Group'}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}