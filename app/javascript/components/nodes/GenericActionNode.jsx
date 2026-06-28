import React, { useState } from 'react';
import { Handle, Position } from '@xyflow/react';
import { useTranslation } from 'react-i18next';
import {
  Box, Typography, TextField, Paper, Stack, Accordion, AccordionSummary,
  AccordionDetails, FormControl, InputLabel, Select, MenuItem,
  FormControlLabel, Switch,
} from '@mui/material';
import {
  ExpandMore, Email, NotificationsActive, Chat, VideoCall, Sms,
  Webhook, HttpsOutlined, Api, Label, DriveFileMove, FileCopy, Archive,
  PublicOutlined, DataObject, AutoAwesome, Image, CloudSync, Timer, CallSplit,
  Groups, AccountTree,
} from '@mui/icons-material';

// ─── Node-type metadata ───────────────────────────────────────────────────────
// Maps each node `type` to its icon, accent colour, header label, and which
// config fields to render in the body.

const NODE_META = {
  // Notifications
  emailNode:        { icon: Email,               color: '#d97706', label: 'Send Email',           fields: ['recipient', 'subject', 'body'],                    backendType: 'email_notification' },
  inAppNotifyNode:  { icon: NotificationsActive, color: '#b45309', label: 'In-App Alert',         fields: ['recipient', 'message'],                            backendType: 'in_app_notification' },
  slackNode:        { icon: Chat,                color: '#4a1d96', label: 'Slack Message',        fields: ['channel', 'message'],                              backendType: 'slack' },
  teamsNode:        { icon: VideoCall,           color: '#1d4ed8', label: 'Teams Message',        fields: ['channel', 'message'],                              backendType: 'teams' },
  smsNode:          { icon: Sms,                 color: '#065f46', label: 'SMS Alert',            fields: ['phone', 'message'],                                backendType: 'sms' },
  // Integrations
  webhookNode:      { icon: Webhook,             color: '#0284c7', label: 'Webhook',              fields: ['url', 'method'],                                   backendType: 'webhook' },
  secureWebhookNode:{ icon: HttpsOutlined,       color: '#075985', label: 'Secure Webhook',       fields: ['url', 'method', 'authType', 'secret'],             backendType: 'secure_webhook' },
  apiCallNode:      { icon: Api,                 color: '#0369a1', label: 'Custom API Call',      fields: ['url', 'method', 'headers', 'body'],                backendType: 'api_call' },
  // Asset ops
  setStatusNode:    { icon: Label,               color: '#059669', label: 'Set Asset Status',     fields: ['status'],                                          backendType: 'set_status' },
  addTagsNode:      { icon: Label,               color: '#047857', label: 'Add Tags',             fields: ['tags'],                                            backendType: 'add_tags' },
  removeTagsNode:   { icon: Label,               color: '#b91c1c', label: 'Remove Tags',          fields: ['tags'],                                            backendType: 'remove_tags' },
  moveAssetNode:    { icon: DriveFileMove,       color: '#0d9488', label: 'Move Asset',           fields: ['folder'],                                          backendType: 'move_asset' },
  copyAssetNode:    { icon: FileCopy,            color: '#0891b2', label: 'Copy Asset',           fields: ['folder'],                                          backendType: 'copy_asset' },
  archiveNode:      { icon: Archive,             color: '#78350f', label: 'Archive Asset',        fields: [],                                                  backendType: 'archive' },
  publishNode:      { icon: PublicOutlined,      color: '#15803d', label: 'Publish Asset',        fields: [],                                                  backendType: 'publish' },
  metadataUpdateNode:{ icon: DataObject,         color: '#1e40af', label: 'Update Metadata',      fields: ['metadataKey', 'metadataValue'],                     backendType: 'update_metadata' },
  // AI & processing
  aiMetadataNode:   { icon: AutoAwesome,         color: '#7c3aed', label: 'AI Extract Metadata',  fields: ['aiTask'],                                          backendType: 'ai_metadata' },
  generateThumbNode:{ icon: Image,               color: '#6d28d9', label: 'Regenerate Thumbnail', fields: [],                                                  backendType: 'generate_thumbnail' },
  cdnSyncNode:      { icon: CloudSync,           color: '#0e7490', label: 'CDN Sync / Purge',     fields: [],                                                  backendType: 'cdn_sync' },
  // Flow control
  delayNode:        { icon: Timer,               color: '#475569', label: 'Delay / Wait',         fields: ['delayValue', 'delayUnit'],                         backendType: 'delay' },
  conditionNode:    { icon: CallSplit,           color: '#334155', label: 'Condition Branch',     fields: ['field', 'operator', 'value'], branching: true,     backendType: 'condition' },
  // Approval variants (rendered by ApprovalNode, but kept here for completeness)
  parallelApprovalNode:   { icon: Groups,        color: '#6d28d9', label: 'Parallel Review',      fields: [],                                                  backendType: 'approval' },
  sequentialApprovalNode: { icon: AccountTree,   color: '#5b21b6', label: 'Sequential Review',    fields: [],                                                  backendType: 'approval' },
};

// ─── Field renderers ──────────────────────────────────────────────────────────

function ConfigField({ field, config, onChange }) {
  const { t } = useTranslation();
  const set = (val) => onChange(field, val);

  switch (field) {
    case 'recipient':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.email.recipient')}</InputLabel>
          <Select value={config.recipient || 'assignee'} label={t('nodes.email.recipient')} onChange={(e) => set(e.target.value)}>
            <MenuItem value="assignee">{t('nodes.email.recipientOwner')}</MenuItem>
            <MenuItem value="uploader">{t('nodes.email.recipientUploader')}</MenuItem>
            <MenuItem value="admins">{t('nodes.email.recipientAdmins')}</MenuItem>
            <MenuItem value="custom">{t('nodes.email.recipientCustom')}</MenuItem>
          </Select>
        </FormControl>
      );
    case 'subject':
      return <TextField size="small" fullWidth label={t('nodes.email.subject')} value={config.subject || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'message':
      return <TextField size="small" fullWidth multiline rows={2} label="Message" placeholder={t('nodes.tokenHint')} value={config[field] || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'channel':
      return <TextField size="small" fullWidth label={t('nodes.slack.channel')} placeholder={t('nodes.slack.channelPlaceholder')} value={config.channel || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'phone':
      return <TextField size="small" fullWidth label={t('nodes.sms.phone')} placeholder={t('nodes.sms.phonePlaceholder')} value={config.phone || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'url':
      return <TextField size="small" fullWidth label={t('nodes.webhook.url')} placeholder="https://…" value={config.url || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'method':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.webhook.method')}</InputLabel>
          <Select value={config.method || 'POST'} label={t('nodes.webhook.method')} onChange={(e) => set(e.target.value)}>
            {['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].map((m) => <MenuItem key={m} value={m}>{m}</MenuItem>)}
          </Select>
        </FormControl>
      );
    case 'authType':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.secureWebhook.authType')}</InputLabel>
          <Select value={config.authType || 'hmac'} label={t('nodes.secureWebhook.authType')} onChange={(e) => set(e.target.value)}>
            <MenuItem value="hmac">{t('nodes.secureWebhook.authHmac')}</MenuItem>
            <MenuItem value="bearer">{t('nodes.secureWebhook.authBearer')}</MenuItem>
            <MenuItem value="basic">{t('nodes.secureWebhook.authBasic')}</MenuItem>
          </Select>
        </FormControl>
      );
    case 'secret':
      return <TextField size="small" fullWidth type="password" label={t('nodes.secureWebhook.secret')} value={config.secret || ''} onChange={(e) => set(e.target.value)} className="nodrag" autoComplete="new-password" />;
    case 'headers':
      return <TextField size="small" fullWidth multiline rows={2} label={t('nodes.webhook.headers')} placeholder={t('nodes.webhook.headersPlaceholder')} value={config.headers || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'body':
      return <TextField size="small" fullWidth multiline rows={2} label={t('nodes.apiCall.body')} placeholder='{"key": "value"}' value={config.body || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'status':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.setStatus.newStatus')}</InputLabel>
          <Select value={config.status || 'approved'} label={t('nodes.setStatus.newStatus')} onChange={(e) => set(e.target.value)}>
            {['draft', 'pending', 'processing', 'ready', 'in_review', 'approved', 'rejected', 'failed'].map((s) => <MenuItem key={s} value={s}>{s}</MenuItem>)}
          </Select>
        </FormControl>
      );
    case 'tags':
      return <TextField size="small" fullWidth label={t('nodes.tags.tagsLabel')} placeholder={t('nodes.tags.tagsPlaceholder')} value={config.tags || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'folder':
      return <TextField size="small" fullWidth label={t('nodes.moveAsset.folder')} placeholder={t('nodes.moveAsset.folderPlaceholder')} value={config.folder || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'metadataKey':
      return <TextField size="small" fullWidth label={t('nodes.metadata.key')} placeholder={t('nodes.metadata.keyPlaceholder')} value={config.metadataKey || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'metadataValue':
      return <TextField size="small" fullWidth label={t('nodes.metadata.value')} placeholder={t('nodes.metadata.valuePlaceholder')} value={config.metadataValue || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'aiTask':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.ai.task')}</InputLabel>
          <Select value={config.aiTask || 'metadata_extraction'} label={t('nodes.ai.task')} onChange={(e) => set(e.target.value)}>
            <MenuItem value="metadata_extraction">{t('nodes.ai.taskExtract')}</MenuItem>
            <MenuItem value="seo_enrichment">{t('nodes.ai.taskSeo')}</MenuItem>
            <MenuItem value="visual_context">{t('nodes.ai.taskVisual')}</MenuItem>
          </Select>
        </FormControl>
      );
    case 'delayValue':
      return <TextField size="small" type="number" label={t('nodes.delay.duration')} value={config.delayValue || 1} onChange={(e) => set(e.target.value)} className="nodrag" sx={{ width: 90 }} slotProps={{ htmlInput: { min: 1 } }} />;
    case 'delayUnit':
      return (
        <FormControl size="small" sx={{ minWidth: 110 }} className="nodrag">
          <Select value={config.delayUnit || 'hours'} onChange={(e) => set(e.target.value)}>
            <MenuItem value="minutes">{t('nodes.delay.unitMinutes')}</MenuItem>
            <MenuItem value="hours">{t('nodes.delay.unitHours')}</MenuItem>
            <MenuItem value="days">{t('nodes.delay.unitDays')}</MenuItem>
          </Select>
        </FormControl>
      );
    case 'field':
      return <TextField size="small" fullWidth label={t('nodes.condition.field')} placeholder={t('nodes.condition.fieldPlaceholder')} value={config.field || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'operator':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>{t('nodes.condition.operator')}</InputLabel>
          <Select value={config.operator || 'equals'} label={t('nodes.condition.operator')} onChange={(e) => set(e.target.value)}>
            <MenuItem value="equals">{t('nodes.condition.opEquals')}</MenuItem>
            <MenuItem value="not_equals">{t('nodes.condition.opNotEquals')}</MenuItem>
            <MenuItem value="contains">{t('nodes.condition.opContains')}</MenuItem>
            <MenuItem value="starts_with">{t('nodes.condition.opStartsWith')}</MenuItem>
            <MenuItem value="ends_with">{t('nodes.condition.opEndsWith')}</MenuItem>
            <MenuItem value="greater_than">{t('nodes.condition.opGreaterThan')}</MenuItem>
            <MenuItem value="less_than">{t('nodes.condition.opLessThan')}</MenuItem>
          </Select>
        </FormControl>
      );
    case 'value':
      return <TextField size="small" fullWidth label={t('nodes.condition.compareValue')} value={config.value || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    default:
      return null;
  }
}

// ─── Generic Action Node (fallback renderer) ──────────────────────────────────

export default function GenericActionNode({ type, data, isConnectable }) {
  const { t } = useTranslation();
  const meta = NODE_META[type] || { icon: DataObject, color: '#64748b', label: 'Action', fields: [], branching: false };
  const Icon = meta.icon;
  const { step = {}, updateNodeData } = data;
  const config = step.config || {};
  const [open, setOpen] = useState(true);

  const handleConfigChange = (field, value) => {
    updateNodeData(step.id, 'config', { ...config, [field]: value });
  };

  const inlineFields = meta.fields.slice(0, 2);
  const advancedFields = meta.fields.slice(2);

  return (
    <Paper elevation={3} sx={{ width: 320, borderRadius: 2, borderTop: `5px solid ${meta.color}`, bgcolor: '#fff', overflow: 'hidden' }}>
      <Handle type="target" position={Position.Top} isConnectable={isConnectable} style={{ width: 12, height: 12, background: meta.color }} />

      <Box sx={{ px: 2, py: 1.25, bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: 1 }}>
        <Icon sx={{ color: meta.color, fontSize: 18 }} />
        <Typography variant="subtitle2" sx={{ fontWeight: 800, color: '#1e293b' }}>{meta.label}</Typography>
      </Box>

      <Stack spacing={1.5} sx={{ p: 2 }}>
        <TextField size="small" fullWidth label={t('nodes.stepTitle')} placeholder={meta.label} value={step.title || ''} onChange={(e) => updateNodeData(step.id, 'title', e.target.value)} className="nodrag" />
        {inlineFields.map((f) => <ConfigField key={f} field={f} config={config} onChange={handleConfigChange} />)}
      </Stack>

      {advancedFields.length > 0 && (
        <Accordion expanded={open} onChange={() => setOpen(!open)} disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, borderTop: '1px solid #e2e8f0' }}>
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ bgcolor: '#f8fafc', minHeight: 40, '& .MuiAccordionSummary-content': { my: 1 } }}>
            <Typography variant="caption" fontWeight="bold" color="text.secondary">{t('nodes.configSection')}</Typography>
          </AccordionSummary>
          <AccordionDetails sx={{ pt: 1, pb: 2, px: 2 }}>
            <Stack spacing={1.5}>{advancedFields.map((f) => <ConfigField key={f} field={f} config={config} onChange={handleConfigChange} />)}</Stack>
          </AccordionDetails>
        </Accordion>
      )}

      {meta.branching ? (
        <>
          <Handle type="source" position={Position.Bottom} id="true" style={{ left: '25%', background: '#22c55e', width: 12, height: 12 }} isConnectable={isConnectable} />
          <Handle type="source" position={Position.Bottom} id="false" style={{ left: '75%', background: '#ef4444', width: 12, height: 12 }} isConnectable={isConnectable} />
          <Box sx={{ display: 'flex', justifyContent: 'space-between', px: 3, pb: 1, pt: 0.5, bgcolor: '#f8fafc', borderTop: '1px solid #e2e8f0' }}>
            <Typography variant="caption" sx={{ color: '#22c55e', fontWeight: 800 }}>{t('nodes.condition.trueBranch')}</Typography>
            <Typography variant="caption" sx={{ color: '#ef4444', fontWeight: 800 }}>{t('nodes.condition.falseBranch')}</Typography>
          </Box>
        </>
      ) : (
        <Handle type="source" position={Position.Bottom} style={{ width: 12, height: 12, background: meta.color }} isConnectable={isConnectable} />
      )}
    </Paper>
  );
}

export { NODE_META };
