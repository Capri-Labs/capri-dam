import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, Paper, Typography, Button, Stack, TextField,
    CircularProgress, Alert, FormControl, InputLabel, Select, MenuItem, Chip, Tabs, Tab,
    FormGroup, FormControlLabel, Checkbox
} from '@mui/material';
import { useTranslation } from 'react-i18next';
import { CloudQueue, Save, SettingsInputComponent, Storage } from '@mui/icons-material';
import OriginStorageTab from './OriginStorageTab';

// Output formats the Fastly Image Optimizer (Fastly IO) integration can be
// configured to request. Mirrors Api::V1::CdnConfigurationsController::FASTLY_IMAGE_OPTIMIZER_FORMATS.
const FASTLY_IMAGE_OPTIMIZER_FORMATS = [ 'webp', 'avif' ];

function csrfToken() {
    const meta = document.querySelector('[name="csrf-token"]');
    return meta ? meta.content : '';
}

export default function StorageOperationsTab({ activeProvider, allConfigs: originStorageConfigs }) {
    const { t } = useTranslation();
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [notification, setNotification] = useState(null);
    const [activeTab, setActiveTab] = useState(0);

    // CDN State
    const [dbActiveCdn, setDbActiveCdn] = useState(null);
    const [selectedCdn, setSelectedCdn] = useState('fastly');

    const [configs, setConfigs] = useState({
        cdn: {
            fastly: { service_id: '', api_key: '', image_optimizer_formats: [] },
            cloudflare: { zone_id: '', api_token: '', kv_namespace: '' },
            akamai: { host: '', client_token: '', client_secret: '', access_token: '', edgekv_namespace: '' }
        }
    });

    const fetchCdnConfigurations = useCallback(async () => {
        try {
            const response = await fetch('/api/v1/cdn_configurations');
            const data = await response.json();

            setConfigs(prev => ({
                ...prev,
                cdn: {
                    fastly: {
                        ...prev.cdn.fastly,
                        ...(data.fastly?.settings || {}),
                        image_optimizer_formats: data.fastly?.settings?.image_optimizer_formats || [],
                    },
                    cloudflare: { ...prev.cdn.cloudflare, ...(data.cloudflare?.settings || {}) },
                    akamai: { ...prev.cdn.akamai, ...(data.akamai?.settings || {}) },
                }
            }));

            const active = [ 'fastly', 'cloudflare', 'akamai' ].find(p => data[p]?.is_active);
            setDbActiveCdn(active || null);
            if (active) setSelectedCdn(active);
        } catch (e) {
            // Non-fatal: the form still renders with blank/default values.
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchCdnConfigurations();
    }, [ fetchCdnConfigurations ]);

    const handleConfigChange = (domain, provider, field, value) => {
        setConfigs(prev => ({
            ...prev,
            [domain]: {
                ...prev[domain],
                [provider]: { ...prev[domain][provider], [field]: value }
            }
        }));
    };

    const toggleImageOptimizerFormat = (format) => {
        setConfigs(prev => {
            const current = prev.cdn.fastly.image_optimizer_formats || [];
            const next = current.includes(format)
                ? current.filter(f => f !== format)
                : [ ...current, format ];
            return {
                ...prev,
                cdn: { ...prev.cdn, fastly: { ...prev.cdn.fastly, image_optimizer_formats: next } }
            };
        });
    };

    const handleSave = async () => {
        setSaving(true);
        try {
            const settings = { ...configs.cdn[selectedCdn] };
            const response = await fetch('/api/v1/cdn_configurations', {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
                body: JSON.stringify({ provider: selectedCdn, is_active: true, settings })
            });
            const data = await response.json();

            if (response.ok && data.success) {
                setNotification({ type: 'success', msg: data.message || `${selectedCdn.toUpperCase()} configuration encrypted and activated.` });
                setDbActiveCdn(selectedCdn);
            } else {
                setNotification({ type: 'error', msg: (data.errors || []).join(', ') || 'Failed to save CDN configuration.' });
            }
        } catch (e) {
            setNotification({ type: 'error', msg: 'Failed to save CDN configuration.' });
        } finally {
            setSaving(false);
            setTimeout(() => setNotification(null), 4000);
        }
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
                                        <Box>
                                            <Typography variant="body2" fontWeight="600" sx={{ mb: 0.5 }}>
                                                {t('cdnEdge.imageOptimizerFormats', 'Image Optimizer Formats')}
                                            </Typography>
                                            <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 1 }}>
                                                {t('cdnEdge.imageOptimizerFormatsHint', "Output formats Fastly's Image Optimizer (Fastly IO) is allowed to serve for image assets.")}
                                            </Typography>
                                            <FormGroup row>
                                                {FASTLY_IMAGE_OPTIMIZER_FORMATS.map((format) => (
                                                    <FormControlLabel
                                                        key={format}
                                                        control={
                                                            <Checkbox
                                                                size="small"
                                                                checked={(configs.cdn.fastly.image_optimizer_formats || []).includes(format)}
                                                                onChange={() => toggleImageOptimizerFormat(format)}
                                                                slotProps={{ input: { 'aria-label': format } }}
                                                            />
                                                        }
                                                        label={t(`cdnEdge.formats.${format}`, format.toUpperCase())}
                                                    />
                                                ))}
                                            </FormGroup>
                                        </Box>
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