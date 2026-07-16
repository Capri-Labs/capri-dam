import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, Typography, Button, Grid, Card, CardContent,
    IconButton, Chip, Stack, CircularProgress, Menu, MenuItem, Paper,
    Dialog, DialogTitle, DialogContent, DialogActions, TextField, Slider, Divider, ImageListItemBar, ImageListItem,
    ImageList, Tooltip, Collapse, ToggleButton, ToggleButtonGroup
} from '@mui/material';
import {
    ArrowBack, Share, MoreVert, SettingsSuggest,
    AutoAwesome, Image as ImageIcon, CloudDownload, DeleteOutlined, PushPin, Analytics, PlayArrow,
    Shield, WarningAmber, AutoFixHigh, LaunchOutlined, AddPhotoAlternate, ExpandMore, ExpandLess
} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';
import { useCollections } from './CollectionContext';
import { navigateTo } from '../../utils/globalutils';
import SemanticClusterMap from './SemanticClusterMap';
import ShareCollectionDialog from './ShareCollectionDialog';
import AddAssetsToCollectionDialog from './AddAssetsToCollectionDialog';
import { useTranslation } from 'react-i18next';

export default function CollectionDetail({ slug, onBack }) {
    const notify = useNotify();
    const { t } = useTranslation();
    const { updateSmartRule, simulateSmartRule, temporalDate } = useCollections();
    const [collection, setCollection] = useState(null);
    const [loading, setLoading] = useState(true);

    const [openRuleDialog, setOpenRuleDialog] = useState(false);
    const [ruleForm, setRuleForm] = useState({ match_mode: 'semantic', semantic_prompt: '', similarity_threshold: 0.8, metadata_filters: {} });
    const [filterKeyDraft, setFilterKeyDraft] = useState('');
    const [filterValueDraft, setFilterValueDraft] = useState('');

    const [simulating, setSimulating] = useState(false);
    const [simulationResults, setSimulationResults] = useState(null);

    const [anchorEl, setAnchorEl] = useState(null);
    const [selectedAsset, setSelectedAsset] = useState(null);
    const [removingAssetId, setRemovingAssetId] = useState(null);

    const [shareDialogOpen, setShareDialogOpen] = useState(false);
    const [addAssetsDialogOpen, setAddAssetsDialogOpen] = useState(false);


    // AI Insights State
    const [aiDialogOpen, setAiDialogOpen] = useState(false);
    const [aiInsights, setAiInsights] = useState(null);
    const [analyzing, setAnalyzing] = useState(false);

    const [mapDialogOpen, setMapDialogOpen] = useState(false);

    // Governance & Usage Violations banner starts collapsed to save vertical
    // space; users expand it on demand to see the full violation list.
    const [violationsExpanded, setViolationsExpanded] = useState(false);

    const fetchCollectionDetail = useCallback(async () => {
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
    }, [slug, notify, onBack, temporalDate]);

    useEffect(() => {
        fetchCollectionDetail();
    }, [fetchCollectionDetail]);

    const handleMenuOpen = (event, asset) => {
        setAnchorEl(event.currentTarget);
        setSelectedAsset(asset);
    };

    const handleMenuClose = () => {
        setAnchorEl(null);
        setSelectedAsset(null);
    };

    const handleNavigateToAsset = () => {
        if (!selectedAsset) return;
        const assetId = selectedAsset.id || selectedAsset.asset_id;
        handleMenuClose();
        navigateTo(`/assets?id=${assetId}`);
    };

    const handleRemoveAsset = async () => {
        if (!selectedAsset) return;
        const assetId = selectedAsset.id || selectedAsset.asset_id;
        handleMenuClose();
        setRemovingAssetId(assetId);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch(`/api/v1/collections/${slug}/assets/${assetId}`, {
                method: 'DELETE',
                headers: { 'X-CSRF-Token': csrfToken },
            });
            if (res.ok) {
                // Optimistic remove from local state
                setCollection(prev => ({
                    ...prev,
                    collection_assets: prev.collection_assets.filter(
                        a => (a.id || a.asset_id) !== assetId
                    ),
                }));
                notify("Asset removed from collection.", "success");
            } else {
                const data = await res.json();
                notify(data.error || "Failed to remove asset.", "error");
            }
        } catch {
            notify("Network error removing asset.", "error");
        } finally {
            setRemovingAssetId(null);
        }
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
            match_mode: collection.collection_rule?.match_mode || 'semantic',
            semantic_prompt: collection.collection_rule?.semantic_prompt || '',
            similarity_threshold: parseFloat(collection.collection_rule?.similarity_threshold) || 0.8,
            metadata_filters: collection.collection_rule?.metadata_filters || {}
        });
        setFilterKeyDraft('');
        setFilterValueDraft('');
        setSimulationResults(null); // Reset sandbox on open
        setOpenRuleDialog(true);
    };

    const addMetadataFilter = () => {
        if (!filterKeyDraft.trim()) return;
        const values = filterValueDraft.split(',').map((v) => v.trim()).filter(Boolean);
        setRuleForm((prev) => ({
            ...prev,
            metadata_filters: { ...prev.metadata_filters, [filterKeyDraft.trim()]: values.length > 1 ? values : (values[0] ?? '') }
        }));
        setFilterKeyDraft('');
        setFilterValueDraft('');
    };

    const removeMetadataFilter = (key) => {
        setRuleForm((prev) => {
            const next = { ...prev.metadata_filters };
            delete next[key];
            return { ...prev, metadata_filters: next };
        });
    };

    const usesMetadata = ruleForm.match_mode === 'metadata' || ruleForm.match_mode === 'hybrid';
    const usesSemantic = ruleForm.match_mode === 'semantic' || ruleForm.match_mode === 'hybrid';

    const handleSimulate = async () => {
        if (usesMetadata && Object.keys(ruleForm.metadata_filters || {}).length > 0) {
            const results = await simulateSmartRule({ metadata_filters: ruleForm.metadata_filters });
            setSimulationResults(results || []);
            return;
        }
        if (!ruleForm.semantic_prompt) return;
        setSimulating(true);
        const results = await simulateSmartRule({ semantic_prompt: ruleForm.semantic_prompt, similarity_threshold: ruleForm.similarity_threshold });
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
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2, flexWrap: 'wrap', gap: 1 }}>
                    <Button startIcon={<ArrowBack />} onClick={onBack} sx={{ color: '#64748b', textTransform: 'none' }}>
                        Back to Workspace Board
                    </Button>

                    <Stack direction="row" spacing={2} flexWrap="wrap" useFlexGap>
                        {/* Add Assets to this workspace */}
                        <Button
                            variant="outlined"
                            startIcon={<AddPhotoAlternate />}
                            onClick={() => setAddAssetsDialogOpen(true)}
                            data-testid="collection-add-assets-button"
                            sx={{ borderColor: '#e3e8ef', color: '#5e35b1' }}
                        >
                            {t('collectionDetail.addAssets')}
                        </Button>
                        {/* Generate a public share link */}
                        <Button
                            variant="outlined"
                            startIcon={<Share />}
                            onClick={() => setShareDialogOpen(true)}
                            data-testid="collection-share-button"
                            sx={{ borderColor: '#e3e8ef', color: '#5e35b1' }}
                        >
                            {t('collectionDetail.share')}
                        </Button>
                        {/*  Trigger AI Map */}
                        <Button variant="outlined" startIcon={<AutoFixHigh />} onClick={() => setMapDialogOpen(true)} sx={{ borderColor: '#e3e8ef', color: '#5e35b1' }}>
                            View AI Map
                        </Button>
                        {/* Smart Rule / Upgrade Button */}
                        <Button variant="outlined" startIcon={<SettingsSuggest />} onClick={openConfigurator} sx={{ borderColor: '#e3e8ef', color: '#5e35b1' }}>
                            {isSmart ? 'Configure Rules' : 'Upgrade to Smart Collection'}
                        </Button>

                        {/* Trigger AI Insights */}
                        <Button variant="outlined" startIcon={<AutoAwesome />} onClick={runAiAnalysis} sx={{ borderColor: '#e3e8ef', color: '#5e35b1' }}>
                            Ask AI about this Collection
                        </Button>
                    </Stack>
                </Box>

                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 2 }}>
                    <Box>
                        <Stack direction="row" spacing={2} sx={{
  mb: 1,
  alignItems: "center"
}}>
                            <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                                {collection.name}
                            </Typography>
                        </Stack>
                        <Typography variant="body1" color="textSecondary" sx={{ maxWidth: 800 }}>
                            {collection.description}
                        </Typography>
                    </Box>

                    <Box sx={{ textAlign: 'right' }}>
                        {isSmart && (
                            <Chip icon={<AutoAwesome fontSize="small" />} label="AI Smart Collection" size="small" sx={{ bgcolor: '#f3e5f5', color: '#8e24aa', fontWeight: 600, mb: isSmart && collection.collection_rule ? 1 : 0 }} />
                        )}
                        {isSmart && collection.collection_rule && (
                            <Box sx={{ p: 1.5, bgcolor: '#f8fafc', borderRadius: 2, border: '1px dashed #cbd5e1', display: 'inline-block', textAlign: 'left' }}>
                                <Typography variant="caption" sx={{ fontWeight: 700, color: '#475569', display: 'block' }}>
                                    Active Routing Rule ({collection.collection_rule.match_mode || 'semantic'}):
                                </Typography>
                                {(collection.collection_rule.match_mode !== 'metadata') && collection.collection_rule.semantic_prompt && (
                                    <Typography variant="body2" sx={{ color: '#0f172a', fontStyle: 'italic' }}>
                                        "{collection.collection_rule.semantic_prompt}" (Threshold: {collection.collection_rule.similarity_threshold})
                                    </Typography>
                                )}
                                {(collection.collection_rule.match_mode === 'metadata' || collection.collection_rule.match_mode === 'hybrid') && collection.collection_rule.metadata_filters && Object.keys(collection.collection_rule.metadata_filters).length > 0 && (
                                    <Typography variant="body2" sx={{ color: '#0f172a' }}>
                                        {Object.entries(collection.collection_rule.metadata_filters).map(([k, v]) => `${k}: ${Array.isArray(v) ? v.join(' or ') : v}`).join(', ')}
                                    </Typography>
                                )}
                            </Box>
                        )}
                    </Box>
                </Box>
            </Paper>

            {/*  Automated TDM Compliance Sweep Display */}
            {collection.compliance_violations && collection.compliance_violations.length > 0 && (
                <Paper elevation={0} sx={{ p: 2, mb: 4, borderRadius: 2, bgcolor: '#fef2f2', border: '1px solid #fca5a5' }}>
                    <Box sx={{ display: 'flex', alignItems: 'flex-start' }}>
                        <Shield sx={{ color: '#ef4444', mr: 2, mt: 0.5 }} />
                        <Box sx={{ flex: 1 }}>
                            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                                <Typography variant="subtitle2" sx={{ color: '#b91c1c', fontWeight: 700 }}>
                                    Governance & Usage Violations Detected ({collection.compliance_violations.length})
                                </Typography>
                                <IconButton
                                    size="small"
                                    onClick={() => setViolationsExpanded((prev) => !prev)}
                                    data-testid="collection-violations-toggle"
                                    aria-label={violationsExpanded ? 'Collapse violations' : 'Expand violations'}
                                    sx={{ color: '#b91c1c' }}
                                >
                                    {violationsExpanded ? <ExpandLess /> : <ExpandMore />}
                                </IconButton>
                            </Box>
                            <Collapse in={violationsExpanded} unmountOnExit>
                                <Typography variant="body2" sx={{ color: '#991b1b', mb: 1, mt: 0.5 }}>
                                    The following assets conflict with this workspace's legal or temporal boundaries. Resolve these before exporting to downstream CMS systems.
                                </Typography>
                                <ul style={{ margin: 0, paddingLeft: '20px', color: '#991b1b', fontSize: '0.875rem' }}>
                                    {collection.compliance_violations.map((violation, idx) => (
                                        <li key={idx} style={{ marginBottom: '4px' }}>
                                            <strong>{violation.title}:</strong> {violation.reason}
                                        </li>
                                    ))}
                                </ul>
                            </Collapse>
                        </Box>
                    </Box>
                </Paper>
            )}

            <Typography variant="h6" sx={{ fontWeight: 600, mb: 3 }}>Curated Assets ({assets.length})</Typography>

            {assets.length === 0 ? (
                <Paper elevation={0} sx={{ p: 6, textAlign: 'center', borderRadius: 3, border: '1px dashed #cbd5e1', bgcolor: '#f8fafc' }}>
                    <ImageIcon sx={{ fontSize: 48, color: '#cbd5e1', mb: 2 }} />
                    <Typography variant="h6" color="textSecondary">This collection is empty</Typography>
                    <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>Navigate to the Asset Explorer to add files, or define a Smart Rule to auto-populate.</Typography>
                    <Button
                        variant="contained"
                        startIcon={<AddPhotoAlternate />}
                        onClick={() => setAddAssetsDialogOpen(true)}
                        data-testid="collection-add-assets-empty-cta"
                        sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                    >
                        {t('collectionDetail.addAssets')}
                    </Button>
                </Paper>
            ) : (
                <Grid container spacing={3}>
                    {assets.map((asset) => {
                        const assetData = asset.asset || asset;
                        const assetId = assetData.id || asset.asset_id;
                        const thumbnail = assetData.url || assetData.thumbnail_url;
                        const isRemoving = removingAssetId === assetId;
                        return (
                        <Grid size={{ xs: 12, sm: 6, md: 4, lg: 3 }} key={asset.id || assetId}>
                            <Card elevation={0} sx={{
                                border: '1px solid',
                                borderColor: asset.pinned ? '#5e35b1' : '#e3e8ef',
                                borderRadius: 2,
                                position: 'relative',
                                opacity: isRemoving ? 0.5 : 1,
                                transition: 'opacity 0.2s',
                            }}>
                                {asset.pinned && (
                                    <Box sx={{ position: 'absolute', top: 8, right: 8, bgcolor: '#fff', borderRadius: '50%', p: 0.5, boxShadow: 1, zIndex: 1 }}>
                                        <PushPin sx={{ fontSize: 16, color: '#5e35b1' }} />
                                    </Box>
                                )}
                                <Box
                                    sx={{
                                        height: 160,
                                        bgcolor: '#f1f5f9',
                                        display: 'flex',
                                        alignItems: 'center',
                                        justifyContent: 'center',
                                        borderBottom: '1px solid #e3e8ef',
                                        overflow: 'hidden',
                                        cursor: 'pointer',
                                    }}
                                    onClick={() => navigateTo(`/assets?id=${assetId}`)}
                                >
                                    {thumbnail ? (
                                        <Box
                                            component="img"
                                            src={thumbnail}
                                            alt={assetData.title || assetData.original_filename || 'Asset'}
                                            sx={{ width: '100%', height: '100%', objectFit: 'cover' }}
                                        />
                                    ) : (
                                        <ImageIcon sx={{ fontSize: 40, color: '#cbd5e1' }} />
                                    )}
                                </Box>
                                <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
                                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                                        <Box sx={{ overflow: 'hidden', flex: 1 }}>
                                            <Typography
                                                variant="subtitle2"
                                                sx={{ fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', cursor: 'pointer', '&:hover': { color: '#5e35b1' } }}
                                                onClick={() => navigateTo(`/assets?id=${assetId}`)}
                                            >
                                                {assetData.original_filename || assetData.title || 'Unknown File'}
                                            </Typography>
                                            <Typography variant="caption" color="textSecondary">
                                                {assetData.file_size || assetData.size || ''}
                                            </Typography>
                                        </Box>
                                        <IconButton size="small" onClick={(e) => handleMenuOpen(e, { ...assetData, id: assetId, pinned: asset.pinned })} sx={{ ml: 1, mt: -0.5, mr: -0.5 }}>
                                            <MoreVert fontSize="small" />
                                        </IconButton>
                                    </Box>
                                </CardContent>
                            </Card>
                        </Grid>
                        );
                    })}
                </Grid>
            )}

            {/* Asset Actions Menu */}
            <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={handleMenuClose} elevation={2} slotProps={{paper: { sx: { borderRadius: 2, minWidth: 180 } } }}>
                <MenuItem onClick={handleNavigateToAsset}>
                    <LaunchOutlined fontSize="small" sx={{ mr: 1.5, color: '#3b82f6' }} /> View Asset
                </MenuItem>
                <MenuItem onClick={handleMenuClose}>
                    <CloudDownload fontSize="small" sx={{ mr: 1.5, color: '#64748b' }} /> Download
                </MenuItem>
                <Divider />
                <MenuItem onClick={handleRemoveAsset} sx={{ color: '#d32f2f' }}>
                    <DeleteOutlined fontSize="small" sx={{ mr: 1.5 }} /> Remove from Collection
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
                        <Grid size={{ xs: 12, md: 5 }} sx={{ p: 3, borderRight: { md: '1px solid #e2e8f0' }, bgcolor: '#f8fafc' }}>
                            <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 1 }}>Match Mode</Typography>
                            <ToggleButtonGroup
                                exclusive
                                fullWidth
                                size="small"
                                value={ruleForm.match_mode}
                                onChange={(e, val) => val && setRuleForm({ ...ruleForm, match_mode: val })}
                                sx={{ mb: 3, bgcolor: '#fff' }}
                            >
                                <ToggleButton value="semantic">Semantic (AI)</ToggleButton>
                                <ToggleButton value="metadata">Metadata / Tags</ToggleButton>
                                <ToggleButton value="hybrid">Hybrid</ToggleButton>
                            </ToggleButtonGroup>

                            {usesSemantic && (
                                <>
                                    <Typography variant="body2" color="textSecondary" sx={{ mb: 2 }}>
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
                                </>
                            )}

                            {usesMetadata && (
                                <Box sx={{ mt: usesSemantic ? 4 : 0 }}>
                                    <Typography variant="body2" color="textSecondary" sx={{ mb: 2 }}>
                                        Route assets whose properties/tags match these filters — no AI involved, applies instantly.
                                        Array values (e.g. multiple tags) match "any of" the listed options.
                                    </Typography>

                                    <Stack direction="row" spacing={1} sx={{ mb: 2 }}>
                                        <TextField
                                            label="Property key" placeholder="tags"
                                            value={filterKeyDraft}
                                            onChange={(e) => setFilterKeyDraft(e.target.value)}
                                            sx={{ bgcolor: '#fff', flex: 1 }}
                                        />
                                        <TextField
                                            label="Value(s), comma separated" placeholder="Q3 Campaign, Social Media"
                                            value={filterValueDraft}
                                            onChange={(e) => setFilterValueDraft(e.target.value)}
                                            sx={{ bgcolor: '#fff', flex: 1 }}
                                        />
                                        <Button variant="outlined" onClick={addMetadataFilter} disabled={!filterKeyDraft.trim()}>
                                            Add
                                        </Button>
                                    </Stack>

                                    <Stack direction="row" flexWrap="wrap" gap={1}>
                                        {Object.entries(ruleForm.metadata_filters || {}).map(([key, value]) => (
                                            <Chip
                                                key={key}
                                                label={`${key}: ${Array.isArray(value) ? value.join(' or ') : value}`}
                                                onDelete={() => removeMetadataFilter(key)}
                                                sx={{ bgcolor: '#f3e5f5', color: '#8e24aa' }}
                                            />
                                        ))}
                                    </Stack>
                                </Box>
                            )}

                            <Button
                                fullWidth
                                variant="outlined"
                                startIcon={simulating ? <CircularProgress size={16} /> : <PlayArrow />}
                                onClick={handleSimulate}
                                disabled={(usesSemantic && !ruleForm.semantic_prompt && !usesMetadata) || (usesMetadata && !usesSemantic && Object.keys(ruleForm.metadata_filters || {}).length === 0) || simulating}
                                sx={{ mt: 4, borderColor: '#5e35b1', color: '#5e35b1', bgcolor: '#fff' }}
                            >
                                {simulating ? 'Vectorizing...' : 'Run Dry-Run Simulation'}
                            </Button>
                        </Grid>

                        {/* RIGHT COLUMN: The Sandbox Results */}
                        <Grid size={{ xs: 12, md: 7 }} sx={{ p: 3, display: 'flex', flexDirection: 'column' }}>
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

            <ShareCollectionDialog
                open={shareDialogOpen}
                onClose={() => setShareDialogOpen(false)}
                slug={slug}
            />

            <AddAssetsToCollectionDialog
                open={addAssetsDialogOpen}
                onClose={() => setAddAssetsDialogOpen(false)}
                slug={slug}
                onAssetsAdded={() => fetchCollectionDetail()}
            />
        </Box>
    );
}
