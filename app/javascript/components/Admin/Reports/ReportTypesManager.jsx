import React, { useState, useEffect, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Box, Grid, Typography, Paper, Button, Chip, IconButton, Tooltip,
  TextField, MenuItem, Select, FormControl, InputLabel, Pagination,
  Dialog, DialogTitle, DialogContent, DialogActions, FormControlLabel,
  Switch, Alert, CircularProgress, Stack, InputAdornment, Autocomplete,
  Accordion, AccordionSummary, AccordionDetails, Divider,
} from '@mui/material';
import {
  Add, Edit, Search, FilterList, BarChartOutlined,
  CheckCircle, RemoveCircle, LockOutlined, TuneOutlined,
  InfoOutlined, ExpandMore, FolderOutlined,
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext';

const PER_PAGE = 12;

// ─── Type Key Explainer ───────────────────────────────────────────────────────
function TypeKeyHelp() {
  return (
    <Box sx={{ p: 1.5, bgcolor: '#f0f9ff', border: '1px solid #bae6fd', borderRadius: 2, mt: 0.5 }}>
      <Typography variant="caption" sx={{ color: '#0369a1', lineHeight: 1.6 }}>
        <strong>What is a Type Key?</strong><br />
        A unique machine-readable identifier for your custom report — like a slug or code name.
        It is used internally to route and tag report data, link to scheduled jobs, and distinguish
        report types in exports.<br /><br />
        <strong>Rules:</strong> lowercase letters, numbers, underscores and hyphens only.<br />
        <strong>Examples:</strong> <code>brand_compliance</code>, <code>large_images_q4</code>,
        <code>red-images-recent</code>, <code>campaign_assets_2026</code>
      </Typography>
    </Box>
  );
}

// ─── Dynamic Query Builder ────────────────────────────────────────────────────
function QueryBuilder({ config, onChange, folders, propertyHints }) {
  const { t } = useTranslation();
  const [customKey, setCustomKey] = useState('');
  const [customVal, setCustomVal] = useState('');

  const set = (key, value) => onChange({ ...config, [key]: value });
  const setNum = (key, value) => onChange({ ...config, [key]: value === '' ? undefined : Number(value) });

  const addCustomFilter = () => {
    if (!customKey.trim() || !customVal.trim()) return;
    const existing = config.custom_filters || {};
    onChange({ ...config, custom_filters: { ...existing, [customKey.trim()]: customVal.trim() } });
    setCustomKey('');
    setCustomVal('');
  };

  const removeCustomFilter = (key) => {
    const { [key]: _removed, ...rest } = config.custom_filters || {};
    onChange({ ...config, custom_filters: rest });
  };

  const activeFilterCount = Object.entries(config)
    .filter(([k, v]) => v && k !== 'description' && !['folder_ids', 'custom_filters', 'ai_tags', 'tags'].includes(k)).length
    + (config.folder_ids?.length || 0)
    + Object.keys(config.custom_filters || {}).length
    + (config.ai_tags?.length || 0)
    + (config.tags?.length || 0);

  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
        <TuneOutlined sx={{ fontSize: 18, color: '#5e35b1' }} />
        <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#374151' }}>
          {t('reports.types.form.query_builder')}
        </Typography>
        <Tooltip title={t('reports.types.form.query_builder_hint')}>
          <InfoOutlined sx={{ fontSize: 16, color: '#94a3b8', cursor: 'help' }} />
        </Tooltip>
        {activeFilterCount > 0 && (
          <Chip label={`${activeFilterCount} active`} size="small"
            sx={{ bgcolor: '#ede7f6', color: '#5e35b1', fontWeight: 700, ml: 'auto' }} />
        )}
      </Box>
      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 2 }}>
        {t('reports.types.form.query_builder_hint')}
      </Typography>

      <Grid container spacing={2}>
        {/* ── Asset Core ── */}
        <Grid size={{ xs: 12 }}>
          <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5 }}>
            {t('reports.types.form.section_core', 'Asset Core')}
          </Typography>
          <Divider sx={{ mt: 0.5, mb: 1.5 }} />
        </Grid>

        <Grid size={{ xs: 12, sm: 6 }}>
          <FormControl fullWidth size="small">
            <InputLabel>{t('reports.types.form.content_type')}</InputLabel>
            <Select value={config.content_type || ''} label={t('reports.types.form.content_type')}
              onChange={(e) => set('content_type', e.target.value)}>
              <MenuItem value="">{t('reports.types.form.any')}</MenuItem>
              <MenuItem value="image/">{t('reports.types.form.images')}</MenuItem>
              <MenuItem value="video/">{t('reports.types.form.videos')}</MenuItem>
              <MenuItem value="audio/">Audio</MenuItem>
              <MenuItem value="application/pdf">PDF</MenuItem>
              <MenuItem value="application/vnd">Word / Excel</MenuItem>
              <MenuItem value="text/">Text</MenuItem>
            </Select>
          </FormControl>
        </Grid>

        <Grid size={{ xs: 12, sm: 6 }}>
          <FormControl fullWidth size="small">
            <InputLabel>{t('reports.types.form.asset_status')}</InputLabel>
            <Select value={config.status || ''} label={t('reports.types.form.asset_status')}
              onChange={(e) => set('status', e.target.value)}>
              <MenuItem value="">{t('reports.types.form.any')}</MenuItem>
              <MenuItem value="draft">{t('reports.types.form.draft')}</MenuItem>
              <MenuItem value="published">{t('reports.types.form.published')}</MenuItem>
              <MenuItem value="archived">{t('reports.types.form.archived', 'Archived')}</MenuItem>
            </Select>
          </FormControl>
        </Grid>

        <Grid size={{ xs: 12, sm: 6 }}>
          <FormControl fullWidth size="small">
            <InputLabel>{t('reports.types.form.approved_status')}</InputLabel>
            <Select value={config.approved_status || ''} label={t('reports.types.form.approved_status')}
              onChange={(e) => set('approved_status', e.target.value)}>
              <MenuItem value="">{t('reports.types.form.any')}</MenuItem>
              <MenuItem value="approved">{t('reports.types.form.approved')}</MenuItem>
              <MenuItem value="rejected">{t('reports.types.form.rejected')}</MenuItem>
              <MenuItem value="pending">{t('reports.types.form.pending')}</MenuItem>
            </Select>
          </FormControl>
        </Grid>

        <Grid size={{ xs: 12, sm: 6 }}>
          <FormControl fullWidth size="small">
            <InputLabel>{t('reports.types.form.date_range', 'Default Date Range')}</InputLabel>
            <Select value={config.date_range || ''} label={t('reports.types.form.date_range', 'Default Date Range')}
              onChange={(e) => set('date_range', e.target.value)}>
              <MenuItem value="">{t('reports.types.form.any')}</MenuItem>
              <MenuItem value="last_7_days">{t('reports.types.form.last_7_days', 'Last 7 Days')}</MenuItem>
              <MenuItem value="last_30_days">{t('reports.types.form.last_30_days', 'Last 30 Days')}</MenuItem>
              <MenuItem value="last_90_days">{t('reports.types.form.last_90_days', 'Last 90 Days')}</MenuItem>
              <MenuItem value="this_quarter">{t('reports.types.form.this_quarter', 'This Quarter')}</MenuItem>
              <MenuItem value="this_year">{t('reports.types.form.this_year', 'Year to Date')}</MenuItem>
            </Select>
          </FormControl>
        </Grid>

        {/* ── Visual Properties ── */}
        <Grid size={{ xs: 12 }}>
          <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5, mt: 1, display: 'block' }}>
            {t('reports.types.form.section_visual', 'Visual Properties')}
          </Typography>
          <Divider sx={{ mt: 0.5, mb: 1.5 }} />
        </Grid>

        <Grid size={{ xs: 12, sm: 6 }}>
          <FormControl fullWidth size="small">
            <InputLabel>{t('reports.types.form.color_mode')}</InputLabel>
            <Select value={config.color_mode || ''} label={t('reports.types.form.color_mode')}
              onChange={(e) => set('color_mode', e.target.value)}>
              <MenuItem value="">{t('reports.types.form.any')}</MenuItem>
              <MenuItem value="color">{t('reports.types.form.color')}</MenuItem>
              <MenuItem value="grayscale">{t('reports.types.form.grayscale')}</MenuItem>
            </Select>
          </FormControl>
        </Grid>

        <Grid size={{ xs: 12, sm: 6 }}>
          <FormControl fullWidth size="small">
            <InputLabel>{t('reports.types.form.orientation')}</InputLabel>
            <Select value={config.orientation || ''} label={t('reports.types.form.orientation')}
              onChange={(e) => set('orientation', e.target.value)}>
              <MenuItem value="">{t('reports.types.form.any')}</MenuItem>
              <MenuItem value="landscape">{t('reports.types.form.landscape')}</MenuItem>
              <MenuItem value="portrait">{t('reports.types.form.portrait')}</MenuItem>
              <MenuItem value="square">{t('reports.types.form.square')}</MenuItem>
            </Select>
          </FormControl>
        </Grid>

        <Grid size={{ xs: 12, sm: 6 }}>
          <TextField fullWidth size="small"
            label={t('reports.types.form.dominant_color', 'Dominant Color (AI)')}
            placeholder="e.g. red, #ff0000"
            value={config.dominant_color || ''}
            onChange={(e) => set('dominant_color', e.target.value)}
            slotProps={{
              input: {
                endAdornment: config.dominant_color ? (
                  <Box sx={{ width: 16, height: 16, borderRadius: '50%', bgcolor: config.dominant_color, border: '1px solid #ccc', mr: 0.5 }} />
                ) : null,
              },
            }}
          />
        </Grid>

        {/* ── Dimensions & Size ── */}
        <Grid size={{ xs: 12 }}>
          <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5, mt: 1, display: 'block' }}>
            {t('reports.types.form.section_dimensions', 'Dimensions & File Size')}
          </Typography>
          <Divider sx={{ mt: 0.5, mb: 1.5 }} />
        </Grid>

        <Grid size={{ xs: 6, sm: 3 }}>
          <TextField size="small" label={t('reports.types.form.min_size')} fullWidth type="number"
            value={config.min_size_bytes ?? ''} onChange={(e) => setNum('min_size_bytes', e.target.value)} />
        </Grid>
        <Grid size={{ xs: 6, sm: 3 }}>
          <TextField size="small" label={t('reports.types.form.max_size')} fullWidth type="number"
            value={config.max_size_bytes ?? ''} onChange={(e) => setNum('max_size_bytes', e.target.value)} />
        </Grid>
        <Grid size={{ xs: 6, sm: 3 }}>
          <TextField size="small" label={t('reports.types.form.min_width')} fullWidth type="number"
            value={config.min_width ?? ''} onChange={(e) => setNum('min_width', e.target.value)} />
        </Grid>
        <Grid size={{ xs: 6, sm: 3 }}>
          <TextField size="small" label={t('reports.types.form.max_width')} fullWidth type="number"
            value={config.max_width ?? ''} onChange={(e) => setNum('max_width', e.target.value)} />
        </Grid>
        <Grid size={{ xs: 6, sm: 3 }}>
          <TextField size="small" label={t('reports.types.form.min_height')} fullWidth type="number"
            value={config.min_height ?? ''} onChange={(e) => setNum('min_height', e.target.value)} />
        </Grid>
        <Grid size={{ xs: 6, sm: 3 }}>
          <TextField size="small" label={t('reports.types.form.max_height')} fullWidth type="number"
            value={config.max_height ?? ''} onChange={(e) => setNum('max_height', e.target.value)} />
        </Grid>

        {/* ── AI & Tags ── */}
        <Grid size={{ xs: 12 }}>
          <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5, mt: 1, display: 'block' }}>
            {t('reports.types.form.section_ai_tags', 'AI Analysis & Tags')}
          </Typography>
          <Divider sx={{ mt: 0.5, mb: 1.5 }} />
        </Grid>

        <Grid size={{ xs: 12, sm: 6 }}>
          <Autocomplete multiple freeSolo size="small"
            options={propertyHints?.image_analysis || []}
            value={config.ai_tags || []}
            onChange={(_, val) => set('ai_tags', val)}
            renderTags={(value, getTagProps) =>
              value.map((option, index) => (
                <Chip key={option} label={option} size="small"
                  sx={{ bgcolor: '#f3e8ff', color: '#6b21a8', fontSize: 11 }}
                  {...getTagProps({ index })} />
              ))
            }
            renderInput={(params) => (
              <TextField {...params} label={t('reports.types.form.ai_tags', 'AI Tags / Labels')}
                placeholder="e.g. outdoor, portrait" size="small" />
            )}
          />
        </Grid>

        <Grid size={{ xs: 12, sm: 6 }}>
          <Autocomplete multiple freeSolo size="small"
            options={[]}
            value={config.tags || []}
            onChange={(_, val) => set('tags', val)}
            renderTags={(value, getTagProps) =>
              value.map((option, index) => (
                <Chip key={option} label={option} size="small"
                  sx={{ bgcolor: '#e0f2fe', color: '#0369a1', fontSize: 11 }}
                  {...getTagProps({ index })} />
              ))
            }
            renderInput={(params) => (
              <TextField {...params} label={t('reports.types.form.asset_tags', 'Asset Tags')}
                placeholder="e.g. brand, campaign" size="small" />
            )}
          />
        </Grid>

        {/* ── Folder Scope ── */}
        <Grid size={{ xs: 12 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 0.5, mt: 1 }}>
            <FolderOutlined sx={{ fontSize: 16, color: '#5e35b1' }} />
            <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5 }}>
              {t('reports.types.form.folder_scope')}
            </Typography>
            <Typography variant="caption" color="text.secondary" sx={{ ml: 0.5 }}>— {t('reports.types.form.folder_scope_hint')}</Typography>
          </Box>
          <Divider sx={{ mb: 1.5 }} />
          <Autocomplete multiple size="small"
            options={folders}
            getOptionLabel={(o) => o.name}
            isOptionEqualToValue={(a, b) => a.id === b.id}
            value={folders.filter(f => (config.folder_ids || []).includes(f.id))}
            onChange={(_, selected) => set('folder_ids', selected.map(s => s.id))}
            renderInput={(params) => (
              <TextField {...params} placeholder={t('reports.types.form.folder_placeholder', 'Select folders...')} size="small" />
            )}
            renderTags={(value, getTagProps) =>
              value.map((option, index) => (
                <Chip key={option.id} label={option.name} size="small"
                  icon={<FolderOutlined sx={{ fontSize: 14 }} />}
                  {...getTagProps({ index })} />
              ))
            }
          />
        </Grid>

        {/* ── Custom Property Filters ── */}
        <Grid size={{ xs: 12 }}>
          <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: 0.5, mt: 1, display: 'block' }}>
            {t('reports.types.form.custom_properties', 'Custom Property Filters')}
          </Typography>
          <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 1 }}>
            {t('reports.types.form.custom_properties_hint', 'Match any JSON property key stored in asset properties (including AI-populated fields).')}
          </Typography>
          <Divider sx={{ mb: 1.5 }} />

          {Object.entries(config.custom_filters || {}).length > 0 && (
            <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1, mb: 1.5 }}>
              {Object.entries(config.custom_filters).map(([k, v]) => (
                <Chip key={k} label={`${k} = ${v}`} size="small"
                  onDelete={() => removeCustomFilter(k)}
                  sx={{ bgcolor: '#fef9c3', color: '#713f12', fontFamily: 'monospace', fontSize: 11 }} />
              ))}
            </Box>
          )}

          <Box sx={{ display: 'flex', gap: 1, alignItems: 'flex-start' }}>
            <Autocomplete freeSolo size="small"
              options={[
                ...(propertyHints?.system || []),
                ...(propertyHints?.image_analysis || []),
                ...(propertyHints?.custom || []),
              ]}
              value={customKey}
              onInputChange={(_, v) => setCustomKey(v)}
              sx={{ flex: 1 }}
              renderInput={(params) => (
                <TextField {...params} size="small"
                  label={t('reports.types.form.property_key', 'Property Key')}
                  placeholder="e.g. ai_label, dominant_color" />
              )}
            />
            <TextField size="small" label={t('reports.types.form.property_value', 'Value')}
              value={customVal} onChange={(e) => setCustomVal(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && addCustomFilter()}
              placeholder="e.g. outdoor" sx={{ flex: 1 }} />
            <Button size="small" variant="outlined" onClick={addCustomFilter}
              disabled={!customKey.trim() || !customVal.trim()}
              sx={{ height: 40, minWidth: 80, borderColor: '#5e35b1', color: '#5e35b1' }}>
              {t('reports.types.form.add_filter', 'Add')}
            </Button>
          </Box>
        </Grid>

        {/* Active Filters Summary */}
        {activeFilterCount > 0 && (
          <Grid size={{ xs: 12 }}>
            <Box sx={{ p: 1.5, bgcolor: '#f0fdf4', border: '1px solid #bbf7d0', borderRadius: 2, mt: 1 }}>
              <Typography variant="caption" sx={{ fontWeight: 600, color: '#15803d' }}>
                {t('reports.types.form.active_filters_summary', 'Active filters')} ({activeFilterCount}):
              </Typography>
              <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5, mt: 0.75 }}>
                {Object.entries(config)
                  .filter(([k, v]) => v && !['description', 'folder_ids', 'custom_filters', 'ai_tags', 'tags'].includes(k))
                  .map(([k, v]) => (
                    <Chip key={k} label={`${k}: ${v}`} size="small"
                      sx={{ bgcolor: '#dcfce7', color: '#166534', fontSize: 11 }} />
                  ))}
                {(config.folder_ids || []).length > 0 && (
                  <Chip label={`${config.folder_ids.length} folder(s)`} size="small"
                    icon={<FolderOutlined sx={{ fontSize: 12 }} />}
                    sx={{ bgcolor: '#dcfce7', color: '#166534', fontSize: 11 }} />
                )}
                {(config.ai_tags || []).map(tag => (
                  <Chip key={tag} label={`ai_tag: ${tag}`} size="small"
                    sx={{ bgcolor: '#f3e8ff', color: '#6b21a8', fontSize: 11 }} />
                ))}
                {(config.tags || []).map(tag => (
                  <Chip key={tag} label={`tag: ${tag}`} size="small"
                    sx={{ bgcolor: '#e0f2fe', color: '#0369a1', fontSize: 11 }} />
                ))}
              </Box>
            </Box>
          </Grid>
        )}

      </Grid>
    </Box>
  );
}
// ─── Form Dialog ─────────────────────────────────────────────────────────────

function ReportTypeFormDialog({ open, editing, onClose, onSaved, folders, propertyHints }) {
  const { t } = useTranslation();
  const notify = useNotify();
  const [name, setName] = useState('');
  const [typeKey, setTypeKey] = useState('');
  const [description, setDescription] = useState('');
  const [active, setActive] = useState(true);
  const [queryConfig, setQueryConfig] = useState({});
  const [saving, setSaving] = useState(false);
  const [errors, setErrors] = useState([]);
  const [showTypeKeyHelp, setShowTypeKeyHelp] = useState(false);

  useEffect(() => {
    if (editing) {
      setName(editing.name || '');
      setTypeKey(editing.report_type || '');
      setDescription(editing.description || '');
      setActive(editing.active !== false);
      const { description: _d, ...rest } = editing.query_config || {};
      setQueryConfig(rest);
    } else {
      setName('');
      setTypeKey('');
      setDescription('');
      setActive(true);
      setQueryConfig({});
    }
    setErrors([]);
    setShowTypeKeyHelp(false);
  }, [editing, open]);

  // Auto-generate type key from name when creating new
  const handleNameChange = (val) => {
    setName(val);
    if (!editing) {
      setTypeKey(val.toLowerCase().replace(/\s+/g, '_').replace(/[^a-z0-9_-]/g, '').slice(0, 40));
    }
  };

  const handleSubmit = async () => {
    setSaving(true);
    setErrors([]);
    try {
      const csrf = document.querySelector('[name="csrf-token"]')?.content || '';
      const body = {
        report_definition: {
          name,
          report_type: typeKey,
          active,
          query_config: { ...queryConfig, description },
        },
      };
      const url = editing ? `/admin/reports/${editing.id}.json` : '/admin/reports.json';
      const method = editing ? 'PATCH' : 'POST';
      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (res.ok) {
        notify(editing ? t('reports.types.form.updated') : t('reports.types.form.created'), 'success');
        onSaved(data.report);
        onClose();
      } else {
        setErrors(data.errors || ['Unknown error']);
      }
    } catch {
      setErrors([t('reports.builder.network_error')]);
    } finally {
      setSaving(false);
    }
  };

  const isBuiltIn = editing?.built_in;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth
      slotProps={{ paper: { sx: { borderRadius: 3 } } }}>
      <DialogTitle sx={{ fontWeight: 700, pb: 1 }}>
        <Stack direction="row" alignItems="center" spacing={1.5}>
          <Box sx={{ width: 36, height: 36, borderRadius: 2, bgcolor: '#ede7f6',
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <BarChartOutlined sx={{ fontSize: 20, color: '#5e35b1' }} />
          </Box>
          <Box>
            <Typography variant="h6" sx={{ fontWeight: 700, lineHeight: 1.2 }}>
              {editing ? t('reports.types.form.edit_title') : t('reports.types.form.create_title')}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              {editing
                ? 'Update report definition and dynamic filters'
                : 'Define a reusable report type with saved filters — users pick it from the Create Export menu'}
            </Typography>
          </Box>
        </Stack>
      </DialogTitle>
      <Divider />

      <DialogContent sx={{ pt: 2.5 }}>
        {errors.length > 0 && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {errors.map((e, i) => <div key={i}>{e}</div>)}
          </Alert>
        )}

        <Stack spacing={2.5}>
          {/* Name */}
          <TextField
            label={t('reports.types.form.name')}
            placeholder={t('reports.types.form.name_placeholder')}
            value={name}
            onChange={(e) => handleNameChange(e.target.value)}
            fullWidth size="small" required
          />

          {/* Type Key */}
          <Box>
            <TextField
              label={t('reports.types.form.type_key')}
              placeholder={t('reports.types.form.type_key_placeholder')}
              value={typeKey}
              onChange={(e) => setTypeKey(e.target.value.toLowerCase().replace(/[^a-z0-9_-]/g, ''))}
              fullWidth size="small" required disabled={isBuiltIn}
              slotProps={{
                input: {
                  startAdornment: isBuiltIn
                    ? <InputAdornment position="start"><LockOutlined sx={{ fontSize: 16, color: '#94a3b8' }} /></InputAdornment>
                    : undefined,
                  endAdornment: (
                    <InputAdornment position="end">
                      <Tooltip title="Learn about Type Keys">
                        <IconButton size="small" onClick={() => setShowTypeKeyHelp(v => !v)}>
                          <InfoOutlined sx={{ fontSize: 16, color: '#94a3b8' }} />
                        </IconButton>
                      </Tooltip>
                    </InputAdornment>
                  ),
                },
              }}
            />
            {showTypeKeyHelp && <TypeKeyHelp />}
          </Box>

          {/* Description */}
          <TextField
            label={t('reports.types.form.description')}
            placeholder={t('reports.types.form.description_placeholder')}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            fullWidth size="small" multiline rows={2}
          />

          <Divider />

          {/* Dynamic Query Builder */}
          <QueryBuilder
            config={queryConfig}
            onChange={setQueryConfig}
            folders={folders}
            propertyHints={propertyHints}
          />

          <Divider />

          {/* Active toggle */}
          <FormControlLabel
            control={<Switch checked={active} onChange={(e) => setActive(e.target.checked)} />}
            label={<Typography variant="body2">{t('reports.types.form.active')}</Typography>}
          />
        </Stack>
      </DialogContent>

      <DialogActions sx={{ px: 3, pb: 2.5 }}>
        <Button onClick={onClose} disabled={saving}>{t('reports.types.form.cancel')}</Button>
        <Button variant="contained" onClick={handleSubmit}
          disabled={saving || !name || !typeKey}
          sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, minWidth: 100 }}>
          {saving ? t('reports.types.form.saving') : t('reports.types.form.save')}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

// ─── Report Type Card ─────────────────────────────────────────────────────────

function ReportTypeCard({ report, onEdit, onToggle, onUse }) {
  const { t } = useTranslation();
  const typeDesc = t(`reports.type_descriptions.${report.report_type}`, { defaultValue: report.description || '' });

  return (
    <Paper elevation={0} sx={{
      border: '1px solid #e2e8f0', borderRadius: 2.5, p: 2.5, height: '100%',
      display: 'flex', flexDirection: 'column', opacity: report.active ? 1 : 0.6,
      transition: 'box-shadow 0.2s',
      '&:hover': { boxShadow: '0 4px 16px rgba(0,0,0,0.08)' },
    }}>
      {/* Header */}
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 1 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Box sx={{
            width: 36, height: 36, borderRadius: 2,
            bgcolor: report.built_in ? '#ede7f6' : '#e3f2fd',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <BarChartOutlined sx={{ fontSize: 18, color: report.built_in ? '#5e35b1' : '#1976d2' }} />
          </Box>
          <Stack spacing={0.25}>
            {report.built_in && (
              <Chip label={t('reports.types.built_in_badge')} size="small"
                sx={{ height: 18, fontSize: 10, bgcolor: '#ede7f6', color: '#5e35b1', fontWeight: 700 }} />
            )}
            {!report.built_in && (
              <Chip label={t('reports.types.custom_badge')} size="small"
                sx={{ height: 18, fontSize: 10, bgcolor: '#e3f2fd', color: '#1976d2', fontWeight: 700 }} />
            )}
            {!report.active && (
              <Chip label={t('reports.types.inactive_badge')} size="small"
                sx={{ height: 18, fontSize: 10 }} />
            )}
          </Stack>
        </Box>
        <Box>
          <Tooltip title={t('reports.types.actions.edit')}>
            <IconButton size="small" onClick={() => onEdit(report)}>
              <Edit sx={{ fontSize: 16 }} />
            </IconButton>
          </Tooltip>
          <Tooltip title={report.active ? t('reports.types.actions.deactivate') : t('reports.types.actions.activate')}>
            <IconButton size="small" onClick={() => onToggle(report)}>
              {report.active
                ? <RemoveCircle sx={{ fontSize: 16, color: '#ef5350' }} />
                : <CheckCircle sx={{ fontSize: 16, color: '#43a047' }} />}
            </IconButton>
          </Tooltip>
        </Box>
      </Box>

      {/* Name */}
      <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 0.5, lineHeight: 1.3 }}>
        {report.name}
      </Typography>

      {/* Type key */}
      <Typography variant="caption" sx={{ color: '#94a3b8', fontFamily: 'monospace', mb: 1 }}>
        {report.report_type}
      </Typography>

      {/* Description */}
      <Typography variant="body2" color="text.secondary" sx={{ flex: 1, mb: 2, fontSize: 12, lineHeight: 1.5 }}>
        {typeDesc || '—'}
      </Typography>

      {/* Action */}
      <Button size="small" variant="outlined" onClick={() => onUse(report)}
        disabled={!report.active}
        sx={{ borderColor: '#5e35b1', color: '#5e35b1', textTransform: 'none',
              '&:hover': { bgcolor: '#ede7f6' } }}>
        {t('reports.types.actions.create_report')}
      </Button>
    </Paper>
  );
}

// ─── Main Manager ─────────────────────────────────────────────────────────────

export default function ReportTypesManager({ onOpenBuilder }) {
  const { t } = useTranslation();
  const notify = useNotify();
  const [reports, setReports] = useState([]);
  const [meta, setMeta] = useState({ total: 0, total_pages: 1, page: 1 });
  const [loading, setLoading] = useState(true);
  const [folders, setFolders] = useState([]);
  const [propertyHints, setPropertyHints] = useState(null);
  const [q, setQ] = useState('');
  const [activeFilter, setActiveFilter] = useState('true');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [page, setPage] = useState(1);
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState(null);

  // Load folders for the form's folder picker
  useEffect(() => {
    fetch('/api/v1/folders', {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    })
      .then(r => r.json())
      .then(d => setFolders((d.folders || d || []).map(f => ({ id: f.id, name: f.name }))))
      .catch(() => {}); // non-critical

    // Load asset property hints for QueryBuilder autocomplete
    fetch('/admin/reports/asset_property_hints.json', {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    })
      .then(r => r.json())
      .then(d => setPropertyHints(d.hints || {}))
      .catch(() => {}); // non-critical
  }, []);

  const fetchReports = useCallback(async (opts = {}) => {
    setLoading(true);
    try {
      const params = new URLSearchParams({
        active: opts.activeFilter ?? activeFilter,
        page: opts.page ?? page,
        per_page: PER_PAGE,
      });
      if (opts.q ?? q) params.set('q', opts.q ?? q);
      if (opts.categoryFilter ?? categoryFilter) params.set('category', opts.categoryFilter ?? categoryFilter);

      const res = await fetch(`/admin/reports.json?${params}`, { headers: { Accept: 'application/json' } });
      const data = await res.json();
      setReports(data.reports || []);
      setMeta(data.meta || { total: 0, total_pages: 1, page: 1 });
    } catch {
      notify(t('reports.builder.error_load'), 'error');
    } finally {
      setLoading(false);
    }
  }, [activeFilter, page, q, categoryFilter, notify, t]);

  useEffect(() => { fetchReports(); }, []);

  const handleSearch = (val) => {
    setQ(val);
    setPage(1);
    fetchReports({ q: val, page: 1 });
  };

  const handleActiveFilter = (val) => {
    setActiveFilter(val);
    setPage(1);
    fetchReports({ activeFilter: val, page: 1 });
  };

  const handlePageChange = (_, newPage) => {
    setPage(newPage);
    fetchReports({ page: newPage });
  };

  const handleEdit = (report) => {
    setEditing(report);
    setFormOpen(true);
  };

  const handleNew = () => {
    setEditing(null);
    setFormOpen(true);
  };

  const handleToggle = async (report) => {
    try {
      const csrf = document.querySelector('[name="csrf-token"]')?.content || '';
      const url = report.active
        ? `/admin/reports/${report.id}.json`
        : `/admin/reports/${report.id}.json`;
      const method = report.active ? 'DELETE' : 'PATCH';
      const body = method === 'PATCH' ? JSON.stringify({ report_definition: { active: true } }) : undefined;
      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
        body,
      });
      if (res.ok) {
        notify(report.active ? t('reports.types.form.deactivated') : t('reports.types.form.updated'), 'success');
        fetchReports();
      }
    } catch {
      notify(t('reports.builder.network_error'), 'error');
    }
  };

  const handleSaved = () => { fetchReports(); };

  return (
    <Box>
      {/* Toolbar */}
      <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1.5} sx={{ mb: 3 }} alignItems="center">
        <TextField
          size="small"
          placeholder={t('reports.types.search_placeholder')}
          value={q}
          onChange={(e) => handleSearch(e.target.value)}
          slotProps={{ input: { startAdornment: <InputAdornment position="start"><Search sx={{ fontSize: 18, color: '#94a3b8' }} /></InputAdornment> } }}
          sx={{ minWidth: 240 }}
        />
        <FormControl size="small" sx={{ minWidth: 140 }}>
          <InputLabel><FilterList sx={{ fontSize: 16, mr: 0.5 }} />{t('reports.types.filter_active')}</InputLabel>
          <Select value={activeFilter} label={t('reports.types.filter_active')}
            onChange={(e) => handleActiveFilter(e.target.value)}>
            <MenuItem value="all">{t('reports.types.filter_all')}</MenuItem>
            <MenuItem value="true">{t('reports.types.filter_active')}</MenuItem>
            <MenuItem value="false">{t('reports.types.filter_inactive')}</MenuItem>
          </Select>
        </FormControl>
        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel><TuneOutlined sx={{ fontSize: 16, mr: 0.5 }} />Type</InputLabel>
          <Select value={categoryFilter} label="Type"
            onChange={(e) => { setCategoryFilter(e.target.value); setPage(1); fetchReports({ categoryFilter: e.target.value, page: 1 }); }}>
            <MenuItem value="">{t('reports.types.filter_all')}</MenuItem>
            <MenuItem value="built_in_only">{t('reports.types.filter_built_in')}</MenuItem>
            <MenuItem value="custom_only">{t('reports.types.filter_custom')}</MenuItem>
          </Select>
        </FormControl>
        <Box sx={{ flex: 1 }} />
        <Button variant="contained" startIcon={<Add />} onClick={handleNew}
          sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none', whiteSpace: 'nowrap' }}>
          {t('reports.types.new_type')}
        </Button>
      </Stack>

      {/* Count */}
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        {meta.total} {meta.total === 1 ? 'report type' : 'report types'}
      </Typography>

      {/* Grid */}
      {loading ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 8 }}>
          <CircularProgress sx={{ color: '#5e35b1' }} />
        </Box>
      ) : reports.length === 0 ? (
        <Box sx={{ textAlign: 'center', py: 8, color: '#94a3b8' }}>
          <BarChartOutlined sx={{ fontSize: 48, mb: 2 }} />
          <Typography>{t('reports.types.empty')}</Typography>
        </Box>
      ) : (
        <Grid container spacing={2.5}>
          {reports.map((r) => (
            <Grid size={{ xs: 12, sm: 6, md: 4 }} key={r.id}>
              <ReportTypeCard
                report={r}
                onEdit={handleEdit}
                onToggle={handleToggle}
                onUse={(report) => onOpenBuilder && onOpenBuilder(report.id)}
              />
            </Grid>
          ))}
        </Grid>
      )}

      {/* Pagination */}
      {meta.total_pages > 1 && (
        <Box sx={{ display: 'flex', justifyContent: 'center', mt: 4 }}>
          <Pagination
            count={meta.total_pages}
            page={page}
            onChange={handlePageChange}
            color="primary"
            shape="rounded"
          />
        </Box>
      )}

      {/* Form dialog */}
      <ReportTypeFormDialog
        open={formOpen}
        editing={editing}
        onClose={() => setFormOpen(false)}
        onSaved={handleSaved}
        folders={folders}
        propertyHints={propertyHints}
      />
    </Box>
  );
}
