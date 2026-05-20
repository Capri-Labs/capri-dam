import React from 'react';
import {
    Box, Drawer, List, Typography, ListItem,
    ListItemButton, ListItemIcon, ListItemText, Toolbar, Divider
} from '@mui/material';
import { MENU_GROUPS } from './MenuConfig';

const drawerWidth = 260;

export default function Sidebar({ activeView, onNavigate }) {
    return (
        <Drawer
            variant="permanent"
            sx={{
                width: drawerWidth,
                flexShrink: 0,
                '& .MuiDrawer-paper': {
                    width: drawerWidth,
                    boxSizing: 'border-box',
                    borderRight: '1px solid #e3e8ef',
                    bgcolor: '#fff',
                },
            }}
        >
            <Toolbar sx={{ mb: 2 }}>
                {/* Logo Section */}
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                    <Box sx={{ width: 34, height: 34, bgcolor: '#5e35b1', borderRadius: 2 }} />
                    <Typography variant="h5" sx={{ fontWeight: 800, color: '#121926', letterSpacing: 1 }}>
                        Headless DAM
                    </Typography>
                </Box>
            </Toolbar>

            <Box sx={{ px: 2, overflow: 'auto' }}>
                {MENU_GROUPS.map((group) => (
                    <Box key={group.id} sx={{ mb: 3 }}>
                        <Typography
                            variant="subtitle2"
                            sx={{ px: 2, mb: 1, fontWeight: 700, color: '#121926', fontSize: '0.875rem' }}
                        >
                            {group.title}
                        </Typography>

                        <List sx={{ p: 0 }}>
                            {group.items.map((item) => {
                                const isSelected = activeView === item.id;
                                return (
                                    <ListItem key={item.id} disablePadding sx={{ mb: 0.5 }}>
                                        <ListItemButton
                                            component={item.isLink ? 'a' : 'div'}
                                            href={item.url}
                                            onClick={() => !item.isLink && onNavigate(item.id)}
                                            sx={{
                                                borderRadius: '12px',
                                                py: 1.25,
                                                px: 2,
                                                bgcolor: isSelected ? '#ede7f6' : 'transparent',
                                                color: isSelected ? '#5e35b1' : '#4b5563',
                                                '&:hover': {
                                                    bgcolor: isSelected ? '#ede7f6' : '#f8fafc',
                                                    color: '#5e35b1',
                                                    '& .MuiListItemIcon-root': { color: '#5e35b1' }
                                                }
                                            }}
                                        >
                                            <ListItemIcon sx={{
                                                minWidth: 36,
                                                color: isSelected ? '#5e35b1' : '#4b5563'
                                            }}>
                                                {item.icon}
                                            </ListItemIcon>
                                            <ListItemText
                                                primary={item.label}
                                                primaryTypographyProps={{
                                                    variant: 'body2',
                                                    fontWeight: isSelected ? 600 : 500
                                                }}
                                            />
                                        </ListItemButton>
                                    </ListItem>
                                );
                            })}
                        </List>
                        <Divider sx={{ mt: 2, mx: 2, opacity: 0.5 }} />
                    </Box>
                ))}
            </Box>
        </Drawer>
    );
}