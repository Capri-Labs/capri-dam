import React, { useState, useEffect } from 'react';
import {
    Box, Grid, Paper, Typography, Button, TextField, List, ListItem,
    ListItemButton, ListItemText, ListItemIcon, Chip, Stack, Tab, Tabs,
    IconButton, Dialog, DialogTitle, DialogContent, DialogActions, Divider,
    CssBaseline, Toolbar, Alert
} from '@mui/material';
import {
    GroupWorkOutlined, PersonAddOutlined, DeleteOutlined,
    SubdirectoryArrowRight, AddCircleOutlined
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext'; // Using our global toast engine
import Sidebar from "../Sidebar";
import { navigateTo } from '../../utils/globalutils';

export default function UserGroupsManager() {
    const notify = useNotify();
    const [groups, setGroups] = useState([]);
    const [selectedGroup, setSelectedGroup] = useState(null);
    const [currentTab, setCurrentTab] = useState(0);
    const [loading, setLoading] = useState(true);
    const [activeView, setActiveView] = useState('User Groups');

    // Form States
    const [newUserEmail, setNewUserEmail] = useState('');
    const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
    const [newGroupForm, setNewGroupForm] = useState({ name: '', description: '', parent_id: null });

    useEffect(() => {
        fetchGroups();
    }, []);

    const fetchGroups = () => {
        setLoading(true);
        fetch('/admin/user_groups.json')
            .then(res => res.json())
            .then(data => {
                setGroups(data.user_groups || []);
                setLoading(false);
            })
            .catch(err => {
                console.error("Fetch error:", err); // Added console log for easier debugging
                notify("Failed to load user groups.", "error");
                setLoading(false);
            });
    };

    // --- GROUP CREATION LOGIC ---
    const handleOpenCreateModal = (parentId = null) => {
        setNewGroupForm({ name: '', description: '', parent_id: parentId });
        setIsCreateModalOpen(true);
    };

    const handleCreateGroup = () => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const payload = {
            user_group: {
                name: newGroupForm.name,
                description: newGroupForm.description
            },
            parent_id: newGroupForm.parent_id
        };

        // Add .json to the endpoint
        fetch('/admin/user_groups.json', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify(payload)
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify("Group created successfully.", "success");
                    setIsCreateModalOpen(false);
                    fetchGroups(); // This will now fetch the fresh JSON and update the UI!
                } else {
                    notify(`Error: ${data.errors?.join(', ')}`, "error");
                }
            });
    };

    // --- MEMBERSHIP LOGIC ---
    const handleAddUser = () => {
        if (!newUserEmail) return;

        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        fetch(`/admin/user_groups/${selectedGroup.id}/add_user`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify({ email: newUserEmail })
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    notify(data.message, "success");
                    setNewUserEmail('');
                    fetchGroups(); // Refresh to update member count
                } else {
                    notify(data.error, "warning");
                }
            });
    };

    // --- RECURSIVE TREE RENDERER ---
    // Builds the hierarchical list by finding children of a specific parent
    const renderGroupTree = (parentId = null, depth = 0) => {
        const children = groups.filter(g => g.parent_id === parentId);

        return children.map(group => (
            <React.Fragment key={group.id}>
                <ListItem disablePadding>
                    <ListItemButton
                        selected={selectedGroup?.id === group.id}
                        onClick={() => { setSelectedGroup(group); setCurrentTab(0); }}
                        sx={{ pl: 2 + (depth * 3), borderRadius: 1, mb: 0.5 }}
                    >
                        <ListItemIcon sx={{ minWidth: 36 }}>
                            {depth > 0 ? <SubdirectoryArrowRight fontSize="small" color="disabled" /> : <GroupWorkOutlined color="primary" />}
                        </ListItemIcon>
                        <ListItemText
                            primary={group.name}
                            primaryTypographyProps={{ fontWeight: selectedGroup?.id === group.id ? 700 : 500 }}
                        />
                        <Chip label={group.member_count} size="small" sx={{ height: 20, fontSize: '0.7rem' }} />
                    </ListItemButton>
                </ListItem>
                {/* Recursively render descendants */}
                {renderGroupTree(group.id, depth + 1)}
            </React.Fragment>
        ));
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <Sidebar activeView={activeView} onNavigate={(v) => v === 'System' ? null : navigateTo('/dashboard')} />

            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                <Toolbar />
                <Box sx={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    width: '100%', // Ensure it spans the full width
                }}>
                    {/* LEFT SIDE */}
                    <Box>
                        <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>User Groups</Typography>
                        <Typography variant="body2" color="textSecondary">Manage hierarchical access structures and team assignments.</Typography>
                    </Box>

                    {/* RIGHT SIDE */}
                    <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 2 }}>
                        <Button
                            variant="contained"
                            startIcon={<AddCircleOutlined />}
                            onClick={() => handleOpenCreateModal(null)}
                        >
                            New Root Group
                        </Button>
                    </Stack>
                </Box>

                <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
                    <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
                        <Grid container spacing={3} sx={{ height: '100%' }}>
                            {/* LEFT PANEL: Hierarchy Tree */}
                            <Grid item xs={12} md={4} lg={3} sx={{ height: '100%' }}>
                                <Paper variant="outlined" sx={{ p: 2, height: '100%', borderRadius: 3, overflowY: 'auto' }}>
                                    <Typography variant="subtitle2" sx={{ mb: 2, fontWeight: 700, color: 'text.secondary', textTransform: 'uppercase' }}>
                                        Organization Hierarchy
                                    </Typography>
                                    {loading ? (
                                        <Typography variant="body2" color="textSecondary">Loading hierarchy...</Typography>
                                    ) : (
                                        <List sx={{ pt: 0 }}>
                                            {renderGroupTree(null, 0)}
                                        </List>
                                    )}
                                </Paper>
                            </Grid>

                            {/* RIGHT PANEL: Group Management */}
                            <Grid item xs={12} md={8} lg={9}>
                                {selectedGroup ? (
                                    <Paper variant="outlined" sx={{ borderRadius: 3, height: '100%', display: 'flex', flexDirection: 'column' }}>
                                        {/* Header Area */}
                                        <Box sx={{ p: 3, borderBottom: '1px solid #e3e8ef', bgcolor: '#f8f9fa', borderRadius: '12px 12px 0 0' }}>
                                            <Typography variant="h5" sx={{ fontWeight: 700 }}>{selectedGroup.name}</Typography>
                                            <Typography variant="body2" color="textSecondary" sx={{ mb: 2 }}>{selectedGroup.description || 'No description provided.'}</Typography>

                                            <Button
                                                size="small"
                                                variant="outlined"
                                                startIcon={<SubdirectoryArrowRight />}
                                                onClick={() => handleOpenCreateModal(selectedGroup.id)}
                                            >
                                                Create Sub-Group Here
                                            </Button>
                                        </Box>

                                        <Tabs value={currentTab} onChange={(e, val) => setCurrentTab(val)} sx={{ px: 3, borderBottom: '1px solid #e3e8ef' }}>
                                            <Tab label={`Members (${selectedGroup.member_count})`} />
                                            <Tab label="Effective Roles (Inheritance)" />
                                        </Tabs>

                                        <Box sx={{ p: 3, flexGrow: 1, overflowY: 'auto' }}>
                                            {currentTab === 0 && (
                                                <Stack spacing={3}>
                                                    {/* Add User Bar */}
                                                    <Box sx={{ display: 'flex', gap: 2 }}>
                                                        <TextField
                                                            size="small"
                                                            fullWidth
                                                            placeholder="Enter user email to add..."
                                                            value={newUserEmail}
                                                            onChange={(e) => setNewUserEmail(e.target.value)}
                                                        />
                                                        <Button variant="contained" startIcon={<PersonAddOutlined />} onClick={handleAddUser} disableElevation>
                                                            Add Member
                                                        </Button>
                                                    </Box>

                                                    <Divider />

                                                    {/* Member List - (In a real app, you'd fetch the user list for this group.
                                             For this UI mock, we assume the API provides a users array inside the group object) */}
                                                    <List>
                                                        <ListItem
                                                            secondaryAction={
                                                                <IconButton edge="end" color="error"><DeleteOutlined /></IconButton>
                                                            }
                                                            sx={{ border: '1px solid #eee', borderRadius: 2, mb: 1 }}
                                                        >
                                                            <ListItemText primary="Example User" secondary="example@aldi.com" />
                                                        </ListItem>
                                                    </List>
                                                </Stack>
                                            )}

                                            {currentTab === 1 && (
                                                <Box>
                                                    <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 1 }}>Inheritance Chain</Typography>
                                                    <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                                                        This group automatically inherits access policies from its parent groups.
                                                        Folder-level access is managed directly inside the Asset Browser by right-clicking a folder.
                                                    </Typography>
                                                    <Alert severity="info" sx={{ borderRadius: 2 }}>
                                                        Advanced Effective Permissions calculation matrix will be displayed here in v2.
                                                    </Alert>
                                                </Box>
                                            )}
                                        </Box>
                                    </Paper>
                                ) : (
                                    <Paper variant="outlined" sx={{ borderRadius: 3, height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', bgcolor: '#f8f9fa' }}>
                                        <Box sx={{ p: 3, textAlign: 'center', bgcolor: '#f8f9fa' }}>
                                            <GroupWorkOutlined sx={{ fontSize: 64, color: '#ccc', mb: 2 }} />
                                            <Typography variant="h6" color="textSecondary">Select a group to manage</Typography>
                                            <Typography variant="body2" color="textSecondary">Choose a group from the hierarchy tree on the left.</Typography>
                                        </Box>
                                    </Paper>
                                )}
                            </Grid>
                        </Grid>
                    </Stack>
                </Paper>
            </Box>

            {/* Create Group Modal */}
            <Dialog open={isCreateModalOpen} onClose={() => setIsCreateModalOpen(false)} maxWidth="sm" fullWidth>
                <DialogTitle sx={{ fontWeight: 700 }}>
                    {newGroupForm.parent_id ? 'Create Nested Sub-Group' : 'Create Root Group'}
                </DialogTitle>
                <DialogContent dividers>
                    <Stack spacing={3} sx={{ mt: 1 }}>
                        <TextField
                            label="Group Name"
                            fullWidth
                            required
                            value={newGroupForm.name}
                            onChange={(e) => setNewGroupForm({ ...newGroupForm, name: e.target.value })}
                        />
                        <TextField
                            label="Description"
                            fullWidth
                            multiline rows={3}
                            value={newGroupForm.description}
                            onChange={(e) => setNewGroupForm({ ...newGroupForm, description: e.target.value })}
                        />
                    </Stack>
                </DialogContent>
                <DialogActions sx={{ p: 2 }}>
                    <Button onClick={() => setIsCreateModalOpen(false)}>Cancel</Button>
                    <Button variant="contained" onClick={handleCreateGroup} disabled={!newGroupForm.name}>Create Group</Button>
                </DialogActions>
            </Dialog>
        </Box>
    );
}