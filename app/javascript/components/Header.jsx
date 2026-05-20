import React, { useState } from 'react';
import { AppBar, Toolbar, Button, Box, InputBase, alpha, styled, Typography } from '@mui/material';
import { Logout, Search as SearchIcon, Login } from '@mui/icons-material';

// Styled components for the search bar
const SearchContainer = styled('div')(({ theme }) => ({
    position: 'relative',
    borderRadius: theme.shape.borderRadius,
    backgroundColor: alpha(theme.palette.common.white, 0.15),
    '&:hover': {
        backgroundColor: alpha(theme.palette.common.white, 0.25),
    },
    marginRight: theme.spacing(2),
    marginLeft: 0,
    width: '100%',
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
}));

const StyledInputBase = styled(InputBase)(({ theme }) => ({
    color: 'inherit',
    '& .MuiInputBase-input': {
        padding: theme.spacing(1, 1, 1, 0),
        paddingLeft: `calc(1em + ${theme.spacing(4)})`,
        transition: theme.transitions.create('width'),
        width: '100%',
        [theme.breakpoints.up('md')]: {
            width: '45ch', // Width of the search bar
        },
    },
}));

export default function Header(props) {
    const [searchQuery, setSearchQuery] = useState('');

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
            // Redirect to dashboard with search query
            window.location.href = `/dashboard?search=${encodeURIComponent(searchQuery)}`;
        }
    };

    return (
        <AppBar
            position="fixed"
            sx={{
                zIndex: (theme) => theme.zIndex.drawer + 1,
                bgcolor: '#2f3542',
                boxShadow: '0px 2px 4px -1px rgba(0,0,0,0.2)'
            }}
        >
            <Toolbar sx={{ display: 'flex', justifyContent: 'space-between' }}>
                {/* 1. LOGO */}
                <Box
                    component="img"
                    src="/images/logo.png"
                    alt="Headless DAM Logo"
                    sx={{
                        height: 65, // Slightly reduced to fit better with search
                        width: 'auto',
                        cursor: 'pointer',
                    }}
                    onClick={() => window.location.href = '/dashboard'}
                />

                {/* 2. CENTER SEARCH BAR (Visible only if signed in) */}
                {props.isSignedIn && (
                    <SearchContainer>
                        <SearchIconWrapper>
                            <SearchIcon sx={{ color: 'rgba(255,255,255,0.7)' }} />
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

                {/* 3. USER ACTIONS */}
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    {props.isSignedIn ? (
                        <>
                            <Typography variant="body2" sx={{ color: 'rgba(255,255,255,0.6)', display: { xs: 'none', md: 'block' } }}>
                                Welcome, {props.userName}
                            </Typography>
                            <Button
                                color="inherit"
                                onClick={handleLogout}
                                startIcon={<Logout />}
                                sx={{ textTransform: 'none', fontWeight: 600 }}
                            >
                                Sign Out
                            </Button>
                        </>
                    ) : (
                        <Button
                            color="inherit"
                            onClick={() => window.location.href = '/users/sign_in'}
                            startIcon={<Login />}
                            sx={{ textTransform: 'none' }}
                        >
                            Sign In
                        </Button>
                    )}
                </Box>
            </Toolbar>
        </AppBar>
    );
}