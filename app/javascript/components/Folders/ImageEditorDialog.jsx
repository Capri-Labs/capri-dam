import React, {useEffect, useState} from 'react';
import {
    Dialog, AppBar, Toolbar, IconButton, Typography, Box, Grid,
    Button, Stack, Radio, RadioGroup, FormControlLabel, FormControl,
    Divider, Slider, Tabs, Tab, Tooltip, CircularProgress, Paper, Chip,
    Accordion, AccordionSummary, AccordionDetails
} from '@mui/material';
import {
    Close, RotateRight, CheckCircle, Tune, AutoFixHigh,
    History, AutoAwesome, Flip, ExpandMore, WbSunnyOutlined,
    ContrastOutlined, ColorLensOutlined, BlurOn, Crop,
    FilterBAndW, ViewInAr, HighQuality, Wallpaper, Architecture
} from '@mui/icons-material';

import { useNotify } from '../../context/NotificationContext';

function TabPanel(props) {
    const { children, value, index, ...other } = props;
    return (
        <div role="tabpanel" hidden={value !== index} style={{ height: '100%', overflowY: 'auto' }} {...other}>
            {value === index && <Box sx={{ pt: 2, pb: 4 }}>{children}</Box>}
        </div>
    );
}

export default function ImageEditorDialog({ asset, open, onClose, onSave }) {
    const notify = useNotify();

    const [saveMode, setSaveMode] = useState('version');
    const [isSaving, setIsSaving] = useState(false);
    const [activeTab, setActiveTab] = useState(0);

    const [aiProcessing, setAiProcessing] = useState(false);
    const [aiMessage, setAiMessage] = useState("");

    const [adjustments, setAdjustments] = useState({});
    const [cropAspect, setCropAspect] = useState('free');
    const [activeFilter, setActiveFilter] = useState('None');
    const [rotation, setRotation] = useState(0);
    const [flipH, setFlipH] = useState(false);

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

    const handleTabChange = (event, newValue) => setActiveTab(newValue);

    const handleRotate = () => {
        setRotation((prev) => (prev + 90) % 360);
    };

    const handleFlip = () => {
        setFlipH((prev) => !prev);
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

    const simulateAiProcess = (processName, duration, effect) => {
        setAiProcessing(true);
        setAiMessage(processName);
        setTimeout(() => {
            if (effect) effect();
            setAiProcessing(false);
            setAiMessage("");
        }, duration);
    };

    const handleQuickAction = (actionType) => {
        const actions = {
            'auto': { msg: "Applying Auto-Enhance...", time: 1000 },
            'dynamic': { msg: "Balancing HDR & Dynamics...", time: 1500 },
            'color_pop': { msg: "Isolating subject color...", time: 1800 },
            'warm_contrast': { msg: "Applying studio warmth...", time: 800 },
            'cinematic': { msg: "Grading cinematic tones...", time: 1200 },
            'magic_eraser': { msg: "Analyzing & removing objects...", time: 2500 },
            'unblur': { msg: "Restoring sharp details...", time: 2000 },
            'portrait_light': { msg: "Adjusting studio lighting...", time: 1500 },
            'generative_expand': { msg: "Outpainting borders via local diffusion...", time: 3500 },
            'super_res': { msg: "Upscaling via local ESRGAN...", time: 3000 },
            'bg_swap': { msg: "Extracting semantic masks...", time: 2800 },
            'depth_map': { msg: "Calculating 3D depth geometry...", time: 2200 }
        };
        const action = actions[actionType];
        simulateAiProcess(action.msg, action.time, () => console.log(`${actionType} complete`));
    };

    const handleSave = async () => {
        setIsSaving(true);
        const payload = {
            save_mode: saveMode,
            adjustments, crop_aspect:
            cropAspect,
            filter: activeFilter,
            geometry: { rotate: rotation, flip_horizontal: flipH }
        };

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content || '';
            const response = await fetch(`/api/v1/assets/${asset.id}/process_image`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(payload)
            });

            if (response.ok) {
                const updatedAsset = await response.json();
                onSave(updatedAsset);
                notify("Image edits applied successfully.", "success");
            } else {
                notify("Failed to apply edits.", "error");
            }
        } catch (error) {
            notify("Network error occurred.", "error");
        } finally {
            setIsSaving(false);
        }
    };

    if (!asset) return null;

    const liveFilterStyle = `
        brightness(${100 + adjustments.brightness}%) 
        contrast(${100 + adjustments.contrast}%) 
        saturate(${100 + adjustments.saturation}%) 
        sepia(${adjustments.warmth > 0 ? adjustments.warmth / 2 : 0}%) 
        hue-rotate(${adjustments.tint}deg)
    `;

    return (
        <Dialog fullScreen open={open} onClose={onClose}>
            <AppBar sx={{ position: 'relative', bgcolor: '#ffffff', color: '#1e293b', boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
                <Toolbar>
                    <IconButton edge="start" color="inherit" onClick={onClose} aria-label="close"><Close /></IconButton>
                    <Typography sx={{ ml: 2, flex: 1, fontWeight: 700 }} variant="h6">
                        Studio Editor
                    </Typography>
                    <Button onClick={onClose} disabled={isSaving} color="inherit" sx={{ mr: 2 }}>Cancel</Button>
                    <Button onClick={handleSave} variant="contained" color="primary" startIcon={<CheckCircle />} disabled={isSaving} sx={{ bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' } }}>
                        {isSaving ? "Rendering..." : "Export & Save"}
                    </Button>
                </Toolbar>
            </AppBar>

            <Grid container sx={{ height: 'calc(100vh - 64px)'}}>
                {/* LEFT PANE: Dark Mode Canvas (75%) */}
                <Grid item xs={12} md={9} sx={{
                    bgcolor: '#0f172a', position: 'relative', width: '65%',
                    display: 'flex', alignItems: 'center', justifyContent: 'center', p: 4,
                    backgroundImage: 'url("data:image/svg+xml,%3Csvg width=\'20\' height=\'20\' xmlns=\'http://www.w3.org/2000/svg\'%3E%3Cpath d=\'M0 0h10v10H0zm10 10h10v10H10z\' fill=\'%231e293b\' fill-opacity=\'0.4\' fill-rule=\'evenodd\'/%3E%3C/svg%3E")'
                }}>
                    <Box sx={{ position: 'relative', maxWidth: '100%', maxHeight: '100%' }}>
                        <Box
                            component="img"
                            src={asset.url}
                            alt="Editor Canvas"
                            sx={{
                                maxWidth: '100%', maxHeight: '80vh', objectFit: 'contain',
                                boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.5)',
                                filter: liveFilterStyle,
                                transform: `scaleX(${flipH ? -1 : 1}) rotate(${rotation}deg)`,
                                transition: 'filter 0.1s ease-out, transform 0.3s cubic-bezier(0.4, 0, 0.2, 1)'
                            }}
                        />

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
                        <Tooltip title="Reset All"><IconButton size="small" onClick={resetAdjustments}><History fontSize="small" /></IconButton></Tooltip>
                        <Divider orientation="vertical" flexItem />
                        <Tooltip title="Rotate 90°"><IconButton size="small" onClick={handleRotate}><RotateRight fontSize="small" /></IconButton></Tooltip>
                        <Tooltip title="Flip Horizontal"><IconButton size="small" onClick={handleFlip}><Flip fontSize="small" /></IconButton></Tooltip>
                    </Paper>
                </Grid>

                {/* RIGHT PANE: Tool Sidebar (25%) */}
                <Grid item xs={12} md={3} sx={{ bgcolor: '#ffffff', display: 'flex', flexDirection: 'column', borderLeft: '1px solid #e2e8f0', width: '35%' }}>
                    <Box sx={{ borderBottom: 1, borderColor: 'divider' }}>
                        <Tabs value={activeTab} onChange={handleTabChange} variant="fullWidth" sx={{ '& .MuiTab-root': { minWidth: 'auto', px: 2, textTransform: 'none', fontWeight: 600 } }}>
                            <Tab icon={<AutoAwesome fontSize="small" />} iconPosition="start" label="Suggestions" />
                            <Tab icon={<Tune fontSize="small" />} iconPosition="start" label="Adjust" />
                            <Tab icon={<AutoFixHigh fontSize="small" />} iconPosition="start" label="AI Studio" sx={{ color: '#8b5cf6', '&.Mui-selected': { color: '#7c3aed' } }} />
                        </Tabs>
                    </Box>

                    <Box sx={{ flexGrow: 1, overflowY: 'auto', px: 2 }}>

                        {/* TAB 0: SUGGESTIONS */}
                        <TabPanel value={activeTab} index={0}>
                            <Typography variant="subtitle2" color="textSecondary" sx={{ mb: 2 }}>One-tap enhancements</Typography>
                            <Stack spacing={2}>
                                <Button variant="outlined" onClick={() => handleQuickAction('auto')} sx={{ justifyContent: 'flex-start', color: '#1e293b', borderColor: '#e2e8f0', p: 1.5 }}>
                                    Auto Enhance
                                </Button>
                                <Button variant="outlined" onClick={() => handleQuickAction('dynamic')} sx={{ justifyContent: 'flex-start', color: '#1e293b', borderColor: '#e2e8f0', p: 1.5 }}>
                                    Dynamic HDR
                                </Button>
                                <Button variant="outlined" onClick={() => handleQuickAction('color_pop')} sx={{ justifyContent: 'flex-start', color: '#1e293b', borderColor: '#e2e8f0', p: 1.5 }}>
                                    Color Pop
                                </Button>
                                <Button variant="outlined" onClick={() => handleQuickAction('warm_contrast')} sx={{ justifyContent: 'flex-start', color: '#1e293b', borderColor: '#e2e8f0', p: 1.5 }}>
                                    Warm Contrast
                                </Button>
                                <Button variant="outlined" onClick={() => handleQuickAction('cinematic')} sx={{ justifyContent: 'flex-start', color: '#1e293b', borderColor: '#e2e8f0', p: 1.5 }}>
                                    Cinematic Tone
                                </Button>
                            </Stack>
                        </TabPanel>

                        {/* TAB 1: ADJUST (Granular Sliders, Crop & Filters) */}
                        <TabPanel value={activeTab} index={1}>
                            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                                <Typography variant="subtitle2" fontWeight="700">Manual Adjustments</Typography>
                                <Button size="small" onClick={resetAdjustments} sx={{ textTransform: 'none' }}>Reset</Button>
                            </Box>

                            <Accordion disableGutters defaultExpanded elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', mb: 1, borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><Crop fontSize="small" sx={{ mr: 1 }} /> Crop & Geometry</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 2, px: 2 }}>
                                    <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap sx={{ mb: 2 }}>
                                        {['Free', 'Original', 'Square', '16:9', '4:3', '3:2'].map(ratio => (
                                            <Chip
                                                key={ratio} label={ratio}
                                                onClick={() => setCropAspect(ratio)}
                                                variant={cropAspect === ratio ? 'filled' : 'outlined'}
                                                color={cropAspect === ratio ? 'primary' : 'default'}
                                                sx={{ borderRadius: 1, mb: 1 }} clickable size="small"
                                            />
                                        ))}
                                    </Stack>
                                    <Button variant="outlined" size="small" fullWidth startIcon={<Architecture />}>Set Focal Point</Button>
                                </AccordionDetails>
                            </Accordion>

                            <Accordion disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', mb: 1, borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><WbSunnyOutlined fontSize="small" sx={{ mr: 1 }} /> Light</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 1, px: 2 }}>
                                    {[
                                        { label: 'Brightness', key: 'brightness' },
                                        { label: 'Contrast', key: 'contrast' },
                                        { label: 'Ultra HDR', key: 'hdr' },
                                        { label: 'White Point', key: 'whitePoint' },
                                        { label: 'Highlights', key: 'highlights' },
                                        { label: 'Shadows', key: 'shadows' },
                                        { label: 'Black Point', key: 'blackPoint' }
                                    ].map(item => (
                                        <Box key={item.key} sx={{ mb: 1 }}>
                                            <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                                                <Typography variant="caption" color="textSecondary">{item.label}</Typography>
                                                <Typography variant="caption" color="textSecondary">{adjustments[item.key]}</Typography>
                                            </Box>
                                            <Slider value={adjustments[item.key]} min={-100} max={100} onChange={handleAdjustmentChange(item.key)} size="small" sx={{ color: '#64748b', p: 0 }} />
                                        </Box>
                                    ))}
                                </AccordionDetails>
                            </Accordion>

                            <Accordion disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', mb: 1, borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><ColorLensOutlined fontSize="small" sx={{ mr: 1 }} /> Color</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 1, px: 2 }}>
                                    {[
                                        { label: 'Saturation', key: 'saturation' },
                                        { label: 'Warmth', key: 'warmth' },
                                        { label: 'Tint', key: 'tint' },
                                        { label: 'Skin Tone', key: 'skinTone' },
                                        { label: 'Blue Tone', key: 'blueTone' }
                                    ].map(item => (
                                        <Box key={item.key} sx={{ mb: 1 }}>
                                            <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                                                <Typography variant="caption" color="textSecondary">{item.label}</Typography>
                                                <Typography variant="caption" color="textSecondary">{adjustments[item.key]}</Typography>
                                            </Box>
                                            <Slider value={adjustments[item.key]} min={-100} max={100} onChange={handleAdjustmentChange(item.key)} size="small" sx={{ color: '#64748b', p: 0 }} />
                                        </Box>
                                    ))}
                                </AccordionDetails>
                            </Accordion>

                            <Accordion disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', mb: 1, borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><BlurOn fontSize="small" sx={{ mr: 1 }} /> Effects</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 1, px: 2 }}>
                                    <Box sx={{ mb: 1 }}>
                                        <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                                            <Typography variant="caption" color="textSecondary">Vignette</Typography>
                                            <Typography variant="caption" color="textSecondary">{adjustments.vignette}</Typography>
                                        </Box>
                                        <Slider value={adjustments.vignette} min={0} max={100} onChange={handleAdjustmentChange('vignette')} size="small" sx={{ color: '#64748b', p: 0 }} />
                                    </Box>
                                </AccordionDetails>
                            </Accordion>

                            <Accordion disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, border: '1px solid #e2e8f0', borderRadius: 1 }}>
                                <AccordionSummary expandIcon={<ExpandMore />}>
                                    <Typography variant="body2" fontWeight="600" sx={{ display: 'flex', alignItems: 'center' }}><FilterBAndW fontSize="small" sx={{ mr: 1 }} /> LUT Filters</Typography>
                                </AccordionSummary>
                                <AccordionDetails sx={{ pt: 0, pb: 2, px: 2 }}>
                                    <Grid container spacing={1}>
                                        {['None', 'Vivid', 'West', 'Palma', 'Metro', 'Eiffel', 'Blush', 'Modena', 'Vogue'].map(filter => (
                                            <Grid item xs={6} key={filter}>
                                                <Paper
                                                    onClick={() => setActiveFilter(filter)}
                                                    elevation={0}
                                                    sx={{ height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid', borderColor: activeFilter === filter ? '#4f46e5' : '#e2e8f0', bgcolor: activeFilter === filter ? '#eef2ff' : 'transparent', cursor: 'pointer' }}
                                                >
                                                    <Typography variant="caption" fontWeight="600" color={activeFilter === filter ? '#4f46e5' : 'textPrimary'}>{filter}</Typography>
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
                                    <AutoAwesome fontSize="small" sx={{ mr: 1 }} /> Agentic Tools
                                </Typography>
                                <Typography variant="caption" color="#5b21b6">
                                    Generative and analytical models optimized for local HuggingFace inference nodes.
                                </Typography>
                            </Box>

                            <Stack spacing={2}>
                                <Button variant="outlined" onClick={() => handleQuickAction('magic_eraser')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700">Magic Eraser</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">Remove unwanted objects & people</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('unblur')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700">Unblur & Sharpen</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">Restore detail to blurry subjects</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('portrait_light')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700">Portrait Light</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">Relight faces and subjects dynamically</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('generative_expand')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}><Crop fontSize="small" sx={{ mr: 0.5 }} /> Generative Expand</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">Outpaint borders to alter aspect ratios</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('super_res')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}><HighQuality fontSize="small" sx={{ mr: 0.5 }} /> Super Resolution</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">Lossless 4x upscale via ESRGAN</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('bg_swap')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}><Wallpaper fontSize="small" sx={{ mr: 0.5 }} /> Background Swap</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">Generate new contexts via prompt</Typography>
                                    </Box>
                                </Button>

                                <Button variant="outlined" onClick={() => handleQuickAction('depth_map')} disabled={aiProcessing} sx={{ justifyContent: 'flex-start', color: '#4f46e5', borderColor: '#c7d2fe', p: 1.2 }}>
                                    <Box sx={{ textAlign: 'left' }}>
                                        <Typography variant="body2" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}><ViewInAr fontSize="small" sx={{ mr: 0.5 }} /> 3D Depth Map</Typography>
                                        <Typography variant="caption" color="textSecondary" display="block">Extract geometry for parallax motion</Typography>
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
                                    label={<Typography variant="body2" fontWeight="500">Save as New Version</Typography>}
                                    sx={{ m: 0, p: 0.5, mb: 0.5, border: '1px solid', borderColor: saveMode === 'version' ? '#4f46e5' : 'transparent', borderRadius: 1, bgcolor: saveMode === 'version' ? '#eef2ff' : 'transparent' }}
                                />
                                <FormControlLabel
                                    value="new" control={<Radio size="small" />}
                                    label={<Typography variant="body2" fontWeight="500">Save as Copy</Typography>}
                                    sx={{ m: 0, p: 0.5, border: '1px solid', borderColor: saveMode === 'new' ? '#4f46e5' : 'transparent', borderRadius: 1, bgcolor: saveMode === 'new' ? '#eef2ff' : 'transparent' }}
                                />
                            </RadioGroup>
                        </FormControl>
                    </Box>
                </Grid>
            </Grid>
        </Dialog>
    );
}