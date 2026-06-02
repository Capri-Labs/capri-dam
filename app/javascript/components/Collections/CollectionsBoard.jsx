import React, { useState, useEffect } from 'react';
import {
    Grid, Card, CardContent, CardActions, Typography, Button,
    Box, Chip, Avatar, AvatarGroup, Stack, CircularProgress
} from '@mui/material';
import { AutoAwesome, FolderShared, Lock, Image as ImageIcon } from '@mui/icons-material';

export default function CollectionsBoard({ onSelectCollection }) {
    const [collections, setCollections] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        // In reality, this would be your GraphQL or REST fetch:
        // fetch('/api/v1/collections').then(...)

        // Simulating an API response matching our schema design
        setTimeout(() => {
            setCollections([
                {
                    id: 1,
                    slug: 'q3-website-relaunch',
                    name: 'Q3 Website Relaunch',
                    description: 'Approved assets for the new corporate homepage.',
                    asset_count: 24,
                    smart_collection: false,
                    shared: true
                },
                {
                    id: 2,
                    slug: 'brand-logos-2026',
                    name: 'Brand Logos 2026',
                    description: 'Dynamically tracking all transparent PNG logos uploaded this year.',
                    asset_count: 142,
                    smart_collection: true, // Triggers the AI visual badge
                    shared: false
                }
            ]);
            setLoading(false);
        }, 800);
    }, []);

    if (loading) {
        return <Box sx={{ display: 'flex', justifyContent: 'center', py: 8 }}><CircularProgress /></Box>;
    }

    if (collections.length === 0) {
        return (
            <Box sx={{ textAlign: 'center', py: 10, bgcolor: '#fff', borderRadius: 3, border: '1px dashed #e3e8ef' }}>
                <FolderShared sx={{ fontSize: 60, color: '#cbd5e1', mb: 2 }} />
                <Typography variant="h6" color="textSecondary">No collections found</Typography>
                <Typography variant="body2" color="textSecondary">Create your first collection to start curating assets.</Typography>
            </Box>
        );
    }

    return (
        <Grid container spacing={3}>
            {collections.map((collection) => (
                <Grid item xs={12} sm={6} md={4} lg={3} key={collection.id}>
                    <Card
                        elevation={0}
                        sx={{
                            height: '100%',
                            display: 'flex',
                            flexDirection: 'column',
                            border: '1px solid #e3e8ef',
                            borderRadius: 3,
                            transition: 'transform 0.2s, box-shadow 0.2s',
                            '&:hover': {
                                transform: 'translateY(-4px)',
                                boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.1)',
                                borderColor: '#5e35b1'
                            }
                        }}
                    >
                        <CardContent sx={{ flexGrow: 1, p: 3 }}>
                            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 2 }}>
                                <Avatar sx={{ bgcolor: collection.smart_collection ? '#f3e5f5' : '#e3f2fd', color: collection.smart_collection ? '#8e24aa' : '#1976d2' }}>
                                    {collection.smart_collection ? <AutoAwesome fontSize="small" /> : <FolderShared fontSize="small" />}
                                </Avatar>

                                <Chip
                                    size="small"
                                    icon={collection.shared ? <FolderShared fontSize="small" /> : <Lock fontSize="small" />}
                                    label={collection.shared ? 'Shared' : 'Private'}
                                    variant="outlined"
                                    sx={{ borderColor: '#e3e8ef', color: '#64748b' }}
                                />
                            </Box>

                            <Typography variant="h6" sx={{ fontWeight: 600, mb: 1, lineHeight: 1.2 }}>
                                {collection.name}
                            </Typography>

                            <Typography variant="body2" color="textSecondary" sx={{ mb: 3, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
                                {collection.description || 'No description provided.'}
                            </Typography>

                            <Stack direction="row" alignItems="center" spacing={1}>
                                <ImageIcon sx={{ color: '#94a3b8', fontSize: '1.2rem' }} />
                                <Typography variant="caption" sx={{ fontWeight: 600, color: '#475569' }}>
                                    {collection.asset_count} Assets
                                </Typography>
                            </Stack>
                        </CardContent>

                        <CardActions sx={{ p: 2, pt: 0, borderTop: '1px solid #f1f5f9', mt: 'auto' }}>
                            <Button
                                size="small"
                                sx={{ color: '#5e35b1', fontWeight: 600 }}
                                onClick={() => onSelectCollection(collection.slug)}
                            >
                                Open Workspace
                            </Button>
                        </CardActions>
                    </Card>
                </Grid>
            ))}
        </Grid>
    );
}