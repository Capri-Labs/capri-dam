import React, { useState, useEffect } from 'react';
import {
    Box, Paper, Typography, Button, Stack, TextField,
    CircularProgress, Alert, FormControl, InputLabel, Select, MenuItem, Chip, Tabs, Tab, InputAdornment, IconButton
} from '@mui/material';
import { CloudQueue, Save, SettingsInputComponent, Storage, Visibility, VisibilityOff } from '@mui/icons-material';

export default function StorageOperationsTab() {
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [notification, setNotification] = useState(null);
    const [activeTab, setActiveTab] = useState(0);
    const [showSecret, setShowSecret] = useState(false);

    // CDN State
    const [dbActiveCdn, setDbActiveCdn] = useState(null);
    const [selectedCdn, setSelectedCdn] = useState('fastly');

    // Storage State
    const [dbActiveStorage, setDbActiveStorage] = useState(null);
    const [selectedStorage, setSelectedStorage] = useState('aws_s3');

    const [configs, setConfigs] = useState({
        cdn: {
            fastly: { service_id: '', api_key: '' },
            cloudflare: { zone_id: '', api_token: '', kv_namespace: '' },
            akamai: { host: '', client_token: '', client_secret: '', access_token: '', edgekv_namespace: '' }
        },
        storage: {
            aws_s3: { bucket: '', region: '', access_key: '', secret_key: '' },
            azure_blob: { account_name: '', container: '', sas_token: '' }
        }
    });

    useEffect(() => {
        // In a real implementation, you'd fetch both CDN and Storage configs here
        // simulating the fetch merge:
        setTimeout(() => {
            setDbActiveCdn('fastly');
            setDbActiveStorage('aws_s3');
            setLoading(false);
        }, 600);
    }, []);

    const handleConfigChange = (domain, provider, field, value) => {
        setConfigs(prev => ({
            ...prev,
            [domain]: {
                ...prev[domain],
                [provider]: { ...prev[domain][provider], [field]: value }
            }
        }));
    };

    const handleSave = () => {
        setSaving(true);
        // Payload routing based on the active tab
        const domain = activeTab === 0 ? 'cdn' : 'storage';
        const provider = activeTab === 0 ? selectedCdn : selectedStorage;

        console.log(`Saving ${domain} config for ${provider}:`, configs[domain][provider]);

        setTimeout(() => {
            setSaving(false);
            setNotification({ type: 'success', msg: `${provider.toUpperCase()} configuration encrypted and activated.` });
            if (activeTab === 0) setDbActiveCdn(selectedCdn);
            if (activeTab === 1) setDbActiveStorage(selectedStorage);
            setTimeout(() => setNotification(null), 4000);
        }, 1000);
    };

    if (loading) return <Box sx={{ p: 4, textAlign: 'center' }}><CircularProgress /></Box>;

    return (
        <Paper elevation={0} sx={{ p: 0, border: '2px solid #e2e8f0', borderRadius: 3, bgcolor: '#f8fafc', overflow: 'hidden' }}>

            {/* Header Area */}
            <Box sx={{ p: 4, bgcolor: '#ffffff', borderBottom: '1px solid #e2e8f0' }}>
                <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                    <CloudQueue sx={{ fontSize: 36, color: '#4f46e5', mr: 2 }} />
                    <Box>
                        <Typography variant="h6" sx={{ fontWeight: 700 }}>Infrastructure Routing</Typography>
                        <Typography variant="body2" color="textSecondary">Manage Origin Storage and Edge Delivery providers.</Typography>
                    </Box>
                </Box>

                <Tabs value={activeTab} onChange={(e, newValue) => setActiveTab(newValue)} sx={{ mt: 2 }}>
                    <Tab icon={<SettingsInputComponent sx={{ fontSize: 18, mr: 1 }}/>} iconPosition="start" label="Edge CDN" sx={{ fontWeight: 600 }} />
                    <Tab icon={<Storage sx={{ fontSize: 18, mr: 1 }}/>} iconPosition="start" label="Origin Storage" sx={{ fontWeight: 600 }} />
                </Tabs>
            </Box>

            <Box sx={{ p: 4 }}>
                {notification && <Alert severity={notification.type} sx={{ mb: 4 }}>{notification.msg}</Alert>}

                {/* TAB 1: EDGE CDN */}
                {activeTab === 0 && (
                    <Stack spacing={4}>
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                            <FormControl fullWidth size="small">
                                <InputLabel>Target Edge Provider</InputLabel>
                                <Select value={selectedCdn} label="Target Edge Provider" onChange={(e) => setSelectedCdn(e.target.value)} sx={{ fontWeight: 600, textTransform: 'capitalize' }}>
                                    <MenuItem value="fastly">Fastly CDN</MenuItem>
                                    <MenuItem value="cloudflare">Cloudflare Enterprise</MenuItem>
                                    <MenuItem value="akamai">Akamai Edge</MenuItem>
                                </Select>
                            </FormControl>
                            <Box sx={{ minWidth: 120 }}>
                                {dbActiveCdn === selectedCdn ? <Chip label="Live in Production" color="success" size="small" sx={{ fontWeight: 600 }} /> : <Chip label="Inactive" color="default" size="small" sx={{ fontWeight: 600 }} />}
                            </Box>
                        </Box>

                        <Box sx={{ p: 3, bgcolor: '#f1f5f9', borderRadius: 2, border: '1px dashed #cbd5e1' }}>
                            <Typography variant="subtitle2" color="textSecondary" textTransform="uppercase" fontWeight="700" sx={{ mb: 2 }}>{selectedCdn} Credentials</Typography>
                            <Stack spacing={2.5}>
                                {selectedCdn === 'fastly' && (
                                    <>
                                        <TextField label="Service ID" fullWidth size="small" variant="filled" value={configs.cdn.fastly.service_id} onChange={(e) => handleConfigChange('cdn', 'fastly', 'service_id', e.target.value)} />
                                        <TextField label="API Token" type="password" fullWidth size="small" variant="filled" value={configs.cdn.fastly.api_key} onChange={(e) => handleConfigChange('cdn', 'fastly', 'api_key', e.target.value)} />
                                    </>
                                )}
                                {selectedCdn === 'cloudflare' && (
                                    <>
                                        <TextField label="Zone ID" fullWidth size="small" variant="filled" value={configs.cdn.cloudflare.zone_id} onChange={(e) => handleConfigChange('cdn', 'cloudflare', 'zone_id', e.target.value)} />
                                        <TextField label="Workers KV Namespace ID (Metadata)" fullWidth size="small" variant="filled" value={configs.cdn.cloudflare.kv_namespace} onChange={(e) => handleConfigChange('cdn', 'cloudflare', 'kv_namespace', e.target.value)} helperText="Required for Edge Metadata Sync" />
                                        <TextField label="API Token" type="password" fullWidth size="small" variant="filled" value={configs.cdn.cloudflare.api_token} onChange={(e) => handleConfigChange('cdn', 'cloudflare', 'api_token', e.target.value)} />
                                    </>
                                )}
                                {selectedCdn === 'akamai' && (
                                    <>
                                        <TextField label="Host (URL)" fullWidth size="small" variant="filled" value={configs.cdn.akamai.host} onChange={(e) => handleConfigChange('cdn', 'akamai', 'host', e.target.value)} />
                                        <TextField label="EdgeKV Namespace" fullWidth size="small" variant="filled" value={configs.cdn.akamai.edgekv_namespace} onChange={(e) => handleConfigChange('cdn', 'akamai', 'edgekv_namespace', e.target.value)} />
                                        <TextField label="Client Secret" type="password" fullWidth size="small" variant="filled" value={configs.cdn.akamai.client_secret} onChange={(e) => handleConfigChange('cdn', 'akamai', 'client_secret', e.target.value)} />
                                    </>
                                )}
                            </Stack>
                        </Box>
                    </Stack>
                )}

                {/* TAB 2: ORIGIN STORAGE */}
                {activeTab === 1 && (
                    <Stack spacing={4}>
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                            <FormControl fullWidth size="small">
                                <InputLabel>Origin Storage Provider</InputLabel>
                                <Select value={selectedStorage} label="Origin Storage Provider" onChange={(e) => setSelectedStorage(e.target.value)} sx={{ fontWeight: 600, textTransform: 'capitalize' }}>
                                    <MenuItem value="aws_s3">Amazon S3</MenuItem>
                                    <MenuItem value="azure_blob">Azure Blob Storage</MenuItem>
                                </Select>
                            </FormControl>
                            <Box sx={{ minWidth: 120 }}>
                                {dbActiveStorage === selectedStorage ? <Chip label="Live in Production" color="success" size="small" sx={{ fontWeight: 600 }} /> : <Chip label="Inactive" color="default" size="small" sx={{ fontWeight: 600 }} />}
                            </Box>
                        </Box>

                        <Box sx={{ p: 3, bgcolor: '#f1f5f9', borderRadius: 2, border: '1px dashed #cbd5e1' }}>
                            <Typography variant="subtitle2" color="textSecondary" textTransform="uppercase" fontWeight="700" sx={{ mb: 2 }}>{selectedStorage.replace('_', ' ')} Settings</Typography>
                            <Stack spacing={2.5}>
                                {selectedStorage === 'aws_s3' && (
                                    <>
                                        <TextField label="Bucket Name" fullWidth size="small" variant="filled" value={configs.storage.aws_s3.bucket} onChange={(e) => handleConfigChange('storage', 'aws_s3', 'bucket', e.target.value)} />
                                        <TextField label="Region (e.g., eu-central-1)" fullWidth size="small" variant="filled" value={configs.storage.aws_s3.region} onChange={(e) => handleConfigChange('storage', 'aws_s3', 'region', e.target.value)} />
                                        <TextField label="IAM Access Key" fullWidth size="small" variant="filled" value={configs.storage.aws_s3.access_key} onChange={(e) => handleConfigChange('storage', 'aws_s3', 'access_key', e.target.value)} />
                                        <TextField
                                            label="IAM Secret Key"
                                            type={showSecret ? "text" : "password"}
                                            fullWidth size="small" variant="filled"
                                            value={configs.storage.aws_s3.secret_key}
                                            onChange={(e) => handleConfigChange('storage', 'aws_s3', 'secret_key', e.target.value)}
                                            InputProps={{
                                                endAdornment: (
                                                    <InputAdornment position="end">
                                                        <IconButton onClick={() => setShowSecret(!showSecret)} edge="end" size="small">
                                                            {showSecret ? <VisibilityOff /> : <Visibility />}
                                                        </IconButton>
                                                    </InputAdornment>
                                                )
                                            }}
                                        />
                                    </>
                                )}
                            </Stack>
                        </Box>
                    </Stack>
                )}

                {/* Universal Action Area */}
                <Box sx={{ display: 'flex', justifyContent: 'flex-end', mt: 4 }}>
                    <Button variant="contained" startIcon={<Save />} onClick={handleSave} disabled={saving} sx={{ bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' } }}>
                        {saving ? 'Encrypting...' : `Save ${activeTab === 0 ? 'CDN' : 'Storage'} Settings`}
                    </Button>
                </Box>
            </Box>
        </Paper>
    );
}