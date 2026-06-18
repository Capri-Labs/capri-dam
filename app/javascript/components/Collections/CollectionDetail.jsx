import React, { useState, useEffect } from 'react';
import {
    Box, Typography, Button, Grid, Card, CardContent,
    IconButton, Chip, Stack, CircularProgress, Menu, MenuItem, Paper,
    Dialog, DialogTitle, DialogContent, DialogActions, TextField, Slider, Divider, ImageListItemBar, ImageListItem,
    ImageList
} from '@mui/material';
import {
    ArrowBack, Share, MoreVert, SettingsSuggest,
    AutoAwesome, Image as ImageIcon, CloudDownload, DeleteOutlined, PushPin, Analytics, PlayArrow,
    Shield, WarningAmber, AutoFixHigh
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';
import { useCollections } from './CollectionContext';
import SemanticClusterMap from './SemanticClusterMap';

export default function CollectionDetail({ slug, onBack }) {
    const notify = useNotify();
    const { updateSmartRule, toggleAssetPin, simulateSmartRule, temporalDate } = useCollections();
    const [collection, setCollection] = useState(null);
    const [loading, setLoading] = useState(true);

    const [openRuleDialog, setOpenRuleDialog] = useState(false);
    const [ruleForm, setRuleForm] = useState({ semantic_prompt: '', similarity_threshold: 0.8 });

    const [simulating, setSimulating] = useState(false);
    const [simulationResults, setSimulationResults] = useState(null);

    const [anchorEl, setAnchorEl] = useState(null);
    const [selectedAsset, setSelectedAsset] = useState(null);

    // AI Insights State
    const [aiDialogOpen, setAiDialogOpen] = useState(false);
    const [aiInsights, setAiInsights] = useState(null);
    const [analyzing, setAnalyzing] = useState(false);

    const [mapDialogOpen, setMapDialogOpen] = useState(false);

    useEffect(() => {
        const fetchCollectionDetail = async () => {
            setLoading(true);
            try {
                const queryParam = temporalDate ? `?as_of=${temporalDate}` : '';
                const res = await fetch(`/api/v1/collections/${slug}${queryParam}`);
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
    }, [slug, notify, onBack, temporalDate]);

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
            similarity_threshold: parseFloat(collection.collection_rule?.similarity_threshold) || 0.8
        });
        setSimulationResults(null); // Reset sandbox on open
        setOpenRuleDialog(true);
    };

    const handleSimulate = async () => {
        if (!ruleForm.semantic_prompt) return;
        setSimulating(true);
        const results = await simulateSmartRule(ruleForm.semantic_prompt, ruleForm.similarity_threshold);
        setSimulationResults(results || []);
        setSimulating(false);
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
    const assets = collection.collection_assets || [];

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
                        {/*  Trigger AI Map */}
                        <Button variant="outlined" startIcon={<AutoFixHigh />} onClick={() => setMapDialogOpen(true)} sx={{ borderColor: '#e3e8ef', color: '#0ea5e9' }}>
                            View AI Map
                        </Button>
                        {/* Existing Configurator Button */}
                        <Button variant="outlined" startIcon={<SettingsSuggest />} onClick={openConfigurator} sx={{ borderColor: '#e3e8ef', color: '#5e35b1' }}>
                            {isSmart ? 'Configure Rules' : 'Upgrade to Smart Collection'}
                        </Button>

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

            {/*  Automated TDM Compliance Sweep Display */}
            {collection.compliance_violations && collection.compliance_violations.length > 0 && (
                <Paper elevation={0} sx={{ p: 2, mb: 4, borderRadius: 2, bgcolor: '#fef2f2', border: '1px solid #fca5a5', display: 'flex', alignItems: 'flex-start' }}>
                    <Shield sx={{ color: '#ef4444', mr: 2, mt: 0.5 }} />
                    <Box>
                        <Typography variant="subtitle2" sx={{ color: '#b91c1c', fontWeight: 700, mb: 0.5 }}>
                            Governance & Usage Violations Detected ({collection.compliance_violations.length})
                        </Typography>
                        <Typography variant="body2" sx={{ color: '#991b1b', mb: 1 }}>
                            The following assets conflict with this workspace's legal or temporal boundaries. Resolve these before exporting to downstream CMS systems.
                        </Typography>
                        <ul style={{ margin: 0, paddingLeft: '20px', color: '#991b1b', fontSize: '0.875rem' }}>
                            {collection.compliance_violations.map((violation, idx) => (
                                <li key={idx} style={{ marginBottom: '4px' }}>
                                    <strong>{violation.title}:</strong> {violation.reason}
                                </li>
                            ))}
                        </ul>
                    </Box>
                </Paper>
            )}

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

            {/* Smart Rule Configurator & Sandbox Dialog */}
            <Dialog open={openRuleDialog} onClose={() => setOpenRuleDialog(false)} maxWidth="md" fullWidth>
                <DialogTitle sx={{ fontWeight: 700, borderBottom: '1px solid #e2e8f0', pb: 2, display: 'flex', alignItems: 'center' }}>
                    <AutoAwesome sx={{ color: '#8e24aa', mr: 1.5 }} /> Smart Rule Engine Sandbox
                </DialogTitle>

                <DialogContent sx={{ p: 0, display: 'flex', flexDirection: 'column', minHeight: 400 }}>
                    <Grid container sx={{ flexGrow: 1 }}>

                        {/* LEFT COLUMN: The Configurator */}
                        <Grid item xs={12} md={5} sx={{ p: 3, borderRight: { md: '1px solid #e2e8f0' }, bgcolor: '#f8fafc' }}>
                            <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                                Define semantic boundaries. Assets meeting the Cosine Similarity threshold will be autonomously routed here.
                            </Typography>

                            <TextField
                                fullWidth multiline rows={4} label="Semantic AI Prompt"
                                placeholder="e.g., High resolution outdoor lifestyle shots involving snow"
                                value={ruleForm.semantic_prompt}
                                onChange={(e) => setRuleForm({...ruleForm, semantic_prompt: e.target.value})}
                                sx={{ mb: 4, bgcolor: '#fff' }}
                            />

                            <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1 }}>Cosine Similarity Threshold</Typography>
                            <Box sx={{ px: 2, mb: 2 }}>
                                <Slider
                                    value={Number(ruleForm.similarity_threshold) || 0.8}
                                    min={0.5} max={0.99} step={0.01}
                                    valueLabelDisplay="auto"
                                    onChange={(e, val) => setRuleForm({...ruleForm, similarity_threshold: val})}
                                    sx={{ color: '#5e35b1' }}
                                />
                            </Box>
                            <Typography variant="caption" color="textSecondary">
                                Currently set to <strong>{ruleForm.similarity_threshold}</strong>. Higher values require stricter semantic matching.
                            </Typography>

                            <Button
                                fullWidth
                                variant="outlined"
                                startIcon={simulating ? <CircularProgress size={16} /> : <PlayArrow />}
                                onClick={handleSimulate}
                                disabled={!ruleForm.semantic_prompt || simulating}
                                sx={{ mt: 4, borderColor: '#5e35b1', color: '#5e35b1', bgcolor: '#fff' }}
                            >
                                {simulating ? 'Vectorizing...' : 'Run Dry-Run Simulation'}
                            </Button>
                        </Grid>

                        {/* RIGHT COLUMN: The Sandbox Results */}
                        <Grid item xs={12} md={7} sx={{ p: 3, display: 'flex', flexDirection: 'column' }}>
                            <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 2, display: 'flex', justifyContent: 'space-between' }}>
                                Sandbox Preview
                                {simulationResults && (
                                    <Chip size="small" label={`${simulationResults.length} theoretical matches`} color="success" variant="outlined" />
                                )}
                            </Typography>

                            {simulating ? (
                                <Box sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
                                    <CircularProgress size={30} sx={{ color: '#8e24aa', mb: 2 }} />
                                    <Typography variant="body2" color="textSecondary">Scanning vector database...</Typography>
                                </Box>
                            ) : !simulationResults ? (
                                <Box sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', border: '1px dashed #cbd5e1', borderRadius: 2, bgcolor: '#f1f5f9' }}>
                                    <AutoAwesome sx={{ fontSize: 40, color: '#cbd5e1', mb: 1 }} />
                                    <Typography variant="body2" color="textSecondary">Run a simulation to see predicted assets.</Typography>
                                </Box>
                            ) : simulationResults.length === 0 ? (
                                <Box sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', border: '1px dashed #fca5a5', borderRadius: 2, bgcolor: '#fef2f2' }}>
                                    <Typography variant="body2" color="error">No assets met the threshold.</Typography>
                                    <Typography variant="caption" color="textSecondary">Try lowering the similarity score.</Typography>
                                </Box>
                            ) : (
                                <Box sx={{ overflowY: 'auto', maxHeight: 350, pr: 1 }}>
                                    <ImageList cols={2} gap={12}>
                                        {simulationResults.map((asset) => (
                                            <ImageListItem key={asset.id} sx={{ border: '1px solid #e2e8f0', borderRadius: 2, overflow: 'hidden' }}>
                                                {/* Fallback image block if real image URL isn't present in mock */}
                                                <Box sx={{ height: 120, bgcolor: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                                                    {asset.url ? (
                                                        <img src={asset.url} alt={asset.title} style={{ height: '100%', width: '100%', objectFit: 'cover' }} />
                                                    ) : (
                                                        <ImageIcon sx={{ color: '#cbd5e1', fontSize: 32 }} />
                                                    )}
                                                </Box>
                                                <ImageListItemBar
                                                    title={<Typography variant="caption" sx={{ fontWeight: 600 }}>{asset.title || 'Asset'}</Typography>}
                                                    subtitle={<Typography variant="caption" sx={{ color: '#a7f3d0' }}>Match: {asset.mock_match_score || 0.88}</Typography>}
                                                    sx={{ bgcolor: 'rgba(15, 23, 42, 0.8)' }}
                                                />
                                            </ImageListItem>
                                        ))}
                                    </ImageList>
                                </Box>
                            )}
                        </Grid>
                    </Grid>
                </DialogContent>

                <DialogActions sx={{ p: 2, borderTop: '1px solid #e2e8f0', bgcolor: '#f8fafc' }}>
                    <Button onClick={() => setOpenRuleDialog(false)} color="inherit">Cancel</Button>
                    <Button onClick={handleSaveRule} variant="contained" sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                        Activate Rule in Production
                    </Button>
                </DialogActions>
            </Dialog>

            <SemanticClusterMap
                open={mapDialogOpen}
                onClose={() => setMapDialogOpen(false)}
                slug={slug}
            />
        </Box>
    );
}