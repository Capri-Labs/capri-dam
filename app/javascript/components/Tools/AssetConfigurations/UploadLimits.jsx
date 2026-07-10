import React, { useState, useEffect, useCallback } from 'react';
import {
    Box, Typography, Button, TextField, Paper, CircularProgress, Chip, Alert
} from '@mui/material';
import { CloudUploadOutlined, SaveOutlined, SecurityOutlined } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';

const BYTES_PER_GB = 1024 * 1024 * 1024;
const DEFAULT_GB = 2;

export default function UploadLimitsPanel() {
    const { t } = useTranslation();
    const translate = (key, fallback, options) => {
        const value = t(key, options);
        return value === key ? fallback : value;
    };
    const notify = useNotify();

    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [maxSizeGb, setMaxSizeGb] = useState(DEFAULT_GB);
    const [savedGb, setSavedGb] = useState(DEFAULT_GB);
    const [inputError, setInputError] = useState('');

    const isDirty = Number(maxSizeGb) !== Number(savedGb);

    const loadLimit = useCallback(async () => {
        setLoading(true);
        try {
            const res = await fetch('/api/v1/upload_limits');
            if (!res.ok) throw new Error('Failed to load');
            const data = await res.json();
            const bytes = Number(data.max_upload_size_bytes) || DEFAULT_GB * BYTES_PER_GB;
            const gb = Math.round((bytes / BYTES_PER_GB) * 100) / 100;
            setMaxSizeGb(gb);
            setSavedGb(gb);
        } catch {
            notify(translate('uploadLimits.loadError', 'Failed to load the upload size limit.'), 'error');
        } finally {
            setLoading(false);
        }
    }, []); // eslint-disable-line

    useEffect(() => { loadLimit(); }, [loadLimit]);

    const handleChange = (e) => {
        setMaxSizeGb(e.target.value);
        setInputError('');
    };

    const handleSave = async () => {
        const numeric = Number(maxSizeGb);
        if (!numeric || numeric <= 0) {
            setInputError(translate('uploadLimits.invalidValue', 'Please enter a positive number.'));
            return;
        }

        setSaving(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const bytes = Math.round(numeric * BYTES_PER_GB);
            const res = await fetch('/api/v1/upload_limits', {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ max_upload_size_bytes: bytes }),
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.error || 'Save failed');
            notify(data.message || translate('uploadLimits.savedSuccess', 'Upload size limit saved successfully.'), 'success');
            setSavedGb(numeric);
        } catch (err) {
            notify(err.message, 'error');
        } finally {
            setSaving(false);
        }
    };

    if (loading) {
        return (
            <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', flex: 1, pt: 8 }}>
                <CircularProgress sx={{ color: '#5e35b1' }} />
            </Box>
        );
    }

    return (
        <Box sx={{ flex: 1, overflow: 'auto', p: 3, maxWidth: 800 }}>
            <Paper variant="outlined" sx={{ p: 3, mb: 3, borderRadius: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 2, mb: 2 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                        <CloudUploadOutlined sx={{ color: '#5e35b1', fontSize: 28 }} />
                        <Box>
                            <Typography variant="subtitle1" fontWeight={700} sx={{ color: '#1e293b' }}>
                                {translate('uploadLimits.title', 'Upload Size Limit')}
                            </Typography>
                            <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                {translate('uploadLimits.subtitle', 'Maximum file size allowed for asset uploads')}
                            </Typography>
                        </Box>
                    </Box>
                    <Chip icon={<SecurityOutlined sx={{ fontSize: '14px !important' }} />}
                          label={translate('uploadLimits.adminOnly', 'Admin only')} size="small"
                          sx={{ bgcolor: '#fef3c7', color: '#92400e', fontSize: '0.7rem', border: '1px solid #fde68a' }} />
                </Box>

                <Typography variant="body2" sx={{ color: '#64748b', mb: 3 }}>
                    {translate(
                        'uploadLimits.description',
                        'By default, DAM does not allow uploading assets larger than 2 GB. Administrators can override this limit below. The new limit is enforced both by the API and the upload interface.'
                    )}
                </Typography>

                <Alert severity="info" sx={{ mb: 3, bgcolor: '#f0f9ff', border: '1px solid #bae6fd', color: '#0369a1' }}>
                    {translate('uploadLimits.currentLimit', `Current limit: ${savedGb} GB`, { size: `${savedGb} GB` })}
                </Alert>

                <Box sx={{ display: 'flex', gap: 2, alignItems: 'flex-start' }}>
                    <TextField
                        type="number"
                        size="small"
                        label={translate('uploadLimits.maxSizeLabel', 'Maximum Upload Size (GB)')}
                        helperText={inputError || translate('uploadLimits.helperText', 'Enter a value greater than 0. Example: 2 = 2 GB.')}
                        error={Boolean(inputError)}
                        value={maxSizeGb}
                        onChange={handleChange}
                        slotProps={{ htmlInput: { min: 0.1, step: 0.1 } }}
                        sx={{ minWidth: 260, bgcolor: '#f8fafc' }}
                    />
                    <Button
                        variant="contained"
                        startIcon={saving ? <CircularProgress size={16} color="inherit" /> : <SaveOutlined />}
                        onClick={handleSave}
                        disabled={saving || !isDirty}
                        sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' }, textTransform: 'none', fontWeight: 600, px: 3, height: 40 }}
                    >
                        {saving ? translate('uploadLimits.saving', 'Saving…') : translate('uploadLimits.save', 'Save')}
                    </Button>
                </Box>

                <Box sx={{ mt: 2 }}>
                    {isDirty && (
                        <Typography variant="caption" sx={{ color: '#f59e0b', fontWeight: 600 }}>
                            {translate('uploadLimits.unsavedChanges', 'Unsaved changes')}
                        </Typography>
                    )}
                    {!isDirty && (
                        <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                            {translate('uploadLimits.changesSaved', 'Changes saved')}
                        </Typography>
                    )}
                </Box>
            </Paper>
        </Box>
    );
}
