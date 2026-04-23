import React from 'react';
import {
    Box, Drawer, Toolbar, List, Typography, Divider,
    ListItem, ListItemButton, ListItemIcon, ListItemText,
    Grid,
    Paper, Table, TableBody,
    TableCell, TableContainer, TableHead, TableRow, Chip
} from '@mui/material';

import {
    Dashboard as DashIcon,
    CloudUpload,
    PhotoLibrary,
    Settings
} from '@mui/icons-material';

// Import our new shared component
import Header from './Header';

const drawerWidth = 240;

const mockAssets = [
    { id: 1, name: 'hero-banner.jpg', type: 'Image', size: '2.4 MB', status: 'Published' },
    { id: 2, name: 'product-demo.mp4', type: 'Video', size: '15.8 MB', status: 'Processing' },
    { id: 3, name: 'api-docs.pdf', type: 'Document', size: '450 KB', status: 'Draft' },
];

export default function Dashboard() {
    return (
        <Box sx={{ display: 'flex' }}>
            <Header />

            <Drawer
                variant="permanent"
                sx={{
                    width: drawerWidth,
                    flexShrink: 0,
                    [`& .MuiDrawer-paper`]: { width: drawerWidth, boxSizing: 'border-box' },
                }}
            >
                <Toolbar />
                <Box sx={{ overflow: 'auto' }}>
                    <List>
                        {['Dashboard', 'All Assets', 'Upload'].map((text, index) => (
                            <ListItem key={text} disablePadding>
                                <ListItemButton selected={index === 0}>
                                    <ListItemIcon>
                                        {index === 0 ? <DashIcon /> : index === 1 ? <PhotoLibrary /> : <CloudUpload />}
                                    </ListItemIcon>
                                    <ListItemText primary={text} />
                                </ListItemButton>
                            </ListItem>
                        ))}
                    </List>
                    <Divider />
                    <List>
                        <ListItem disablePadding>
                            <ListItemButton>
                                <ListItemIcon><Settings /></ListItemIcon>
                                <ListItemText primary="System Settings" />
                            </ListItemButton>
                        </ListItem>
                    </List>
                </Box>
            </Drawer>

            <Box component="main" sx={{ flexGrow: 1, p: 3, bgcolor: '#f5f6fa', minHeight: '100vh' }}>
                <Toolbar />
                <Typography variant="h4" sx={{ mb: 4, fontWeight: 'bold' }}>Command Center</Typography>

                <Grid container spacing={3} sx={{ mb: 4 }}>
                    {[
                        { label: 'Total Assets', val: '1,284', color: '#556cd6' },
                        { label: 'Storage Used', val: '42.5 GB', color: '#19857b' },
                        { label: 'Pending Review', val: '12', color: '#ff9f43' }
                    ].map((stat) => (
                        <Grid key={stat.label} size={{ xs: 12, md: 4 }}>
                            <Paper sx={{ p: 3, textAlign: 'center', borderTop: `4px solid ${stat.color}` }}>
                                <Typography color="textSecondary" gutterBottom>{stat.label}</Typography>
                                <Typography variant="h3">{stat.val}</Typography>
                            </Paper>
                        </Grid>
                    ))}
                </Grid>

                <Typography variant="h6" sx={{ mb: 2 }}>Recent Activity</Typography>
                <TableContainer component={Paper}>
                    <Table>
                        <TableHead sx={{ bgcolor: '#eee' }}>
                            <TableRow>
                                <TableCell>Asset Name</TableCell>
                                <TableCell>Type</TableCell>
                                <TableCell>Size</TableCell>
                                <TableCell>Status</TableCell>
                            </TableRow>
                        </TableHead>
                        <TableBody>
                            {mockAssets.map((asset) => (
                                <TableRow key={asset.id}>
                                    <TableCell style={{ fontWeight: 500 }}>{asset.name}</TableCell>
                                    <TableCell>{asset.type}</TableCell>
                                    <TableCell>{asset.size}</TableCell>
                                    <TableCell>
                                        <Chip
                                            label={asset.status}
                                            color={asset.status === 'Published' ? 'success' : 'default'}
                                            size="small"
                                        />
                                    </TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                </TableContainer>
            </Box>
        </Box>
    );
}