/**
 * AddTagsNode – Append tags to asset workflow step.
 * Config shape: { tags }
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import { Stack, TextField } from '@mui/material';
import { Label } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#047857';

export default function AddTagsNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={Label}
      label={t('nodes.addTagsNode')}
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
        <TextField
          size="small"
          fullWidth
          label={t('nodes.tags.tagsLabel')}
          placeholder={t('nodes.tags.tagsPlaceholder')}
          value={config.tags || ''}
          onChange={(e) => set('tags', e.target.value)}
          className="nodrag"
          helperText="Separate multiple tags with commas"
        />
      </Stack>
    </NodeShell>
  );
}

