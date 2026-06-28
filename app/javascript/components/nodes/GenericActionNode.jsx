import React, { useState } from 'react';
import { Handle, Position } from 'reactflow';
import {
  Box, Typography, TextField, Paper, Stack, Accordion, AccordionSummary,
  AccordionDetails, FormControl, InputLabel, Select, MenuItem, Switch,
  FormControlLabel, InputAdornment,
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
  emailNode:        { icon: Email,               color: '#d97706', label: 'Send Email',          fields: ['recipient', 'subject', 'body'] },
  inAppNotifyNode:  { icon: NotificationsActive, color: '#b45309', label: 'In-App Alert',        fields: ['recipient', 'message'] },
  slackNode:        { icon: Chat,                color: '#4a1d96', label: 'Slack Message',       fields: ['channel', 'message'] },
  teamsNode:        { icon: VideoCall,           color: '#1d4ed8', label: 'Teams Message',       fields: ['channel', 'message'] },
  smsNode:          { icon: Sms,                 color: '#065f46', label: 'SMS Alert',           fields: ['phone', 'message'] },
  // Integrations
  webhookNode:      { icon: Webhook,             color: '#0284c7', label: 'Webhook',             fields: ['url', 'method'] },
  secureWebhookNode: { icon: HttpsOutlined,      color: '#075985', label: 'Secure Webhook',      fields: ['url', 'method', 'authType', 'secret'] },
  apiCallNode:      { icon: Api,                 color: '#0369a1', label: 'Custom API Call',     fields: ['url', 'method', 'headers', 'body'] },
  // Asset ops
  setStatusNode:    { icon: Label,               color: '#059669', label: 'Set Asset Status',    fields: ['status'] },
  addTagsNode:      { icon: Label,               color: '#047857', label: 'Add Tags',            fields: ['tags'] },
  removeTagsNode:   { icon: Label,               color: '#b91c1c', label: 'Remove Tags',         fields: ['tags'] },
  moveAssetNode:    { icon: DriveFileMove,       color: '#0d9488', label: 'Move Asset',          fields: ['folder'] },
  copyAssetNode:    { icon: FileCopy,            color: '#0891b2', label: 'Copy Asset',          fields: ['folder'] },
  archiveNode:      { icon: Archive,             color: '#78350f', label: 'Archive Asset',       fields: [] },
  publishNode:      { icon: PublicOutlined,      color: '#15803d', label: 'Publish Asset',       fields: [] },
  metadataUpdateNode: { icon: DataObject,        color: '#1e40af', label: 'Update Metadata',     fields: ['metadataKey', 'metadataValue'] },
  // AI & processing
  aiMetadataNode:   { icon: AutoAwesome,         color: '#7c3aed', label: 'AI Extract Metadata', fields: ['aiTask'] },
  generateThumbNode: { icon: Image,              color: '#6d28d9', label: 'Regenerate Thumbnail', fields: [] },
  cdnSyncNode:      { icon: CloudSync,           color: '#0e7490', label: 'CDN Sync / Purge',    fields: [] },
  // Flow control
  delayNode:        { icon: Timer,               color: '#475569', label: 'Delay / Wait',        fields: ['delayValue', 'delayUnit'] },
  conditionNode:    { icon: CallSplit,           color: '#334155', label: 'Condition Branch',    fields: ['field', 'operator', 'value'], branching: true },
  // Approval variants (rendered by ApprovalNode, but kept here for completeness)
  parallelApprovalNode:   { icon: Groups,        color: '#6d28d9', label: 'Parallel Review',     fields: [] },
  sequentialApprovalNode: { icon: AccountTree,   color: '#5b21b6', label: 'Sequential Review',   fields: [] },
};

// ─── Field renderers ──────────────────────────────────────────────────────────

function ConfigField({ field, config, onChange }) {
  const set = (val) => onChange(field, val);

  switch (field) {
    case 'recipient':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>Recipient</InputLabel>
          <Select value={config.recipient || 'assignee'} label="Recipient" onChange={(e) => set(e.target.value)}>
            <MenuItem value="assignee">Asset Owner</MenuItem>
            <MenuItem value="uploader">Original Uploader</MenuItem>
            <MenuItem value="admins">All Admins</MenuItem>
            <MenuItem value="custom">Custom Address…</MenuItem>
          </Select>
        </FormControl>
      );
    case 'subject':
      return <TextField size="small" fullWidth label="Subject" value={config.subject || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'body':
    case 'message':
      return <TextField size="small" fullWidth multiline rows={2} label="Message" placeholder="Use {{asset.title}}, {{asset.url}} tokens…" value={config[field] || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'channel':
      return <TextField size="small" fullWidth label="Channel / Webhook URL" placeholder="#design-reviews" value={config.channel || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'phone':
      return <TextField size="small" fullWidth label="Phone Number" placeholder="+1…" value={config.phone || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'url':
      return <TextField size="small" fullWidth label="Endpoint URL" placeholder="https://…" value={config.url || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'method':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>HTTP Method</InputLabel>
          <Select value={config.method || 'POST'} label="HTTP Method" onChange={(e) => set(e.target.value)}>
            {['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].map((m) => <MenuItem key={m} value={m}>{m}</MenuItem>)}
          </Select>
        </FormControl>
      );
    case 'authType':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>Auth</InputLabel>
          <Select value={config.authType || 'hmac'} label="Auth" onChange={(e) => set(e.target.value)}>
            <MenuItem value="hmac">HMAC-SHA256 Signature</MenuItem>
            <MenuItem value="bearer">Bearer Token</MenuItem>
            <MenuItem value="basic">Basic Auth</MenuItem>
          </Select>
        </FormControl>
      );
    case 'secret':
      return <TextField size="small" fullWidth type="password" label="Signing Secret / Token" value={config.secret || ''} onChange={(e) => set(e.target.value)} className="nodrag" autoComplete="new-password" />;
    case 'headers':
      return <TextField size="small" fullWidth multiline rows={2} label="Headers (JSON)" placeholder='{"X-Api-Key": "…"}' value={config.headers || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'status':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>New Status</InputLabel>
          <Select value={config.status || 'approved'} label="New Status" onChange={(e) => set(e.target.value)}>
            {['draft', 'pending', 'processing', 'ready', 'in_review', 'approved', 'rejected', 'failed'].map((s) => <MenuItem key={s} value={s}>{s}</MenuItem>)}
          </Select>
        </FormControl>
      );
    case 'tags':
      return <TextField size="small" fullWidth label="Tags (comma-separated)" placeholder="hero, campaign-2026" value={config.tags || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'folder':
      return <TextField size="small" fullWidth label="Target Folder ID / Path" value={config.folder || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'metadataKey':
      return <TextField size="small" fullWidth label="Metadata Key" placeholder="dam:campaign" value={config.metadataKey || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'metadataValue':
      return <TextField size="small" fullWidth label="Metadata Value" value={config.metadataValue || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'aiTask':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>AI Task</InputLabel>
          <Select value={config.aiTask || 'metadata_extraction'} label="AI Task" onChange={(e) => set(e.target.value)}>
            <MenuItem value="metadata_extraction">Metadata Extraction</MenuItem>
            <MenuItem value="seo_enrichment">SEO Enrichment</MenuItem>
            <MenuItem value="visual_context">Deep Visual Context</MenuItem>
          </Select>
        </FormControl>
      );
    case 'delayValue':
      return <TextField size="small" type="number" label="Wait" value={config.delayValue || 1} onChange={(e) => set(e.target.value)} className="nodrag" sx={{ width: 90 }} slotProps={{ htmlInput: { min: 1 } }} />;
    case 'delayUnit':
      return (
        <FormControl size="small" sx={{ minWidth: 110 }} className="nodrag">
          <Select value={config.delayUnit || 'hours'} onChange={(e) => set(e.target.value)}>
            <MenuItem value="minutes">Minutes</MenuItem>
            <MenuItem value="hours">Hours</MenuItem>
            <MenuItem value="days">Days</MenuItem>
          </Select>
        </FormControl>
      );
    case 'field':
      return <TextField size="small" fullWidth label="Asset Field" placeholder="status / properties.content_type" value={config.field || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    case 'operator':
      return (
        <FormControl size="small" fullWidth className="nodrag">
          <InputLabel>Operator</InputLabel>
          <Select value={config.operator || 'equals'} label="Operator" onChange={(e) => set(e.target.value)}>
            <MenuItem value="equals">Equals</MenuItem>
            <MenuItem value="not_equals">Not equals</MenuItem>
            <MenuItem value="contains">Contains</MenuItem>
            <MenuItem value="greater_than">Greater than</MenuItem>
          </Select>
        </FormControl>
      );
    case 'value':
      return <TextField size="small" fullWidth label="Compare Value" value={config.value || ''} onChange={(e) => set(e.target.value)} className="nodrag" />;
    default:
      return null;
  }
}

// ─── Generic Action Node ──────────────────────────────────────────────────────

export default function GenericActionNode({ type, data, isConnectable }) {
  const meta = NODE_META[type] || { icon: DataObject, color: '#64748b', label: 'Action', fields: [] };
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
        <TextField size="small" fullWidth label="Step Title" placeholder={meta.label} value={step.title || ''} onChange={(e) => updateNodeData(step.id, 'title', e.target.value)} className="nodrag" />
        {inlineFields.map((f) => <ConfigField key={f} field={f} config={config} onChange={handleConfigChange} />)}
      </Stack>

      {advancedFields.length > 0 && (
        <Accordion expanded={open} onChange={() => setOpen(!open)} disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, borderTop: '1px solid #e2e8f0' }}>
          <AccordionSummary expandIcon={<ExpandMore />} sx={{ bgcolor: '#f8fafc', minHeight: 40, '& .MuiAccordionSummary-content': { my: 1 } }}>
            <Typography variant="caption" fontWeight="bold" color="text.secondary">Configuration</Typography>
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
            <Typography variant="caption" sx={{ color: '#22c55e', fontWeight: 800 }}>TRUE</Typography>
            <Typography variant="caption" sx={{ color: '#ef4444', fontWeight: 800 }}>FALSE</Typography>
          </Box>
        </>
      ) : (
        <Handle type="source" position={Position.Bottom} style={{ width: 12, height: 12, background: meta.color }} isConnectable={isConnectable} />
      )}
    </Paper>
  );
}

export { NODE_META };

