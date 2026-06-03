import React, { useState, useEffect } from 'react';
import {
    Box, Paper, Typography, Grid, Button, Stack,
    TextField, MenuItem, Switch, FormControlLabel,
    Slider, Divider, Alert, LinearProgress, Chip
} from '@mui/material';
import {
    SmartToy, Save, Memory, AccountBalanceWallet,
    Security, SwapCalls, LocalFireDepartment
} from '@mui/icons-material';
import { useNotify } from '../../../context/NotificationContext'; // Assuming you have this

export default function AiGatewayTab() {
    const notify = useNotify();
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [config, setConfig] = useState({
        active_provider: 'openai',
        generation_model: 'gpt-4o',
        embedding_model: 'text-embedding-3-small',
        monthly_budget_usd: 100,
        current_spend_usd: 42.50, // Simulated current spend
        system_prompt: '',
        fallback_to_local: true
    });

    useEffect(() => {
        // Fetch current config from Rails API
        // fetch('/api/v1/ai_configuration').then(res => res.json()).then(data => { setConfig(data); setLoading(false); });

        // Simulating load for now
        setTimeout(() => setLoading(false), 500);
    }, []);

    const handleChange = (field, value) => {
        setConfig(prev => ({ ...prev, [field]: value }));
    };

    const handleSave = async () => {
        setSaving(true);
        try {
            // await fetch('/api/v1/ai_configuration', { method: 'PUT', body: JSON.stringify({ ai_configuration: config }) });
            setTimeout(() => {
                notify("AI Gateway routing updated. Python MCP synchronized.", "success");
                setSaving(false);
            }, 800);
        } catch (e) {
            notify("Failed to sync configuration.", "error");
            setSaving(false);
        }
    };

    const spendPercentage = (config.current_spend_usd / config.monthly_budget_usd) * 100;

    if (loading) return <LinearProgress color="secondary" />;

    return (
        <Box>
            <Box sx={{ mb: 4, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                    <Typography variant="h5" sx={{ fontWeight: 700, mb: 0.5, display: 'flex', alignItems: 'center', gap: 1.5 }}>
                        <Memory sx={{ color: '#5e35b1' }} />
                        AI & LLM Gateway Governance
                    </Typography>
                    <Typography variant="body2" color="textSecondary">
                        Manage foundational models, operational budgets, and LangChain orchestration rules.
                    </Typography>
                </Box>
                <Button
                    variant="contained"
                    startIcon={<Save />}
                    onClick={handleSave}
                    disabled={saving}
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                >
                    {saving ? 'Synchronizing...' : 'Save & Sync Gateway'}
                </Button>
            </Box>

            <Grid container spacing={4}>
                {/* LEFT COLUMN: Routing & Models */}
                <Grid item xs={12} md={7}>
                    <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 3, mb: 4 }}>
                        <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 3, display: 'flex', alignItems: 'center', gap: 1 }}>
                            <SwapCalls color="primary" /> Traffic Routing & Models
                        </Typography>

                        <Grid container spacing={3}>
                            <Grid item xs={12}>
                                <TextField
                                    select
                                    fullWidth
                                    label="Active Cloud Provider"
                                    value={config.active_provider}
                                    onChange={(e) => handleChange('active_provider', e.target.value)}
                                >
                                    <MenuItem value="openai">OpenAI (Default)</MenuItem>
                                    <MenuItem value="anthropic">Anthropic (Claude)</MenuItem>
                                    <MenuItem value="huggingface">HuggingFace (Managed Endpoint)</MenuItem>
                                    <MenuItem value="perplexity">Perplexity AI</MenuItem>
                                </TextField>
                            </Grid>
                            <Grid item xs={12} sm={6}>
                                <TextField
                                    select
                                    fullWidth
                                    label="Generation Model (Text/Agents)"
                                    value={config.generation_model}
                                    onChange={(e) => handleChange('generation_model', e.target.value)}
                                >
                                    <MenuItem value="gpt-4o">GPT-4o (High Intelligence)</MenuItem>
                                    <MenuItem value="gpt-4o-mini">GPT-4o-Mini (High Speed)</MenuItem>
                                    <MenuItem value="claude-3-sonnet">Claude 3.5 Sonnet</MenuItem>
                                    <MenuItem value="llama-3">Llama 3 70B</MenuItem>
                                </TextField>
                            </Grid>
                            <Grid item xs={12} sm={6}>
                                <TextField
                                    select
                                    fullWidth
                                    label="Embedding Model (Vectors)"
                                    value={config.embedding_model}
                                    onChange={(e) => handleChange('embedding_model', e.target.value)}
                                >
                                    <MenuItem value="text-embedding-3-small">text-embedding-3-small (1536d)</MenuItem>
                                    <MenuItem value="text-embedding-3-large">text-embedding-3-large (3072d)</MenuItem>
                                </TextField>
                            </Grid>
                        </Grid>

                        <Divider sx={{ my: 3 }} />

                        <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px dashed #cbd5e1' }}>
                            <FormControlLabel
                                control={<Switch checked={config.fallback_to_local} onChange={(e) => handleChange('fallback_to_local', e.target.checked)} color="primary" />}
                                label={
                                    <Box>
                                        <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Enable Edge Fallback</Typography>
                                        <Typography variant="caption" color="textSecondary">If cloud provider times out, failover to a localized LangChain model to prevent pipeline blockage.</Typography>
                                    </Box>
                                }
                            />
                        </Box>
                    </Paper>

                    <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 3 }}>
                        <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 3, display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Security sx={{ color: '#10b981' }} /> Global System Persona (RAG Base)
                        </Typography>
                        <TextField
                            multiline
                            rows={4}
                            fullWidth
                            variant="outlined"
                            placeholder="You are an enterprise AI working within a Headless DAM..."
                            value={config.system_prompt}
                            onChange={(e) => handleChange('system_prompt', e.target.value)}
                            helperText="This prompt is prepended to all LangChain agents and Copilot queries. Use this to enforce brand tone and strict data output formats."
                        />
                    </Paper>
                </Grid>

                {/* RIGHT COLUMN: Budgets & Metrics */}
                <Grid item xs={12} md={5}>
                    <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 3, mb: 4 }}>
                        <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 3, display: 'flex', alignItems: 'center', gap: 1 }}>
                            <AccountBalanceWallet sx={{ color: '#f59e0b' }} /> Financial Token Governance
                        </Typography>

                        <Box sx={{ mb: 4 }}>
                            <Stack direction="row" justifyContent="space-between" sx={{ mb: 1 }}>
                                <Typography variant="body2" color="textSecondary">Current Pipeline Spend (MTD)</Typography>
                                <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>${config.current_spend_usd.toFixed(2)} / ${config.monthly_budget_usd}</Typography>
                            </Stack>
                            <LinearProgress
                                variant="determinate"
                                value={spendPercentage > 100 ? 100 : spendPercentage}
                                color={spendPercentage > 85 ? "error" : "primary"}
                                sx={{ height: 8, borderRadius: 4 }}
                            />
                        </Box>

                        <Typography variant="subtitle2" sx={{ mb: 1, fontWeight: 600 }}>Hard Limit Trigger (USD)</Typography>
                        <Slider
                            value={config.monthly_budget_usd}
                            onChange={(e, val) => handleChange('monthly_budget_usd', val)}
                            step={50}
                            min={50}
                            max={1000}
                            valueLabelDisplay="auto"
                            valueLabelFormat={(v) => `$${v}`}
                            sx={{ color: '#5e35b1' }}
                        />
                        <Typography variant="caption" color="textSecondary">
                            If the gateway detects API spend exceeding this threshold, it will auto-trigger the "Edge Fallback" circuit or pause non-critical batch processes.
                        </Typography>
                    </Paper>

                    <Paper elevation={0} sx={{ p: 3, border: '1px solid #fca5a5', bgcolor: '#fef2f2', borderRadius: 3 }}>
                        <Typography variant="subtitle1" sx={{ fontWeight: 600, mb: 1, color: '#b91c1c', display: 'flex', alignItems: 'center', gap: 1 }}>
                            <LocalFireDepartment fontSize="small" /> Circuit Breaker
                        </Typography>
                        <Typography variant="body2" sx={{ color: '#991b1b', mb: 2 }}>
                            In the event of a catastrophic API loop or hallucination cascade, you can sever the Python MCP connection instantly.
                        </Typography>
                        <Button variant="contained" color="error" fullWidth sx={{ textTransform: 'none', fontWeight: 600 }}>
                            Kill Switch (Halt All AI Agents)
                        </Button>
                    </Paper>
                </Grid>
            </Grid>
        </Box>
    );
}