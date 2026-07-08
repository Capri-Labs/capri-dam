import React from 'react';
import {
  Box,
  ImageList,
  ImageListItem,
  Checkbox,
  IconButton,
  Tooltip,
  Typography,
  Stack,
  Chip
} from '@mui/material';
import {
  PictureAsPdf,
  VideoFile,
  InsertDriveFile,
  InfoOutlined,
  PushPinOutlined,
  CheckCircle,
  EditNote,
  ErrorOutlined,
  ImageSearchOutlined,
  AutoAwesomeOutlined,
  Publish,
  AudiotrackOutlined,
  HourglassTopOutlined,
  BrokenImageOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const GRID_SIZE_CONFIG = {
  small: { minWidth: 140, height: 140 },
  medium: { minWidth: 200, height: 200 },
  large: { minWidth: 260, height: 260 },
};

const formatBytes = (size) => {
  if (!size) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  const index = Math.min(Math.floor(Math.log(size) / Math.log(1024)), units.length - 1);
  const value = size / (1024 ** index);
  return `${value >= 10 || index === 0 ? Math.round(value) : value.toFixed(1)} ${units[index]}`;
};

const getStatusConfig = (status, t) => {
  switch (status) {
    case 'published':
    case 'ready':
      return { tone: '#166534', background: '#dcfce7', icon: <Publish fontSize="small" />, label: t('folders.filter.published') };
    case 'approved':
      return { tone: '#166534', background: '#dcfce7', icon: <CheckCircle fontSize="small" />, label: t('folders.filter.approved') };
    case 'rejected':
    case 'failed':
      return { tone: '#991b1b', background: '#fee2e2', icon: <ErrorOutlined fontSize="small" />, label: t('folders.filter.rejected') };
    case 'draft':
      return { tone: '#475569', background: '#e2e8f0', icon: <EditNote fontSize="small" />, label: t('folders.filter.draft') };
    case 'pending':
    case 'processing':
      return { tone: '#92400e', background: '#fef3c7', icon: <HourglassTopOutlined fontSize="small" />, label: t('folders.grid.processing', { defaultValue: 'Processing…' }) };
    default:
      return null;
  }
};

// Renders a single grid-cell thumbnail with three mutually-exclusive states:
//   1. Processing  — the asset's background worker (AssetProcessorWorker) has
//      not finished yet (`status` is "pending"/"processing"); we deliberately
//      avoid attempting to load an image at all, since the preview endpoint
//      is guaranteed to 404 until processing completes.
//   2. Loaded image — the normal case; falls back to state 3 via `onError` if
//      the URL 404s or the file is missing on disk (e.g. storage drift).
//   3. Fallback icon — no source available, or the image failed to load.
function AssetThumbnail({ imageSrc, displayName, isPdf, isVideo, isAudio, isProcessing, t }) {
  const [imgError, setImgError] = React.useState(false);

  if (isProcessing) {
    return (
      <Box sx={{ height: '100%', width: '100%', bgcolor: '#f8fafc', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 0.5 }}>
        <HourglassTopOutlined sx={{ fontSize: 40, color: '#94a3b8' }} />
        <Typography variant="caption" sx={{ color: '#94a3b8', fontWeight: 600 }}>
          {t('folders.grid.processing', { defaultValue: 'Processing…' })}
        </Typography>
      </Box>
    );
  }

  if (imageSrc && !imgError) {
    return (
      <img
        src={imageSrc}
        alt={displayName}
        loading="lazy"
        onError={() => setImgError(true)}
        style={{ height: '100%', width: '100%', objectFit: 'cover' }}
      />
    );
  }

  return (
    <Box sx={{ height: '100%', width: '100%', bgcolor: '#f8fafc', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 0.5 }}>
      {imgError ? (
        <>
          <BrokenImageOutlined sx={{ fontSize: 48, color: '#94a3b8' }} />
          <Typography variant="caption" sx={{ color: '#94a3b8' }}>
            {t('folders.grid.previewUnavailable', { defaultValue: 'Preview unavailable' })}
          </Typography>
        </>
      ) : (
        <>
          {isPdf && <PictureAsPdf sx={{ fontSize: 64, color: '#ef4444' }} />}
          {isVideo && <VideoFile sx={{ fontSize: 64, color: '#3b82f6' }} />}
          {isAudio && <AudiotrackOutlined sx={{ fontSize: 64, color: '#8b5cf6' }} />}
          {!isPdf && !isVideo && !isAudio && <InsertDriveFile sx={{ fontSize: 64, color: '#64748b' }} />}
        </>
      )}
    </Box>
  );
}

export default function AssetGrid({
  assets,
  viewMode,
  selectedItems,
  toggleSelection,
  setSelectedAsset,
  onPinClick,
  onFindDuplicates,
  onAiAnalysis,
  gridSize = 'medium',
}) {
  const { t } = useTranslation();
  const translate = (key, fallback) => {
    const value = t(key);
    return value === key ? fallback : value;
  };
  const cardConfig = GRID_SIZE_CONFIG[gridSize] || GRID_SIZE_CONFIG.medium;

  return (
    <ImageList
      gap={16}
      variant="quilted"
      sx={{
        mb: 8,
        overflow: 'visible',
        gridTemplateColumns: `repeat(auto-fill, minmax(${cardConfig.minWidth}px, 1fr)) !important`
      }}
    >
      {assets.map((asset) => {
        const metadata = asset.properties || {};
        const displayName = asset.name || asset.title || translate('folders.grid.unknown_file', 'Unknown File');
        const contentType = asset.content_type || metadata.content_type || '';
        const isImage = contentType.startsWith('image/');
        const hasGeneratedPreview = Boolean(
          metadata.preview_storage_path || metadata.preview_content_type
        );
        const isPdf = contentType === 'application/pdf';
        const isVideo = contentType.startsWith('video/');
        const isAudio = contentType.startsWith('audio/');
        const isSelected = selectedItems.assets.includes(asset.id);
        const statusConfig = getStatusConfig(asset.status, t);
        const sizeLabel = formatBytes(asset.size || metadata.size || metadata.file_size);
        // Prefer the web-renderable preview (e.g. a flattened PNG generated for
        // PSD/TIFF/HEIC) so non-browser-native formats still show a thumbnail.
        const displaySrc = asset.preview_url || asset.url;
        const imageSrc = displaySrc
          ? `${displaySrc}${displaySrc.includes('?') ? '&' : '?'}w=640&fit=crop&auto=format`
          : null;
        // The background worker (AssetProcessorWorker) hasn't finished yet —
        // any preview/download URL is guaranteed to 404 until it does, so we
        // show a "Processing…" placeholder instead of attempting to load one.
        const isProcessing = asset.status === 'pending' || asset.status === 'processing';

        return (
          <ImageListItem
            key={asset.id}
            sx={{
              borderRadius: '16px',
              overflow: 'hidden',
              border: isSelected ? '2px solid #4f46e5' : '1px solid #e2e8f0',
              bgcolor: '#ffffff',
              boxShadow: '0 8px 24px rgba(15, 23, 42, 0.06)',
              transition: 'transform 0.2s ease, box-shadow 0.2s ease',
              '&:hover': { transform: 'translateY(-2px)', boxShadow: '0 12px 28px rgba(15, 23, 42, 0.12)' }
            }}
          >
            <Box sx={{ position: 'absolute', top: 8, left: 8, zIndex: 10 }}>
              <Checkbox
                size="small"
                checked={isSelected}
                onClick={(event) => {
                  event.stopPropagation();
                  toggleSelection('assets', asset.id, event);
                }}
                sx={{
                  color: 'rgba(255,255,255,0.8)',
                  bgcolor: isSelected ? 'rgba(255,255,255,0.9)' : 'rgba(15,23,42,0.25)',
                  borderRadius: '6px',
                  p: 0.5,
                  '&:hover': { bgcolor: 'rgba(255,255,255,0.95)' }
                }}
              />
            </Box>

            {statusConfig && (
              <Box sx={{ position: 'absolute', top: 10, right: 10, zIndex: 10 }}>
                <Chip
                  icon={statusConfig.icon}
                  label={statusConfig.label}
                  size="small"
                  sx={{
                    fontWeight: 700,
                    bgcolor: statusConfig.background,
                    color: statusConfig.tone,
                    '& .MuiChip-icon': { color: statusConfig.tone }
                  }}
                />
              </Box>
            )}

            <Box
              onClick={(event) => {
                event.stopPropagation();
                if (viewMode === 'bin') {
                  toggleSelection('assets', asset.id, event);
                } else {
                  setSelectedAsset(asset);
                }
              }}
              sx={{ position: 'relative', width: '100%', height: cardConfig.height, cursor: 'pointer' }}
            >
              {isProcessing ? (
                <AssetThumbnail isProcessing t={t} />
              ) : (isImage || hasGeneratedPreview) && imageSrc ? (
                <AssetThumbnail
                  imageSrc={imageSrc}
                  displayName={displayName}
                  isPdf={isPdf}
                  isVideo={isVideo}
                  isAudio={isAudio}
                  t={t}
                />
              ) : (
                <Box sx={{ height: '100%', width: '100%', bgcolor: '#f8fafc', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  {isPdf && <PictureAsPdf sx={{ fontSize: 64, color: '#ef4444' }} />}
                  {isVideo && <VideoFile sx={{ fontSize: 64, color: '#3b82f6' }} />}
                  {isAudio && <AudiotrackOutlined sx={{ fontSize: 64, color: '#8b5cf6' }} />}
                  {!isPdf && !isVideo && !isAudio && <InsertDriveFile sx={{ fontSize: 64, color: '#64748b' }} />}
                </Box>
              )}

              <Box sx={{ position: 'absolute', inset: 0, background: 'linear-gradient(to top, rgba(15, 23, 42, 0.72), rgba(15, 23, 42, 0.12) 45%, rgba(15, 23, 42, 0))' }} />

              <Stack direction="row" spacing={0.5} sx={{ position: 'absolute', right: 8, bottom: 8, zIndex: 10 }}>
                {viewMode !== 'bin' && (
                  <>
                    <Tooltip title={t('folders.ai.title')}>
                      <IconButton
                        size="small"
                        sx={{ color: '#fff', bgcolor: 'rgba(15,23,42,0.32)' }}
                        onClick={(event) => {
                          event.stopPropagation();
                          onAiAnalysis?.(asset);
                        }}
                        data-testid="asset-ai-analysis-toggle"
                      >
                        <AutoAwesomeOutlined fontSize="small" />
                      </IconButton>
                    </Tooltip>

                    <Tooltip title={t('folders.duplicates.title')}>
                      <IconButton
                        size="small"
                        sx={{ color: '#fff', bgcolor: 'rgba(15,23,42,0.32)' }}
                        onClick={(event) => {
                          event.stopPropagation();
                          onFindDuplicates?.(asset);
                        }}
                      >
                        <ImageSearchOutlined fontSize="small" />
                      </IconButton>
                    </Tooltip>

                    <Tooltip title={translate('folders.grid.pin_to_collection', 'Pin to Collection')}>
                      <IconButton
                        size="small"
                        sx={{ color: '#fff', bgcolor: 'rgba(15,23,42,0.32)' }}
                        onClick={(event) => {
                          event.stopPropagation();
                          onPinClick(asset, event);
                        }}
                      >
                        <PushPinOutlined fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  </>
                )}

                <Tooltip title={translate('folders.grid.view_details', 'View Details')}>
                  <IconButton
                    size="small"
                    sx={{ color: '#fff', bgcolor: 'rgba(15,23,42,0.32)' }}
                    onClick={(event) => {
                      event.stopPropagation();
                      setSelectedAsset(asset);
                    }}
                  >
                    <InfoOutlined fontSize="small" />
                  </IconButton>
                </Tooltip>
              </Stack>
            </Box>

            <Box sx={{ p: 1.5 }}>
              <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#0f172a' }} noWrap>
                {displayName}
              </Typography>
              <Stack direction="row" sx={{ mt: 0.75, justifyContent: 'space-between', alignItems: 'center' }}>
                <Typography variant="caption" sx={{ color: '#64748b' }} noWrap>
                  {contentType.split('/')[1] || contentType || '—'}
                </Typography>
                <Typography variant="caption" sx={{ color: '#64748b', fontWeight: 600 }}>
                  {sizeLabel}
                </Typography>
              </Stack>
            </Box>
          </ImageListItem>
        );
      })}
    </ImageList>
  );
}
