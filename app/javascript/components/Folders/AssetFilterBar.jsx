import React, { useState } from 'react';
import {
  Box,
  Typography,
  InputAdornment,
  TextField,
  Divider,
  Button,
  Menu,
  MenuItem,
  ToggleButton,
  ToggleButtonGroup,
  Checkbox,
  ListItemText,
  Chip,
  Select,
  FormControl,
  Tooltip,
  IconButton,
} from '@mui/material';
import {
  SearchOutlined,
  Sort,
  ViewModule,
  ViewList,
  FolderOutlined,
  ImageOutlined,
  VideocamOutlined,
  DescriptionOutlined,
  AudioFileOutlined,
  KeyboardArrowDown,
  IosShare,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const SORT_OPTIONS = [
  { labelKey: 'folders.filter.name_az',        field: 'name',       direction: 'asc'  },
  { labelKey: 'folders.filter.name_za',        field: 'name',       direction: 'desc' },
  { labelKey: 'folders.filter.created_newest', field: 'created_at', direction: 'desc' },
  { labelKey: 'folders.filter.created_oldest', field: 'created_at', direction: 'asc'  },
  { labelKey: 'folders.filter.size_largest',   field: 'size',       direction: 'desc' },
  { labelKey: 'folders.filter.size_smallest',  field: 'size',       direction: 'asc'  },
  { labelKey: 'folders.filter.type_sort',      field: 'type',       direction: 'asc'  },
];

const TYPE_OPTIONS = [
  { key: 'folders',   labelKey: 'folders.filter.folders',   icon: <FolderOutlined      fontSize="small" sx={{ mr: 1 }} /> },
  { key: 'images',    labelKey: 'folders.filter.images',    icon: <ImageOutlined       fontSize="small" sx={{ mr: 1 }} /> },
  { key: 'videos',    labelKey: 'folders.filter.videos',    icon: <VideocamOutlined    fontSize="small" sx={{ mr: 1 }} /> },
  { key: 'documents', labelKey: 'folders.filter.documents', icon: <DescriptionOutlined fontSize="small" sx={{ mr: 1 }} /> },
  { key: 'audio',     labelKey: 'folders.filter.audio',     icon: <AudioFileOutlined   fontSize="small" sx={{ mr: 1 }} /> },
];

const STATUS_OPTIONS = [
  { key: 'draft',     labelKey: 'folders.filter.draft'     },
  { key: 'published', labelKey: 'folders.filter.published' },
  { key: 'approved',  labelKey: 'folders.filter.approved'  },
  { key: 'rejected',  labelKey: 'folders.filter.rejected'  },
];

export const PER_PAGE_OPTIONS = [25, 50, 100];

const GRID_SIZES = [
  { key: 'small',  label: 'S' },
  { key: 'medium', label: 'M' },
  { key: 'large',  label: 'L' },
];

// ─── Reusable multi-select dropdown ──────────────────────────────────────────
function MultiSelectDropdown({ label, options, selected, onChange, t }) {
  const [anchor, setAnchor] = useState(null);
  const active = selected.length > 0;

  const toggle = (key) =>
    onChange(selected.includes(key) ? selected.filter((k) => k !== key) : [...selected, key]);

  return (
    <>
      <Button
        size="small"
        onClick={(e) => setAnchor(e.currentTarget)}
        endIcon={<KeyboardArrowDown sx={{ fontSize: 16, color: '#94a3b8' }} />}
        sx={{
          textTransform: 'none',
          fontWeight: active ? 700 : 500,
          color: active ? '#4f46e5' : '#475569',
          border: '1px solid',
          borderColor: active ? '#4f46e5' : '#cbd5e1',
          borderRadius: 2,
          px: 1.5,
          py: 0.4,
          bgcolor: active ? '#eef2ff' : 'transparent',
          '&:hover': { bgcolor: active ? '#e0e7ff' : '#f8fafc' },
          whiteSpace: 'nowrap',
          flexShrink: 0,
        }}
      >
        {label}
        {active && (
          <Chip
            label={selected.length}
            size="small"
            sx={{
              ml: 0.75, height: 18, fontSize: 10, fontWeight: 700,
              bgcolor: '#4f46e5', color: '#fff',
              '& .MuiChip-label': { px: 0.75 },
            }}
          />
        )}
      </Button>

      <Menu
        anchorEl={anchor}
        open={Boolean(anchor)}
        onClose={() => setAnchor(null)}
        slotProps={{ paper: { elevation: 3, sx: { mt: 0.5, minWidth: 180, borderRadius: 2 } } }}
      >
        {options.map(({ key, labelKey, icon }) => (
          <MenuItem key={key} dense onClick={() => toggle(key)} sx={{ py: 0.5 }}>
            <Checkbox size="small" checked={selected.includes(key)} sx={{ p: 0.5, mr: 0.5 }} />
            {icon || null}
            <ListItemText primary={<Typography variant="body2">{t(labelKey)}</Typography>} />
          </MenuItem>
        ))}

        {selected.length > 0 && [
          <Divider key="sep" sx={{ my: 0.5 }} />,
          <MenuItem key="clear" dense onClick={() => { onChange([]); setAnchor(null); }}>
            <Typography variant="body2" sx={{ color: '#ef4444', fontWeight: 600, pl: 0.5 }}>
              {t('folders.filter.clear')}
            </Typography>
          </MenuItem>,
        ]}
      </Menu>
    </>
  );
}

// ─── Main filter bar ──────────────────────────────────────────────────────────
export default function AssetFilterBar({
  query,
  onQueryChange,
  typeFilters,
  onTypeFiltersChange,
  statusFilters,
  onStatusFiltersChange,
  sort,
  onSortChange,
  viewLayout,
  onViewLayoutChange,
  gridSize,
  onGridSizeChange,
  resultCount,
  perPage,
  onPerPageChange,
  onShareLink,
}) {
  const { t } = useTranslation();
  const [sortAnchor, setSortAnchor] = useState(null);

  const activeSort = SORT_OPTIONS.find(
    (o) => o.field === sort?.field && o.direction === sort?.direction,
  ) || SORT_OPTIONS[0];

  return (
    <Box sx={{ bgcolor: '#fff', borderBottom: '1px solid #e2e8f0', px: 3, py: 1, mb: 3 }}>
      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
          gap: 1,
          flexWrap: 'nowrap',
          overflowX: 'auto',
          '&::-webkit-scrollbar': { height: 4 },
          '&::-webkit-scrollbar-thumb': { bgcolor: '#e2e8f0', borderRadius: 2 },
        }}
      >
        {/* Search */}
        <TextField
          value={query}
          onChange={(e) => onQueryChange(e.target.value)}
          placeholder={t('folders.filter.search_placeholder')}
          size="small"
          sx={{ width: 200, flexShrink: 0, '& .MuiOutlinedInput-root': { borderRadius: 2 } }}
          slotProps={{
            input: {
              startAdornment: (
                <InputAdornment position="start">
                  <SearchOutlined fontSize="small" sx={{ color: '#94a3b8' }} />
                </InputAdornment>
              ),
            },
          }}
        />

        <Divider orientation="vertical" flexItem sx={{ mx: 0.5 }} />

        {/* Type multi-select */}
        <MultiSelectDropdown
          label={t('folders.filter.type_label')}
          options={TYPE_OPTIONS}
          selected={typeFilters}
          onChange={onTypeFiltersChange}
          t={t}
        />

        {/* Status multi-select */}
        <MultiSelectDropdown
          label={t('folders.filter.status_label')}
          options={STATUS_OPTIONS}
          selected={statusFilters}
          onChange={onStatusFiltersChange}
          t={t}
        />

        {/* Sort */}
        <Button
          size="small"
          variant="outlined"
          onClick={(e) => setSortAnchor(e.currentTarget)}
          endIcon={<Sort fontSize="small" />}
          sx={{
            textTransform: 'none', color: '#475569', borderColor: '#cbd5e1',
            borderRadius: 2, px: 1.5, flexShrink: 0,
            '&:hover': { bgcolor: '#f8fafc' },
          }}
        >
          <Box
            component="span"
            sx={{ fontWeight: 600, maxWidth: 110, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
          >
            {t(activeSort.labelKey)}
          </Box>
        </Button>
        <Menu
          anchorEl={sortAnchor}
          open={Boolean(sortAnchor)}
          onClose={() => setSortAnchor(null)}
          slotProps={{ paper: { elevation: 3, sx: { mt: 0.5, minWidth: 220, borderRadius: 2 } } }}
        >
          {SORT_OPTIONS.map((opt, i) => {
            const isActive = opt.field === sort?.field && opt.direction === sort?.direction;
            const showDivider = i > 0 && SORT_OPTIONS[i - 1].field !== opt.field;
            return [
              showDivider && <Divider key={`d-${opt.labelKey}`} sx={{ my: 0.5 }} />,
              <MenuItem
                key={opt.labelKey}
                selected={isActive}
                dense
                onClick={() => { setSortAnchor(null); onSortChange({ field: opt.field, direction: opt.direction }); }}
              >
                {t(opt.labelKey)}
              </MenuItem>,
            ];
          })}
        </Menu>

        {/* Spacer */}
        <Box sx={{ flexGrow: 1, flexShrink: 1, minWidth: 8 }} />

        {/* Share link */}
        {onShareLink && (
          <Tooltip title={t('folders.filter.share_link', 'Copy shareable link')}>
            <IconButton size="small" onClick={onShareLink} sx={{ color: '#64748b', flexShrink: 0 }}>
              <IosShare fontSize="small" />
            </IconButton>
          </Tooltip>
        )}

        {/* Result count */}
        <Box sx={{ border: '1px solid #e2e8f0', borderRadius: 1.5, px: 1.25, py: 0.4, flexShrink: 0 }}>
          <Typography variant="body2" sx={{ fontWeight: 600, color: '#475569', whiteSpace: 'nowrap' }}>
            {resultCount}{' '}
            <Box component="span" sx={{ fontWeight: 400 }}>{t('folders.filter.results')}</Box>
          </Typography>
        </Box>

        {/* Per-page */}
        <FormControl size="small" sx={{ flexShrink: 0, minWidth: 90 }}>
          <Select
            value={perPage}
            onChange={(e) => onPerPageChange(Number(e.target.value))}
            sx={{
              borderRadius: 2, fontSize: '0.8rem', color: '#475569',
              '& .MuiOutlinedInput-notchedOutline': { borderColor: '#cbd5e1' },
            }}
          >
            {PER_PAGE_OPTIONS.map((n) => (
              <MenuItem key={n} value={n} dense>
                <Typography variant="body2">{n} / {t('folders.filter.per_page', 'page')}</Typography>
              </MenuItem>
            ))}
          </Select>
        </FormControl>

        <Divider orientation="vertical" flexItem sx={{ mx: 0.5 }} />

        {/* S / M / L — grid mode only */}
        {viewLayout === 'grid' && (
          <ToggleButtonGroup
            value={gridSize}
            exclusive
            onChange={(_, v) => v && onGridSizeChange(v)}
            size="small"
            sx={{ flexShrink: 0 }}
          >
            {GRID_SIZES.map(({ key, label }) => (
              <ToggleButton
                key={key}
                value={key}
                sx={{
                  fontWeight: 700, fontSize: '0.7rem', px: 1.25,
                  border: '1px solid #cbd5e1 !important',
                  '&.Mui-selected': { bgcolor: '#334155 !important', color: '#fff !important' },
                }}
              >
                {label}
              </ToggleButton>
            ))}
          </ToggleButtonGroup>
        )}

        {/* Grid / List toggle */}
        <ToggleButtonGroup
          value={viewLayout}
          exclusive
          onChange={(_, v) => v && onViewLayoutChange(v)}
          size="small"
          sx={{ flexShrink: 0 }}
        >
          <ToggleButton
            value="grid"
            sx={{ border: '1px solid #cbd5e1', color: '#64748b', '&.Mui-selected': { bgcolor: '#334155 !important', color: '#fff !important' } }}
          >
            <ViewModule fontSize="small" />
          </ToggleButton>
          <ToggleButton
            value="list"
            sx={{ border: '1px solid #cbd5e1', color: '#64748b', '&.Mui-selected': { bgcolor: '#334155 !important', color: '#fff !important' } }}
          >
            <ViewList fontSize="small" />
          </ToggleButton>
        </ToggleButtonGroup>
      </Box>
    </Box>
  );
}
