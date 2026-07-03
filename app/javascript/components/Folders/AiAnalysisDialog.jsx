import React, { useEffect, useMemo, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Checkbox,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  FormControlLabel,
  FormGroup,
  IconButton,
  LinearProgress,
  Stack,
  Typography
} from '@mui/material';
import { Close } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';

const requestHeaders = () => ({
  'Content-Type': 'application/json',
  'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content || ''
});

const translateWithFallback = (t, key, fallback) => {
  const translated = t(key, { defaultValue: fallback });
  return translated === key ? fallback : translated;
};

export default function AiAnalysisDialog({ open, onClose, asset }) {
  const { t } = useTranslation();
  const notify = useNotify();
  const [loading, setLoading] = useState(false);
  const [queued, setQueued] = useState(false);
  const [error, setError] = useState('');
  const [analysis, setAnalysis] = useState(null);
  const [selectedTags, setSelectedTags] = useState([]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open || !asset?.id) return undefined;

    let active = true;
    setLoading(true);
    setQueued(false);
    setError('');
    setAnalysis(null);

    fetch(`/api/v1/assets/${asset.id}/ai_analysis`, { method: 'POST', headers: requestHeaders() })
      .then(async (response) => {
        const payload = await response.json();
        if (response.status === 202) {
          if (!active) return;
          setQueued(true);
          return;
        }
        if (!response.ok) throw new Error(payload.error || 'error');
        if (!active) return;
        setAnalysis(payload);
        setSelectedTags(payload.suggested_tags || []);
      })
      .catch(() => {
        if (active) setError(t('folders.ai.error'));
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, asset?.id]);

  const toggleTag = (tag) => {
    setSelectedTags((prev) => (prev.includes(tag) ? prev.filter((value) => value !== tag) : [...prev, tag]));
  };

  const qualityScore = useMemo(() => analysis?.quality_score || 0, [analysis]);

  const persistAsset = async (payload, successMessage) => {
    setSaving(true);
    try {
      const response = await fetch(`/api/v1/assets/${asset.id}`, {
        method: 'PATCH',
        headers: requestHeaders(),
        body: JSON.stringify(payload)
      });
      if (!response.ok) throw new Error('save');
      notify(successMessage, 'success');
    } catch {
      notify(t('folders.ai.error'), 'error');
    } finally {
      setSaving(false);
    }
  };

  const applySuggestedTags = async () => {
    await persistAsset({ asset: { tags: selectedTags } }, t('folders.ai.apply_tags'));
  };

  const saveToProperties = async () => {
    await persistAsset({ asset: { metadata: { ai_analysis: analysis, image_analysis_status: 'completed' } } }, t('folders.ai.save_properties'));
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle component="div" sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <Box>
          <Typography variant="h6" fontWeight={700}>{t('folders.ai.title')}</Typography>
          {asset?.title && <Typography variant="body2" color="text.secondary">{asset.title}</Typography>}
        </Box>
        <IconButton onClick={onClose} size="small"><Close /></IconButton>
      </DialogTitle>
      <DialogContent dividers>
        <Stack spacing={3}>
          <Box sx={{ display: 'flex', gap: 2, alignItems: 'center' }}>
            <Box sx={{ width: 120, height: 120, borderRadius: 3, overflow: 'hidden', bgcolor: '#e2e8f0', flexShrink: 0 }}>
              {asset?.url ? (
                <img src={asset.url} alt={asset?.title || translateWithFallback(t, 'folders.ai.asset_alt', 'asset')} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
              ) : null}
            </Box>
            <Box sx={{ flexGrow: 1 }}>
              {loading && (
                <Stack spacing={1.5}>
                  <Typography fontWeight={600}>{t('folders.ai.analyzing')}</Typography>
                  <LinearProgress />
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <CircularProgress size={18} />
                    <Typography variant="body2" color="text.secondary">{t('folders.ai.analyzing')}</Typography>
                  </Box>
                </Stack>
              )}
              {queued && !loading && <Alert severity="info">{t('folders.ai.queued')}</Alert>}
              {error && !loading && <Alert severity="error">{error}</Alert>}
              {!loading && !queued && !error && analysis && (
                <Typography variant="body2" color="text.secondary">{analysis.description}</Typography>
              )}
            </Box>
          </Box>

          {!loading && analysis && (
            <>
              <Divider />

              <Box>
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>{t('folders.ai.labels')}</Typography>
                <Stack direction="row" spacing={1} useFlexGap sx={{flexWrap: 'wrap'}}>
                  {(analysis.labels || []).map((label) => <Chip key={label} label={label} size="small" />)}
                </Stack>
              </Box>

              <Box>
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>{t('folders.ai.colors')}</Typography>
                <Stack direction="row" spacing={1.5} useFlexGap sx={{flexWrap: 'wrap'}}>
                  {(analysis.colors || []).map((color) => (
                    <Stack key={color.hex || color.name} direction="row" spacing={1} sx={{alignItems: 'center'}}>
                      <Box sx={{ width: 22, height: 22, borderRadius: '50%', bgcolor: color.hex, border: '1px solid #cbd5e1' }} />
                      <Typography variant="body2">{color.name}</Typography>
                    </Stack>
                  ))}
                </Stack>
              </Box>

              <Box>
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>{t('folders.ai.quality')}</Typography>
                <Stack direction="row" spacing={2} sx={{alignItems: 'center'}}>
                  <Box sx={{ flexGrow: 1 }}>
                    <LinearProgress variant="determinate" value={qualityScore} sx={{ height: 10, borderRadius: 999 }} />
                  </Box>
                  <Typography variant="body2" fontWeight={700}>{qualityScore}%</Typography>
                </Stack>
              </Box>

              <Box>
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>{t('folders.ai.suggested_tags')}</Typography>
                <FormGroup row>
                  {(analysis.suggested_tags || []).map((tag) => (
                    <FormControlLabel
                      key={tag}
                      control={<Checkbox checked={selectedTags.includes(tag)} onChange={() => toggleTag(tag)} />}
                      label={tag}
                    />
                  ))}
                </FormGroup>
              </Box>

              <Box>
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>{t('folders.ai.description')}</Typography>
                <Typography variant="body2" color="text.secondary">{analysis.description}</Typography>
              </Box>

              <Box>
                <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>{t('folders.ai.similar')}</Typography>
                <Stack direction="row" spacing={1.5} useFlexGap sx={{flexWrap: 'wrap'}}>
                  {(analysis.similar_assets || []).map((similarAsset) => (
                    <Box key={similarAsset.id} sx={{ width: 96 }}>
                      <Box sx={{ width: 96, height: 72, borderRadius: 2, overflow: 'hidden', bgcolor: '#e2e8f0' }}>
                        {similarAsset.url ? <img src={similarAsset.url} alt={similarAsset.title} style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : null}
                      </Box>
                      <Typography variant="caption" sx={{ display: 'block', mt: 0.5 }} noWrap>{similarAsset.title}</Typography>
                    </Box>
                  ))}
                </Stack>
              </Box>
            </>
          )}
        </Stack>
      </DialogContent>
      <DialogActions sx={{ px: 3, py: 2 }}>
        <Button onClick={onClose}>{t('common.close')}</Button>
        <Stack direction="row" spacing={1}>
          <Button variant="outlined" onClick={applySuggestedTags} disabled={!analysis || saving || selectedTags.length === 0}>
            {t('folders.ai.apply_tags')}
          </Button>
          <Button variant="contained" onClick={saveToProperties} disabled={!analysis || saving}>
            {t('folders.ai.save_properties')}
          </Button>
        </Stack>
      </DialogActions>
    </Dialog>
  );
}
