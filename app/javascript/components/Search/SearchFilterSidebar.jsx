import React, { useState } from 'react';
import {
  Box, Typography, Chip, TextField, Accordion,
  AccordionSummary, AccordionDetails, Badge, IconButton, Tooltip,
} from '@mui/material';
import {
  ExpandMore, FilterAlt, RestartAlt, Image, Description,
  VideoLibrary, FolderZip, MoreHoriz, AccessTime, Storage,
  Public, CropLandscape, Palette, Videocam, Audiotrack,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const MIME_GROUPS = [
  { key: 'images', icon: <Image fontSize="small" />, color: '#3b82f6' },
  { key: 'documents', icon: <Description fontSize="small" />, color: '#f59e0b' },
  { key: 'multimedia', icon: <VideoLibrary fontSize="small" />, color: '#8b5cf6' },
  { key: 'archives', icon: <FolderZip fontSize="small" />, color: '#10b981' },
  { key: 'other', icon: <MoreHoriz fontSize="small" />, color: '#64748b' },
];

const MODIFIED_OPTIONS = ['hour', 'day', 'week', 'month', 'year'];
const FILE_SIZE_OPTIONS = ['small', 'medium', 'large'];
const ORIENTATION_OPTIONS = ['horizontal', 'vertical', 'square'];
const STYLE_OPTIONS = ['color', 'black_white'];
const VIDEO_FORMAT_OPTIONS = ['dvi', 'flash', 'mpeg4', 'mpeg', 'ogg', 'quicktime', 'wmv'];
const VIDEO_CODEC_OPTIONS = ['x264', 'h264', 'h265', 'vp9'];
const AUDIO_CODEC_OPTIONS = ['libvorbis', 'lame_mp3', 'aac'];

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
          sx={{
            cursor: 'pointer',
            fontWeight: value === opt ? 600 : 400,
            borderRadius: 1.5,
          }}
        />
      ))}
    </Box>
  );
}

function RangeFilter({ labelMin, labelMax, valueMin, valueMax, onChangeMin, onChangeMax }) {
  return (
    <Box sx={{ display: 'flex', gap: 1 }}>
      <TextField
        label={labelMin}
        size="small"
        type="number"
        value={valueMin}
        onChange={(event) => onChangeMin(event.target.value)}
        sx={{ flex: 1 }}
        slotProps={{ htmlInput: { min: 0 } }}
      />
      <TextField
        label={labelMax}
        size="small"
        type="number"
        value={valueMax}
        onChange={(event) => onChangeMax(event.target.value)}
        sx={{ flex: 1 }}
        slotProps={{ htmlInput: { min: 0 } }}
      />
    </Box>
  );
}

export default function SearchFilterSidebar({ filters, activeFilterCount, onFilterChange, onReset }) {
  const { t } = useTranslation();
  const [expanded, setExpanded] = useState(['mime', 'modified', 'size', 'status']);

  const toggle = (panel) => setExpanded((prev) => (
    prev.includes(panel) ? prev.filter((item) => item !== panel) : [...prev, panel]
  ));

  const set = (key, val) => onFilterChange({ ...filters, [key]: val });

  return (
    <Box
      sx={{
        width: 260,
        flexShrink: 0,
        borderRight: '1px solid #e2e8f0',
        bgcolor: '#fff',
        overflowY: 'auto',
        display: { xs: 'none', md: 'flex' },
        flexDirection: 'column',
      }}
    >
      <Box
        sx={{
          px: 2.5,
          py: 2,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          borderBottom: '1px solid #f1f5f9',
          position: 'sticky',
          top: 0,
          bgcolor: '#fff',
          zIndex: 1,
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <FilterAlt sx={{ fontSize: 18, color: '#6366f1' }} />
          <Typography variant="subtitle2" fontWeight={700} color="#1e293b">
            {t('search.filters.title')}
          </Typography>
          {activeFilterCount > 0 && (
            <Badge badgeContent={activeFilterCount} color="primary" sx={{ ml: 0.5 }} />
          )}
        </Box>
        {activeFilterCount > 0 && (
          <Tooltip title={t('search.filters.reset')}>
            <IconButton size="small" onClick={onReset} sx={{ color: '#64748b' }}>
              <RestartAlt fontSize="small" />
            </IconButton>
          </Tooltip>
        )}
      </Box>

      <Box sx={{ flex: 1, overflow: 'auto', pb: 3 }}>
        <Accordion
          expanded={expanded.includes('mime')}
          onChange={() => toggle('mime')}
          elevation={0}
          disableGutters
          sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}
        >
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
                <Chip
                  key={key}
                  icon={React.cloneElement(icon, { style: { color: filters.mime_group === key ? '#fff' : color } })}
                  label={t(`search.filters.mime.${key}`)}
                  size="small"
                  variant={filters.mime_group === key ? 'filled' : 'outlined'}
                  onClick={() => set('mime_group', filters.mime_group === key ? '' : key)}
                  sx={{
                    cursor: 'pointer',
                    fontWeight: filters.mime_group === key ? 600 : 400,
                    borderRadius: 1.5,
                    borderColor: color,
                    color: filters.mime_group === key ? '#fff' : color,
                    bgcolor: filters.mime_group === key ? color : 'transparent',
                    '&:hover': { bgcolor: filters.mime_group === key ? color : `${color}20` },
                  }}
                />
              ))}
            </Box>
          </AccordionDetails>
        </Accordion>

        <Accordion
          expanded={expanded.includes('modified')}
          onChange={() => toggle('modified')}
          elevation={0}
          disableGutters
          sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}
        >
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <AccessTime sx={{ fontSize: 16, color: '#f59e0b' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.lastModified')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2 }}>
            <SingleSelect
              options={MODIFIED_OPTIONS}
              value={filters.modified_within || ''}
              onChange={(value) => set('modified_within', value)}
              tPrefix="search.filters.modified"
              t={t}
            />
          </AccordionDetails>
        </Accordion>

        <Accordion
          expanded={expanded.includes('size')}
          onChange={() => toggle('size')}
          elevation={0}
          disableGutters
          sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}
        >
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Storage sx={{ fontSize: 16, color: '#10b981' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.fileSize')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2 }}>
            <SingleSelect
              options={FILE_SIZE_OPTIONS}
              value={filters.file_size_group || ''}
              onChange={(value) => set('file_size_group', value)}
              tPrefix="search.filters.size"
              t={t}
            />
          </AccordionDetails>
        </Accordion>

        <Accordion
          expanded={expanded.includes('status')}
          onChange={() => toggle('status')}
          elevation={0}
          disableGutters
          sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}
        >
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
              <SingleSelect
                options={['published', 'unpublished']}
                value={filters.publish_status || ''}
                onChange={(value) => set('publish_status', value)}
                tPrefix="search.filters.publish"
                t={t}
              />
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.5, display: 'block' }}>
                {t('search.filters.approvedStatus')}
              </Typography>
              <SingleSelect
                options={['approved', 'rejected']}
                value={filters.approved_status || ''}
                onChange={(value) => set('approved_status', value)}
                tPrefix="search.filters.approval"
                t={t}
              />
            </Box>
          </AccordionDetails>
        </Accordion>

        <Accordion
          expanded={expanded.includes('orientation')}
          onChange={() => toggle('orientation')}
          elevation={0}
          disableGutters
          sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}
        >
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <CropLandscape sx={{ fontSize: 16, color: '#0ea5e9' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.orientation')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2 }}>
            <SingleSelect
              options={ORIENTATION_OPTIONS}
              value={filters.orientation || ''}
              onChange={(value) => set('orientation', value)}
              tPrefix="search.filters.orientations"
              t={t}
            />
          </AccordionDetails>
        </Accordion>

        <Accordion
          expanded={expanded.includes('style')}
          onChange={() => toggle('style')}
          elevation={0}
          disableGutters
          sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}
        >
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ px: 2.5, minHeight: 44 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Palette sx={{ fontSize: 16, color: '#ec4899' }} />
              <Typography variant="caption" fontWeight={700} sx={{ textTransform: 'uppercase', letterSpacing: 0.5, color: '#64748b' }}>
                {t('search.filters.style')}
              </Typography>
            </Box>
          </AccordionSummary>
          <AccordionDetails sx={{ px: 2.5, pt: 0, pb: 2 }}>
            <SingleSelect
              options={STYLE_OPTIONS}
              value={filters.style || ''}
              onChange={(value) => set('style', value)}
              tPrefix="search.filters.styles"
              t={t}
            />
          </AccordionDetails>
        </Accordion>

        <Accordion
          expanded={expanded.includes('video')}
          onChange={() => toggle('video')}
          elevation={0}
          disableGutters
          sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}
        >
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
                {VIDEO_FORMAT_OPTIONS.map((format) => (
                  <Chip
                    key={format}
                    label={format.toUpperCase()}
                    size="small"
                    variant={filters.video_format === format ? 'filled' : 'outlined'}
                    color={filters.video_format === format ? 'secondary' : 'default'}
                    onClick={() => set('video_format', filters.video_format === format ? '' : format)}
                    sx={{ cursor: 'pointer', borderRadius: 1, fontWeight: 600, fontSize: '0.7rem' }}
                  />
                ))}
              </Box>
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.videoCodec')}
              </Typography>
              <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                {VIDEO_CODEC_OPTIONS.map((codec) => (
                  <Chip
                    key={codec}
                    label={codec.toUpperCase()}
                    size="small"
                    variant={filters.video_codec === codec ? 'filled' : 'outlined'}
                    color={filters.video_codec === codec ? 'secondary' : 'default'}
                    onClick={() => set('video_codec', filters.video_codec === codec ? '' : codec)}
                    sx={{ cursor: 'pointer', borderRadius: 1, fontWeight: 600, fontSize: '0.7rem' }}
                  />
                ))}
              </Box>
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.videoHeight')} (px)
              </Typography>
              <RangeFilter
                labelMin={t('search.filters.min')}
                labelMax={t('search.filters.max')}
                valueMin={filters.video_height_min || ''}
                valueMax={filters.video_height_max || ''}
                onChangeMin={(value) => set('video_height_min', value)}
                onChangeMax={(value) => set('video_height_max', value)}
              />
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.videoWidth')} (px)
              </Typography>
              <RangeFilter
                labelMin={t('search.filters.min')}
                labelMax={t('search.filters.max')}
                valueMin={filters.video_width_min || ''}
                valueMax={filters.video_width_max || ''}
                onChangeMin={(value) => set('video_width_min', value)}
                onChangeMax={(value) => set('video_width_max', value)}
              />
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.videoBitrate')} (kbps)
              </Typography>
              <RangeFilter
                labelMin={t('search.filters.min')}
                labelMax={t('search.filters.max')}
                valueMin={filters.video_bitrate_min || ''}
                valueMax={filters.video_bitrate_max || ''}
                onChangeMin={(value) => set('video_bitrate_min', value)}
                onChangeMax={(value) => set('video_bitrate_max', value)}
              />
            </Box>
          </AccordionDetails>
        </Accordion>

        <Accordion
          expanded={expanded.includes('audio')}
          onChange={() => toggle('audio')}
          elevation={0}
          disableGutters
          sx={{ '&:before': { display: 'none' }, borderBottom: '1px solid #f1f5f9' }}
        >
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
                  <Chip
                    key={codec}
                    label={codec.replace('_', ' ')}
                    size="small"
                    variant={filters.audio_codec === codec ? 'filled' : 'outlined'}
                    color={filters.audio_codec === codec ? 'error' : 'default'}
                    onClick={() => set('audio_codec', filters.audio_codec === codec ? '' : codec)}
                    sx={{ cursor: 'pointer', borderRadius: 1, fontWeight: 600, fontSize: '0.7rem' }}
                  />
                ))}
              </Box>
            </Box>
            <Box>
              <Typography variant="caption" color="textSecondary" sx={{ mb: 0.75, display: 'block' }}>
                {t('search.filters.audioBitrate')} (kbps)
              </Typography>
              <RangeFilter
                labelMin={t('search.filters.min')}
                labelMax={t('search.filters.max')}
                valueMin={filters.audio_bitrate_min || ''}
                valueMax={filters.audio_bitrate_max || ''}
                onChangeMin={(value) => set('audio_bitrate_min', value)}
                onChangeMax={(value) => set('audio_bitrate_max', value)}
              />
            </Box>
          </AccordionDetails>
        </Accordion>
      </Box>
    </Box>
  );
}
