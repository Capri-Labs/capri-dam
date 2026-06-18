import React, {useEffect, useState} from 'react';
import {
    Dialog, AppBar, Toolbar, IconButton, Typography, Box, Grid,
    Button, Divider, Chip, Tabs, Tab, Paper, List, ListItem,
    ListItemText, Tooltip, Menu, MenuItem
} from '@mui/material';
import {
    Close,
    Edit,
    Download,
    InfoOutlined,
    History,
    AnalyticsOutlined,
    AccountTreeOutlined,
    AutoAwesome,
    LocalOffer,
    ChevronRight,
    ContentCopy, PushPin, Share, PolicyOutlined
} from '@mui/icons-material';
import ImageEditorDialog from './ImageEditorDialog';
import WorkflowPanel from '../WorkflowPanel';
import AssetTagsEditor from './AssetTagsEditor';
import PinToCollectionDialog from './PinToCollectionDialog';
import { useNotify } from '../../context/NotificationContext';

import AssetVersionsTab from './AssetVersionsTab';
import AssetStatisticsTab from './AssetStatisticsTab';
import AssetAuditTab from './AssetAuditTab';

function TabPanel(props) {
    const { children, value, index, ...other } = props;
    return (
        <div role="tabpanel" hidden={value !== index} style={{ height: '100%', overflowY: 'auto' }} {...other}>
            {value === index && <Box sx={{ pt: 3 }}>{children}</Box>}
        </div>
    );
}

export default function AssetViewer({ asset: initialAsset, open, onClose, onAssetUpdated }) {
    const notify = useNotify();
    const [asset, setAsset] = useState(initialAsset);
    const [editorOpen, setEditorOpen] = useState(false);
    const [tagsEditorOpen, setTagsEditorOpen] = useState(false); //  State for Tags Editor
    const [pinOpen, setPinOpen] = useState(false);
    const [activeTab, setActiveTab] = useState(0);
    const [downloadMenuAnchor, setDownloadMenuAnchor] = useState(null);

    // Keep it synced if the parent explicitly passes a new asset
    useEffect(() => {
        setAsset(initialAsset);
    }, [initialAsset]);

    if (!asset) return null;

    const handleTabChange = (event, newValue) => setActiveTab(newValue);

    const handleCopyUrl = () => {
        navigator.clipboard.writeText(asset.url);
        notify("Asset URL copied to clipboard!", "success");
    };

    const handleDownloadWatermarked = () => {
        setDownloadMenuAnchor(null);
        notify("Generating secure watermarked proxy...", "info");

        // Use standard browser navigation to trigger the Rails send_data stream
        window.location.href = `/api/v1/assets/${asset.id}/watermarked`;
    };

    const handleDownload = async () => {
        try {
            // Fetch the image to trigger a programmatic browser download
            const response = await fetch(asset.url);
            const blob = await response.blob();
            const blobUrl = window.URL.createObjectURL(blob);

            const link = document.createElement('a');
            link.href = blobUrl;
            link.download = asset.properties?.original_filename || asset.title || 'download';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            window.URL.revokeObjectURL(blobUrl);

            notify("Download started", "info");
        } catch (error) {
            // Fallback
            window.open(asset.url, '_blank');
        }
    };

    const isImage = asset.properties?.content_type?.startsWith('image/');
    const displayName = asset.title || asset.name || "Unknown File";
    const fileSize = asset.properties?.file_size || "Unknown Size";

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
                    <IconButton edge="start" color="inherit" onClick={onClose} aria-label="close"><Close /></IconButton>
                    <Typography sx={{ ml: 2, flex: 1 }} variant="h6" component="div" noWrap>{displayName}</Typography>

                    <Tooltip title="Pin to Collection">
                        <IconButton color="inherit" onClick={() => setPinOpen(true)}><PushPin fontSize="small" /></IconButton>
                    </Tooltip>

                    <Tooltip title="Share Asset">
                        <IconButton color="inherit" onClick={() => notify("Share dialog coming soon", "info")}><Share fontSize="small" /></IconButton>
                    </Tooltip>

                    <Tooltip title="Copy Image URL">
                        <IconButton color="inherit" onClick={handleCopyUrl}><ContentCopy fontSize="small" /></IconButton>
                    </Tooltip>

                    <Divider orientation="vertical" variant="middle" flexItem sx={{ borderColor: 'rgba(255,255,255,0.2)', mx: 1 }} />

                    {/*  MOVED: Launch Image Editor Button */}
                    {isImage && (
                        <Button
                            variant="outlined"
                            startIcon={<Edit />}
                            onClick={() => setEditorOpen(true)}
                            sx={{ color: '#fff', borderColor: 'rgba(255,255,255,0.5)', '&:hover': { borderColor: '#fff' }, mr: 1, textTransform: 'none' }}
                        >
                            Edit Image
                        </Button>
                    )}

                    <Button
                        variant="contained"
                        startIcon={<Download />}
                        onClick={(e) => setDownloadMenuAnchor(e.currentTarget)}
                        sx={{ bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' }, textTransform: 'none' }}
                    >
                        Download Options
                    </Button>
                    <Menu
                        anchorEl={downloadMenuAnchor}
                        open={Boolean(downloadMenuAnchor)}
                        onClose={() => setDownloadMenuAnchor(null)}
                        PaperProps={{ elevation: 3, sx: { mt: 1, minWidth: 200, borderRadius: 2 } }}
                    >
                        <MenuItem onClick={() => { setDownloadMenuAnchor(null); handleDownload(); }}>
                            <ListItemText primary="Download Original" secondary="High-resolution source file" />
                        </MenuItem>
                        <Divider />
                        <MenuItem onClick={handleDownloadWatermarked}>
                            <ListItemText
                                primary="Download Secure Proxy"
                                secondary="Includes unremovable watermark"
                                primaryTypographyProps={{ color: 'error', fontWeight: 600 }}
                            />
                        </MenuItem>
                    </Menu>
                </Toolbar>
            </AppBar>

            <Grid container sx={{ height: 'calc(100vh - 64px)' }}>
                {/* LEFT PANE: 60% Image Preview */}
                <Grid item sx={{ width: '65%', bgcolor: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center', p: 4, borderRight: '1px solid #cbd5e1' }}>
                    {isImage && asset.url ? (
                        <Box component="img"
                             src={`${asset.url}?v=${asset.version || Date.now()}`}
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
                        <Typography color="textSecondary">Preview not available for this file type.</Typography>
                    )}
                </Grid>

                {/* RIGHT PANE: 40% Tabbed Inspector */}
                <Grid item sx={{ width: '35%', bgcolor: '#ffffff', display: 'flex', flexDirection: 'column' }}>
                    <Box sx={{ borderBottom: 1, borderColor: 'divider', px: 2, pt: 1 }}>
                        <Tabs value={activeTab} onChange={handleTabChange} variant="scrollable" scrollButtons="auto" sx={{ '& .MuiTab-root': { textTransform: 'none', minWidth: 'auto', px: 2 } }}>
                            <Tab icon={<InfoOutlined fontSize="small" />} iconPosition="start" label="Info" />
                            <Tab icon={<History fontSize="small" />} iconPosition="start" label="Versions" />
                            <Tab icon={<AnalyticsOutlined fontSize="small" />} iconPosition="start" label="Statistics" />
                            <Tab icon={<PolicyOutlined fontSize="small" />} iconPosition="start" label="Audit" />
                            <Tab icon={<AccountTreeOutlined fontSize="small" />} iconPosition="start" label="Workflows" />
                            <Tab icon={<AutoAwesome fontSize="small" />} iconPosition="start" label="AI Engine" />
                        </Tabs>
                    </Box>

                    <Box sx={{ flexGrow: 1, overflow: 'hidden', px: 3 }}>

                        {/* TAB 0: INFO */}
                        <TabPanel value={activeTab} index={0}>
                            <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 2 }}>
                                <Typography variant="subtitle1" fontWeight="700">General Metadata</Typography>
                                <Chip label={asset.status || 'Pending'} color={asset.status === 'approved' ? 'success' : 'warning'} size="small" />
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
                                        <Typography variant="body2" fontWeight="700" color="textPrimary">{totalTagsCount} tags</Typography>
                                        <Typography variant="caption" color="textSecondary">AI-recognized & Manual</Typography>
                                    </Box>
                                </Box>
                                <IconButton size="small" sx={{ bgcolor: '#4f46e5', color: '#fff', '&:hover': { bgcolor: '#4338ca' } }}>
                                    <ChevronRight fontSize="small" />
                                </IconButton>
                            </Paper>

                            <List dense disablePadding sx={{ mb: 4 }}>
                                <ListItem disableGutters><ListItemText primary="File Name" secondary={displayName} /></ListItem>
                                <ListItem disableGutters><ListItemText primary="Date Added" secondary={new Date(asset.created_at).toLocaleString()} /></ListItem>
                                <ListItem disableGutters><ListItemText primary="Resolution" secondary={asset.properties?.resolution || "Unknown"} /></ListItem>
                                <ListItem disableGutters><ListItemText primary="File Size" secondary={fileSize} /></ListItem>
                            </List>

                            {/* Extract the palette from properties, defaulting to empty array */}
                            {asset.properties?.color_palette && asset.properties.color_palette.length > 0 && (
                                <Box sx={{ mb: 4 }}>
                                    <Typography variant="caption" sx={{ color: '#475569', mb: 1, display: 'block', fontWeight: 600 }}>
                                        Dominant Palette
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

                            <Typography variant="subtitle2" fontWeight="700" sx={{ mb: 2 }}>EXIF / IPTC Data</Typography>
                            <Paper elevation={0} sx={{ p: 2, bgcolor: '#f8fafc', border: '1px solid #e2e8f0', borderRadius: 2 }}>
                                <Typography variant="caption" color="textSecondary" sx={{ fontFamily: 'monospace' }}>
                                    {asset.properties?.exif_data ? JSON.stringify(asset.properties.exif_data, null, 2) : "No EXIF data extracted yet."}
                                </Typography>
                            </Paper>
                        </TabPanel>

                        {/*  TAB 2 */}
                        <TabPanel value={activeTab} index={1}>
                            <AssetVersionsTab asset={asset}
                                              onAssetUpdated={onAssetUpdated} />
                        </TabPanel>
                        {/*  TAB 3 */}
                        <TabPanel value={activeTab} index={2}><AssetStatisticsTab asset={asset} /></TabPanel>
                        {/*  TAB 4 */}
                        <TabPanel value={activeTab} index={3}><AssetAuditTab asset={asset} /></TabPanel>
                        {/* TAB 5: WORKFLOWS */}
                        <TabPanel value={activeTab} index={4}>
                            <WorkflowPanel assetId={asset.id} onWorkflowUpdate={() => { if (onAssetUpdated) onAssetUpdated(asset); }} />
                        </TabPanel>
                        {/* TAB 5: AI */}
                        <TabPanel value={activeTab} index={5}>
                            <Typography variant="subtitle1" fontWeight="700" sx={{ mb: 2 }}>Semantic & Vision Analysis</Typography>
                        </TabPanel>

                    </Box>
                </Grid>
            </Grid>

            {/* OVERLAYS */}
            {isImage && (
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
                assetIds={[asset.id]} // Wrap single ID in array if your PinToCollectionDialog expects bulk IDs
            />
        </Dialog>
    );
}