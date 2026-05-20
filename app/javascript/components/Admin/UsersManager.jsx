import React, { useState, useEffect } from 'react';
import {
    Box, Paper, Typography, Button, TextField, Table, TableBody,
    TableCell, TableHead, TableRow, Chip, Drawer, Stack, IconButton,
    Divider, Alert, Avatar, CssBaseline, Toolbar
} from '@mui/material';
import {
    PersonAddOutlined, Close, Security, VpnKey, Block, CheckCircleOutlined
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';
import Sidebar from "../Sidebar";
import {navigateTo} from "../../utils/globalutils";

export default function UsersManager() {
    const notify = useNotify();
    const [users, setUsers] = useState([]);
    const [loading, setLoading] = useState(true);
    const [activeView, setActiveView] = useState('Users');

    // Drawer & Form State
    const [drawerOpen, setDrawerOpen] = useState(false);
    const [selectedUser, setSelectedUser] = useState(null);
    const [isEditing, setIsEditing] = useState(false);
    const [editForm, setEditForm] = useState({
        email: '', first_name: '', last_name: '', department: '', role: ''
    });

    useEffect(() => {
        fetchUsers();
    }, []);

    const fetchUsers = () => {
        setLoading(true);
        fetch('/admin/users.json')
            .then(res => res.json())
            .then(data => {
                setUsers(data.users || []);
                setLoading(false);
            })
            .catch(() => {
                notify("Failed to load user directory.", "error");
                setLoading(false);
            });
    };

    const handleRowClick = (user) => {
        setSelectedUser(user);
        setEditForm({
            email: user.email || '',
            first_name: user.first_name || '',
            last_name: user.last_name || '',
            department: user.department || '',
            role: user.role || ''
        });
        setIsEditing(false);
        setDrawerOpen(true);
    };

    const handleToggleStatus = () => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        fetch(`/admin/users/${selectedUser.id}/toggle_status.json`, {
            method: 'POST',
            headers: { 'X-CSRF-Token': csrfToken }
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify(data.message, selectedUser.active ? "warning" : "success");
                    setDrawerOpen(false);
                    fetchUsers();
                } else {
                    notify("Failed to change user status.", "error");
                }
            });
    };

    const handleSaveChanges = () => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const method = selectedUser.id ? 'PATCH' : 'POST';
        const url = selectedUser.id ? `/admin/users/${selectedUser.id}.json` : '/admin/users.json';

        fetch(url, {
            method: method,
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify({ user: editForm })
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify(data.message || "Saved successfully.", "success");
                    setDrawerOpen(false);
                    fetchUsers();
                } else {
                    notify(`Error: ${data.errors?.join(', ')}`, "error");
                }
            });
    };

    const openCreateDrawer = () => {
        setSelectedUser({});
        setEditForm({ email: '', first_name: '', last_name: '', department: '', role: '' });
        setIsEditing(true);
        setDrawerOpen(true);
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <Sidebar activeView={activeView} onNavigate={(v) => v === 'System' ? null : navigateTo('/dashboard')} />

            <Box component="main" sx={{ flexGrow: 1, p: 3 }}>
                <Toolbar/>
                <Box sx={{ width: '100%', p: 1 }}>
                    <Box sx={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        width: '100%', // Ensure it spans the full width
                    }}>
                        {/* LEFT SIDE */}
                        <Box>
                            <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>System Users</Typography>
                            <Typography variant="body2" color="textSecondary">Manage employee access, inspect origin identities, and handle account lifecycles.</Typography>
                        </Box>

                        {/* RIGHT SIDE */}
                        <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 2 }}>
                            <Button variant="contained" startIcon={<PersonAddOutlined />} onClick={openCreateDrawer}>
                                Invite Local User
                            </Button>
                        </Stack>
                    </Box>
                </Box>


                <Paper variant="outlined" sx={{ borderRadius: 3, overflow: 'hidden', marginTop: 1 }}>
                    <Table>
                        <TableHead sx={{ bgcolor: '#f8f9fa' }}>
                            <TableRow>
                                <TableCell sx={{ fontWeight: 600 }}>Profile</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Identity Origin</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Department & Role</TableCell>
                                <TableCell sx={{ fontWeight: 600 }}>Status</TableCell>
                            </TableRow>
                        </TableHead>
                        <TableBody>
                            {users.map((user) => (
                                <TableRow
                                    key={user.id}
                                    hover
                                    onClick={() => handleRowClick(user)}
                                    sx={{ cursor: 'pointer', '&:hover': { bgcolor: '#f1f5f9' } }}
                                >
                                    <TableCell>
                                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                                            <Avatar src={user.avatar_url} sx={{ width: 40, height: 40, bgcolor: 'primary.main' }}>
                                                {user.display_name.charAt(0).toUpperCase()}
                                            </Avatar>
                                            <Box>
                                                <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>{user.display_name}</Typography>
                                                <Typography variant="caption" color="textSecondary">{user.email}</Typography>
                                            </Box>
                                        </Box>
                                    </TableCell>
                                    <TableCell>
                                        {user.sso_managed ? (
                                            <Chip icon={<Security sx={{ fontSize: 16 }} />} label={user.provider} size="small" color="primary" variant="outlined" sx={{ textTransform: 'capitalize' }} />
                                        ) : (
                                            <Chip icon={<VpnKey sx={{ fontSize: 16 }} />} label="Local Account" size="small" color="default" variant="outlined" />
                                        )}
                                    </TableCell>
                                    <TableCell>
                                        <Typography variant="body2">{user.department || '—'}</Typography>
                                        <Typography variant="caption" color="textSecondary">{user.role || 'No role defined'}</Typography>
                                    </TableCell>
                                    <TableCell>
                                        {user.active
                                            ? <Chip label="Active" size="small" color="success" sx={{ height: 20, fontSize: '0.7rem' }} />
                                            : <Chip label="Suspended" size="small" color="error" sx={{ height: 20, fontSize: '0.7rem' }} />
                                        }
                                    </TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                </Paper>
            </Box>



            <Drawer anchor="right" open={drawerOpen} onClose={() => setDrawerOpen(false)}>
                <Box sx={{ width: 450, p: 3, display: 'flex', flexDirection: 'column', height: '100%' }}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
                        <Typography variant="h6" sx={{ fontWeight: 700 }}>
                            {selectedUser?.id ? 'User Profile' : 'Create New User'}
                        </Typography>
                        <IconButton onClick={() => setDrawerOpen(false)}><Close /></IconButton>
                    </Box>

                    {selectedUser?.id && (
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 4, p: 2, bgcolor: '#f8f9fa', borderRadius: 2 }}>
                            <Avatar src={selectedUser.avatar_url} sx={{ width: 64, height: 64 }} />
                            <Box>
                                <Typography variant="h6" sx={{ fontWeight: 700, lineHeight: 1.2 }}>{selectedUser.display_name}</Typography>
                                <Typography variant="body2" color="textSecondary">{selectedUser.email}</Typography>
                            </Box>
                        </Box>
                    )}

                    {selectedUser?.sso_managed && (
                        <Alert severity="info" sx={{ mb: 3, borderRadius: 2 }}>
                            This account is synchronized via <strong>{selectedUser.provider}</strong>. Identity fields cannot be modified locally.
                        </Alert>
                    )}

                    <Stack spacing={3} sx={{ flexGrow: 1 }}>
                        <Box sx={{ display: 'flex', gap: 2 }}>
                            <TextField
                                label="First Name" fullWidth
                                value={editForm.first_name}
                                onChange={(e) => setEditForm({ ...editForm, first_name: e.target.value })}
                                disabled={!isEditing || selectedUser?.sso_managed}
                            />
                            <TextField
                                label="Last Name" fullWidth
                                value={editForm.last_name}
                                onChange={(e) => setEditForm({ ...editForm, last_name: e.target.value })}
                                disabled={!isEditing || selectedUser?.sso_managed}
                            />
                        </Box>

                        <TextField
                            label="Email Address" fullWidth
                            value={editForm.email}
                            onChange={(e) => setEditForm({ ...editForm, email: e.target.value })}
                            disabled={!isEditing || selectedUser?.sso_managed}
                        />

                        <Box sx={{ display: 'flex', gap: 2 }}>
                            <TextField
                                label="Department" fullWidth
                                value={editForm.department}
                                onChange={(e) => setEditForm({ ...editForm, department: e.target.value })}
                                disabled={!isEditing}
                            />
                            <TextField
                                label="Job Role" fullWidth
                                value={editForm.role}
                                onChange={(e) => setEditForm({ ...editForm, role: e.target.value })}
                                disabled={!isEditing}
                            />
                        </Box>

                        {selectedUser?.id && (
                            <>
                                <Divider />
                                <Box>
                                    <Typography variant="subtitle2" sx={{ mb: 1, color: 'text.secondary' }}>Assigned Access Groups</Typography>
                                    <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
                                        {selectedUser.groups?.map(g => <Chip key={g} label={g} size="small" color="primary" variant="outlined" />)}
                                        {(!selectedUser.groups || selectedUser.groups.length === 0) && (
                                            <Typography variant="caption" color="textSecondary">No active group memberships.</Typography>
                                        )}
                                    </Box>
                                </Box>
                            </>
                        )}
                    </Stack>

                    <Divider sx={{ my: 2 }} />

                    <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                        {selectedUser?.id ? (
                            <>
                                <Button
                                    color={selectedUser.active ? "error" : "success"}
                                    startIcon={selectedUser.active ? <Block /> : <CheckCircleOutlined />}
                                    onClick={handleToggleStatus}
                                >
                                    {selectedUser.active ? 'Suspend Access' : 'Restore Access'}
                                </Button>

                                {!isEditing ? (
                                    <Button variant="outlined" onClick={() => setIsEditing(true)}>Edit Details</Button>
                                ) : (
                                    <Button variant="contained" onClick={handleSaveChanges}>Save Changes</Button>
                                )}
                            </>
                        ) : (
                            <Button variant="contained" fullWidth onClick={handleSaveChanges}>
                                Provision Local Account
                            </Button>
                        )}
                    </Box>
                </Box>
            </Drawer>
        </Box>
    );
}