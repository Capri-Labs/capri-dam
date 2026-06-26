import React, { useState, useEffect } from 'react';
import {
    Box, Typography, Grid, Card, CardContent, Paper,
    LinearProgress, Button, Stack, Divider, List, ListItem,
    ListItemText, ListItemIcon, IconButton, Tooltip, Chip
} from '@mui/material';
import {
    HealthAndSafety, Storage, WarningAmber, CleaningServices,
    AutoGraph, ImageNotSupported, Gavel, Archive
} from '@mui/icons-material';

export default function DataHealthDashboard() {
    const [healthData, setHealthData] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        // Simulating API fetch: GET /api/v1/data_health/metrics
        setTimeout(() => {
            setHealthData({
                storage: {
                    total_allocated_tb: 18.5,
                    active_used_tb: 12.1,
                    duplicates_prevented_tb: 4.2,
                    orphaned_wasted_tb: 2.2, // Files not attached to any collection/workspace
                    monthly_savings_usd: 3400
                },
                debt_flags: [
                    { id: 'd1', type: 'orphaned', title: 'Orphaned Legacy Assets', count: 14205, impact: 'High', icon: <ImageNotSupported color="error" /> },
                    { id: 'd2', type: 'copyright', title: 'Missing Usage Rights / Expiry', count: 3102, impact: 'Critical', icon: <Gavel color="error" /> },
                    { id: 'd3', type: 'stale', title: 'Stale Media (Unaccessed > 3 Yrs)', count: 8540, impact: 'Medium', icon: <Archive color="warning" /> }
                ]
            });
            setLoading(false);
        }, 800);
    }, []);

    const handleRemediate = (type) => {
        // Triggering background cleanup jobs (e.g., POST /api/v1/jobs/remediate)
        alert(`Initializing remediation job for: ${type}. Sidekiq workers will process this in the background.`);
    };

    if (loading) return <Box sx={{ p: 4 }}><LinearProgress color="secondary" /></Box>;

    const storageUsagePct = (healthData.storage.active_used_tb / healthData.storage.total_allocated_tb) * 100;
    const wastedPct = (healthData.storage.orphaned_wasted_tb / healthData.storage.total_allocated_tb) * 100;

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh', maxWidth: 1200, margin: '0 auto' }}>
            <Stack direction="row" justifyContent="space-between" alignItems="flex-end" sx={{ mb: 4 }}>
                <Box>
                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', mb: 1, display: 'flex', alignItems: 'center' }}>
                        <HealthAndSafety sx={{ mr: 1.5, color: '#5e35b1', fontSize: 32 }} />
                        TDM & Storage Health
                    </Typography>
                    <Typography variant="body2" color="textSecondary">
                        Proactively monitor technical debt, optimize AWS S3 footprint, and resolve metadata compliance issues.
                    </Typography>
                </Box>
                <Button variant="outlined" startIcon={<AutoGraph />} sx={{ borderColor: '#cbd5e1', color: '#475569' }}>
                    Generate Executive TDM Report
                </Button>
            </Stack>

            {/* Top Row: Executive TDM Metrics */}
            <Grid container spacing={3} sx={{ mb: 4 }}>
                <Grid size={{ xs: 12, md: 4 }}>
                    <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%' }}>
                        <CardContent>
                            <Typography color="textSecondary" variant="caption" sx={{ fontWeight: 600 }}>DEDUPLICATION SAVINGS</Typography>
                            <Typography variant="h3" sx={{ fontWeight: 700, color: '#137333', mt: 1 }}>
                                {healthData.storage.duplicates_prevented_tb} <Typography component="span" variant="h5">TB</Typography>
                            </Typography>
                            <Typography variant="body2" color="textSecondary" sx={{ mt: 1 }}>
                                Prevented at the edge during legacy ingestion.
                            </Typography>
                        </CardContent>
                    </Card>
                </Grid>
                <Grid size={{ xs: 12, md: 8 }}>
                    <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%' }}>
                        <CardContent>
                            <Typography color="textSecondary" variant="caption" sx={{ fontWeight: 600 }}>CLOUD STORAGE COMPOSITION</Typography>

                            {/* Rich Multi-segment Progress Bar Simulator */}
                            <Box sx={{ mt: 3, mb: 2, height: 24, width: '100%', display: 'flex', borderRadius: 1, overflow: 'hidden' }}>
                                <Tooltip title={`Active Used: ${healthData.storage.active_used_tb} TB`}>
                                    <Box sx={{ width: `${storageUsagePct}%`, bgcolor: '#5e35b1' }} />
                                </Tooltip>
                                <Tooltip title={`Wasted/Orphaned: ${healthData.storage.orphaned_wasted_tb} TB`}>
                                    <Box sx={{ width: `${wastedPct}%`, bgcolor: '#ef4444' }} />
                                </Tooltip>
                                <Tooltip title={`Free Allocation`}>
                                    <Box sx={{ flexGrow: 1, bgcolor: '#f1f5f9' }} />
                                </Tooltip>
                            </Box>

                            <Stack direction="row" spacing={4}>
                                <Box sx={{ display: 'flex', alignItems: 'center' }}>
                                    <Box sx={{ w: 12, h: 12, bgcolor: '#5e35b1', borderRadius: '50%', width: 12, height: 12, mr: 1 }} />
                                    <Typography variant="caption" color="textSecondary">Active ({healthData.storage.active_used_tb} TB)</Typography>
                                </Box>
                                <Box sx={{ display: 'flex', alignItems: 'center' }}>
                                    <Box sx={{ w: 12, h: 12, bgcolor: '#ef4444', borderRadius: '50%', width: 12, height: 12, mr: 1 }} />
                                    <Typography variant="caption" color="textSecondary">Orphaned/Wasted ({healthData.storage.orphaned_wasted_tb} TB)</Typography>
                                </Box>
                            </Stack>
                        </CardContent>
                    </Card>
                </Grid>
            </Grid>

            {/* Bottom Row: Debt Remediation Action Center */}
            <Typography variant="h6" sx={{ fontWeight: 600, mb: 2, color: '#121926' }}>
                Debt Remediation Center
            </Typography>
            <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3 }}>
                <List sx={{ p: 0 }}>
                    {healthData.debt_flags.map((flag, index) => (
                        <React.Fragment key={flag.id}>
                            <ListItem sx={{ p: 3, display: 'flex', alignItems: 'flex-start' }}>
                                <ListItemIcon sx={{ mt: 0.5 }}>{flag.icon}</ListItemIcon>
                                <ListItemText
                                    primary={
                                        <Stack direction="row" alignItems="center" spacing={2} sx={{ mb: 0.5 }}>
                                            <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>{flag.title}</Typography>
                                            <Chip label={`${flag.impact} Impact`} size="small" color={flag.impact === 'Critical' ? 'error' : 'warning'} sx={{ height: 20, fontSize: '0.7rem' }} />
                                        </Stack>
                                    }
                                    secondary={`${flag.count.toLocaleString()} assets identified.`}
                                />
                                <Box sx={{ ml: 2 }}>
                                    {flag.type === 'stale' ? (
                                        <Button
                                            variant="outlined"
                                            startIcon={<Archive />}
                                            onClick={() => handleRemediate(flag.type)}
                                            sx={{ borderColor: '#cbd5e1', color: '#475569' }}
                                        >
                                            Move to S3 Glacier
                                        </Button>
                                    ) : (
                                        <Button
                                            variant="contained"
                                            startIcon={<CleaningServices />}
                                            onClick={() => handleRemediate(flag.type)}
                                            sx={{ bgcolor: '#121926', '&:hover': { bgcolor: '#334155' } }}
                                        >
                                            Remediate Now
                                        </Button>
                                    )}
                                </Box>
                            </ListItem>
                            {index < healthData.debt_flags.length - 1 && <Divider />}
                        </React.Fragment>
                    ))}
                </List>
            </Paper>
        </Box>
    );
}