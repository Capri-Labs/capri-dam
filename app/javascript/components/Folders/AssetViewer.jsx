import React, {useEffect, useState} from 'react';
import {
    Dialog, AppBar, Toolbar, IconButton, Typography, Box, Grid,
    Button, Divider, Chip, Tabs, Tab, Paper, List, ListItem,
    ListItemText, Tooltip, Menu, MenuItem, Collapse
} from '@mui/material';
import {
    Close,
    Edit,
    Download,
    InfoOutlined,
    History,
    AccountTreeOutlined,
    AutoAwesome,
    LocalOffer,
    ChevronRight,
    ExpandMore,
    ContentCopy, PushPin, Share, PolicyOutlined, SchemaOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import ImageEditorDialog from './ImageEditorDialog';
import { isWebRenderableImage } from '../../utils/webRenderableMimeTypes';
import WorkflowPanel from '../WorkflowPanel';
import AssetTagsEditor from './AssetTagsEditor';
import PinToCollectionDialog from './PinToCollectionDialog';
import { useNotify } from '../../context/NotificationContext';

import AssetVersionsTab from './AssetVersionsTab';
import AssetAuditTab from './AssetAuditTab';
import AssetMetadataPanel from './AssetMetadataPanel';
import AssetStatsPopover from './AssetStatsPopover';

const interpolate = (template, values = {}) => template.replace(/\{\{(\w+)\}\}/g, (_, key) => values[key] ?? '');

function TabPanel(props) {
    const { children, value, index, ...other } = props;
    return (
        <div role="tabpanel" hidden={value !== index} style={{ height: '100%', overflowY: 'auto', overflowX: 'auto' }} {...other}>
            {value === index && <Box sx={{ pt: 3 }}>{children}</Box>}
        </div>
    );
}

export default function AssetViewer({ asset: initialAsset, open, onClose, onAssetUpdated }) {
    const { t } = useTranslation();
    const translate = (key, defaultValue, options = {}) => {
        const result = t(key, options);
        if (result === key || (options.count != null && result === `${key}:${options.count}`)) {
            return interpolate(defaultValue, options);
        }
        return result;
    };
    const notify = useNotify();
    const [asset, setAsset] = useState(initialAsset);
    const [editorOpen, setEditorOpen] = useState(false);
    const [tagsEditorOpen, setTagsEditorOpen] = useState(false); //  State for Tags Editor
    const [pinOpen, setPinOpen] = useState(false);
    const [activeTab, setActiveTab] = useState(0);
    const [downloadMenuAnchor, setDownloadMenuAnchor] = useState(null);
    // EXIF/IPTC/XMP raw metadata block in the Info tab — collapsed by default
    // since it's a large, rarely-needed JSON dump.
    const [exifExpanded, setExifExpanded] = useState(false);
    // Full raw `properties` JSON blob — a separate, also-collapsed-by-default
    // section so users can inspect *everything* stored on the asset (not just
    // the curated EXIF/IPTC/XMP subset).
    const [rawMetadataExpanded, setRawMetadataExpanded] = useState(false);

    // Keep it synced if the parent explicitly passes a new asset
    useEffect(() => {
        setAsset(initialAsset);
    }, [initialAsset]);

    // Record a "view" the moment the viewer is opened for a given asset. This
    // runs client-side (not on the read-only GET /show) so opening the same
    // asset twice counts as two views, matching how most DAM products define it.
    useEffect(() => {
        if (open && asset?.id) {
            trackUsageEvent(asset.id, 'view');
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [open, asset?.id]);

    if (!asset) return null;

    // Fire-and-forget usage tracking. See Api::V1::AssetsController#track_event
    // for why this is called at the moment of user intent rather than derived
    // from CDN logs (the actual bytes are often served straight from CDN/S3).
    const trackUsageEvent = (assetId, event) => {
        fetch(`/api/v1/assets/${assetId}/track_event`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ event }),
        }).catch(() => { /* stats are non-critical; ignore failures */ });
    };

    const handleTabChange = (event, newValue) => setActiveTab(newValue);

    const handleCopyUrl = () => {
        navigator.clipboard.writeText(asset.url);
        trackUsageEvent(asset.id, 'share');
        notify(translate('assetViewer.notifications.assetUrlCopiedToClipboard', 'Asset URL copied to clipboard!'), "success");
    };

    const handleDownloadWatermarked = () => {
        setDownloadMenuAnchor(null);
        notify(translate('assetViewer.notifications.generatingSecureWatermarkedProxy', 'Generating secure watermarked proxy...'), "info");

        // Use standard browser navigation to trigger the Rails send_data stream
        // (the controller itself records this as a confirmed download).
        window.location.href = `/api/v1/assets/${asset.id}/watermarked`;
    };

    const handleDownload = async () => {
        trackUsageEvent(asset.id, 'download');
        try {
            // Fetch the image to trigger a programmatic browser download
            const response = await fetch(asset.url);
            const blob = await response.blob();
            const blobUrl = window.URL.createObjectURL(blob);

            const link = document.createElement('a');
            link.href = blobUrl;
            link.download = asset.properties?.original_filename || asset.title || translate('assetViewer.download.defaultFilename', 'download');
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            window.URL.revokeObjectURL(blobUrl);

            notify(translate('assetViewer.notifications.downloadStarted', 'Download started'), "info");
        } catch (error) {
            // Fallback
            window.open(asset.url, '_blank');
        }
    };

    const isImage = asset.properties?.content_type?.startsWith('image/');
    const hasGeneratedPreview = Boolean(
        asset.properties?.preview_storage_path || asset.properties?.preview_content_type
    );
    const canPreview = isImage || hasGeneratedPreview;
    // The interactive Image Editor renders the *original* file directly (not
    // the flattened preview), so it only works for formats browsers can decode
    // natively. Trust the backend-computed `editable` flag when present (see
    // Api::V1::AssetsController#web_renderable_image?); fall back to a
    // client-side check by content type for any response shape that predates it.
    const canEditImage = asset.editable ?? (isImage && isWebRenderableImage(asset.properties?.content_type));
    const displayName = asset.title || asset.name || translate('assetViewer.fallbacks.unknownFile', 'Unknown File');
    const fileSize = asset.properties?.file_size || translate('assetViewer.fallbacks.unknownSize', 'Unknown Size');
    const statusLabel = asset.status
        ? translate(`asset.status.${asset.status}`, asset.status)
        : translate('asset.status.pending', 'Pending');

    // Prefer a generated web preview (e.g. flattened PNG for PSD/TIFF) for
    // display; the original URL is still used for downloads.
    const displayImageUrl = asset.preview_url || asset.url;
    const previewSrc = displayImageUrl
        ? `${displayImageUrl}${displayImageUrl.includes('?') ? '&' : '?'}v=${asset.version || Date.now()}`
        : null;

    const editorState = asset.properties?.editor_state || {};
    const adjustments = editorState.adjustments || {};
    const geometry = editorState.geometry || {};

    // Safely extract tags to show the count
    const props = typeof asset.properties === 'string' ? JSON.parse(asset.properties) : (asset.properties || {});
    const totalTagsCount = (props.tags?.length || 0) + (props.ai_tags?.faces?.length || 0) + (props.ai_tags?.text?.length || 0);

    const liveFilterStyle = `
        brightness(${100 + (adjustments.brightness || 0)}%)
        contrast(${100 + (adjustments.contrast || 0)}%)
        saturate(${100 + (adjustments.saturation || 0)}%)
        sepia(${adjustments.warmth > 0 ? adjustments.warmth / 2 : 0}%)
        hue-rotate(${adjustments.tint || 0}deg)
    `;

    return (
        <Dialog fullScreen open={open} onClose={onClose}>
            <AppBar sx={{ position: 'relative', bgcolor: '#1e293b', boxShadow: 'none' }}>
                <Toolbar>
                    <IconButton edge="start" color="inherit" onClick={onClose} aria-label={translate('assetViewer.actions.closeAriaLabel', 'close')}><Close /></IconButton>
                    <Typography sx={{ ml: 2, flex: 1 }} variant="h6" component="div" noWrap>{displayName}</Typography>

                    <AssetStatsPopover asset={asset} />

                    <Tooltip title={translate('assetViewer.toolbar.pinToCollection', 'Pin to Collection')}>
                        <IconButton color="inherit" onClick={() => setPinOpen(true)} data-testid="asset-pin-to-collection-toggle"><PushPin fontSize="small" /></IconButton>
                    </Tooltip>

                    <Tooltip title={translate('assetViewer.toolbar.shareAsset', 'Share Asset')}>
                        <IconButton color="inherit" onClick={() => notify(translate('assetViewer.notifications.shareDialogComingSoon', 'Share dialog coming soon'), "info")}><Share fontSize="small" /></IconButton>
                    </Tooltip>

                    <Tooltip title={translate('assetViewer.toolbar.copyImageUrl', 'Copy Image URL')}>
                        <IconButton color="inherit" onClick={handleCopyUrl}><ContentCopy fontSize="small" /></IconButton>
                    </Tooltip>

                    <Divider orientation="vertical" variant="middle" flexItem sx={{ borderColor: 'rgba(255,255,255,0.2)', mx: 1 }} />

                    {/*  MOVED: Launch Image Editor Button */}
                    {isImage && (
                        <Tooltip title={canEditImage ? '' : translate('assetViewer.toolbar.editUnsupportedTooltip', "Editing isn't supported for this file format (e.g. PSD, TIFF, RAW). Download the original or view the generated preview instead.")}>
                            <span>
                                <Button
                                    variant="outlined"
                                    startIcon={<Edit />}
                                    onClick={() => setEditorOpen(true)}
                                    disabled={!canEditImage}
                                    sx={{ color: '#fff', borderColor: 'rgba(255,255,255,0.5)', '&:hover': { borderColor: '#fff' }, mr: 1, textTransform: 'none',
                                          '&.Mui-disabled': { color: 'rgba(255,255,255,0.35)', borderColor: 'rgba(255,255,255,0.2)' } }}
                                >
                                    {translate('assetViewer.toolbar.editImage', 'Edit Image')}
                                </Button>
                            </span>
                        </Tooltip>
                    )}

                    <Button
                        variant="contained"
                        startIcon={<Download />}
                        onClick={(e) => setDownloadMenuAnchor(e.currentTarget)}
                        sx={{ bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' }, textTransform: 'none' }}
                    >
                        {translate('assetViewer.download.options', 'Download Options')}
                    </Button>
                    <Menu
                        anchorEl={downloadMenuAnchor}
                        open={Boolean(downloadMenuAnchor)}
                        onClose={() => setDownloadMenuAnchor(null)} slotProps={{paper: { elevation: 3, sx: { mt: 1, minWidth: 200, borderRadius: 2 } } }}
                    >
                        <MenuItem onClick={() => { setDownloadMenuAnchor(null); handleDownload(); }}>
                            <ListItemText primary={translate('assetViewer.download.original', 'Download Original')} secondary={translate('assetViewer.download.originalDescription', 'High-resolution source file')} />
                        </MenuItem>
                        <Divider />
                        <MenuItem onClick={handleDownloadWatermarked}>
                            <ListItemText
                                primary={translate('assetViewer.download.secureProxy', 'Download Secure Proxy')}
                                secondary={translate('assetViewer.download.secureProxyDescription', 'Includes unremovable watermark')}
                                slotProps={{ primary: { color: 'error', fontWeight: 600 } }}
                            />
                        </MenuItem>
                    </Menu>
                </Toolbar>
            </AppBar>

            <Grid container wrap="nowrap" sx={{ height: 'calc(100vh - 64px)', overflow: 'hidden' }}>
                {/* LEFT PANE: 65% Image Preview — fixed width/position; must
                    never reflow or resize when the right-hand tab content
                    changes (e.g. switching to a tab with a wide table/JSON
                    dump). `flexShrink: 0` pins its size; `overflow: hidden`
                    stops it from ever needing to scroll itself. */}
                <Grid sx={{ width: '65%', flexShrink: 0, bgcolor: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center', p: 4, borderRight: '1px solid #cbd5e1', overflow: 'hidden' }}>
                    {canPreview && previewSrc ? (
                        <Box component="img"
                             src={previewSrc}
                             alt={displayName}
                             sx={{
                                 maxWidth: '100%',
                                 maxHeight: '100%',
                                 objectFit: 'contain',
                                 boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.1)',
                                 filter: liveFilterStyle,
                                 transform: `scaleX(${geometry.flip_horizontal ? -1 : 1}) rotate(${geometry.rotate || 0}deg)`
                        }} />
                    ) : (
                        <Typography color="textSecondary">{translate('assetViewer.preview.notAvailableForFileType', 'Preview not available for this file type.')}</Typography>
                    )}
                </Grid>

                {/* RIGHT PANE: 35% Tabbed Inspector — `minWidth: 0` is required
                    so this flex item can never be forced wider than its 35%
                    allocation by tab content (tables, JSON, long text); any
                    overflow scrolls *within* this pane instead of pushing the
                    image pane around. */}
                <Grid sx={{ width: '35%', minWidth: 0, flexShrink: 1, bgcolor: '#ffffff', display: 'flex', flexDirection: 'column' }}>
                    <Box sx={{ borderBottom: 1, borderColor: 'divider', px: 2, pt: 1 }}>
                        <Tabs value={activeTab} onChange={handleTabChange} variant="scrollable" scrollButtons="auto" sx={{ '& .MuiTab-root': { textTransform: 'none', minWidth: 'auto', px: 2 } }}>
                            <Tab icon={<InfoOutlined fontSize="small" />} iconPosition="start" label={translate('assetViewer.tabs.info', 'Info')} />
                            <Tab icon={<SchemaOutlined fontSize="small" />} iconPosition="start" label={translate('assetViewer.tabs.metadata', 'Metadata')} />
                            <Tab icon={<History fontSize="small" />} iconPosition="start" label={translate('assetViewer.tabs.versions', 'Versions')} />
                            <Tab icon={<PolicyOutlined fontSize="small" />} iconPosition="start" label={translate('assetViewer.tabs.audit', 'Audit')} />
                            <Tab icon={<AccountTreeOutlined fontSize="small" />} iconPosition="start" label={translate('assetViewer.tabs.workflows', 'Workflows')} />
                            <Tab icon={<AutoAwesome fontSize="small" />} iconPosition="start" label={translate('assetViewer.tabs.aiEngine', 'AI Engine')} />
                        </Tabs>
                    </Box>

                    <Box sx={{ flexGrow: 1, minWidth: 0, minHeight: 0, overflow: 'hidden', px: 3 }}>

                        {/* TAB 0: INFO */}
                        <TabPanel value={activeTab} index={0}>
                            <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 2 }}>
                                <Typography variant="subtitle1" fontWeight="700">{translate('assetViewer.info.generalMetadata', 'General Metadata')}</Typography>
                                <Chip label={statusLabel} color={asset.status === 'approved' ? 'success' : 'warning'} size="small" />
                            </Box>

                            {/*   The Tags Entry Point matching your UI mock */}
                            <Paper
                                onClick={() => setTagsEditorOpen(true)}
                                elevation={0}
                                sx={{ p: 2, mb: 4, display: 'flex', alignItems: 'center', justifyContent: 'space-between', bgcolor: '#f8fafc', border: '1px solid #e2e8f0', borderRadius: 2, cursor: 'pointer', transition: 'all 0.2s', '&:hover': { borderColor: '#4f46e5', bgcolor: '#eef2ff' } }}
                            >
                                <Box sx={{ display: 'flex', alignItems: 'center' }}>
                                    <LocalOffer sx={{ color: '#475569', mr: 2 }} />
                                    <Box>
                                        <Typography variant="body2" fontWeight="700" color="textPrimary">{translate('assetViewer.info.tagsCount', '{{count}} tags', { count: totalTagsCount })}</Typography>
                                        <Typography variant="caption" color="textSecondary">{translate('assetViewer.info.aiRecognizedAndManual', 'AI-recognized & Manual')}</Typography>
                                    </Box>
                                </Box>
                                <IconButton size="small" sx={{ bgcolor: '#4f46e5', color: '#fff', '&:hover': { bgcolor: '#4338ca' } }}>
                                    <ChevronRight fontSize="small" />
                                </IconButton>
                            </Paper>

                            <List dense disablePadding sx={{ mb: 4 }}>
                                <ListItem disableGutters><ListItemText primary={translate('assetViewer.info.fileName', 'File Name')} secondary={displayName} /></ListItem>
                                <ListItem disableGutters><ListItemText primary={translate('assetViewer.info.dateAdded', 'Date Added')} secondary={new Date(asset.created_at).toLocaleString()} /></ListItem>
                                <ListItem disableGutters><ListItemText primary={translate('assetViewer.info.resolution', 'Resolution')} secondary={asset.properties?.resolution || translate('assetViewer.fallbacks.unknown', 'Unknown')} /></ListItem>
                                <ListItem disableGutters><ListItemText primary={translate('assetViewer.info.fileSize', 'File Size')} secondary={fileSize} /></ListItem>
                                {asset.properties?.creator && (
                                    <ListItem disableGutters><ListItemText primary={translate('assetViewer.info.creator', 'Creator')} secondary={[].concat(asset.properties.creator).join(', ')} /></ListItem>
                                )}
                                {asset.properties?.copyright && (
                                    <ListItem disableGutters><ListItemText primary={translate('assetViewer.info.copyright', 'Copyright')} secondary={asset.properties.copyright} /></ListItem>
                                )}
                                {(asset.properties?.camera_make || asset.properties?.camera_model) && (
                                    <ListItem disableGutters><ListItemText primary={translate('assetViewer.info.camera', 'Camera')} secondary={[asset.properties.camera_make, asset.properties.camera_model].filter(Boolean).join(' ')} /></ListItem>
                                )}
                                {asset.properties?.lens && (
                                    <ListItem disableGutters><ListItemText primary={translate('assetViewer.info.lens', 'Lens')} secondary={asset.properties.lens} /></ListItem>
                                )}
                                {asset.properties?.color_mode && (
                                    <ListItem disableGutters><ListItemText primary={translate('assetViewer.info.colorMode', 'Color Mode')} secondary={asset.properties.color_mode} /></ListItem>
                                )}
                                {asset.properties?.metadata_field_count > 0 && (
                                    <ListItem disableGutters><ListItemText primary={translate('assetViewer.info.embeddedMetadataFields', 'Embedded Metadata Fields')} secondary={asset.properties.metadata_field_count} /></ListItem>
                                )}
                            </List>

                            {/* Extract the palette from properties, defaulting to empty array */}
                            {asset.properties?.color_palette && asset.properties.color_palette.length > 0 && (
                                <Box sx={{ mb: 4 }}>
                                    <Typography variant="caption" sx={{ color: '#475569', mb: 1, display: 'block', fontWeight: 600 }}>
                                        {translate('assetViewer.info.dominantPalette', 'Dominant Palette')}
                                    </Typography>
                                    <Box sx={{ display: 'flex', gap: 1 }}>
                                        {asset.properties.color_palette.map((hex, index) => (
                                            <Tooltip title={hex.toUpperCase()} key={index}>
                                                <Box
                                                    sx={{
                                                        width: 32, height: 32, borderRadius: '50%',
                                                        bgcolor: hex,
                                                        border: '1px solid rgba(0,0,0,0.1)',
                                                        boxShadow: 'inset 0 2px 4px rgba(255,255,255,0.2)'
                                                    }}
                                                />
                                            </Tooltip>
                                        ))}
                                    </Box>
                                </Box>
                            )}

                            <Divider sx={{ mb: 3 }} />

                            <Box
                                onClick={() => setExifExpanded((prev) => !prev)}
                                sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer', mb: exifExpanded ? 2 : 0 }}
                            >
                                <Typography variant="subtitle2" fontWeight="700">{translate('assetViewer.info.embeddedMetadataSection', 'EXIF / IPTC / XMP Data')}</Typography>
                                <IconButton
                                    size="small"
                                    aria-label={exifExpanded
                                        ? translate('assetViewer.info.collapseExifData', 'Collapse EXIF / IPTC / XMP data')
                                        : translate('assetViewer.info.expandExifData', 'Expand EXIF / IPTC / XMP data')}
                                    sx={{
                                        transform: exifExpanded ? 'rotate(180deg)' : 'rotate(0deg)',
                                        transition: 'transform 0.2s',
                                    }}
                                >
                                    <ExpandMore fontSize="small" />
                                </IconButton>
                            </Box>
                            <Collapse in={exifExpanded} unmountOnExit>
                                <Paper elevation={0} sx={{ p: 2, bgcolor: '#f8fafc', border: '1px solid #e2e8f0', borderRadius: 2, maxHeight: 360, overflowY: 'auto' }}>
                                    <Typography component="pre" variant="caption" color="textSecondary" sx={{ fontFamily: 'monospace', whiteSpace: 'pre-wrap', m: 0 }}>
                                        {asset.properties?.embedded_metadata
                                            ? JSON.stringify(asset.properties.embedded_metadata, null, 2)
                                            : asset.properties?.exif_data
                                                ? JSON.stringify(asset.properties.exif_data, null, 2)
                                                : translate('assetViewer.info.noExifDataExtractedYet', 'No EXIF data extracted yet.')}
                                    </Typography>
                                </Paper>
                            </Collapse>

                            <Divider sx={{ my: 3 }} />

                            <Box
                                onClick={() => setRawMetadataExpanded((prev) => !prev)}
                                sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer', mb: rawMetadataExpanded ? 2 : 0 }}
                            >
                                <Typography variant="subtitle2" fontWeight="700">{translate('assetViewer.info.rawMetadataSection', 'Raw Metadata')}</Typography>
                                <IconButton
                                    size="small"
                                    aria-label={rawMetadataExpanded
                                        ? translate('assetViewer.info.collapseRawMetadata', 'Collapse Raw Metadata')
                                        : translate('assetViewer.info.expandRawMetadata', 'Expand Raw Metadata')}
                                    sx={{
                                        transform: rawMetadataExpanded ? 'rotate(180deg)' : 'rotate(0deg)',
                                        transition: 'transform 0.2s',
                                    }}
                                >
                                    <ExpandMore fontSize="small" />
                                </IconButton>
                            </Box>
                            <Collapse in={rawMetadataExpanded} unmountOnExit>
                                <Paper elevation={0} sx={{ p: 2, bgcolor: '#f8fafc', border: '1px solid #e2e8f0', borderRadius: 2, maxHeight: 360, overflowY: 'auto' }}>
                                    <Typography component="pre" variant="caption" color="textSecondary" sx={{ fontFamily: 'monospace', whiteSpace: 'pre-wrap', m: 0 }}>
                                        {asset.properties && Object.keys(asset.properties).length > 0
                                            ? JSON.stringify(asset.properties, null, 2)
                                            : translate('assetViewer.info.noRawMetadataAvailable', 'No raw metadata available.')}
                                    </Typography>
                                </Paper>
                            </Collapse>
                        </TabPanel>

                        {/* TAB 1: METADATA SCHEMA */}
                        <TabPanel value={activeTab} index={1}>
                            <AssetMetadataPanel
                                asset={asset}
                                onAssetUpdated={(updated) => {
                                    setAsset(updated);
                                    if (onAssetUpdated) onAssetUpdated(updated);
                                }}
                            />
                        </TabPanel>

                        {/* TAB 2: VERSIONS */}
                        <TabPanel value={activeTab} index={2}>
                            <AssetVersionsTab asset={asset} onAssetUpdated={onAssetUpdated} />
                        </TabPanel>
                        {/* TAB 3: AUDIT */}
                        <TabPanel value={activeTab} index={3}><AssetAuditTab asset={asset} /></TabPanel>
                        {/* TAB 4: WORKFLOWS */}
                        <TabPanel value={activeTab} index={4}>
                            <WorkflowPanel assetId={asset.id} onWorkflowUpdate={() => { if (onAssetUpdated) onAssetUpdated(asset); }} />
                        </TabPanel>
                        {/* TAB 5: AI */}
                        <TabPanel value={activeTab} index={5}>
                            <Typography variant="subtitle1" fontWeight="700" sx={{ mb: 2 }}>{translate('assetViewer.ai.semanticAndVisionAnalysis', 'Semantic & Vision Analysis')}</Typography>
                        </TabPanel>

                    </Box>
                </Grid>
            </Grid>

            {/* OVERLAYS */}
            {canEditImage && (
                <ImageEditorDialog
                    asset={asset}
                    open={editorOpen}
                    onClose={() => setEditorOpen(false)}
                    onSave={(updatedAsset) => {
                        //  1. Update the local view instantly (Dialog stays open!)
                        setAsset(updatedAsset);

                        //  2. Quietly notify the parent to update the background grid
                        if (onAssetUpdated) onAssetUpdated(updatedAsset);
                    }}
                />
            )}

            {/*  Tags Editor Overlay */}
            <AssetTagsEditor
                asset={asset}
                open={tagsEditorOpen}
                onClose={() => setTagsEditorOpen(false)}
                onSave={(updatedAsset) => {
                    setTagsEditorOpen(false);
                    if (onAssetUpdated) onAssetUpdated(updatedAsset);
                }}
            />

            <PinToCollectionDialog
                open={pinOpen}
                onClose={() => setPinOpen(false)}
                asset={asset}
            />
        </Dialog>
    );
}
