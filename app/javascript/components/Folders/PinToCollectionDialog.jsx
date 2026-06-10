import React, { useState, useEffect } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Button, List, ListItem, ListItemButton, ListItemIcon, ListItemText,
    CircularProgress, Typography, Box, InputBase, Paper
} from '@mui/material';
import { FolderShared, Search, AutoAwesome } from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

export default function PinToCollectionDialog({ open, onClose, asset }) {
    const notify = useNotify();
    const [collections, setCollections] = useState([]);
    const [loading, setLoading] = useState(true);
    const [searchQuery, setSearchQuery] = useState('');

    useEffect(() => {
        if (open) {
            fetchActiveCollections();
        }
    }, [open]);

    const fetchActiveCollections = async () => {
        setLoading(true);
        try {
            // Note: Update this to match your actual collections endpoint if different
            const res = await fetch('/api/v1/collections');
            if (res.ok) {
                const data = await res.json();
                setCollections(data);
            }
        } catch (error) {
            notify("Failed to load collections.", "error");
        } finally {
            setLoading(false);
        }
    };

    const handlePinToCollection = async (slug) => {
        if (!asset) return;

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/collections/${slug}/assets`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ asset_id: asset.id })
            });

            const data = await res.json();

            if (res.ok) {
                notify("Asset pinned to collection successfully.", "success");
                onClose();
            } else {
                notify(data.errors?.join(", ") || data.error || "Failed to pin asset.", "error");
            }
        } catch (error) {
            notify("Network error occurred.", "error");
        }
    };

    const filteredCollections = collections.filter(c =>
        c.name.toLowerCase().includes(searchQuery.toLowerCase())
    );

    if (!open) return null;

    return (
        <Dialog open={open} onClose={onClose} maxWidth="xs" fullWidth>
            <DialogTitle sx={{ fontWeight: 700, pb: 1 }}>
                Pin to Workspace
            </DialogTitle>

            <DialogContent sx={{ p: 0 }}>
                <Box sx={{ px: 3, pb: 2 }}>
                    <Typography variant="body2" color="textSecondary" sx={{ mb: 2 }}>
                        Select a campaign or workspace to add <strong>{asset?.name || asset?.title || 'this asset'}</strong>.
                    </Typography>

                    <Paper elevation={0} sx={{ display: 'flex', alignItems: 'center', px: 2, border: '1px solid #e2e8f0', borderRadius: 2 }}>
                        <Search sx={{ color: '#94a3b8', mr: 1 }} fontSize="small" />
                        <InputBase
                            fullWidth
                            placeholder="Search collections..."
                            value={searchQuery}
                            onChange={(e) => setSearchQuery(e.target.value)}
                            sx={{ py: 1, fontSize: '0.875rem' }}
                        />
                    </Paper>
                </Box>

                <List sx={{ pt: 0, maxHeight: 300, overflow: 'auto', borderTop: '1px solid #f1f5f9' }}>
                    {loading ? (
                        <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                            <CircularProgress size={24} sx={{ color: '#5e35b1' }} />
                        </Box>
                    ) : filteredCollections.length === 0 ? (
                        <Box sx={{ textAlign: 'center', py: 3 }}>
                            <Typography variant="body2" color="textSecondary">No collections match your search.</Typography>
                        </Box>
                    ) : (
                        filteredCollections.map((collection) => (
                            <ListItem key={collection.id} disablePadding>
                                <ListItemButton onClick={() => handlePinToCollection(collection.slug)}>
                                    <ListItemIcon sx={{ minWidth: 40 }}>
                                        {collection.collection_type === 'smart' ? (
                                            <AutoAwesome fontSize="small" sx={{ color: '#8e24aa' }} />
                                        ) : (
                                            <FolderShared fontSize="small" sx={{ color: '#1976d2' }} />
                                        )}
                                    </ListItemIcon>
                                    <ListItemText
                                        primary={collection.name}
                                        secondary={collection.collection_type === 'smart' ? 'AI Smart Routing' : 'Manual Curation'}
                                        primaryTypographyProps={{ variant: 'subtitle2', fontWeight: 600 }}
                                    />
                                </ListItemButton>
                            </ListItem>
                        ))
                    )}
                </List>
            </DialogContent>

            <DialogActions sx={{ p: 2, borderTop: '1px solid #f1f5f9' }}>
                <Button onClick={onClose} color="inherit" sx={{ textTransform: 'none' }}>Cancel</Button>
            </DialogActions>
        </Dialog>
    );
}