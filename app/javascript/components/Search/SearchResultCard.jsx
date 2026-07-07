import React, { useState } from 'react';
import {
  Box, Card, CardContent, Typography,
  Chip, Tooltip, Skeleton,
} from '@mui/material';
import {
  InsertDriveFile, Image as ImageIcon, VideoFile, AudioFile,
  Description, FolderZip, CheckCircle, Cancel, RadioButtonUnchecked,
  AccessTime, DeleteOutlineOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const typeIcon = (contentType) => {
  if (!contentType) return <InsertDriveFile />;
  if (contentType.startsWith('image/')) return <ImageIcon sx={{ color: '#3b82f6' }} />;
  if (contentType.startsWith('video/')) return <VideoFile sx={{ color: '#8b5cf6' }} />;
  if (contentType.startsWith('audio/')) return <AudioFile sx={{ color: '#f43f5e' }} />;
  if (contentType.includes('pdf') || contentType.includes('document') || contentType.startsWith('text/')) {
    return <Description sx={{ color: '#f59e0b' }} />;
  }
  if (contentType.includes('zip') || contentType.includes('tar')) {
    return <FolderZip sx={{ color: '#10b981' }} />;
  }
  return <InsertDriveFile sx={{ color: '#64748b' }} />;
};

function StatusChip({ status, t }) {
  const configs = {
    active: { label: t('search.status.published'), color: '#10b981', bg: '#d1fae5', icon: <CheckCircle sx={{ fontSize: 12 }} /> },
    approved: { label: t('search.status.approved'), color: '#3b82f6', bg: '#dbeafe', icon: <CheckCircle sx={{ fontSize: 12 }} /> },
    rejected: { label: t('search.status.rejected'), color: '#ef4444', bg: '#fee2e2', icon: <Cancel sx={{ fontSize: 12 }} /> },
    in_review: { label: t('search.status.inReview'), color: '#f59e0b', bg: '#fef3c7', icon: <RadioButtonUnchecked sx={{ fontSize: 12 }} /> },
  };
  const config = configs[status];
  if (!config) return null;

  return (
    <Chip
      icon={config.icon}
      label={config.label}
      size="small"
      sx={{
        height: 20,
        fontSize: '0.65rem',
        fontWeight: 600,
        color: config.color,
        bgcolor: config.bg,
        border: 'none',
        '& .MuiChip-icon': { color: config.color, ml: '4px' },
      }}
    />
  );
}

// Only rendered when the result is a soft-deleted (Recycle Bin) asset —
// i.e. the caller opted in via the Search screen's "Include Recycle Bin"
// toggle (`?include_bin=true`); regular results never show this.
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

export default function SearchResultCard({ asset, viewMode = 'grid', onClick }) {
  const { t } = useTranslation();
  const [previewFailed, setPreviewFailed] = useState(false);
  // `preview_url` is a generated flattened-PNG preview for formats a browser
  // can't decode natively (PSD, TIFF, HEIC, RAW, PDF, AI, EPS, ...); it falls
  // back to `thumb_url`/`url` for plain web-renderable images. Any content
  // type can have a usable preview, so we no longer gate rendering on
  // `content_type` starting with "image/" — we just try the URL and fall back
  // to the file-type icon if it fails to load (e.g. preview not yet generated).
  const previewSrc = asset.preview_url || asset.thumb_url || asset.url;
  const showPreview = Boolean(previewSrc) && !previewFailed;
  const updatedAt = asset.updated_at ? new Date(asset.updated_at).toLocaleDateString() : null;

  if (viewMode === 'list') {
    return (
      <Card
        elevation={0}
        onClick={() => onClick?.(asset)}
        sx={{
          border: '1px solid #e2e8f0',
          borderRadius: 2,
          cursor: 'pointer',
          '&:hover': { borderColor: '#6366f1', boxShadow: '0 4px 12px rgba(99,102,241,0.1)' },
          transition: 'all 0.2s ease',
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'center', p: 2, gap: 2 }}>
          <Box
            sx={{
              width: 56,
              height: 56,
              flexShrink: 0,
              borderRadius: 1.5,
              overflow: 'hidden',
              bgcolor: '#f1f5f9',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            {showPreview ? (
              <img
                src={previewSrc}
                alt={asset.title}
                style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                onError={() => setPreviewFailed(true)}
              />
            ) : (
              typeIcon(asset.content_type)
            )}
          </Box>
          <Box sx={{ flex: 1, minWidth: 0 }}>
            <Typography variant="body2" fontWeight={600} noWrap color="#1e293b">{asset.title}</Typography>
            <Typography variant="caption" color="textSecondary" noWrap>{asset.content_type}</Typography>
          </Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
            <StatusChip status={asset.status} t={t} />
            {asset.in_bin && <BinChip t={t} />}
            <Typography variant="caption" color="textSecondary">{asset.size}</Typography>
            {updatedAt && (
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                <AccessTime sx={{ fontSize: 12, color: '#94a3b8' }} />
                <Typography variant="caption" color="textSecondary">{updatedAt}</Typography>
              </Box>
            )}
            {asset.width && asset.height && (
              <Typography variant="caption" color="textSecondary">{asset.width}×{asset.height}</Typography>
            )}
          </Box>
        </Box>
      </Card>
    );
  }

  return (
    <Card
      elevation={0}
      onClick={() => onClick?.(asset)}
      sx={{
        border: '1px solid #e2e8f0',
        borderRadius: 2,
        cursor: 'pointer',
        overflow: 'hidden',
        '&:hover': {
          borderColor: '#6366f1',
          boxShadow: '0 8px 24px rgba(99,102,241,0.12)',
          transform: 'translateY(-2px)',
        },
        transition: 'all 0.2s ease',
      }}
    >
      <Box
        sx={{
          position: 'relative',
          height: 160,
          bgcolor: '#f8fafc',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          overflow: 'hidden',
        }}
      >
        {showPreview ? (
          <img
            src={previewSrc}
            alt={asset.title}
            style={{ width: '100%', height: '100%', objectFit: 'cover' }}
            loading="lazy"
            onError={() => setPreviewFailed(true)}
          />
        ) : (
          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 1 }}>
            <Box sx={{ fontSize: 40 }}>{typeIcon(asset.content_type)}</Box>
            <Typography variant="caption" color="textSecondary">
              {asset.content_type?.split('/')[1]?.toUpperCase() || t('search.fileLabel')}
            </Typography>
          </Box>
        )}
        <Box sx={{ position: 'absolute', top: 8, right: 8, display: 'flex', gap: 0.5 }}>
          {asset.in_bin && <BinChip t={t} />}
          <StatusChip status={asset.status} t={t} />
        </Box>
      </Box>

      <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
        <Tooltip title={asset.title} placement="top">
          <Typography variant="body2" fontWeight={600} noWrap color="#1e293b" sx={{ mb: 0.5 }}>
            {asset.title}
          </Typography>
        </Tooltip>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Typography variant="caption" color="textSecondary">{asset.size}</Typography>
          {asset.width && asset.height && (
            <Typography variant="caption" color="textSecondary">{asset.width}×{asset.height}</Typography>
          )}
        </Box>
        {updatedAt && (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mt: 0.5 }}>
            <AccessTime sx={{ fontSize: 11, color: '#94a3b8' }} />
            <Typography variant="caption" color="textSecondary">{updatedAt}</Typography>
          </Box>
        )}
        {asset.metadata?.brand && (
          <Chip
            label={asset.metadata.brand}
            size="small"
            variant="outlined"
            sx={{ mt: 0.75, height: 18, fontSize: '0.65rem', borderRadius: 1 }}
          />
        )}
      </CardContent>
    </Card>
  );
}

export function SearchResultCardSkeleton({ viewMode = 'grid' }) {
  if (viewMode === 'list') {
    return (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, p: 2, border: '1px solid #e2e8f0', borderRadius: 2 }}>
        <Skeleton variant="rounded" width={56} height={56} />
        <Box sx={{ flex: 1 }}>
          <Skeleton variant="text" width="60%" />
          <Skeleton variant="text" width="40%" />
        </Box>
        <Skeleton variant="rounded" width={60} height={20} />
      </Box>
    );
  }

  return (
    <Box sx={{ border: '1px solid #e2e8f0', borderRadius: 2, overflow: 'hidden' }}>
      <Skeleton variant="rectangular" height={160} />
      <Box sx={{ p: 2 }}>
        <Skeleton variant="text" width="70%" />
        <Skeleton variant="text" width="40%" />
      </Box>
    </Box>
  );
}
