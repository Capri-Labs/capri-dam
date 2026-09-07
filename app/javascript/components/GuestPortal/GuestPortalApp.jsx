import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Alert, Box, Chip, CircularProgress, Container, Stack, Typography,
} from '@mui/material';

import useGuestPortal from './useGuestPortal';
import PortalAssetCard from './PortalAssetCard';
import PassphraseGate from './PassphraseGate';
import IdentityGate from './IdentityGate';

/**
 * Root of the distribution portal.
 *
 * Everything it knows arrives from `/s/portal/:token`. There is no access to
 * `/api/v1`, no user object and no permission model on this side — the server
 * decides what the token covers, which assets were granted and which of those
 * may be downloaded. This only renders the answer.
 */
export default function GuestPortalApp({ config }) {
    const { t } = useTranslation();
    const portal = useGuestPortal(config.token);
    const [identityDismissed, setIdentityDismissed] = useState(false);

    const accent = portal.portal?.accent || config.accent || '#2563eb';

    if (portal.loading) {
        return (
            <Box sx={{ display: 'grid', placeItems: 'center', height: '70vh' }}>
                <CircularProgress />
            </Box>
        );
    }

    if (portal.locked) {
        return <PassphraseGate onUnlock={portal.unlock} accent={accent} />;
    }

    if (portal.error) {
        return (
            <Box sx={{ maxWidth: 520, mx: 'auto', mt: 8 }}>
                <Alert severity="error" data-testid="portal-error">{portal.error}</Alert>
            </Box>
        );
    }

    const details = portal.portal || {};
    // Ask who they are on arrival when the link demands it, unless they have
    // already been asked and declined during this visit.
    const needsIdentity = Boolean(details.require_email && !portal.guest);

    return (
        <Container maxWidth="lg" sx={{ py: 4 }}>
            <Stack spacing={1} sx={{ mb: 3 }}>
                <Typography variant="h4" fontWeight={800} data-testid="portal-headline">
                    {details.headline || config.headline}
                </Typography>

                {details.message && (
                    <Typography variant="body1" color="text.secondary" sx={{ maxWidth: 760 }}>
                        {details.message}
                    </Typography>
                )}

                <Stack direction="row" spacing={1} alignItems="center" useFlexGap sx={{ flexWrap: 'wrap' }}>
                    <Chip
                        size="small"
                        label={t('portal.fileCount', { count: portal.assets.length })}
                        data-testid="portal-file-count"
                    />
                    {portal.guest && !portal.guest.anonymous && (
                        <Chip size="small" variant="outlined" label={portal.guest.name} />
                    )}
                </Stack>
            </Stack>

            {portal.assets.length === 0 ? (
                <Alert severity="info" data-testid="portal-empty">{t('portal.empty')}</Alert>
            ) : (
                <Box sx={{
                    display: 'grid',
                    gap: 2.5,
                    gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))',
                }}
                >
                    {portal.assets.map((asset) => (
                        <PortalAssetCard key={asset.id} asset={asset} accent={accent} />
                    ))}
                </Box>
            )}

            <IdentityGate
                open={needsIdentity && !identityDismissed}
                onSubmit={portal.identify}
                onDismiss={() => setIdentityDismissed(true)}
            />
        </Container>
    );
}
