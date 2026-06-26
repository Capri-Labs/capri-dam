import React, { useState } from 'react';
import {
    AppBar, Toolbar, Button, Box, Typography,
    IconButton, Avatar, Menu, MenuItem, ListItemIcon, Divider, Tooltip, Chip
} from '@mui/material';
import {
    Logout, Settings, Add, Person,
    CloudUpload, AccountTree, HelpOutlined, SupervisedUserCircle
} from '@mui/icons-material';

import NotificationBell from '../NotificationBell';
import GlobalSearchBar from '../Search/GlobalSearchBar';
import ImpersonationBanner from './ImpersonationBanner';
import ImpersonateUserDialog from './ImpersonateUserDialog';

export default function Header(props) {
    const [profileAnchorEl, setProfileAnchorEl] = useState(null);
    const [createAnchorEl, setCreateAnchorEl]   = useState(null);
    const [impersonateOpen, setImpersonateOpen] = useState(false);

    // Impersonation state from Rails data attributes
    const impersonating    = props.impersonating === true || props.impersonating === 'true';
    const isAdmin          = props.isAdmin === true || props.isAdmin === 'true';
    const isSuperAdmin     = props.isSuperAdmin === true || props.isSuperAdmin === 'true';
    const canImpersonate   = (isAdmin || isSuperAdmin) && !impersonating;

    const impersonatedUser = (() => {
        try {
            return props.impersonatedUser && props.impersonatedUser !== 'null'
                ? JSON.parse(props.impersonatedUser) : null;
        } catch { return null; }
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

                    {/* LOGO */}
                    <Box
                        component="img"
                        src="/images/logo.png"
                        alt="Capri DAM Logo"
                        sx={{
                            height: 64, width: 'auto', cursor: 'pointer',
                            boxShadow: 2, borderRadius: '4px', transition: 'transform 0.2s',
                            '&:hover': { transform: 'scale(1.05)', boxShadow: 4 },
                        }}
                        onClick={() => window.location.href = '/dashboard'}
                    />

                    {/* CENTER SEARCH */}
                    <Box sx={{ flexGrow: 1, display: 'flex', justifyContent: 'center', px: 2 }}>
                        {props.isSignedIn && <GlobalSearchBar />}
                    </Box>

                    {/* RIGHT — actions */}
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        {props.isSignedIn && (
                            <>
                                {/* Active impersonation chip */}
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

                                {/* Quick Add */}
                                <Tooltip title="Create New…">
                                    <Button
                                        variant="contained" color="primary" size="small"
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
                                    slotProps={{ paper: { elevation: 3, sx: { mt: 1.5, minWidth: 200, borderRadius: 2 } } }}
                                >
                                    <MenuItem onClick={() => setCreateAnchorEl(null)}>
                                        <ListItemIcon><CloudUpload fontSize="small" color="primary" /></ListItemIcon>
                                        Upload Asset
                                    </MenuItem>
                                    <MenuItem onClick={() => setCreateAnchorEl(null)}>
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

                                {/* Profile Avatar */}
                                <Tooltip title={impersonating
                                    ? `Acting as ${impersonatedUser?.display_name}`
                                    : 'Account settings'
                                }>
                                    <IconButton
                                        onClick={(e) => setProfileAnchorEl(e.currentTarget)}
                                        size="small" sx={{ ml: 1 }}
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
                                    slotProps={{ paper: { elevation: 3, sx: { mt: 1.5, minWidth: 240, borderRadius: 2 } } }}
                                    transformOrigin={{ horizontal: 'right', vertical: 'top' }}
                                    anchorOrigin={{ horizontal: 'right', vertical: 'bottom' }}
                                >
                                    {/* User identity header */}
                                    <Box sx={{ px: 2, py: 1.5 }}>
                                        <Typography variant="subtitle2" fontWeight="bold" color="text.primary">
                                            {props.userName || 'System User'}
                                        </Typography>
                                        <Typography variant="body2" color="text.secondary">
                                            {impersonating ? '⚠️ Impersonation active' : 'Active Session'}
                                        </Typography>
                                    </Box>

                                    <Divider />

                                    {/* My Profile */}
                                    <MenuItem onClick={() => {
                                        setProfileAnchorEl(null);
                                        window.location.href = '/profile';
                                    }}>
                                        <ListItemIcon><Person fontSize="small" /></ListItemIcon>
                                        My Profile
                                    </MenuItem>

                                    {/* ── Impersonate User — only for admins/super-admins ── */}
                                    {canImpersonate && (
                                        <MenuItem
                                            onClick={() => {
                                                setProfileAnchorEl(null);
                                                setImpersonateOpen(true);
                                            }}
                                            sx={{
                                                color: 'warning.dark',
                                                '&:hover': { bgcolor: '#fffbeb' },
                                            }}
                                        >
                                            <ListItemIcon>
                                                <SupervisedUserCircle fontSize="small" sx={{ color: 'warning.main' }} />
                                            </ListItemIcon>
                                            Impersonate User
                                        </MenuItem>
                                    )}

                                    <MenuItem onClick={() => {
                                        setProfileAnchorEl(null);
                                        window.location.href = '/settings';
                                    }}>
                                        <ListItemIcon><Settings fontSize="small" /></ListItemIcon>
                                        System Settings
                                    </MenuItem>

                                    <Divider />

                                    <MenuItem onClick={handleLogout} sx={{ color: 'error.main' }}>
                                        <ListItemIcon>
                                            {/* inline SVG logout icon to avoid unused import */}
                                            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"
                                                viewBox="0 0 24 24" fill="currentColor" style={{ color: '#d32f2f' }}>
                                                <path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5-5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/>
                                            </svg>
                                        </ListItemIcon>
                                        Sign Out
                                    </MenuItem>
                                </Menu>
                            </>
                        )}
                    </Box>
                </Toolbar>
            </AppBar>

            {/* Impersonate User Dialog */}
            {canImpersonate && (
                <ImpersonateUserDialog
                    open={impersonateOpen}
                    onClose={() => setImpersonateOpen(false)}
                />
            )}
        </>
    );
}