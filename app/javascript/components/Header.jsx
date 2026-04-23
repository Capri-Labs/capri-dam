import React from 'react';
import { AppBar, Toolbar, Typography, Button, Chip } from '@mui/material';
import { Logout } from '@mui/icons-material';

export default function Header() {
    const handleLogout = () => {
        fetch('/users/sign_out', {
            method: 'DELETE',
            headers: {
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                'Content-Type': 'application/json'
            }
        }).then(() => window.location.href = '/');
    };

    return (
        <AppBar
            position="fixed"
            sx={{
                zIndex: (theme) => theme.zIndex.drawer + 1,
                bgcolor: '#2f3542'
            }}
        >
            <Toolbar>
                <Typography variant="h6" noWrap component="div" sx={{ flexGrow: 1 }}>
                    Headless DAM <Chip label="MVP v1.0" size="small" color="primary" sx={{ ml: 1 }} />
                </Typography>
                <Button color="inherit" onClick={handleLogout} startIcon={<Logout />}>
                    Sign Out
                </Button>
            </Toolbar>
        </AppBar>
    );
}