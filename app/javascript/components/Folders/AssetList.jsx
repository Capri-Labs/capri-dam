import React from 'react';
import { TableContainer, Table, TableHead, TableRow, TableCell, TableBody, Checkbox, Box, Typography, IconButton, Paper, Tooltip, Stack, Chip } from '@mui/material';
import { InsertPhoto, PictureAsPdf, VideoFile, InsertDriveFile, InfoOutlined, PushPinOutlined, AudioFile } from '@mui/icons-material';

function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  let value = Number(bytes);
  while (value >= 1024 && i < units.length - 1) { value /= 1024; i++; }
  return `${value.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

const STATUS_COLORS = {
  draft:     { bg: '#f1f5f9', color: '#475569' },
  published: { bg: '#dcfce7', color: '#166534' },
  approved:  { bg: '#dbeafe', color: '#1e40af' },
  rejected:  { bg: '#fee2e2', color: '#991b1b' },
  archived:  { bg: '#fef3c7', color: '#92400e' },
};

export default function AssetList({ assets, viewMode, selectedItems, toggleSelection, setSelectedAsset, onPinClick }) {

  const getFileIcon = (contentType) => {
    if (!contentType) return <InsertDriveFile sx={{ color: '#64748b' }} />;
    if (contentType.startsWith('image/')) return <InsertPhoto sx={{ color: '#10b981' }} />;
    if (contentType === 'application/pdf') return <PictureAsPdf sx={{ color: '#ef4444' }} />;
    if (contentType.startsWith('video/')) return <VideoFile sx={{ color: '#3b82f6' }} />;
    if (contentType.startsWith('audio/')) return <AudioFile sx={{ color: '#a855f7' }} />;
    return <InsertDriveFile sx={{ color: '#64748b' }} />;
  };

  return (
    <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', borderRadius: 3, mb: 8 }}>
      <Table size="small">
        <TableHead sx={{ bgcolor: '#f8fafc' }}>
          <TableRow>
            <TableCell padding="checkbox" />
            <TableCell sx={{ fontWeight: 700, color: '#475569', minWidth: 200 }}>Name</TableCell>
            <TableCell sx={{ fontWeight: 700, color: '#475569' }}>Status</TableCell>
            <TableCell sx={{ fontWeight: 700, color: '#475569' }}>Type</TableCell>
            <TableCell sx={{ fontWeight: 700, color: '#475569' }}>Size</TableCell>
            <TableCell sx={{ fontWeight: 700, color: '#475569' }}>Ver.</TableCell>
            <TableCell sx={{ fontWeight: 700, color: '#475569' }}>Modified</TableCell>
            <TableCell sx={{ fontWeight: 700, color: '#475569' }}>Created</TableCell>
            <TableCell align="right" sx={{ fontWeight: 700, color: '#475569' }}>Actions</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {assets.map((asset) => {
            const isSelected = selectedItems.assets.includes(asset.id);
            const displayName = asset.name || asset.title || 'Unknown File';
            let props = {};
            try { props = typeof asset.properties === 'string' ? JSON.parse(asset.properties) : (asset.properties || {}); } catch (e) { /* ignore */ }
            const contentType = props.content_type || asset.content_type || '';
            const status = (asset.status === 'ready' ? 'published' : asset.status) || 'draft';
            const statusStyle = STATUS_COLORS[status] || STATUS_COLORS.draft;
            const fileSize = props.file_size || props.size || asset.size;
            const version = asset.version;

            return (
              <TableRow
                key={asset.id}
                hover
                selected={isSelected}
                sx={{ cursor: 'pointer', '&.Mui-selected': { bgcolor: '#eef2ff' } }}
              >
                <TableCell padding="checkbox">
                  <Checkbox
                    size="small"
                    checked={isSelected}
                    onClick={(e) => { e.stopPropagation(); toggleSelection('assets', asset.id, e); }}
                  />
                </TableCell>

                <TableCell onClick={() => viewMode !== 'bin' && setSelectedAsset(asset)}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                    {getFileIcon(contentType)}
                    <Box>
                      <Typography variant="body2" sx={{ fontWeight: 600, color: '#0f172a' }}>{displayName}</Typography>
                      {props.original_filename && props.original_filename !== displayName && (
                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>{props.original_filename}</Typography>
                      )}
                    </Box>
                  </Box>
                </TableCell>

                <TableCell>
                  <Chip
                    label={status}
                    size="small"
                    sx={{
                      bgcolor: statusStyle.bg,
                      color: statusStyle.color,
                      fontWeight: 700,
                      fontSize: '0.7rem',
                      height: 20,
                      textTransform: 'capitalize',
                    }}
                  />
                </TableCell>

                <TableCell sx={{ color: '#64748b', fontSize: '0.75rem', maxWidth: 140, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {contentType || '—'}
                </TableCell>

                <TableCell sx={{ color: '#475569', whiteSpace: 'nowrap' }}>
                  <Typography variant="body2">{formatBytes(fileSize)}</Typography>
                </TableCell>

                <TableCell sx={{ color: '#475569', textAlign: 'center' }}>
                  {version ? (
                    <Chip label={`v${version}`} size="small" sx={{ height: 20, fontSize: '0.7rem', bgcolor: '#f1f5f9' }} />
                  ) : '—'}
                </TableCell>

                <TableCell sx={{ color: '#64748b', whiteSpace: 'nowrap' }}>
                  {asset.updated_at ? new Date(asset.updated_at).toLocaleDateString() : '—'}
                </TableCell>

                <TableCell sx={{ color: '#64748b', whiteSpace: 'nowrap' }}>
                  {asset.created_at ? new Date(asset.created_at).toLocaleDateString() : '—'}
                </TableCell>

                <TableCell align="right">
                  <Stack direction="row" spacing={0.5} justifyContent="flex-end">
                    <Tooltip title="Pin to Collection">
                      <IconButton size="small" onClick={(e) => { e.preventDefault(); e.stopPropagation(); onPinClick(asset, e); }}>
                        <PushPinOutlined fontSize="small" sx={{ color: '#475569' }} />
                      </IconButton>
                    </Tooltip>
                    <Tooltip title="View Details">
                      <IconButton size="small" onClick={(e) => { e.preventDefault(); e.stopPropagation(); setSelectedAsset(asset); }}>
                        <InfoOutlined fontSize="small" sx={{ color: '#475569' }} />
                      </IconButton>
                    </Tooltip>
                  </Stack>
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </TableContainer>
  );
}