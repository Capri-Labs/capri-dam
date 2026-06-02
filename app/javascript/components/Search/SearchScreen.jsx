import React, { useState, useEffect, useCallback } from 'react';
import { Box, Typography, Grid, Paper, Chip, CircularProgress, Stack, Button, Snackbar, Alert } from '@mui/material';
import { InsertDriveFile, SearchOff, Image as ImageIcon, IosShare } from '@mui/icons-material';
import AssetFilterBar from './AssetFilterBar';

export default function SearchScreen() {
    const [assets, setAssets] = useState([]);
    const [loading, setLoading] = useState(true);
    const [meta, setMeta] = useState({ total: 0, facets: {} });
    const [searchParams, setSearchParams] = useState({ query: '', mode: 'images' });

    // Notification state for the Share button
    const [snackbarOpen, setSnackbarOpen] = useState(false);

    const fetchResults = useCallback(() => {
        setLoading(true);
        const queryString = window.location.search; // Grabs ?q=logo&mode=images&content_type=image/png

        const params = new URLSearchParams(queryString);
        setSearchParams({ query: params.get('q') || '', mode: params.get('mode') || 'images' });

        fetch(`/api/v1/search${queryString}`, {
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${window.localStorage.getItem('access_token') || ''}`
            }
        })
            .then(res => res.json())
            .then(data => {
                setAssets(data.results || []);
                setMeta({ total: data.meta?.total_found || 0, facets: data.meta?.facets || {} });
            })
            .catch(err => console.error("Search API Error:", err))
            .finally(() => setLoading(false));
    }, []);

    // Fetch on initial load and whenever the browser history changes (e.g., clicking back)
    useEffect(() => {
        fetchResults();
        window.addEventListener('popstate', fetchResults);
        return () => window.removeEventListener('popstate', fetchResults);
    }, [fetchResults]);

    // Handle updates from the AssetFilterBar
    const handleFilterUpdate = (category, newValues) => {
        const url = new URL(window.location);
        if (newValues.length > 0) {
            url.searchParams.set(category, newValues);
        } else {
            url.searchParams.delete(category); // Clean up empty params
        }

        // Push the new URL to the browser without reloading the page
        window.history.pushState({}, '', url);
        // Trigger a fresh data fetch based on the new URL
        fetchResults();
    };

    const handleShareClick = () => {
        navigator.clipboard.writeText(window.location.href);
        setSnackbarOpen(true);
    };

    return (
        <Box sx={{ display: 'flex', height: '100%', overflow: 'hidden' }}>

            {/* The Dynamic Left Sidebar */}
            <AssetFilterBar facets={meta.facets} onFilterChange={handleFilterUpdate} />

            <Box sx={{ flexGrow: 1, p: 4, overflowY: 'auto', bgcolor: '#f8fafc' }}>
                <Box sx={{ mb: 4, display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <Box>
                        <Typography variant="h4" sx={{ fontWeight: 700, color: '#0f172a', mb: 1 }}>
                            Search Results
                        </Typography>
                        <Stack direction="row" spacing={1} alignItems="center">
                            <Typography variant="body1" color="textSecondary">
                                Found {meta.total} results for
                            </Typography>
                            {searchParams.query && (
                                <Chip label={`"${searchParams.query}"`} color="primary" variant="outlined" size="small" sx={{ fontWeight: 600 }} />
                            )}
                            <Chip label={`Mode: ${searchParams.mode}`} size="small" sx={{ bgcolor: '#e2e8f0', color: '#475569' }} />
                        </Stack>
                    </Box>

                    {/* The Share Button */}
                    <Button
                        variant="outlined"
                        startIcon={<IosShare />}
                        onClick={handleShareClick}
                        sx={{ borderRadius: 2, textTransform: 'none', color: '#64748b', borderColor: '#cbd5e1' }}
                    >
                        Share Results
                    </Button>
                </Box>

                {loading ? (
                    <Box sx={{ display: 'flex', justifyContent: 'center', py: 10 }}>
                        <CircularProgress />
                    </Box>
                ) : assets.length > 0 ? (
                    <Grid container spacing={3}>
                        {/* Map through your assets here just as before... */}
                        {assets.map((asset) => (
                            <Grid item xs={12} sm={6} md={4} lg={3} key={asset.uuid}>
                                <Paper elevation={0} sx={{ /* ... styles ... */ }}>
                                    {/* ... Thumbnail and Metadata ... */}
                                    <Box sx={{ p: 2 }}>
                                        <Typography variant="subtitle2" noWrap sx={{ fontWeight: 600 }}>{asset.title}</Typography>
                                    </Box>
                                </Paper>
                            </Grid>
                        ))}
                    </Grid>
                ) : (
                    <Box sx={{ textAlign: 'center', py: 12, bgcolor: '#ffffff', borderRadius: 2, border: '1px dashed #cbd5e1' }}>
                        <SearchOff sx={{ fontSize: 64, color: '#94a3b8', mb: 2 }} />
                        <Typography variant="h6" color="#334155" fontWeight="600" gutterBottom>No matching assets found</Typography>
                    </Box>
                )}
            </Box>

            {/* Success Toast for Copying Link */}
            <Snackbar open={snackbarOpen} autoHideDuration={3000} onClose={() => setSnackbarOpen(false)} anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}>
                <Alert onClose={() => setSnackbarOpen(false)} severity="success" sx={{ width: '100%', borderRadius: 2 }}>
                    Search URL copied to clipboard!
                </Alert>
            </Snackbar>
        </Box>
    );
}