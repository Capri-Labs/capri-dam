import React from 'react';
import { Box, Paper, Typography, Grid, Button, Stack } from '@mui/material';
import { ToggleOn, Science, Construction } from '@mui/icons-material';

export default function FeatureFlagsTab() {
    return (
        <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
            <Grid container spacing={4}>
                <Grid size={12}>
                    <Paper variant="outlined" sx={{ p: 5, borderRadius: 3, textAlign: 'center', bgcolor: '#ffffff' }}>
                        <Box sx={{ display: 'flex', justifyContent: 'center', mb: 2 }}>
                            <ToggleOn sx={{ fontSize: 60, color: '#5e35b1' }} />
                        </Box>
                        <Typography variant="h5" sx={{ fontWeight: 700, mb: 1 }}>
                            Feature Flags & Release Management
                        </Typography>
                        <Typography variant="body1" color="textSecondary" sx={{ maxWidth: 600, mx: 'auto', mb: 4 }}>
                            Decouple deployment from release. This control plane will allow administrators to toggle global maintenance mode, enable beta UI components, and manage A/B testing rollouts.
                        </Typography>

                        <Stack direction="row" spacing={2} sx={{
  justifyContent: "center"
}}>
                            <Button variant="outlined" startIcon={<Science />} disabled>
                                View Active Flags
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