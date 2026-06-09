import React, { useState, useEffect } from 'react';
import {
    Box, Typography, Button, Grid, Card, CardContent,
    IconButton, Chip, Stack, CircularProgress, Menu, MenuItem, Paper,
    Dialog, DialogTitle, DialogContent, DialogActions, TextField, Slider, Divider
} from '@mui/material';
import {
    ArrowBack, Share, MoreVert, SettingsSuggest,
    AutoAwesome, Image as ImageIcon, CloudDownload, DeleteOutlined, PushPin, Analytics
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';
import { useCollections } from './CollectionContext';

export default function CollectionDetail({ slug, onBack }) {
    const notify = useNotify();
    const { updateSmartRule, toggleAssetPin } = useCollections();
    const [collection, setCollection] = useState(null);
    const [loading, setLoading] = useState(true);

    const [openRuleDialog, setOpenRuleDialog] = useState(false);
    const [ruleForm, setRuleForm] = useState({ semantic_prompt: '', similarity_threshold: 0.8 });

    const [anchorEl, setAnchorEl] = useState(null);
    const [selectedAsset, setSelectedAsset] = useState(null);

    // AI Insights State
    const [aiDialogOpen, setAiDialogOpen] = useState(false);
    const [aiInsights, setAiInsights] = useState(null);
    const [analyzing, setAnalyzing] = useState(false);

    useEffect(() => {
        const fetchCollectionDetail = async () => {
            setLoading(true);
            try {
                const res = await fetch(`/api/v1/collections/${slug}`);
                if (res.ok) {
                    const data = await res.json();
                    setCollection(data);
                } else {
                    notify("Failed to load collection.", "error");
                    onBack();
                }
            } catch (error) {
                notify("Network error.", "error");
            } finally {
                setLoading(false);
            }
        };

        fetchCollectionDetail();
    }, [slug, notify, onBack]);

    const handleMenuOpen = (event, asset) => {
        setAnchorEl(event.currentTarget);
        setSelectedAsset(asset);
    };

    const handleMenuClose = () => {
        setAnchorEl(null);
        setSelectedAsset(null);
    };

    const handleTogglePin = async () => {
        if (!selectedAsset) return;
        handleMenuClose();

        // Optimistic UI update
        setCollection(prev => ({
            ...prev,
            assets: prev.assets.map(a => a.id === selectedAsset.id ? { ...a, pinned: !a.pinned } : a)
        }));

        await toggleAssetPin(slug, selectedAsset.id);
    };

    const handleSaveRule = async () => {
        const updatedCollection = await updateSmartRule(slug, ruleForm);
        if (updatedCollection) {
            setCollection(updatedCollection);
            setOpenRuleDialog(false);
        }
    };

    const openConfigurator = () => {
        setRuleForm({
            semantic_prompt: collection.collection_rule?.semantic_prompt || '',
            similarity_threshold: collection.collection_rule?.similarity_threshold || 0.8
        });
        setOpenRuleDialog(true);
    };

    const runAiAnalysis = () => {
        setAiDialogOpen(true);
        setAnalyzing(true);
        // Simulate AI Gateway Analysis Call
        setTimeout(() => {
            setAiInsights({
                summary: "This collection primarily features high-contrast outdoor lifestyle imagery. Metadata completeness is at 92%.",
                tdm_warnings: "2 assets lack required alt-text formatting. 1 asset has a low-resolution vector warning.",
                campaign_alignment: "Strong alignment with 'Winter 2026' brand guidelines."
            });
            setAnalyzing(false);
        }, 1500);
    };

    if (loading) {
        return (
            <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', py: 10 }}>
                <CircularProgress size={40} sx={{ mb: 2, color: '#5e35b1' }} />
                <Typography color="textSecondary">Loading workspace...</Typography>
            </Box>
        );
    }

    if (!collection) return null;

    const isSmart = collection.collection_type === 'smart';
    const assets = collection.assets || [];

    return (
        <Box>
            <Paper elevation={0} sx={{ p: 3, mb: 4, borderRadius: 3, border: '1px solid #e3e8ef', bgcolor: '#fff' }}>
                <Button startIcon={<ArrowBack />} onClick={onBack} sx={{ color: '#64748b', mb: 2, textTransform: 'none' }}>
                    Back to Workspace Board
                </Button>

                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <Box>
                        <Stack direction="row" alignItems="center" spacing={2} sx={{ mb: 1 }}>
                            <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                                {collection.name}
                            </Typography>
                            {isSmart && (
                                <Chip icon={<AutoAwesome fontSize="small" />} label="AI Smart Collection" size="small" sx={{ bgcolor: '#f3e5f5', color: '#8e24aa', fontWeight: 600 }} />
                            )}
                        </Stack>
                        <Typography variant="body1" color="textSecondary" sx={{ maxWidth: 800 }}>
                            {collection.description}
                        </Typography>

                        {isSmart && collection.collection_rule && (
                            <Box sx={{ mt: 2, p: 1.5, bgcolor: '#f8fafc', borderRadius: 2, border: '1px dashed #cbd5e1', display: 'inline-block' }}>
                                <Typography variant="caption" sx={{ fontWeight: 700, color: '#475569', display: 'block' }}>Active Routing Rule:</Typography>
                                <Typography variant="body2" sx={{ color: '#0f172a', fontStyle: 'italic' }}>
                                    "{collection.collection_rule.semantic_prompt}" (Threshold: {collection.collection_rule.similarity_threshold})
                                </Typography>
                            </Box>
                        )}
                    </Box>

                    <Stack direction="row" spacing={2}>
                        {/* Trigger AI Insights */}
                        <Button variant="outlined" startIcon={<AutoAwesome />} onClick={runAiAnalysis} sx={{ borderColor: '#e3e8ef', color: '#5e35b1' }}>
                            Ask AI about this Collection
                        </Button>

                        {isSmart ? (
                            <Button variant="outlined" startIcon={<SettingsSuggest />} onClick={openConfigurator} sx={{ borderColor: '#e3e8ef', color: '#5e35b1' }}>
                                Configure Rules
                            </Button>
                        ) : (
                            <Button variant="outlined" startIcon={<SettingsSuggest />} onClick={openConfigurator} sx={{ borderColor: '#e3e8ef', color: '#5e35b1' }}>
                                Upgrade to Smart Collection
                            </Button>
                        )}
                    </Stack>
                </Box>
            </Paper>

            <Typography variant="h6" sx={{ fontWeight: 600, mb: 3 }}>Curated Assets ({assets.length})</Typography>

            {assets.length === 0 ? (
                <Paper elevation={0} sx={{ p: 6, textAlign: 'center', borderRadius: 3, border: '1px dashed #cbd5e1', bgcolor: '#f8fafc' }}>
                    <ImageIcon sx={{ fontSize: 48, color: '#cbd5e1', mb: 2 }} />
                    <Typography variant="h6" color="textSecondary">This collection is empty</Typography>
                    <Typography variant="body2" color="textSecondary">Navigate to the Asset Explorer to add files, or define a Smart Rule to auto-populate.</Typography>
                </Paper>
            ) : (
                <Grid container spacing={3}>
                    {assets.map((asset) => (
                        <Grid item xs={12} sm={6} md={4} lg={3} key={asset.id}>
                            <Card elevation={0} sx={{ border: '1px solid', borderColor: asset.pinned ? '#5e35b1' : '#e3e8ef', borderRadius: 2, position: 'relative' }}>
                                {asset.pinned && (
                                    <Box sx={{ position: 'absolute', top: 8, right: 8, bgcolor: '#fff', borderRadius: '50%', p: 0.5, boxShadow: 1, zIndex: 1 }}>
                                        <PushPin sx={{ fontSize: 16, color: '#5e35b1' }} />
                                    </Box>
                                )}
                                <Box sx={{ height: 160, bgcolor: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center', borderBottom: '1px solid #e3e8ef' }}>
                                    <ImageIcon sx={{ fontSize: 40, color: '#cbd5e1' }} />
                                </Box>
                                <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
                                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                                        <Box sx={{ overflow: 'hidden' }}>
                                            {/* Note: Adjust properties below based on your actual Asset model JSON */}
                                            <Typography variant="subtitle2" sx={{ fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{asset.original_filename || asset.title || 'Unknown File'}</Typography>
                                            <Typography variant="caption" color="textSecondary">{asset.file_size || asset.size || 'N/A'}</Typography>
                                        </Box>
                                        <IconButton size="small" onClick={(e) => handleMenuOpen(e, asset)} sx={{ ml: 1, mt: -0.5, mr: -0.5 }}>
                                            <MoreVert fontSize="small" />
                                        </IconButton>
                                    </Box>
                                </CardContent>
                            </Card>
                        </Grid>
                    ))}
                </Grid>
            )}

            {/* Asset Actions Menu */}
            <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleMenuClose} elevation={2} PaperProps={{ sx: { borderRadius: 2, minWidth: 180 } }}>
                <MenuItem onClick={handleMenuClose}>
                    <CloudDownload fontSize="small" sx={{ mr: 1.5, color: '#64748b' }} /> Download
                </MenuItem>
                {isSmart && selectedAsset && (
                    <MenuItem onClick={handleTogglePin}>
                        <PushPin fontSize="small" sx={{ mr: 1.5, color: '#5e35b1' }} />
                        {selectedAsset.pinned ? 'Unpin Asset' : 'Pin to Collection'}
                    </MenuItem>
                )}
                <MenuItem onClick={handleMenuClose} sx={{ color: '#d32f2f' }}>
                    <DeleteOutlined fontSize="small" sx={{ mr: 1.5 }} /> Remove
                </MenuItem>
            </Menu>

            {/* AI Insights Dialog */}
            <Dialog open={aiDialogOpen} onClose={() => setAiDialogOpen(false)} maxWidth="sm" fullWidth>
                <DialogTitle sx={{ fontWeight: 700, borderBottom: '1px solid #e2e8f0', pb: 2, display: 'flex', alignItems: 'center' }}>
                    <AutoAwesome sx={{ color: '#8e24aa', mr: 1.5 }} /> Campaign Insights
                </DialogTitle>
                <DialogContent sx={{ p: 3, mt: 2, minHeight: 150 }}>
                    {analyzing ? (
                        <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', py: 4 }}>
                            <CircularProgress size={30} sx={{ color: '#8e24aa', mb: 2 }} />
                            <Typography color="textSecondary">Vectorizing collection assets and scanning metadata...</Typography>
                        </Box>
                    ) : aiInsights ? (
                        <Box>
                            <Typography variant="subtitle2" sx={{ fontWeight: 600, color: '#1e293b', mb: 0.5 }}>Semantic Summary</Typography>
                            <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>{aiInsights.summary}</Typography>

                            <Divider sx={{ mb: 3 }} />

                            <Typography variant="subtitle2" sx={{ fontWeight: 600, color: '#b91c1c', mb: 0.5, display: 'flex', alignItems: 'center' }}>
                                <Analytics sx={{ fontSize: 18, mr: 1 }} /> Technical Debt Warnings
                            </Typography>
                            <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>{aiInsights.tdm_warnings}</Typography>
                        </Box>
                    ) : null}
                </DialogContent>
                <DialogActions sx={{ p: 2 }}>
                    <Button onClick={() => setAiDialogOpen(false)} color="inherit">Close</Button>
                </DialogActions>
            </Dialog>

            {/* Smart Rule Configurator Dialog */}
            <Dialog open={openRuleDialog} onClose={() => setOpenRuleDialog(false)} maxWidth="sm" fullWidth>
                <DialogTitle sx={{ fontWeight: 700, borderBottom: '1px solid #e2e8f0', pb: 2 }}>Configure Smart Routing</DialogTitle>
                <DialogContent sx={{ p: 3, mt: 2 }}>
                    <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                        Define the semantic properties of this campaign. The AI Gateway will autonomously route matching assets here as they are ingested.
                    </Typography>

                    <TextField
                        fullWidth multiline rows={3} label="Semantic AI Prompt"
                        placeholder="e.g., High resolution outdoor lifestyle shots involving snow"
                        value={ruleForm.semantic_prompt}
                        onChange={(e) => setRuleForm({...ruleForm, semantic_prompt: e.target.value})}
                        sx={{ mb: 4 }}
                    />

                    <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1 }}>Cosine Similarity Threshold</Typography>
                    <Box sx={{ px: 2 }}>
                        <Slider
                            value={ruleForm.similarity_threshold}
                            min={0.5} max={1.0} step={0.05}
                            valueLabelDisplay="auto"
                            onChange={(e, val) => setRuleForm({...ruleForm, similarity_threshold: val})}
                        />
                    </Box>
                    <Typography variant="caption" color="textSecondary">
                        A higher threshold ({'>'} 0.85) ensures strict matching, reducing false positives and maintaining zero-noise operations.
                    </Typography>
                </DialogContent>
                <DialogActions sx={{ p: 3, pt: 0 }}>
                    <Button onClick={() => setOpenRuleDialog(false)} color="inherit">Cancel</Button>
                    <Button onClick={handleSaveRule} variant="contained" sx={{ bgcolor: '#5e35b1' }}>Save & Activate Rules</Button>
                </DialogActions>
            </Dialog>
        </Box>
    );
}