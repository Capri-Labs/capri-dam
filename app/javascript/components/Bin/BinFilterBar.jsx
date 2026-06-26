import React from 'react';
import {
    Box, Typography, InputAdornment, TextField, Chip, Stack, Divider,
    Button, Menu, MenuItem, ToggleButton, ToggleButtonGroup, Checkbox
} from '@mui/material';
import {
    SearchOutlined, Sort, ViewModule, ViewList,
    FolderOutlined, InsertDriveFileOutlined, ImageOutlined,
    VideocamOutlined, DescriptionOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useState } from 'react';

const SORT_OPTIONS = [
    { labelKey: 'bin.sort.deletedNewest', field: 'deleted_at', direction: 'desc' },
    { labelKey: 'bin.sort.deletedOldest', field: 'deleted_at', direction: 'asc'  },
    { labelKey: 'bin.sort.nameAZ',        field: 'name',       direction: 'asc'  },
    { labelKey: 'bin.sort.nameZA',        field: 'name',       direction: 'desc' },
    { labelKey: 'bin.sort.sizeDesc',      field: 'size',       direction: 'desc' },
    { labelKey: 'bin.sort.sizeAsc',       field: 'size',       direction: 'asc'  },
];

const TYPE_FILTERS = [
    { key: 'all',      labelKey: 'bin.filters.all',       icon: null },
    { key: 'asset',    labelKey: 'bin.filters.assets',    icon: <InsertDriveFileOutlined fontSize="small" /> },
    { key: 'folder',   labelKey: 'bin.filters.folders',   icon: <FolderOutlined fontSize="small" /> },
    { key: 'image',    labelKey: 'bin.filters.images',    icon: <ImageOutlined fontSize="small" /> },
    { key: 'video',    labelKey: 'bin.filters.videos',    icon: <VideocamOutlined fontSize="small" /> },
    { key: 'document', labelKey: 'bin.filters.documents', icon: <DescriptionOutlined fontSize="small" /> },
];

const GRID_SIZES = [
    { key: 'small',   label: 'S' },
    { key: 'medium',  label: 'M' },
    { key: 'large',   label: 'L' },
];

export default function BinFilterBar({
    query, onQueryChange,
    typeFilter, onTypeFilterChange,
    sort, onSortChange,
    viewLayout, onViewLayoutChange,
    gridSize, onGridSizeChange,
    resultCount,
    allSelected, hasSelection, onSelectAll, onDeselectAll,
}) {
    const { t } = useTranslation();
    const [sortAnchor, setSortAnchor] = useState(null);

    const activeSort = SORT_OPTIONS.find(
        o => o.field === sort?.field && o.direction === sort?.direction
    ) || SORT_OPTIONS[0];

    return (
        <Box sx={{
            bgcolor: '#fff',
            borderBottom: '1px solid #e2e8f0',
            px: 4, py: 1.5,
        }}>
            {/* ROW 1: Search + Type chips */}
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap', mb: 1.5 }}>

                {/* Select-all checkbox */}
                <Box sx={{ display: 'flex', alignItems: 'center' }}>
                    <Checkbox
                        size="small"
                        checked={allSelected}
                        indeterminate={hasSelection && !allSelected}
                        onChange={allSelected ? onDeselectAll : onSelectAll}
                    />
                </Box>

                {/* Search input */}
                <TextField
                    value={query}
                    onChange={(e) => onQueryChange(e.target.value)}
                    placeholder={t('bin.search')}
                    size="small"
                    sx={{ width: 280, '& .MuiOutlinedInput-root': { borderRadius: 2 } }}
                    slotProps={{
                        input: {
                            startAdornment: (
                                <InputAdornment position="start">
                                    <SearchOutlined fontSize="small" sx={{ color: '#94a3b8' }} />
                                </InputAdornment>
                            ),
                        }
                    }}
                />

                <Divider orientation="vertical" flexItem />

                {/* Type filter chips */}
                <Stack direction="row" spacing={0.75} flexWrap="wrap">
                    {TYPE_FILTERS.map(({ key, labelKey, icon }) => (
                        <Chip
                            key={key}
                            label={t(labelKey)}
                            icon={icon}
                            size="small"
                            onClick={() => onTypeFilterChange(key)}
                            variant={typeFilter === key ? 'filled' : 'outlined'}
                            color={typeFilter === key ? 'primary' : 'default'}
                            sx={{
                                fontWeight: typeFilter === key ? 600 : 400,
                                cursor: 'pointer',
                                '& .MuiChip-icon': { color: typeFilter === key ? 'inherit' : '#64748b' }
                            }}
                        />
                    ))}
                </Stack>
            </Box>

            {/* ROW 2: Result count + Sort + View toggles */}
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
                {/* Result count */}
                <Box sx={{ border: '1px solid #cbd5e1', borderRadius: 1, px: 1.5, py: 0.4, display: 'flex', alignItems: 'center' }}>
                    <Typography variant="body2" sx={{ fontWeight: 600, color: '#475569' }}>
                        {resultCount} <Box component="span" sx={{ fontWeight: 400 }}>{t('bin.results')}</Box>
                    </Typography>
                </Box>

                {/* Sort dropdown */}
                <Button
                    variant="outlined"
                    onClick={(e) => setSortAnchor(e.currentTarget)}
                    endIcon={<Sort fontSize="small" />}
                    size="small"
                    sx={{
                        textTransform: 'none', color: '#475569', borderColor: '#cbd5e1',
                        '&:hover': { bgcolor: '#f1f5f9' }
                    }}
                >
                    {t(activeSort.labelKey)}
                </Button>
                <Menu anchorEl={sortAnchor} open={Boolean(sortAnchor)} onClose={() => setSortAnchor(null)}
                    slotProps={{ paper: { elevation: 3, sx: { mt: 1, minWidth: 220, borderRadius: 2 } } }}>
                    {SORT_OPTIONS.map((opt, i) => {
                        const isActive = opt.field === sort?.field && opt.direction === sort?.direction;
                        const showDiv  = i > 0 && SORT_OPTIONS[i - 1].field !== opt.field;
                        return [
                            showDiv && <Divider key={`d${i}`} sx={{ my: 0.5 }} />,
                            <MenuItem key={opt.labelKey} selected={isActive}
                                onClick={() => { setSortAnchor(null); onSortChange({ field: opt.field, direction: opt.direction }); }}>
                                {t(opt.labelKey)}
                            </MenuItem>
                        ];
                    })}
                </Menu>

                {/* Spacer */}
                <Box sx={{ flexGrow: 1 }} />

                {/* Grid size (only when grid view) */}
                {viewLayout === 'grid' && (
                    <ToggleButtonGroup value={gridSize} exclusive onChange={(_, v) => v && onGridSizeChange(v)} size="small">
                        {GRID_SIZES.map(({ key, label }) => (
                            <ToggleButton key={key} value={key}
                                sx={{
                                    fontWeight: 700, fontSize: '0.7rem', px: 1.5,
                                    border: '1px solid #cbd5e1 !important',
                                    '&.Mui-selected': { bgcolor: '#334155 !important', color: '#fff !important' }
                                }}>
                                {label}
                            </ToggleButton>
                        ))}
                    </ToggleButtonGroup>
                )}

                {/* View layout toggle */}
                <ToggleButtonGroup value={viewLayout} exclusive onChange={(_, v) => v && onViewLayoutChange(v)} size="small">
                    <ToggleButton value="grid"
                        sx={{ border: '1px solid #cbd5e1', color: '#64748b', '&.Mui-selected': { bgcolor: '#334155 !important', color: '#fff !important' } }}>
                        <ViewModule fontSize="small" />
                    </ToggleButton>
                    <ToggleButton value="list"
                        sx={{ border: '1px solid #cbd5e1', color: '#64748b', '&.Mui-selected': { bgcolor: '#334155 !important', color: '#fff !important' } }}>
                        <ViewList fontSize="small" />
                    </ToggleButton>
                </ToggleButtonGroup>
            </Box>
        </Box>
    );
}

