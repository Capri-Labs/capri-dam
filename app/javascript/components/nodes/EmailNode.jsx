/**
 * EmailNode – Send Email workflow step.
 *
 * Rendered by WorkflowCanvas for nodeType === 'emailNode'.
 * Config shape:
 *   { recipient, subject, body, cc, priority }
 */

import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
  Accordion, AccordionSummary, AccordionDetails, Typography, Chip, Box,
} from '@mui/material';
import { ExpandMore, Email } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#d97706';

export default function EmailNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};
  const [open, setOpen] = useState(false);

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={Email}
      label={t('nodes.emailNode')}
      isConnectable={isConnectable}
    >
      <Stack spacing={1.5} sx={{ p: 2 }}>
        {/* Step title */}
        <TextField
          size="small"
          fullWidth
          label={t('nodes.stepTitle')}
          placeholder={t('nodes.emailNode')}
          value={step.title || ''}
          onChange={(e) => updateNodeData(step.id, 'title', e.target.value)}
          className="nodrag"
        />

        {/* Recipient */}
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.email.recipient')}</InputLabel>
          <Select
            value={config.recipient || 'assignee'}
            label={t('nodes.email.recipient')}
            onChange={(e) => set('recipient', e.target.value)}
          >
            <MenuItem value="assignee">{t('nodes.email.recipientOwner')}</MenuItem>
            <MenuItem value="uploader">{t('nodes.email.recipientUploader')}</MenuItem>
            <MenuItem value="admins">{t('nodes.email.recipientAdmins')}</MenuItem>
            <MenuItem value="custom">{t('nodes.email.recipientCustom')}</MenuItem>
          </Select>
        </FormControl>

        {/* Subject */}
        <TextField
          size="small"
          fullWidth
          label={t('nodes.email.subject')}
          value={config.subject || ''}
          onChange={(e) => set('subject', e.target.value)}
          className="nodrag"
        />

        {/* Body */}
        <TextField
          size="small"
          fullWidth
          multiline
          rows={2}
          label={t('nodes.email.body')}
          placeholder={t('nodes.tokenHint')}
          value={config.body || ''}
          onChange={(e) => set('body', e.target.value)}
          className="nodrag"
        />
      </Stack>

      {/* Advanced: CC + Priority */}
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
              label={t('nodes.email.cc')}
              placeholder="extra@example.com, team@example.com"
              value={config.cc || ''}
              onChange={(e) => set('cc', e.target.value)}
              className="nodrag"
            />
            <FormControl size="small" fullWidth className="nodrag">
              <InputLabel>{t('nodes.email.priority')}</InputLabel>
              <Select
                value={config.priority || 'normal'}
                label={t('nodes.email.priority')}
                onChange={(e) => set('priority', e.target.value)}
              >
                <MenuItem value="normal">{t('nodes.email.priorityNormal')}</MenuItem>
                <MenuItem value="high">{t('nodes.email.priorityHigh')}</MenuItem>
              </Select>
            </FormControl>
            <Box>
              <Typography variant="caption" color="text.secondary" display="block" sx={{ mb: 0.5 }}>
                {t('nodes.tokenHint')}
              </Typography>
              <Stack direction="row" flexWrap="wrap" gap={0.5}>
                {['{{asset.title}}', '{{asset.url}}', '{{asset.status}}', '{{workflow.name}}'].map((tok) => (
                  <Chip key={tok} label={tok} size="small" variant="outlined" sx={{ fontSize: '0.65rem' }} />
                ))}
              </Stack>
            </Box>
          </Stack>
        </AccordionDetails>
      </Accordion>
    </NodeShell>
  );
}

