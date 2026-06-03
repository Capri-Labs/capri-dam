import React, { useState, useEffect } from 'react';
import {
    Box, Typography, Grid, Card, CardContent, Paper,
    Button, Stack, Chip, Divider, List, ListItem,
    ListItemText, ListItemIcon, IconButton, Switch, Tooltip
} from '@mui/material';
import {
    Route, PlayArrow, Stop, SmartToy,
    AccountTree, Gavel, AutoFixHigh, CheckCircle,
    Sensors, Extension, Speed, History
} from '@mui/icons-material';

export default function AgentWorkflows() {
    const [workflows, setWorkflows] = useState([]);
    const [executionLogs, setExecutionLogs] = useState([]);

    useEffect(() => {
        // Simulated API fetch: GET /api/v1/ai/agent_workflows
        const mockWorkflows = [
            {
                id: 'wf-1',
                name: 'Auto-SEO Enrichment',
                description: 'Triggers on new image ingestion. Extracts visual context and maps semantic keywords.',
                trigger: 'asset.staged',
                agent_model: 'gpt-4o-mini',
                tools_enabled: ['VisualContextExtractor', 'SEOTaxonomyMapper'],
                active: true,
                success_rate: '99.2%',
                avg_latency: '1.4s'
            },
            {
                id: 'wf-2',
                name: 'Copyright & Compliance Guard',
                description: 'Scans EXIF data and visually detects watermarks to prevent legal/usage debt.',
                trigger: 'asset.staged',
                agent_model: 'gpt-4o',
                tools_enabled: ['ExifReader', 'WatermarkDetector', 'QuarantineAction'],
                active: true,
                success_rate: '100%',
                avg_latency: '2.8s'
            },
            {
                id: 'wf-3',
                name: 'Legacy Metadata Sanitizer',
                description: 'Runs on a nightly cron job to clean unstructured JSONB properties across the DAM.',
                trigger: 'schedule.nightly',
                agent_model: 'llama-3-local',
                tools_enabled: ['JsonSchemaValidator', 'DatabasePatcher'],
                active: false,
                success_rate: '-',
                avg_latency: '-'
            }
        ];
        setWorkflows(mockWorkflows);

        // Simulated real-time execution stream
        setExecutionLogs([
            { id: 1, time: '11:12:04', agent: 'Auto-SEO Enrichment', action: 'Mapped 4 semantic tags to summer_hero.jpg', status: 'success' },
            { id: 2, time: '11:11:52', agent: 'Copyright Guard', action: 'Quarantined GettyImages_Draft.png (Watermark detected)', status: 'warning' },
            { id: 3, time: '11:05:10', agent: 'Auto-SEO Enrichment', action: 'Mapped 6 semantic tags to urban_skate.jpg', status: 'success' },
        ]);
    }, []);

    const toggleWorkflow = (id) => {
        setWorkflows(workflows.map(wf => wf.id === id ? { ...wf, active: !wf.active } : wf));
    };

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <Stack direction="row" justifyContent="space-between" alignItems="flex-end" sx={{ mb: 4 }}>
                <Box>
                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', mb: 1, display: 'flex', alignItems: 'center' }}>
                        <Route sx={{ mr: 1.5, color: '#0ea5e9', fontSize: 32 }} />
                        Agent Automations
                    </Typography>
                    <Typography variant="body2" color="textSecondary">
                        Orchestrate autonomous LangChain agents. Map system events to AI operational workflows.
                    </Typography>
                </Box>
                <Button variant="contained" startIcon={<AccountTree />} sx={{ bgcolor: '#0ea5e9', '&:hover': { bgcolor: '#0284c7' } }}>
                    Create New Workflow
                </Button>
            </Stack>

            <Grid container spacing={3}>
                {/* Main Orchestration Canvas */}
                <Grid item xs={12} lg={8}>
                    <Stack spacing={3}>
                        {workflows.map((wf) => (
                            <Card key={wf.id} elevation={0} sx={{ border: '1px solid', borderColor: wf.active ? '#bae6fd' : '#e2e8f0', borderRadius: 3, transition: 'all 0.2s', ...(wf.active && { boxShadow: '0 4px 20px rgba(14, 165, 233, 0.05)' }) }}>
                                <CardContent sx={{ p: 3 }}>
                                    <Stack direction="row" justifyContent="space-between" alignItems="flex-start" sx={{ mb: 2 }}>
                                        <Box>
                                            <Stack direction="row" alignItems="center" spacing={1.5} sx={{ mb: 0.5 }}>
                                                <Typography variant="h6" sx={{ fontWeight: 600 }}>{wf.name}</Typography>
                                                {wf.active ? (
                                                    <Chip label="Listening" size="small" color="success" sx={{ height: 20, fontSize: '0.7rem' }} icon={<PlayArrow sx={{ fontSize: '1rem' }} />} />
                                                ) : (
                                                    <Chip label="Halted" size="small" sx={{ height: 20, fontSize: '0.7rem', bgcolor: '#f1f5f9' }} icon={<Stop sx={{ fontSize: '1rem' }} />} />
                                                )}
                                            </Stack>
                                            <Typography variant="body2" color="textSecondary">{wf.description}</Typography>
                                        </Box>
                                        <Switch checked={wf.active} onChange={() => toggleWorkflow(wf.id)} color="primary" />
                                    </Stack>

                                    {/* Pipeline Visualizer */}
                                    <Box sx={{ mt: 3, p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px dashed #cbd5e1' }}>
                                        <Grid container alignItems="center" spacing={2}>
                                            {/* Trigger Node */}
                                            <Grid item xs={3}>
                                                <Paper elevation={0} sx={{ p: 1.5, textAlign: 'center', border: '1px solid #e2e8f0', bgcolor: '#fff' }}>
                                                    <Sensors sx={{ color: '#64748b', mb: 0.5 }} />
                                                    <Typography variant="caption" sx={{ display: 'block', fontWeight: 600, color: '#475569' }}>Event Trigger</Typography>
                                                    <Typography variant="caption" sx={{ fontFamily: 'monospace', color: '#0ea5e9' }}>{wf.trigger}</Typography>
                                                </Paper>
                                            </Grid>

                                            {/* Connector */}
                                            <Grid item xs={1} sx={{ textAlign: 'center', color: '#94a3b8' }}>➔</Grid>

                                            {/* Agent Node */}
                                            <Grid item xs={4}>
                                                <Paper elevation={0} sx={{ p: 1.5, textAlign: 'center', border: '1px solid #c7d2fe', bgcolor: '#e0e7ff' }}>
                                                    <SmartToy sx={{ color: '#4f46e5', mb: 0.5 }} />
                                                    <Typography variant="caption" sx={{ display: 'block', fontWeight: 600, color: '#3730a3' }}>LangChain Agent</Typography>
                                                    <Typography variant="caption" sx={{ fontFamily: 'monospace', color: '#4f46e5' }}>{wf.agent_model}</Typography>
                                                </Paper>
                                            </Grid>

                                            {/* Connector */}
                                            <Grid item xs={1} sx={{ textAlign: 'center', color: '#94a3b8' }}>➔</Grid>

                                            {/* Tools Node */}
                                            <Grid item xs={3}>
                                                <Paper elevation={0} sx={{ p: 1.5, textAlign: 'center', border: '1px solid #e2e8f0', bgcolor: '#fff' }}>
                                                    <Extension sx={{ color: '#64748b', mb: 0.5 }} />
                                                    <Typography variant="caption" sx={{ display: 'block', fontWeight: 600, color: '#475569' }}>Capabilities</Typography>
                                                    <Typography variant="caption" color="textSecondary">{wf.tools_enabled.length} Tools Loaded</Typography>
                                                </Paper>
                                            </Grid>
                                        </Grid>
                                    </Box>

                                    {/* Operational Stats */}
                                    <Stack direction="row" spacing={4} sx={{ mt: 3, pt: 2, borderTop: '1px solid #f1f5f9' }}>
                                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                            <CheckCircle sx={{ fontSize: 16, color: '#10b981' }} />
                                            <Typography variant="caption" color="textSecondary">Reliability: <strong>{wf.success_rate}</strong></Typography>
                                        </Box>
                                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                            <Speed sx={{ fontSize: 16, color: '#8b5cf6' }} />
                                            <Typography variant="caption" color="textSecondary">Avg Latency: <strong>{wf.avg_latency}</strong></Typography>
                                        </Box>
                                    </Stack>
                                </CardContent>
                            </Card>
                        ))}
                    </Stack>
                </Grid>

                {/* Right Sidebar: Execution Stream */}
                <Grid item xs={12} lg={4}>
                    <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%', display: 'flex', flexDirection: 'column' }}>
                        <Box sx={{ p: 2.5, borderBottom: '1px solid #e3e8ef', display: 'flex', alignItems: 'center', gap: 1.5 }}>
                            <History sx={{ color: '#64748b' }} />
                            <Typography variant="h6" sx={{ fontWeight: 600 }}>Agent Telemetry</Typography>
                        </Box>
                        <List sx={{ flexGrow: 1, overflowY: 'auto', p: 0 }}>
                            {executionLogs.map((log, index) => (
                                <React.Fragment key={log.id}>
                                    <ListItem sx={{ p: 2.5, alignItems: 'flex-start' }}>
                                        <ListItemIcon sx={{ minWidth: 36, mt: 0.5 }}>
                                            {log.status === 'success' ? <AutoFixHigh fontSize="small" sx={{ color: '#10b981' }} /> : <Gavel fontSize="small" sx={{ color: '#f59e0b' }} />}
                                        </ListItemIcon>
                                        <ListItemText
                                            primary={
                                                <Stack direction="row" justifyContent="space-between" sx={{ mb: 0.5 }}>
                                                    <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>{log.agent}</Typography>
                                                    <Typography variant="caption" color="textSecondary">{log.time}</Typography>
                                                </Stack>
                                            }
                                            secondary={log.action}
                                            secondaryTypographyProps={{ variant: 'body2', color: '#475569' }}
                                        />
                                    </ListItem>
                                    {index < executionLogs.length - 1 && <Divider component="li" />}
                                </React.Fragment>
                            ))}
                        </List>
                        <Box sx={{ p: 2, bgcolor: '#f8fafc', borderTop: '1px solid #e3e8ef', textAlign: 'center' }}>
                            <Button size="small" color="inherit">View Full Logs</Button>
                        </Box>
                    </Paper>
                </Grid>
            </Grid>
        </Box>
    );
}