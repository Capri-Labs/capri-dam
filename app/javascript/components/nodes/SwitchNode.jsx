/**
 * SwitchNode – Multi-way switch/case branching on an asset field.
 *
 * Config shape:
 *   {
 *     field: string,
 *     cases: [{ operator, value, label }],
 *     default_label: string   // handle id for the "no match" branch
 *   }
 *
 * Renders one labelled bottom source handle per case plus a default handle.
 * The handle `id` equals the case `label` (or "case_<n>" when blank) and the
 * default handle id equals `default_label` (or "default"). These handle ids are
 * matched against graph edge `sourceHandle`s by the backend advancer so routing
 * follows the winning case.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
  IconButton, Button, Box, Typography, Divider,
} from '@mui/material';
import { AltRoute, Add, DeleteOutlined } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#0f766e';
const DEFAULT_COLOR = '#64748b';
const CASE_COLORS = ['#0ea5e9', '#8b5cf6', '#f59e0b', '#ec4899', '#10b981', '#ef4444'];

const OPERATORS = [
  'equals', 'not_equals', 'contains', 'starts_with', 'ends_with', 'greater_than', 'less_than',
];

// Handle id for a case: explicit label, else positional "case_<n>".
export function caseHandleId(c, index) {
  const label = (c?.label || '').trim();
  return label || `case_${index + 1}`;
}

export default function SwitchNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};
  const cases = Array.isArray(config.cases) ? config.cases : [];
  const defaultLabel = (config.default_label || '').trim() || 'default';

  const setConfig = (patch) => updateNodeData(step.id, 'config', { ...config, ...patch });

  const setCase = (index, patch) => {
    const next = cases.map((c, i) => (i === index ? { ...c, ...patch } : c));
    setConfig({ cases: next });
  };

  const addCase = () =>
    setConfig({ cases: [...cases, { operator: 'equals', value: '', label: '' }] });

  const removeCase = (index) =>
    setConfig({ cases: cases.filter((_, i) => i !== index) });

  const branches = [
    ...cases.map((c, i) => ({
      id: caseHandleId(c, i),
      label: caseHandleId(c, i),
      color: CASE_COLORS[i % CASE_COLORS.length],
    })),
    { id: defaultLabel, label: t('nodes.switch.defaultBranch'), color: DEFAULT_COLOR },
  ];

  return (
    <NodeShell
      color={COLOR}
      icon={AltRoute}
      label={t('nodes.switchNode')}
      handles="multi"
      branches={branches}
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
          label={t('nodes.switch.field')}
          placeholder={t('nodes.switch.fieldPlaceholder')}
          value={config.field || ''}
          onChange={(e) => setConfig({ field: e.target.value })}
          className="nodrag"
        />

        <Divider textAlign="left">
          <Typography variant="caption" sx={{ fontWeight: 700, color: '#475569' }}>
            {t('nodes.switch.cases')}
          </Typography>
        </Divider>

        {cases.length === 0 && (
          <Typography variant="caption" sx={{ color: '#94a3b8' }}>
            {t('nodes.switch.noCases')}
          </Typography>
        )}

        {cases.map((c, index) => (
          <Box
            key={index}
            sx={{ border: '1px solid #e2e8f0', borderRadius: 1.5, p: 1, position: 'relative' }}
          >
            <Stack spacing={1}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                <Typography variant="caption" sx={{ fontWeight: 700, color: '#0f766e', flexGrow: 1 }}>
                  {t('nodes.switch.caseN', { n: index + 1 })}
                </Typography>
                <IconButton
                  size="small"
                  aria-label={t('nodes.switch.removeCase')}
                  onClick={() => removeCase(index)}
                  className="nodrag"
                >
                  <DeleteOutlined sx={{ fontSize: 16 }} />
                </IconButton>
              </Box>

              <FormControl size="small" fullWidth className="nodrag">
                <InputLabel>{t('nodes.switch.operator')}</InputLabel>
                <Select
                  value={c.operator || 'equals'}
                  label={t('nodes.switch.operator')}
                  onChange={(e) => setCase(index, { operator: e.target.value })}
                >
                  {OPERATORS.map((op) => (
                    <MenuItem key={op} value={op}>
                      {t(`nodes.switch.op_${op}`)}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>

              <TextField
                size="small"
                fullWidth
                label={t('nodes.switch.compareValue')}
                value={c.value || ''}
                onChange={(e) => setCase(index, { value: e.target.value })}
                className="nodrag"
              />

              <TextField
                size="small"
                fullWidth
                label={t('nodes.switch.outputLabel')}
                placeholder={t('nodes.switch.outputLabelPlaceholder')}
                value={c.label || ''}
                onChange={(e) => setCase(index, { label: e.target.value })}
                className="nodrag"
              />
            </Stack>
          </Box>
        ))}

        <Button
          size="small"
          startIcon={<Add />}
          onClick={addCase}
          className="nodrag"
          variant="outlined"
        >
          {t('nodes.switch.addCase')}
        </Button>

        <TextField
          size="small"
          fullWidth
          label={t('nodes.switch.defaultLabel')}
          placeholder="default"
          value={config.default_label || ''}
          onChange={(e) => setConfig({ default_label: e.target.value })}
          className="nodrag"
          helperText={t('nodes.switch.defaultHelp')}
        />
      </Stack>
    </NodeShell>
  );
}
