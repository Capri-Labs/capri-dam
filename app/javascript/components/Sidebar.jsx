import React, { cloneElement, useEffect, useState } from 'react';
import {
    Badge,
    Box,
    Collapse,
    Divider,
    IconButton,
    List,
    ListItem,
    ListItemButton,
    ListItemIcon,
    ListItemText,
    Tooltip,
    Typography,
} from '@mui/material';
import { MenuOpen, Menu, ExpandLess, ExpandMore } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { MENU_GROUPS } from './MenuConfig';

const expandedWidth = 260;
const collapsedWidth = 80;

export default function Sidebar({ activeView, onNavigate }) {
    const { t } = useTranslation();
    const [open, setOpen] = useState(() => {
        const savedState = localStorage.getItem('dam_sidebar_open');
        return savedState !== null ? JSON.parse(savedState) : true;
    });
    const [expandedMenus, setExpandedMenus] = useState({});
    const [inboxUnread, setInboxUnread] = useState(0);

    useEffect(() => {
        const initialExpanded = {};
        MENU_GROUPS.forEach(group => {
            group.items.forEach(item => {
                if (item.children) {
                    const hasActiveChild = item.children.some(child => child.id === activeView);
                    if (hasActiveChild) initialExpanded[item.id] = true;
                }
            });
        });
        setExpandedMenus(prev => ({ ...prev, ...initialExpanded }));
    }, [activeView]);

    useEffect(() => {
        let ignore = false;

        const loadUnread = () => {
            fetch('/api/v1/inbox/unread_count')
                .then(async response => {
                    if (!response.ok) throw new Error('inbox_count_failed');
                    return response.json();
                })
                .then(data => {
                    if (!ignore) setInboxUnread(data.unread_count || 0);
                })
                .catch(() => {
                    if (!ignore) setInboxUnread(0);
                });
        };

        loadUnread();
        const interval = window.setInterval(loadUnread, 30000);
        return () => {
            ignore = true;
            window.clearInterval(interval);
        };
    }, []);

    const toggleSidebar = () => {
        setOpen(prev => {
            const newState = !prev;
            localStorage.setItem('dam_sidebar_open', JSON.stringify(newState));
            return newState;
        });
    };

    const handleMenuClick = (item) => {
        if (item.children) {
            if (!open) setOpen(true);
            setExpandedMenus(prev => ({ ...prev, [item.id]: !prev[item.id] }));
            return;
        }

        if (item.url) {
            window.location.href = item.url;
        } else if (onNavigate) {
            onNavigate(item.id);
        }
    };

    const renderIcon = (item, isActive) => {
        const icon = item.icon || null;
        if (item.id !== 'Inbox' || inboxUnread <= 0 || !icon) return icon;

        return (
            <Badge badgeContent={inboxUnread} color="error">
                {cloneElement(icon, { color: isActive ? 'primary' : icon.props.color })}
            </Badge>
        );
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
                data-testid={item.id === 'Inbox' ? 'inbox-nav' : undefined}
                sx={{
                    borderRadius: '8px',
                    py: 1.25,
                    px: 2.5,
                    justifyContent: open ? 'initial' : 'center',
                    bgcolor: isActive ? '#ede7f6' : 'transparent',
                    color: isActive ? '#5e35b1' : '#4b5563',
                    mb: 0.5,
                    mx: open ? 1 : 0,
                    transition: 'all 0.3s ease',
                    '&:hover': {
                        bgcolor: isActive ? '#ede7f6' : '#f8fafc',
                        color: '#5e35b1',
                        '& .MuiListItemIcon-root': { color: '#5e35b1' },
                    },
                }}
            >
                <ListItemIcon sx={{
                    minWidth: 0,
                    mr: open ? 2 : 'auto',
                    ml: open && isChild ? 2 : 0,
                    justifyContent: 'center',
                    color: isActive ? '#5e35b1' : '#4b5563',
                    transition: 'all 0.3s ease',
                }}>
                    {renderIcon(item, isActive)}
                </ListItemIcon>

                <ListItemText
                    primary={item.labelKey ? t(item.labelKey, { defaultValue: item.label }) : item.label}
                    sx={{
                        opacity: open ? 1 : 0,
                        transition: 'opacity 0.3s ease',
                        m: 0,
                        whiteSpace: 'nowrap',
                    }}
                    slotProps={{
                        primary: {
                            variant: 'body2',
                            fontWeight: isActive ? 600 : 500,
                            fontSize: isChild ? '0.85rem' : '0.875rem',
                        },
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
                {MENU_GROUPS.map(group => (
                    <Box key={group.id} sx={{ mb: 2 }}>
                        <Typography
                            variant="subtitle2"
                            sx={{
                                px: 3,
                                mb: 1,
                                mt: 1,
                                fontWeight: 700,
                                color: '#94a3b8',
                                fontSize: '0.75rem',
                                textTransform: 'uppercase',
                                letterSpacing: '0.5px',
                                opacity: open ? 1 : 0,
                                transition: 'opacity 0.3s ease',
                                whiteSpace: 'nowrap',
                                overflow: 'hidden',
                            }}
                        >
                            {group.titleKey ? t(group.titleKey, { defaultValue: group.title }) : group.title}
                        </Typography>

                        <List sx={{ p: 0 }}>
                            {group.items.map(item => (
                                <React.Fragment key={item.id}>
                                    <ListItem disablePadding sx={{ display: 'block' }}>
                                        {!open && !item.children ? (
                                            <Tooltip title={item.label} placement="right" arrow>
                                                <Box sx={{ width: '100%' }}>{renderMenuItem(item)}</Box>
                                            </Tooltip>
                                        ) : renderMenuItem(item)}
                                    </ListItem>

                                    {item.children && (
                                        <Collapse in={expandedMenus[item.id] && open} timeout="auto" unmountOnExit>
                                            <List component="div" disablePadding>
                                                {item.children.map(child => (
                                                    <ListItem key={child.id} disablePadding sx={{ display: 'block' }}>
                                                        {!open ? (
                                                            <Tooltip title={child.label} placement="right" arrow>
                                                                <Box sx={{ width: '100%' }}>{renderMenuItem(child, true)}</Box>
                                                            </Tooltip>
                                                        ) : renderMenuItem(child, true)}
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
