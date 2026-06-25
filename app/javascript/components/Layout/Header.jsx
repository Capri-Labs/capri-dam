import React, { useState } from 'react';
import {
    AppBar, Toolbar, Button, Box, Typography,
    IconButton, Avatar, Menu, MenuItem, ListItemIcon, Divider, Tooltip
} from '@mui/material';
import {
    Logout, Login, Settings, Add, Person,
    CloudUpload, AccountTree, HelpOutlined
} from '@mui/icons-material';

import NotificationBell from '../NotificationBell';
import GlobalSearchBar from '../Search/GlobalSearchBar';

export default function Header(props) {
    // Menu States
    const [profileAnchorEl, setProfileAnchorEl] = useState(null);
    const [createAnchorEl, setCreateAnchorEl] = useState(null);

    const handleLogout = () => {
        fetch('/users/sign_out', {
            method: 'DELETE',
            headers: {
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                'Content-Type': 'application/json'
            }
        }).then(() => window.location.href = '/');
    };

    // Helper to extract initials for the Avatar
    const getInitials = (name) => {
        if (!name) return 'U';
        return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    };

    return (
        <AppBar
            position="fixed"
            elevation={0}
            sx={{
                zIndex: (theme) => theme.zIndex.drawer + 1,
                bgcolor: '#ffffff',
                borderBottom: '1px solid #e2e8f0',
                color: '#1e293b'
            }}
        >
            <Toolbar sx={{ display: 'flex', justifyContent: 'space-between', minHeight: '64px' }}>

                {/* 1. LOGO */}
                <Box
                    component="img"
                    src="/images/logo.png" // You would use the transparent asset src
                    alt="Capri DAM Logo"
                    sx={{
                        height: 64, //
                        width: 'auto', //
                        cursor: 'pointer', //
                        // Add styles for better integration
                        boxShadow: 2, // Subtle drop shadow for depth
                        borderRadius: '4px', // Slightly rounded corners
                        transition: 'transform 0.2s', // Smooth transition on hover
                        '&:hover': {
                            transform: 'scale(1.05)', // Gently scale up on hover
                            boxShadow: 4, // Increase shadow on hover
                        },
                    }}
                    onClick={() => window.location.href = '/dashboard'} //
                />

                {/* 2. CENTER SEARCH BAR */}
                <Box sx={{ flexGrow: 1, display: 'flex', justifyContent: 'center', px: 2 }}>
                    {props.isSignedIn && (
                        <GlobalSearchBar /> /* <-- 2. Render it cleanly */
                    )}
                </Box>

                {/* 3. USER ACTIONS & NAVIGATION */}
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    {props.isSignedIn && (
                        <>
                            {/* Quick Add Menu */}
                            <Tooltip title="Create New...">
                                <Button
                                    variant="contained"
                                    color="primary"
                                    size="small"
                                    startIcon={<Add />}
                                    onClick={(e) => setCreateAnchorEl(e.currentTarget)}
                                    sx={{ mr: 1, textTransform: 'none', borderRadius: '8px', boxShadow: 'none' }}
                                >
                                    New
                                </Button>
                            </Tooltip>

                            <Menu
                                anchorEl={createAnchorEl}
                                open={Boolean(createAnchorEl)}
                                onClose={() => setCreateAnchorEl(null)}
                                PaperProps={{ elevation: 3, sx: { mt: 1.5, minWidth: 200, borderRadius: 2 } }}
                            >
                                <MenuItem onClick={() => { /* Implement Upload Trigger */ }}>
                                    <ListItemIcon><CloudUpload fontSize="small" color="primary" /></ListItemIcon>
                                    Upload Asset
                                </MenuItem>
                                <MenuItem onClick={() => { /* Implement Workflow Trigger */ }}>
                                    <ListItemIcon><AccountTree fontSize="small" color="success" /></ListItemIcon>
                                    Start Workflow
                                </MenuItem>
                            </Menu>

                            {/* Help & Documentation */}
                            <Tooltip title="Help & Support">
                                <IconButton size="large" sx={{ color: '#64748b' }}>
                                    <HelpOutlined />
                                </IconButton>
                            </Tooltip>

                            {/* Notification Engine */}
                            <NotificationBell />

                            <Divider orientation="vertical" flexItem sx={{ mx: 1, my: 1.5 }} />

                            {/* User Profile Avatar Dropdown */}
                            <Tooltip title="Account settings">
                                <IconButton
                                    onClick={(e) => setProfileAnchorEl(e.currentTarget)}
                                    size="small"
                                    sx={{ ml: 1 }}
                                >
                                    <Avatar sx={{ width: 36, height: 36, bgcolor: '#3b82f6', fontSize: '0.9rem', fontWeight: 600 }}>
                                        {getInitials(props.userName)}
                                    </Avatar>
                                </IconButton>
                            </Tooltip>

                            <Menu
                                anchorEl={profileAnchorEl}
                                open={Boolean(profileAnchorEl)}
                                onClose={() => setProfileAnchorEl(null)}
                                PaperProps={{ elevation: 3, sx: { mt: 1.5, minWidth: 220, borderRadius: 2 } }}
                                transformOrigin={{ horizontal: 'right', vertical: 'top' }}
                                anchorOrigin={{ horizontal: 'right', vertical: 'bottom' }}
                            >
                                <Box sx={{ px: 2, py: 1.5 }}>
                                    <Typography variant="subtitle2" fontWeight="bold" color="text.primary">
                                        {props.userName || 'System User'}
                                    </Typography>
                                    <Typography variant="body2" color="text.secondary">
                                        Active Session
                                    </Typography>
                                </Box>
                                <Divider />
                                <MenuItem onClick={() => window.location.href = '/profile'}>
                                    <ListItemIcon><Person fontSize="small" /></ListItemIcon>
                                    My Profile
                                </MenuItem>
                                <MenuItem onClick={() => window.location.href = '/settings'}>
                                    <ListItemIcon><Settings fontSize="small" /></ListItemIcon>
                                    System Settings
                                </MenuItem>
                                <Divider />
                                <MenuItem onClick={handleLogout} sx={{ color: 'error.main' }}>
                                    <ListItemIcon><Logout fontSize="small" color="error" /></ListItemIcon>
                                    Sign Out
                                </MenuItem>
                            </Menu>
                        </>
                    )}
                </Box>
            </Toolbar>
        </AppBar>
    );
}