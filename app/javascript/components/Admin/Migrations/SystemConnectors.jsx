import React, { useState } from 'react';
import {
    Box, Typography, Paper, Grid, TextField, Button,
    MenuItem, Stack, Alert, Divider
} from '@mui/material';
import { BackupTable, CloudQueue, Lan, Code, RocketLaunch } from '@mui/icons-material';

export default function SystemConnectors() {
    const [loading, setLoading] = useState(false);
    const [successMessage, setSuccessMessage] = useState('');

    // Form State
    const [batchName, setBatchName] = useState('');
    const [sourceType, setSourceType] = useState('aws_s3');
    const [credentials, setCredentials] = useState({
        bucket: '', region: '', accessKey: '', secretKey: '',
        endpointUrl: '', username: '', password: ''
    });

    const handleCredentialChange = (field, value) => {
        setCredentials(prev => ({ ...prev, [field]: value }));
    };

    const handleStartMigration = async (e) => {
        e.preventDefault();
        setLoading(true);

        // Payload matching our Rails API controller
        const payload = {
            ingestion_batch: {
                name: batchName,
                source_type: sourceType,
                source_credentials: credentials // In production, these should be encrypted at the database level
            }
        };

        try {
            // fetch('/api/v1/ingestion_batches', { method: 'POST', body: JSON.stringify(payload) })

            // Simulating API latency
            setTimeout(() => {
                setLoading(false);
                setSuccessMessage(`Connection established. Sidekiq worker successfully triggered for "${batchName}". Navigate to the Batch Ingestion dashboard to monitor progress.`);
                setBatchName('');
            }, 1200);
        } catch (error) {
            setLoading(false);
            alert("Failed to initialize connection.");
        }
    };

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh', margin: '0 auto' }}>
            <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', mb: 1 }}>
                System Connectors
            </Typography>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 4 }}>
                Provision secure connections to legacy infrastructure to extract and migrate asset payloads.
            </Typography>

            {successMessage && (
                <Alert severity="success" sx={{ mb: 4, borderRadius: 2 }}>{successMessage}</Alert>
            )}

            <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3 }}>
                <form onSubmit={handleStartMigration}>
                    <Box sx={{ p: 4 }}>
                        <Typography variant="h6" sx={{ fontWeight: 600, mb: 3 }}>1. Batch Configuration</Typography>
                        <Grid container spacing={3}>
                            <Grid item xs={12} md={6}>
                                <TextField
                                    fullWidth
                                    label="Migration Batch Name"
                                    variant="outlined"
                                    required
                                    value={batchName}
                                    onChange={(e) => setBatchName(e.target.value)}
                                    placeholder="e.g. Q3 EMEA SharePoint Migration"
                                />
                            </Grid>
                            <Grid item xs={12} md={6}>
                                <TextField
                                    select
                                    fullWidth
                                    label="Legacy Source System"
                                    required
                                    value={sourceType}
                                    onChange={(e) => setSourceType(e.target.value)}
                                >
                                    <MenuItem value="aws_s3"><CloudQueue sx={{ mr: 1, fontSize: 18 }} /> Amazon S3 (Legacy)</MenuItem>
                                    <MenuItem value="azure_blob"><CloudQueue sx={{ mr: 1, fontSize: 18 }} /> Azure Blob Storage</MenuItem>
                                    <MenuItem value="gcp_bucket"><CloudQueue sx={{ mr: 1, fontSize: 18 }} /> Google Cloud Storage</MenuItem>
                                    <MenuItem value="aem_api"><Code sx={{ mr: 1, fontSize: 18 }} /> Adobe Experience Manager (AEM)</MenuItem>
                                    <MenuItem value="ftp"><Lan sx={{ mr: 1, fontSize: 18 }} /> Secure FTP (SFTP)</MenuItem>
                                </TextField>
                            </Grid>
                        </Grid>
                    </Box>

                    <Divider sx={{ borderColor: '#e3e8ef' }} />

                    <Box sx={{ p: 4 }}>
                        <Typography variant="h6" sx={{ fontWeight: 600, mb: 3 }}>2. Extraction Credentials</Typography>

                        {/* Dynamic Rendering based on selected Source Type */}
                        <Grid container spacing={3}>
                            {(sourceType === 'aws_s3' || sourceType === 'gcp_bucket') && (
                                <>
                                    <Grid item xs={12} md={6}>
                                        <TextField fullWidth required label="Bucket Name" onChange={e => handleCredentialChange('bucket', e.target.value)} />
                                    </Grid>
                                    <Grid item xs={12} md={6}>
                                        <TextField fullWidth required label="Region" onChange={e => handleCredentialChange('region', e.target.value)} />
                                    </Grid>
                                    <Grid item xs={12} md={6}>
                                        <TextField fullWidth required label="Access Key ID" onChange={e => handleCredentialChange('accessKey', e.target.value)} />
                                    </Grid>
                                    <Grid item xs={12} md={6}>
                                        <TextField fullWidth required type="password" label="Secret Access Key" onChange={e => handleCredentialChange('secretKey', e.target.value)} />
                                    </Grid>
                                </>
                            )}

                            {(sourceType === 'aem_api' || sourceType === 'ftp' || sourceType === 'azure_blob') && (
                                <>
                                    <Grid item xs={12}>
                                        <TextField fullWidth required label="Endpoint URL / Host" placeholder="https://legacy-aem.enterprise.com/content/dam.json" onChange={e => handleCredentialChange('endpointUrl', e.target.value)} />
                                    </Grid>
                                    <Grid item xs={12} md={6}>
                                        <TextField fullWidth required label="Username / Access Tier" onChange={e => handleCredentialChange('username', e.target.value)} />
                                    </Grid>
                                    <Grid item xs={12} md={6}>
                                        <TextField fullWidth required type="password" label="Password / API Token" onChange={e => handleCredentialChange('password', e.target.value)} />
                                    </Grid>
                                </>
                            )}
                        </Grid>
                    </Box>

                    <Box sx={{ p: 3, bgcolor: '#f8fafc', borderTop: '1px solid #e3e8ef', borderBottomLeftRadius: 12, borderBottomRightRadius: 12, display: 'flex', justifyContent: 'flex-end' }}>
                        <Button
                            type="submit"
                            variant="contained"
                            disabled={loading}
                            startIcon={<RocketLaunch />}
                            sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, py: 1.5, px: 4 }}
                        >
                            {loading ? 'Initializing Connection...' : 'Initialize Extraction Pipeline'}
                        </Button>
                    </Box>
                </form>
            </Paper>
        </Box>
    );
}