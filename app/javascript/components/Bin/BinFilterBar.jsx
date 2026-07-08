import React from 'react';
import {
    Box, Typography, InputAdornment, TextField, Divider,
    Button, Menu, MenuItem, ToggleButton, ToggleButtonGroup, Checkbox,
    Select, FormControl,
} from '@mui/material';
import {
    SearchOutlined, Sort, ViewModule, ViewList, KeyboardArrowDown,
    FolderOutlined, InsertDriveFileOutlined, ImageOutlined,
    VideocamOutlined, DescriptionOutlined, CategoryOutlined,
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
    { key: 'asset',    labelKey: 'bin.filters.assets',    icon: <InsertDriveFileOutlined fontSize="small" sx={{ mr: 1 }} /> },
    { key: 'folder',   labelKey: 'bin.filters.folders',   icon: <FolderOutlined fontSize="small" sx={{ mr: 1 }} /> },
    { key: 'image',    labelKey: 'bin.filters.images',    icon: <ImageOutlined fontSize="small" sx={{ mr: 1 }} /> },
    { key: 'video',    labelKey: 'bin.filters.videos',    icon: <VideocamOutlined fontSize="small" sx={{ mr: 1 }} /> },
    { key: 'document', labelKey: 'bin.filters.documents', icon: <DescriptionOutlined fontSize="small" sx={{ mr: 1 }} /> },
    { key: 'other',    labelKey: 'bin.filters.others',    icon: <CategoryOutlined fontSize="small" sx={{ mr: 1 }} /> },
];

const GRID_SIZES = [
    { key: 'small',   label: 'S' },
    { key: 'medium',  label: 'M' },
    { key: 'large',   label: 'L' },
];

export const PER_PAGE_OPTIONS = [ 25, 50, 100 ];

export default function BinFilterBar({
    query, onQueryChange,
    typeFilter, onTypeFilterChange,
    sort, onSortChange,
    viewLayout, onViewLayoutChange,
    gridSize, onGridSizeChange,
    resultCount,
    perPage, onPerPageChange,
    allSelected, hasSelection, onSelectAll, onDeselectAll,
}) {
    const { t } = useTranslation();
    const [sortAnchor, setSortAnchor] = useState(null);
    const [typeAnchor, setTypeAnchor] = useState(null);

    const activeSort = SORT_OPTIONS.find(
        o => o.field === sort?.field && o.direction === sort?.direction
    ) || SORT_OPTIONS[0];

    const activeType = TYPE_FILTERS.find(o => o.key === typeFilter) || TYPE_FILTERS[0];

    return (
        <Box sx={{
            bgcolor: '#fff',
            borderBottom: '1px solid #e2e8f0',
            px: 4, py: 1.25,
        }}>
            {/* Single row: select-all, search, type filter, sort, results,
                per-page, grid size, view toggle — kept on one line so the
                page saves vertical space. */}
            <Box sx={{
                display: 'flex', alignItems: 'center', gap: 1,
                flexWrap: 'nowrap', overflowX: 'auto',
                '&::-webkit-scrollbar': { height: 4 },
                '&::-webkit-scrollbar-thumb': { bgcolor: '#e2e8f0', borderRadius: 2 },
            }}>
                {/* Select-all checkbox */}
                <Checkbox
                    size="small"
                    checked={allSelected}
                    indeterminate={hasSelection && !allSelected}
                    onChange={allSelected ? onDeselectAll : onSelectAll}
                    sx={{ flexShrink: 0 }}
                />

                {/* Search input */}
                <TextField
                    value={query}
                    onChange={(e) => onQueryChange(e.target.value)}
                    placeholder={t('bin.search')}
                    size="small"
                    sx={{ width: 220, flexShrink: 0, '& .MuiOutlinedInput-root': { borderRadius: 2 } }}
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

                <Divider orientation="vertical" flexItem sx={{ mx: 0.5 }} />

                {/* Type filter dropdown */}
                <Button
                    size="small"
                    onClick={(e) => setTypeAnchor(e.currentTarget)}
                    endIcon={<KeyboardArrowDown sx={{ fontSize: 16, color: '#94a3b8' }} />}
                    sx={{
                        textTransform: 'none',
                        fontWeight: typeFilter !== 'all' ? 700 : 500,
                        color: typeFilter !== 'all' ? '#4f46e5' : '#475569',
                        border: '1px solid',
                        borderColor: typeFilter !== 'all' ? '#4f46e5' : '#cbd5e1',
                        borderRadius: 2, px: 1.5, py: 0.4, flexShrink: 0,
                        bgcolor: typeFilter !== 'all' ? '#eef2ff' : 'transparent',
                        '&:hover': { bgcolor: typeFilter !== 'all' ? '#e0e7ff' : '#f8fafc' },
                        whiteSpace: 'nowrap',
                    }}
                >
                    {activeType.icon}
                    {t(activeType.labelKey)}
                </Button>
                <Menu anchorEl={typeAnchor} open={Boolean(typeAnchor)} onClose={() => setTypeAnchor(null)}
                    slotProps={{ paper: { elevation: 3, sx: { mt: 0.5, minWidth: 200, borderRadius: 2 } } }}>
                    {TYPE_FILTERS.map(({ key, labelKey, icon }) => (
                        <MenuItem key={key} dense selected={typeFilter === key}
                            onClick={() => { setTypeAnchor(null); onTypeFilterChange(key); }}>
                            {icon}
                            {t(labelKey)}
                        </MenuItem>
                    ))}
                </Menu>

                {/* Sort dropdown */}
                <Button
                    variant="outlined"
                    onClick={(e) => setSortAnchor(e.currentTarget)}
                    endIcon={<Sort fontSize="small" />}
                    size="small"
                    sx={{
                        textTransform: 'none', color: '#475569', borderColor: '#cbd5e1',
                        borderRadius: 2, px: 1.5, flexShrink: 0,
                        '&:hover': { bgcolor: '#f1f5f9' }
                    }}
                >
                    <Box component="span" sx={{ fontWeight: 600, maxWidth: 130, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {t(activeSort.labelKey)}
                    </Box>
                </Button>
                <Menu anchorEl={sortAnchor} open={Boolean(sortAnchor)} onClose={() => setSortAnchor(null)}
                    slotProps={{ paper: { elevation: 3, sx: { mt: 1, minWidth: 220, borderRadius: 2 } } }}>
                    {SORT_OPTIONS.map((opt, i) => {
                        const isActive = opt.field === sort?.field && opt.direction === sort?.direction;
                        const showDiv  = i > 0 && SORT_OPTIONS[i - 1].field !== opt.field;
                        return [
                            showDiv && <Divider key={`d${i}`} sx={{ my: 0.5 }} />,
                            <MenuItem key={opt.labelKey} selected={isActive} dense
                                onClick={() => { setSortAnchor(null); onSortChange({ field: opt.field, direction: opt.direction }); }}>
                                {t(opt.labelKey)}
                            </MenuItem>
                        ];
                    })}
                </Menu>

                {/* Spacer */}
                <Box sx={{ flexGrow: 1, flexShrink: 1, minWidth: 8 }} />

                {/* Result count */}
                <Box sx={{ border: '1px solid #cbd5e1', borderRadius: 1.5, px: 1.25, py: 0.4, flexShrink: 0 }}>
                    <Typography variant="body2" sx={{ fontWeight: 600, color: '#475569', whiteSpace: 'nowrap' }}>
                        {resultCount} <Box component="span" sx={{ fontWeight: 400 }}>{t('bin.results')}</Box>
                    </Typography>
                </Box>

                {/* Per-page selector */}
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
                                <Typography variant="body2">{n} / {t('bin.perPage')}</Typography>
                            </MenuItem>
                        ))}
                    </Select>
                </FormControl>

                <Divider orientation="vertical" flexItem sx={{ mx: 0.5 }} />

                {/* Grid size (only when grid view) */}
                {viewLayout === 'grid' && (
                    <ToggleButtonGroup value={gridSize} exclusive onChange={(_, v) => v && onGridSizeChange(v)} size="small" sx={{ flexShrink: 0 }}>
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
                <ToggleButtonGroup value={viewLayout} exclusive onChange={(_, v) => v && onViewLayoutChange(v)} size="small" sx={{ flexShrink: 0 }}>
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
