import React from 'react';
import { Box, Typography, Grid, Paper, Chip } from '@mui/material';
import { InsertDriveFile, SearchOff } from '@mui/icons-material';

export default function SearchResults({ searchTerm, rawAssets }) {
    const getParsedAssets = () => {
        try {
            if (rawAssets && rawAssets.trim() !== "") {
                const parsed = JSON.parse(rawAssets);
                return Array.isArray(parsed) ? parsed : [];
            }
        } catch (e) {
            console.error("SearchResults: Failed to parse assets JSON", e);
        }
        return [];
    };

    const searchAssets = getParsedAssets();

    return (
        <Box sx={{ p: 3 }}>
            <Box sx={{ mb: 4, display: 'flex', alignItems: 'center', gap: 2 }}>
                <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                    Search Results
                </Typography>
                <Chip label={`"${searchTerm}"`} color="primary" variant="outlined" />
            </Box>

            {searchAssets.length > 0 ? (
                <Grid container spacing={2}>
                    {searchAssets.map((asset) => (
                        <Grid item xs={12} sm={6} md={3} key={asset.id}>
                            <Paper
                                elevation={0}
                                sx={{
                                    p: 2, border: '1px solid #e3e8ef', borderRadius: 2,
                                    display: 'flex', alignItems: 'center', gap: 2,
                                    transition: '0.2s',
                                    '&:hover': { borderColor: '#5e35b1', bgcolor: '#f8f5ff', cursor: 'pointer' }
                                }}
                                onClick={() => window.location.href = `/assets/${asset.id}`}
                            >
                                <InsertDriveFile sx={{ color: '#5e35b1' }} />
                                <Box sx={{ overflow: 'hidden' }}>
                                    <Typography variant="subtitle2" noWrap sx={{ fontWeight: 600 }}>{asset.name}</Typography>
                                    <Typography variant="caption" color="textSecondary">{asset.type} • {asset.size}</Typography>
                                </Box>
                            </Paper>
                        </Grid>
                    ))}
                </Grid>
            ) : (
                <Box sx={{ textAlign: 'center', py: 10 }}>
                    <SearchOff sx={{ fontSize: 60, color: '#cfd8dc', mb: 2 }} />
                    <Typography variant="h6" color="textSecondary">No assets found for "{searchTerm}"</Typography>
                </Box>
            )}
        </Box>
    );
}