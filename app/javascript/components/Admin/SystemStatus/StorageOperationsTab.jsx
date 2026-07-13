import React, { useState, useEffect } from 'react';
import {
    Box, Paper, Typography, Button, Stack, TextField,
    CircularProgress, Alert, FormControl, InputLabel, Select, MenuItem, Chip, Tabs, Tab
} from '@mui/material';
import { CloudQueue, Save, SettingsInputComponent, Storage } from '@mui/icons-material';
import OriginStorageTab from './OriginStorageTab';

export default function StorageOperationsTab({ activeProvider, allConfigs: originStorageConfigs }) {
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [notification, setNotification] = useState(null);
    const [activeTab, setActiveTab] = useState(0);

    // CDN State
    const [dbActiveCdn, setDbActiveCdn] = useState(null);
    const [selectedCdn, setSelectedCdn] = useState('fastly');

    const [configs, setConfigs] = useState({
        cdn: {
            fastly: { service_id: '', api_key: '' },
            cloudflare: { zone_id: '', api_token: '', kv_namespace: '' },
            akamai: { host: '', client_token: '', client_secret: '', access_token: '', edgekv_namespace: '' }
        }
    });

    useEffect(() => {
        // In a real implementation, you'd fetch the CDN config here.
        // The Origin Storage tab is backed by real settings data (activeProvider /
        // allConfigs props) so it does not need this simulated fetch.
        setTimeout(() => {
            setDbActiveCdn('fastly');
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
        // Only the Edge CDN tab uses this simulated save; Origin Storage has its
        // own real save/test-connection actions wired to /settings endpoints.
        setTimeout(() => {
            setSaving(false);
            setNotification({ type: 'success', msg: `${selectedCdn.toUpperCase()} configuration encrypted and activated.` });
            setDbActiveCdn(selectedCdn);
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
                            <Typography variant="subtitle2" color="textSecondary" fontWeight="700" sx={{ mb: 2, textTransform: 'uppercase' }}>{selectedCdn} Credentials</Typography>
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

                {/* TAB 2: ORIGIN STORAGE — real storage backend configuration */}
                {activeTab === 1 && (
                    <OriginStorageTab
                        activeProvider={activeProvider}
                        allConfigs={originStorageConfigs}
                    />
                )}

                {/* Universal Action Area — only applies to the Edge CDN tab; Origin
                    Storage has its own Save & Activate / Test Connection actions. */}
                {activeTab === 0 && (
                    <Box sx={{ display: 'flex', justifyContent: 'flex-end', mt: 4 }}>
                        <Button variant="contained" startIcon={<Save />} onClick={handleSave} disabled={saving} sx={{ bgcolor: '#4f46e5', '&:hover': { bgcolor: '#4338ca' } }}>
                            {saving ? 'Encrypting...' : 'Save CDN Settings'}
                        </Button>
                    </Box>
                )}
            </Box>
        </Paper>
    );
}