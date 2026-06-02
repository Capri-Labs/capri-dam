import React from 'react';
import { Box, Paper, Typography, Grid, Button, Stack } from '@mui/material';
import { SmartToy, AutoAwesome, Construction } from '@mui/icons-material';

export default function AiGatewayTab() {
    return (
        <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
            <Grid container spacing={4}>
                <Grid item xs={12}>
                    <Paper variant="outlined" sx={{ p: 5, borderRadius: 3, textAlign: 'center', bgcolor: '#ffffff' }}>
                        <Box sx={{ display: 'flex', justifyContent: 'center', mb: 2 }}>
                            <SmartToy sx={{ fontSize: 60, color: '#5e35b1' }} />
                        </Box>
                        <Typography variant="h5" sx={{ fontWeight: 700, mb: 1 }}>
                            AI & LLM Gateway Governance
                        </Typography>
                        <Typography variant="body1" color="textSecondary" sx={{ maxWidth: 600, mx: 'auto', mb: 4 }}>
                            Control the Python MCP microservice. Future capabilities will include switching active foundational models, setting token spend limits, and adjusting the global RAG system prompt.
                        </Typography>

                        <Stack direction="row" spacing={2} justifyContent="center">
                            <Button variant="outlined" startIcon={<AutoAwesome />} disabled>
                                Configure Active Model
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