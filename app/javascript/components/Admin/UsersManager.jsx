/**
 * UsersManager — DAM user directory with advanced admin features.
 *
 * Features:
 *  - Server-side paginated DataGrid
 *  - Row click → full tabbed UserDrawer (Properties | Groups | Permissions |
 *    Impersonators | Preferences)
 *  - Quick status toggle, group assignment from grid
 *  - Invite new local user
 *  - Admin/super-admin context propagated to all sub-components
 *
 * Access control note:
 *  - isAdmin  : can manage all non-system groups
 *  - isSuperAdmin : can also manage administrators + super-administrators groups
 *    and toggle the "System Administrator" switch on users
 */
import React, { useState, useEffect } from 'react';
import {
  Box, Paper, Typography, Button, Chip, IconButton,
  CssBaseline, Stack, Tooltip, Badge,
} from '@mui/material';
import {
  DataGrid,
  GridToolbarContainer,
  GridToolbarColumnsButton,
  GridToolbarFilterButton,
  GridToolbarDensitySelector,
  GridToolbarExport,
} from '@mui/x-data-grid';
import {
  PersonAddOutlined, Security, VpnKey, GroupAdd,
  CheckCircleOutlined, BlockOutlined, Shield,
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';
import UserDrawer from './UserDrawer';
import GroupAssignmentModal from './GroupAssignmentModal';
import { apiFetch } from '../../utils/adminUtils';

function CustomToolbar() {
  return (
    <GridToolbarContainer>
      <GridToolbarColumnsButton />
      <GridToolbarFilterButton />
      <GridToolbarDensitySelector />
      <GridToolbarExport />
    </GridToolbarContainer>
  );
}

export default function UsersManager({ isAdmin = false, isSuperAdmin = false }) {
  const notify = useNotify();

  const isAdminBool     = isAdmin === true || isAdmin === 'true';
  const isSuperAdminBool = isSuperAdmin === true || isSuperAdmin === 'true';

  const [users, setUsers]     = useState([]);
  const [allGroups, setAllGroups] = useState([]);
  const [loading, setLoading] = useState(true);
  const [paginationModel, setPaginationModel] = useState({ page: 0, pageSize: 25 });
  const [totalCount, setTotalCount] = useState(0);

  const [drawerOpen, setDrawerOpen]     = useState(false);
  const [selectedUser, setSelectedUser] = useState(null);
  const [editForm, setEditForm]         = useState({});

  const [groupModalOpen, setGroupModalOpen]   = useState(false);
  const [groupTargetUser, setGroupTargetUser] = useState(null);

  useEffect(() => { fetchGroups(); }, []);
  useEffect(() => { fetchUsers();  }, [paginationModel]);

  const fetchUsers = async () => {
    setLoading(true);
    try {
      const { page, pageSize } = paginationModel;
      const data = await apiFetch(`/admin/users.json?page=${page}&limit=${pageSize}`);
      setUsers(data.users || []);
      setTotalCount(data.total_count || data.users?.length || 0);
    } catch { notify('Failed to load users.', 'error'); }
    finally   { setLoading(false); }
  };

  const fetchGroups = async () => {
    try {
      const data = await apiFetch('/admin/user_groups.json');
      setAllGroups(data.user_groups || []);
    } catch { /* non-critical */ }
  };

  const handleToggleStatus = async () => {
    if (!selectedUser?.id) return;
    const data = await apiFetch(`/admin/users/${selectedUser.id}/toggle_status.json`, { method: 'POST' });
    if (data.success) {
      notify(data.message, selectedUser.active ? 'warning' : 'success');
      fetchUsers();
    } else {
      notify('Failed to change user status.', 'error');
    }
  };

  const handleSaveProfile = async () => {
    const url    = selectedUser.id ? `/admin/users/${selectedUser.id}.json` : '/admin/users.json';
    const method = selectedUser.id ? 'PATCH' : 'POST';
    const data   = await apiFetch(url, { method, body: JSON.stringify({ user: editForm }) });
    if (data.success) {
      notify('Saved successfully.', 'success');
      setDrawerOpen(false);
      fetchUsers();
    } else {
      notify(`Error: ${data.errors?.join(', ')}`, 'error');
    }
  };

  const handleSaveGroups = async (userId, groupIds) => {
    const data = await apiFetch(`/admin/users/${userId}.json`, {
      method: 'PATCH',
      body: JSON.stringify({ user: { user_group_ids: groupIds } })
    });
    if (data.success) {
      notify('Groups updated.', 'success');
      setGroupModalOpen(false);
      fetchUsers();
    } else {
      notify('Error updating groups.', 'error');
    }
  };

  const handleRowClick = (params) => {
    const user = params.row;
    setSelectedUser(user);
    setEditForm({
      email:      user.email,
      first_name: user.first_name,
      last_name:  user.last_name,
      department: user.department,
      role:       user.role,
      admin:      user.admin || false,
    });
    setDrawerOpen(true);
  };

  // ── Columns ──────────────────────────────────────────────────────────────

  const columns = [
    {
      field: 'display_name', headerName: 'Name', flex: 1.2, minWidth: 180,
      renderCell: (p) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Typography variant="body2" fontWeight={500}>{p.row.display_name}</Typography>
          {p.row.admin && (
            <Tooltip title="System Administrator">
              <Shield sx={{ fontSize: 14, color: 'warning.main' }} />
            </Tooltip>
          )}
        </Box>
      )
    },
    { field: 'email', headerName: 'Email', flex: 1.2, minWidth: 200 },
    {
      field: 'origin', headerName: 'Auth', flex: 0.7, minWidth: 100,
      renderCell: (p) => p.row.sso_managed
        ? <Chip icon={<Security sx={{ fontSize: 14 }} />} label={p.row.provider || 'SSO'}
            size="small" color="primary" variant="outlined" sx={{ fontSize: '0.7rem' }} />
        : <Chip icon={<VpnKey sx={{ fontSize: 14 }} />} label="Local"
            size="small" variant="outlined" sx={{ fontSize: '0.7rem' }} />
    },
    { field: 'department', headerName: 'Department', flex: 0.9, minWidth: 120 },
    { field: 'role',       headerName: 'Role',       flex: 0.8, minWidth: 100 },
    {
      field: 'groups', headerName: 'Groups', flex: 1.5, minWidth: 200,
      renderCell: (p) => (
        <Box sx={{ display: 'flex', gap: 0.5, alignItems: 'center', width: '100%' }}>
          {p.row.groups?.slice(0, 2).map(g => (
            <Chip key={g} label={g} size="small" sx={{ fontSize: '0.65rem', height: 20 }} />
          ))}
          {p.row.groups?.length > 2 && (
            <Typography variant="caption" color="text.secondary">
              +{p.row.groups.length - 2}
            </Typography>
          )}
          <Tooltip title="Manage group memberships">
            <IconButton size="small" sx={{ ml: 'auto' }}
              onClick={e => {
                e.stopPropagation();
                setGroupTargetUser(p.row);
                setGroupModalOpen(true);
              }}>
              <GroupAdd fontSize="small" color="primary" />
            </IconButton>
          </Tooltip>
        </Box>
      )
    },
    {
      field: 'active', headerName: 'Status', width: 110,
      renderCell: (p) => (
        <Chip
          label={p.row.active ? 'Active' : 'Suspended'}
          size="small"
          color={p.row.active ? 'success' : 'default'}
          icon={p.row.active
            ? <CheckCircleOutlined sx={{ fontSize: 14 }} />
            : <BlockOutlined sx={{ fontSize: 14 }} />
          }
          sx={{ fontSize: '0.7rem' }}
        />
      )
    },
  ];

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
      <CssBaseline />
      <Box component="main" sx={{ flexGrow: 1, p: 3 }}>

        {/* Header */}
        <Stack direction="row" sx={{
  mb: 3,
  alignItems: "flex-start",
  justifyContent: "space-between"
}}>
          <Box>
            <Typography variant="h4" sx={{ fontWeight: 700 }}>System Users</Typography>
            <Typography variant="body2" color="text.secondary">
              Manage employee access, group hierarchy, and preferences.
            </Typography>
          </Box>
          <Button
            variant="contained"
            startIcon={<PersonAddOutlined />}
            disableElevation
            onClick={() => {
              setSelectedUser({});
              setEditForm({ email: '', first_name: '', last_name: '', department: '', role: '', admin: false });
              setDrawerOpen(true);
            }}
          >
            Invite Local User
          </Button>
        </Stack>

        {/* Grid */}
        <Paper variant="outlined" sx={{ borderRadius: 3, height: 680, bgcolor: 'white' }}>
          <DataGrid
            rows={users}
            columns={columns}
            loading={loading}
            paginationMode="server"
            paginationModel={paginationModel}
            onPaginationModelChange={setPaginationModel}
            rowCount={totalCount}
            pageSizeOptions={[25, 50, 100]}
            slots={{ toolbar: CustomToolbar }}
            disableRowSelectionOnClick
            onRowClick={handleRowClick}
            sx={{
              border: 'none',
              '& .MuiDataGrid-row': { cursor: 'pointer' },
              '& .MuiDataGrid-row:hover': { bgcolor: '#f1f5f9' },
            }}
          />
        </Paper>
      </Box>

      {/* Full tabbed user drawer */}
      <UserDrawer
        open={drawerOpen}
        user={selectedUser}
        editForm={editForm}
        setEditForm={setEditForm}
        onClose={() => setDrawerOpen(false)}
        onSave={handleSaveProfile}
        onToggleStatus={handleToggleStatus}
        allGroups={allGroups}
        isAdmin={isAdminBool}
        isSuperAdmin={isSuperAdminBool}
      />

      {/* Group assignment modal with access control */}
      <GroupAssignmentModal
        open={groupModalOpen}
        user={groupTargetUser}
        allGroups={allGroups}
        onClose={() => setGroupModalOpen(false)}
        onSave={handleSaveGroups}
        isAdmin={isAdminBool}
        isSuperAdmin={isSuperAdminBool}
      />
    </Box>
  );
}