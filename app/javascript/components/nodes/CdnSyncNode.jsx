/**
 * CdnSyncNode – Purge CDN caches and re-sync to edge nodes.
 *
 * Config shape: { purgeType, notifyOnComplete }
 * Dispatched to EdgeMetadataSyncWorker.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
  FormControlLabel, Switch, Typography,
} from '@mui/material';
import { CloudSync } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#0e7490';

export default function CdnSyncNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={CloudSync}
      label={t('nodes.cdnSyncNode')}
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
          <InputLabel>{t('nodes.cdn.purgeType')}</InputLabel>
          <Select
            value={config.purgeType || 'smart'}
            label={t('nodes.cdn.purgeType')}
            onChange={(e) => set('purgeType', e.target.value)}
          >
            <MenuItem value="smart">{t('nodes.cdn.purgeTypeSmart')}</MenuItem>
            <MenuItem value="full">{t('nodes.cdn.purgeTypeFull')}</MenuItem>
          </Select>
        </FormControl>

        <FormControlLabel
          className="nodrag"
          control={
            <Switch
              size="small"
              checked={!!config.notifyOnComplete}
              onChange={(e) => set('notifyOnComplete', e.target.checked)}
            />
          }
          label={<Typography variant="caption">{t('nodes.cdn.notifyOnComplete')}</Typography>}
        />
      </Stack>
    </NodeShell>
  );
}

