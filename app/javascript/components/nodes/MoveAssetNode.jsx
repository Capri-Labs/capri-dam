/**
 * MoveAssetNode – Move asset to a target folder.
 * Config shape: { folder }
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import { Stack, TextField } from '@mui/material';
import { DriveFileMove } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#0d9488';

export default function MoveAssetNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={DriveFileMove}
      label={t('nodes.moveAssetNode')}
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
          label={t('nodes.moveAsset.folder')}
          placeholder={t('nodes.moveAsset.folderPlaceholder')}
          value={config.folder || ''}
          onChange={(e) => set('folder', e.target.value)}
          className="nodrag"
        />
      </Stack>
    </NodeShell>
  );
}

