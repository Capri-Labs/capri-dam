/**
 * AiMetadataNode – Run AI metadata extraction workflow step.
 *
 * Config shape: { aiTask, confidence, overwrite }
 * Enqueues an AiBatchJob for the target asset via AiBatchJobWorker.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
  FormControlLabel, Switch, Typography,
} from '@mui/material';
import { AutoAwesome } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#7c3aed';

export default function AiMetadataNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={AutoAwesome}
      label={t('nodes.aiMetadataNode')}
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
          <InputLabel>{t('nodes.ai.task')}</InputLabel>
          <Select
            value={config.aiTask || 'metadata_extraction'}
            label={t('nodes.ai.task')}
            onChange={(e) => set('aiTask', e.target.value)}
          >
            <MenuItem value="metadata_extraction">{t('nodes.ai.taskExtract')}</MenuItem>
            <MenuItem value="seo_enrichment">{t('nodes.ai.taskSeo')}</MenuItem>
            <MenuItem value="visual_context">{t('nodes.ai.taskVisual')}</MenuItem>
          </Select>
        </FormControl>

        <TextField
          size="small"
          type="number"
          label={t('nodes.ai.confidence')}
          value={config.confidence ?? 70}
          onChange={(e) => set('confidence', parseInt(e.target.value, 10))}
          className="nodrag"
          slotProps={{ htmlInput: { min: 0, max: 100 } }}
          sx={{ width: 180 }}
        />

        <FormControlLabel
          className="nodrag"
          control={
            <Switch
              size="small"
              checked={!!config.overwrite}
              onChange={(e) => set('overwrite', e.target.checked)}
            />
          }
          label={<Typography variant="caption">{t('nodes.ai.overwrite')}</Typography>}
        />
      </Stack>
    </NodeShell>
  );
}

