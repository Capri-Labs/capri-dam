import React from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    TextField, Switch, FormControlLabel, MenuItem,
    CircularProgress, Alert, IconButton, Box, Typography, Stack, Button, Grid
} from '@mui/material';
import { Close, CheckCircleOutlined, ErrorOutlined, AutoFixHigh } from '@mui/icons-material';

export default function ConnectorDialog({
                                            open, onClose, formData, setFormData, onSave, onTest,
                                            isSaving, isTesting, testResult, isFormValid
                                        }) {
    return (
        <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth PaperProps={{ sx: { borderRadius: 3 } }}>
            <DialogTitle sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontWeight: 700, borderBottom: '1px solid #e2e8f0', pb: 2, pt: 3, px: 3 }}>
                {formData.id ? 'Configure System Connector' : 'Establish System Connector'}
                <IconButton onClick={onClose} size="small"><Close /></IconButton>
            </DialogTitle>
            <DialogContent sx={{ p: 3 }}>

                {testResult && (
                    <Alert severity={testResult.type} sx={{ mb: 3, borderRadius: 2 }} icon={testResult.type === 'success' ? <CheckCircleOutlined /> : <ErrorOutlined />}>
                        {testResult.message}
                    </Alert>
                )}

                <Stack spacing={3} sx={{ mt: 1 }}>
                    <TextField select fullWidth label="Source System Provider" value={formData.provider_type} onChange={(e) => setFormData({ ...formData, provider_type: e.target.value })}>
                        <MenuItem value="AEM">Adobe Experience Manager (Assets API)</MenuItem>
                        <MenuItem value="S3">AWS S3 Bucket</MenuItem>
                        <MenuItem value="SHAREPOINT">Microsoft SharePoint</MenuItem>
                    </TextField>

                    <TextField fullWidth label="Connection Name" placeholder="e.g., Global Marketing AEM" value={formData.name} onChange={(e) => setFormData({ ...formData, name: e.target.value })} />

                    <TextField fullWidth label="API Endpoint / URI" placeholder="https://author-instance.adobecqms.net/api/assets" value={formData.endpoint} onChange={(e) => setFormData({ ...formData, endpoint: e.target.value })} />

                    <TextField fullWidth type="password" label="Authentication Token (Leave blank to keep existing)" value={formData.auth_token} onChange={(e) => setFormData({ ...formData, auth_token: e.target.value })} helperText={formData.id ? "Only enter a token if you need to update the credentials." : ""} />

                    <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0' }}>
                        <FormControlLabel
                            control={<Switch checked={formData.tdm_sanitation} onChange={(e) => setFormData({ ...formData, tdm_sanitation: e.target.checked })} color="secondary" />}
                            label={
                                <Box>
                                    <Typography variant="subtitle2" sx={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: 0.5 }}>
                                        <AutoFixHigh fontSize="small" sx={{ color: '#8b5cf6' }} /> Apply TDM Sanitization
                                    </Typography>
                                    <Typography variant="caption" color="textSecondary">
                                        Route incoming assets through the AI Gateway to extract standard schemas.
                                    </Typography>
                                </Box>
                            }
                        />
                    </Box>

                    <Grid container spacing={2}>
                        <Grid item xs={6}>
                            <TextField
                                type="number"
                                label="Max Concurrent Threads"
                                value={formData.concurrency_limit || 3}
                                onChange={(e) => setFormData({ ...formData, concurrency_limit: parseInt(e.target.value) })}
                            />
                        </Grid>
                        <Grid item xs={6}>
                            <TextField
                                type="number"
                                label="Max Requests/Sec"
                                value={formData.rps_limit || 5}
                                onChange={(e) => setFormData({ ...formData, rps_limit: parseInt(e.target.value) })}
                            />
                        </Grid>
                    </Grid>
                </Stack>
            </DialogContent>
            <DialogActions sx={{ p: 3, borderTop: '1px solid #e2e8f0', bgcolor: '#f8fafc', display: 'flex', gap: 1 }}>
                <Button
                    onClick={onTest}
                    variant="outlined"
                    disabled={!isFormValid || isTesting}
                    startIcon={isTesting ? <CircularProgress size={16} /> : null}
                    sx={{ textTransform: 'none', borderRadius: '8px', color: '#475569', borderColor: '#cbd5e1', bgcolor: '#ffffff' }}
                >
                    {isTesting ? 'Pinging...' : 'Test Connection'}
                </Button>
                <Box sx={{ flexGrow: 1 }} />
                <Button
                    onClick={onClose}
                    sx={{ textTransform: 'none', color: '#475569', fontWeight: 600 }}
                >
                    Cancel
                </Button>
                <Button
                    onClick={onSave}
                    variant="contained"
                    disabled={!isFormValid || isSaving}
                    startIcon={isSaving ? <CircularProgress size={16} color="inherit" /> : null}
                    sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#0ea5e9', '&:hover': { bgcolor: '#0284c7' } }}
                >
                    {isSaving ? 'Saving...' : (formData.id ? 'Save Configuration' : 'Initialize Connection')}
                </Button>
            </DialogActions>
        </Dialog>
    );
}