import React from 'react';
import { Box, Container, Grid, Typography, Link as MuiLink, Stack, Divider } from '@mui/material';

export default function Footer() {
    const currentYear = new Date().getFullYear();

    return (
        <Box
            component="footer"
            sx={{
                bgcolor: '#ffffff',
                borderTop: '1px solid #e2e8f0',
                py: 4,
                mt: 'auto',
                width: '100%'
            }}
        >
            <Container maxWidth="xl">
                {/* MUI v9 Grid2: no `item` prop; use `size` for responsive columns */}
                <Grid container spacing={4} sx={{ justifyContent: 'space-between' }}>

                    {/* Branding & Mission */}
                    <Grid size={{ xs: 12, md: 5 }}>
                        <Typography variant="subtitle1" sx={{ fontWeight: 700, color: '#1e293b', mb: 1.5, letterSpacing: '-0.02em' }}>
                            Intelligent Asset Engine
                        </Typography>
                        <Typography variant="body2" sx={{ color: '#64748b', mb: 2, maxWidth: 400, lineHeight: 1.6 }}>
                            The operating system for your digital creative life-cycle. Engineered for high-velocity global teams who demand automated compliance, semantic discovery, and infinite scalability.
                        </Typography>
                    </Grid>

                    {/* Navigation Columns */}
                    <Grid size={{ xs: 12, md: 7 }}>
                        {/* Responsive justifyContent via sx (not a direct prop in Grid2 children) */}
                        <Grid container spacing={4} sx={{ justifyContent: { xs: 'flex-start', md: 'flex-end' } }}>

                            {/* Resources Column */}
                            <Grid size={{ xs: 6, sm: 4 }}>
                                <Typography variant="subtitle2" sx={{ fontWeight: 600, color: '#1e293b', mb: 2, textTransform: 'uppercase', letterSpacing: '0.05em', fontSize: '0.75rem' }}>
                                    Resources
                                </Typography>
                                <Stack spacing={1.5}>
                                    <MuiLink href="/developers/api" underline="none" sx={{ color: '#64748b', typography: 'body2', transition: 'color 0.2s', '&:hover': { color: '#4f46e5' } }}>
                                        API Documentation
                                    </MuiLink>
                                    <MuiLink href="/integrations" underline="none" sx={{ color: '#64748b', typography: 'body2', transition: 'color 0.2s', '&:hover': { color: '#4f46e5' } }}>
                                        Webhooks & Integrations
                                    </MuiLink>
                                    <MuiLink href="/status" underline="none" sx={{ color: '#64748b', typography: 'body2', transition: 'color 0.2s', '&:hover': { color: '#4f46e5' } }}>
                                        System Status
                                    </MuiLink>
                                </Stack>
                            </Grid>

                            {/* Legal Column */}
                            <Grid size={{ xs: 6, sm: 4 }}>
                                <Typography variant="subtitle2" sx={{ fontWeight: 600, color: '#1e293b', mb: 2, textTransform: 'uppercase', letterSpacing: '0.05em', fontSize: '0.75rem' }}>
                                    Legal & Security
                                </Typography>
                                <Stack spacing={1.5}>
                                    <MuiLink href="/privacy" underline="none" sx={{ color: '#64748b', typography: 'body2', transition: 'color 0.2s', '&:hover': { color: '#4f46e5' } }}>
                                        Privacy Policy
                                    </MuiLink>
                                    <MuiLink href="/terms" underline="none" sx={{ color: '#64748b', typography: 'body2', transition: 'color 0.2s', '&:hover': { color: '#4f46e5' } }}>
                                        Terms of Service
                                    </MuiLink>
                                    <MuiLink href="/compliance" underline="none" sx={{ color: '#64748b', typography: 'body2', transition: 'color 0.2s', '&:hover': { color: '#4f46e5' } }}>
                                        GDPR Compliance
                                    </MuiLink>
                                </Stack>
                            </Grid>

                        </Grid>
                    </Grid>
                </Grid>

                <Divider sx={{ my: 2, borderColor: '#f1f5f9' }} />

                {/* Bottom Bar: Copyright and Versioning */}
                <Box sx={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: 2 }}>
                    <Typography variant="body2" sx={{ color: '#94a3b8' }}>
                        &copy; {currentYear} Capri DAM. All rights reserved.
                    </Typography>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Box sx={{ width: 8, height: 8, borderRadius: '50%', bgcolor: '#10b981' }} />
                        <Typography variant="caption" sx={{ color: '#cbd5e1', fontWeight: 500, fontFamily: 'monospace', fontSize: '0.8rem' }}>
                            v1.0.0-alpha
                        </Typography>
                    </Box>
                </Box>
            </Container>
        </Box>
    );
}
