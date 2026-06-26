import React, { useState } from 'react';
import {
    AppBar, Toolbar, Button, Box, Typography,
    IconButton, Avatar, Menu, MenuItem, ListItemIcon, Divider, Tooltip, Chip
} from '@mui/material';
import {
    Logout, Login, Settings, Add, Person,
    CloudUpload, AccountTree, HelpOutlined, SupervisedUserCircle
} from '@mui/icons-material';

import NotificationBell from '../NotificationBell';
import GlobalSearchBar from '../Search/GlobalSearchBar';
import ImpersonationBanner from './ImpersonationBanner';

export default function Header(props) {
    const [profileAnchorEl, setProfileAnchorEl] = useState(null);
    const [createAnchorEl, setCreateAnchorEl] = useState(null);

    // Impersonation state from Rails data attributes
    const impersonating   = props.impersonating === true || props.impersonating === 'true';
    const impersonatedUser = (() => {
        try { return props.impersonatedUser && props.impersonatedUser !== 'null'
                ? JSON.parse(props.impersonatedUser) : null; }
        catch { return null; }
    })();

    const handleLogout = () => {
        fetch('/users/sign_out', {
            method: 'DELETE',
            headers: {
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                'Content-Type': 'application/json'
            }
        }).then(() => window.location.href = '/');
    };

    const getInitials = (name) => {
        if (!name) return 'U';
        return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    };

    // Push AppBar down when impersonation banner is active (banner = 40px)
    const bannerOffset = impersonating ? '40px' : '0px';

    return (
        <>
            {/* Impersonation banner — rendered ABOVE the AppBar */}
            {impersonating && impersonatedUser && (
                <ImpersonationBanner
                    impersonatedUser={impersonatedUser}
                    trueUserName={props.trueUserName}
                />
            )}

            <AppBar
                position="fixed"
                elevation={0}
                sx={{
                    top: bannerOffset,
                    zIndex: (theme) => theme.zIndex.drawer + 1,
                    bgcolor: impersonating ? '#fff3cd' : '#ffffff',
                    borderBottom: impersonating ? '2px solid #f59e0b' : '1px solid #e2e8f0',
                    color: '#1e293b',
                    transition: 'top 0.2s ease, background-color 0.2s ease',
                }}
            >
                <Toolbar sx={{ display: 'flex', justifyContent: 'space-between', minHeight: '64px' }}>

                    {/* 1. LOGO */}
                    <Box
                        component="img"
                        src="/images/logo.png"
                        alt="Capri DAM Logo"
                        sx={{
                            height: 64,
                            width: 'auto',
                            cursor: 'pointer',
                            boxShadow: 2,
                            borderRadius: '4px',
                            transition: 'transform 0.2s',
                            '&:hover': { transform: 'scale(1.05)', boxShadow: 4 },
                        }}
                        onClick={() => window.location.href = '/dashboard'}
                    />

                    {/* 2. CENTER SEARCH BAR */}
                    <Box sx={{ flexGrow: 1, display: 'flex', justifyContent: 'center', px: 2 }}>
                        {props.isSignedIn && <GlobalSearchBar />}
                    </Box>

                    {/* 3. USER ACTIONS */}
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        {props.isSignedIn && (
                            <>
                                {/* Impersonation indicator chip */}
                                {impersonating && impersonatedUser && (
                                    <Chip
                                        icon={<SupervisedUserCircle sx={{ fontSize: 16 }} />}
                                        label={`Acting as ${impersonatedUser.display_name}`}
                                        size="small"
                                        color="warning"
                                        variant="outlined"
                                        sx={{ fontWeight: 600, fontSize: '0.7rem' }}
                                    />
                                )}

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
                                    <MenuItem onClick={() => {}}>
                                        <ListItemIcon><CloudUpload fontSize="small" color="primary" /></ListItemIcon>
                                        Upload Asset
                                    </MenuItem>
                                    <MenuItem onClick={() => {}}>
                                        <ListItemIcon><AccountTree fontSize="small" color="success" /></ListItemIcon>
                                        Start Workflow
                                    </MenuItem>
                                </Menu>

                                <Tooltip title="Help & Support">
                                    <IconButton size="large" sx={{ color: '#64748b' }}>
                                        <HelpOutlined />
                                    </IconButton>
                                </Tooltip>

                                <NotificationBell />

                                <Divider orientation="vertical" flexItem sx={{ mx: 1, my: 1.5 }} />

                                {/* User Profile Avatar Dropdown */}
                                <Tooltip title={impersonating ? `Acting as ${impersonatedUser?.display_name}` : 'Account settings'}>
                                    <IconButton
                                        onClick={(e) => setProfileAnchorEl(e.currentTarget)}
                                        size="small"
                                        sx={{ ml: 1 }}
                                    >
                                        <Avatar sx={{
                                            width: 36, height: 36,
                                            bgcolor: impersonating ? '#f59e0b' : '#3b82f6',
                                            fontSize: '0.9rem', fontWeight: 600,
                                        }}>
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
                                            {impersonating ? '⚠️ Impersonation active' : 'Active Session'}
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
        </>
    );
}