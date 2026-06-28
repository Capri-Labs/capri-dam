/**
 * InAppNotifyNode – In-App Alert workflow step.
 *
 * Config shape: { recipient, title, message, priority, actionUrl }
 */

import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Stack, TextField, FormControl, InputLabel, Select, MenuItem,
  Accordion, AccordionSummary, AccordionDetails, Typography,
} from '@mui/material';
import { ExpandMore, NotificationsActive } from '@mui/icons-material';
import NodeShell from './NodeShell';

const COLOR = '#b45309';

export default function InAppNotifyNode({ data, isConnectable }) {
  const { t } = useTranslation();
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};
  const [open, setOpen] = useState(false);

  const set = (field, val) =>
    updateNodeData(step.id, 'config', { ...config, [field]: val });

  return (
    <NodeShell
      color={COLOR}
      icon={NotificationsActive}
      label={t('nodes.inAppNotifyNode')}
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

        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.inApp.recipient')}</InputLabel>
          <Select
            value={config.recipient || 'assignee'}
            label={t('nodes.inApp.recipient')}
            onChange={(e) => set('recipient', e.target.value)}
          >
            <MenuItem value="assignee">{t('nodes.email.recipientOwner')}</MenuItem>
            <MenuItem value="uploader">{t('nodes.email.recipientUploader')}</MenuItem>
            <MenuItem value="admins">{t('nodes.email.recipientAdmins')}</MenuItem>
          </Select>
        </FormControl>

        <TextField
          size="small"
          fullWidth
          label={t('nodes.inApp.title')}
          value={config.title || ''}
          onChange={(e) => set('title', e.target.value)}
          className="nodrag"
        />

        <TextField
          size="small"
          fullWidth
          multiline
          rows={2}
          label={t('nodes.inApp.message')}
          placeholder={t('nodes.tokenHint')}
          value={config.message || ''}
          onChange={(e) => set('message', e.target.value)}
          className="nodrag"
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
          <Stack spacing={1.5}>
            <FormControl size="small" fullWidth className="nodrag">
              <InputLabel>{t('nodes.inApp.priority')}</InputLabel>
              <Select
                value={config.priority || 'normal'}
                label={t('nodes.inApp.priority')}
                onChange={(e) => set('priority', e.target.value)}
              >
                <MenuItem value="normal">{t('nodes.inApp.priorityNormal')}</MenuItem>
                <MenuItem value="high">{t('nodes.inApp.priorityHigh')}</MenuItem>
                <MenuItem value="critical">{t('nodes.inApp.priorityCritical')}</MenuItem>
              </Select>
            </FormControl>
            <TextField
              size="small"
              fullWidth
              label={t('nodes.inApp.actionUrl')}
              placeholder="/dashboard?view=asset_explorer&asset={{asset.id}}"
              value={config.actionUrl || ''}
              onChange={(e) => set('actionUrl', e.target.value)}
              className="nodrag"
            />
          </Stack>
        </AccordionDetails>
      </Accordion>
    </NodeShell>
  );
}

