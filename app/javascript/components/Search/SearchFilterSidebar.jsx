import React, { useState } from 'react';
import {
  Box, Typography, Chip, TextField, Accordion, AccordionSummary,
  AccordionDetails, IconButton, Tooltip, Badge,
} from '@mui/material';
import {
  ExpandMore, FilterAlt, RestartAlt, Image, Description,
  VideoLibrary, FolderZip, MoreHoriz, AccessTime, Storage,
  Public, CropLandscape, Palette, Videocam, Audiotrack,
  ChevronLeft, ChevronRight, Tune,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

// ── Constants ──────────────────────────────────────────────────────────────────
const EXPANDED_WIDTH  = 260;
const COLLAPSED_WIDTH = 52;

const MIME_GROUPS = [
  { key: 'images',     icon: <Image fontSize="small" />,        color: '#3b82f6' },
  { key: 'documents',  icon: <Description fontSize="small" />,  color: '#f59e0b' },
  { key: 'multimedia', icon: <VideoLibrary fontSize="small" />, color: '#8b5cf6' },
  { key: 'archives',   icon: <FolderZip fontSize="small" />,    color: '#10b981' },
  { key: 'other',      icon: <MoreHoriz fontSize="small" />,    color: '#64748b' },
];

const MODIFIED_OPTIONS     = ['hour', 'day', 'week', 'month', 'year'];
const FILE_SIZE_OPTIONS    = ['small', 'medium', 'large'];
const ORIENTATION_OPTIONS  = ['horizontal', 'vertical', 'square'];
const STYLE_OPTIONS        = ['color', 'black_white'];
const VIDEO_FORMAT_OPTIONS = ['dvi', 'flash', 'mpeg4', 'mpeg', 'ogg', 'quicktime', 'wmv'];
const VIDEO_CODEC_OPTIONS  = ['x264', 'h264', 'h265', 'vp9'];
const AUDIO_CODEC_OPTIONS  = ['libvorbis', 'lame_mp3', 'aac'];

const SECTIONS = [
  { id: 'mime',        icon: <Image />,         labelKey: 'search.filters.mimeType',     color: '#3b82f6', activeKeys: ['mime_group'] },
  { id: 'modified',    icon: <AccessTime />,    labelKey: 'search.filters.lastModified', color: '#f59e0b', activeKeys: ['modified_within'] },
  { id: 'size',        icon: <Storage />,       labelKey: 'search.filters.fileSize',     color: '#10b981', activeKeys: ['file_size_group'] },
  { id: 'status',      icon: <Public />,        labelKey: 'search.filters.status',       color: '#6366f1', activeKeys: ['publish_status', 'approved_status'] },
  { id: 'orientation', icon: <CropLandscape />, labelKey: 'search.filters.orientation',  color: '#0ea5e9', activeKeys: ['orientation'] },
  { id: 'style',       icon: <Palette />,       labelKey: 'search.filters.style',        color: '#ec4899', activeKeys: ['style'] },
  { id: 'video',       icon: <Videocam />,      labelKey: 'search.filters.video',        color: '#8b5cf6', activeKeys: ['video_format', 'video_codec', 'video_height_min', 'video_height_max', 'video_width_min', 'video_width_max', 'video_bitrate_min', 'video_bitrate_max'] },
  { id: 'audio',       icon: <Audiotrack />,    labelKey: 'search.filters.audio',        color: '#f43f5e', activeKeys: ['audio_codec', 'audio_bitrate_min', 'audio_bitrate_max'] },
];

// ── Helpers ────────────────────────────────────────────────────────────────────
function SingleSelect({ options, value, onChange, tPrefix, t }) {
  return (
    <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.75 }}>
      {options.map((opt) => (
        <Chip
          key={opt}
          label={t(`${tPrefix}.${opt}`)}
          size="small"
          variant={value === opt ? 'filled' : 'outlined'}
          color={value === opt ? 'primary' : 'default'}
          onClick={() => onChange(value === opt ? '' : opt)}
          sx={{ cursor: 'pointer', fontWeight: value === opt ? 600 : 400, borderRadius: 1.5 }}
        />
      ))}
    </Box>
  );
}

function RangeFilter({ labelMin, labelMax, valueMin, valueMax, onChangeMin, onChangeMax }) {
  return (
    <Box sx={{ display: 'flex', gap: 1 }}>
      <TextField label={labelMin} size="small" type="number" value={valueMin}
        onChange={(e) => onChangeMin(e.target.value)} sx={{ flex: 1 }}
        slotProps={{ htmlInput: { min: 0 } }} />
      <TextField label={labelMax} size="small" type="number" value={valueMax}
        onChange={(e) => onChangeMax(e.target.value)} sx={{ flex: 1 }}
        slotProps={{ htmlInput: { min: 0 } }} />
    </Box>
  );
}

// ── Main component ─────────────────────────────────────────────────────────────
export default function SearchFilterSidebar({ filters, activeFilterCount, onFilterChange, onReset, metadataFacets = {} }) {
  const { t } = useTranslation();

  const [collapsed, setCollapsed] = useState(() => {
    const saved = localStorage.getItem('dam_search_filters_open');
    return saved !== null ? !JSON.parse(saved) : false;
  });

  const [expanded, setExpanded] = useState(['mime', 'modified', 'size', 'status']);

  const toggleCollapsed = () => {
    setCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem('dam_search_filters_open', JSON.stringify(!next));
      return next;
    });
  };

  const toggle = (panel) =>
    setExpanded((prev) =>
      prev.includes(panel) ? prev.filter((p) => p !== panel) : [...prev, panel]
    );

  const set = (key, val) => onFilterChange({ ...filters, [key]: val });

  // ─────────────────────────────────────────────────────────────────────────────
  // Single Box — width CSS transition (mirrors Sidebar.jsx exactly).
  // overflowX: hidden clips content to the animated width at every frame.
  // Body layers use display:none / display:flex — pure CSS property change,
  // no React remount, so the outer width animation stays uninterrupted.
  // ─────────────────────────────────────────────────────────────────────────────
  return (
    <Box
      sx={{
        width: collapsed ? COLLAPSED_WIDTH : EXPANDED_WIDTH,
        flexShrink: 0,
        height: '100%',
        display: { xs: 'none', md: 'flex' },
        flexDirection: 'column',
        borderRight: '1px solid #e2e8f0',
        bgcolor: '#fff',
        transition: 'width 0.3s ease',  // ← the smooth width animation
        overflowX: 'hidden',            // ← clips content to current width
      }}
    >
      {/* ── Header ─────────────────────────────────────────────────────────── */}
      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          px: 1,
          minHeight: 52,
          flexShrink: 0,
          borderBottom: '1px solid #f1f5f9',
          bgcolor: '#fff',
          position: 'sticky',
          top: 0,
          zIndex: 1,
        }}
      >
        {/* FilterAlt icon — always visible; clicking expands when collapsed */}
        <Tooltip
          title={collapsed ? t('search.filters.expand') : ''}
          placement="right"
          disableHoverListener={!collapsed}
        >
          <IconButton
            size="small"
            onClick={collapsed ? toggleCollapsed : undefined}
            sx={{ color: '#6366f1', flexShrink: 0 }}
          >
            <FilterAlt sx={{ fontSize: 20 }} />
          </IconButton>
        </Tooltip>

        {/* Title — fades with opacity, same as ListItemText in Sidebar.jsx */}
        <Typography
          variant="subtitle2"
          fontWeight={700}
          color="#1e293b"
          sx={{
            flex: 1,
            ml: 1,
            opacity: collapsed ? 0 : 1,
            transition: 'opacity 0.3s ease',
            whiteSpace: 'nowrap',
          }}
        >
          {t('search.filters.title')}
          {activeFilterCount > 0 && (
            <Box
              component="span"
              sx={{
                ml: 1,
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                minWidth: 18,
                height: 18,
                borderRadius: '50%',
                bgcolor: 'primary.main',
                color: '#fff',
                fontSize: '0.65rem',
                fontWeight: 700,
                verticalAlign: 'middle',
              }}
            >
              {activeFilterCount}
            </Box>
          )}
        </Typography>

        {/* Right actions — only rendered when expanded (no layout impact when collapsed) */}
        {!collapsed && (
          <Box sx={{ display: 'flex', gap: 0.5, flexShrink: 0 }}>
            {activeFilterCount > 0 && (
              <Tooltip title={t('search.filters.reset')}>
                <IconButton size="small" onClick={onReset} sx={{ color: '#64748b' }}>
                  <RestartAlt fontSize="small" />
                </IconButton>
              </Tooltip>
            )}
            <Tooltip title={t('search.filters.collapse')}>
              <IconButton
                size="small"
                onClick={toggleCollapsed}
                sx={{ color: '#64748b', '&:hover': { color: '#6366f1' } }}
              >
                <ChevronLeft fontSize="small" />
              </IconButton>
            </Tooltip>
          </Box>
        )}
      </Box>

      {/* ── MINI ICON BAR — shown only when collapsed ──────────────────────── */}
      {/* display:none/flex is a CSS property change — no React remount,       */}
      {/* so the outer width CSS transition continues uninterrupted.            */}
      <Box
        sx={{
          display: collapsed ? 'flex' : 'none',
          flexDirection: 'column',
          alignItems: 'center',
          py: 1,
          gap: 0.5,
          overflowY: 'auto',
          flex: 1,
        }}
      >
        {/* Expand toggle */}
        <Tooltip title={t('search.filters.expand')} placement="right">
          <IconButton
            size="small"
            onClick={toggleCollapsed}
            sx={{
              mb: 0.5,
              color: '#6366f1',
              bgcolor: '#f0f0ff',
              borderRadius: 1.5,
              width: 36,
              height: 36,
              '&:hover': { bgcolor: '#e0e7ff' },
            }}
          >
            <ChevronRight fontSize="small" />
          </IconButton>
        </Tooltip>

        {/* Reset badge */}
        {activeFilterCount > 0 && (
          <Tooltip title={t('search.filters.reset')} placement="right">
            <IconButton
              size="small"
              onClick={onReset}
              sx={{ color: '#ef4444', width: 36, height: 36, borderRadius: 1.5, '&:hover': { bgcolor: '#fee2e2' } }}
            >
              <Badge
                badgeContent={activeFilterCount}
                color="error"
                sx={{ '& .MuiBadge-badge': { fontSize: '0.6rem', minWidth: 14, height: 14 } }}
              >
                <RestartAlt fontSize="small" />
              </Badge>
            </IconButton>
          </Tooltip>
        )}

        <Box sx={{ width: 28, bgcolor: '#e2e8f0', flexShrink: 0, height: '1px', my: 0.5 }} />

        {/* Section icon buttons */}
        {SECTIONS.map((section) => {
          const sectionActive = section.activeKeys.some((k) => filters[k]);
          return (
            <Tooltip key={section.id} title={t(section.labelKey)} placement="right">
              <IconButton
                size="small"
                onClick={toggleCollapsed}
                sx={{
                  width: 36, height: 36, borderRadius: 1.5,
                  color: sectionActive ? '#fff' : '#64748b',
                  bgcolor: sectionActive ? section.color : 'transparent',
                  transition: 'all 0.2s ease',
                  position: 'relative',
                  '&:hover': {
                    bgcolor: sectionActive ? section.color : `${section.color}18`,
                    color: sectionActive ? '#fff' : section.color,
                  },
                }}
              >
                {React.cloneElement(section.icon, { fontSize: 'small' })}
                {sectionActive && (
                  <Box sx={{
                    position: 'absolute', top: 4, right: 4,
                    width: 6, height: 6, borderRadius: '50%',
                    bgcolor: '#fff', border: `1.5px solid ${section.color}`,
                  }} />
                )}
              </IconButton>
            </Tooltip>
          );
        })}

        {/* Dynamic metadata icon (mini bar) — shown when schema fields exist */}
        {Object.keys(metadataFacets).length > 0 && (() => {
          const metaActive = Object.keys(metadataFacets).some((k) => filters[k]);
          return (
            <Tooltip title={t('search.filters.metadata')} placement="right">
              <IconButton
                size="small"
                onClick={toggleCollapsed}
                sx={{
                  width: 36, height: 36, borderRadius: 1.5,
                  color: metaActive ? '#fff' : '#64748b',
                  bgcolor: metaActive ? '#0284c7' : 'transparent',
                  transition: 'all 0.2s ease',
                  position: 'relative',
                  '&:hover': { bgcolor: metaActive ? '#0284c7' : '#0284c718', color: metaActive ? '#fff' : '#0284c7' },
                }}
              >
                <Tune fontSize="small" />
                {metaActive && (
                  <Box sx={{
                    position: 'absolute', top: 4, right: 4,
                    width: 6, height: 6, borderRadius: '50%',
                    bgcolor: '#fff', border: '1.5px solid #0284c7',
                  }} />
                )}
              </IconButton>
            </Tooltip>
          );
        })()}
      </Box>

      {/* ── FULL ACCORDION PANEL — shown only when expanded ────────────────── */}
      <Box
        sx={{
          display: collapsed ? 'none' : 'flex',
          flexDirection: 'column',
          flex: 1,
          overflowY: 'auto',
          overflowX: 'hidden',
          pb: 3,
        }}
      >
        {/* MIME Type */}
        <Accordion expanded={expanded.includes('mime')} onChange={() => toggle('mime')}
          elevation={0} disableGutters sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}>
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Image sx={{ fontSize: 16, color: '#3b82f6' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.mimeType')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2 }}>
            <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.75 }}>
              {MIME_GROUPS.map(({ key, icon, color }) => (
                <Chip key={key}
                  icon={React.cloneElement(icon, { style: { color: filters.mime_group === key ? '#fff' : color } })}
                  label={t(`search.filters.mime.${key}`)}
                  size="small"
                  variant={filters.mime_group === key ? 'filled' : 'outlined'}
                  onClick={() => set('mime_group', filters.mime_group === key ? '' : key)}
                  sx={{
                    cursor: 'pointer', fontWeight: filters.mime_group === key ? 600 : 400, borderRadius: 1.5,
                    borderColor: color, color: filters.mime_group === key ? '#fff' : color,
                    bgcolor: filters.mime_group === key ? color : 'transparent',
                    '&:hover': { bgcolor: filters.mime_group === key ? color : `${color}20` },
                  }}
                />
              ))}
            </Box>
          </AccordionDetails>
        </Accordion>

        {/* Last Modified */}
        <Accordion expanded={expanded.includes('modified')} onChange={() => toggle('modified')}
          elevation={0} disableGutters sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}>
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <AccessTime sx={{ fontSize: 16, color: '#f59e0b' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.lastModified')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2 }}>
            <SingleSelect options={MODIFIED_OPTIONS} value={filters.modified_within || ''}
              onChange={(v) => set('modified_within', v)} tPrefix="search.filters.modified" t={t} />
          </AccordionDetails>
        </Accordion>

        {/* File Size */}
        <Accordion expanded={expanded.includes('size')} onChange={() => toggle('size')}
          elevation={0} disableGutters sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}>
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Storage sx={{ fontSize: 16, color: '#10b981' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.fileSize')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2 }}>
            <SingleSelect options={FILE_SIZE_OPTIONS} value={filters.file_size_group || ''}
              onChange={(v) => set('file_size_group', v)} tPrefix="search.filters.size" t={t} />
          </AccordionDetails>
        </Accordion>

        {/* Status */}
        <Accordion expanded={expanded.includes('status')} onChange={() => toggle('status')}
          elevation={0} disableGutters sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}>
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Public sx={{ fontSize: 16, color: '#6366f1' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.status')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2, display: 'flex', flexDirection: 'column', gap: 1.5 }}>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.5, display: 'block' }}>
                {t('search.filters.publishStatus')}
              </Typography>
              <SingleSelect options={['published', 'unpublished']} value={filters.publish_status || ''}
                onChange={(v) => set('publish_status', v)} tPrefix="search.filters.publish" t={t} />
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.5, display: 'block' }}>
                {t('search.filters.approvedStatus')}
              </Typography>
              <SingleSelect options={['approved', 'rejected']} value={filters.approved_status || ''}
                onChange={(v) => set('approved_status', v)} tPrefix="search.filters.approval" t={t} />
            </Box>
          </AccordionDetails>
        </Accordion>

        {/* Orientation */}
        <Accordion expanded={expanded.includes('orientation')} onChange={() => toggle('orientation')}
          elevation={0} disableGutters sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}>
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <CropLandscape sx={{ fontSize: 16, color: '#0ea5e9' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.orientation')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2 }}>
            <SingleSelect options={ORIENTATION_OPTIONS} value={filters.orientation || ''}
              onChange={(v) => set('orientation', v)} tPrefix="search.filters.orientations" t={t} />
          </AccordionDetails>
        </Accordion>

        {/* Style */}
        <Accordion expanded={expanded.includes('style')} onChange={() => toggle('style')}
          elevation={0} disableGutters sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}>
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Palette sx={{ fontSize: 16, color: '#ec4899' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.style')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2 }}>
            <SingleSelect options={STYLE_OPTIONS} value={filters.style || ''}
              onChange={(v) => set('style', v)} tPrefix="search.filters.styles" t={t} />
          </AccordionDetails>
        </Accordion>

        {/* Video */}
        <Accordion expanded={expanded.includes('video')} onChange={() => toggle('video')}
          elevation={0} disableGutters sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}>
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Videocam sx={{ fontSize: 16, color: '#8b5cf6' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.video')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2, display: 'flex', flexDirection: 'column', gap: 2 }}>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.videoFormat')}
              </Typography>
              <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                {VIDEO_FORMAT_OPTIONS.map((fmt) => (
                  <Chip key={fmt} label={fmt.toUpperCase()} size="small"
                    variant={filters.video_format === fmt ? 'filled' : 'outlined'}
                    color={filters.video_format === fmt ? 'secondary' : 'default'}
                    onClick={() => set('video_format', filters.video_format === fmt ? '' : fmt)}
                    sx={{ cursor: 'pointer', borderRadius: 1, fontWeight: 600, fontSize: '0.7rem' }} />
                ))}
              </Box>
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.videoCodec')}
              </Typography>
              <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                {VIDEO_CODEC_OPTIONS.map((codec) => (
                  <Chip key={codec} label={codec.toUpperCase()} size="small"
                    variant={filters.video_codec === codec ? 'filled' : 'outlined'}
                    color={filters.video_codec === codec ? 'secondary' : 'default'}
                    onClick={() => set('video_codec', filters.video_codec === codec ? '' : codec)}
                    sx={{ cursor: 'pointer', borderRadius: 1, fontWeight: 600, fontSize: '0.7rem' }} />
                ))}
              </Box>
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.videoHeight')} (px)
              </Typography>
              <RangeFilter labelMin={t('search.filters.min')} labelMax={t('search.filters.max')}
                valueMin={filters.video_height_min || ''} valueMax={filters.video_height_max || ''}
                onChangeMin={(v) => set('video_height_min', v)} onChangeMax={(v) => set('video_height_max', v)} />
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.videoWidth')} (px)
              </Typography>
              <RangeFilter labelMin={t('search.filters.min')} labelMax={t('search.filters.max')}
                valueMin={filters.video_width_min || ''} valueMax={filters.video_width_max || ''}
                onChangeMin={(v) => set('video_width_min', v)} onChangeMax={(v) => set('video_width_max', v)} />
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.videoBitrate')} (kbps)
              </Typography>
              <RangeFilter labelMin={t('search.filters.min')} labelMax={t('search.filters.max')}
                valueMin={filters.video_bitrate_min || ''} valueMax={filters.video_bitrate_max || ''}
                onChangeMin={(v) => set('video_bitrate_min', v)} onChangeMax={(v) => set('video_bitrate_max', v)} />
            </Box>
          </AccordionDetails>
        </Accordion>

        {/* Audio */}
        <Accordion expanded={expanded.includes('audio')} onChange={() => toggle('audio')}
          elevation={0} disableGutters sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}>
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Audiotrack sx={{ fontSize: 16, color: '#f43f5e' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.audio')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2, display: 'flex', flexDirection: 'column', gap: 2 }}>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.audioCodec')}
              </Typography>
              <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                {AUDIO_CODEC_OPTIONS.map((codec) => (
                  <Chip key={codec} label={codec.replace('_', ' ')} size="small"
                    variant={filters.audio_codec === codec ? 'filled' : 'outlined'}
                    color={filters.audio_codec === codec ? 'error' : 'default'}
                    onClick={() => set('audio_codec', filters.audio_codec === codec ? '' : codec)}
                    sx={{ cursor: 'pointer', borderRadius: 1, fontWeight: 600, fontSize: '0.7rem' }} />
                ))}
              </Box>
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.audioBitrate')} (kbps)
              </Typography>
              <RangeFilter labelMin={t('search.filters.min')} labelMax={t('search.filters.max')}
                valueMin={filters.audio_bitrate_min || ''} valueMax={filters.audio_bitrate_max || ''}
                onChangeMin={(v) => set('audio_bitrate_min', v)} onChangeMax={(v) => set('audio_bitrate_max', v)} />
            </Box>
          </AccordionDetails>
        </Accordion>

        {/* ── Dynamic Metadata Filters (schema-driven, auto-discovered) ──── */}
        {Object.keys(metadataFacets).length > 0 && (
          <Accordion
            expanded={expanded.includes('metadata')}
            onChange={() => toggle('metadata')}
            elevation={0}
            disableGutters
            sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}
          >
            <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <Tune sx={{ fontSize: 16, color: '#0284c7' }} />
                <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                  {t('search.filters.metadata')}
                </Typography>
              </Box>
            </AccordionSummary>
            <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2, display: 'flex', flexDirection: 'column', gap: 2 }}>
              {Object.entries(metadataFacets).map(([propKey, { label, values }]) => (
                <Box key={propKey}>
                  <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block', fontWeight: 600 }}>
                    {label}
                  </Typography>
                  <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                    {values.map(({ value, count }) => {
                      const isActive = filters[propKey] === value;
                      return (
                        <Chip
                          key={value}
                          label={`${value}${count > 1 ? ` (${count})` : ''}`}
                          size="small"
                          variant={isActive ? 'filled' : 'outlined'}
                          color={isActive ? 'info' : 'default'}
                          onClick={() => set(propKey, isActive ? '' : value)}
                          sx={{
                            cursor: 'pointer',
                            borderRadius: 1.5,
                            fontWeight: isActive ? 600 : 400,
                            fontSize: '0.72rem',
                          }}
                        />
                      );
                    })}
                  </Box>
                </Box>
              ))}
            </AccordionDetails>
          </Accordion>
        )}
      </Box>
    </Box>
  );
}
