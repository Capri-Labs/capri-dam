import React, { useState, useEffect } from 'react';
import {
    Dialog, AppBar, Toolbar, IconButton, Typography, Box, Grid,
    Button, Chip, Divider, Autocomplete, TextField, Stack, Paper, CircularProgress
} from '@mui/material';
import { Close, AutoAwesome, Face, TextFields, LabelOutlined, Save } from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

// Mock database of existing tags for the Auto-suggestion feature
const EXISTING_DATABASE_TAGS = [
    'Summer Campaign', 'Social Media', 'High Resolution', 'Product Shot',
    'Lifestyle', 'Studio', 'Outdoor', 'Approved', 'Needs Review'
];

export default function AssetTagsEditor({ asset, open, onClose, onSave }) {
    const notify = useNotify();
    const [manualTags, setManualTags] = useState([]);
    const [aiTags, setAiTags] = useState({ faces: [], text: [], general: [] });
    const [isScanning, setIsScanning] = useState(false);

    useEffect(() => {
        if (asset && open) {
            // Load existing tags from the asset's properties
            try {
                const props = typeof asset.properties === 'string' ? JSON.parse(asset.properties) : (asset.properties || {});
                setManualTags(props.tags || []);
                // If you already have AI tags stored, load them here
                setAiTags(props.ai_tags || { faces: [], text: [], general: [] });
            } catch (e) {
                setManualTags([]);
            }
        }
    }, [asset, open]);

    const handleRunAiScan = () => {
        setIsScanning(true);
        // Simulate a call to your Python AI Gateway for Vision Analysis
        setTimeout(() => {
            setAiTags({
                faces: ['Unnamed Person 1'],
                text: ['CE', 'Music Notes'],
                general: ['Indoor', 'Instrument', 'Playing']
            });
            setIsScanning(false);
            notify("AI Vision Scan complete. New tags discovered.", "success");
        }, 2000);
    };

    const handleSave = () => {
        // Here you would trigger your API to patch the asset's properties JSONB payload
        const updatedProperties = {
            ...asset.properties,
            tags: manualTags,
            ai_tags: aiTags
        };

        onSave({ ...asset, properties: updatedProperties });
        notify("Tags updated successfully.", "success");
    };

    if (!asset) return null;

    return (
        <Dialog fullScreen open={open} onClose={onClose}>
            <AppBar sx={{ position: 'relative', bgcolor: '#ffffff', color: '#1e293b', boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
                <Toolbar>
                    <IconButton edge="start" color="inherit" onClick={onClose} aria-label="close">
                        <Close />
                    </IconButton>
                    <Typography sx={{ ml: 2, flex: 1, fontWeight: 700 }} variant="h6">
                        Manage Tags: {asset.title || asset.name}
                    </Typography>
                    <Button variant="contained" startIcon={<Save />} onClick={handleSave} sx={{ bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' } }}>
                        Save Changes
                    </Button>
                </Toolbar>
            </AppBar>

            <Grid container sx={{ height: 'calc(100vh - 64px)' }}>
                {/* LEFT PANE: 60% Image Preview */}
                <Grid  sx={{ width: '60%', bgcolor: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center', p: 4, borderRight: '1px solid #cbd5e1' }}>
                    {asset.url ? (
                        <Box component="img" src={asset.url} alt="Preview" sx={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain', boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.1)' }} />
                    ) : (
                        <Typography color="textSecondary">Preview not available.</Typography>
                    )}
                </Grid>

                {/* RIGHT PANE: 40% Tagging Workspace */}
                <Grid  sx={{ width: '40%', bgcolor: '#ffffff', overflowY: 'auto', p: 4 }}>

                    {/* MANUAL TAGS SECTION */}
                    <Box sx={{ mb: 5 }}>
                        <Typography variant="subtitle1" fontWeight="700" sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                            <LabelOutlined sx={{ mr: 1, color: '#475569' }} /> Manual Tags
                        </Typography>
                        <Autocomplete
                            multiple
                            freeSolo
                            options={EXISTING_DATABASE_TAGS}
                            value={manualTags}
                            onChange={(event, newValue) => setManualTags(newValue)}
                            renderTags={(value, getTagProps) =>
                                value.map((option, index) => (
                                    <Chip variant="outlined" label={option} {...getTagProps({ index })} sx={{ borderRadius: 1 }} />
                                ))
                            }
                            renderInput={(params) => (
                                <TextField {...params} variant="outlined" placeholder="Search or type new tag..." helperText="Press enter to add custom tags not in the database." />
                            )}
                        />
                    </Box>

                    <Divider sx={{ mb: 4 }} />

                    {/* AI TAGS SECTION */}
                    <Box sx={{ mb: 3, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <Typography variant="subtitle1" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}>
                            <AutoAwesome sx={{ mr: 1, color: '#8b5cf6' }} /> AI-Recognized Tags
                        </Typography>
                        <Button variant="outlined" size="small" onClick={handleRunAiScan} disabled={isScanning} sx={{ color: '#8b5cf6', borderColor: '#c4b5fd' }}>
                            {isScanning ? <CircularProgress size={20} /> : 'Run Smart Scan'}
                        </Button>
                    </Box>

                    <Stack spacing={3}>
                        {/* Facial Recognition */}
                        <Paper elevation={0} sx={{ p: 2, border: '1px solid #e2e8f0', borderRadius: 2 }}>
                            <Typography variant="body2" fontWeight="600" sx={{ mb: 1.5, display: 'flex', alignItems: 'center', color: '#475569' }}>
                                <Face fontSize="small" sx={{ mr: 1 }} /> Face Recognition ({aiTags.faces.length})
                            </Typography>
                            {aiTags.faces.length === 0 ? <Typography variant="caption" color="textSecondary">No faces detected.</Typography> : (
                                <Stack direction="row" spacing={1} flexWrap="wrap">
                                    {aiTags.faces.map((tag, i) => <Chip key={i} label={tag} size="small" sx={{ bgcolor: '#f1f5f9' }} />)}
                                </Stack>
                            )}
                        </Paper>

                        {/* OCR / Text in Image */}
                        <Paper elevation={0} sx={{ p: 2, border: '1px solid #e2e8f0', borderRadius: 2 }}>
                            <Typography variant="body2" fontWeight="600" sx={{ mb: 1.5, display: 'flex', alignItems: 'center', color: '#475569' }}>
                                <TextFields fontSize="small" sx={{ mr: 1 }} /> Text-in-Image ({aiTags.text.length})
                            </Typography>
                            {aiTags.text.length === 0 ? <Typography variant="caption" color="textSecondary">No text detected.</Typography> : (
                                <Stack direction="row" spacing={1} flexWrap="wrap">
                                    {aiTags.text.map((tag, i) => <Chip key={i} label={tag} size="small" sx={{ bgcolor: '#fef2f2', color: '#b91c1c' }} />)}
                                </Stack>
                            )}
                        </Paper>

                        {/* General Semantic Objects */}
                        <Paper elevation={0} sx={{ p: 2, border: '1px solid #e2e8f0', borderRadius: 2 }}>
                            <Typography variant="body2" fontWeight="600" sx={{ mb: 1.5, display: 'flex', alignItems: 'center', color: '#475569' }}>
                                <LabelOutlined fontSize="small" sx={{ mr: 1 }} /> Semantic Objects ({aiTags.general.length})
                            </Typography>
                            {aiTags.general.length === 0 ? <Typography variant="caption" color="textSecondary">No objects detected.</Typography> : (
                                <Stack direction="row" spacing={1} flexWrap="wrap">
                                    {aiTags.general.map((tag, i) => <Chip key={i} label={tag} size="small" sx={{ bgcolor: '#f3e8ff', color: '#7e22ce' }} />)}
                                </Stack>
                            )}
                        </Paper>
                    </Stack>
                </Grid>
            </Grid>
        </Dialog>
    );
}