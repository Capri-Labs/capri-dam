import React, { useState, useEffect } from 'react';
import { Box, Paper, Typography, Button, Chip, IconButton, CssBaseline } from '@mui/material';
import { DataGrid, GridToolbarContainer, GridToolbarColumnsButton, GridToolbarFilterButton, GridToolbarDensitySelector } from '@mui/x-data-grid';
import { PersonAddOutlined, Security, VpnKey, GroupAdd } from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';
import Sidebar from "../Sidebar";
import { navigateTo } from "../../utils/globalutils";

import UserDrawer from './UserDrawer';
import GroupAssignmentModal from './GroupAssignmentModal';

/**
 * Custom Toolbar to replace the deprecated monolithic GridToolbar
 */
function CustomToolbar() {
    return (
        <GridToolbarContainer>
            <GridToolbarColumnsButton />
            <GridToolbarFilterButton />
            <GridToolbarDensitySelector />
        </GridToolbarContainer>
    );
}

export default function UsersManager() {
    const notify = useNotify();
    const [users, setUsers] = useState([]);
    const [allGroups, setAllGroups] = useState([]);
    const [loading, setLoading] = useState(true);

    const [paginationModel, setPaginationModel] = useState({ page: 0, pageSize: 25 });
    const [totalCount, setTotalCount] = useState(0);

    const [drawerOpen, setDrawerOpen] = useState(false);
    const [selectedUser, setSelectedUser] = useState(null);
    const [isEditing, setIsEditing] = useState(false);
    const [editForm, setEditForm] = useState({ email: '', first_name: '', last_name: '', department: '', role: '' });

    const [groupModalOpen, setGroupModalOpen] = useState(false);
    const [groupTargetUser, setGroupTargetUser] = useState(null);

    useEffect(() => {
        fetchGroups();
    }, []);

    // Re-fetch users whenever paginationModel changes
    useEffect(() => {
        fetchUsers();
    }, [paginationModel]);

    const fetchUsers = () => {
        setLoading(true);
        const { page, pageSize } = paginationModel;
        fetch(`/admin/users.json?page=${page}&limit=${pageSize}`)
            .then(res => res.json())
            .then(data => {
                setUsers(data.users || []);
                setTotalCount(data.total_count || 0);
                setLoading(false);
            })
            .catch(() => { notify("Failed to load user directory.", "error"); setLoading(false); });
    };

    const handleToggleStatus = async () => {
        if (!selectedUser?.id) return;

        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const response = await fetch(`/admin/users/${selectedUser.id}/toggle_status.json`, {
            method: 'POST',
            headers: { 'X-CSRF-Token': csrfToken }
        });

        const data = await response.json();
        if (data.success) {
            notify(data.message, selectedUser.active ? "warning" : "success");
            fetchUsers(); // Refresh the grid
        } else {
            notify("Failed to change user status.", "error");
        }
    };

    const fetchGroups = () => {
        fetch('/admin/user_groups.json')
            .then(res => res.json())
            .then(data => setAllGroups(data.user_groups || []));
    };

    const columns = [
        { field: 'display_name', headerName: 'Profile', flex: 1.5, minWidth: 200 },
        { field: 'email', headerName: 'Email', flex: 1.2, minWidth: 200 },
        {
            field: 'origin', headerName: 'Origin', flex: 0.8,
            renderCell: (params) => (
                params.row.sso_managed
                    ? <Chip icon={<Security sx={{ fontSize: 16 }} />} label={params.row.provider} size="small" color="primary" variant="outlined" />
                    : <Chip icon={<VpnKey sx={{ fontSize: 16 }} />} label="Local" size="small" variant="outlined" />
            )
        },
        { field: 'department', headerName: 'Department', flex: 1, hideable: true },
        { field: 'role', headerName: 'Role', flex: 1, hideable: true },
        {
            field: 'groups', headerName: 'Groups', flex: 1.5, minWidth: 200,
            renderCell: (params) => (
                <Box sx={{ display: 'flex', gap: 0.5, alignItems: 'center', width: '100%' }}>
                    {params.row.groups?.slice(0, 2).map(g => <Chip key={g} label={g} size="small" sx={{ fontSize: '0.7rem' }} />)}
                    {params.row.groups?.length > 2 && <Typography variant="caption">+{params.row.groups.length - 2}</Typography>}
                    <IconButton size="small" sx={{ ml: 'auto' }} onClick={(e) => { e.stopPropagation(); setGroupTargetUser(params.row); setGroupModalOpen(true); }}>
                        <GroupAdd fontSize="small" color="primary" />
                    </IconButton>
                </Box>
            )
        },
        { field: 'active', headerName: 'Status', width: 100, type: 'boolean', renderCell: (p) => p.row.active ? 'Active' : 'Suspended' }
    ];

    const handleRowClick = (params) => {
        const user = params.row;
        setSelectedUser(user);
        setEditForm({
            email: user.email,
            first_name: user.first_name,
            last_name: user.last_name,
            department: user.department,
            role: user.role,
            admin: user.admin || false
        });
        setIsEditing(true);
        setDrawerOpen(true);
    };

    const handleSaveProfile = () => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const url = selectedUser.id ? `/admin/users/${selectedUser.id}.json` : '/admin/users.json';
        fetch(url, {
            method: selectedUser.id ? 'PATCH' : 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify({ user: editForm })
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify("Saved successfully.", "success");
                    setDrawerOpen(false);
                    fetchUsers();
                } else { notify(`Error: ${data.errors?.join(', ')}`, "error"); }
            });
    };

    const handleSaveGroups = (userId, groupIds) => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        fetch(`/admin/users/${userId}.json`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify({ user: { user_group_ids: groupIds } })
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify("Groups updated.", "success");
                    setGroupModalOpen(false);
                    fetchUsers();
                } else { notify("Error updating groups.", "error"); }
            });
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <Sidebar activeView="Users" onNavigate={(v) => navigateTo('/dashboard')} />

            <Box component="main" sx={{ flexGrow: 1, p: 3 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 2 }}>
                    <Box>
                        <Typography variant="h4" sx={{ fontWeight: 700 }}>System Users</Typography>
                        <Typography variant="body2" color="textSecondary">Manage employee access and group hierarchy.</Typography>
                    </Box>
                    <Button variant="contained" startIcon={<PersonAddOutlined />} onClick={() => { setSelectedUser({}); setEditForm({ email: '', first_name: '', last_name: '' }); setIsEditing(true); setDrawerOpen(true); }}>
                        Invite Local User
                    </Button>
                </Box>

                <Paper variant="outlined" sx={{ borderRadius: 3, height: 750, bgcolor: 'white' }}>
                    <DataGrid
                        rows={users}
                        columns={columns}
                        loading={loading}
                        // Pagination
                        paginationMode="server"
                        paginationModel={paginationModel}
                        onPaginationModelChange={setPaginationModel}
                        rowCount={totalCount}
                        pageSizeOptions={[25, 50, 100]}
                        // Toolbar
                        slots={{ toolbar: CustomToolbar }}
                        disableRowSelectionOnClick
                        onRowClick={handleRowClick}
                        sx={{ border: 'none', '& .MuiDataGrid-row:hover': { bgcolor: '#f1f5f9' } }}
                    />
                </Paper>
            </Box>

            <UserDrawer
                open={drawerOpen}
                user={selectedUser}
                isEditing={isEditing}
                editForm={editForm}
                setEditForm={setEditForm}
                onClose={() => setDrawerOpen(false)}
                onSave={handleSaveProfile}
                onOpenGroups={() => { setDrawerOpen(false); setGroupTargetUser(selectedUser); setGroupModalOpen(true); }}
                onToggleStatus={handleToggleStatus}
            />

            <GroupAssignmentModal
                open={groupModalOpen} user={groupTargetUser} allGroups={allGroups}
                onClose={() => setGroupModalOpen(false)} onSave={handleSaveGroups}
            />
        </Box>
    );
}