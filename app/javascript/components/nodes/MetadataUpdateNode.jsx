/**
 * MetadataUpdateNode – Write one or more key-value pairs to asset properties.
 *
 * Config shape: { pairs: [{ key, value }] }
 * Values support token substitution: {{asset.title}}, etc.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, Typography, IconButton, Box, Divider,
} from '@mui/material';
import { DataObject, Add, Remove } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#1e40af';

export default function MetadataUpdateNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};
  const pairs = Array.isArray(config.pairs) ? config.pairs : [{ key: '', value: '' }];

  const updatePairs = (newPairs) =>
    updateNodeData(step.id, 'config', { ...config, pairs: newPairs });

  const setPair = (idx, field, val) => {
    const next = pairs.map((p, i) => (i === idx ? { ...p, [field]: val } : p));
    updatePairs(next);
  };

  const addPair = () => updatePairs([...pairs, { key: '', value: '' }]);
  const removePair = (idx) => updatePairs(pairs.filter((_, i) => i !== idx));

  return (
    <NodeShell
      color={COLOR}
      icon={DataObject}
      label={t('nodes.metadataUpdateNode')}
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

        <Typography variant="caption" color="text.secondary">
          {t('nodes.metadata.pairsLabel')}
        </Typography>

        {pairs.map((pair, idx) => (
          <Box key={idx} sx={{ display: 'flex', gap: 0.5, alignItems: 'flex-start' }}>
            <Stack spacing={0.75} sx={{ flexGrow: 1 }}>
              <TextField
                size="small"
                fullWidth
                label={t('nodes.metadata.key')}
                placeholder={t('nodes.metadata.keyPlaceholder')}
                value={pair.key}
                onChange={(e) => setPair(idx, 'key', e.target.value)}
                className="nodrag"
              />
              <TextField
                size="small"
                fullWidth
                label={t('nodes.metadata.value')}
                placeholder={t('nodes.metadata.valuePlaceholder')}
                value={pair.value}
                onChange={(e) => setPair(idx, 'value', e.target.value)}
                className="nodrag"
              />
            </Stack>
            <IconButton size="small" onClick={() => removePair(idx)} disabled={pairs.length === 1} className="nodrag" sx={{ mt: 0.5 }}>
              <Remove fontSize="small" color="error" />
            </IconButton>
          </Box>
        ))}

        {pairs.length < 8 && (
          <Box sx={{ display: 'flex', justifyContent: 'flex-end' }}>
            <IconButton size="small" onClick={addPair} className="nodrag" color="primary">
              <Add fontSize="small" />
            </IconButton>
            <Typography variant="caption" sx={{ alignSelf: 'center', ml: 0.5, color: '#3b82f6' }}>
              {t('nodes.metadata.addPair')}
            </Typography>
          </Box>
        )}
      </Stack>
    </NodeShell>
  );
}




