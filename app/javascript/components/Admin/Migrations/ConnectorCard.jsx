import React from 'react';
import {
    Box, Typography, Card, CardContent, CardActions,
    Chip, Divider, Stack, Switch, Tooltip, Button, IconButton
} from '@mui/material';
import {
    AccountTree, Storage, CloudSync, AutoFixHigh,
    SettingsInputComponent, ContentCopy, Webhook, QueryStats, RocketLaunch
} from '@mui/icons-material';
import { useNotify } from "../../../context/NotificationContext";
import { DAM_PROVIDERS } from './ConnectorDialog';

const getProviderLabel = (type) =>
    DAM_PROVIDERS[type?.toLowerCase()]?.label || type || 'Unknown Provider';

const getSystemIcon = (type) => {
    const t = type?.toLowerCase();
    if (t === 'aem')          return <AccountTree sx={{ color: '#ef4444', fontSize: 32 }} />;
    if (t === 'legacy_s3')    return <Storage sx={{ color: '#f59e0b', fontSize: 32 }} />;
    if (t === 'bynder')       return <CloudSync sx={{ color: '#0ea5e9', fontSize: 32 }} />;
    if (t === 'widen')        return <CloudSync sx={{ color: '#7c3aed', fontSize: 32 }} />;
    if (t === 'cloudinary')   return <Storage sx={{ color: '#3b82f6', fontSize: 32 }} />;
    if (t === 'sharepoint')   return <Storage sx={{ color: '#0078D4', fontSize: 32 }} />;
    return <CloudSync sx={{ color: '#3b82f6', fontSize: 32 }} />;
};

export default function ConnectorCard({ conn, onEdit, onToggleStatus, onStartMigration }) {
    const notify = useNotify();

    const copyToClipboard = (text, label) => {
        navigator.clipboard.writeText(text);
        notify(`${label} copied to clipboard`, 'success');
    };

    return (
        <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, opacity: conn.status === 'disabled' ? 0.7 : 1, transition: 'opacity 0.2s' }}>
            <CardContent sx={{ p: 3 }}>
                <Stack direction="row" justifyContent="space-between" alignItems="flex-start" sx={{ mb: 1.5 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                        <Box sx={{ p: 1, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0', display: 'flex' }}>
                            {getSystemIcon(conn.provider_type)}
                        </Box>
                        <Box>
                            <Typography variant="overline" sx={{ fontWeight: 700, color: '#64748b', lineHeight: 1 }}>
                                {getProviderLabel(conn.provider_type)}
                            </Typography>
                            <Typography variant="h6" sx={{ fontWeight: 600, lineHeight: 1.2 }}>{conn.name}</Typography>
                        </Box>
                    </Box>

                    <Tooltip title={conn.status === 'active' ? "Pause Ingestion" : "Resume Ingestion"}>
                        <Switch size="small" checked={conn.status === 'active'} onChange={() => onToggleStatus(conn)} color="success" />
                    </Tooltip>
                </Stack>

                <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
                    <Chip
                        label={conn.status?.toUpperCase()} size="small"
                        color={conn.status === 'active' ? 'success' : conn.status === 'disabled' ? 'error' : 'warning'}
                        sx={{ height: 20, fontSize: '0.65rem', fontWeight: 700 }}
                    />
                    <Typography variant="caption" sx={{ fontFamily: 'monospace', color: '#64748b', wordBreak: 'break-all' }}>
                        {conn.endpoint}
                    </Typography>
                </Stack>

                <Divider sx={{ my: 2 }} />

                <Stack spacing={1.5}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                        <Typography variant="body2" color="textSecondary">Assets Imported:</Typography>
                        <Typography variant="body2" sx={{ fontWeight: 600 }}>{conn.assets_imported?.toLocaleString() ?? '—'}</Typography>
                    </Box>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <Typography variant="body2" color="textSecondary">AI TDM Pipeline:</Typography>
                        {conn.tdm_sanitation ? (
                            <Chip icon={<AutoFixHigh sx={{ fontSize: '1rem' }} />} label="Active" size="small" sx={{ bgcolor: '#f3e8ff', color: '#7e22ce', height: 20 }} />
                        ) : (
                            <Chip label="Bypassed" size="small" sx={{ height: 20 }} />
                        )}
                    </Box>
                </Stack>

                {conn.analysis_report && (
                    <Box sx={{ mt: 2, p: 1.5, bgcolor: '#f0fdf4', border: '1px solid #bbf7d0', borderRadius: 2 }}>
                        <Typography variant="caption" sx={{ fontWeight: 700, color: '#166534' }}>
                            Health Scan: {conn.analysis_report.total_found} assets found, {conn.analysis_report.missing_tags} require AI enrichment.
                        </Typography>
                    </Box>
                )}
            </CardContent>

            <Divider />

            {/* Webhook Section */}
            <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px dashed #cbd5e1', m: 2, mb: 0 }}>
                <Typography variant="caption" sx={{ fontWeight: 700, color: '#475569', display: 'flex', alignItems: 'center', gap: 0.5, mb: 1.5, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                    <Webhook fontSize="small" /> Event Webhook
                </Typography>
                <Stack spacing={1}>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <Box sx={{ overflow: 'hidden' }}>
                            <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 0.2 }}>Endpoint URL</Typography>
                            <Typography variant="body2" sx={{ fontFamily: 'monospace', fontWeight: 600, color: '#0ea5e9' }}>
                                {`${window.location.origin}/api/v1/webhooks/connectors/${conn.id}/receive`}
                            </Typography>
                        </Box>
                        <IconButton size="small" onClick={() => copyToClipboard(`${window.location.origin}/api/v1/webhooks/connectors/${conn.id}/receive`, 'Endpoint URL')}>
                            <ContentCopy fontSize="small" sx={{ color: '#64748b' }} />
                        </IconButton>
                    </Box>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <Box>
                            <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 0.2 }}>HMAC Secret</Typography>
                            <Typography variant="body2" sx={{ fontFamily: 'monospace', fontWeight: 600, color: '#1e293b' }}>
                                ••••••••••••••••••••••••••••
                            </Typography>
                        </Box>
                        <IconButton size="small" onClick={() => copyToClipboard(conn.webhook_secret || '', 'HMAC Secret')}>
                            <ContentCopy fontSize="small" sx={{ color: '#64748b' }} />
                        </IconButton>
                    </Box>
                </Stack>
            </Box>

            <CardActions sx={{ p: 2, borderTop: '1px solid #f1f5f9', bgcolor: '#f8fafc', display: 'flex', gap: 1, mt: 2 }}>
                <Button variant="outlined" size="small" startIcon={<SettingsInputComponent />} onClick={() => onEdit(conn)}
                    sx={{ textTransform: 'none', borderRadius: '6px', color: '#475569', borderColor: '#cbd5e1', bgcolor: '#ffffff' }}>
                    Configure
                </Button>
                <Button variant="text" size="small" startIcon={<QueryStats />}
                    sx={{ textTransform: 'none', color: '#64748b' }}>
                    Pre-Flight
                </Button>
                <Button variant="contained" size="small" startIcon={<RocketLaunch />}
                    disabled={conn.status !== 'active'}
                    onClick={() => onStartMigration && onStartMigration(conn)}
                    sx={{ textTransform: 'none', borderRadius: '6px', boxShadow: 'none', ml: 'auto', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                    Start Migration
                </Button>
            </CardActions>
        </Card>
    );
}