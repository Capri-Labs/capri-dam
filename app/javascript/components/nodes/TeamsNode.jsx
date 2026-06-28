/**
 * TeamsNode – Post to Microsoft Teams workflow step.
 *
 * Config shape: { channel, title, message, color }
 * `channel` holds the Teams Incoming Webhook URL.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
} from '@mui/material';
import { VideoCall } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#1d4ed8';

export default function TeamsNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={VideoCall}
      label={t('nodes.teamsNode')}
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
          label={t('nodes.teams.webhookUrl')}
          placeholder="https://outlook.office.com/webhook/…"
          value={config.channel || ''}
          onChange={(e) => set('channel', e.target.value)}
          className="nodrag"
        />

        <TextField
          size="small"
          fullWidth
          label={t('nodes.teams.title')}
          placeholder={t('nodes.tokenHint')}
          value={config.teamsTitle || ''}
          onChange={(e) => set('teamsTitle', e.target.value)}
          className="nodrag"
        />

        <TextField
          size="small"
          fullWidth
          multiline
          rows={2}
          label={t('nodes.teams.message')}
          placeholder={t('nodes.tokenHint')}
          value={config.message || ''}
          onChange={(e) => set('message', e.target.value)}
          className="nodrag"
        />

        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.teams.color')}</InputLabel>
          <Select
            value={config.color || 'good'}
            label={t('nodes.teams.color')}
            onChange={(e) => set('color', e.target.value)}
          >
            <MenuItem value="good">{t('nodes.teams.colorGreen')}</MenuItem>
            <MenuItem value="warning">{t('nodes.teams.colorOrange')}</MenuItem>
            <MenuItem value="attention">{t('nodes.teams.colorRed')}</MenuItem>
          </Select>
        </FormControl>
      </Stack>
    </NodeShell>
  );
}

