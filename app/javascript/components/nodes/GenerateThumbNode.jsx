/**
 * GenerateThumbNode – Trigger thumbnail regeneration.
 *
 * Config shape: { profile, forceRegen }
 * profile = '' means all active profiles.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
  FormControlLabel, Switch, Typography,
} from '@mui/material';
import { Image } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#6d28d9';

export default function GenerateThumbNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={Image}
      label={t('nodes.generateThumbNode')}
      isConnectable={isConnectable}
    >
      <Stack spacing={1.5} sx={{ p: 2 }}>
        <TextField
          size="small"
          fullWidth
          label={t('nodes.stepTitle')}
          value={step.title || ''}
          onChange={(e) => updateNodeData(step.id, 'title', e.target.value)}
          className="nodrag"
        />

        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.thumb.profile')}</InputLabel>
          <Select
            value={config.profile || ''}
            label={t('nodes.thumb.profile')}
            onChange={(e) => set('profile', e.target.value)}
          >
            <MenuItem value="">{t('nodes.thumb.profileAll')}</MenuItem>
            <MenuItem value="small">Small (150 × 150)</MenuItem>
            <MenuItem value="medium">Medium (400 × 400)</MenuItem>
            <MenuItem value="large">Large (800 × 800)</MenuItem>
          </Select>
        </FormControl>

        <FormControlLabel
          className="nodrag"
          control={
            <Switch
              size="small"
              checked={!!config.forceRegen}
              onChange={(e) => set('forceRegen', e.target.checked)}
            />
          }
          label={<Typography variant="caption">{t('nodes.thumb.forceRegen')}</Typography>}
        />
      </Stack>
    </NodeShell>
  );
}

