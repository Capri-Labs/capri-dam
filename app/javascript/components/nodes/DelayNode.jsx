/**
 * DelayNode – Pause the workflow for a configurable duration.
 *
 * Config shape: { delayValue, delayUnit }
 * On execution WorkflowActionExecutor schedules
 * WorkflowDelayWorker to resume after the specified duration.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, Select, MenuItem, Typography, Alert,
} from '@mui/material';
import { Timer } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#475569';

export default function DelayNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={Timer}
      label={t('nodes.delayNode')}
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

        <Stack direction="row" spacing={1} sx={{
  alignItems: "center"
}}>
          <Typography variant="body2" color="text.secondary" sx={{ whiteSpace: 'nowrap' }}>
            {t('nodes.delay.duration')}
          </Typography>
          <TextField
            size="small"
            type="number"
            value={config.delayValue ?? 1}
            onChange={(e) => set('delayValue', Math.max(1, parseInt(e.target.value, 10) || 1))}
            className="nodrag"
            sx={{ width: 80 }}
            slotProps={{ htmlInput: { min: 1, max: 9999 } }}
          />
          <FormControl size="small" sx={{ minWidth: 100 }} className="nodrag">
            <Select
              value={config.delayUnit || 'hours'}
              onChange={(e) => set('delayUnit', e.target.value)}
            >
              <MenuItem value="minutes">{t('nodes.delay.unitMinutes')}</MenuItem>
              <MenuItem value="hours">{t('nodes.delay.unitHours')}</MenuItem>
              <MenuItem value="days">{t('nodes.delay.unitDays')}</MenuItem>
            </Select>
          </FormControl>
        </Stack>

        <Alert severity="info" sx={{ py: 0.25, fontSize: '0.72rem' }}>
          {t('nodes.delay.hint')}
        </Alert>
      </Stack>
    </NodeShell>
  );
}

