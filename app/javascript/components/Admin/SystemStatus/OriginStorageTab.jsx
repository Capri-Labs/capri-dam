import React, { useState } from 'react';
import {
    Typography, Paper, TextField,
    CircularProgress, Button, Divider,
    Stack, Grid, FormControl, InputLabel, Select, MenuItem, Alert,
    Chip, Collapse
} from '@mui/material';
import {
    Save, CloudUpload,
    CheckCircle, Error as ErrorIcon, Info, ExpandMore, ExpandLess,
    Storage as StorageIcon
} from '@mui/icons-material';

// ─────────────────────────────────────────────────────────────
// Provider Definitions — drives both the dropdown and the form fields
// ─────────────────────────────────────────────────────────────
const PROVIDERS = {
    local: {
        label: 'Local Disk',
        description: 'Development only. Files stored in /storage/dam on the server.',
        icon: '🖥️',
        color: '#757575',
        fields: [],
        supportsPresign: true,
        supportsAcl: false,
    },
    aws: {
        label: 'Amazon S3',
        description: 'Industry-standard object storage. Best for US/EU compliance.',
        icon: '🟠',
        color: '#FF9900',
        fields: [
            { key: 'access_key', label: 'Access Key ID', type: 'text', required: true },
            { key: 'secret_key', label: 'Secret Access Key', type: 'password', required: true },
            { key: 'region', label: 'Region', type: 'text', placeholder: 'us-east-1', required: true },
            { key: 'bucket', label: 'Bucket Name', type: 'text', required: true },
            { key: 'acl', label: 'Access Control', type: 'select', options: ['private', 'public-read'], default: 'private' },
            { key: 'cdn_base_url', label: 'CloudFront / CDN Base URL', type: 'text', placeholder: 'https://d1234.cloudfront.net' },
        ],
        supportsPresign: true,
        supportsAcl: true,
    },
    cloudflare: {
        label: 'Cloudflare R2',
        description: 'Zero egress fees. S3-compatible. Requires your Account ID.',
        icon: '🟠',
        color: '#F48120',
        fields: [
            { key: 'account_id', label: 'Account ID', type: 'text', required: true, helperText: 'Found in Cloudflare dashboard → R2 → Manage R2 API Tokens' },
            { key: 'access_key', label: 'R2 Access Key ID', type: 'text', required: true },
            { key: 'secret_key', label: 'R2 Secret Access Key', type: 'password', required: true },
            { key: 'bucket', label: 'Bucket Name', type: 'text', required: true },
            { key: 'cdn_base_url', label: 'Custom Domain / Workers.dev URL', type: 'text', placeholder: 'https://assets.yourdomain.com' },
        ],
        supportsPresign: true,
        supportsAcl: false,
    },
    digitalocean: {
        label: 'DigitalOcean Spaces',
        description: 'S3-compatible object storage with built-in CDN edge caching.',
        icon: '🔵',
        color: '#0080FF',
        fields: [
            { key: 'access_key', label: 'Spaces Access Key', type: 'text', required: true },
            { key: 'secret_key', label: 'Spaces Secret Key', type: 'password', required: true },
            { key: 'region', label: 'Region', type: 'text', placeholder: 'nyc3', required: true, helperText: 'e.g. nyc3, ams3, sgp1, fra1' },
            { key: 'bucket', label: 'Space Name', type: 'text', required: true },
            { key: 'acl', label: 'Access Control', type: 'select', options: ['private', 'public-read'], default: 'private' },
            { key: 'cdn_base_url', label: 'CDN Endpoint', type: 'text', placeholder: 'https://myspace.nyc3.cdn.digitaloceanspaces.com' },
        ],
        supportsPresign: true,
        supportsAcl: true,
    },
    wasabi: {
        label: 'Wasabi Hot Storage',
        description: 'No egress fees, no minimum storage duration. S3-compatible.',
        icon: '🟢',
        color: '#3CB371',
        fields: [
            { key: 'access_key', label: 'Access Key', type: 'text', required: true },
            { key: 'secret_key', label: 'Secret Key', type: 'password', required: true },
            { key: 'region', label: 'Region', type: 'text', placeholder: 'us-east-1', required: true, helperText: 'e.g. us-east-1, eu-central-1, ap-northeast-1' },
            { key: 'bucket', label: 'Bucket Name', type: 'text', required: true },
            { key: 'cdn_base_url', label: 'CDN Base URL', type: 'text' },
        ],
        supportsPresign: true,
        supportsAcl: false,
    },
    backblaze: {
        label: 'Backblaze B2',
        description: 'Lowest cost object storage. S3-compatible API (B2 S3 Compatible API).',
        icon: '🔴',
        color: '#CC0000',
        fields: [
            { key: 'access_key', label: 'Application Key ID', type: 'text', required: true, helperText: 'The keyID from your Backblaze Application Key (not Master Key)' },
            { key: 'secret_key', label: 'Application Key', type: 'password', required: true },
            { key: 'region', label: 'Region', type: 'text', placeholder: 'us-west-002', required: true, helperText: 'e.g. us-west-002, eu-central-003' },
            { key: 'bucket', label: 'Bucket Name', type: 'text', required: true },
            { key: 'cdn_base_url', label: 'Cloudflare CDN URL (optional)', type: 'text', placeholder: 'https://cdn.yourdomain.com' },
        ],
        supportsPresign: true,
        supportsAcl: false,
    },
    google: {
        label: 'Google Cloud Storage',
        description: 'Enterprise-grade GCS with V4 signed URLs and Cloud CDN support.',
        icon: '🔷',
        color: '#4285F4',
        fields: [
            { key: 'project_id', label: 'GCP Project ID', type: 'text', required: true },
            { key: 'credentials_json', label: 'Service Account JSON', type: 'multiline', required: true, helperText: 'Paste the full service account JSON key (or provide a file path)' },
            { key: 'bucket', label: 'Bucket Name', type: 'text', required: true },
            { key: 'acl', label: 'Access Control', type: 'select', options: ['private', 'public-read'], default: 'private' },
            { key: 'cdn_base_url', label: 'Cloud CDN / Custom Domain URL', type: 'text', placeholder: 'https://cdn.yourdomain.com' },
        ],
        supportsPresign: true,
        supportsAcl: true,
    },
    azure: {
        label: 'Azure Blob Storage',
        description: 'Microsoft Azure enterprise storage with SAS token presigning.',
        icon: '🔷',
        color: '#0078D4',
        fields: [
            { key: 'account_name', label: 'Storage Account Name', type: 'text', required: true },
            { key: 'account_key', label: 'Account Key', type: 'password', required: true, helperText: 'Found in Azure Portal → Storage Account → Access keys' },
            { key: 'container', label: 'Container Name', type: 'text', required: true, helperText: 'Equivalent to a bucket' },
            { key: 'acl', label: 'Access Control', type: 'select', options: ['private', 'public-read'], default: 'private' },
            { key: 'cdn_base_url', label: 'Azure CDN Endpoint URL', type: 'text', placeholder: 'https://myendpoint.azureedge.net' },
        ],
        supportsPresign: true,
        supportsAcl: true,
    },
};

// ─────────────────────────────────────────────────────────────
// Origin Storage — storage backend configuration (provider credentials).
// Rendered as the "Origin Storage" sub-tab under Settings → System →
// Storage & Edge. Moved here from the general /settings page so that
// provider credentials live alongside the rest of the System Operations
// console. System Administration (service accounts) remains on the
// general /settings page (see app/javascript/components/Settings.jsx).
// ─────────────────────────────────────────────────────────────
export default function OriginStorageTab(props) {
    const [loading, setLoading] = useState(false);
    const [testStatus, setTestStatus] = useState({ loading: false, msg: null, error: null });
    const [saveStatus, setSaveStatus] = useState(null);
    const [showAdvanced, setShowAdvanced] = useState(false);

    const parsedAllConfigs = React.useMemo(() => (
        typeof props.allConfigs === 'string'
            ? JSON.parse(props.allConfigs || '{}')
            : (props.allConfigs || {})
    ), [props.allConfigs]);
    const [allConfigs, setAllConfigs] = useState(parsedAllConfigs);
    const [storageProvider, setStorageProvider] = useState(props.activeProvider || 'local');

    const currentStorageConfigs = allConfigs[storageProvider] || {};
    const providerDef = PROVIDERS[storageProvider] || PROVIDERS.local;

    const updateField = (field, value) => {
        setAllConfigs(prev => ({
            ...prev,
            [storageProvider]: { ...(prev[storageProvider] || {}), [field]: value }
        }));
    };

    const handleProviderSwitch = (newProvider) => {
        setStorageProvider(newProvider);
        setTestStatus({ loading: false, msg: null, error: null });
        setSaveStatus(null);
    };

    const handleClear = () => {
        if (window.confirm(`Clear all unsaved fields for ${PROVIDERS[storageProvider]?.label}?`)) {
            setAllConfigs(prev => ({ ...prev, [storageProvider]: {} }));
            setSaveStatus(null);
            setTestStatus({ loading: false, msg: null, error: null });
        }
    };

    const buildPayload = () => ({
        storage_config: { provider: storageProvider, ...allConfigs[storageProvider] }
    });

    const handleSaveStorage = async () => {
        setLoading(true);
        setSaveStatus(null);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const response = await fetch('/settings/update_storage', {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(buildPayload())
            });
            const data = await response.json();
            if (response.ok) {
                setSaveStatus({ success: true, msg: data.message });
            } else {
                setSaveStatus({ success: false, msg: data.error || 'Save failed' });
            }
        } catch {
            setSaveStatus({ success: false, msg: 'Network error occurred.' });
        } finally {
            setLoading(false);
        }
    };

    const handleTestConnection = async () => {
        setTestStatus({ loading: true, msg: null, error: null });
        try {
            const response = await fetch('/settings/test_connection', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                },
                body: JSON.stringify(buildPayload())
            });
            const data = await response.json();
            if (response.ok && data.success) {
                setTestStatus({ loading: false, msg: data.message, error: null });
            } else {
                setTestStatus({ loading: false, msg: null, error: data.error || 'Connection failed' });
            }
        } catch {
            setTestStatus({ loading: false, msg: null, error: 'Network error occurred.' });
        }
    };

    // ─────────────────────────────────────────────────────────────
    // Render a single field based on its definition
    // ─────────────────────────────────────────────────────────────
    const renderField = (fieldDef) => {
        const val = currentStorageConfigs[fieldDef.key] || '';

        if (fieldDef.type === 'select') {
            return (
                <Grid size={{ xs: 12, md: 6 }} sx={{ p: 1 }} key={fieldDef.key}>
                    <FormControl fullWidth sx={{ bgcolor: 'white' }}>
                        <InputLabel>{fieldDef.label}</InputLabel>
                        <Select
                            variant="outlined"
                            value={val || fieldDef.default || ''}
                            label={fieldDef.label}
                            onChange={(e) => updateField(fieldDef.key, e.target.value)}
                        >
                            {fieldDef.options.map(opt => (
                                <MenuItem key={opt} value={opt}>
                                    {opt === 'private' ? '🔒 Private (Presigned URLs)' : '🌐 Public Read'}
                                </MenuItem>
                            ))}
                        </Select>
                    </FormControl>
                </Grid>
            );
        }

        if (fieldDef.type === 'multiline') {
            return (
                <Grid size={12} sx={{ p: 1 }} key={fieldDef.key}>
                    <TextField
                        label={fieldDef.label}
                        fullWidth multiline rows={5}
                        value={val}
                        onChange={(e) => updateField(fieldDef.key, e.target.value)}
                        onFocus={() => { if (val === '********') updateField(fieldDef.key, ''); }}
                        helperText={fieldDef.helperText}
                        placeholder='{ "type": "service_account", "project_id": "..." }'
                        sx={{ bgcolor: 'white', fontFamily: 'monospace' }}
                        required={fieldDef.required}
                    />
                </Grid>
            );
        }

        return (
            <Grid size={{ xs: 12, md: fieldDef.type === 'text' && fieldDef.key.includes('url') ? 12 : 6 }} sx={{ p: 1 }} key={fieldDef.key}>
                <TextField
                    label={fieldDef.label}
                    type={fieldDef.type === 'password' ? 'password' : 'text'}
                    fullWidth
                    value={val}
                    placeholder={fieldDef.placeholder}
                    onChange={(e) => updateField(fieldDef.key, e.target.value)}
                    onFocus={() => { if (val === '********') updateField(fieldDef.key, ''); }}
                    helperText={fieldDef.helperText}
                    required={fieldDef.required}
                    sx={{ bgcolor: 'white' }}
                />
            </Grid>
        );
    };

    return (
        <Stack spacing={4}>
            {/* ── Storage Backend Configuration ── */}
            <Paper elevation={0} sx={{ p: 3, border: '2px solid #5e35b1', borderRadius: 3, bgcolor: '#f9f8ff' }}>
                <Stack direction="row" sx={{ mb: 3, alignItems: 'center', justifyContent: 'space-between' }}>
                    <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                        <CloudUpload sx={{ color: '#5e35b1' }} />
                        <Typography variant="h6" sx={{ fontWeight: 700, color: '#5e35b1' }}>
                            Storage Backend Configuration
                        </Typography>
                    </Stack>
                    {/* Active provider badge */}
                    <Chip
                        icon={<StorageIcon fontSize="small" />}
                        label={`Active: ${PROVIDERS[props.activeProvider || 'local']?.label}`}
                        color="secondary"
                        variant="outlined"
                        size="small"
                    />
                </Stack>

                <Divider sx={{ mb: 2 }} />

                {/* Provider Selector */}
                <Grid container>
                    <Grid size={12} sx={{ p: 1 }}>
                        <FormControl fullWidth sx={{ bgcolor: 'white' }}>
                            <InputLabel id="storage-provider-label">Primary Storage Provider</InputLabel>
                            <Select
                                labelId="storage-provider-label"
                                variant="outlined"
                                value={storageProvider}
                                label="Primary Storage Provider"
                                onChange={(e) => handleProviderSwitch(e.target.value)}
                            >
                                {Object.entries(PROVIDERS).map(([key, def]) => (
                                    <MenuItem key={key} value={key}>
                                        <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                                            <span>{def.icon}</span>
                                            <span>{def.label}</span>
                                            {def.supportsPresign && (
                                                <Chip label="Presign" size="small" sx={{ fontSize: 10, height: 18, ml: 1 }} />
                                            )}
                                        </Stack>
                                    </MenuItem>
                                ))}
                            </Select>
                        </FormControl>
                    </Grid>

                    {/* Provider description */}
                    <Grid size={12} sx={{ px: 1, pb: 1 }}>
                        <Alert severity="info" icon={<Info fontSize="small" />}
                            sx={{ borderRadius: 2, py: 0.5 }}>
                            <strong>{providerDef.label}:</strong> {providerDef.description}
                            {providerDef.supportsPresign && (
                                <span> &nbsp;✅ Supports <strong>presigned URLs</strong> for secure private asset delivery.</span>
                            )}
                        </Alert>
                    </Grid>
                </Grid>

                <Divider sx={{ my: 1 }} />

                {/* Dynamic credential fields */}
                {storageProvider === 'local' ? (
                    <Grid size={12} sx={{ p: 1 }}>
                        <Alert severity="info">
                            Local storage saves files to <code>/storage/dam/</code> in your Rails root.
                            Presigned URLs are generated using Rails message verifier.
                            <strong> Switch to a cloud provider for production deployments.</strong>
                        </Alert>
                    </Grid>
                ) : (
                    <Grid container>
                        {providerDef.fields.map(renderField)}
                    </Grid>
                )}

                {/* Advanced / Common Options */}
                {storageProvider !== 'local' && (
                    <>
                        <Divider sx={{ my: 1 }} />
                        <Button
                            size="small" variant="text" color="inherit"
                            endIcon={showAdvanced ? <ExpandLess /> : <ExpandMore />}
                            onClick={() => setShowAdvanced(v => !v)}
                            sx={{ mb: 1, textTransform: 'none', color: '#5e35b1' }}
                        >
                            Advanced Options
                        </Button>
                        <Collapse in={showAdvanced}>
                            <Grid container>
                                <Grid size={{ xs: 12, md: 6 }} sx={{ p: 1 }}>
                                    <TextField
                                        label="Presigned URL Expiry (seconds)"
                                        type="number"
                                        fullWidth
                                        value={currentStorageConfigs.presign_expiry || 3600}
                                        onChange={(e) => updateField('presign_expiry', e.target.value)}
                                        helperText="Default: 3600 (1 hour). Max: 604800 (7 days for S3)."
                                        sx={{ bgcolor: 'white' }}
                                    />
                                </Grid>
                                <Grid size={{ xs: 12, md: 6 }} sx={{ p: 1 }}>
                                    <FormControl fullWidth sx={{ bgcolor: 'white' }}>
                                        <InputLabel>AI Enrichment on Upload</InputLabel>
                                        <Select
                                            variant="outlined"
                                            value={currentStorageConfigs.ai_enrichment || 'enabled'}
                                            label="AI Enrichment on Upload"
                                            onChange={(e) => updateField('ai_enrichment', e.target.value)}
                                        >
                                            <MenuItem value="enabled">✅ Enabled — Generate embeddings after upload</MenuItem>
                                            <MenuItem value="disabled">⏸ Disabled — Manual embedding only</MenuItem>
                                            <MenuItem value="images_only">🖼️ Images Only</MenuItem>
                                        </Select>
                                    </FormControl>
                                </Grid>
                                <Grid size={12} sx={{ p: 1 }}>
                                    <Alert severity="info" sx={{ borderRadius: 2 }}>
                                        <strong>Presigned URLs</strong> generate time-limited signed links so private assets are served
                                        securely without exposing your bucket publicly. Recommended for all production deployments.
                                        <br />
                                        <strong>AI Enrichment</strong> publishes a Redis event after each upload so the Python AI Gateway
                                        can generate 1536-dim vector embeddings for semantic search.
                                    </Alert>
                                </Grid>
                            </Grid>
                        </Collapse>
                    </>
                )}

                <Divider sx={{ my: 2 }} />

                {/* Action Buttons */}
                <Stack direction="row" spacing={2} useFlexGap sx={{ justifyContent: 'flex-end', flexWrap: 'wrap' }}>
                    <Button
                        variant="outlined" color="primary"
                        onClick={handleTestConnection}
                        disabled={testStatus.loading || storageProvider === 'local'}
                        startIcon={testStatus.loading ? <CircularProgress size={16} /> :
                            testStatus.msg ? <CheckCircle color="success" fontSize="small" /> :
                            testStatus.error ? <ErrorIcon color="error" fontSize="small" /> : null}
                    >
                        {testStatus.loading ? 'Testing…' : 'Test Connection'}
                    </Button>
                    <Button variant="outlined" color="inherit" onClick={handleClear} sx={{ borderRadius: 2, textTransform: 'none' }}>
                        Clear Fields
                    </Button>
                    <Button
                        variant="contained"
                        onClick={handleSaveStorage}
                        disabled={loading}
                        startIcon={loading ? <CircularProgress size={18} color="inherit" /> : <Save />}
                        sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                    >
                        Save & Activate {PROVIDERS[storageProvider]?.label}
                    </Button>
                </Stack>

                {/* Status alerts */}
                <Stack spacing={1} sx={{ mt: 2 }}>
                    {testStatus.error && <Alert severity="error" onClose={() => setTestStatus(s => ({ ...s, error: null }))}>{testStatus.error}</Alert>}
                    {testStatus.msg && <Alert severity="success" onClose={() => setTestStatus(s => ({ ...s, msg: null }))}>{testStatus.msg}</Alert>}
                    {saveStatus && (
                        <Alert severity={saveStatus.success ? 'success' : 'error'}
                            onClose={() => setSaveStatus(null)}>
                            {saveStatus.msg}
                        </Alert>
                    )}
                </Stack>
            </Paper>
        </Stack>
    );
}
