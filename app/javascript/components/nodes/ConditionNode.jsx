/**
 * ConditionNode – Evaluate an asset field and branch TRUE / FALSE.
 *
 * Config shape: { field, operator, value }
 * Operators: equals | not_equals | contains | starts_with | ends_with |
 *            greater_than | less_than
 *
 * Renders two bottom source handles (id="true" / id="false").
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
} from '@mui/material';
import { CallSplit } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#334155';

export default function ConditionNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={CallSplit}
      label={t('nodes.conditionNode')}
      handles="branching"
      branchLabels={{
        true: t('nodes.condition.trueBranch'),
        false: t('nodes.condition.falseBranch'),
      }}
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
          label={t('nodes.condition.field')}
          placeholder={t('nodes.condition.fieldPlaceholder')}
          value={config.field || ''}
          onChange={(e) => set('field', e.target.value)}
          className="nodrag"
        />

        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.condition.operator')}</InputLabel>
          <Select
            value={config.operator || 'equals'}
            label={t('nodes.condition.operator')}
            onChange={(e) => set('operator', e.target.value)}
          >
            <MenuItem value="equals">{t('nodes.condition.opEquals')}</MenuItem>
            <MenuItem value="not_equals">{t('nodes.condition.opNotEquals')}</MenuItem>
            <MenuItem value="contains">{t('nodes.condition.opContains')}</MenuItem>
            <MenuItem value="starts_with">{t('nodes.condition.opStartsWith')}</MenuItem>
            <MenuItem value="ends_with">{t('nodes.condition.opEndsWith')}</MenuItem>
            <MenuItem value="greater_than">{t('nodes.condition.opGreaterThan')}</MenuItem>
            <MenuItem value="less_than">{t('nodes.condition.opLessThan')}</MenuItem>
          </Select>
        </FormControl>

        <TextField
          size="small"
          fullWidth
          label={t('nodes.condition.compareValue')}
          value={config.value || ''}
          onChange={(e) => set('value', e.target.value)}
          className="nodrag"
        />
      </Stack>
    </NodeShell>
  );
}

