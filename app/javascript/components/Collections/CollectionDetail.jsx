import React, { useState, useEffect } from 'react';
import {
    Box, Typography, Button, Grid, Card, CardContent,
    IconButton, Chip, Stack, CircularProgress, Menu, MenuItem, Paper
} from '@mui/material';
import {
    ArrowBack, Share, MoreVert,
    AutoAwesome, Image as ImageIcon, CloudDownload, DeleteOutlined
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

export default function CollectionDetail({ slug, onBack }) {
    const notify = useNotify();
    const [collection, setCollection] = useState(null);
    const [loading, setLoading] = useState(true);

    // Action Menu State for individual assets
    const [anchorEl, setAnchorEl] = useState(null);
    const [selectedAssetId, setSelectedAssetId] = useState(null);

    useEffect(() => {
        // Simulating the API fetch: GET /api/v1/collections/:slug
        setLoading(true);
        setTimeout(() => {
            setCollection({
                id: 1,
                slug: slug,
                name: slug === 'brand-logos-2026' ? 'Brand Logos 2026' : 'Q3 Website Relaunch',
                description: 'Approved digital assets curated for this specific workspace.',
                smart_collection: slug === 'brand-logos-2026',
                assets: [
                    { id: 101, title: 'Hero_Banner_V2.png', type: 'image', size: '2.4 MB' },
                    { id: 102, title: 'Product_Mockup_Front.jpg', type: 'image', size: '1.1 MB' },
                    { id: 103, title: 'Corporate_Logo_Transparent.png', type: 'image', size: '450 KB' },
                    { id: 104, title: 'Campaign_Guidelines.pdf', type: 'document', size: '3.2 MB' }
                ]
            });
            setLoading(false);
        }, 600);
    }, [slug]);

    const handleMenuOpen = (event, assetId) => {
        setAnchorEl(event.currentTarget);
        setSelectedAssetId(assetId);
    };

    const handleMenuClose = () => {
        setAnchorEl(null);
        setSelectedAssetId(null);
    };

    const handleRemoveAsset = () => {
        // In reality, you would call your REST or GraphQL endpoint here:
        // fetch(`/api/v1/collections/${slug}/assets/${selectedAssetId}`, { method: 'DELETE' })

        setCollection(prev => ({
            ...prev,
            assets: prev.assets.filter(a => a.id !== selectedAssetId)
        }));

        notify("Asset removed from collection.", "success");
        handleMenuClose();
    };

    if (loading) {
        return (
            <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', py: 10 }}>
                <CircularProgress size={40} sx={{ mb: 2, color: '#5e35b1' }} />
                <Typography color="textSecondary">Loading workspace...</Typography>
            </Box>
        );
    }

    if (!collection) return null;

    return (
        <Box>
            {/* Header / Meta Section */}
            <Paper elevation={0} sx={{ p: 3, mb: 4, borderRadius: 3, border: '1px solid #e3e8ef', bgcolor: '#fff' }}>
                <Button
                    startIcon={<ArrowBack />}
                    onClick={onBack}
                    sx={{ color: '#64748b', mb: 2, textTransform: 'none' }}
                >
                    Back to Workspace Board
                </Button>

                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <Box>
                        <Stack direction="row" alignItems="center" spacing={2} sx={{ mb: 1 }}>
                            <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                                {collection.name}
                            </Typography>
                            {collection.smart_collection && (
                                <Chip
                                    icon={<AutoAwesome fontSize="small" />}
                                    label="AI Smart Collection"
                                    size="small"
                                    sx={{ bgcolor: '#f3e5f5', color: '#8e24aa', fontWeight: 600 }}
                                />
                            )}
                        </Stack>
                        <Typography variant="body1" color="textSecondary" sx={{ maxWidth: 800 }}>
                            {collection.description}
                        </Typography>
                    </Box>

                    <Stack direction="row" spacing={2}>
                        {/* The AI Integration Payload Trigger */}
                        <Button
                            variant="outlined"
                            startIcon={<AutoAwesome />}
                            sx={{ borderColor: '#e3e8ef', color: '#5e35b1' }}
                        >
                            Ask AI about this Collection
                        </Button>

                        <Button
                            variant="contained"
                            startIcon={<Share />}
                            sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                        >
                            Share Public Link
                        </Button>
                    </Stack>
                </Box>
            </Paper>

            {/* Asset Grid */}
            <Typography variant="h6" sx={{ fontWeight: 600, mb: 3 }}>
                Curated Assets ({collection.assets.length})
            </Typography>

            {collection.assets.length === 0 ? (
                <Paper elevation={0} sx={{ p: 6, textAlign: 'center', borderRadius: 3, border: '1px dashed #cbd5e1', bgcolor: '#f8fafc' }}>
                    <ImageIcon sx={{ fontSize: 48, color: '#cbd5e1', mb: 2 }} />
                    <Typography variant="h6" color="textSecondary">This collection is empty</Typography>
                    <Typography variant="body2" color="textSecondary">Navigate to the Asset Explorer to add files to this workspace.</Typography>
                </Paper>
            ) : (
                <Grid container spacing={3}>
                    {collection.assets.map((asset) => (
                        <Grid item xs={12} sm={6} md={4} lg={3} key={asset.id}>
                            <Card
                                elevation={0}
                                sx={{
                                    border: '1px solid #e3e8ef',
                                    borderRadius: 2,
                                    '&:hover': { borderColor: '#94a3b8' }
                                }}
                            >
                                {/* Asset Thumbnail Placeholder */}
                                <Box sx={{ height: 160, bgcolor: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center', borderBottom: '1px solid #e3e8ef' }}>
                                    <ImageIcon sx={{ fontSize: 40, color: '#cbd5e1' }} />
                                </Box>

                                <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
                                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                                        <Box sx={{ overflow: 'hidden' }}>
                                            <Typography variant="subtitle2" sx={{ fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                                {asset.title}
                                            </Typography>
                                            <Typography variant="caption" color="textSecondary">
                                                {asset.size} • {asset.type.toUpperCase()}
                                            </Typography>
                                        </Box>
                                        <IconButton
                                            size="small"
                                            onClick={(e) => handleMenuOpen(e, asset.id)}
                                            sx={{ ml: 1, mt: -0.5, mr: -0.5 }}
                                        >
                                            <MoreVert fontSize="small" />
                                        </IconButton>
                                    </Box>
                                </CardContent>
                            </Card>
                        </Grid>
                    ))}
                </Grid>
            )}

            {/* Action Menu for Individual Assets */}
            <Menu
                anchorEl={anchorEl}
                open={Boolean(anchorEl)}
                onClose={handleMenuClose}
                elevation={2}
                PaperProps={{ sx: { borderRadius: 2, minWidth: 180, border: '1px solid #e3e8ef' } }}
            >
                <MenuItem onClick={handleMenuClose}>
                    <CloudDownload fontSize="small" sx={{ mr: 1.5, color: '#64748b' }} />
                    Download File
                </MenuItem>
                <MenuItem onClick={handleRemoveAsset} sx={{ color: '#d32f2f' }}>
                    <DeleteOutlined fontSize="small" sx={{ mr: 1.5 }} />
                    Remove from Collection
                </MenuItem>
            </Menu>
        </Box>
    );
}