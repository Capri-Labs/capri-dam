/**
 * SmsNode – Send SMS Alert workflow step.
 *
 * Config shape: { phone, message }
 * Dispatched via WorkflowSmsWorker (Twilio / SNS).
 * Shows live character count; warns above 160.
 */

import React from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, Typography, Box,
} from '@mui/material';
import { Sms } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#065f46';
const SMS_LIMIT = 160;

export default function SmsNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  const msgLen = (config.message || '').length;
  const overLimit = msgLen > SMS_LIMIT;

  return (
    <NodeShell
      color={COLOR}
      icon={Sms}
      label={t('nodes.smsNode')}
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
          label={t('nodes.sms.phone')}
          placeholder={t('nodes.sms.phonePlaceholder')}
          value={config.phone || ''}
          onChange={(e) => set('phone', e.target.value)}
          className="nodrag"
        />

        <Box className="nodrag">
          <TextField
            size="small"
            fullWidth
            multiline
            rows={3}
            label={t('nodes.sms.message')}
            placeholder={t('nodes.tokenHint')}
            value={config.message || ''}
            onChange={(e) => set('message', e.target.value)}
            error={overLimit}
          />
          <Typography
            variant="caption"
            sx={{ color: overLimit ? 'error.main' : 'text.secondary', display: 'block', textAlign: 'right', mt: 0.25 }}
          >
            {overLimit
              ? t('nodes.sms.overLimit')
              : `${msgLen} / ${SMS_LIMIT}`}
          </Typography>
        </Box>
      </Stack>
    </NodeShell>
  );
}

