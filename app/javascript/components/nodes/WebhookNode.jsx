/**
 * WebhookNode – HTTP Webhook workflow step.
 *
 * Config shape: { url, method, headers, retries, timeout }
 */

import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
  Accordion, AccordionSummary, AccordionDetails, Typography,
} from '@mui/material';
import { ExpandMore, Webhook } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#0284c7';

export default function WebhookNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};
  const [open, setOpen] = useState(false);

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={Webhook}
      label={t('nodes.webhookNode')}
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
          label={t('nodes.webhook.url')}
          placeholder="https://api.example.com/dam-hook"
          value={config.url || ''}
          onChange={(e) => set('url', e.target.value)}
          className="nodrag"
        />

        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.webhook.method')}</InputLabel>
          <Select
            value={config.method || 'POST'}
            label={t('nodes.webhook.method')}
            onChange={(e) => set('method', e.target.value)}
          >
            {['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].map((m) => (
              <MenuItem key={m} value={m}>{m}</MenuItem>
            ))}
          </Select>
        </FormControl>
      </Stack>

      <Accordion
        expanded={open}
        onChange={() => setOpen(!open)}
        disableGutters
        elevation={0}
        sx={{ '&:before': { display: 'none' }, borderTop: '1px solid #e2e8f0' }}
      >
        <AccordionSummary
          expandIcon={<ExpandMore />}
          sx={{ bgcolor: '#f8fafc', minHeight: 40, '& .MuiAccordionSummary-content': { my: 1 } }}
        >
          <Typography variant="caption" fontWeight="bold" color="text.secondary">
            {t('nodes.advancedSettings')}
          </Typography>
        </AccordionSummary>
        <AccordionDetails sx={{ pt: 1, pb: 2, px: 2 }}>
          <Stack spacing={1.5}>
            <TextField
              size="small"
              fullWidth
              multiline
              rows={2}
              label={t('nodes.webhook.headers')}
              placeholder={t('nodes.webhook.headersPlaceholder')}
              value={config.headers || ''}
              onChange={(e) => set('headers', e.target.value)}
              className="nodrag"
            />
            <Stack direction="row" spacing={1}>
              <TextField
                size="small"
                type="number"
                label={t('nodes.webhook.retries')}
                value={config.retries ?? 3}
                onChange={(e) => set('retries', parseInt(e.target.value, 10))}
                className="nodrag"
                sx={{ width: 120 }}
                slotProps={{ htmlInput: { min: 0, max: 10 } }}
              />
              <TextField
                size="small"
                type="number"
                label={t('nodes.webhook.timeout')}
                value={config.timeout ?? 10}
                onChange={(e) => set('timeout', parseInt(e.target.value, 10))}
                className="nodrag"
                sx={{ width: 140 }}
                slotProps={{ htmlInput: { min: 1, max: 120 } }}
              />
            </Stack>
          </Stack>
        </AccordionDetails>
      </Accordion>
    </NodeShell>
  );
}

