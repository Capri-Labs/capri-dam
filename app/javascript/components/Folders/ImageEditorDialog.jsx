import React, {useEffect, useState, useRef} from 'react';
import {
    Dialog, AppBar, Toolbar, IconButton, Typography, Box, Grid,
    Button, Stack, Radio, RadioGroup, FormControlLabel, FormControl,
    Divider, Slider, Tabs, Tab, Tooltip, CircularProgress, Paper, Chip,
    Accordion, AccordionSummary, AccordionDetails, Select, MenuItem, Autocomplete, TextField
} from '@mui/material';
import {
    Close, RotateRight, CheckCircle, Tune, AutoFixHigh,
    History, AutoAwesome, Flip, ExpandMore, WbSunnyOutlined,
    ContrastOutlined, ColorLensOutlined, BlurOn, Crop,
    FilterBAndW, ViewInAr, HighQuality, Wallpaper, FolderOpen, Architecture
} from '@mui/icons-material';

import { useNotify } from '../../context/NotificationContext';
import { useTranslation } from 'react-i18next';

function TabPanel(props) {
    const { children, value, index, ...other } = props;
    return (
        <div role="tabpanel" hidden={value !== index} style={{ height: '100%', overflowY: 'auto' }} {...other}>
            {value === index && <Box sx={{ pt: 2, pb: 4 }}>{children}</Box>}
        </div>
    );
}

const tr = (t, key, fallback, options = {}) => {
    const translated = t(key, options);
    if (translated === key) return fallback;
    if (options.count != null && translated === `${key}:${options.count}`) return fallback;
    return translated;
};

const LIGHT_ADJUSTMENTS = [
    { key: 'brightness', labelKey: 'imageEditor.brightness', fallback: 'Brightness' },
    { key: 'contrast', labelKey: 'imageEditor.contrast', fallback: 'Contrast' },
    { key: 'hdr', labelKey: 'imageEditor.ultraHdr', fallback: 'Ultra HDR' },
    { key: 'whitePoint', labelKey: 'imageEditor.whitePoint', fallback: 'White Point' },
    { key: 'highlights', labelKey: 'imageEditor.highlights', fallback: 'Highlights' },
    { key: 'shadows', labelKey: 'imageEditor.shadows', fallback: 'Shadows' },
    { key: 'blackPoint', labelKey: 'imageEditor.blackPoint', fallback: 'Black Point' },
];

const COLOR_ADJUSTMENTS = [
    { key: 'saturation', labelKey: 'imageEditor.saturation', fallback: 'Saturation' },
    { key: 'warmth', labelKey: 'imageEditor.warmth', fallback: 'Warmth' },
    { key: 'tint', labelKey: 'imageEditor.tint', fallback: 'Tint' },
    { key: 'skinTone', labelKey: 'imageEditor.skinTone', fallback: 'Skin Tone' },
    { key: 'blueTone', labelKey: 'imageEditor.blueTone', fallback: 'Blue Tone' },
];

const FILTER_OPTIONS = [
    { id: 'None', labelKey: 'imageEditor.filters.none', fallback: 'None' },
    { id: 'Vivid', labelKey: 'imageEditor.filters.vivid', fallback: 'Vivid' },
    { id: 'West', labelKey: 'imageEditor.filters.west', fallback: 'West' },
    { id: 'Palma', labelKey: 'imageEditor.filters.palma', fallback: 'Palma' },
    { id: 'Metro', labelKey: 'imageEditor.filters.metro', fallback: 'Metro' },
    { id: 'Eiffel', labelKey: 'imageEditor.filters.eiffel', fallback: 'Eiffel' },
    { id: 'Blush', labelKey: 'imageEditor.filters.blush', fallback: 'Blush' },
    { id: 'Modena', labelKey: 'imageEditor.filters.modena', fallback: 'Modena' },
    { id: 'Vogue', labelKey: 'imageEditor.filters.vogue', fallback: 'Vogue' },
];

export default function ImageEditorDialog({ asset, open, onClose, onSave }) {
    const notify = useNotify();
    const { t } = useTranslation();

    const [saveMode, setSaveMode] = useState('version');
    const [isSaving, setIsSaving] = useState(false);
    const [activeTab, setActiveTab] = useState(0);

    const [targetFolder, setTargetFolder] = useState(null);
    const [folderOptions, setFolderOptions] = useState([]);
    const [isFetchingFolders, setIsFetchingFolders] = useState(false);

    const [aiProcessing, setAiProcessing] = useState(false);
    const [aiMessage, setAiMessage] = useState("");

    const [adjustments, setAdjustments] = useState({});
    const [cropAspect, setCropAspect] = useState('free');
    const [activeFilter, setActiveFilter] = useState('None');
    const [rotation, setRotation] = useState(0);
    const [flipH, setFlipH] = useState(false);

    const [focalPoint, setFocalPoint] = useState({ x: 50, y: 50 });
    const [isDraggingFocal, setIsDraggingFocal] = useState(false);
    const [isTargetingFocal, setIsTargetingFocal] = useState(false);
    const imageContainerRef = useRef(null);
    const [customCli, setCustomCli] = useState('');

    // This runs every time the dialog opens or the selected asset changes
    useEffect(() => {
        if (open && asset) {
            // Extract the editor state from JSONB properties, or fallback to empty
            const savedState = asset.properties?.editor_state || {};

            setAdjustments(savedState.adjustments || {
                brightness: 0, contrast: 0, hdr: 0, whitePoint: 0,
                highlights: 0, shadows: 0, blackPoint: 0,
                saturation: 0, warmth: 0, tint: 0, skinTone: 0, blueTone: 0,
                vignette: 0
            });

            setCropAspect(savedState.crop_aspect || 'free');
            setActiveFilter(savedState.filter || 'None');
            setRotation(savedState.geometry?.rotate || 0);
            setFlipH(savedState.geometry?.flip_horizontal || false);

            // Reset to default active tab when opening
            setActiveTab(0);
        }
    }, [open, asset]);

    useEffect(() => {
        if (saveMode === 'new' && folderOptions.length === 0) {
            fetchFolders();
        }
    }, [saveMode]);

    const fetchFolders = async () => {
        setIsFetchingFolders(true);

        try {
            await fetch('/api/v1/folders')
                .then(res => res.json())
                .then(data => {
                    const fetchedFolders = data.folders || data || [];
                    setFolderOptions(fetchedFolders);
                })
                .catch(() => notify(tr(t, 'imageEditor.errors.failedToLoadFoldersNoPeriod', 'Failed to load folders'), 'error'));
        } catch (error) {
            notify(tr(t, 'imageEditor.errors.failedToLoadFolders', 'Failed to load folders.'), 'error');
        } finally {
            setIsFetchingFolders(false);
        }
    };

    const handleTabChange = (event, newValue) => setActiveTab(newValue);

    const handleRotate = () => {
        setRotation((prev) => (prev + 90) % 360);
    };

    const handleFlip = () => {
        setFlipH((prev) => !prev);
    };

    const handleFocalDragStart = (e) => {
        e.preventDefault(); // Prevents the browser's default image drag behavior
        setIsDraggingFocal(true);
    };

    const handleFocalDrag = (e) => {
        if (!isDraggingFocal || !imageContainerRef.current) return;

        const rect = imageContainerRef.current.getBoundingClientRect();
        let x = ((e.clientX - rect.left) / rect.width) * 100;
        let y = ((e.clientY - rect.top) / rect.height) * 100;

        // Clamp the values so the pin can't be dragged outside the image
        x = Math.max(0, Math.min(100, x));
        y = Math.max(0, Math.min(100, y));

        setFocalPoint({ x, y });
    };

    const handleFocalDragEnd = () => {
        setIsDraggingFocal(false);
    };

    const handleAdjustmentChange = (prop) => (event, newValue) => {
        setAdjustments(prev => ({ ...prev, [prop]: newValue }));
    };

    const resetAdjustments = () => {
        setAdjustments({
            brightness: 0, contrast: 0, hdr: 0, whitePoint: 0,
            highlights: 0, shadows: 0, blackPoint: 0,
            saturation: 0, warmth: 0, tint: 0, skinTone: 0, blueTone: 0, vignette: 0
        });
        setCropAspect('free');
        setActiveFilter('None');
        setRotation(0);
        setFlipH(false);
    };

    // Apply quick action presets to actual adjustments
    const applyQuickActionPreset = (actionType) => {
        const presets = {
            'auto': { brightness: 10, contrast: 15, saturation: 10 },
            'dynamic': { brightness: 5, contrast: 25, hdr: 30, shadows: 10 },
            'color_pop': { saturation: 40 },
            'warm_contrast': { warmth: 30, contrast: 20 },
            'cinematic': { warmth: 20, contrast: 15, saturation: -10, tint: 5 },
        };

        const preset = presets[actionType];
        if (preset) {
            setAdjustments(prev => {
                const updated = { ...prev, ...preset };
                notify(tr(t, 'imageEditor.notifications.applied', `Applied: ${actionType}`, { action: actionType }), 'success');
                return updated;
            });
        }
    };

    const handleQuickAction = (actionType) => {
        const actions = {
            auto: { msg: tr(t, 'imageEditor.processing.autoEnhance', 'Applying Auto-Enhance...'), time: 800, apply: true },
            dynamic: { msg: tr(t, 'imageEditor.processing.dynamicHdr', 'Balancing HDR & Dynamics...'), time: 1000, apply: true },
            color_pop: { msg: tr(t, 'imageEditor.processing.colorPop', 'Isolating subject color...'), time: 1000, apply: true },
            warm_contrast: { msg: tr(t, 'imageEditor.processing.warmContrast', 'Applying studio warmth...'), time: 600, apply: true },
            cinematic: { msg: tr(t, 'imageEditor.processing.cinematicTone', 'Grading cinematic tones...'), time: 900, apply: true },
            magic_eraser: { msg: tr(t, 'imageEditor.processing.magicEraser', 'Analyzing & removing objects...'), time: 2500, apply: false },
            unblur: { msg: tr(t, 'imageEditor.processing.unblur', 'Restoring sharp details...'), time: 2000, apply: false },
            portrait_light: { msg: tr(t, 'imageEditor.processing.portraitLight', 'Adjusting studio lighting...'), time: 1500, apply: false },
            generative_expand: { msg: tr(t, 'imageEditor.processing.generativeExpand', 'Outpainting borders via local diffusion...'), time: 3500, apply: false },
            super_res: { msg: tr(t, 'imageEditor.processing.superResolution', 'Upscaling via local ESRGAN...'), time: 3000, apply: false },
            bg_swap: { msg: tr(t, 'imageEditor.processing.backgroundSwap', 'Extracting semantic masks...'), time: 2800, apply: false },
            depth_map: { msg: tr(t, 'imageEditor.processing.depthMap', 'Calculating 3D depth geometry...'), time: 2200, apply: false },
        };
        const action = actions[actionType];
        
        setAiProcessing(true);
        setAiMessage(action.msg);
        
        if (action.apply) {
            applyQuickActionPreset(actionType);
        }

        setTimeout(() => {
            setAiProcessing(false);
            setAiMessage("");
        }, action.time);
    };

    const handleSave = async () => {
        setIsSaving(true);
        const payload = {
            save_mode: saveMode,
            target_folder_id: targetFolder?.id,
            adjustments: adjustments,
            crop_aspect: cropAspect,
            filter: activeFilter,
            geometry: {
                rotate: rotation,
                flip_horizontal: flipH,
                focal_point: focalPoint,
            },
            custom_cli: customCli,
        };

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content || "";
            const response = await fetch(`/api/v1/assets/${asset.id}/process_image`, {
                method: "POST",
                headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
                body: JSON.stringify(payload),
            });

            if (response.ok) {
                const updatedAsset = await response.json();

                // Dynamic Notifications based on mode
                const targetFolderName = targetFolder?.name || tr(t, 'imageEditor.currentFolder', 'current folder');

                if (saveMode === "new") {
                    notify(tr(t, 'imageEditor.notifications.savedAsCopy', `Saved as copy to ${targetFolderName}.`, { folder: targetFolderName }), 'success');
                } else if (saveMode === "overwrite") {
                    notify(tr(t, 'imageEditor.notifications.overwritten', 'Current version forcefully overwritten.'), 'warning');
                } else {
                    if (targetFolder) {
                        notify(tr(t, 'imageEditor.notifications.versionSavedAndMoved', `New version saved and moved to ${targetFolderName}.`, { folder: targetFolderName }), 'success');
                    } else {
                        notify(tr(t, 'imageEditor.notifications.savedAsNewVersion', 'New immutable version saved successfully.'), 'success');
                    }
                }

                onSave(updatedAsset);
                onClose();
            } else {
                const errorData = await response.json();
                notify(errorData.error || tr(t, 'imageEditor.errors.failedToApplyEdits', 'Failed to apply edits.'), 'error');
            }
        } catch (error) {
            console.error("Image processing error:", error);
            notify(tr(t, 'imageEditor.errors.networkErrorRetry', 'Network error occurred. Please try again.'), 'error');
        } finally {
            setIsSaving(false);
        }
    };

    if (!asset) return null;

    // Define CSS-based LUT filter approximations for preview
    const filterStyles = {
        'None': '',
        'Vivid': 'saturate(1.3) contrast(1.2)',
        'West': 'sepia(0.3) saturate(0.8) brightness(1.05)',
        'Palma': 'sepia(0.2) hue-rotate(-5deg) saturate(1.1)',
        'Metro': 'saturate(1.15) contrast(1.1)',
        'Eiffel': 'saturate(0.8) hue-rotate(180deg) brightness(0.95)',
        'Blush': 'sepia(0.15) saturate(1.1) brightness(1.05)',
        'Modena': 'sepia(0.3) hue-rotate(-10deg) saturate(0.7)',
        'Vogue': 'contrast(1.3) grayscale(0.3) brightness(0.95)',
    };

    // Calculate aspect ratio box shadow if not free form
    const aspectRatioAdjustments = {
        'free': {},
        '1:1': { aspectRatio: '1/1' },
        '16:9': { aspectRatio: '16/9' },
        '4:3': { aspectRatio: '4/3' },
        '3:2': { aspectRatio: '3/2' },
        '21:9': { aspectRatio: '21/9' },
    };

    const liveFilterStyle = `
        brightness(${100 + adjustments.brightness}%)
        contrast(${100 + adjustments.contrast}%)
        saturate(${100 + adjustments.saturation}%)
        sepia(${adjustments.warmth > 0 ? adjustments.warmth / 2 : 0}%)
        hue-rotate(${adjustments.tint}deg)
        ${filterStyles[activeFilter] || ''}
    `;

    return (
        <Dialog fullScreen open={open} onClose={onClose}>
            <AppBar sx={{ position: 'relative', bgcolor: '#ffffff', color: '#1e293b', boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
                <Toolbar>
                    <IconButton edge="start" color="inherit" onClick={onClose} aria-label={tr(t, 'common.close', 'Close')}><Close /></IconButton>
                    <Typography sx={{ ml: 2, flex: 1, fontWeight: 700 }} variant="h6">
                        {tr(t, 'imageEditor.title', 'Studio Editor')}
                    </Typography>
                    <Button onClick={onClose} disabled={isSaving} color="inherit" sx={{ mr: 2 }}>{tr(t, 'common.cancel', 'Cancel')}</Button>
                    <Button onClick={handleSave} variant="contained" color="primary" startIcon={<CheckCircle />} disabled={isSaving} sx={{ bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' } }}>
                        {isSaving ? tr(t, 'imageEditor.rendering', 'Rendering...') : tr(t, 'imageEditor.exportAndSave', 'Export & Save')}
                    </Button>
                </Toolbar>
            </AppBar>

            <Grid container sx={{ height: 'calc(100vh - 64px)'}}>
                {/* LEFT PANE: Dark Mode Canvas (75%) */}
                <Grid size={{ xs: 12, md: 9 }} sx={{
 bgcolor: '#0f172a', position: 'relative', width: '65%',
 display: 'flex', alignItems: 'center', justifyContent: 'center', p: 4,
 backgroundImage: 'url("data:image/svg+xml,%3Csvg width=\'20\' height=\'20\' xmlns=\'http://www.w3.org/2000/svg\'%3E%3Cpath d=\'M0 0h10v10H0zm10 10h10v10H10z\' fill=\'%231e293b\' fill-opacity=\'0.4\' fill-rule=\'evenodd\'/%3E%3C/svg%3E")'
 }}>
                    <Box
                        ref={imageContainerRef}
                        onMouseMove={handleFocalDrag}
                        onMouseUp={handleFocalDragEnd}
                        onMouseLeave={handleFocalDragEnd}
                        sx={{
                            position: "relative",
                            display: "inline-block",
                            maxWidth: "100%",
                            maxHeight: "100%",
                            ...aspectRatioAdjustments[cropAspect],
                        }}
                    >
                        <Box
                            component="img"
                            src={`${asset.url}${asset.url?.includes('?') ? '&' : '?'}v=${asset.version || Date.now()}`}
                            alt={tr(t, 'imageEditor.editorCanvasAlt', 'Editor Canvas')}
                            draggable={false} // Disable native drag
                            sx={{
                                maxWidth: '100%', maxHeight: '80vh', objectFit: 'contain',
                                boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.5)',
                                filter: liveFilterStyle,
                                transform: `scaleX(${flipH ? -1 : 1}) rotate(${rotation}deg)`,
                                transition: 'filter 0.1s ease-out, transform 0.3s cubic-bezier(0.4, 0, 0.2, 1)'
                            }}
                        />

                        {/*  The Visual Focal Point Reticle */}
                        <Box
                            onMouseDown={handleFocalDragStart}
                            sx={{
                                position: 'absolute',
                                top: `${focalPoint.y}%`,
                                left: `${focalPoint.x}%`,
                                transform: 'translate(-50%, -50%)',
                                width: 32, height: 32, // Made slightly larger for easier grabbing
                                border: '3px solid #fff',
                                borderRadius: '50%',
                                boxShadow: '0 0 10px rgba(0,0,0,0.5)',
                                cursor: isDraggingFocal ? 'grabbing' : 'grab',
                                display: 'flex', alignItems: 'center', justifyContent: 'center',
                                '&::after': { content: '""', width: 6, height: 6, bgcolor: '#ef4444', borderRadius: '50%' }
                            }}
                        />


                        {/*  Targeting Overlay Instructions */}
                        {isTargetingFocal && (
                            <Box sx={{ position: 'absolute', inset: 0, bgcolor: 'rgba(0,0,0,0.3)', display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none', borderRadius: 1 }}>
                                <Typography variant="h6" color="#fff" fontWeight="700" sx={{ textShadow: '0 2px 4px rgba(0,0,0,0.5)' }}>
                                    {tr(t, 'imageEditor.clickToSetFocalPoint', 'Click anywhere to set the focal point')}
                                </Typography>
                            </Box>
                        )}

                        <Box sx={{
                            position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, pointerEvents: 'none',
                            boxShadow: `inset 0 0 ${adjustments.vignette * 2}px rgba(0,0,0,${adjustments.vignette / 100})`
                        }} />

                        {aiProcessing && (
                            <Box sx={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, bgcolor: 'rgba(15, 23, 42, 0.7)', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', zIndex: 10, borderRadius: 1 }}>
                                <CircularProgress sx={{ color: '#8b5cf6', mb: 2 }} />
                                <Typography variant="subtitle2" sx={{ color: '#fff', fontWeight: 600 }}>{aiMessage}</Typography>
                            </Box>
                        )}
                    </Box>

                    <Paper elevation={3} sx={{ position: 'absolute', bottom: 32, display: 'flex', gap: 1, p: 0.5, borderRadius: 2, bgcolor: 'rgba(255,255,255,0.95)' }}>
                        <Tooltip title={tr(t, 'imageEditor.resetAllTooltip', 'Reset All')}><IconButton size="small" onClick={resetAdjustments}><History fontSize="small" /></IconButton></Tooltip>
                        <Divider orientation="vertical" flexItem />
                        <Tooltip title={tr(t, 'imageEditor.rotateTooltip', 'Rotate 90°')}><IconButton size="small" onClick={handleRotate}><RotateRight fontSize="small" /></IconButton></Tooltip>
                        <Tooltip title={tr(t, 'imageEditor.flipTooltip', 'Flip Horizontal')}><IconButton size="small" onClick={handleFlip}><Flip fontSize="small" /></IconButton></Tooltip>
                    </Paper>
                </Grid>

                {/* RIGHT PANE: Tool Sidebar (25%) */}
                <Grid size={{ xs: 12, md: 3 }} sx={{ bgcolor: '#ffffff', display: 'flex', flexDirection: 'column', borderLeft: '1px solid #e2e8f0', width: '35%' }}>
                    <Box sx={{ borderBottom: 1, borderColor: 'divider' }}>
                        <Tabs value={activeTab} onChange={handleTabChange} variant="fullWidth" sx={{ '& .MuiTab-root': { minWidth: 'auto', px: 2, textTransform: 'none', fontWeight: 600 } }}>
                            <Tab icon={<AutoAwesome fontSize="small" />} iconPosition="start" label={tr(t, 'imageEditor.tabs.suggestions', 'Suggestions')} />
                            <Tab icon={<Tune fontSize="small" />} iconPosition="start" label={tr(t, 'imageEditor.tabs.adjust', 'Adjust')} />
                            <Tab icon={<AutoFixHigh fontSize="small" />} iconPosition="start" label={tr(t, 'imageEditor.tabs.aiStudio', 'AI Studio')} sx={{ color: '#8b5cf6', '&.Mui-selected': { color: '#7c3aed' } }} />
                        </Tabs>
                    </Box>

                    <Box sx={{ flexGrow: 1, overflowY: 'auto', px: 2 }}>

                        {/* TAB 0: SUGGESTIONS */}
                        <TabPanel value={activeTab} index={0}>
                            <Typography variant="subtitle2" color="textSecondary" sx={{ mb: 2 }}>{tr(t, 'imageEditor.quickActions.oneTabEnhancements', 'One-tap enhancements')}</Typography>
                            <Stack spacing={2}>
                                <Button variant="outlined" onClick={() => handleQuickAction('auto')} sx={{ justifyContent: 'flex-start', color: '#1e293b', borderColor: '#e2e8f0', p: 1.5 }}>
                                    {tr(t, 'imageEditor.quickActions.autoEnhance', 'Auto Enhance')}
                                </Button>
                                <Button variant="outlined" onClick={() => handleQuickAction('dynamic')} sx={{ justifyContent: 'flex-start', color: '#1e293b', borderColor: '#e2e8f0', p: 1.5 }}>
                                    {tr(t, 'imageEditor.quickActions.dynamicHdr', 'Dynamic HDR')}
                                </Button>
                                <Button variant="outlined" onClick={() => handleQuickAction('color_pop')} sx={{ justifyContent: 'flex-start', color: '#1e293b', borderColor: '#e2e8f0', p: 1.5 }}>
                                    {tr(t, 'imageEditor.quickActions.colorPop', 'Color Pop')}
                                </Button>
                                <Button variant="outlined" onClick={() => handleQuickAction('warm_contrast')} sx={{ justifyContent: 'flex-start', color: '#1e293b', borderColor: '#e2e8f0', p: 1.5 }}>
                                    {tr(t, 'imageEditor.quickActions.warmContrast', 'Warm Contrast')}
                                </Button>
                                <Button variant="outlined" onClick={() => handleQuickAction('cinematic')} sx={{ justifyContent: 'flex-start', color: '#1e293b', borderColor: '#e2e8f0', p: 1.5 }}>
                                    {tr(t, 'imageEditor.quickActions.cinematicTone', 'Cinematic Tone')}
                                </Button>
                            </Stack>
                        </TabPanel>

                        {/* TAB 1: ADJUST (Granular Sliders, Crop & Filters) */}
                        <TabPanel value={activeTab} index={1}>
                            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                                <Typography variant="subtitle2" fontWeight="700">{tr(t, 'imageEditor.manualAdjustments', 'Manual Adjustments')}</Typography>
                                <Button size="small" onClick={resetAdjustments} sx={{ textTransform: 'none' }}>{tr(t, 'imageEditor.reset', 'Reset')}</Button>
                            </Box>

                            <Accordion disableGutters defaultExpanded elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', mb: 1, borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><Crop fontSize="small" sx={{ mr: 1 }} /> {tr(t, 'imageEditor.cropAndGeometry', 'Crop & Geometry')}</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 2, px: 2 }}>
                                    <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 1 }}>{tr(t, 'imageEditor.aspectRatio', 'Aspect Ratio')}</Typography>
                                    <Select fullWidth size="small" value={cropAspect} onChange={(e) => setCropAspect(e.target.value)} sx={{ mb: 3 }}>
                                        <MenuItem value="free">{tr(t, 'imageEditor.freeform', 'Freeform')}</MenuItem>
                                        <MenuItem value="1:1">{tr(t, 'imageEditor.square', '1:1 Square')}</MenuItem>
                                        <MenuItem value="16:9">{tr(t, 'imageEditor.widescreen', '16:9 Widescreen')}</MenuItem>
                                        <MenuItem value="4:3">{tr(t, 'imageEditor.standard', '4:3 Standard')}</MenuItem>
                                    </Select>

                                    <Divider sx={{ my: 2 }} />

                                    {/*   Manual Focal Point Sliders */}
                                    <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
                                        <Typography variant="caption" color="textSecondary">{tr(t, 'imageEditor.focalPointX', 'Focal Point X')}</Typography>
                                        <Typography variant="caption" fontWeight="700">{Math.round(focalPoint.x)}%</Typography>
                                    </Box>
                                    <Slider
                                        size="small" min={0} max={100} value={focalPoint.x}
                                        onChange={(e, val) => setFocalPoint(prev => ({...prev, x: val}))}
                                    />

                                    <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5, mt: 1 }}>
                                        <Typography variant="caption" color="textSecondary">{tr(t, 'imageEditor.focalPointY', 'Focal Point Y')}</Typography>
                                        <Typography variant="caption" fontWeight="700">{Math.round(focalPoint.y)}%</Typography>
                                    </Box>
                                    <Slider
                                        size="small" min={0} max={100} value={focalPoint.y}
                                        onChange={(e, val) => setFocalPoint(prev => ({...prev, y: val}))}
                                    />
                                    <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1, lineHeight: 1.2 }}>
                                        {tr(t, 'imageEditor.focalPointHelp', 'Drag the pin on the image or use sliders. This ensures the subject remains visible when cropped for mobile devices.')}
                                    </Typography>
                                </AccordionDetails>
                            </Accordion>

                            <Divider sx={{ my: 3 }} />
                            <Accordion disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><Architecture fontSize="small" sx={{ mr: 1 }} /> {tr(t, 'imageEditor.advancedCli', 'Advanced CLI (ImageMagick)')}</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 2, px: 2 }}>
                                    <Typography variant="caption" color="textSecondary" display="block" sx={{ mb: 1 }}>
                                        {tr(t, 'imageEditor.advancedCliHelp', 'Inject raw ImageMagick operators. (e.g., -monochrome -charcoal 2)')}
                                    </Typography>
                                    <TextField
                                        fullWidth size="small" variant="outlined"
                                        placeholder="-blur 0x8"
                                        value={customCli}
                                        onChange={(e) => setCustomCli(e.target.value)}
                                        sx={{ fontFamily: 'monospace' }}
                                    />
                                </AccordionDetails>
                            </Accordion>

                            <Divider sx={{ my: 3 }} />

                            <Accordion disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', mb: 1, borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><WbSunnyOutlined fontSize="small" sx={{ mr: 1 }} /> {tr(t, 'imageEditor.light', 'Light')}</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 1, px: 2 }}>
                                    {LIGHT_ADJUSTMENTS.map(item => (
                                        <Box key={item.key} sx={{ mb: 1 }}>
                                            <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                                                <Typography variant="caption" color="textSecondary">{tr(t, item.labelKey, item.fallback)}</Typography>
                                                <Typography variant="caption" color="textSecondary">{adjustments[item.key]}</Typography>
                                            </Box>
                                            <Slider value={adjustments[item.key]} min={-100} max={100} onChange={handleAdjustmentChange(item.key)} size="small" sx={{ color: '#64748b', p: 0 }} />
                                        </Box>
                                    ))}
                                </AccordionDetails>
                            </Accordion>

                            <Accordion disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', mb: 1, borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><ColorLensOutlined fontSize="small" sx={{ mr: 1 }} /> {tr(t, 'imageEditor.color', 'Color')}</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 1, px: 2 }}>
                                    {COLOR_ADJUSTMENTS.map(item => (
                                        <Box key={item.key} sx={{ mb: 1 }}>
                                            <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                                                <Typography variant="caption" color="textSecondary">{tr(t, item.labelKey, item.fallback)}</Typography>
                                                <Typography variant="caption" color="textSecondary">{adjustments[item.key]}</Typography>
                                            </Box>
                                            <Slider value={adjustments[item.key]} min={-100} max={100} onChange={handleAdjustmentChange(item.key)} size="small" sx={{ color: '#64748b', p: 0 }} />
                                        </Box>
                                    ))}
                                </AccordionDetails>
                            </Accordion>

                            <Accordion disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', mb: 1, borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><BlurOn fontSize="small" sx={{ mr: 1 }} /> {tr(t, 'imageEditor.effects', 'Effects')}</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 1, px: 2 }}>
                                    <Box sx={{ mb: 1 }}>
                                        <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                                            <Typography variant="caption" color="textSecondary">{tr(t, 'imageEditor.vignette', 'Vignette')}</Typography>
                                            <Typography variant="caption" color="textSecondary">{adjustments.vignette}</Typography>
                                        </Box>
                                        <Slider value={adjustments.vignette} min={0} max={100} onChange={handleAdjustmentChange('vignette')} size="small" sx={{ color: '#64748b', p: 0 }} />
                                    </Box>
                                </AccordionDetails>
                            </Accordion>

                            <Accordion disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><FilterBAndW fontSize="small" sx={{ mr: 1 }} /> {tr(t, 'imageEditor.lutFilters', 'LUT Filters')}</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 2, px: 2 }}>
                                    <Grid container spacing={1}>
                                        {FILTER_OPTIONS.map(filter => (
                                            <Grid size={6} key={filter.id}>
                                                <Paper
                                                    onClick={() => setActiveFilter(filter.id)}
                                                    elevation={0}
                                                    sx={{ height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid', borderColor: activeFilter === filter.id ? '#4f46e5' : '#e2e8f0', bgcolor: activeFilter === filter.id ? '#eef2ff' : 'transparent', cursor: 'pointer' }}
                                                >
                                                    <Typography variant="caption" fontWeight="600" color={activeFilter === filter.id ? '#4f46e5' : 'textPrimary'}>{tr(t, filter.labelKey, filter.fallback)}</Typography>
                                                </Paper>
                                            </Grid>
                                        ))}
                                    </Grid>
                                </AccordionDetails>
                            </Accordion>
                        </TabPanel>

                        {/* TAB 2: AI STUDIO */}
                        <TabPanel value={activeTab} index={2}>
                            <Box sx={{ mb: 2, p: 2, bgcolor: '#f5f3ff', border: '1px solid #ddd6fe', borderRadius: 2 }}>
                                <Typography variant="body2" color="#6d28d9" fontWeight="700" sx={{ display: 'flex', alignItems: 'center', mb: 1 }}>
                                    <AutoAwesome fontSize="small" sx={{ mr: 1 }} /> {tr(t, 'imageEditor.aiStudioTitle', 'Agentic Tools')}
                                </Typography>
                                <Typography variant="caption" color="#5b21b6">
                                    {tr(t, 'imageEditor.aiStudioDesc', 'Generative and analytical models optimized for local HuggingFace inference nodes.')}
                                </Typography>
                            </Box>

                            <Stack spacing={2}>
                                <Button variant="outlined" onClick={() => handleQuickAction('magic_eraser')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700">{tr(t, 'imageEditor.magicEraser', 'Magic Eraser')}</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">{tr(t, 'imageEditor.magicEraserDesc', 'Remove unwanted objects & people')}</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('unblur')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700">{tr(t, 'imageEditor.unblur', 'Unblur & Sharpen')}</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">{tr(t, 'imageEditor.unblurDesc', 'Restore detail to blurry subjects')}</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('portrait_light')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700">{tr(t, 'imageEditor.portraitLight', 'Portrait Light')}</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">{tr(t, 'imageEditor.portraitLightDesc', 'Relight faces and subjects dynamically')}</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('generative_expand')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}><Crop fontSize="small" sx={{ mr: 0.5 }} /> {tr(t, 'imageEditor.generativeExpand', 'Generative Expand')}</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">{tr(t, 'imageEditor.generativeExpandDesc', 'Outpaint borders to alter aspect ratios')}</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('super_res')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}><HighQuality fontSize="small" sx={{ mr: 0.5 }} /> {tr(t, 'imageEditor.superResolution', 'Super Resolution')}</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">{tr(t, 'imageEditor.superResolutionDesc', 'Lossless 4x upscale via ESRGAN')}</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('bg_swap')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}><Wallpaper fontSize="small" sx={{ mr: 0.5 }} /> {tr(t, 'imageEditor.backgroundSwap', 'Background Swap')}</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">{tr(t, 'imageEditor.backgroundSwapDesc', 'Generate new contexts via prompt')}</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('depth_map')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}><ViewInAr fontSize="small" sx={{ mr: 0.5 }} /> {tr(t, 'imageEditor.depthMap', '3D Depth Map')}</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">{tr(t, 'imageEditor.depthMapDesc', 'Extract geometry for parallax motion')}</Typography>
                                    </Box>
                                </Button>
                            </Stack>
                        </TabPanel>

                    </Box>

                    {/* SAVE OPTIONS FOOTER */}
                    <Box sx={{ p: 2, bgcolor: '#f8fafc', borderTop: '1px solid #e2e8f0' }}>
                        <FormControl component="fieldset" fullWidth>
                            <RadioGroup value={saveMode} onChange={(e) => setSaveMode(e.target.value)}>
                                <FormControlLabel
                                    value="version" control={<Radio size="small" />}
                                    label={<Typography variant="body2" fontWeight="500">{tr(t, 'imageEditor.saveAsNewVersion', 'Save as New Version')}</Typography>}
                                    sx={{ m: 0, p: 0.5, mb: 0.5, border: '1px solid', borderColor: saveMode === 'version' ? '#4f46e5' : 'transparent', borderRadius: 1, bgcolor: saveMode === 'version' ? '#eef2ff' : 'transparent' }}
                                />
                                {/*   Overwrite Current Mode */}
                                <FormControlLabel
                                    value="overwrite" control={<Radio size="small" color="error" />}
                                    label={<Typography variant="body2" fontWeight="500" color="error">{tr(t, 'imageEditor.overwriteCurrent', 'Overwrite Current')}</Typography>}
                                    sx={{ m: 0, p: 0.5, mb: 0.5, border: '1px solid', borderColor: saveMode === 'overwrite' ? '#ef4444' : 'transparent', borderRadius: 1, bgcolor: saveMode === 'overwrite' ? '#fef2f2' : 'transparent' }}
                                />
                                <FormControlLabel
                                    value="new" control={<Radio size="small" />}
                                    label={<Typography variant="body2" fontWeight="500">{tr(t, 'imageEditor.saveAsCopy', 'Save as Copy')}</Typography>}
                                    sx={{ m: 0, p: 0.5, border: '1px solid', borderColor: saveMode === 'new' ? '#4f46e5' : 'transparent', borderRadius: 1, bgcolor: saveMode === 'new' ? '#eef2ff' : 'transparent' }}
                                />
                            </RadioGroup>
                        </FormControl>

                        {/*  Target Folder Selector (Appears for both Copy and New Version) */}
                        {(saveMode === 'new' || saveMode === 'version') && (
                            <Box sx={{ mt: 2 }}>
                                <Autocomplete
                                    size="small"
                                    options={folderOptions}
                                    getOptionLabel={(option) => option.name || ""}
                                    isOptionEqualToValue={(option, value) => option.id === value.id}
                                    loading={isFetchingFolders}
                                    value={targetFolder}
                                    onChange={(event, newValue) => setTargetFolder(newValue)}
                                    slotProps={{
                                        popper: {
                                            modifiers: [{ name: "flip", enabled: false }],
                                        },
                                    }}
                                    renderInput={(params) => (
                                        <TextField
                                            {...params}
                                            placeholder={tr(t, 'imageEditor.targetFolder', 'Target Folder (Defaults to current)')}
                                            slotProps={{
                                                input: {
                                                    ...params.InputProps,
                                                    startAdornment: (
                                                        <React.Fragment>
                                                            <FolderOpen fontSize="small" sx={{ color: "#94a3b8", ml: 1, mr: 0.5 }} />
                                                            {params.InputProps?.startAdornment}
                                                        </React.Fragment>
                                                    ),
                                                    endAdornment: (
                                                        <React.Fragment>
                                                            {isFetchingFolders ? <CircularProgress color="inherit" size={20} /> : null}
                                                            {params.InputProps?.endAdornment}
                                                        </React.Fragment>
                                                    ),
                                                },
                                            }}
                                            sx={{ bgcolor: "#fff", borderRadius: 1 }}
                                        />
                                    )}
                                />
                            </Box>
                        )}
                    </Box>
                </Grid>
            </Grid>
        </Dialog>
    );
}