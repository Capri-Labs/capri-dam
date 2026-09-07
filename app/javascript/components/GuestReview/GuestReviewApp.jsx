import React, { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Alert, Box, Chip, CircularProgress, Divider, Stack, Typography,
} from '@mui/material';

import useGuestReview from './useGuestReview';
import GuestAssetViewer from './GuestAssetViewer';
import GuestCommentPanel from './GuestCommentPanel';
import IdentityGate from './IdentityGate';

/**
 * Root of the external review app.
 *
 * Everything it knows arrives from `/s/reviews/:token`. There is no access to
 * `/api/v1`, no user object and no permission model on this side — the server
 * decides what the token covers and this only renders it.
 */
export default function GuestReviewApp({ config }) {
    const { t } = useTranslation();
    const review = useGuestReview(config.token);

    const [draft, setDraft] = useState([]);
    const [selectedThreadId, setSelectedThreadId] = useState(null);
    const [hoveredThreadId, setHoveredThreadId] = useState(null);
    const [identityOpen, setIdentityOpen] = useState(false);
    const [identityDismissed, setIdentityDismissed] = useState(false);

    const handleCreateThread = useCallback(async ({ body }) => {
        const thread = await review.createThread({ body, annotations: draft });
        setDraft([]);
        setSelectedThreadId(thread?.id || null);
        return thread;
    }, [review, draft]);

    const handleIdentify = useCallback(async (details) => {
        await review.identify(details);
        setIdentityOpen(false);
    }, [review]);

    if (review.loading) {
        return (
            <Box sx={{ display: 'grid', placeItems: 'center', height: '70vh' }}>
                <CircularProgress />
            </Box>
        );
    }

    if (review.error && !review.review) {
        return (
            <Box sx={{ maxWidth: 520, mx: 'auto', mt: 8 }}>
                <Alert severity="error">{review.error}</Alert>
            </Box>
        );
    }

    // Prompt on arrival when the link demands a name, unless the reviewer has
    // already been asked and declined during this visit.
    const needsIdentity = Boolean(
        review.review?.require_email && review.review?.allow_comments && !review.guest,
    );
    const showGate = identityOpen || (needsIdentity && !identityDismissed);

    return (
        <Box sx={{ height: 'calc(100vh - 57px)', display: 'flex', flexDirection: 'column' }}>
            <Stack
                direction="row" alignItems="center" spacing={1.5}
                sx={{ px: 3, py: 1.25, bgcolor: 'background.paper', borderBottom: '1px solid', borderColor: 'divider' }}
            >
                <Typography variant="subtitle1" fontWeight={700} noWrap>
                    {review.review?.name}
                </Typography>
                <Typography variant="body2" color="text.secondary" noWrap>
                    {review.review?.target_label}
                </Typography>
                <Box sx={{ flex: 1 }} />
                {review.guest && (
                    <Chip size="small" variant="outlined"
                          label={t('guestReview.header.reviewingAs', { name: review.guest.display_name })} />
                )}
                {review.review?.expires_at && (
                    <Typography variant="caption" color="text.secondary">
                        {t('guestReview.header.expires', {
                            date: new Date(review.review.expires_at).toLocaleDateString(),
                        })}
                    </Typography>
                )}
            </Stack>

            <Box sx={{ flex: 1, minHeight: 0, display: 'flex' }}>
                {/* The asset rail only earns its space when the link covers
                    more than one thing, which for a single-asset link it never
                    does. */}
                {review.assets.length > 1 && (
                    <Box sx={{
                        width: 180, flexShrink: 0, overflowY: 'auto', p: 1,
                        borderRight: '1px solid', borderColor: 'divider', bgcolor: 'background.paper',
                    }}>
                        {review.assets.map((asset) => (
                            <Box
                                key={asset.id}
                                onClick={() => review.setSelectedAssetId(asset.id)}
                                sx={{
                                    p: 0.75, mb: 0.75, borderRadius: 1.5, cursor: 'pointer',
                                    border: '2px solid',
                                    borderColor: asset.id === review.selectedAssetId ? 'primary.main' : 'transparent',
                                    bgcolor: 'action.hover',
                                }}
                            >
                                <Box
                                    component="img"
                                    src={asset.preview_url}
                                    alt={asset.title}
                                    loading="lazy"
                                    sx={{ width: '100%', aspectRatio: '4 / 3', objectFit: 'cover', borderRadius: 1, display: 'block' }}
                                />
                                <Typography variant="caption" noWrap sx={{ display: 'block', mt: 0.5 }}>
                                    {asset.title}
                                </Typography>
                            </Box>
                        ))}
                    </Box>
                )}

                <Box sx={{ flex: 1, minWidth: 0 }}>
                    <GuestAssetViewer
                        asset={review.selectedAsset}
                        annotations={review.annotations}
                        draft={draft}
                        onDraftAdd={(annotation) => setDraft((current) => [...current, annotation])}
                        onClearDraft={() => setDraft([])}
                        canComment={review.canComment}
                        selectedThreadId={selectedThreadId}
                        hoveredThreadId={hoveredThreadId}
                        onSelectThread={setSelectedThreadId}
                        onHoverThread={setHoveredThreadId}
                        token={config.token}
                    />
                </Box>

                <Divider orientation="vertical" flexItem />

                <Box sx={{ width: 360, flexShrink: 0, bgcolor: 'background.paper' }}>
                    <GuestCommentPanel
                        threads={review.threads}
                        canComment={review.canComment}
                        draftCount={draft.length}
                        selectedThreadId={selectedThreadId}
                        onSelectThread={setSelectedThreadId}
                        onHoverThread={setHoveredThreadId}
                        onCreateThread={handleCreateThread}
                        onReply={review.createReply}
                        onClearDraft={() => setDraft([])}
                        requiresIdentity={needsIdentity}
                        onIdentify={() => setIdentityOpen(true)}
                    />
                </Box>
            </Box>

            <IdentityGate
                open={showGate}
                required={false}
                onIdentify={handleIdentify}
                onSkip={() => { setIdentityOpen(false); setIdentityDismissed(true); }}
            />
        </Box>
    );
}
