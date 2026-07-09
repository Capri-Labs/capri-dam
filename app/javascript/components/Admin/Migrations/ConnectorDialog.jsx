import React from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    TextField, Switch, FormControlLabel, MenuItem,
    CircularProgress, Alert, IconButton, Box, Typography,
    Stack, Button, Grid, Divider, ToggleButtonGroup, ToggleButton, Chip
} from '@mui/material';
import { Close, CheckCircleOutlined, ErrorOutlined, AutoFixHigh, Info, VpnKeyOutlined, RefreshOutlined, BlockOutlined } from '@mui/icons-material';

// ─────────────────────────────────────────────────────────────────────────────
// Provider Definitions — drives the dropdown and per-provider field rendering
// ─────────────────────────────────────────────────────────────────────────────
const DAM_PROVIDERS = {
    aem: {
        label: 'Adobe Experience Manager (AEM)',
        category: 'Enterprise DAM',
        supportsJwt: true,
        fields: [
            { key: 'endpoint', label: 'AEM Author Instance URL', placeholder: 'https://author.yourdomain.com', required: true },
            { key: 'auth_token', label: 'Bearer / Service Account Token', type: 'password', required: true },
        ],
        hint: 'Use the AEM Assets API. Ensure the service user has /api/assets read access.'
    },
    bynder: {
        label: 'Bynder',
        category: 'Enterprise DAM',
        fields: [
            { key: 'endpoint', label: 'Bynder Portal URL', placeholder: 'https://yourcompany.bynder.com', required: true },
            { key: 'auth_token', label: 'OAuth2 Access Token', type: 'password', required: true },
        ],
        hint: 'Generate an access token in Bynder → Settings → API Tokens.'
    },
    widen: {
        label: 'Acquia DAM (Widen)',
        category: 'Enterprise DAM',
        fields: [
            { key: 'endpoint', label: 'Widen API Base URL', placeholder: 'https://api.widencollective.com', required: true },
            { key: 'auth_token', label: 'Widen API Key', type: 'password', required: true },
        ],
        hint: 'Found in Widen Admin → API Keys.'
    },
    canto: {
        label: 'Canto',
        category: 'Mid-Market DAM',
        fields: [
            { key: 'endpoint', label: 'Canto Instance URL', placeholder: 'https://yourco.canto.com', required: true },
            { key: 'auth_token', label: 'JWT Bearer Token', type: 'password', required: true },
        ],
        hint: 'Use Canto OAuth2 to generate a JWT access token.'
    },
    mediavalet: {
        label: 'MediaValet',
        category: 'Enterprise DAM',
        fields: [
            { key: 'endpoint', label: 'MediaValet API URL', placeholder: 'https://api.mediavalet.com', required: true },
            { key: 'auth_token', label: 'Azure AD OAuth2 Bearer Token', type: 'password', required: true },
        ],
        hint: 'Register an app in Azure AD, grant DAM permissions, and use the access token.'
    },
    brandfolder: {
        label: 'Brandfolder',
        category: 'Mid-Market DAM',
        fields: [
            { key: 'endpoint', label: 'Brandfolder API URL', placeholder: 'https://brandfolder.com', required: true },
            { key: 'auth_token', label: 'API Key', type: 'password', required: true },
            { key: 'brandfolder_key', label: 'Brandfolder Slug', placeholder: 'my-brand', required: true, helperText: 'The URL slug of your Brandfolder' },
        ],
        hint: 'Find your API key in Account Settings → API Keys.'
    },
    cloudinary: {
        label: 'Cloudinary',
        category: 'Media Platform',
        fields: [
            { key: 'cloud_name', label: 'Cloud Name', placeholder: 'my-cloud', required: true },
            { key: 'access_key', label: 'API Key', required: true },
            { key: 'secret_key', label: 'API Secret', type: 'password', required: true },
        ],
        hint: 'Found in Cloudinary Console → Settings → Access Keys.'
    },
    nuxeo: {
        label: 'Nuxeo Platform',
        category: 'Enterprise DAM',
        fields: [
            { key: 'endpoint', label: 'Nuxeo Server URL', placeholder: 'https://your-nuxeo.cloud.nuxeo.com/nuxeo', required: true },
            { key: 'auth_token', label: 'Bearer Token', type: 'password', helperText: 'Leave blank to use username/password below' },
            { key: 'username', label: 'Username (alt. to token)', helperText: 'Used for Basic auth if no token provided' },
            { key: 'password', label: 'Password', type: 'password' },
        ],
        hint: 'Supports both Bearer token and username/password (Basic auth) for older instances.'
    },
    aprimo: {
        label: 'Aprimo DAM',
        category: 'Enterprise DAM',
        fields: [
            { key: 'endpoint', label: 'Aprimo API URL', placeholder: 'https://yourco.aprimo.com', required: true },
            { key: 'auth_token', label: 'OAuth2 Bearer Token', type: 'password', required: true },
        ],
        hint: 'Use Aprimo → Settings → API Configuration to generate an OAuth token.'
    },
    extensis: {
        label: 'Extensis Portfolio',
        category: 'Mid-Market DAM',
        fields: [
            { key: 'endpoint', label: 'Portfolio Server URL', placeholder: 'https://portfolio.yourcompany.com', required: true },
            { key: 'auth_token', label: 'Session Token / API Key', type: 'password', required: true },
        ],
        hint: 'Authenticate via Portfolio Server API and use the session token.'
    },
    sharepoint: {
        label: 'Microsoft SharePoint / OneDrive',
        category: 'File Repository',
        fields: [
            { key: 'endpoint', label: 'Microsoft Graph Drive URL', placeholder: 'https://graph.microsoft.com/v1.0/drives/{driveId}', required: true },
            { key: 'auth_token', label: 'Azure AD Bearer Token', type: 'password', required: true },
            { key: 'folder_path', label: 'Root Folder Path', placeholder: 'root/Marketing Assets', helperText: 'Relative path inside the drive (leave blank for root)' },
        ],
        hint: 'Register an app in Azure AD with Files.Read.All permission and use the access token.'
    },
    legacy_s3: {
        label: 'AWS S3 Bucket',
        category: 'Cloud Storage',
        fields: [
            { key: 'endpoint', label: 'S3 Endpoint (leave blank for AWS)', placeholder: 'https://s3.amazonaws.com' },
            { key: 'auth_token', label: 'Secret Access Key', type: 'password', required: true, helperText: 'Use access_key as the token field here' },
            { key: 'region', label: 'Region', placeholder: 'us-east-1', required: true },
            { key: 'bucket', label: 'Bucket Name', required: true },
        ],
        hint: 'For migrating a legacy S3 bucket. Ensure the IAM role has s3:GetObject and s3:ListBucket.'
    },
    ftp: {
        label: 'FTP / SFTP Server',
        category: 'Legacy Server',
        fields: [
            { key: 'host', label: 'Host / IP Address', placeholder: 'ftp.yourcompany.com', required: true },
            { key: 'port', label: 'Port', placeholder: '21' },
            { key: 'username', label: 'Username', required: true },
            { key: 'password', label: 'Password', type: 'password', required: true },
            { key: 'remote_path', label: 'Remote Path', placeholder: '/assets/marketing', helperText: 'Root directory to scan for assets' },
        ],
        hint: 'Use FTP for legacy on-premises DAM exports. SFTP support requires configuration.'
    },
};

const CATEGORIES = [...new Set(Object.values(DAM_PROVIDERS).map(p => p.category))];

export default function ConnectorDialog({
    open, onClose, formData, setFormData, onSave, onTest,
    isSaving, isTesting, testResult, isFormValid,
    onRefreshToken, onRevokeToken, isRefreshingToken
}) {
    const providerDef = DAM_PROVIDERS[formData.provider_type?.toLowerCase()] || null;
    const isJwt = providerDef?.supportsJwt && (formData.credential_type || 'token') === 'jwt_service_account';

    const updateExtra = (key, value) => {
        setFormData(prev => ({ ...prev, [key]: value }));
    };

    const tokenStatusColor = { valid: 'success', error: 'error', revoked: 'default', not_configured: 'default' }[formData.token_status] || 'default';

    return (
        <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth slotProps={{ paper: { sx: { borderRadius: 3 } } }}>
            <DialogTitle sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontWeight: 700, borderBottom: '1px solid #e2e8f0', pb: 2, pt: 3, px: 3 }}>
                {formData.id ? 'Configure System Connector' : 'Establish System Connector'}
                <IconButton onClick={onClose} size="small"><Close /></IconButton>
            </DialogTitle>

            <DialogContent sx={{ p: 3 }}>
                {testResult && (
                    <Alert severity={testResult.type} sx={{ mb: 2, borderRadius: 2 }}
                        icon={testResult.type === 'success' ? <CheckCircleOutlined /> : <ErrorOutlined />}>
                        {testResult.message}
                    </Alert>
                )}

                <Stack spacing={2.5}>
                    {/* Provider Selector — grouped by category */}
                    <TextField select fullWidth label="Source System / DAM Provider"
                        value={formData.provider_type || ''}
                        onChange={(e) => setFormData({ ...formData, provider_type: e.target.value })}>
                        {CATEGORIES.map(cat => [
                            <MenuItem key={`cat-${cat}`} disabled sx={{ opacity: 0.6, fontWeight: 700, fontSize: '0.7rem', textTransform: 'uppercase', letterSpacing: '0.08em', pt: 1 }}>
                                ── {cat}
                            </MenuItem>,
                            ...Object.entries(DAM_PROVIDERS)
                                .filter(([, def]) => def.category === cat)
                                .map(([key, def]) => (
                                    <MenuItem key={key} value={key.toUpperCase()} sx={{ pl: 3 }}>
                                        {def.label}
                                    </MenuItem>
                                ))
                        ])}
                    </TextField>

                    {/* Provider hint */}
                    {providerDef?.hint && (
                        <Alert severity="info" icon={<Info fontSize="small" />} sx={{ py: 0.5, borderRadius: 2 }}>
                            {providerDef.hint}
                        </Alert>
                    )}

                    <TextField fullWidth label="Connection Name"
                        placeholder={`e.g., Global Marketing ${providerDef?.label || 'DAM'}`}
                        value={formData.name || ''}
                        onChange={(e) => setFormData({ ...formData, name: e.target.value })} />

                    {/* Credential type toggle — only providers with an IMS/JWT service-account option */}
                    {providerDef?.supportsJwt && (
                        <ToggleButtonGroup
                            exclusive
                            fullWidth
                            size="small"
                            value={formData.credential_type || 'token'}
                            onChange={(e, val) => val && setFormData({ ...formData, credential_type: val })}
                        >
                            <ToggleButton value="token">Access Token</ToggleButton>
                            <ToggleButton value="jwt_service_account">Service Account (JWT)</ToggleButton>
                        </ToggleButtonGroup>
                    )}

                    {/* Provider-specific credential fields (Access Token mode) */}
                    {providerDef && !isJwt && (
                        <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0' }}>
                            <Typography variant="caption" sx={{ fontWeight: 700, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.05em', display: 'block', mb: 1.5 }}>
                                Credentials
                            </Typography>
                            <Grid container spacing={2}>
                                {providerDef.fields.map(field => (
                                    <Grid size={{ xs: 12, md: field.key === 'auth_token' || field.key.includes('url') || field.key.includes('endpoint') ? 12 : 6 }} key={field.key}>
                                        <TextField
                                            fullWidth
                                            label={field.label}
                                            placeholder={field.placeholder}
                                            type={field.type || 'text'}
                                            required={field.required}
                                            helperText={field.helperText}
                                            value={formData[field.key] || ''}
                                            onChange={(e) => updateExtra(field.key, e.target.value)}
                                            sx={{ bgcolor: 'white' }}
                                        />
                                    </Grid>
                                ))}
                            </Grid>
                        </Box>
                    )}

                    {/* Adobe IMS Service Account (JWT) credentials */}
                    {providerDef && isJwt && (
                        <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0' }}>
                            <Typography variant="caption" sx={{ fontWeight: 700, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.05em', display: 'block', mb: 1.5 }}>
                                <VpnKeyOutlined fontSize="inherit" sx={{ verticalAlign: 'middle', mr: 0.5 }} />
                                Adobe IMS Service Account
                            </Typography>

                            <TextField fullWidth label="AEM Author Instance URL" placeholder="https://author-xxxx.adobeaemcloud.com"
                                required sx={{ bgcolor: 'white', mb: 2 }}
                                value={formData.endpoint || ''}
                                onChange={(e) => updateExtra('endpoint', e.target.value)} />

                            <TextField
                                fullWidth multiline minRows={6} sx={{ bgcolor: 'white', fontFamily: 'monospace', mb: 1 }}
                                label="Paste Adobe Developer Console integration JSON"
                                placeholder='{"integration": {"imsEndpoint": "ims-na1.adobelogin.com", "technicalAccount": {"clientId": "...", "clientSecret": "..."}, "privateKey": "...", "org": "...", "id": "...", "metascopes": "ent_aem_cloud_api"}}'
                                value={formData.integration_json || ''}
                                onChange={(e) => updateExtra('integration_json', e.target.value)}
                                helperText="Generated from Adobe Developer Console → your project → Service Account (JWT) → Download the JSON credential. Secrets are encrypted at rest and never re-displayed."
                            />

                            {formData.id && formData.credential_type === 'jwt_service_account' && (
                                <Stack direction="row" spacing={1} alignItems="center" sx={{ mt: 1 }}>
                                    <Chip size="small" color={tokenStatusColor} label={`Token: ${formData.token_status || 'not_configured'}`} />
                                    {formData.access_token_expires_at && (
                                        <Typography variant="caption" color="textSecondary">
                                            expires {new Date(formData.access_token_expires_at).toLocaleString()}
                                        </Typography>
                                    )}
                                    <Box sx={{ flexGrow: 1 }} />
                                    <Button size="small" startIcon={isRefreshingToken ? <CircularProgress size={14} /> : <RefreshOutlined fontSize="small" />}
                                        onClick={onRefreshToken} disabled={isRefreshingToken} sx={{ textTransform: 'none' }}>
                                        Refresh Token
                                    </Button>
                                    <Button size="small" color="error" startIcon={<BlockOutlined fontSize="small" />}
                                        onClick={onRevokeToken} sx={{ textTransform: 'none' }}>
                                        Revoke
                                    </Button>
                                </Stack>
                            )}
                        </Box>
                    )}

                    {/* Folder scope — lets the admin pick which DAM folder to migrate */}
                    {providerDef && (
                        <TextField fullWidth label="Default Folder to Migrate (optional)"
                            placeholder="/content/dam/marketing-assets/beautiful-assets"
                            helperText="Scopes migrations to this folder. Leave blank to migrate the whole DAM root. Can be overridden per migration run."
                            value={formData.default_source_path || ''}
                            onChange={(e) => updateExtra('default_source_path', e.target.value)} />
                    )}

                    <Divider />

                    {/* TDM + Rate Limits */}
                    <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0' }}>
                        <FormControlLabel
                            control={<Switch checked={formData.tdm_sanitation ?? true}
                                onChange={(e) => setFormData({ ...formData, tdm_sanitation: e.target.checked })}
                                color="secondary" />}
                            label={
                                <Box>
                                    <Typography variant="subtitle2" sx={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: 0.5 }}>
                                        <AutoFixHigh fontSize="small" sx={{ color: '#8b5cf6' }} /> Apply AI / TDM Sanitization
                                    </Typography>
                                    <Typography variant="caption" color="textSecondary">
                                        Route each asset through the AI Gateway for metadata normalization and compliance scanning.
                                    </Typography>
                                </Box>
                            }
                        />
                    </Box>

                    <Grid container spacing={2}>
                        <Grid size={6}>
                            <TextField type="number" fullWidth label="Max Concurrent Threads"
                                value={formData.concurrency_limit || 3}
                                onChange={(e) => setFormData({ ...formData, concurrency_limit: parseInt(e.target.value) })}
                                helperText="Parallel download threads" />
                        </Grid>
                        <Grid size={6}>
                            <TextField type="number" fullWidth label="Max Requests/Sec (Rate Limit)"
                                value={formData.rps_limit || 5}
                                onChange={(e) => setFormData({ ...formData, rps_limit: parseInt(e.target.value) })}
                                helperText="Source system throttle" />
                        </Grid>
                    </Grid>
                </Stack>
            </DialogContent>

            <DialogActions sx={{ p: 3, borderTop: '1px solid #e2e8f0', bgcolor: '#f8fafc', display: 'flex', gap: 1 }}>
                <Button onClick={onTest} variant="outlined"
                    disabled={!isFormValid || isTesting}
                    startIcon={isTesting ? <CircularProgress size={16} /> : null}
                    sx={{ textTransform: 'none', borderRadius: '8px' }}>
                    {isTesting ? 'Pinging...' : 'Test Connection'}
                </Button>
                <Box sx={{ flexGrow: 1 }} />
                <Button onClick={onClose} sx={{ textTransform: 'none', color: '#475569', fontWeight: 600 }}>Cancel</Button>
                <Button onClick={onSave} variant="contained"
                    disabled={!isFormValid || isSaving}
                    startIcon={isSaving ? <CircularProgress size={16} color="inherit" /> : null}
                    sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#0ea5e9', '&:hover': { bgcolor: '#0284c7' } }}>
                    {isSaving ? 'Saving...' : (formData.id ? 'Save Configuration' : 'Initialize Connection')}
                </Button>
            </DialogActions>
        </Dialog>
    );
}

export { DAM_PROVIDERS };
