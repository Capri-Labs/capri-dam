import React, { useState, useCallback, useEffect } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions, Button, Tabs, Tab,
    Box, Typography, TextField, InputAdornment, CircularProgress,
    List, ListItem, ListItemAvatar, ListItemText, Avatar, Checkbox, Chip
} from '@mui/material';
import { AddPhotoAlternate, Search, CloudUpload, Image as ImageIcon } from '@mui/icons-material';
import { useDropzone } from 'react-dropzone';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';
import { useCollections } from './CollectionContext';

/**
 * Lets a user add assets to a collection either by (a) searching the
 * existing library via the lightweight `/api/v1/search/suggestions`
 * endpoint, or (b) drag-dropping new files, which are uploaded via the
 * standard `POST /api/v1/assets` pipeline and then attached to the
 * collection. Mirrors {PinToCollectionDialog}'s search pattern and
 * {UploadWorkspace}'s dropzone pattern.
 */
export default function AddAssetsToCollectionDialog({ open, onClose, slug, onAssetsAdded }) {
    const { t } = useTranslation();
    const notify = useNotify();
    const { addAssetToCollection } = useCollections();

    const [tab, setTab] = useState(0);
    const [query, setQuery] = useState('');
    const [searching, setSearching] = useState(false);
    const [results, setResults] = useState([]);
    const [addingIds, setAddingIds] = useState([]);
    const [addedIds, setAddedIds] = useState([]);

    const [uploadFiles, setUploadFiles] = useState([]);
    const [uploading, setUploading] = useState(false);

    useEffect(() => {
        if (!open) {
            setTab(0);
            setQuery('');
            setResults([]);
            setAddedIds([]);
            setUploadFiles([]);
        }
    }, [open]);

    useEffect(() => {
        if (!query.trim()) {
            setResults([]);
            return;
        }
        let cancelled = false;
        setSearching(true);
        const handle = setTimeout(async () => {
            try {
                const res = await fetch(`/api/v1/search/suggestions?q=${encodeURIComponent(query)}`);
                const data = await res.json();
                if (!cancelled) {
                    setResults((data.results || []).filter(r => r.type === 'asset'));
                }
            } catch {
                if (!cancelled) notify(t('addAssetsDialog.searchError'), 'error');
            } finally {
                if (!cancelled) setSearching(false);
            }
        }, 300);
        return () => { cancelled = true; clearTimeout(handle); };
        // `notify`/`t` are intentionally excluded — both are re-created on every
        // render by their respective hooks, which previously caused this debounced
        // search effect to re-fire every render (an infinite update loop under
        // React's fake-timer test environment). Only `query` should retrigger it.
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [query]);

    const handleAddAsset = async (assetId) => {
        setAddingIds(prev => [...prev, assetId]);
        const collection = await addAssetToCollection(slug, assetId);
        setAddingIds(prev => prev.filter(id => id !== assetId));
        if (collection) {
            setAddedIds(prev => [...prev, assetId]);
            notify(t('addAssetsDialog.assetAdded'), 'success');
            if (onAssetsAdded) onAssetsAdded(collection);
        }
    };

    const onDrop = useCallback((acceptedFiles) => {
        setUploadFiles(prev => [
            ...prev,
            ...acceptedFiles.map(file => ({ file, id: `${file.name}-${file.size}-${Date.now()}`, status: 'pending' })),
        ]);
    }, []);

    const { getRootProps, getInputProps, isDragActive } = useDropzone({ onDrop, accept: { 'image/*': [] } });

    const handleUploadAndAttach = async () => {
        setUploading(true);
        const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
        let anySucceeded = false;

        for (const item of uploadFiles.filter(f => f.status === 'pending')) {
            setUploadFiles(prev => prev.map(f => f.id === item.id ? { ...f, status: 'uploading' } : f));
            try {
                const formData = new FormData();
                formData.append('file', item.file);
                formData.append('title', item.file.name);

                const createRes = await fetch('/api/v1/assets', {
                    method: 'POST',
                    headers: { 'X-CSRF-Token': csrfToken },
                    body: formData,
                });
                const created = await createRes.json();

                if (createRes.ok && created?.id) {
                    const collection = await addAssetToCollection(slug, created.id);
                    if (collection) {
                        anySucceeded = true;
                        setUploadFiles(prev => prev.map(f => f.id === item.id ? { ...f, status: 'done' } : f));
                        if (onAssetsAdded) onAssetsAdded(collection);
                        continue;
                    }
                }
                setUploadFiles(prev => prev.map(f => f.id === item.id ? { ...f, status: 'error' } : f));
            } catch {
                setUploadFiles(prev => prev.map(f => f.id === item.id ? { ...f, status: 'error' } : f));
            }
        }

        setUploading(false);
        if (anySucceeded) notify(t('addAssetsDialog.uploadComplete'), 'success');
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth data-testid="add-assets-dialog">
            <DialogTitle sx={{ fontWeight: 700, borderBottom: '1px solid #e2e8f0', pb: 2, display: 'flex', alignItems: 'center' }}>
                <AddPhotoAlternate sx={{ color: '#5e35b1', mr: 1.5 }} /> {t('addAssetsDialog.title')}
            </DialogTitle>

            <Tabs value={tab} onChange={(e, v) => setTab(v)} sx={{ borderBottom: '1px solid #e2e8f0', px: 2 }}>
                <Tab label={t('addAssetsDialog.searchTab')} data-testid="add-assets-tab-search" />
                <Tab label={t('addAssetsDialog.uploadTab')} data-testid="add-assets-tab-upload" />
            </Tabs>

            <DialogContent sx={{ p: 3, minHeight: 320 }}>
                {tab === 0 && (
                    <Box>
                        <TextField
                            fullWidth
                            placeholder={t('addAssetsDialog.searchPlaceholder')}
                            value={query}
                            onChange={(e) => setQuery(e.target.value)}
                            slotProps={{
                                htmlInput: { 'data-testid': 'add-assets-search-input' },
                                input: {
                                    startAdornment: <InputAdornment position="start"><Search fontSize="small" /></InputAdornment>,
                                },
                            }}
                            sx={{ mb: 2 }}
                        />
                        {searching ? (
                            <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                                <CircularProgress size={24} sx={{ color: '#5e35b1' }} />
                            </Box>
                        ) : results.length === 0 ? (
                            <Typography variant="body2" color="textSecondary" sx={{ textAlign: 'center', py: 4 }}>
                                {query.trim() ? t('addAssetsDialog.noResults') : t('addAssetsDialog.searchHint')}
                            </Typography>
                        ) : (
                            <List data-testid="add-assets-search-results">
                                {results.map((result) => {
                                    const isAdded = addedIds.includes(result.id);
                                    const isAdding = addingIds.includes(result.id);
                                    return (
                                        <ListItem
                                            key={result.id}
                                            data-testid="add-assets-search-result-item"
                                            secondaryAction={
                                                isAdding ? (
                                                    <CircularProgress size={20} />
                                                ) : isAdded ? (
                                                    <Chip size="small" label={t('addAssetsDialog.added')} color="success" />
                                                ) : (
                                                    <Checkbox
                                                        edge="end"
                                                        checked={false}
                                                        onChange={() => handleAddAsset(result.id)}
                                                        inputProps={{ 'aria-label': t('addAssetsDialog.addAria', { title: result.title }) }}
                                                    />
                                                )
                                            }
                                        >
                                            <ListItemAvatar>
                                                <Avatar variant="rounded" src={result.thumb_url}>
                                                    <ImageIcon />
                                                </Avatar>
                                            </ListItemAvatar>
                                            <ListItemText primary={result.title} secondary={result.subtitle} />
                                        </ListItem>
                                    );
                                })}
                            </List>
                        )}
                    </Box>
                )}

                {tab === 1 && (
                    <Box>
                        <Box
                            {...getRootProps()}
                            data-testid="add-assets-dropzone"
                            sx={{
                                border: '2px dashed', borderColor: isDragActive ? '#5e35b1' : '#cbd5e1',
                                borderRadius: 2, p: 4, textAlign: 'center', bgcolor: isDragActive ? '#f3e5f5' : '#f8fafc',
                                cursor: 'pointer',
                            }}
                        >
                            <input {...getInputProps()} />
                            <CloudUpload sx={{ fontSize: 36, color: '#94a3b8', mb: 1 }} />
                            <Typography variant="body2" color="textSecondary">
                                {isDragActive ? t('addAssetsDialog.dropHere') : t('addAssetsDialog.dragOrClick')}
                            </Typography>
                        </Box>

                        {uploadFiles.length > 0 && (
                            <List data-testid="add-assets-upload-list" sx={{ mt: 2 }}>
                                {uploadFiles.map((item) => (
                                    <ListItem key={item.id}>
                                        <ListItemText
                                            primary={item.file.name}
                                            secondary={t(`addAssetsDialog.status.${item.status}`)}
                                        />
                                        {item.status === 'uploading' && <CircularProgress size={18} />}
                                    </ListItem>
                                ))}
                            </List>
                        )}
                    </Box>
                )}
            </DialogContent>

            <DialogActions sx={{ p: 2 }}>
                <Button onClick={onClose} color="inherit">{t('addAssetsDialog.done')}</Button>
                {tab === 1 && uploadFiles.some(f => f.status === 'pending') && (
                    <Button
                        variant="contained"
                        onClick={handleUploadAndAttach}
                        disabled={uploading}
                        data-testid="add-assets-upload-button"
                        sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                    >
                        {uploading ? <CircularProgress size={18} sx={{ color: '#fff' }} /> : t('addAssetsDialog.uploadAndAttach')}
                    </Button>
                )}
            </DialogActions>
        </Dialog>
    );
}
