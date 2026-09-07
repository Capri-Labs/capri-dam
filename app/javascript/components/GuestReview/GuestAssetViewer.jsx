import React, { useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Box, IconButton, Paper, Stack, Tooltip, Typography } from '@mui/material';
import CropSquareIcon from '@mui/icons-material/CropSquare';
import RadioButtonUncheckedIcon from '@mui/icons-material/RadioButtonUnchecked';
import NorthEastIcon from '@mui/icons-material/NorthEast';
import GestureIcon from '@mui/icons-material/Gesture';
import PlaceIcon from '@mui/icons-material/Place';
import DownloadIcon from '@mui/icons-material/Download';
import NearMeIcon from '@mui/icons-material/NearMe';

import AnnotationOverlay from '../Folders/AnnotationOverlay';
import { SHAPES } from '../../utils/annotationGeometry';

const TOOLS = [
    { shape: null, icon: NearMeIcon, key: 'select' },
    { shape: SHAPES.RECT, icon: CropSquareIcon, key: 'rect' },
    { shape: SHAPES.ELLIPSE, icon: RadioButtonUncheckedIcon, key: 'ellipse' },
    { shape: SHAPES.ARROW, icon: NorthEastIcon, key: 'arrow' },
    { shape: SHAPES.FREEHAND, icon: GestureIcon, key: 'freehand' },
    { shape: SHAPES.PIN, icon: PlaceIcon, key: 'pin' },
];

/**
 * The asset under review, with the shared annotation overlay stacked over it.
 *
 * WHY `AnnotationOverlay` IS REUSED BUT `AssetViewer` IS NOT
 * ---------------------------------------------------------
 * The overlay is pure geometry: it takes normalised shapes and a size and
 * draws them. It has no notion of permissions, versions or the authenticated
 * API, so it is safe and correct to share — and sharing it is what guarantees
 * a client's rectangle lands in exactly the same place internally.
 *
 * `AssetViewer` is the opposite: version tabs, metadata, workflow actions,
 * downloads and the internal comment panel, all wired to `/api/v1`. Reusing it
 * would have meant hiding most of it behind guest checks, which is how an
 * internal control ends up one bug away from being visible externally.
 */
export default function GuestAssetViewer({
    asset, annotations, draft, onDraftAdd, onClearDraft,
    canComment, selectedThreadId, hoveredThreadId, onSelectThread, onHoverThread, token,
}) {
    const { t } = useTranslation();
    const [tool, setTool] = useState(null);
    const [naturalSize, setNaturalSize] = useState({ width: null, height: null });

    const isVideo = useMemo(
        () => String(asset?.content_type || '').startsWith('video/'),
        [asset],
    );

    if (!asset) {
        return (
            <Box sx={{ display: 'grid', placeItems: 'center', height: '100%' }}>
                <Typography color="text.secondary">{t('guestReview.viewer.noAsset')}</Typography>
            </Box>
        );
    }

    return (
        <Stack sx={{ height: '100%', minHeight: 0 }}>
            <Stack
                direction="row" alignItems="center" spacing={1}
                sx={{ px: 2, py: 1, borderBottom: '1px solid', borderColor: 'divider' }}
            >
                <Typography variant="subtitle2" fontWeight={700} noWrap sx={{ flex: 1 }}>
                    {asset.title}
                </Typography>

                {canComment && !isVideo && (
                    <Paper variant="outlined" sx={{ display: 'flex', borderRadius: 2, p: 0.25 }}>
                        {TOOLS.map(({ shape, icon: Icon, key }) => (
                            <Tooltip key={key} title={t(`guestReview.tools.${key}`)}>
                                <IconButton
                                    size="small"
                                    color={tool === shape ? 'primary' : 'default'}
                                    onClick={() => setTool(shape)}
                                >
                                    <Icon fontSize="small" />
                                </IconButton>
                            </Tooltip>
                        ))}
                    </Paper>
                )}

                {asset.downloadable && (
                    <Tooltip title={t('guestReview.viewer.download')}>
                        <IconButton
                            size="small"
                            component="a"
                            href={`/s/reviews/${token}/assets/${asset.id}/download`}
                        >
                            <DownloadIcon fontSize="small" />
                        </IconButton>
                    </Tooltip>
                )}
            </Stack>

            <Box sx={{
                flex: 1, minHeight: 0, display: 'grid', placeItems: 'center',
                bgcolor: '#0f172a', p: 2, overflow: 'hidden',
            }}>
                <Box sx={{ position: 'relative', maxWidth: '100%', maxHeight: '100%', lineHeight: 0 }}>
                    {isVideo ? (
                        <video
                            src={asset.preview_url}
                            controls
                            style={{ maxWidth: '100%', maxHeight: '72vh', display: 'block' }}
                        />
                    ) : (
                        <img
                            src={asset.preview_url}
                            alt={asset.title}
                            onLoad={(e) => setNaturalSize({
                                width: e.target.naturalWidth,
                                height: e.target.naturalHeight,
                            })}
                            style={{ maxWidth: '100%', maxHeight: '72vh', display: 'block' }}
                        />
                    )}

                    {/* Absolutely positioned so it tracks the *rendered* box of
                        the media, not the padded container — otherwise every
                        normalised coordinate would be offset by the letterbox. */}
                    <Box sx={{ position: 'absolute', inset: 0 }}>
                        <AnnotationOverlay
                            annotations={annotations}
                            draft={draft}
                            tool={tool}
                            onDraftAdd={onDraftAdd}
                            selectedThreadId={selectedThreadId}
                            hoveredThreadId={hoveredThreadId}
                            onSelectThread={onSelectThread}
                            onHoverThread={onHoverThread}
                            sourceSize={naturalSize}
                            mediaType={isVideo ? 'video' : 'image'}
                        />
                    </Box>
                </Box>
            </Box>
        </Stack>
    );
}
