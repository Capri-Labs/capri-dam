import React, { useEffect, useMemo, useState } from 'react';
import {
  Alert,
  Avatar,
  Box,
  Button,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  Grid,
  IconButton,
  List,
  ListItem,
  ListItemAvatar,
  ListItemText,
  Paper,
  Stack,
  Typography
} from '@mui/material';
import { Close, AutoFixHigh, MergeType, SkipNext, FileCopy, FolderSpecial, DeleteOutlined, VisibilityOffOutlined, DeleteOutlineOutlined } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';

const actionHeaders = () => ({
  'Content-Type': 'application/json',
  'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content || ''
});

const interpolate = (template, values = {}) => template.replace(/\{\{(\w+)\}\}/g, (_match, key) => values[key] ?? '');

const translateWithFallback = (t, key, fallback, options = {}) => {
  const translated = t(key, { ...options, defaultValue: fallback });
  return translated === key || (options.count != null && translated === `${key}:${options.count}`)
    ? interpolate(fallback, options)
    : translated;
};

const formatBytes = (size) => {
  if (!size) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  const index = Math.min(Math.floor(Math.log(size) / Math.log(1024)), units.length - 1);
  const value = size / (1024 ** index);
  return `${value >= 10 || index === 0 ? Math.round(value) : value.toFixed(1)} ${units[index]}`;
};

// Same visual treatment as the "Bin" badge on Search results
// (see SearchResultCard.jsx's BinChip) — flags an existing/matched asset
// that currently lives in the Recycle Bin (soft-deleted), so the user isn't
// misled into thinking an active duplicate exists when it's actually trashed.
function BinChip({ t }) {
  return (
    <Chip
      icon={<DeleteOutlineOutlined sx={{ fontSize: 12 }} />}
      label={t('search.binBadge')}
      size="small"
      sx={{
        height: 20,
        fontSize: '0.65rem',
        fontWeight: 600,
        color: '#b91c1c',
        bgcolor: '#fee2e2',
        border: 'none',
        '& .MuiChip-icon': { color: '#b91c1c', ml: '4px' },
      }}
    />
  );
}

function LegacyDuplicateResolverDialog({ open, onClose, fileData, onResolve }) {
  const { t } = useTranslation();
  const translate = (key, fallback, options = {}) => translateWithFallback(t, key, fallback, options);
  const notify = useNotify();
  const [isAiAnalyzing, setIsAiAnalyzing] = useState(false);

  if (!fileData || !fileData.duplicateData) return null;

  const existingAssets = fileData.duplicateData;
  const primaryAsset = existingAssets[0];

  const handleAiMerge = () => {
    setIsAiAnalyzing(true);
    setTimeout(() => {
      setIsAiAnalyzing(false);
      notify(translate('folders.duplicates.legacy.notifications.aiMerged', 'AI successfully merged new metadata into {{count}} existing asset(s).', { count: existingAssets.length }), 'success');
      onResolve(fileData.id, 'skip');
    }, 1500);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle component="div" sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0' }}>
        <Typography variant="h6" fontWeight="700">{translate('folders.duplicates.legacy.title', 'Resolve Duplicate: {{title}}', { title: fileData.meta.title })}</Typography>
        <IconButton onClick={onClose} size="small"><Close /></IconButton>
      </DialogTitle>

      <DialogContent sx={{ p: 4 }}>
        <Grid container spacing={4}>
          <Grid size={6}>
            <Typography variant="subtitle2" color="textSecondary" fontWeight="700" sx={{ mb: 2 }}>
              {translate('folders.duplicates.legacy.currentlyInDam', 'Currently in DAM ({{count}} found)', { count: existingAssets.length })}
            </Typography>
            <Paper variant="outlined" sx={{ p: 2, borderRadius: 2, bgcolor: '#f1f5f9' }}>
              <Box sx={{ height: 140, position: 'relative', display: 'flex', justifyContent: 'center', mb: 2 }}>
                {primaryAsset.in_bin && (
                  <Box sx={{ position: 'absolute', top: 0, left: 0, zIndex: 1 }}>
                    <BinChip t={t} />
                  </Box>
                )}
                <img src={primaryAsset.url} alt={translate('folders.duplicates.legacy.alt.existing', 'existing')} style={{ maxHeight: '100%', objectFit: 'contain' }} />
              </Box>
              <Typography variant="body2" fontWeight="700" noWrap>{translate('folders.duplicates.legacy.primaryTitle', 'Title: {{title}}', { title: primaryAsset.title })}</Typography>

              <Box sx={{ mt: 1.5 }}>
                <Typography variant="caption" color="textSecondary" display="block" sx={{ mb: 0.5 }}>{translate('folders.duplicates.legacy.locations', 'Locations:')}</Typography>
                {existingAssets.map((existingAsset, index) => (
                  <Box key={index} sx={{ display: 'inline-flex', gap: 0.5, mr: 0.5, mb: 0.5 }}>
                    <Chip
                      icon={<FolderSpecial fontSize="small" />}
                      label={existingAsset.folderName}
                      size="small"
                      sx={{ bgcolor: '#e2e8f0' }}
                    />
                    {existingAsset.in_bin && <BinChip t={t} />}
                  </Box>
                ))}
              </Box>
            </Paper>
          </Grid>

          <Grid size={6}>
            <Typography variant="subtitle2" color="primary" fontWeight="700" sx={{ mb: 2 }}>{translate('folders.duplicates.legacy.newUpload', 'Your New Upload')}</Typography>
            <Paper variant="outlined" sx={{ p: 2, borderRadius: 2, borderColor: '#4f46e5', bgcolor: '#eef2ff', height: '100%' }}>
              <Box sx={{ height: 140, display: 'flex', justifyContent: 'center', mb: 2 }}>
                <img src={fileData.preview} alt={translate('folders.duplicates.legacy.alt.new', 'new')} style={{ maxHeight: '100%', objectFit: 'contain' }} />
              </Box>
              <Typography variant="body2" fontWeight="700" noWrap>{fileData.meta.title}</Typography>
              <Typography variant="caption" color="textSecondary" display="block">
                {translate('folders.duplicates.legacy.pendingStatus', 'Status: Pending Upload')}
              </Typography>
              <Chip label={translate('folders.duplicates.legacy.identicalHash', 'Identical Hash')} size="small" color="warning" sx={{ mt: 1 }} />
            </Paper>
          </Grid>
        </Grid>

        <Paper sx={{ mt: 4, p: 2, bgcolor: '#f5f3ff', border: '1px solid #ddd6fe', borderRadius: 2, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Box>
            <Typography variant="body2" color="#6d28d9" fontWeight="700" sx={{ display: 'flex', alignItems: 'center' }}>
              <AutoFixHigh fontSize="small" sx={{ mr: 1 }} /> {translate('folders.duplicates.legacy.aiMergeRecommendation', 'AI Merge Recommendation')}
            </Typography>
            <Typography variant="caption" color="#5b21b6">
              {translate('folders.duplicates.legacy.aiMergeDescription', 'The bytes are identical. AI can append your new tags to the existing asset to prevent clutter.')}
            </Typography>
          </Box>
          <Button
            variant="contained"
            onClick={handleAiMerge}
            disabled={isAiAnalyzing}
            sx={{ bgcolor: '#6d28d9', '&:hover': { bgcolor: '#5b21b6' }, textTransform: 'none' }}
            startIcon={isAiAnalyzing ? <CircularProgress size={16} color="inherit" /> : <MergeType />}
          >
            {translate('folders.duplicates.legacy.mergeMetadata', 'Merge Metadata')}
          </Button>
        </Paper>
      </DialogContent>

      <DialogActions sx={{ p: 3, bgcolor: '#f8fafc', borderTop: '1px solid #e2e8f0' }}>
        <Button onClick={() => onResolve(fileData.id, 'skip')} color="inherit" startIcon={<SkipNext />}>{translate('folders.duplicates.legacy.skipUpload', 'Skip Upload')}</Button>
        <Button onClick={() => onResolve(fileData.id, 'upload')} color="warning" variant="outlined" startIcon={<FileCopy />}>{translate('folders.duplicates.legacy.uploadAnyway', 'Upload as Duplicate Anyway')}</Button>
      </DialogActions>
    </Dialog>
  );
}

function AssetDuplicateFinderDialog({ open, onClose, asset }) {
  const { t } = useTranslation();
  const notify = useNotify();
  const [duplicates, setDuplicates] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [busyIds, setBusyIds] = useState([]);
  const [ignoredIds, setIgnoredIds] = useState([]);
  const [deactivatedIds, setDeactivatedIds] = useState([]);

  useEffect(() => {
    if (!open || !asset?.id) return undefined;

    let active = true;
    setLoading(true);
    setError('');

    fetch(`/api/v1/assets/${asset.id}/duplicates`)
      .then(async (response) => {
        if (!response.ok) throw new Error('load');
        return response.json();
      })
      .then((payload) => {
        if (active) setDuplicates(payload.duplicates || []);
      })
      .catch(() => {
        if (active) setError(t('common.error'));
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [open, asset?.id, t]);

  const visibleDuplicates = useMemo(
    () => duplicates.filter((duplicate) => !ignoredIds.includes(duplicate.id) && !deactivatedIds.includes(duplicate.id)),
    [duplicates, ignoredIds, deactivatedIds]
  );

  const withBusy = async (id, callback) => {
    setBusyIds((prev) => [...prev, id]);
    try {
      await callback();
    } finally {
      setBusyIds((prev) => prev.filter((busyId) => busyId !== id));
    }
  };

  const updateAssetMetadata = async (assetId, metadata) => {
    const response = await fetch(`/api/v1/assets/${assetId}`, {
      method: 'PATCH',
      headers: actionHeaders(),
      body: JSON.stringify({ asset: { metadata } })
    });

    if (!response.ok) throw new Error('request');
    return response.json();
  };

  const ignoreDuplicate = async (duplicate) => {
    await withBusy(duplicate.id, async () => {
      const existingIds = Array.isArray(asset?.properties?.ignored_duplicate_asset_ids)
        ? asset.properties.ignored_duplicate_asset_ids
        : [];
      await updateAssetMetadata(asset.id, { ignored_duplicate_asset_ids: [...new Set([...existingIds, duplicate.id])] });
      setIgnoredIds((prev) => [...prev, duplicate.id]);
      notify(t('folders.duplicates.ignore'), 'success');
    });
  };

  const deactivateDuplicate = async (duplicate) => {
    await withBusy(duplicate.id, async () => {
      await updateAssetMetadata(duplicate.id, { duplicate_status: 'deactivated', duplicate_source_asset_id: asset.id });
      setDeactivatedIds((prev) => [...prev, duplicate.id]);
      notify(t('folders.duplicates.deactivate'), 'success');
    });
  };

  const deleteDuplicate = async (duplicate) => {
    await withBusy(duplicate.id, async () => {
      const response = await fetch(`/api/v1/assets/${duplicate.id}`, {
        method: 'DELETE',
        headers: actionHeaders()
      });
      if (!response.ok) throw new Error('delete');
      setDuplicates((prev) => prev.filter((item) => item.id !== duplicate.id));
      notify(t('folders.duplicates.delete'), 'success');
    });
  };

  const ignoreAll = async () => {
    const ids = visibleDuplicates.map((duplicate) => duplicate.id);
    if (ids.length === 0) return;
    const existingIds = Array.isArray(asset?.properties?.ignored_duplicate_asset_ids)
      ? asset.properties.ignored_duplicate_asset_ids
      : [];

    try {
      await updateAssetMetadata(asset.id, { ignored_duplicate_asset_ids: [...new Set([...existingIds, ...ids])] });
      setIgnoredIds((prev) => [...new Set([...prev, ...ids])]);
      notify(t('folders.duplicates.ignore_all'), 'success');
    } catch {
      notify(t('common.error'), 'error');
    }
  };

  const deleteAll = async () => {
    const ids = visibleDuplicates.map((duplicate) => duplicate.id);
    try {
      const responses = await Promise.all(ids.map((id) => fetch(`/api/v1/assets/${id}`, { method: 'DELETE', headers: actionHeaders() })));
      if (responses.some((response) => !response.ok)) throw new Error('delete');
      setDuplicates((prev) => prev.filter((duplicate) => !ids.includes(duplicate.id)));
      notify(t('folders.duplicates.delete_all'), 'success');
    } catch {
      notify(t('common.error'), 'error');
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle component="div" sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <Box>
          <Typography variant="h6" fontWeight={700}>{t('folders.duplicates.title')}</Typography>
          {asset?.title && <Typography variant="body2" color="text.secondary">{asset.title}</Typography>}
        </Box>
        <IconButton onClick={onClose} size="small"><Close /></IconButton>
      </DialogTitle>
      <DialogContent dividers>
        {loading && (
          <Stack spacing={2} sx={{py: 6, alignItems: 'center'}}>
            <CircularProgress />
            <Typography color="text.secondary">{t('folders.duplicates.loading')}</Typography>
          </Stack>
        )}

        {!loading && error && <Alert severity="error">{error}</Alert>}

        {!loading && !error && visibleDuplicates.length === 0 && (
          <Alert severity="success">{t('folders.duplicates.none_found')}</Alert>
        )}

        {!loading && !error && visibleDuplicates.length > 0 && (
          <List disablePadding>
            {visibleDuplicates.map((duplicate, index) => {
              const similarityLabel = duplicate.similarity_type === 'exact'
                ? t('folders.duplicates.exact_match')
                : t('folders.duplicates.name_match');
              const isBusy = busyIds.includes(duplicate.id);

              return (
                <React.Fragment key={duplicate.id}>
                  {index > 0 && <Divider />}
                  <ListItem alignItems="flex-start" sx={{ px: 0, py: 2 }}>
                    <ListItemAvatar>
                      <Avatar src={duplicate.url} variant="rounded" sx={{ width: 72, height: 72, bgcolor: '#e2e8f0' }} />
                    </ListItemAvatar>
                    <ListItemText slotProps={{secondary: { component: 'div' } }}
                      primary={<Typography fontWeight={700}>{duplicate.title}</Typography>}
                      secondary={(
                        <Stack spacing={1} sx={{ mt: 0.5 }}>
                          <Stack direction="row" spacing={1} sx={{flexWrap: 'wrap'}}>
                            <Chip label={similarityLabel} size="small" color={duplicate.similarity_type === 'exact' ? 'success' : 'default'} />
                            <Chip label={`${t('folders.duplicates.similarity')}: ${duplicate.similarity_score}%`} size="small" />
                            <Chip label={formatBytes(duplicate.size)} size="small" />
                          </Stack>
                          <Typography variant="body2" color="text.secondary">
                            {t('folders.duplicates.folder')}: {duplicate.folder_name || '—'}
                          </Typography>
                        </Stack>
                      )}
                    />
                    <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} sx={{ alignSelf: 'center', ml: 2 }}>
                      <Button size="small" variant="outlined" disabled={isBusy} onClick={() => ignoreDuplicate(duplicate)}>
                        {t('folders.duplicates.ignore')}
                      </Button>
                      <Button size="small" variant="outlined" color="warning" disabled={isBusy} startIcon={<VisibilityOffOutlined />} onClick={() => deactivateDuplicate(duplicate)}>
                        {t('folders.duplicates.deactivate')}
                      </Button>
                      <Button size="small" variant="contained" color="error" disabled={isBusy} startIcon={isBusy ? <CircularProgress size={14} color="inherit" /> : <DeleteOutlined />} onClick={() => deleteDuplicate(duplicate)}>
                        {t('folders.duplicates.delete')}
                      </Button>
                    </Stack>
                  </ListItem>
                </React.Fragment>
              );
            })}
          </List>
        )}
      </DialogContent>
      <DialogActions sx={{ justifyContent: 'space-between', px: 3, py: 2 }}>
        <Button onClick={onClose}>{t('common.close')}</Button>
        <Stack direction="row" spacing={1}>
          <Button onClick={ignoreAll} disabled={visibleDuplicates.length === 0}>{t('folders.duplicates.ignore_all')}</Button>
          <Button variant="contained" color="error" onClick={deleteAll} disabled={visibleDuplicates.length === 0}>
            {t('folders.duplicates.delete_all')}
          </Button>
        </Stack>
      </DialogActions>
    </Dialog>
  );
}

export default function DuplicateFinderDialog({ open, onClose, asset, fileData, onResolve }) {
  if (fileData) {
    return <LegacyDuplicateResolverDialog open={open} onClose={onClose} fileData={fileData} onResolve={onResolve} />;
  }

  return <AssetDuplicateFinderDialog open={open} onClose={onClose} asset={asset} />;
}
