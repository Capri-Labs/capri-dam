/**
 * PublishNode – Publish asset (set status to approved + optional CDN sync).
 * Config shape: { cdnSync }
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import { Stack, TextField, FormControlLabel, Switch, Typography } from '@mui/material';
import { PublicOutlined } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#15803d';

export default function PublishNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={PublicOutlined}
      label={t('nodes.publishNode')}
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
        <FormControlLabel
          className="nodrag"
          control={
            <Switch
              size="small"
              checked={config.cdnSync !== false}
              onChange={(e) => set('cdnSync', e.target.checked)}
              color="success"
            />
          }
          label={<Typography variant="caption">{t('nodes.publish.cdnSync')}</Typography>}
        />
        <Typography variant="caption" color="text.secondary">
          {t('nodes.publish.statusNote')}
        </Typography>
      </Stack>
    </NodeShell>
  );
}

