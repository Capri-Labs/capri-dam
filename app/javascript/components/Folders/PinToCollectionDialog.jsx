import React, { useState, useEffect } from 'react';
import {
  Dialog, DialogTitle, DialogContent, DialogActions,
  Button, List, ListItem, ListItemButton, ListItemIcon, ListItemText,
  CircularProgress, Typography, Box, InputBase, Paper, Chip, Stack, Tooltip,
} from '@mui/material';
import { FolderShared, Search, AutoAwesome, CheckCircle, RadioButtonUnchecked } from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

export default function PinToCollectionDialog({ open, onClose, asset }) {
  const notify = useNotify();
  const [collections, setCollections] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [pending, setPending] = useState({}); // collectionSlug → 'pinning' | 'unpinning'

  useEffect(() => {
    if (open && asset) {
      fetchCollections(asset.id);
      setSearchQuery('');
    }
  }, [open, asset]);

  const fetchCollections = async (assetId) => {
    setLoading(true);
    try {
      const res = await fetch(`/api/v1/collections?asset_id=${assetId}`);
      if (res.ok) {
        const data = await res.json();
        setCollections(data);
      }
    } catch {
      notify('Failed to load collections.', 'error');
    } finally {
      setLoading(false);
    }
  };

  const csrfToken = () => document.querySelector('[name="csrf-token"]')?.content || '';

  const handleToggle = async (collection) => {
    if (!asset) return;
    const slug = collection.slug;
    const isPinned = collection.pinned_for_asset;
    setPending((prev) => ({ ...prev, [slug]: isPinned ? 'unpinning' : 'pinning' }));

    try {
      let res;
      if (isPinned) {
        res = await fetch(`/api/v1/collections/${slug}/assets/${asset.id}`, {
          method: 'DELETE',
          headers: { 'X-CSRF-Token': csrfToken() },
        });
      } else {
        res = await fetch(`/api/v1/collections/${slug}/assets`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
          body: JSON.stringify({ asset_id: asset.id }),
        });
      }

      if (res.ok) {
        // Optimistically update local state
        setCollections((prev) =>
          prev.map((c) => c.slug === slug ? { ...c, pinned_for_asset: !isPinned } : c)
        );
        notify(isPinned ? 'Removed from collection.' : 'Added to collection.', 'success');
      } else {
        const data = await res.json().catch(() => ({}));
        notify(data.error || data.errors?.join(', ') || 'Operation failed.', 'error');
      }
    } catch {
      notify('Network error.', 'error');
    } finally {
      setPending((prev) => { const next = { ...prev }; delete next[slug]; return next; });
    }
  };

  const pinnedCollections = collections.filter((c) => c.pinned_for_asset);
  const filteredCollections = collections.filter((c) =>
    c.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  if (!open) return null;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle sx={{ fontWeight: 700, pb: 1 }}>
        Pin to Collections
      </DialogTitle>

      <DialogContent sx={{ p: 0 }}>
        <Box sx={{ px: 3, pb: 2 }}>
          <Typography variant="body2" color="textSecondary" sx={{ mb: 1.5 }}>
            Add <strong>{asset?.name || asset?.title || 'this asset'}</strong> to one or more collections.
          </Typography>

          {/* Currently pinned summary */}
          {pinnedCollections.length > 0 && (
            <Stack direction="row" spacing={0.75} sx={{mb: 1.5, gap: 0.75, flexWrap: 'wrap'}}>
              {pinnedCollections.map((c) => (
                <Chip
                  key={c.slug}
                  label={c.name}
                  size="small"
                  onDelete={() => handleToggle(c)}
                  color="primary"
                  variant="outlined"
                  sx={{ fontWeight: 600 }}
                />
              ))}
            </Stack>
          )}

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

        <List sx={{ pt: 0, maxHeight: 320, overflow: 'auto', borderTop: '1px solid #f1f5f9' }}>
          {loading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
              <CircularProgress size={24} sx={{ color: '#5e35b1' }} />
            </Box>
          ) : filteredCollections.length === 0 ? (
            <Box sx={{ textAlign: 'center', py: 3 }}>
              <Typography variant="body2" color="textSecondary">No collections match your search.</Typography>
            </Box>
          ) : (
            filteredCollections.map((collection) => {
              const isPinned = collection.pinned_for_asset;
              const isLoading = Boolean(pending[collection.slug]);
              return (
                <ListItem key={collection.id} disablePadding>
                  <ListItemButton
                    onClick={() => !isLoading && handleToggle(collection)}
                    selected={isPinned}
                    sx={{
                      '&.Mui-selected': { bgcolor: '#eef2ff' },
                      opacity: isLoading ? 0.6 : 1,
                    }}
                  >
                    <ListItemIcon sx={{ minWidth: 40 }}>
                      {collection.collection_type === 'smart' ? (
                        <AutoAwesome fontSize="small" sx={{ color: '#8e24aa' }} />
                      ) : (
                        <FolderShared fontSize="small" sx={{ color: '#1976d2' }} />
                      )}
                    </ListItemIcon>
                    <ListItemText
                      primary={collection.name}
                      secondary={
                        <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                          <span>{collection.collection_type === 'smart' ? 'AI Smart Routing' : 'Manual Curation'}</span>
                          {typeof collection.assets_count === 'number' && (
                            <Chip label={`${collection.assets_count} assets`} size="small" sx={{ height: 16, fontSize: '0.65rem' }} />
                          )}
                        </Stack>
                      }
                      slotProps={{ primary: { variant: 'subtitle2', fontWeight: 600 }, secondary: { component: 'div' } }}
                    />
                    <Tooltip title={isPinned ? 'Remove from this collection' : 'Add to this collection'}>
                      {isLoading ? (
                        <CircularProgress size={18} sx={{ ml: 1 }} />
                      ) : isPinned ? (
                        <CheckCircle sx={{ color: '#4f46e5', fontSize: 22 }} />
                      ) : (
                        <RadioButtonUnchecked sx={{ color: '#cbd5e1', fontSize: 22 }} />
                      )}
                    </Tooltip>
                  </ListItemButton>
                </ListItem>
              );
            })
          )}
        </List>
      </DialogContent>

      <DialogActions sx={{ p: 2, borderTop: '1px solid #f1f5f9', justifyContent: 'space-between' }}>
        <Typography variant="caption" sx={{ color: '#94a3b8' }}>
          {pinnedCollections.length > 0
            ? `Pinned to ${pinnedCollections.length} collection${pinnedCollections.length > 1 ? 's' : ''}`
            : 'Not pinned to any collection'}
        </Typography>
        <Button onClick={onClose} variant="contained" disableElevation sx={{ textTransform: 'none', borderRadius: 2 }}>
          Done
        </Button>
      </DialogActions>
    </Dialog>
  );
}
