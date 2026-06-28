/**
 * SlackNode – Post to Slack workflow step.
 *
 * Config shape: { channel, message, color }
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
} from '@mui/material';
import { Chat } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#4a1d96';

export default function SlackNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={Chat}
      label={t('nodes.slackNode')}
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
          label={t('nodes.slack.channel')}
          placeholder={t('nodes.slack.channelPlaceholder')}
          value={config.channel || ''}
          onChange={(e) => set('channel', e.target.value)}
          className="nodrag"
        />

        <TextField
          size="small"
          fullWidth
          multiline
          rows={2}
          label={t('nodes.slack.message')}
          placeholder={t('nodes.tokenHint')}
          value={config.message || ''}
          onChange={(e) => set('message', e.target.value)}
          className="nodrag"
        />

        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.slack.color')}</InputLabel>
          <Select
            value={config.color || 'good'}
            label={t('nodes.slack.color')}
            onChange={(e) => set('color', e.target.value)}
          >
            <MenuItem value="good">{t('nodes.slack.colorGood')}</MenuItem>
            <MenuItem value="warning">{t('nodes.slack.colorWarning')}</MenuItem>
            <MenuItem value="danger">{t('nodes.slack.colorDanger')}</MenuItem>
          </Select>
        </FormControl>
      </Stack>
    </NodeShell>
  );
}

