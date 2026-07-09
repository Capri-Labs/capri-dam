/**
 * CustomNode – schema-driven canvas node for tenant-registered plugin nodes.
 *
 * A custom node is a *manifest*, never code. The node renders a form from the
 * definition's `config_schema` (an array of `{ key, type, label, options }`
 * field descriptors) and, when the plugin declares branching `outputs`, exposes
 * one labelled bottom handle per output so the workflow can route on the
 * plugin's response. No tenant JavaScript executes in the browser — this is a
 * pure, declarative renderer.
 *
 * The backend node_type is `plugin:<key>`; the advancer routes branch handles by
 * the output label just like the built-in switch node.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
  FormControlLabel, Switch, Typography, Box,
} from '@mui/material';
import { Extension } from '@mui/icons-material';
import NodeShell from './NodeShell';

const DEFAULT_COLOR = '#6366f1';
const BRANCH_COLORS = ['#0ea5e9', '#8b5cf6', '#f59e0b', '#ec4899', '#10b981', '#ef4444'];

export default function CustomNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};
  const schema = Array.isArray(step.customSchema) ? step.customSchema : [];
  const outputs = Array.isArray(step.customOutputs) ? step.customOutputs : [];
  const color = step.customColor || DEFAULT_COLOR;
  const label = step.customName || t('customNodes.nodeLabel');

  const setConfig = (key, value) =>
    updateNodeData(step.id, 'config', { ...config, [key]: value });

  const branches = outputs.map((out, i) => ({
    id: String(out),
    label: String(out),
    color: BRANCH_COLORS[i % BRANCH_COLORS.length],
  }));

  const renderField = (field) => {
    const key = field.key;
    const fieldLabel = field.label || key;
    const value = config[key] ?? '';

    switch (field.type) {
      case 'boolean':
        return (
          <FormControlLabel
            key={key}
            className="nodrag"
            control={
              <Switch
                size="small"
                checked={Boolean(config[key])}
                onChange={(e) => setConfig(key, e.target.checked)}
              />
            }
            label={fieldLabel}
          />
        );
      case 'select':
        return (
          <FormControl key={key} size="small" fullWidth className="nodrag">
            <InputLabel>{fieldLabel}</InputLabel>
            <Select
              value={value}
              label={fieldLabel}
              onChange={(e) => setConfig(key, e.target.value)}
            >
              {(field.options || []).map((opt) => (
                <MenuItem key={String(opt)} value={String(opt)}>
                  {String(opt)}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
        );
      case 'number':
        return (
          <TextField
            key={key}
            size="small"
            fullWidth
            type="number"
            label={fieldLabel}
            value={value}
            onChange={(e) => setConfig(key, e.target.value)}
            className="nodrag"
          />
        );
      default:
        return (
          <TextField
            key={key}
            size="small"
            fullWidth
            label={fieldLabel}
            value={value}
            onChange={(e) => setConfig(key, e.target.value)}
            className="nodrag"
          />
        );
    }
  };

  return (
    <NodeShell
      color={color}
      icon={Extension}
      label={label}
      handles={branches.length > 0 ? 'multi' : 'linear'}
      branches={branches.length > 0 ? branches : undefined}
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

        <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
          <Typography variant="caption" sx={{ color: '#94a3b8', fontStyle: 'italic' }}>
            {t('customNodes.pluginBadge', { key: step.customKey || '' })}
          </Typography>
        </Box>

        {schema.length === 0 && (
          <Typography variant="caption" sx={{ color: '#94a3b8' }}>
            {t('customNodes.noFields')}
          </Typography>
        )}

        {schema.map(renderField)}
      </Stack>
    </NodeShell>
  );
}
