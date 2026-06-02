import React from 'react';
import { Box, Paper, Typography, Grid, Button, Stack } from '@mui/material';
import { CloudQueue, Speed, Construction } from '@mui/icons-material';

export default function StorageOperationsTab() {
    return (
        <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
            <Grid container spacing={4}>
                <Grid item xs={12}>
                    <Paper variant="outlined" sx={{ p: 5, borderRadius: 3, textAlign: 'center', bgcolor: '#ffffff' }}>
                        <Box sx={{ display: 'flex', justifyContent: 'center', mb: 2 }}>
                            <CloudQueue sx={{ fontSize: 60, color: '#5e35b1' }} />
                        </Box>
                        <Typography variant="h5" sx={{ fontWeight: 700, mb: 1 }}>
                            Storage & Edge Delivery
                        </Typography>
                        <Typography variant="body1" color="textSecondary" sx={{ maxWidth: 600, mx: 'auto', mb: 4 }}>
                            Govern the ActiveStorage backend and CDN parameters. Future capabilities include global cache invalidation, presigned URL TTL configuration, and upload size thresholds.
                        </Typography>

                        <Stack direction="row" spacing={2} justifyContent="center">
                            <Button variant="outlined" startIcon={<Speed />} disabled>
                                CDN Settings
                            </Button>
                            <Button variant="contained" startIcon={<Construction />} sx={{ bgcolor: '#5e35b1' }} disabled>
                                Module in Development
                            </Button>
                        </Stack>
                    </Paper>
                </Grid>
            </Grid>
        </Paper>
    );
}