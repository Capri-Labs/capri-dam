/**
 * ArchiveNode – Soft-archive asset workflow step.
 * No extra config required; displays an informational note.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import { Stack, TextField, Alert } from '@mui/material';
import { Archive } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#78350f';

export default function ArchiveNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;

  return (
    <NodeShell
      color={COLOR}
      icon={Archive}
      label={t('nodes.archiveNode')}
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
        <Alert severity="info" sx={{ py: 0.25, fontSize: '0.72rem' }}>
          {t('nodes.archive.confirmLabel')}
        </Alert>
        <Alert severity="warning" sx={{ py: 0.25, fontSize: '0.72rem' }}>
          {t('nodes.archive.irreversibleNote')}
        </Alert>
      </Stack>
    </NodeShell>
  );
}

