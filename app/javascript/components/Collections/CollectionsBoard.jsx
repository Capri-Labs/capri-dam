import React, { useEffect, useState } from 'react';
import {
    Grid, Card, CardContent, CardActions, Typography, Button,
    Box, Chip, Avatar, Stack, CircularProgress, Checkbox,
    Paper, IconButton, Tooltip, Menu, MenuItem, Divider, ListItemIcon, ListItemText
} from '@mui/material';
import {
    AutoAwesome, FolderShared, TimerOutlined, Image as ImageIcon,
    DeleteOutlined, EditOutlined, AutoFixHigh, HealthAndSafety,
    MoreVert, Close, Analytics, CloudOff, ContentCopy, Public, Lock, Block, MergeType
} from '@mui/icons-material';
import { useCollections } from './CollectionContext';
import { useNotify } from '../../context/NotificationContext';
import CollectionPropertiesDialog from "./CollectionPropertiesDialog";

export default function CollectionsBoard({ onSelectCollection, selectedIds, setSelectedIds }) {
    const notify = useNotify();
    const { collections, loadingCollections, fetchCollections, deleteCollection, bulkDeleteCollections, purgeCdnCache } = useCollections();

    const [propertiesDialogOpen, setPropertiesDialogOpen] = useState(false);
    const [collectionsToEdit, setCollectionsToEdit] = useState([]);

    const [bulkMenuAnchor, setBulkMenuAnchor] = useState(null);
    const [cardMenuAnchor, setCardMenuAnchor] = useState(null);
    const [activeCard, setActiveCard] = useState(null);

    useEffect(() => { fetchCollections(); }, [fetchCollections]);

    const toggleSelection = (id) => {
        setSelectedIds(prev => prev.includes(id) ? prev.filter(item => item !== id) : [...prev, id]);
    };
    const clearSelection = () => setSelectedIds([]);

    const handleBulkDelete = async () => {
        if (window.confirm(`Are you sure you want to archive ${selectedIds.length} workspaces?`)) {
            const success = await bulkDeleteCollections(selectedIds);
            if (success) clearSelection();
        }
    };

    const handleBulkCopyLinks = () => {
        const selectedSlugs = collections.filter(c => selectedIds.includes(c.id)).map(c => `${window.location.origin}/collections/${c.slug}`);
        navigator.clipboard.writeText(selectedSlugs.join('\n'));
        notify(`Copied ${selectedSlugs.length} workspace links to clipboard.`, 'success');
        setBulkMenuAnchor(null);
    };

    const handleSingleCopyLink = () => {
        if (activeCard) {
            navigator.clipboard.writeText(`${window.location.origin}/collections/${activeCard.slug}`);
            notify("Workspace link copied to clipboard.", "success");
        }
        closeCardMenu();
    };

    const openCardMenu = (event, collection) => {
        event.stopPropagation();
        setCardMenuAnchor(event.currentTarget);
        setActiveCard(collection);
    };

    const closeCardMenu = () => {
        setCardMenuAnchor(null);
        setActiveCard(null);
    };

    const handleSingleDelete = async () => {
        if (activeCard && window.confirm(`Archive "${activeCard.name}"?`)) {
            await deleteCollection(activeCard.slug);
        }
        closeCardMenu();
    };

    const handleCdnPurge = async () => {
        if (activeCard) await purgeCdnCache(activeCard.slug);
        closeCardMenu();
    };

    if (loadingCollections) {
        return <Box sx={{ display: 'flex', justifyContent: 'center', py: 8 }}><CircularProgress sx={{ color: '#5e35b1' }} /></Box>;
    }

    if (!collections || collections.length === 0) {
        return (
            <Box sx={{ textAlign: 'center', py: 10, bgcolor: '#fff', borderRadius: 3, border: '1px dashed #e3e8ef' }}>
                <FolderShared sx={{ fontSize: 60, color: '#cbd5e1', mb: 2 }} />
                <Typography variant="h6" color="textSecondary">No collections found</Typography>
                <Typography variant="body2" color="textSecondary">Create your first campaign workspace to start curating assets.</Typography>
            </Box>
        );
    }

    return (
        <Box>
            {/* Contextual Bulk Action Toolbar */}
            {selectedIds.length > 0 && (
                <Paper
                    elevation={3}
                    sx={{
                        p: 1.5, px: 3, mb: 3, borderRadius: 2,
                        bgcolor: '#1e293b', color: '#fff',
                        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                        position: 'sticky', top: 16, zIndex: 10
                    }}
                >
                    <Stack direction="row" alignItems="center" spacing={2}>
                        <IconButton size="small" onClick={clearSelection} sx={{ color: '#94a3b8' }}>
                            <Close fontSize="small" />
                        </IconButton>
                        <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>
                            {selectedIds.length} workspaces selected
                        </Typography>
                    </Stack>

                    <Stack direction="row" spacing={1}>
                        <Tooltip title="Bulk Edit Properties">
                            <IconButton sx={{ color: '#e2e8f0' }} onClick={() => {
                                setCollectionsToEdit(collections.filter(c => selectedIds.includes(c.id)));
                                setPropertiesDialogOpen(true);
                            }}>
                                <EditOutlined />
                            </IconButton>
                        </Tooltip>

                        <Tooltip title="Copy Shared Links">
                            <IconButton sx={{ color: '#e2e8f0' }} onClick={handleBulkCopyLinks}>
                                <ContentCopy />
                            </IconButton>
                        </Tooltip>

                        <Tooltip title="AI & Advanced Operations">
                            <Button
                                variant="outlined"
                                startIcon={<AutoFixHigh />}
                                onClick={(e) => setBulkMenuAnchor(e.currentTarget)}
                                sx={{ color: '#e2e8f0', borderColor: '#475569', textTransform: 'none', ml: 1 }}
                            >
                                Action Menu
                            </Button>
                        </Tooltip>

                        <Tooltip title="Archive Selected">
                            <IconButton onClick={handleBulkDelete} sx={{ color: '#fca5a5', ml: 1 }}><DeleteOutlined /></IconButton>
                        </Tooltip>
                    </Stack>
                </Paper>
            )}

            {/* Individual Card Context Menu */}
            <Menu anchorEl={cardMenuAnchor} open={Boolean(cardMenuAnchor)} onClose={closeCardMenu} PaperProps={{ sx: { mt: 1, minWidth: 220, borderRadius: 2, border: '1px solid #e3e8ef' } }}>
                <MenuItem onClick={handleSingleCopyLink}>
                    <ListItemIcon><ContentCopy fontSize="small" sx={{ color: '#475569' }}/></ListItemIcon>
                    <ListItemText>Copy Workspace Link</ListItemText>
                </MenuItem>
                <MenuItem onClick={() => {
                    setCollectionsToEdit([activeCard]);
                    setPropertiesDialogOpen(true);
                    closeCardMenu();
                }}>
                    <ListItemIcon><EditOutlined fontSize="small" sx={{ color: '#475569' }}/></ListItemIcon>
                    <ListItemText>Edit Properties & Access</ListItemText>
                </MenuItem>
                <MenuItem onClick={handleCdnPurge}>
                    <ListItemIcon><CloudOff fontSize="small" sx={{ color: '#f59e0b' }}/></ListItemIcon>
                    <ListItemText>Purge CDN Edge Cache</ListItemText>
                </MenuItem>

                <Divider />
                <Typography variant="overline" sx={{ px: 2, color: '#94a3b8', lineHeight: 2.5 }}>AI Engine Tools</Typography>

                <MenuItem onClick={closeCardMenu}>
                    <ListItemIcon><Analytics fontSize="small" sx={{ color: '#8e24aa' }}/></ListItemIcon>
                    <ListItemText>TDM Compliance Scan</ListItemText>
                </MenuItem>
                <MenuItem onClick={closeCardMenu}>
                    <ListItemIcon><AutoFixHigh fontSize="small" sx={{ color: '#0ea5e9' }}/></ListItemIcon>
                    <ListItemText>
                        {activeCard?.collection_type === 'smart' ? 'Tune Semantic Prompt' : 'Generate Smart Rule'}
                    </ListItemText>
                </MenuItem>

                <Divider />

                <MenuItem onClick={handleSingleDelete} sx={{ color: '#d32f2f' }}>
                    <ListItemIcon><DeleteOutlined fontSize="small" sx={{ color: '#d32f2f' }}/></ListItemIcon>
                    <ListItemText>Archive Workspace</ListItemText>
                </MenuItem>
            </Menu>

            {/* Advanced Bulk Menu */}
            <Menu anchorEl={bulkMenuAnchor} open={Boolean(bulkMenuAnchor)} onClose={() => setBulkMenuAnchor(null)} PaperProps={{ sx: { mt: 1, minWidth: 260, borderRadius: 2 } }}>
                <MenuItem onClick={() => setBulkMenuAnchor(null)}>
                    <MergeType fontSize="small" sx={{ mr: 1.5, color: '#0ea5e9' }} />
                    Merge to New AI Workspace
                </MenuItem>
                <MenuItem onClick={() => setBulkMenuAnchor(null)}>
                    <HealthAndSafety fontSize="small" sx={{ mr: 1.5, color: '#059669' }} />
                    Run Bulk TDM Health Scan
                </MenuItem>
                <MenuItem onClick={() => setBulkMenuAnchor(null)}>
                    <Lock fontSize="small" sx={{ mr: 1.5, color: '#f59e0b' }} />
                    Apply Legal Hold (Freeze)
                </MenuItem>
                <Divider />
                <MenuItem onClick={() => setBulkMenuAnchor(null)}>
                    <TimerOutlined fontSize="small" sx={{ mr: 1.5, color: '#475569' }} />
                    Enforce 30-Day Expiration
                </MenuItem>
            </Menu>

            {/* Grid Rendering */}
            <Grid container spacing={3}>
                {collections.map((collection) => {
                    const props = collection.properties || {};
                    const isSmart = collection.collection_type === 'smart';
                    const assetCount = collection.assets_count || 0;
                    const isSelected = selectedIds.includes(collection.id);

                    // Determine Data Governance Status for Icons
                    const isRestricted = Array.isArray(props.denied_groups) && props.denied_groups.length > 0;
                    const isPrivate = Array.isArray(props.allowed_groups) && props.allowed_groups.length > 0;

                    return (
                        <Grid size={{ xs: 12, sm: 6, md: 4, lg: 3 }} key={collection.id}>
                            <Card
                                elevation={0}
                                sx={{
                                    height: '100%', display: 'flex', flexDirection: 'column',
                                    border: '1px solid', borderColor: isSelected ? '#5e35b1' : '#e3e8ef',
                                    borderRadius: 3, bgcolor: isSelected ? '#f8fafc' : '#fff', position: 'relative',
                                    transition: 'transform 0.2s, box-shadow 0.2s',
                                    '&:hover': { boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.1)', borderColor: isSelected ? '#5e35b1' : '#94a3b8' }
                                }}
                            >
                                <Box sx={{ position: 'absolute', top: 8, right: 8, zIndex: 2 }}>
                                    <Checkbox
                                        checked={isSelected}
                                        onChange={() => toggleSelection(collection.id)}
                                        sx={{ color: '#cbd5e1', '&.Mui-checked': { color: '#5e35b1' }, bgcolor: 'rgba(255,255,255,0.8)', borderRadius: 1, p: 0.5 }}
                                    />
                                </Box>

                                <CardContent sx={{ flexGrow: 1, p: 3, pt: 4 }}>
                                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 2 }}>
                                        <Avatar sx={{ bgcolor: isSmart ? '#f3e5f5' : '#e3f2fd', color: isSmart ? '#8e24aa' : '#1976d2' }}>
                                            {isSmart ? <AutoAwesome fontSize="small" /> : <FolderShared fontSize="small" />}
                                        </Avatar>

                                        <Stack direction="row" spacing={1} sx={{ mr: 4 }}>
                                            {/* Data Governance Icons */}
                                            {isRestricted ? (
                                                <Tooltip title="Restricted Access (Blacklisted Groups)">
                                                    <Block fontSize="small" sx={{ color: '#ef4444' }} />
                                                </Tooltip>
                                            ) : isPrivate ? (
                                                <Tooltip title="Private Workspace (Whitelisted Only)">
                                                    <Lock fontSize="small" sx={{ color: '#f59e0b' }} />
                                                </Tooltip>
                                            ) : (
                                                <Tooltip title="Public Access">
                                                    <Public fontSize="small" sx={{ color: '#94a3b8' }} />
                                                </Tooltip>
                                            )}

                                            {collection.expires_at && (
                                                <Tooltip title="TTL Expiration Active">
                                                    <TimerOutlined fontSize="small" sx={{ color: '#b91c1c' }} />
                                                </Tooltip>
                                            )}
                                        </Stack>
                                    </Box>

                                    <Typography variant="h6" sx={{ fontWeight: 600, mb: 1, lineHeight: 1.2 }}>
                                        {collection.name}
                                    </Typography>

                                    <Typography variant="body2" color="textSecondary" sx={{ mb: 3, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
                                        {collection.description || 'No description provided.'}
                                    </Typography>

                                    <Stack direction="row" alignItems="center" spacing={1}>
                                        <ImageIcon sx={{ color: '#94a3b8', fontSize: '1.2rem' }} />
                                        <Typography variant="caption" sx={{ fontWeight: 600, color: '#475569' }}>
                                            {assetCount} Assets
                                        </Typography>
                                    </Stack>
                                </CardContent>

                                <CardActions sx={{ p: 2, borderTop: '1px solid', borderColor: isSelected ? '#e2e8f0' : '#f1f5f9', mt: 'auto' }}>
                                    <Button size="small" sx={{ color: '#5e35b1', fontWeight: 600 }} onClick={() => onSelectCollection(collection.slug)}>
                                        Open Workspace
                                    </Button>

                                    <IconButton size="small" sx={{ ml: 'auto' }} onClick={(e) => openCardMenu(e, collection)}>
                                        <MoreVert fontSize="small" />
                                    </IconButton>
                                </CardActions>
                            </Card>
                        </Grid>
                    );
                })}
            </Grid>

            <CollectionPropertiesDialog
                open={propertiesDialogOpen}
                onClose={() => {
                    setPropertiesDialogOpen(false);
                    if (collectionsToEdit.length > 1) clearSelection();
                }}
                selectedCollections={collectionsToEdit}
            />
        </Box>
    );
}