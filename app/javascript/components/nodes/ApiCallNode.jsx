/**
 * ApiCallNode – Custom HTTP API call workflow step.
 *
 * Config shape: { url, method, headers, body, expectedStatus }
 * Supports arbitrary HTTP method, headers (JSON), and request body (JSON).
 */

import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
  Accordion, AccordionSummary, AccordionDetails, Typography,
} from '@mui/material';
import { ExpandMore, Api } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#0369a1';

export default function ApiCallNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};
  const [open, setOpen] = useState(true);

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={Api}
      label={t('nodes.apiCallNode')}
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
          label={t('nodes.apiCall.url')}
          placeholder="https://api.example.com/v1/assets/{{asset.id}}"
          value={config.url || ''}
          onChange={(e) => set('url', e.target.value)}
          className="nodrag"
        />

        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.apiCall.method')}</InputLabel>
          <Select
            value={config.method || 'POST'}
            label={t('nodes.apiCall.method')}
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
            {t('nodes.configSection')}
          </Typography>
        </AccordionSummary>
        <AccordionDetails sx={{ pt: 1, pb: 2, px: 2 }}>
          <Stack spacing={1.5}>
            <TextField
              size="small"
              fullWidth
              multiline
              rows={2}
              label={t('nodes.apiCall.headers')}
              placeholder='{"Authorization": "Bearer {{workflow.name}}", "Accept": "application/json"}'
              value={config.headers || ''}
              onChange={(e) => set('headers', e.target.value)}
              className="nodrag"
            />
            <TextField
              size="small"
              fullWidth
              multiline
              rows={3}
              label={t('nodes.apiCall.body')}
              placeholder='{"asset_id": "{{asset.id}}", "status": "{{asset.status}}"}'
              value={config.body || ''}
              onChange={(e) => set('body', e.target.value)}
              className="nodrag"
            />
            <TextField
              size="small"
              fullWidth
              label={t('nodes.apiCall.expectedStatus')}
              placeholder="200-299"
              value={config.expectedStatus || ''}
              onChange={(e) => set('expectedStatus', e.target.value)}
              className="nodrag"
            />
          </Stack>
        </AccordionDetails>
      </Accordion>
    </NodeShell>
  );
}

