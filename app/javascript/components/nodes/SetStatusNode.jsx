/**
 * SetStatusNode – Change asset status workflow step.
 * Config shape: { status }
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import { Stack, TextField, FormControl, InputLabel, Select, MenuItem, Box } from '@mui/material';
import { Label } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#059669';

const STATUS_OPTIONS = [
  { value: 'draft',       color: '#94a3b8' },
  { value: 'pending',     color: '#f59e0b' },
  { value: 'processing',  color: '#3b82f6' },
  { value: 'ready',       color: '#10b981' },
  { value: 'in_review',   color: '#8b5cf6' },
  { value: 'approved',    color: '#22c55e' },
  { value: 'rejected',    color: '#ef4444' },
  { value: 'failed',      color: '#dc2626' },
];

export default function SetStatusNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  const selectedStatus = STATUS_OPTIONS.find((s) => s.value === (config.status || 'approved'));

  return (
    <NodeShell
      color={COLOR}
      icon={Label}
      label={t('nodes.setStatusNode')}
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
          <InputLabel>{t('nodes.setStatus.newStatus')}</InputLabel>
          <Select
            value={config.status || 'approved'}
            label={t('nodes.setStatus.newStatus')}
            onChange={(e) => set('status', e.target.value)}
            renderValue={(val) => {
              const opt = STATUS_OPTIONS.find((s) => s.value === val);
              return (
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <Box sx={{ width: 10, height: 10, borderRadius: '50%', bgcolor: opt?.color || '#94a3b8' }} />
                  {val}
                </Box>
              );
            }}
          >
            {STATUS_OPTIONS.map(({ value, color }) => (
              <MenuItem key={value} value={value}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                  <Box sx={{ width: 10, height: 10, borderRadius: '50%', bgcolor: color }} />
                  {value}
                </Box>
              </MenuItem>
            ))}
          </Select>
        </FormControl>
      </Stack>
    </NodeShell>
  );
}

