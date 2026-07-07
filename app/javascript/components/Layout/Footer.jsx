import React from 'react';
import { Box, Container, Grid, Typography, Link as MuiLink, Stack, Divider } from '@mui/material';
import { useTranslation } from 'react-i18next';

const interpolate = (template, values = {}) => template.replace(/\{\{(\w+)\}\}/g, (_, key) => values[key] ?? '');

// Brand gradient shared with the header's accent colors (indigo -> violet),
// keeping the footer visually anchored to the product logo.
const BRAND_GRADIENT = 'linear-gradient(90deg, #4f46e5 0%, #7c3aed 100%)';

function FooterLinkColumn({ title, links }) {
    return (
        <Grid size={{ xs: 6, sm: 4 }}>
            <Typography
                variant="subtitle2"
                sx={{ fontWeight: 600, color: '#1e293b', mb: 2, textTransform: 'uppercase', letterSpacing: '0.05em', fontSize: '0.75rem' }}
            >
                {title}
            </Typography>
            <Stack spacing={1.5}>
                {links.map(({ href, label }) => (
                    <MuiLink
                        key={label}
                        href={href}
                        underline="none"
                        sx={{ color: '#64748b', typography: 'body2', transition: 'color 0.2s', '&:hover': { color: '#4f46e5' } }}
                    >
                        {label}
                    </MuiLink>
                ))}
            </Stack>
        </Grid>
    );
}

export default function Footer() {
    const { t } = useTranslation();
    const translate = (key, defaultValue, options = {}) => {
        const result = t(key, options);
        if (result === key || (options.count != null && result === `${key}:${options.count}`)) {
            return interpolate(defaultValue, options);
        }
        return result;
    };

    const currentYear = new Date().getFullYear();

    const productLinks = [
        { href: '/dashboard', label: translate('footer.product.dashboard', 'Dashboard') },
        { href: '/search', label: translate('footer.product.search', 'Semantic Search') },
        { href: '/workflows', label: translate('footer.product.workflows', 'Workflows') },
        { href: '/duplicates', label: translate('footer.product.duplicateManager', 'Duplicate Manager') },
    ];

    const resourceLinks = [
        { href: '/api/rest', label: translate('footer.resources.apiDocs', 'API Documentation') },
        { href: '/api/graphql', label: translate('footer.resources.graphqlApi', 'GraphQL API') },
        { href: '/api-docs', label: translate('footer.resources.apiReference', 'OpenAPI Reference') },
    ];

    const legalLinks = [
        { href: '/privacy', label: translate('footer.legal.privacyPolicy', 'Privacy Policy') },
        { href: '/terms', label: translate('footer.legal.termsOfService', 'Terms of Service') },
        { href: '/compliance', label: translate('footer.legal.gdprCompliance', 'GDPR Compliance') },
    ];

    return (
        <Box
            component="footer"
            data-testid="app-footer"
            sx={{
                bgcolor: '#ffffff',
                borderTop: '1px solid #e2e8f0',
                position: 'relative',
                mt: 'auto',
                width: '100%',
                // Thin brand-gradient accent stripe across the very top of the
                // footer — ties the footer visually back to the product logo
                // and the primary CTA color used across the app.
                '&::before': {
                    content: '""',
                    position: 'absolute',
                    top: 0, left: 0, right: 0,
                    height: 3,
                    background: BRAND_GRADIENT,
                },
            }}
        >
            <Container maxWidth="xl" sx={{ py: 4 }}>
                {/* MUI v9 Grid2: no `item` prop; use `size` for responsive columns */}
                <Grid container spacing={4} sx={{ justifyContent: 'space-between' }}>

                    {/* Branding & Mission */}
                    <Grid size={{ xs: 12, md: 5 }}>
                        <Box
                            component="img"
                            src="/images/logo.png"
                            alt="Capri DAM"
                            sx={{ height: 32, width: 'auto', mb: 1.5, display: 'block' }}
                        />
                        <Typography variant="body2" sx={{ color: '#64748b', mb: 2, maxWidth: 400, lineHeight: 1.6 }}>
                            {translate(
                                'footer.tagline',
                                'The intelligent operating system for your digital creative life-cycle — automated compliance, semantic discovery, and infinite scalability.'
                            )}
                        </Typography>
                    </Grid>

                    {/* Navigation Columns */}
                    <Grid size={{ xs: 12, md: 7 }}>
                        {/* Responsive justifyContent via sx (not a direct prop in Grid2 children) */}
                        <Grid container spacing={4} sx={{ justifyContent: { xs: 'flex-start', md: 'flex-end' } }}>
                            <FooterLinkColumn title={translate('footer.product.title', 'Product')} links={productLinks} />
                            <FooterLinkColumn title={translate('footer.resources.title', 'Resources')} links={resourceLinks} />
                            <FooterLinkColumn title={translate('footer.legal.title', 'Legal & Security')} links={legalLinks} />
                        </Grid>
                    </Grid>
                </Grid>

                <Divider sx={{ my: 2, borderColor: '#f1f5f9' }} />

                {/* Bottom Bar: Copyright and Versioning */}
                <Box sx={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: 2 }}>
                    <Typography variant="body2" sx={{ color: '#94a3b8' }}>
                        {translate('footer.copyright', '© {{year}} Capri DAM. All rights reserved.', { year: currentYear })}
                    </Typography>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Box sx={{ width: 8, height: 8, borderRadius: '50%', bgcolor: '#10b981' }} />
                        <Typography variant="caption" sx={{ color: '#94a3b8', fontWeight: 500 }}>
                            {translate('footer.systemOperational', 'All systems operational')}
                        </Typography>
                        <Divider orientation="vertical" flexItem sx={{ mx: 1 }} />
                        <Typography variant="caption" sx={{ color: '#cbd5e1', fontWeight: 500, fontFamily: 'monospace', fontSize: '0.8rem' }}>
                            v1.0.0-alpha
                        </Typography>
                    </Box>
                </Box>
            </Container>
        </Box>
    );
}
