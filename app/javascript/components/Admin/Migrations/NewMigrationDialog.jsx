import React, { useState, useEffect, useCallback } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Button, CircularProgress, Alert, Box, Typography, Stack,
    TextField, Stepper, Step, StepLabel, Divider,
    FormControlLabel, Chip, Card, CardContent,
    Switch, Grid
} from '@mui/material';
import {
    Close, CloudSync, RocketLaunch, ArrowBack, ArrowForward,
    CheckCircle, AccountTree, Storage, AutoFixHigh
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../../context/NotificationContext';
import { DAM_PROVIDERS } from './ConnectorDialog';

// ── Helpers ────────────────────────────────────────────────────────────────
const getProviderLabel = (type) =>
    DAM_PROVIDERS[type?.toLowerCase()]?.label || type || 'Unknown Provider';

const getConnectorIcon = (type) => {
    const t = type?.toLowerCase();
    if (t === 'aem')        return <AccountTree sx={{ color: '#ef4444', fontSize: 22 }} />;
    if (t === 'cloudinary') return <Storage sx={{ color: '#3b82f6', fontSize: 22 }} />;
    if (t === 'legacy_s3')  return <Storage sx={{ color: '#f59e0b', fontSize: 22 }} />;
    return <CloudSync sx={{ color: '#0ea5e9', fontSize: 22 }} />;
};

const WIZARD_STEPS = ['Select Source', 'Configure Batch', 'Confirm & Launch'];

/**
 * NewMigrationDialog — 3-step wizard to start a migration from a connector.
 *
 * Props:
 *  open        {boolean}
 *  onClose     {() => void}
 *  onSuccess   {(batch) => void}  — called with the created batch on success
 */
export default function NewMigrationDialog({ open, onClose, onSuccess }) {
    const { t }  = useTranslation();
    const notify = useNotify();

    const [activeStep, setActiveStep]         = useState(0);
    const [connectors, setConnectors]         = useState([]);
    const [loadingConns, setLoadingConns]     = useState(true);
    const [selectedConn, setSelectedConn]     = useState(null);
    const [launching, setLaunching]           = useState(false);
    const [formData, setFormData]             = useState({
        name:            '',
        notes:           '',
        tdm_sanitation:  true,
        concurrency:     3,
    });

    // Fetch active connectors when dialog opens
    useEffect(() => {
        if (!open) return;
        setActiveStep(0);
        setSelectedConn(null);
        setLoadingConns(true);
        fetch('/api/v1/system_connectors')
            .then(r => r.json())
            .then(data => setConnectors(Array.isArray(data) ? data.filter(c => c.status === 'active') : []))
            .catch(() => notify(t('ingestion.wizard.connectorFetchError'), 'error'))
            .finally(() => setLoadingConns(false));
    }, [open]); // eslint-disable-line react-hooks/exhaustive-deps

    // Auto-suggest batch name when connector is selected
    const selectConnector = useCallback((conn) => {
        setSelectedConn(conn);
        const date = new Date().toISOString().slice(0, 10);
        setFormData(prev => ({
            ...prev,
            name: `${getProviderLabel(conn.provider_type)} Migration — ${date}`,
        }));
    }, []);

    const handleNext = () => setActiveStep(s => s + 1);
    const handleBack = () => setActiveStep(s => s - 1);

    const handleLaunch = async () => {
        setLaunching(true);
        try {
            const csrf = document.querySelector('[name="csrf-token"]').content;
            const body = {
                ingestion_batch: {
                    name:         formData.name,
                    notes:        formData.notes,
                    source_type:  selectedConn.provider_type,
                    connector_id: selectedConn.id,
                },
            };
            const res  = await fetch('/api/v1/ingestion_batches', {
                method:  'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf },
                body:    JSON.stringify(body),
            });
            const data = await res.json();
            if (res.ok) {
                notify(t('ingestion.wizard.launchSuccess', { name: data.batch.name }), 'success');
                onSuccess && onSuccess(data.batch);
            } else {
                notify((data.errors || [data.error]).join(', '), 'error');
            }
        } catch {
            notify(t('ingestion.wizard.launchError'), 'error');
        } finally {
            setLaunching(false);
        }
    };

    // ── Step Renderers ───────────────────────────────────────────────────────
    const renderStep1 = () => (
        <Box>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                {t('ingestion.wizard.step1Desc')}
            </Typography>

            {loadingConns ? (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                    <CircularProgress />
                </Box>
            ) : connectors.length === 0 ? (
                <Alert severity="warning" sx={{ borderRadius: 2 }}>
                    {t('ingestion.wizard.noActiveConnectors')}&nbsp;
                    <a href="/admin/migrations/connectors" style={{ color: 'inherit', fontWeight: 700 }}>
                        {t('ingestion.goToConnectors')} →
                    </a>
                </Alert>
            ) : (
                <Grid container spacing={2}>
                    {connectors.map(conn => {
                        const isSelected = selectedConn?.id === conn.id;
                        return (
                            <Grid size={{ xs: 12, sm: 6 }} key={conn.id}>
                                <Card
                                    elevation={0}
                                    onClick={() => selectConnector(conn)}
                                    sx={{
                                        border: `2px solid ${isSelected ? '#5e35b1' : '#e2e8f0'}`,
                                        borderRadius: 2,
                                        cursor: 'pointer',
                                        bgcolor: isSelected ? '#faf5ff' : 'white',
                                        transition: 'all 0.15s',
                                        '&:hover': { borderColor: '#5e35b1', bgcolor: '#faf5ff' },
                                    }}
                                >
                                    <CardContent sx={{ p: 2, '&:last-child': { pb: 2 } }}>
                                        <Stack direction="row" spacing={1.5} sx={{
  alignItems: "center"
}}>
                                            <Box sx={{ p: 0.8, bgcolor: '#f1f5f9', borderRadius: 1.5, display: 'flex' }}>
                                                {getConnectorIcon(conn.provider_type)}
                                            </Box>
                                            <Box sx={{ flex: 1, minWidth: 0 }}>
                                                <Typography variant="subtitle2" sx={{ fontWeight: 700, lineHeight: 1.2 }} noWrap>
                                                    {conn.name}
                                                </Typography>
                                                <Typography variant="caption" color="textSecondary" noWrap>
                                                    {getProviderLabel(conn.provider_type)}
                                                </Typography>
                                            </Box>
                                            {isSelected && <CheckCircle sx={{ color: '#5e35b1', fontSize: 20, flexShrink: 0 }} />}
                                        </Stack>

                                        <Stack direction="row" spacing={0.8} sx={{ mt: 1.5, flexWrap: 'wrap', gap: 0.5 }}>
                                            <Chip label="Active" size="small" color="success"
                                                sx={{ height: 18, fontSize: '0.6rem', fontWeight: 700 }} />
                                            {conn.tdm_sanitation && (
                                                <Chip icon={<AutoFixHigh sx={{ fontSize: '0.7rem' }} />}
                                                    label="AI/TDM"
                                                    size="small"
                                                    sx={{ height: 18, fontSize: '0.6rem', bgcolor: '#f3e8ff', color: '#7e22ce' }} />
                                            )}
                                            {conn.assets_imported > 0 && (
                                                <Chip label={`${conn.assets_imported?.toLocaleString()} imported`}
                                                    size="small" variant="outlined"
                                                    sx={{ height: 18, fontSize: '0.6rem' }} />
                                            )}
                                        </Stack>
                                    </CardContent>
                                </Card>
                            </Grid>
                        );
                    })}
                </Grid>
            )}
        </Box>
    );

    const renderStep2 = () => (
        <Stack spacing={2.5}>
            <TextField
                fullWidth
                label={t('ingestion.wizard.batchName')}
                value={formData.name}
                onChange={e => setFormData(prev => ({ ...prev, name: e.target.value }))}
                helperText={t('ingestion.wizard.batchNameHelper')}
                required
            />
            <TextField
                fullWidth
                multiline
                rows={2}
                label={t('ingestion.wizard.notes')}
                value={formData.notes}
                onChange={e => setFormData(prev => ({ ...prev, notes: e.target.value }))}
                helperText={t('ingestion.wizard.notesHelper')}
            />

            <Divider />

            <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0' }}>
                <FormControlLabel
                    control={
                        <Switch
                            checked={formData.tdm_sanitation}
                            onChange={e => setFormData(prev => ({ ...prev, tdm_sanitation: e.target.checked }))}
                            color="secondary"
                        />
                    }
                    label={
                        <Box>
                            <Typography variant="subtitle2" sx={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: 0.5 }}>
                                <AutoFixHigh fontSize="small" sx={{ color: '#8b5cf6' }} />
                                {t('ingestion.wizard.tdmSanitation')}
                            </Typography>
                            <Typography variant="caption" color="textSecondary">
                                {t('ingestion.wizard.tdmSanitationDesc')}
                            </Typography>
                        </Box>
                    }
                />
            </Box>

            <TextField type="number" label={t('ingestion.wizard.concurrency')} value={formData.concurrency} onChange={e => setFormData(prev => ({
  ...prev,
  concurrency: parseInt(e.target.value, 10) || 1
}))} helperText={t('ingestion.wizard.concurrencyHelper')} sx={{
  width: 200
}} slotProps={{
  htmlInput: {
    min: 1,
    max: 10
  }
}} />
        </Stack>
    );

    const renderStep3 = () => (
        <Stack spacing={2}>
            <Alert severity="info" sx={{ borderRadius: 2 }}>
                {t('ingestion.wizard.confirmInfo')}
            </Alert>

            <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0' }}>
                <Typography variant="caption" sx={{ fontWeight: 700, textTransform: 'uppercase', color: '#64748b', letterSpacing: '0.06em', display: 'block', mb: 1.5 }}>
                    Migration Summary
                </Typography>
                {[
                    { label: 'Batch Name',    value: formData.name },
                    { label: 'Source System', value: `${getProviderLabel(selectedConn?.provider_type)} (${selectedConn?.name})` },
                    { label: 'Source Type',   value: selectedConn?.provider_type },
                    { label: 'AI/TDM',        value: formData.tdm_sanitation ? 'Enabled — full metadata normalization' : 'Bypassed' },
                    { label: 'Concurrency',   value: `${formData.concurrency} parallel threads` },
                    ...(formData.notes ? [{ label: 'Notes', value: formData.notes }] : []),
                ].map(({ label, value }) => (
                    <Box key={label} sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}>
                        <Typography variant="body2" color="textSecondary">{label}:</Typography>
                        <Typography variant="body2" sx={{ fontWeight: 600, textAlign: 'right', ml: 2 }}>{value}</Typography>
                    </Box>
                ))}
            </Box>

            <Alert severity="warning" sx={{ borderRadius: 2 }}>
                <strong>Tip:</strong> Large migrations can take minutes to hours during extraction. The pipeline runs in the background — you&apos;ll receive an email when review is ready.
            </Alert>
        </Stack>
    );

    const stepContent = [renderStep1, renderStep2, renderStep3];

    const canProceedStep1 = !!selectedConn;
    const canProceedStep2 = formData.name.trim().length >= 3;

    const canProceed = activeStep === 0 ? canProceedStep1
        : activeStep === 1 ? canProceedStep2
        : true;

    return (
        <Dialog
            open={open}
            onClose={onClose}
            maxWidth="md"
            fullWidth
            slotProps={{ paper: { sx: { borderRadius: 3 } } }}
        >
            <DialogTitle sx={{
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                fontWeight: 700, borderBottom: '1px solid #e2e8f0', pb: 2, pt: 3, px: 3
            }}>
                <Stack direction="row" spacing={1.5} sx={{
  alignItems: "center"
}}>
                    <RocketLaunch sx={{ color: '#5e35b1' }} />
                    <span>{t('ingestion.wizard.title')}</span>
                </Stack>
                <Button onClick={onClose} size="small" startIcon={<Close />} sx={{ textTransform: 'none', color: '#64748b' }}>
                    {t('common.close')}
                </Button>
            </DialogTitle>

            <Box sx={{ px: 3, pt: 3 }}>
                <Stepper activeStep={activeStep} alternativeLabel>
                    {WIZARD_STEPS.map(label => (
                        <Step key={label}>
                            <StepLabel>{label}</StepLabel>
                        </Step>
                    ))}
                </Stepper>
            </Box>

            <DialogContent sx={{ p: 3, pt: 2 }}>
                {stepContent[activeStep]?.()}
            </DialogContent>

            <DialogActions sx={{ px: 3, pb: 3, borderTop: '1px solid #e2e8f0', bgcolor: '#f8fafc', gap: 1, flexWrap: 'wrap' }}>
                <Button onClick={handleBack} disabled={activeStep === 0} startIcon={<ArrowBack />}
                    sx={{ textTransform: 'none', color: '#64748b' }}>
                    {t('common.back')}
                </Button>
                <Box sx={{ flex: 1 }} />
                <Button onClick={onClose} sx={{ textTransform: 'none', color: '#64748b', fontWeight: 600 }}>
                    {t('common.cancel')}
                </Button>
                {activeStep < WIZARD_STEPS.length - 1 ? (
                    <Button
                        variant="contained"
                        onClick={handleNext}
                        disabled={!canProceed}
                        endIcon={<ArrowForward />}
                        sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                    >
                        Next
                    </Button>
                ) : (
                    <Button
                        variant="contained"
                        onClick={handleLaunch}
                        disabled={launching || !canProceedStep2}
                        startIcon={launching ? <CircularProgress size={16} color="inherit" /> : <RocketLaunch />}
                        sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                    >
                        {launching ? t('ingestion.wizard.launching') : t('ingestion.wizard.launch')}
                    </Button>
                )}
            </DialogActions>
        </Dialog>
    );
}


