/**
 * CopyAssetNode – Duplicate asset to a target folder.
 * Config shape: { folder, titleSuffix }
 * Heavy clone is dispatched to AssetCopyWorker so the engine is never blocked.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import { Stack, TextField } from '@mui/material';
import { FileCopy } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#0891b2';

export default function CopyAssetNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={FileCopy}
      label={t('nodes.copyAssetNode')}
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
          label={t('nodes.copyAsset.folder')}
          placeholder={t('nodes.moveAsset.folderPlaceholder')}
          value={config.folder || ''}
          onChange={(e) => set('folder', e.target.value)}
          className="nodrag"
        />
        <TextField
          size="small"
          fullWidth
          label={t('nodes.copyAsset.titleSuffix')}
          placeholder={t('nodes.copyAsset.titleSuffixPlaceholder')}
          value={config.titleSuffix || ''}
          onChange={(e) => set('titleSuffix', e.target.value)}
          className="nodrag"
        />
      </Stack>
    </NodeShell>
  );
}

