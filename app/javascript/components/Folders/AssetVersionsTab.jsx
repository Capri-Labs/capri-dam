import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
    Alert,
    Avatar,
    Box,
    Button,
    Checkbox,
    Chip,
    CircularProgress,
    Divider,
    FormControlLabel,
    List,
    ListItem,
    Slider,
    Stack,
    Switch,
    Typography,
} from '@mui/material';
import { CompareArrows, FolderZip, Restore } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';

const DIFF_THRESHOLD = 72;

const interpolate = (template, values = {}) => template.replace(/\{\{(\w+)\}\}/g, (_, key) => values[key] ?? '');

const getCanvasContext = (canvas) => {
    const context = canvas?.getContext('2d');
    if (!context) {
        throw new Error('Canvas 2D context unavailable');
    }
    return context;
};

const renderSourceCanvas = (targetCanvas, sourceCanvas) => {
    if (!targetCanvas || !sourceCanvas) return;

    targetCanvas.width = sourceCanvas.width;
    targetCanvas.height = sourceCanvas.height;

    const context = getCanvasContext(targetCanvas);
    context.clearRect(0, 0, targetCanvas.width, targetCanvas.height);
    context.drawImage(sourceCanvas, 0, 0);
};

const isCrossOriginUrl = (url) => {
    try {
        return new URL(url, window.location.origin).origin !== window.location.origin;
    } catch {
        return false;
    }
};

const loadImage = (url) => new Promise((resolve, reject) => {
    const image = new Image();
    // Only mark the image as CORS-mode for genuinely cross-origin URLs (e.g.
    // a production CDN preview URL). Setting `crossOrigin` unconditionally —
    // including for same-origin, cookie-authenticated preview URLs like
    // `/api/v1/assets/local/:uuid` — makes the browser omit session cookies
    // from the request, so it 401s/redirects to the sign-in page and the
    // image silently fails to load, breaking the diff view for every real
    // signed-in user in development/self-hosted deployments without a CDN.
    if (url && !url.startsWith('data:') && isCrossOriginUrl(url)) {
        image.crossOrigin = 'anonymous';
    }
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error(`Failed to load image: ${url}`));
    image.src = url;
});

const isCanvasSecurityError = (error) => error?.name === 'SecurityError' || /cross-origin|tainted/i.test(error?.message || '');

const buildDiffCanvases = async (beforeUrl, afterUrl) => {
    const [beforeImage, afterImage] = await Promise.all([loadImage(beforeUrl), loadImage(afterUrl)]);
    const width = Math.max(beforeImage.width || 1, afterImage.width || 1);
    const height = Math.max(beforeImage.height || 1, afterImage.height || 1);

    const beforeCanvas = document.createElement('canvas');
    const afterCanvas = document.createElement('canvas');
    const diffCanvas = document.createElement('canvas');

    [beforeCanvas, afterCanvas, diffCanvas].forEach((canvas) => {
        canvas.width = width;
        canvas.height = height;
    });

    const beforeContext = getCanvasContext(beforeCanvas);
    const afterContext = getCanvasContext(afterCanvas);
    const diffContext = getCanvasContext(diffCanvas);

    beforeContext.clearRect(0, 0, width, height);
    afterContext.clearRect(0, 0, width, height);
    diffContext.clearRect(0, 0, width, height);

    beforeContext.drawImage(beforeImage, 0, 0);
    afterContext.drawImage(afterImage, 0, 0);

    const beforePixels = beforeContext.getImageData(0, 0, width, height);
    const afterPixels = afterContext.getImageData(0, 0, width, height);
    const diffPixels = diffContext.createImageData(width, height);

    for (let index = 0; index < beforePixels.data.length; index += 4) {
        const redDelta = Math.abs(beforePixels.data[index] - afterPixels.data[index]);
        const greenDelta = Math.abs(beforePixels.data[index + 1] - afterPixels.data[index + 1]);
        const blueDelta = Math.abs(beforePixels.data[index + 2] - afterPixels.data[index + 2]);
        const alphaDelta = Math.abs(beforePixels.data[index + 3] - afterPixels.data[index + 3]);
        const totalDelta = redDelta + greenDelta + blueDelta + alphaDelta;

        if (totalDelta > DIFF_THRESHOLD) {
            diffPixels.data[index] = 255;
            diffPixels.data[index + 1] = 0;
            diffPixels.data[index + 2] = 153;
            diffPixels.data[index + 3] = 170;
        }
    }

    diffContext.putImageData(diffPixels, 0, 0);

    return { width, height, beforeCanvas, afterCanvas, diffCanvas };
};

export default function AssetVersionsTab({ asset, onAssetUpdated }) {
    const { t } = useTranslation();
    const translate = (key, defaultValue, options = {}) => {
        const result = t(key, options);
        if (result === key || (options.count != null && result === `${key}:${options.count}`)) {
            return interpolate(defaultValue, options);
        }
        return result;
    };
    const notify = useNotify();
    const [versions, setVersions] = useState([]);
    const [isLoadingVersions, setIsLoadingVersions] = useState(false);
    const [selectedVersionIds, setSelectedVersionIds] = useState([]);
    const [isCompareMode, setIsCompareMode] = useState(false);
    const [showDiffOverlay, setShowDiffOverlay] = useState(true);
    const [blendValue, setBlendValue] = useState(35);
    const [isRenderingDiff, setIsRenderingDiff] = useState(false);
    const [diffError, setDiffError] = useState(null);
    const [compareDimensions, setCompareDimensions] = useState({ width: 1, height: 1 });

    const beforePreviewCanvasRef = useRef(null);
    const afterPreviewCanvasRef = useRef(null);
    const stageBeforeCanvasRef = useRef(null);
    const stageAfterCanvasRef = useRef(null);
    const stageDiffCanvasRef = useRef(null);

    const resetCompareState = () => {
        setSelectedVersionIds([]);
        setIsCompareMode(false);
        setShowDiffOverlay(true);
        setBlendValue(35);
        setIsRenderingDiff(false);
        setDiffError(null);
        setCompareDimensions({ width: 1, height: 1 });
    };

    useEffect(() => {
        if (asset) {
            resetCompareState();
            fetchVersions();
        }
    }, [asset]);

    const fetchVersions = async () => {
        setIsLoadingVersions(true);
        try {
            const res = await fetch(`/api/v1/assets/${asset.id}/versions`);
            if (res.ok) {
                const data = await res.json();
                setVersions(data.versions);
            } else {
                throw new Error('Failed to fetch');
            }
        } catch (error) {
            notify(translate('assetVersionsTab.notifications.failedToLoadVersionHistory', 'Failed to load version history.'), 'error');
        } finally {
            setIsLoadingVersions(false);
        }
    };

    const handleRestoreVersion = async (versionId) => {
        const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
        try {
            const res = await fetch(`/api/v1/assets/${asset.id}/versions/${versionId}/restore`, {
                method: 'POST',
                headers: { 'X-CSRF-Token': csrfToken },
            });

            if (res.ok) {
                notify(translate('assetVersionsTab.notifications.assetRolledBack', 'Asset successfully rolled back to selected version.'), 'success');
                resetCompareState();
                fetchVersions();
                if (onAssetUpdated) onAssetUpdated();
            } else {
                throw new Error('Restore failed');
            }
        } catch (error) {
            notify(translate('assetVersionsTab.notifications.failedToRestoreVersion', 'Failed to restore version.'), 'error');
        }
    };

    const selectedVersions = useMemo(() => versions
        .filter((version) => selectedVersionIds.includes(version.id))
        .sort((left, right) => left.version_number - right.version_number), [versions, selectedVersionIds]);

    const beforeVersion = selectedVersions[0];
    const afterVersion = selectedVersions[1];

    useEffect(() => {
        if (!isCompareMode || !beforeVersion?.preview_url || !afterVersion?.preview_url) {
            return undefined;
        }

        let cancelled = false;

        const renderDiff = async () => {
            setIsRenderingDiff(true);
            setDiffError(null);

            try {
                const canvases = await buildDiffCanvases(beforeVersion.preview_url, afterVersion.preview_url);
                if (cancelled) return;

                setCompareDimensions({ width: canvases.width, height: canvases.height });
                renderSourceCanvas(beforePreviewCanvasRef.current, canvases.beforeCanvas);
                renderSourceCanvas(afterPreviewCanvasRef.current, canvases.afterCanvas);
                renderSourceCanvas(stageBeforeCanvasRef.current, canvases.beforeCanvas);
                renderSourceCanvas(stageAfterCanvasRef.current, canvases.afterCanvas);
                renderSourceCanvas(stageDiffCanvasRef.current, canvases.diffCanvas);
            } catch (error) {
                if (cancelled) return;
                setDiffError(isCanvasSecurityError(error) ? 'cross-origin' : 'generic');
            } finally {
                if (!cancelled) {
                    setIsRenderingDiff(false);
                }
            }
        };

        renderDiff();

        return () => {
            cancelled = true;
        };
    }, [isCompareMode, beforeVersion?.id, beforeVersion?.preview_url, afterVersion?.id, afterVersion?.preview_url]);

    const toggleVersionSelection = (versionId) => {
        setSelectedVersionIds((current) => {
            if (current.includes(versionId)) {
                return current.filter((id) => id !== versionId);
            }
            if (current.length >= 2) {
                return current;
            }
            return [...current, versionId];
        });
    };

    const compareStageSx = {
        position: 'relative',
        width: '100%',
        maxWidth: 720,
        mx: 'auto',
        borderRadius: 2,
        overflow: 'hidden',
        border: '1px solid #cbd5e1',
        bgcolor: '#0f172a',
        aspectRatio: `${compareDimensions.width} / ${compareDimensions.height}`,
    };

    const renderCompareFallback = () => (
        <Stack spacing={2}>
            <Alert severity="info">
                {diffError === 'cross-origin'
                    ? translate('assetVersionsTab.compare.diffUnavailableCrossOrigin', 'Diff overlay is unavailable because one or both preview images block cross-origin canvas access. Side-by-side comparison is still available.')
                    : translate('assetVersionsTab.compare.diffUnavailable', 'Diff overlay is unavailable for these versions. Side-by-side comparison is still available.')}
            </Alert>
            <Stack direction={{ xs: 'column', md: 'row' }} spacing={2}>
                {[beforeVersion, afterVersion].map((version, index) => (
                    <Box key={version.id} sx={{ flex: 1, minWidth: 0 }}>
                        <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#1e293b', mb: 1 }}>
                            {index === 0
                                ? translate('assetVersionsTab.compare.beforeLabel', 'Before (v{{version}})', { version: version.version_number })
                                : translate('assetVersionsTab.compare.afterLabel', 'After (v{{version}})', { version: version.version_number })}
                        </Typography>
                        <Box
                            component="img"
                            src={version.preview_url}
                            alt={translate('assetVersionsTab.compare.previewAlt', 'Version {{version}} preview', { version: version.version_number })}
                            sx={{ width: '100%', maxHeight: 360, objectFit: 'contain', borderRadius: 2, border: '1px solid #cbd5e1', bgcolor: '#fff' }}
                        />
                    </Box>
                ))}
            </Stack>
        </Stack>
    );

    const renderCompareMode = () => (
        <Stack spacing={3}>
            <Stack direction={{ xs: 'column', md: 'row' }} spacing={2} justifyContent="space-between" alignItems={{ xs: 'flex-start', md: 'center' }}>
                <Box>
                    <Typography variant="h6" sx={{ fontWeight: 700, color: '#1e293b' }}>
                        {translate('assetVersionsTab.compare.compareTitle', 'Comparing v{{after}} against v{{before}}', {
                            before: beforeVersion.version_number,
                            after: afterVersion.version_number,
                        })}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                        {translate('assetVersionsTab.compare.instructions', 'Blend the two previews and toggle the highlight overlay to inspect pixel-level changes between versions.')}
                    </Typography>
                </Box>
                <Button variant="outlined" onClick={() => setIsCompareMode(false)} sx={{ textTransform: 'none' }}>
                    {translate('assetVersionsTab.compare.backToTimeline', 'Back to timeline')}
                </Button>
            </Stack>

            {isRenderingDiff ? (
                <Box sx={{ display: 'flex', justifyContent: 'center', p: 6 }}>
                    <CircularProgress />
                </Box>
            ) : diffError ? renderCompareFallback() : (
                <Stack spacing={3}>
                    <Stack direction={{ xs: 'column', lg: 'row' }} spacing={3} alignItems={{ xs: 'stretch', lg: 'center' }}>
                        <Box sx={{ flex: 1, minWidth: 0 }}>
                            <Box sx={compareStageSx} data-testid="version-diff-stage">
                                <Box
                                    component="canvas"
                                    ref={stageAfterCanvasRef}
                                    sx={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}
                                    aria-label={translate('assetVersionsTab.compare.afterCanvas', 'After image canvas')}
                                />
                                <Box
                                    component="canvas"
                                    ref={stageBeforeCanvasRef}
                                    sx={{ position: 'absolute', inset: 0, width: '100%', height: '100%', opacity: blendValue / 100 }}
                                    aria-label={translate('assetVersionsTab.compare.beforeCanvas', 'Before image canvas')}
                                />
                                <Box
                                    component="canvas"
                                    ref={stageDiffCanvasRef}
                                    data-testid="version-diff-overlay-canvas"
                                    sx={{ position: 'absolute', inset: 0, width: '100%', height: '100%', pointerEvents: 'none', opacity: showDiffOverlay ? 1 : 0 }}
                                    aria-label={translate('assetVersionsTab.compare.diffCanvas', 'Difference overlay canvas')}
                                />
                            </Box>
                        </Box>
                        <Stack spacing={2} sx={{ width: { xs: '100%', lg: 280 } }}>
                            <FormControlLabel
                                control={<Switch checked={showDiffOverlay} onChange={(event) => setShowDiffOverlay(event.target.checked)} />}
                                label={translate('assetVersionsTab.compare.toggleOverlay', 'Show diff overlay')}
                            />
                            <Box>
                                <Typography gutterBottom variant="body2" sx={{ fontWeight: 600 }}>
                                    {translate('assetVersionsTab.compare.blendLabel', 'Blend before/after')}
                                </Typography>
                                <Slider
                                    value={blendValue}
                                    onChange={(_event, value) => setBlendValue(Array.isArray(value) ? value[0] : value)}
                                    min={0}
                                    max={100}
                                    valueLabelDisplay="auto"
                                    aria-label={translate('assetVersionsTab.compare.blendLabel', 'Blend before/after')}
                                />
                            </Box>
                            <Typography variant="caption" color="text.secondary">
                                {translate('assetVersionsTab.compare.overlayHint', 'Move the slider toward 100 to emphasize the earlier version, or leave it low to inspect the current version with diff highlights.')}
                            </Typography>
                        </Stack>
                    </Stack>

                    <Stack direction={{ xs: 'column', md: 'row' }} spacing={2}>
                        <Box sx={{ flex: 1, minWidth: 0 }}>
                            <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#1e293b', mb: 1 }}>
                                {translate('assetVersionsTab.compare.beforeLabel', 'Before (v{{version}})', { version: beforeVersion.version_number })}
                            </Typography>
                            <Box sx={{ border: '1px solid #cbd5e1', borderRadius: 2, bgcolor: '#fff', p: 1.5 }}>
                                <Box component="canvas" ref={beforePreviewCanvasRef} sx={{ width: '100%', height: 'auto', display: 'block' }} />
                            </Box>
                        </Box>
                        <Box sx={{ flex: 1, minWidth: 0 }}>
                            <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#1e293b', mb: 1 }}>
                                {translate('assetVersionsTab.compare.afterLabel', 'After (v{{version}})', { version: afterVersion.version_number })}
                            </Typography>
                            <Box sx={{ border: '1px solid #cbd5e1', borderRadius: 2, bgcolor: '#fff', p: 1.5 }}>
                                <Box component="canvas" ref={afterPreviewCanvasRef} sx={{ width: '100%', height: 'auto', display: 'block' }} />
                            </Box>
                        </Box>
                    </Stack>
                </Stack>
            )}
        </Stack>
    );

    const renderTimeline = () => (
        <Stack spacing={3}>
            {versions.length >= 2 && (
                <Box sx={{ border: '1px solid #e2e8f0', borderRadius: 2, bgcolor: '#f8fafc', p: 2.5 }}>
                    <Stack direction={{ xs: 'column', lg: 'row' }} spacing={2} justifyContent="space-between" alignItems={{ xs: 'flex-start', lg: 'center' }}>
                        <Box>
                            <Typography variant="subtitle1" sx={{ fontWeight: 700, color: '#1e293b' }}>
                                {translate('assetVersionsTab.compare.title', 'Compare versions')}
                            </Typography>
                            <Typography variant="body2" color="text.secondary">
                                {translate('assetVersionsTab.compare.selectionHint', 'Select any two versions to open a side-by-side preview with a pixel-diff overlay.')}
                            </Typography>
                        </Box>
                        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1.5}>
                            <Button
                                variant="outlined"
                                onClick={() => setSelectedVersionIds([])}
                                disabled={selectedVersionIds.length === 0}
                                sx={{ textTransform: 'none' }}
                            >
                                {translate('assetVersionsTab.compare.clearSelection', 'Clear selection')}
                            </Button>
                            <Button
                                variant="contained"
                                startIcon={<CompareArrows />}
                                onClick={() => setIsCompareMode(true)}
                                disabled={selectedVersionIds.length !== 2}
                                sx={{ bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' }, textTransform: 'none' }}
                            >
                                {translate('assetVersionsTab.compare.open', 'Compare selected')}
                            </Button>
                        </Stack>
                    </Stack>
                    <Typography variant="caption" sx={{ display: 'block', mt: 1.5, color: '#64748b' }}>
                        {translate('assetVersionsTab.compare.selectedCount', '{{count}} of 2 versions selected', { count: selectedVersionIds.length })}
                    </Typography>
                </Box>
            )}

            <List sx={{ bgcolor: '#fff', border: '1px solid #e2e8f0', borderRadius: 2, p: 0 }}>
                {versions.map((version, index) => {
                    const compareDisabled = !selectedVersionIds.includes(version.id) && selectedVersionIds.length >= 2;
                    const hasPreview = Boolean(version.preview_url);

                    return (
                        <React.Fragment key={version.id}>
                            <ListItem sx={{ p: 3, display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 2 }}>
                                <Box sx={{ display: 'flex', gap: 2, minWidth: 0 }}>
                                    <Avatar sx={{ bgcolor: version.is_active ? '#4f46e5' : '#f1f5f9', color: version.is_active ? '#fff' : '#64748b', fontWeight: 700, width: 48, height: 48 }}>
                                        v{version.version_number}
                                    </Avatar>

                                    <Box>
                                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 0.5, flexWrap: 'wrap' }}>
                                            <Typography variant="subtitle1" sx={{ fontWeight: 700, color: '#1e293b' }}>
                                                {version.action_type}
                                            </Typography>
                                            {version.is_active && (
                                                <Chip label={translate('assetVersionsTab.currentActive', 'Current Active')} size="small" sx={{ bgcolor: '#eef2ff', color: '#4f46e5', fontWeight: 700, height: 20 }} />
                                            )}
                                            {!hasPreview && (
                                                <Chip label={translate('assetVersionsTab.compare.missingPreview', 'Preview unavailable')} size="small" sx={{ bgcolor: '#fef3c7', color: '#92400e', fontWeight: 700, height: 20 }} />
                                            )}
                                        </Box>

                                        <Typography variant="body2" color="text.secondary" sx={{ mb: 0.5 }}>
                                            {translate('assetVersionsTab.savedOn', 'Saved on')} {version.created_at} {translate('assetVersionsTab.by', 'by')} <strong>{version.created_by}</strong>
                                        </Typography>

                                        <Typography variant="caption" sx={{ color: '#64748b', display: 'flex', alignItems: 'center', gap: 0.5 }}>
                                            <FolderZip fontSize="small" sx={{ fontSize: 14 }} /> {translate('assetVersionsTab.fileSize', 'File Size')}: {version.size}
                                        </Typography>
                                    </Box>
                                </Box>

                                <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1.5} alignItems={{ xs: 'stretch', sm: 'center' }}>
                                    {versions.length >= 2 && (
                                        <FormControlLabel
                                            control={(
                                                <Checkbox
                                                    checked={selectedVersionIds.includes(version.id)}
                                                    onChange={() => toggleVersionSelection(version.id)}
                                                    disabled={compareDisabled || !hasPreview}
                                                />
                                            )}
                                            label={translate('assetVersionsTab.compare.selectVersionLabel', 'Compare v{{version}}', { version: version.version_number })}
                                            sx={{ mr: 0 }}
                                        />
                                    )}

                                    {!version.is_active && (
                                        <Button
                                            variant="outlined"
                                            startIcon={<Restore />}
                                            onClick={() => handleRestoreVersion(version.id)}
                                            sx={{ color: '#4f46e5', borderColor: '#c7d2fe', '&:hover': { bgcolor: '#eef2ff' }, textTransform: 'none' }}
                                        >
                                            {translate('assetVersionsTab.restore', 'Restore')}
                                        </Button>
                                    )}
                                </Stack>
                            </ListItem>

                            {index < versions.length - 1 && <Divider component="li" />}
                        </React.Fragment>
                    );
                })}
            </List>
        </Stack>
    );

    return (
        <Box sx={{ p: 4 }}>
            <Typography variant="h6" sx={{ fontWeight: 700, mb: 1 }}>{translate('assetVersionsTab.title', 'Version Timeline')}</Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mb: 4 }}>
                {translate('assetVersionsTab.description', 'View previous iterations of this asset. Restoring a version makes it the active file without deleting newer edits.')}
            </Typography>

            {isLoadingVersions ? (
                <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
                    <CircularProgress />
                </Box>
            ) : isCompareMode && beforeVersion && afterVersion ? renderCompareMode() : renderTimeline()}
        </Box>
    );
}
