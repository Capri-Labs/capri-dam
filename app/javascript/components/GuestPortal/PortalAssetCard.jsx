import React from 'react';
import { useTranslation } from 'react-i18next';
import {
    Box, Button, Card, CardContent, Chip, Stack, Tooltip, Typography,
} from '@mui/material';
import DownloadIcon from '@mui/icons-material/Download';
import LockOutlinedIcon from '@mui/icons-material/LockOutlined';
import InsertDriveFileOutlinedIcon from '@mui/icons-material/InsertDriveFileOutlined';

/** Human-readable file size. Bytes are meaningless to the person collecting. */
function formatBytes(bytes) {
    if (!bytes || Number.isNaN(Number(bytes))) return null;
    const units = ['B', 'KB', 'MB', 'GB'];
    let value = Number(bytes);
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024;
        unit += 1;
    }
    return `${value < 10 && unit > 0 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
}

/**
 * One collectable file.
 *
 * A view-only asset shows a disabled control with a reason rather than no
 * control at all: a partner who cannot find a download button assumes the
 * portal is broken and emails to ask, whereas "view only" answers the
 * question on the page.
 */
export default function PortalAssetCard({ asset, accent }) {
    const { t } = useTranslation();
    const size = formatBytes(asset.byte_size);
    // The preview endpoint streams the original bytes, so pointing an <img> at
    // a PDF or a video yields a broken-image icon. Only render one when the
    // file is actually an image; anything else gets a neutral file glyph.
    const isImage = String(asset.content_type || '').startsWith('image/');

    return (
        <Card variant="outlined" data-testid="portal-asset-card" sx={{ display: 'flex', flexDirection: 'column' }}>
            <Box sx={{
                height: 160,
                bgcolor: 'grey.100',
                display: 'grid',
                placeItems: 'center',
                overflow: 'hidden',
            }}
            >
                {isImage ? (
                    <Box
                        component="img"
                        src={asset.preview_url}
                        alt={asset.title}
                        loading="lazy"
                        sx={{ width: '100%', height: '100%', objectFit: 'cover' }}
                    />
                ) : (
                    <InsertDriveFileOutlinedIcon
                        data-testid="portal-asset-placeholder"
                        sx={{ fontSize: 48, color: 'text.disabled' }}
                    />
                )}
            </Box>

            <CardContent sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', gap: 1 }}>
                <Typography variant="subtitle2" fontWeight={700} noWrap title={asset.title}>
                    {asset.title}
                </Typography>

                <Stack direction="row" spacing={1} alignItems="center" useFlexGap sx={{ flexWrap: 'wrap' }}>
                    {size && <Chip size="small" label={size} variant="outlined" />}
                    {!asset.downloadable && (
                        <Chip
                            size="small"
                            icon={<LockOutlinedIcon />}
                            label={t('portal.viewOnly')}
                            data-testid="portal-view-only"
                        />
                    )}
                </Stack>

                <Box sx={{ mt: 'auto', pt: 1 }}>
                    {asset.downloadable ? (
                        <Button
                            fullWidth
                            variant="contained"
                            startIcon={<DownloadIcon />}
                            href={asset.download_url}
                            data-testid="portal-download-button"
                            sx={{ bgcolor: accent, '&:hover': { bgcolor: accent, filter: 'brightness(0.92)' } }}
                        >
                            {t('portal.download')}
                        </Button>
                    ) : (
                        <Tooltip title={t('portal.viewOnlyHint')}>
                            {/* A disabled button cannot host a tooltip, so the
                                span carries the listener. */}
                            <span>
                                <Button fullWidth variant="outlined" disabled startIcon={<DownloadIcon />}>
                                    {t('portal.download')}
                                </Button>
                            </span>
                        </Tooltip>
                    )}
                </Box>
            </CardContent>
        </Card>
    );
}
