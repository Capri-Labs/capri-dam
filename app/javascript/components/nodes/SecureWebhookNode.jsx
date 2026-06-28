/**
 * SecureWebhookNode – Authenticated Webhook step.
 *
 * Config shape: { url, method, authType, secret, headers }
 * Supports HMAC-SHA256, Bearer token, and HTTP Basic auth.
 */

import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
  Accordion, AccordionSummary, AccordionDetails, Typography,
} from '@mui/material';
import { ExpandMore, HttpsOutlined } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#075985';

export default function SecureWebhookNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};
  const [open, setOpen] = useState(false);

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={HttpsOutlined}
      label={t('nodes.secureWebhookNode')}
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
          label={t('nodes.secureWebhook.url')}
          placeholder="https://secure.example.com/webhook"
          value={config.url || ''}
          onChange={(e) => set('url', e.target.value)}
          className="nodrag"
        />

        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.secureWebhook.method')}</InputLabel>
          <Select
            value={config.method || 'POST'}
            label={t('nodes.secureWebhook.method')}
            onChange={(e) => set('method', e.target.value)}
          >
            {['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].map((m) => (
              <MenuItem key={m} value={m}>{m}</MenuItem>
            ))}
          </Select>
        </FormControl>

        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.secureWebhook.authType')}</InputLabel>
          <Select
            value={config.authType || 'hmac'}
            label={t('nodes.secureWebhook.authType')}
            onChange={(e) => set('authType', e.target.value)}
          >
            <MenuItem value="hmac">{t('nodes.secureWebhook.authHmac')}</MenuItem>
            <MenuItem value="bearer">{t('nodes.secureWebhook.authBearer')}</MenuItem>
            <MenuItem value="basic">{t('nodes.secureWebhook.authBasic')}</MenuItem>
          </Select>
        </FormControl>

        <TextField
          size="small"
          fullWidth
          type="password"
          label={t('nodes.secureWebhook.secret')}
          value={config.secret || ''}
          onChange={(e) => set('secret', e.target.value)}
          className="nodrag"
          autoComplete="new-password"
        />
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
          <TextField
            size="small"
            fullWidth
            multiline
            rows={2}
            label={t('nodes.secureWebhook.headers')}
            placeholder='{"X-Tenant-Id": "acme"}'
            value={config.headers || ''}
            onChange={(e) => set('headers', e.target.value)}
            className="nodrag"
          />
        </AccordionDetails>
      </Accordion>
    </NodeShell>
  );
}

