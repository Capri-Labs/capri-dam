import React, { useState } from 'react';
import { Box, Typography, Button, CssBaseline, Breadcrumbs, Link } from '@mui/material';
import { Add, CollectionsBookmark } from '@mui/icons-material';
import CollectionsBoard from './CollectionsBoard';
import CollectionDetail from './CollectionDetail'; // We will build this next

export default function CollectionsWorkspace() {
    // In a full router setup (like react-router), you would use URL params here.
    // For now, we use state to toggle between the Board and a Detail view.
    const [activeCollectionSlug, setActiveCollectionSlug] = useState(null);

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />

            {/* Header Area */}
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 4 }}>
                <Box>
                    <Breadcrumbs aria-label="breadcrumb" sx={{ mb: 1 }}>
                        <Link
                            underline="hover"
                            color="inherit"
                            component="button"
                            onClick={() => setActiveCollectionSlug(null)}
                            sx={{ display: 'flex', alignItems: 'center', fontSize: '0.875rem' }}
                        >
                            <CollectionsBookmark sx={{ mr: 0.5, fontSize: '1rem' }} />
                            Workspace
                        </Link>
                        {activeCollectionSlug && (
                            <Typography color="text.primary" sx={{ fontSize: '0.875rem' }}>
                                {activeCollectionSlug}
                            </Typography>
                        )}
                    </Breadcrumbs>

                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                        {activeCollectionSlug ? 'Collection Details' : 'My Collections'}
                    </Typography>
                    <Typography variant="body2" color="textSecondary">
                        Curate, manage, and share digital asset campaigns.
                    </Typography>
                </Box>

                {!activeCollectionSlug && (
                    <Button
                        variant="contained"
                        startIcon={<Add />}
                        sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                    >
                        Create Collection
                    </Button>
                )}
            </Box>

            {/* Main Content Area */}
            {activeCollectionSlug ? (
                <CollectionDetail
                    slug={activeCollectionSlug}
                    onBack={() => setActiveCollectionSlug(null)}
                />
            ) : (
                <CollectionsBoard onSelectCollection={setActiveCollectionSlug} />
            )}
        </Box>
    );
}