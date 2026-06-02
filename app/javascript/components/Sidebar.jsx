import React, { useState, useEffect } from 'react';
import {
    Box, Drawer, List, Typography, ListItem,
    ListItemButton, ListItemIcon, ListItemText, Divider,
    IconButton, Tooltip, Collapse
} from '@mui/material';
import { MenuOpen, Menu, ExpandLess, ExpandMore } from '@mui/icons-material';
import { MENU_GROUPS } from './MenuConfig';

const expandedWidth = 260;
const collapsedWidth = 80;

export default function Sidebar({ activeView, onNavigate }) {
    const [open, setOpen] = useState(() => {
        const savedState = localStorage.getItem('dam_sidebar_open');
        return savedState !== null ? JSON.parse(savedState) : true;
    });

    const [expandedMenus, setExpandedMenus] = useState({});

    useEffect(() => {
        const initialExpanded = {};
        MENU_GROUPS.forEach(group => {
            group.items.forEach(item => {
                if (item.children) {
                    const hasActiveChild = item.children.some(child => child.id === activeView);
                    if (hasActiveChild) {
                        initialExpanded[item.id] = true;
                    }
                }
            });
        });
        setExpandedMenus(prev => ({ ...prev, ...initialExpanded }));
    }, [activeView]);

    const toggleSidebar = () => {
        setOpen((prev) => {
            const newState = !prev;
            localStorage.setItem('dam_sidebar_open', JSON.stringify(newState));
            return newState;
        });
    };

    const handleMenuClick = (item) => {
        if (item.children) {
            if (!open) setOpen(true); // Force open if collapsed
            setExpandedMenus(prev => ({
                ...prev,
                [item.id]: !prev[item.id]
            }));
        } else {
            if (item.url) {
                window.location.href = item.url;
            } else if (onNavigate) {
                onNavigate(item.id);
            }
        }
    };

    const renderMenuItem = (item, isChild = false) => {
        const isSelected = activeView === item.id;
        const hasChildren = !!item.children;
        const isExpanded = expandedMenus[item.id];
        const isParentActive = hasChildren && item.children.some(child => child.id === activeView);
        const isActive = isSelected || isParentActive;

        return (
            <ListItemButton
                onClick={() => handleMenuClick(item)}
                sx={{
                    borderRadius: '8px',
                    py: 1.25,
                    px: 2.5, // Consistent padding, flexbox handles the rest
                    justifyContent: open ? 'initial' : 'center',
                    bgcolor: isActive ? '#ede7f6' : 'transparent',
                    color: isActive ? '#5e35b1' : '#4b5563',
                    mb: 0.5,
                    mx: open ? 1 : 0,
                    transition: 'all 0.3s ease', // Smooth padding/margin transitions
                    '&:hover': {
                        bgcolor: isActive ? '#ede7f6' : '#f8fafc',
                        color: '#5e35b1',
                        '& .MuiListItemIcon-root': { color: '#5e35b1' }
                    }
                }}
            >
                <ListItemIcon sx={{
                    minWidth: 0,
                    mr: open ? 2 : 'auto', // Push text away when open, center when closed
                    ml: open && isChild ? 2 : 0, // Indent child icons when open
                    justifyContent: 'center',
                    color: isActive ? '#5e35b1' : '#4b5563',
                    transition: 'all 0.3s ease'
                }}>
                    {item.icon}
                </ListItemIcon>

                <ListItemText
                    primary={item.label}
                    sx={{
                        opacity: open ? 1 : 0, // Fade text out instead of removing it
                        transition: 'opacity 0.3s ease',
                        m: 0,
                        whiteSpace: 'nowrap'
                    }}
                    primaryTypographyProps={{
                        variant: 'body2',
                        fontWeight: isActive ? 600 : 500,
                        fontSize: isChild ? '0.85rem' : '0.875rem'
                    }}
                />

                {hasChildren && (
                    <Box sx={{ opacity: open ? 1 : 0, transition: 'opacity 0.3s ease', display: 'flex' }}>
                        {isExpanded ? <ExpandLess fontSize="small" /> : <ExpandMore fontSize="small" />}
                    </Box>
                )}
            </ListItemButton>
        );
    };

    return (
        <Box
            variant="permanent"
            sx={{
                width: open ? expandedWidth : collapsedWidth,
                height: '100%',
                display: 'flex',
                flexDirection: 'column',
                transition: 'width 0.3s ease',
                bgcolor: '#fff',
                overflowX: 'hidden',
            }}
        >
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: open ? 'flex-end' : 'center', p: 1.5 }}>
                <IconButton onClick={toggleSidebar} size="small" sx={{ color: '#4b5563' }}>
                    {open ? <MenuOpen /> : <Menu />}
                </IconButton>
            </Box>

            <Box sx={{ overflowY: 'auto', overflowX: 'hidden', pb: 4 }}>
                {MENU_GROUPS.map((group) => (
                    <Box key={group.id} sx={{ mb: 2 }}>

                        <Typography
                            variant="subtitle2"
                            sx={{
                                px: 3, mb: 1, mt: 1, fontWeight: 700, color: '#94a3b8',
                                fontSize: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.5px',
                                opacity: open ? 1 : 0, // Fade out group titles
                                transition: 'opacity 0.3s ease',
                                whiteSpace: 'nowrap',
                                overflow: 'hidden'
                            }}
                        >
                            {group.title}
                        </Typography>

                        <List sx={{ p: 0 }}>
                            {group.items.map((item) => (
                                <React.Fragment key={item.id}>
                                    <ListItem disablePadding sx={{ display: 'block' }}>
                                        {!open && !item.children ? (
                                            <Tooltip title={item.label} placement="right" arrow>
                                                <Box sx={{ width: '100%' }}>{renderMenuItem(item)}</Box>
                                            </Tooltip>
                                        ) : (
                                            renderMenuItem(item)
                                        )}
                                    </ListItem>

                                    {/* Only render children if they exist. Force collapse if sidebar is minimized */}
                                    {item.children && (
                                        <Collapse in={expandedMenus[item.id] && open} timeout="auto" unmountOnExit>
                                            <List component="div" disablePadding>
                                                {item.children.map((child) => (
                                                    <ListItem key={child.id} disablePadding sx={{ display: 'block' }}>
                                                        {/* Adding tooltips to children when sidebar is closed prevents UX dead-ends */}
                                                        {!open ? (
                                                            <Tooltip title={child.label} placement="right" arrow>
                                                                <Box sx={{ width: '100%' }}>{renderMenuItem(child, true)}</Box>
                                                            </Tooltip>
                                                        ) : (
                                                            renderMenuItem(child, true)
                                                        )}
                                                    </ListItem>
                                                ))}
                                            </List>
                                        </Collapse>
                                    )}
                                </React.Fragment>
                            ))}
                        </List>
                        <Divider sx={{ mt: 2, mx: open ? 2 : 1, borderColor: '#f1f5f9', transition: 'margin 0.3s ease' }} />
                    </Box>
                ))}
            </Box>
        </Box>
    );
}