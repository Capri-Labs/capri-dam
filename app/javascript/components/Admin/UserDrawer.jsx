import React from 'react';
import {
    Box, Typography, Button, TextField, Chip, Drawer, Stack, IconButton,
    Divider, Alert, Avatar, Switch, FormControlLabel
} from '@mui/material';
import { Close, Block, CheckCircleOutlined, GroupAdd } from '@mui/icons-material';

export default function UserDrawer({ open, user, isEditing, editForm, setEditForm, onClose, onSave, onToggleStatus, onOpenGroups }) {
    if (!user) return null;

    return (
        <Drawer anchor="right" open={open} onClose={onClose}>
            <Box sx={{ width: 450, p: 3, display: 'flex', flexDirection: 'column', height: '100%' }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
                    <Typography variant="h6" sx={{ fontWeight: 700 }}>
                        {user.id ? 'User Profile' : 'Invite New User'}
                    </Typography>
                    <IconButton onClick={onClose}><Close /></IconButton>
                </Box>

                {user.id && (
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 4, p: 2, bgcolor: '#f8f9fa', borderRadius: 2 }}>
                        <Avatar src={user.avatar_url} sx={{ width: 64, height: 64 }} />
                        <Box>
                            <Typography variant="h6" sx={{ fontWeight: 700, lineHeight: 1.2 }}>{user.display_name}</Typography>
                            <Typography variant="body2" color="textSecondary">{user.email}</Typography>
                        </Box>
                    </Box>
                )}

                {user.sso_managed && (
                    <Alert severity="info" sx={{ mb: 3, borderRadius: 2 }}>
                        Synchronized via <strong>{user.provider}</strong>. Identity fields cannot be modified locally.
                    </Alert>
                )}

                <Stack spacing={3} sx={{ flexGrow: 1 }}>
                    <Box sx={{ display: 'flex', gap: 2 }}>
                        <TextField
                            label="First Name" fullWidth value={editForm.first_name}
                            onChange={(e) => setEditForm({ ...editForm, first_name: e.target.value })}
                            disabled={!isEditing || user.sso_managed}
                        />
                        <TextField
                            label="Last Name" fullWidth value={editForm.last_name}
                            onChange={(e) => setEditForm({ ...editForm, last_name: e.target.value })}
                            disabled={!isEditing || user.sso_managed}
                        />
                    </Box>

                    <TextField
                        label="Email Address" fullWidth value={editForm.email}
                        onChange={(e) => setEditForm({ ...editForm, email: e.target.value })}
                        disabled={!isEditing || user.sso_managed}
                    />

                    <Box sx={{ display: 'flex', gap: 2 }}>
                        <TextField
                            label="Department" fullWidth value={editForm.department}
                            onChange={(e) => setEditForm({ ...editForm, department: e.target.value })}
                            disabled={!isEditing}
                        />
                        <TextField
                            label="Job Role" fullWidth value={editForm.role}
                            onChange={(e) => setEditForm({ ...editForm, role: e.target.value })}
                            disabled={!isEditing}
                        />
                    </Box>

                    <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', p: 1, bgcolor: '#fbfcfe', borderRadius: 2 }}>
                        <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>System Administrator</Typography>
                        <FormControlLabel
                            control={
                                <Switch
                                    checked={editForm.admin || false}
                                    onChange={(e) => setEditForm({ ...editForm, admin: e.target.checked })}
                                    disabled={!isEditing}
                                    color="primary"
                                />
                            }
                            label={editForm.admin ? "Enabled" : "Disabled"}
                        />
                    </Box>

                    {user.id && (
                        <>
                            <Divider />
                            <Box>
                                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                                    <Typography variant="subtitle2" color="text.secondary">Assigned Access Groups</Typography>
                                    <Button size="small" startIcon={<GroupAdd />} onClick={onOpenGroups}>
                                        Manage
                                    </Button>
                                </Box>
                                <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
                                    {user.groups?.map(g => <Chip key={g} label={g} size="small" color="primary" variant="outlined" />)}
                                    {(!user.groups || user.groups.length === 0) && (
                                        <Typography variant="caption" color="textSecondary">No active group memberships.</Typography>
                                    )}
                                </Box>
                            </Box>
                        </>
                    )}
                </Stack>

                <Divider sx={{ my: 2 }} />

                <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                    {user.id ? (
                        <>
                            <Button
                                color={user.active ? "error" : "success"}
                                startIcon={user.active ? <Block /> : <CheckCircleOutlined />}
                                onClick={async () => {
                                    // Trigger the backend toggle
                                    await onToggleStatus();
                                    // Force the drawer to close after the action
                                    onClose();
                                }}
                            >
                                {user.active ? 'Suspend Access' : 'Restore Access'}
                            </Button>
                            <Button variant="contained" onClick={onSave} disabled={!isEditing}>Save Changes</Button>
                        </>
                    ) : (
                        <Button variant="contained" fullWidth onClick={onSave}>
                            Provision Local Account
                        </Button>
                    )}
                </Box>
            </Box>
        </Drawer>
    );
}