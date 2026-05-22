import React, { useState, useEffect } from 'react';
import {
    Badge, IconButton, Menu, MenuItem, Typography, Box, Divider, Button, Avatar
} from '@mui/material';
import { Notifications, Assignment } from '@mui/icons-material';

export default function NotificationBell() {
    const [notifications, setNotifications] = useState([]);
    const [anchorEl, setAnchorEl] = useState(null);
    const open = Boolean(anchorEl);

    const fetchNotifications = async () => {
        try {
            const res = await fetch('/api/v1/notifications.json');
            if (res.ok) {
                const data = await res.json();
                setNotifications(data);
            }
        } catch (error) {
            console.error("Failed to fetch notifications", error);
        }
    };

    // Poll for new notifications every 60 seconds
    useEffect(() => {
        fetchNotifications();
        const interval = setInterval(fetchNotifications, 60000);
        return () => clearInterval(interval);
    }, []);

    const handleOpen = (event) => setAnchorEl(event.currentTarget);
    const handleClose = () => setAnchorEl(null);

    const handleNotificationClick = async (notif) => {
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            await fetch(`/api/v1/notifications/${notif.id}/mark_read`, {
                method: 'PATCH',
                headers: { 'X-CSRF-Token': csrfToken }
            });

            // Remove it from the local list instantly for a snappy UI
            setNotifications(prev => prev.filter(n => n.id !== notif.id));

            // Redirect the user
            window.location.href = notif.action_url;
        } catch (error) {
            console.error("Error marking notification read", error);
        }
        handleClose();
    };

    const handleMarkAllRead = async () => {
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            await fetch('/api/v1/notifications/mark_all_read', {
                method: 'PATCH',
                headers: { 'X-CSRF-Token': csrfToken }
            });
            setNotifications([]);
        } catch (error) {
            console.error("Error clearing notifications", error);
        }
        handleClose();
    };

    return (
        <>
            <IconButton color="inherit" onClick={handleOpen}>
                <Badge badgeContent={notifications.length} color="error" overlap="circular">
                    <Notifications sx={{ color: '#64748b' }} />
                </Badge>
            </IconButton>

            <Menu
                anchorEl={anchorEl}
                open={open}
                onClose={handleClose}
                PaperProps={{
                    elevation: 3,
                    sx: { width: 350, maxHeight: 500, mt: 1.5, borderRadius: 2 }
                }}
                transformOrigin={{ horizontal: 'right', vertical: 'top' }}
                anchorOrigin={{ horizontal: 'right', vertical: 'bottom' }}
            >
                <Box sx={{ p: 2, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <Typography variant="subtitle1" fontWeight="bold">Notifications</Typography>
                    {notifications.length > 0 && (
                        <Button size="small" onClick={handleMarkAllRead}>Mark all read</Button>
                    )}
                </Box>
                <Divider />

                {notifications.length === 0 ? (
                    <Box sx={{ p: 4, textAlign: 'center' }}>
                        <Notifications sx={{ fontSize: 40, color: '#e2e8f0', mb: 1 }} />
                        <Typography variant="body2" color="textSecondary">You're all caught up!</Typography>
                    </Box>
                ) : (
                    notifications.map((notif) => (
                        <MenuItem
                            key={notif.id}
                            onClick={() => handleNotificationClick(notif)}
                            sx={{ py: 1.5, px: 2, borderBottom: '1px solid #f1f5f9', whiteSpace: 'normal' }}
                        >
                            <Avatar sx={{ bgcolor: '#eff6ff', color: '#3b82f6', mr: 2, width: 36, height: 36 }}>
                                <Assignment fontSize="small" />
                            </Avatar>
                            <Box>
                                <Typography variant="body2" fontWeight="bold" sx={{ color: '#1e293b' }}>
                                    {notif.title}
                                </Typography>
                                <Typography variant="caption" sx={{ color: '#64748b', display: 'block' }}>
                                    {notif.message}
                                </Typography>
                            </Box>
                        </MenuItem>
                    ))
                )}
            </Menu>
        </>
    );
}