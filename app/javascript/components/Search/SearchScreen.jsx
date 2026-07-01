import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import {
  Box, Typography, Grid, Chip, CircularProgress, Stack, Button, Snackbar, Alert,
  TextField, InputAdornment, ToggleButton, ToggleButtonGroup, Pagination,
  Select, MenuItem, FormControl, IconButton, Tooltip, Fade,
} from '@mui/material';
import {
  Search as SearchIcon, IosShare, ViewModule, ViewList, AutoAwesome,
  TuneOutlined, SearchOff, Bolt, Image, VideoFile, Description,
  TrendingUp, ArrowUpward, ArrowDownward, SwapVert,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import SearchFilterSidebar from './SearchFilterSidebar';
import SearchResultCard, { SearchResultCardSkeleton } from './SearchResultCard';

const SORT_OPTIONS = [
  { key: 'relevance', dir: 'desc' },
  { key: 'name', dir: 'asc' },
  { key: 'modified', dir: 'desc' },
  { key: 'size', dir: 'desc' },
];

const QUICK_SEARCHES = [
  { key: 'recent_images', icon: <Image fontSize="small" /> },
  { key: 'recent_videos', icon: <VideoFile fontSize="small" /> },
  { key: 'documents', icon: <Description fontSize="small" /> },
  { key: 'approved', icon: <AutoAwesome fontSize="small" /> },
];

// Static (known) filter keys — written and read explicitly so ordering is consistent
const STATIC_FILTER_KEYS = new Set([
  'mime_group', 'modified_within', 'file_size_group',
  'publish_status', 'approved_status', 'orientation', 'style',
  'video_format', 'video_codec',
  'video_height_min', 'video_height_max',
  'video_width_min', 'video_width_max',
  'video_bitrate_min', 'video_bitrate_max',
  'audio_codec', 'audio_bitrate_min', 'audio_bitrate_max',
]);

// URL params that are NOT filter keys (reserved for pagination / sorting / search)
const RESERVED_URL_PARAMS = new Set(['q', 'page', 'per_page', 'sort_by', 'sort_dir']);

function buildQueryString(query, filters, page, perPage, sortBy, sortDir) {
  const params = new URLSearchParams();
  if (query) params.set('q', query);

  // 1. Write known static filters
  STATIC_FILTER_KEYS.forEach((key) => {
    if (filters[key]) params.set(key, filters[key]);
  });

  // 2. Write dynamic metadata filters (anything not in the static set)
  Object.entries(filters).forEach(([key, value]) => {
    if (!STATIC_FILTER_KEYS.has(key) && value) params.set(key, value);
  });

  params.set('page', page);
  params.set('per_page', perPage);
  if (sortBy !== 'relevance') params.set('sort_by', sortBy);
  if (sortDir !== 'desc') params.set('sort_dir', sortDir);
  return params.toString();
}

function parseFiltersFromURL(params) {
  // 1. Read static filters explicitly
  const filters = {};
  STATIC_FILTER_KEYS.forEach((key) => {
    filters[key] = params.get(key) || '';
  });

  // 2. Collect any extra params as dynamic metadata filters (e.g. editor_state.filter)
  params.forEach((value, key) => {
    if (!STATIC_FILTER_KEYS.has(key) && !RESERVED_URL_PARAMS.has(key)) {
      filters[key] = value;
    }
  });

  return filters;
}

function countActiveFilters(filters) {
  return Object.values(filters).filter((value) => value !== '').length;
}

const csrfToken = () => (
  document.querySelector('meta[name="csrf-token"]')?.content
  || document.getElementById('root')?.dataset?.csrfToken
  || ''
);

export default function SearchScreen() {
  const { t } = useTranslation();
  const urlParams = useMemo(() => new URLSearchParams(window.location.search), []);
  const initialQuery = urlParams.get('q') || '';
  const initialFilters = useMemo(() => parseFiltersFromURL(urlParams), [urlParams]);
  const initialPage = parseInt(urlParams.get('page') || '1', 10);
  const initialSortBy = urlParams.get('sort_by') || 'relevance';
  const initialSortDir = urlParams.get('sort_dir') || 'desc';

  const [query, setQuery] = useState(initialQuery);
  const [inputVal, setInputVal] = useState(initialQuery);
  const [filters, setFilters] = useState(initialFilters);
  const [page, setPage] = useState(initialPage);
  const [sortBy, setSortBy] = useState(initialSortBy);
  const [sortDir, setSortDir] = useState(initialSortDir);
  const [viewMode,  setViewMode]  = useState('grid');
  const [gridSize,  setGridSize]  = useState('medium');
  const [assets, setAssets] = useState([]);
  const [meta, setMeta] = useState({ total_found: 0, total_pages: 1, facets: {} });
  const [loading, setLoading] = useState(true);
  const [hasSearched, setHasSearched] = useState(false);
  const [snackbar, setSnackbar] = useState({ open: false, msg: '', severity: 'success' });
  const debounceRef = useRef(null);
  const hasInitializedRef = useRef(false);
  const perPage = 10;

  const fetchResults = useCallback((currentQuery, currentFilters, currentPage, currentSortBy, currentSortDir) => {
    setLoading(true);
    const qs = buildQueryString(currentQuery, currentFilters, currentPage, perPage, currentSortBy, currentSortDir);
    const newUrl = `/search${qs ? `?${qs}` : ''}`;
    window.history.replaceState({}, '', newUrl);

    fetch(`/api/v1/search?${qs}`, {
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken(),
      },
      credentials: 'same-origin',
    })
      .then((response) => response.json())
      .then((data) => {
        setAssets(data.results || []);
        setMeta({
          total_found: data.meta?.total_found || 0,
          total_pages: data.meta?.total_pages || 1,
          facets: data.meta?.facets || {},
        });
        setHasSearched(true);
      })
      .catch(() => setSnackbar({ open: true, msg: t('search.error.fetchFailed'), severity: 'error' }))
      .finally(() => setLoading(false));
  }, [perPage, t]);

  useEffect(() => {
    fetchResults(initialQuery, initialFilters, initialPage, initialSortBy, initialSortDir);
    hasInitializedRef.current = true;
  }, [fetchResults, initialFilters, initialPage, initialQuery, initialSortBy, initialSortDir]);

  useEffect(() => {
    if (!hasInitializedRef.current) return undefined;
    if (inputVal === query) return undefined;

    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      setQuery(inputVal);
      setPage(1);
      fetchResults(inputVal, filters, 1, sortBy, sortDir);
    }, 350);

    return () => clearTimeout(debounceRef.current);
  }, [fetchResults, filters, inputVal, query, sortBy, sortDir]);

  const handleFilterChange = useCallback((newFilters) => {
    setFilters(newFilters);
    setPage(1);
    fetchResults(query, newFilters, 1, sortBy, sortDir);
  }, [fetchResults, query, sortBy, sortDir]);

  const handlePageChange = (_, newPage) => {
    setPage(newPage);
    fetchResults(query, filters, newPage, sortBy, sortDir);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const handleSortChange = (newSortBy) => {
    const nextSortBy = newSortBy || sortBy;
    const defaultSortDir = SORT_OPTIONS.find((option) => option.key === nextSortBy)?.dir || 'desc';
    const nextSortDir = nextSortBy === sortBy
      ? (sortDir === 'desc' ? 'asc' : 'desc')
      : defaultSortDir;
    setSortBy(nextSortBy);
    setSortDir(nextSortDir);
    setPage(1);
    fetchResults(query, filters, 1, nextSortBy, nextSortDir);
  };

  const handleResetFilters = () => {
    const emptyFilters = parseFiltersFromURL(new URLSearchParams());
    setFilters(emptyFilters);
    setPage(1);
    fetchResults(query, emptyFilters, 1, sortBy, sortDir);
  };

  const handleShare = () => {
    navigator.clipboard.writeText(window.location.href);
    setSnackbar({ open: true, msg: t('search.shared'), severity: 'success' });
  };

  const handleQuickSearch = (qsKey) => {
    const emptyFilters = parseFiltersFromURL(new URLSearchParams());
    const presets = {
      recent_images: { q: '', f: { ...emptyFilters, mime_group: 'images', modified_within: 'week' } },
      recent_videos: { q: '', f: { ...emptyFilters, mime_group: 'multimedia', modified_within: 'week' } },
      documents: { q: '', f: { ...emptyFilters, mime_group: 'documents' } },
      approved: { q: '', f: { ...emptyFilters, approved_status: 'approved' } },
    };
    const preset = presets[qsKey];
    if (!preset) return;

    setInputVal(preset.q);
    setQuery(preset.q);
    setFilters(preset.f);
    setPage(1);
    fetchResults(preset.q, preset.f, 1, sortBy, sortDir);
  };

  const activeFilterCount = countActiveFilters(filters);

  const GRID_COLS = {
    small:  { xs: 6,  sm: 4, md: 3, lg: 2 },
    medium: { xs: 12, sm: 6, md: 4, lg: 3 },
    large:  { xs: 12, sm: 6, md: 6, lg: 4 },
  };
  const colSize = GRID_COLS[gridSize] || GRID_COLS.medium;

  return (
    <Box sx={{ display: 'flex', height: '100%', overflow: 'hidden', bgcolor: '#f8fafc' }}>
      <SearchFilterSidebar
        filters={filters}
        activeFilterCount={activeFilterCount}
        onFilterChange={handleFilterChange}
        onReset={handleResetFilters}
        metadataFacets={meta.facets?.metadata_fields || {}}
      />

      <Box sx={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <Box
          sx={{
            background: 'linear-gradient(135deg, #667eea 0%, #764ba2 50%, #f093fb 100%)',
            px: { xs: 2, md: 4 },
            py: 3,
            flexShrink: 0,
          }}
        >
          <TextField
            fullWidth
            value={inputVal}
            onChange={(event) => setInputVal(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Escape') setInputVal('');
            }}
            placeholder={t('search.placeholder')}
            size="medium"
            sx={{
              mb: 2,
              '& .MuiOutlinedInput-root': {
                bgcolor: 'rgba(255,255,255,0.95)',
                backdropFilter: 'blur(8px)',
                borderRadius: 3,
                fontSize: '1rem',
                '& fieldset': { border: 'none' },
                '&:hover': { boxShadow: '0 4px 20px rgba(0,0,0,0.15)' },
                '&.Mui-focused': { boxShadow: '0 4px 24px rgba(0,0,0,0.2)' },
              },
            }}
            slotProps={{
              input: {
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon sx={{ color: '#6366f1', fontSize: 22 }} />
                  </InputAdornment>
                ),
                endAdornment: loading && (
                  <InputAdornment position="end">
                    <CircularProgress size={18} sx={{ color: '#6366f1' }} />
                  </InputAdornment>
                ),
              },
            }}
          />

          <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', alignItems: 'center' }}>
            <Typography variant="caption" sx={{ color: 'rgba(255,255,255,0.8)', fontWeight: 600, mr: 0.5 }}>
              {t('search.quickSearch')}:
            </Typography>
            {QUICK_SEARCHES.map(({ key, icon }) => (
              <Chip
                key={key}
                icon={React.cloneElement(icon, { style: { color: '#fff' } })}
                label={t(`search.quickSearches.${key}`)}
                size="small"
                onClick={() => handleQuickSearch(key)}
                sx={{
                  bgcolor: 'rgba(255,255,255,0.2)',
                  color: '#fff',
                  border: '1px solid rgba(255,255,255,0.3)',
                  backdropFilter: 'blur(4px)',
                  cursor: 'pointer',
                  fontWeight: 500,
                  '&:hover': { bgcolor: 'rgba(255,255,255,0.35)' },
                  '& .MuiChip-icon': { color: '#fff' },
                }}
              />
            ))}
          </Box>
        </Box>

        <Box
          sx={{
            px: 3,
            py: 1.5,
            bgcolor: '#fff',
            borderBottom: '1px solid #e2e8f0',
            display: 'flex',
            alignItems: 'center',
            gap: 2,
            flexWrap: 'wrap',
            flexShrink: 0,
          }}
        >
          <Box
            sx={{
              display: 'flex',
              alignItems: 'center',
              gap: 1,
              bgcolor: '#f1f5f9',
              borderRadius: 2,
              px: 1.5,
              py: 0.5,
            }}
          >
            {query ? <TrendingUp sx={{ fontSize: 16, color: '#6366f1' }} /> : <Bolt sx={{ fontSize: 16, color: '#f59e0b' }} />}
            <Typography variant="body2" fontWeight={700} color="#1e293b">
              {meta.total_found.toLocaleString()}
            </Typography>
            <Typography variant="body2" color="textSecondary">
              {t('search.resultsFound')}
            </Typography>
          </Box>

          {query && (
            <Chip
              label={`"${query}"`}
              size="small"
              color="primary"
              variant="outlined"
              onDelete={() => setInputVal('')}
              sx={{ fontWeight: 600 }}
            />
          )}

          {activeFilterCount > 0 && (
            <Chip
              icon={<TuneOutlined fontSize="small" />}
              label={t('search.activeFilters', { count: activeFilterCount })}
              size="small"
              color="secondary"
              onDelete={handleResetFilters}
              sx={{ fontWeight: 600 }}
            />
          )}

          <Box sx={{ flexGrow: 1 }} />

          <FormControl size="small" sx={{ minWidth: 148 }}>
            <Select
              value={sortBy}
              onChange={(event) => handleSortChange(event.target.value)}
              sx={{ borderRadius: 2, fontSize: '0.875rem' }}
              startAdornment={<SwapVert sx={{ fontSize: 16, color: '#64748b', mr: 0.5 }} />}
              displayEmpty
            >
              {SORT_OPTIONS.map((option) => (
                <MenuItem key={option.key} value={option.key}>
                  {t(`search.sort.${option.key}`)}
                </MenuItem>
              ))}
            </Select>
          </FormControl>

          {/* Explicit ASC / DESC direction toggle — hidden for relevance */}
          {sortBy !== 'relevance' && (
            <ToggleButtonGroup
              value={sortDir}
              exclusive
              onChange={(_, dir) => {
                if (!dir || dir === sortDir) return;
                setSortDir(dir);
                fetchResults(query, filters, 1, sortBy, dir);
              }}
              size="small"
            >
              <ToggleButton
                value="asc"
                aria-label={t('search.sort.direction.asc')}
                sx={{
                  px: 1.25,
                  border: '1px solid #e2e8f0 !important',
                  color: '#64748b',
                  '&.Mui-selected': { bgcolor: '#6366f1 !important', color: '#fff !important' },
                }}
              >
                <ArrowUpward sx={{ fontSize: 15 }} />
              </ToggleButton>
              <ToggleButton
                value="desc"
                aria-label={t('search.sort.direction.desc')}
                sx={{
                  px: 1.25,
                  border: '1px solid #e2e8f0 !important',
                  color: '#64748b',
                  '&.Mui-selected': { bgcolor: '#6366f1 !important', color: '#fff !important' },
                }}
              >
                <ArrowDownward sx={{ fontSize: 15 }} />
              </ToggleButton>
            </ToggleButtonGroup>
          )}

          <Tooltip title={t('search.share')}>
            <IconButton size="small" onClick={handleShare} sx={{ color: '#64748b' }}>
              <IosShare fontSize="small" />
            </IconButton>
          </Tooltip>

          {/* S / M / L grid size — only shown in grid mode */}
          {viewMode === 'grid' && (
            <ToggleButtonGroup
              value={gridSize} exclusive
              onChange={(_, v) => v && setGridSize(v)}
              size="small"
            >
              {[{ key: 'small', label: 'S' }, { key: 'medium', label: 'M' }, { key: 'large', label: 'L' }].map(({ key, label }) => (
                <ToggleButton
                  key={key} value={key}
                  sx={{
                    fontWeight: 700, fontSize: '0.7rem', px: 1.5,
                    border: '1px solid #e2e8f0 !important',
                    color: '#64748b',
                    '&.Mui-selected': { bgcolor: '#334155 !important', color: '#fff !important' },
                  }}
                >
                  {label}
                </ToggleButton>
              ))}
            </ToggleButtonGroup>
          )}

          <ToggleButtonGroup value={viewMode} exclusive onChange={(_, value) => value && setViewMode(value)} size="small">
            <ToggleButton value="grid" sx={{ border: '1px solid #e2e8f0', color: '#64748b', '&.Mui-selected': { bgcolor: '#6366f1 !important', color: '#fff !important' } }}>
              <ViewModule fontSize="small" />
            </ToggleButton>
            <ToggleButton value="list" sx={{ border: '1px solid #e2e8f0', color: '#64748b', '&.Mui-selected': { bgcolor: '#6366f1 !important', color: '#fff !important' } }}>
              <ViewList fontSize="small" />
            </ToggleButton>
          </ToggleButtonGroup>
        </Box>

        {meta.total_pages > 1 && (
          <Box sx={{ px: 3, py: 1.5, bgcolor: '#fff', borderBottom: '1px solid #f1f5f9', display: 'flex', justifyContent: 'flex-end', flexShrink: 0 }}>
            <Pagination
              count={meta.total_pages}
              page={page}
              onChange={handlePageChange}
              size="small"
              color="primary"
              shape="rounded"
              showFirstButton
              showLastButton
            />
          </Box>
        )}

        <Box sx={{ flex: 1, overflowY: 'auto', p: 3 }}>
          {loading ? (
            viewMode === 'grid' ? (
              <Grid container spacing={2.5}>
                {Array.from({ length: 10 }).map((_, index) => (
                  <Grid key={index} size={colSize}>
                    <SearchResultCardSkeleton viewMode="grid" />
                  </Grid>
                ))}
              </Grid>
            ) : (
              <Stack spacing={1.5}>
                {Array.from({ length: 8 }).map((_, index) => (
                  <SearchResultCardSkeleton key={index} viewMode="list" />
                ))}
              </Stack>
            )
          ) : assets.length > 0 ? (
            <Fade in>
              <Box>
                {viewMode === 'grid' ? (
                  <Grid container spacing={2.5}>
                    {assets.map((asset) => (
                      <Grid key={asset.uuid} size={colSize}>
                        <SearchResultCard
                          asset={asset}
                          viewMode="grid"
                          onClick={(item) => { window.location.href = `/assets/${item.uuid}`; }}
                        />
                      </Grid>
                    ))}
                  </Grid>
                ) : (
                  <Stack spacing={1.5}>
                    {assets.map((asset) => (
                      <SearchResultCard
                        key={asset.uuid}
                        asset={asset}
                        viewMode="list"
                        onClick={(item) => { window.location.href = `/assets/${item.uuid}`; }}
                      />
                    ))}
                  </Stack>
                )}

                {meta.total_pages > 1 && (
                  <Box sx={{ mt: 4, display: 'flex', justifyContent: 'center' }}>
                    <Pagination
                      count={meta.total_pages}
                      page={page}
                      onChange={handlePageChange}
                      color="primary"
                      shape="rounded"
                      showFirstButton
                      showLastButton
                    />
                  </Box>
                )}
              </Box>
            </Fade>
          ) : hasSearched ? (
            <Fade in>
              <Box
                sx={{
                  textAlign: 'center',
                  py: 12,
                  bgcolor: '#fff',
                  borderRadius: 3,
                  border: '1px dashed #e2e8f0',
                }}
              >
                <SearchOff sx={{ fontSize: 72, color: '#cbd5e1', mb: 2 }} />
                <Typography variant="h6" fontWeight={600} color="#334155" gutterBottom>
                  {t('search.noResults.title')}
                </Typography>
                <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                  {query ? t('search.noResults.withQuery', { query }) : t('search.noResults.withFilters')}
                </Typography>
                {activeFilterCount > 0 && (
                  <Button variant="outlined" onClick={handleResetFilters} startIcon={<TuneOutlined />}>
                    {t('search.noResults.clearFilters')}
                  </Button>
                )}
              </Box>
            </Fade>
          ) : null}
        </Box>
      </Box>

      <Snackbar
        open={snackbar.open}
        autoHideDuration={3000}
        onClose={() => setSnackbar((state) => ({ ...state, open: false }))}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        <Alert severity={snackbar.severity} sx={{ borderRadius: 2 }} onClose={() => setSnackbar((state) => ({ ...state, open: false }))}>
          {snackbar.msg}
        </Alert>
      </Snackbar>
    </Box>
  );
}
