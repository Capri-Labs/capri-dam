import React, { useState } from 'react';
import {
    AppBar, Toolbar, Button, Box, InputBase, styled, Typography,
    IconButton, Avatar, Menu, MenuItem, ListItemIcon, Divider, Tooltip
} from '@mui/material';
import {
    Logout, Search as SearchIcon, Login, Settings,
    Add, Person, CloudUpload, AccountTree, HelpOutlined
} from '@mui/icons-material';

import NotificationBell from './NotificationBell';

// 1. Search Bar Styled for a White Header (Light Gray Background, Dark Text)
const SearchContainer = styled('div')(({ theme }) => ({
    position: 'relative',
    borderRadius: '8px',
    backgroundColor: '#f1f5f9', // Slate 100
    '&:hover': {
        backgroundColor: '#e2e8f0', // Slate 200
    },
    marginRight: theme.spacing(2),
    marginLeft: 0,
    width: '100%',
    transition: 'background-color 0.2s ease',
    [theme.breakpoints.up('sm')]: {
        marginLeft: theme.spacing(3),
        width: 'auto',
    },
}));

const SearchIconWrapper = styled('div')(({ theme }) => ({
    padding: theme.spacing(0, 2),
    height: '100%',
    position: 'absolute',
    pointerEvents: 'none',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: '#64748b' // Slate 500
}));

const StyledInputBase = styled(InputBase)(({ theme }) => ({
    color: '#1e293b', // Slate 800 text
    fontWeight: 500,
    '& .MuiInputBase-input': {
        padding: theme.spacing(1, 1, 1, 0),
        paddingLeft: `calc(1em + ${theme.spacing(4)})`,
        transition: theme.transitions.create('width'),
        width: '100%',
        [theme.breakpoints.up('md')]: {
            width: '45ch',
        },
        '&::placeholder': {
            color: '#94a3b8',
            opacity: 1,
        }
    },
}));

export default function Header(props) {
    const [searchQuery, setSearchQuery] = useState('');

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

    const handleSearchSubmit = (e) => {
        if (e.key === 'Enter' && searchQuery.trim() !== '') {
            window.location.href = `/dashboard?search=${encodeURIComponent(searchQuery)}`;
        }
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
                borderBottom: '1px solid #e2e8f0', // Crisp border instead of heavy shadow
                color: '#1e293b' // Default text color for the bar
            }}
        >
            <Toolbar sx={{ display: 'flex', justifyContent: 'space-between', minHeight: '64px' }}>

                {/* 1. LOGO */}
                <Box
                    component="img"
                    src="/images/logo.png"
                    alt="Headless DAM Logo"
                    sx={{
                        height: 64,
                        width: 'auto',
                        cursor: 'pointer',
                    }}
                    onClick={() => window.location.href = '/dashboard'}
                />

                {/* 2. CENTER SEARCH BAR */}
                {props.isSignedIn && (
                    <SearchContainer>
                        <SearchIconWrapper>
                            <SearchIcon />
                        </SearchIconWrapper>
                        <StyledInputBase
                            placeholder="Search assets, folders, or tags..."
                            inputProps={{ 'aria-label': 'search' }}
                            value={searchQuery}
                            onChange={(e) => setSearchQuery(e.target.value)}
                            onKeyDown={handleSearchSubmit}
                        />
                    </SearchContainer>
                )}

                {/* 3. USER ACTIONS & NAVIGATION */}
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    {props.isSignedIn ? (
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
                    ) : (
                        <Button
                            variant="outlined"
                            onClick={() => window.location.href = '/users/sign_in'}
                            startIcon={<Login />}
                            sx={{ textTransform: 'none', borderRadius: '8px' }}
                        >
                            Sign In
                        </Button>
                    )}
                </Box>
            </Toolbar>
        </AppBar>
    );
}