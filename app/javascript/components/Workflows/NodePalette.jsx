import React, { useState, useEffect } from 'react';
import { Box, Typography, Stack, Tooltip, Divider, TextField, InputAdornment } from '@mui/material';
import {
  HowToReg, Groups, AccountTree,
  Email, NotificationsActive, Chat, VideoCall, Sms,
  Webhook, HttpsOutlined, Api,
  Label, DriveFileMove, FileCopy, Archive, PublicOutlined, DataObject,
  AutoAwesome, Image, CloudSync,
  Timer, CallSplit, Search, AltRoute, Extension,
} from '@mui/icons-material';

// ─── Toolbox Catalogue ────────────────────────────────────────────────────────
const CATEGORIES = [
  {
    id: 'approval',
    label: 'Approval & Review',
    color: '#7c3aed',
    items: [
      { nodeType: 'approvalNode',           label: 'Approval',              icon: HowToReg,            color: '#7c3aed', bg: '#f3e8ff', description: 'Assign to user or group. First-response or unanimous logic.' },
      { nodeType: 'parallelApprovalNode',   label: 'Parallel Review',       icon: Groups,              color: '#6d28d9', bg: '#ede9fe', description: 'All reviewers must approve simultaneously.' },
      { nodeType: 'sequentialApprovalNode', label: 'Sequential Review',     icon: AccountTree,         color: '#5b21b6', bg: '#ddd6fe', description: 'Reviewers are notified one after another.' },
    ],
  },
  {
    id: 'notification',
    label: 'Notifications',
    color: '#d97706',
    items: [
      { nodeType: 'emailNode',         label: 'Send Email',            icon: Email,               color: '#d97706', bg: '#fef3c7', description: 'Send an email to a user, group, or custom address.' },
      { nodeType: 'inAppNotifyNode',   label: 'In-App Alert',          icon: NotificationsActive, color: '#b45309', bg: '#fef9ee', description: 'Push a notification to the DAM inbox.' },
      { nodeType: 'slackNode',         label: 'Slack Message',         icon: Chat,                color: '#4a1d96', bg: '#ede9fe', description: 'Post to a Slack channel or DM.' },
      { nodeType: 'teamsNode',         label: 'Teams Message',         icon: VideoCall,           color: '#1d4ed8', bg: '#eff6ff', description: 'Adaptive card to an MS Teams channel.' },
      { nodeType: 'smsNode',           label: 'SMS Alert',             icon: Sms,                 color: '#065f46', bg: '#ecfdf5', description: 'SMS via Twilio / SNS to a phone number.' },
    ],
  },
  {
    id: 'integration',
    label: 'Integrations',
    color: '#0284c7',
    items: [
      { nodeType: 'webhookNode',        label: 'Webhook',               icon: Webhook,             color: '#0284c7', bg: '#e0f2fe', description: 'HTTP POST to an external URL with asset context.' },
      { nodeType: 'secureWebhookNode',  label: 'Secure Webhook',        icon: HttpsOutlined,       color: '#075985', bg: '#e0f2fe', description: 'Webhook with HMAC-SHA256 or bearer-token auth.' },
      { nodeType: 'apiCallNode',        label: 'Custom API Call',       icon: Api,                 color: '#0369a1', bg: '#f0f9ff', description: 'Configurable HTTP method, headers and body.' },
    ],
  },
  {
    id: 'asset_ops',
    label: 'Asset Operations',
    color: '#059669',
    items: [
      { nodeType: 'setStatusNode',      label: 'Set Asset Status',      icon: Label,               color: '#059669', bg: '#ecfdf5', description: 'Change the asset status (draft, approved…).' },
      { nodeType: 'addTagsNode',        label: 'Add Tags',              icon: Label,               color: '#047857', bg: '#d1fae5', description: 'Append one or more tags to asset metadata.' },
      { nodeType: 'removeTagsNode',     label: 'Remove Tags',           icon: Label,               color: '#b91c1c', bg: '#fef2f2', description: 'Remove specific tags from the asset.' },
      { nodeType: 'moveAssetNode',      label: 'Move Asset',            icon: DriveFileMove,       color: '#0d9488', bg: '#f0fdfa', description: 'Move the asset to a target folder.' },
      { nodeType: 'copyAssetNode',      label: 'Copy Asset',            icon: FileCopy,            color: '#0891b2', bg: '#ecfeff', description: 'Duplicate into another folder.' },
      { nodeType: 'archiveNode',        label: 'Archive',               icon: Archive,             color: '#78350f', bg: '#fef3c7', description: 'Soft-archive — hidden from search.' },
      { nodeType: 'publishNode',        label: 'Publish',               icon: PublicOutlined,      color: '#15803d', bg: '#f0fdf4', description: 'Mark asset published and sync to CDN.' },
      { nodeType: 'metadataUpdateNode', label: 'Update Metadata',       icon: DataObject,          color: '#1e40af', bg: '#eff6ff', description: 'Set metadata key-value pairs on the asset.' },
    ],
  },
  {
    id: 'ai',
    label: 'AI & Processing',
    color: '#7c3aed',
    items: [
      { nodeType: 'aiMetadataNode',     label: 'AI Extract Metadata',   icon: AutoAwesome,         color: '#7c3aed', bg: '#f5f3ff', description: 'Run AI metadata extraction (tags, alt-text, description).' },
      { nodeType: 'generateThumbNode',  label: 'Regenerate Thumbnail',  icon: Image,               color: '#6d28d9', bg: '#f3e8ff', description: 'Trigger thumbnail regen for all configured profiles.' },
      { nodeType: 'cdnSyncNode',        label: 'CDN Sync / Purge',      icon: CloudSync,           color: '#0e7490', bg: '#ecfeff', description: 'Purge CDN caches and re-sync to all edge nodes.' },
    ],
  },
  {
    id: 'flow',
    label: 'Flow Control',
    color: '#475569',
    items: [
      { nodeType: 'delayNode',          label: 'Delay / Wait',          icon: Timer,               color: '#475569', bg: '#f8fafc', description: 'Pause workflow for N hours or days.' },
      { nodeType: 'conditionNode',      label: 'Condition Branch',      icon: CallSplit,            color: '#334155', bg: '#f1f5f9', description: 'Branch on asset metadata or status value.' },
      { nodeType: 'switchNode',         label: 'Switch / Multi-branch', icon: AltRoute,             color: '#0f766e', bg: '#f0fdfa', description: 'Route to one of many outputs by matching a field against ordered cases.' },
    ],
  },
];

function ToolItem({ nodeType, label, icon: Icon, color, bg, description, customDef }) {
  const onDragStart = (e) => {
    e.dataTransfer.setData('application/reactflow', nodeType);
    if (customDef) {
      e.dataTransfer.setData('application/reactflow-custom', JSON.stringify(customDef));
    }
    e.dataTransfer.effectAllowed = 'move';
  };
  return (
    <Tooltip title={description} placement="right" arrow>
      <Box
        draggable onDragStart={onDragStart}
        sx={{
          display: 'flex', alignItems: 'center', gap: 1.5,
          px: 1.5, py: 0.9, borderRadius: 1.5,
          border: '1px solid transparent', cursor: 'grab', userSelect: 'none',
          transition: 'all 0.15s',
          '&:hover': { border: `1px solid ${color}`, bgcolor: bg, '& .ti': { color } },
          '&:active': { cursor: 'grabbing', opacity: 0.75 },
        }}
      >
        <Icon className="ti" sx={{ fontSize: 15, color: '#94a3b8', flexShrink: 0, transition: 'color 0.15s' }} />
        <Typography variant="caption" sx={{ fontWeight: 600, color: '#334155', lineHeight: 1.2 }}>{label}</Typography>
      </Box>
    </Tooltip>
  );
}

export default function NodePalette() {
  const [search, setSearch] = useState('');
  const [customNodes, setCustomNodes] = useState([]);
  const q = search.toLowerCase();

  useEffect(() => {
    let active = true;
    fetch('/api/v1/custom_node_definitions', { headers: { Accept: 'application/json' } })
      .then((res) => (res.ok ? res.json() : { items: [] }))
      .then((data) => {
        if (!active) return;
        const enabled = (data.items || []).filter((d) => d.status === 'enabled');
        setCustomNodes(enabled);
      })
      .catch(() => { /* palette still works without custom nodes */ });
    return () => { active = false; };
  }, []);

  const customCategory = customNodes.length > 0 ? {
    id: 'custom',
    label: 'Custom Nodes',
    color: '#6366f1',
    items: customNodes.map((d) => ({
      nodeType: 'customNode',
      itemKey: `custom_${d.key}`,
      label: d.name,
      icon: Extension,
      color: d.color || '#6366f1',
      bg: '#eef2ff',
      description: d.description || 'Tenant-registered custom workflow node.',
      customDef: d,
    })),
  } : null;

  const catalogue = customCategory ? [...CATEGORIES, customCategory] : CATEGORIES;

  const filtered = catalogue.map(c => ({ ...c, items: c.items.filter(i => i.label.toLowerCase().includes(q) || i.description.toLowerCase().includes(q)) })).filter(c => c.items.length > 0);

  return (
    <Box sx={{ width: 210, flexShrink: 0, borderRight: '1px solid #e2e8f0', bgcolor: '#f8fafc', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      {/* Header */}
      <Box sx={{ px: 2, pt: 2, pb: 1.5, borderBottom: '1px solid #e2e8f0', bgcolor: '#ffffff' }}>
        <Typography variant="overline" fontWeight={800} sx={{ color: '#475569', letterSpacing: '0.1em', display: 'block', mb: 1, fontSize: '0.65rem' }}>
          🧩 Toolbox
        </Typography>
        <TextField size="small" placeholder="Search…" value={search} onChange={e => setSearch(e.target.value)} fullWidth
          slotProps={{ input: { startAdornment: <InputAdornment position="start"><Search sx={{ fontSize: 14, color: '#94a3b8' }} /></InputAdornment>, sx: { fontSize: '0.75rem' } } }}
          sx={{ '& .MuiOutlinedInput-root': { borderRadius: 1.5 } }}
        />
      </Box>

      {/* Items */}
      <Box sx={{ overflowY: 'auto', flexGrow: 1, px: 1.5, py: 1.5 }}>
        {filtered.map((cat, ci) => (
          <Box key={cat.id} sx={{ mb: 1.5 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, mb: 0.5, px: 0.5 }}>
              <Box sx={{ width: 7, height: 7, borderRadius: '50%', bgcolor: cat.color, flexShrink: 0 }} />
              <Typography variant="caption" sx={{ fontWeight: 700, color: cat.color, fontSize: '0.62rem', letterSpacing: '0.08em', textTransform: 'uppercase' }}>{cat.label}</Typography>
            </Box>
            <Stack spacing={0.25}>{cat.items.map(item => <ToolItem key={item.itemKey || item.nodeType} {...item} />)}</Stack>
            {ci < filtered.length - 1 && <Divider sx={{ mt: 1.5 }} />}
          </Box>
        ))}
        {filtered.length === 0 && <Typography variant="caption" sx={{ color: '#94a3b8', display: 'block', textAlign: 'center', mt: 3 }}>No matches for "{search}"</Typography>}
      </Box>

      {/* Footer */}
      <Box sx={{ px: 2, py: 1.5, borderTop: '1px solid #e2e8f0', bgcolor: '#ffffff' }}>
        <Typography variant="caption" sx={{ color: '#94a3b8', fontSize: '0.62rem', lineHeight: 1.4 }}>Drag a component onto the canvas to add it.</Typography>
      </Box>
    </Box>
  );
}
