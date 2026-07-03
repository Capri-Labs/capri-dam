import React from 'react';
import { Box, Typography, Grid, Paper, Checkbox, Tooltip, IconButton, Chip, Stack } from '@mui/material';
import { Folder as FolderIcon, InfoOutlined, ScheduleOutlined, InsertDriveFileOutlined } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

// small → more items per row (smaller cards), large → fewer items per row (bigger cards)
const GRID_SIZE_CONFIG = {
  small:  { xs: 6, sm: 4, md: 3, lg: 2 },     // 6 per row on lg
  medium: { xs: 6, sm: 4, md: 3, lg: 3 },     // 4 per row on lg
  large:  { xs: 12, sm: 6, md: 4, lg: 4 },    // 3 per row on lg
};

const CARD_SIZE_CONFIG = {
  small:  { p: 1.5, minHeight: 80,  iconSize: 36, titleVariant: 'body2' },
  medium: { p: 2,   minHeight: 112, iconSize: 48, titleVariant: 'body1' },
  large:  { p: 2.5, minHeight: 130, iconSize: 56, titleVariant: 'h6'    },
};

export default function FolderGrid({ folders, viewMode, selectedItems, toggleSelection, handleNavigate, onFolderInfo, gridSize = 'medium' }) {
  const { t } = useTranslation();
  const tr = (key, defaultValue, options = {}) => {
    const value = t(key, { defaultValue, ...options });
    if (value === key || (options.count != null && value === `${key}:${options.count}`)) {
      return defaultValue.replace(/\{\{(\w+)\}\}/g, (_, token) => options[token] ?? '');
    }
    return value;
  };
  const size = GRID_SIZE_CONFIG[gridSize] || GRID_SIZE_CONFIG.medium;
  const card = CARD_SIZE_CONFIG[gridSize] || CARD_SIZE_CONFIG.medium;

  if (!folders || folders.length === 0) return null;

  return (
    <Box sx={{ mb: 5 }}>
      <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.05em', mb: 2 }}>
        {t('folders.filter.folders')}
      </Typography>
      <Grid container spacing={2}>
        {folders.map((folder) => {
          const isSelected = selectedItems.folders.includes(folder.id);

          return (
            <Grid size={size} key={folder.id}>
              <Paper
                elevation={0}
                onClick={(event) => (viewMode === 'bin' ? toggleSelection('folders', folder.id, event) : handleNavigate(folder.id))}
                sx={{
                  position: 'relative',
                  p: card.p,
                  minHeight: card.minHeight,
                  display: 'flex',
                  flexDirection: 'column',
                  justifyContent: 'space-between',
                  border: isSelected ? '2px solid #4f46e5' : '1px solid #e2e8f0',
                  bgcolor: isSelected ? '#eef2ff' : '#ffffff',
                  borderRadius: '16px',
                  cursor: 'pointer',
                  transition: 'all 0.2s',
                  '&:hover': {
                    borderColor: '#4f46e5',
                    boxShadow: '0 8px 24px rgba(79, 70, 229, 0.08)',
                    '& .folder-info-btn': { opacity: 1 }
                  }
                }}
              >
                <Checkbox
                  size="small"
                  checked={isSelected}
                  onClick={(event) => {
                    event.stopPropagation();
                    toggleSelection('folders', folder.id, event);
                  }}
                  sx={{ position: 'absolute', top: 6, right: 6, p: 0.5 }}
                />

                <Stack direction="row" spacing={1.5} sx={{minWidth: 0, alignItems: 'center'}}>
                  <FolderIcon sx={{ fontSize: card.iconSize, color: '#3b82f6', flexShrink: 0 }} />
                  <Box sx={{ minWidth: 0, flexGrow: 1 }}>
                    <Tooltip title={folder.name} placement="top-start">
                      <Typography variant={card.titleVariant} fontWeight="700" sx={{ color: '#0f172a' }} noWrap>
                        {folder.name}
                      </Typography>
                    </Tooltip>
                    <Stack direction="row" spacing={0.75} sx={{mt: 0.75, flexWrap: 'wrap', gap: 0.5, alignItems: 'center'}}>
                      {typeof folder.subfolder_count === 'number' && (
                      <Tooltip title={tr('folders.subfolder_count_tip', '{{count}} sub-folders', { count: folder.subfolder_count })}>
                          <Chip
                            icon={<FolderIcon sx={{ fontSize: 12, ml: 0.5 }} />}
                            label={folder.subfolder_count}
                            size="small"
                            sx={{ height: 22, fontWeight: 700, bgcolor: '#e0f2fe', color: '#075985', '& .MuiChip-label': { px: 0.75 } }}
                          />
                        </Tooltip>
                      )}
                      {typeof folder.asset_count === 'number' && (
                        <Tooltip title={tr('folders.asset_count_tip', '{{count}} assets', { count: folder.asset_count })}>
                          <Chip
                            icon={<InsertDriveFileOutlined sx={{ fontSize: 12, ml: 0.5 }} />}
                            label={folder.asset_count}
                            size="small"
                            sx={{ height: 22, fontWeight: 700, bgcolor: '#f0fdf4', color: '#166534', '& .MuiChip-label': { px: 0.75 } }}
                          />
                        </Tooltip>
                      )}
                      {gridSize !== 'small' && folder.created_at && (
                        <Tooltip title={new Date(folder.created_at).toLocaleString()}>
                          <ScheduleOutlined sx={{ fontSize: 14, color: '#94a3b8' }} />
                        </Tooltip>
                      )}
                    </Stack>
                  </Box>
                </Stack>

                {viewMode !== 'bin' && onFolderInfo && (
                  <Tooltip title={tr('folderGrid.tooltips.folderProperties', 'Folder properties')}>
                    <IconButton
                      className="folder-info-btn"
                      size="small"
                      onClick={(event) => {
                        event.stopPropagation();
                        onFolderInfo(folder);
                      }}
                      sx={{
                        position: 'absolute',
                        bottom: 6,
                        right: 6,
                        opacity: 0,
                        transition: 'opacity 0.15s',
                        color: '#94a3b8',
                        p: 0.25,
                        '&:hover': { color: '#7c3aed', bgcolor: '#f5f3ff' }
                      }}
                    >
                      <InfoOutlined sx={{ fontSize: 16 }} />
                    </IconButton>
                  </Tooltip>
                )}
              </Paper>
            </Grid>
          );
        })}
      </Grid>
    </Box>
  );
}
