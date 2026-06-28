import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  Box, Paper, Typography, TextField, IconButton,
  Button, Chip, Stack, Divider, Tooltip, Slider,
  MenuItem, CircularProgress, Alert, Tabs, Tab,
  Badge,
} from '@mui/material';
import {
  AutoAwesome, Send, ContentCopy, Delete, Add,
  RestartAlt, Science, History, Settings,
  CheckCircleOutlined, ErrorOutlined, Token,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

// ─── helpers ────────────────────────────────────────────────────────────────

const ROLE_COLORS = {
  system:    { bg: '#fef3c7', border: '#fcd34d', label: '#92400e' },
  user:      { bg: '#f0f9ff', border: '#bae6fd', label: '#0c4a6e' },
  assistant: { bg: '#f0fdf4', border: '#86efac', label: '#14532d' },
};

function MessageBlock({ msg, index, onDelete, onChange, disabled }) {
  const { t } = useTranslation();
  const colors = ROLE_COLORS[msg.role] || ROLE_COLORS.user;

  return (
    <Paper
      elevation={0}
      sx={{
        border: `1px solid ${colors.border}`,
        borderRadius: 2,
        overflow: 'hidden',
      }}
    >
      <Box
        sx={{
          px: 2,
          py: 0.75,
          bgcolor: colors.bg,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        <Stack direction="row" spacing={1} alignItems="center">
          <Chip
            label={t(`aiLab.playground.roles.${msg.role}`, { defaultValue: msg.role })}
            size="small"
            sx={{
              height: 20,
              fontSize: '0.7rem',
              bgcolor: colors.border,
              color: colors.label,
              fontWeight: 700,
            }}
          />
          <Typography variant="caption" color="text.secondary">
            {t('aiLab.playground.messageIndex', { index: index + 1, defaultValue: `#${index + 1}` })}
          </Typography>
        </Stack>
        <Tooltip title={t('common.delete')}>
          <span>
            <IconButton size="small" onClick={() => onDelete(index)} disabled={disabled}>
              <Delete fontSize="small" />
            </IconButton>
          </span>
        </Tooltip>
      </Box>
      <TextField
        fullWidth
        multiline
        minRows={3}
        maxRows={12}
        value={msg.content}
        onChange={(e) => onChange(index, e.target.value)}
        disabled={disabled}
        placeholder={t(`aiLab.playground.placeholder.${msg.role}`, {
          defaultValue: `Enter ${msg.role} message…`,
        })}
        slotProps={{
          input: {
            disableUnderline: true,
            sx: { fontSize: '0.875rem', fontFamily: 'monospace', p: 2 },
          },
        }}
        variant="standard"
      />
    </Paper>
  );
}

function TokenBadge({ usage }) {
  if (!usage) return null;
  return (
    <Stack direction="row" spacing={2}>
      <Stack direction="row" spacing={0.5} alignItems="center">
        <Token sx={{ fontSize: 14, color: '#64748b' }} />
        <Typography variant="caption" color="text.secondary">
          Prompt: <strong>{usage.prompt_tokens ?? '—'}</strong>
        </Typography>
      </Stack>
      <Typography variant="caption" color="text.secondary">
        Completion: <strong>{usage.completion_tokens ?? '—'}</strong>
      </Typography>
      <Typography variant="caption" color="text.secondary">
        Total: <strong>{usage.total_tokens ?? '—'}</strong>
      </Typography>
    </Stack>
  );
}

// ─── main component ──────────────────────────────────────────────────────────

const DEFAULT_MESSAGES = [
  { role: 'system',  content: 'You are a helpful DAM content steward. Be concise and precise.' },
  { role: 'user',    content: '' },
];

export default function PromptPlayground() {
  const { t } = useTranslation();

  // ── Config state ──
  const [models, setModels]             = useState([]);
  const [defaultModel, setDefaultModel] = useState('');
  const [model, setModel]               = useState('');
  const [temperature, setTemperature]   = useState(0.7);
  const [maxTokens, setMaxTokens]       = useState(1024);
  const [configLoading, setConfigLoading] = useState(true);

  // ── Prompt state ──
  const [messages, setMessages]   = useState(DEFAULT_MESSAGES);
  const [response, setResponse]   = useState(null);   // { content, usage, model, latency_ms }
  const [loading, setLoading]     = useState(false);
  const [error, setError]         = useState(null);
  const [history, setHistory]     = useState([]);
  const [activeTab, setActiveTab] = useState(0);       // 0=response 1=history

  const responseRef = useRef(null);
  const csrfToken   = document.querySelector('[name="csrf-token"]')?.content;

  // ── Load available models from Rails → AiConfiguration ──
  useEffect(() => {
    fetch('/api/v1/ai/lab/models', { headers: { Accept: 'application/json' } })
      .then((r) => r.json())
      .then((data) => {
        setModels(data.models ?? []);
        setDefaultModel(data.default_model ?? '');
        setModel(data.default_model ?? '');
      })
      .catch(() => {/* silently degrade — model list falls back to user input */})
      .finally(() => setConfigLoading(false));
  }, []);

  // ── Handlers ──
  const handleMessageChange = useCallback((index, content) => {
    setMessages((prev) => prev.map((m, i) => (i === index ? { ...m, content } : m)));
  }, []);

  const handleMessageDelete = useCallback((index) => {
    setMessages((prev) => prev.filter((_, i) => i !== index));
  }, []);

  const handleAddMessage = (role) => {
    setMessages((prev) => [...prev, { role, content: '' }]);
  };

  const handleReset = () => {
    setMessages(DEFAULT_MESSAGES);
    setResponse(null);
    setError(null);
  };

  const handleSubmit = async () => {
    const trimmed = messages.map((m) => ({ ...m, content: m.content.trim() }));
    if (trimmed.every((m) => !m.content)) return;

    setLoading(true);
    setError(null);
    setResponse(null);
    const startMs = Date.now();

    try {
      const res = await fetch('/api/v1/ai/lab/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken,
          Accept: 'application/json',
        },
        body: JSON.stringify({ messages: trimmed, model, temperature, max_tokens: maxTokens }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error || `HTTP ${res.status}`);
        setLoading(false);
        return;
      }

      const entry = {
        id:          Date.now(),
        messages:    trimmed,
        model:       data.model ?? model,
        usage:       data.usage ?? null,
        content:     data.choices?.[0]?.message?.content ?? data.response ?? '',
        latency_ms:  Date.now() - startMs,
        timestamp:   new Date().toLocaleTimeString(),
      };

      setResponse(entry);
      setHistory((prev) => [entry, ...prev].slice(0, 20)); // keep last 20
      setActiveTab(0);
      setTimeout(() => responseRef.current?.scrollIntoView({ behavior: 'smooth' }), 50);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const handleCopyResponse = () => {
    if (response?.content) navigator.clipboard.writeText(response.content);
  };

  const handleRestoreHistory = (entry) => {
    setMessages(entry.messages);
    setModel(entry.model);
    setActiveTab(0);
  };

  // ── derived ──
  const canSubmit = !loading && messages.some((m) => m.content.trim());

  return (
    <Box sx={{ display: 'flex', height: 'calc(100vh - 64px)', overflow: 'hidden', bgcolor: '#f4f7fb' }}>

      {/* ── LEFT: Prompt Editor ────────────────────────────────────── */}
      <Box
        sx={{
          width: { xs: '100%', lg: 520 },
          flexShrink: 0,
          display: 'flex',
          flexDirection: 'column',
          borderRight: '1px solid #e2e8f0',
          bgcolor: '#ffffff',
          overflow: 'hidden',
        }}
      >
        {/* Header */}
        <Box sx={{ p: 2.5, borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center' }}>
          <Science sx={{ color: '#8e24aa', mr: 1.5 }} />
          <Box sx={{ flexGrow: 1 }}>
            <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
              {t('aiLab.playground.title', { defaultValue: 'Prompt Playground' })}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              {t('aiLab.playground.subtitle', {
                defaultValue: 'Build, test & iterate prompts against the AI Gateway',
              })}
            </Typography>
          </Box>
          <Tooltip title={t('aiLab.playground.reset', { defaultValue: 'Reset conversation' })}>
            <IconButton size="small" onClick={handleReset}>
              <RestartAlt fontSize="small" />
            </IconButton>
          </Tooltip>
        </Box>

        {/* Messages */}
        <Box sx={{ flexGrow: 1, overflowY: 'auto', p: 2, display: 'flex', flexDirection: 'column', gap: 2 }}>
          {messages.map((msg, i) => (
            <MessageBlock
              key={i}
              msg={msg}
              index={i}
              onDelete={handleMessageDelete}
              onChange={handleMessageChange}
              disabled={loading}
            />
          ))}

          {/* Add message buttons */}
          <Stack direction="row" spacing={1} sx={{ pt: 1 }}>
            {['user', 'assistant'].map((role) => (
              <Button
                key={role}
                size="small"
                variant="outlined"
                startIcon={<Add />}
                onClick={() => handleAddMessage(role)}
                disabled={loading}
                sx={{ textTransform: 'none', borderColor: ROLE_COLORS[role].border, color: ROLE_COLORS[role].label }}
              >
                {t(`aiLab.playground.roles.${role}`, { defaultValue: role })}
              </Button>
            ))}
          </Stack>
        </Box>

        {/* Submit */}
        <Box sx={{ p: 2, borderTop: '1px solid #e2e8f0' }}>
          <Button
            fullWidth
            variant="contained"
            size="large"
            startIcon={loading ? <CircularProgress size={18} color="inherit" /> : <Send />}
            onClick={handleSubmit}
            disabled={!canSubmit}
            sx={{ bgcolor: '#8e24aa', '&:hover': { bgcolor: '#6a1b9a' }, textTransform: 'none' }}
          >
            {loading
              ? t('aiLab.playground.running', { defaultValue: 'Running…' })
              : t('aiLab.playground.run', { defaultValue: 'Run Prompt' })}
          </Button>
        </Box>
      </Box>

      {/* ── MIDDLE: Parameters ─────────────────────────────────────── */}
      <Paper
        elevation={0}
        sx={{
          width: 260,
          flexShrink: 0,
          borderRight: '1px solid #e2e8f0',
          borderRadius: 0,
          display: { xs: 'none', xl: 'flex' },
          flexDirection: 'column',
          bgcolor: '#fafafa',
          overflowY: 'auto',
        }}
      >
        <Box sx={{ p: 2.5, borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: 1 }}>
          <Settings sx={{ fontSize: 18, color: '#64748b' }} />
          <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>
            {t('aiLab.playground.parameters', { defaultValue: 'Parameters' })}
          </Typography>
        </Box>

        <Stack spacing={3} sx={{ p: 2.5 }}>
          {/* Model */}
          <Box>
            <Typography variant="caption" sx={{ fontWeight: 600, mb: 1, display: 'block' }}>
              {t('aiLab.playground.model', { defaultValue: 'Model' })}
            </Typography>
            {configLoading ? (
              <CircularProgress size={20} />
            ) : models.length > 0 ? (
              <TextField
                select
                fullWidth
                size="small"
                value={model || defaultModel}
                onChange={(e) => setModel(e.target.value)}
                disabled={loading}
              >
                {models.map((m) => (
                  <MenuItem key={m} value={m}>
                    <Typography variant="body2" sx={{ fontFamily: 'monospace' }}>{m}</Typography>
                  </MenuItem>
                ))}
              </TextField>
            ) : (
              <TextField
                fullWidth
                size="small"
                value={model}
                onChange={(e) => setModel(e.target.value)}
                disabled={loading}
                placeholder="gpt-4o"
                slotProps={{ input: { sx: { fontFamily: 'monospace', fontSize: '0.85rem' } } }}
              />
            )}
          </Box>

          <Divider />

          {/* Temperature */}
          <Box>
            <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 1 }}>
              <Typography variant="caption" sx={{ fontWeight: 600 }}>
                {t('aiLab.playground.temperature', { defaultValue: 'Temperature' })}
              </Typography>
              <Chip label={temperature.toFixed(1)} size="small" sx={{ height: 20, fontSize: '0.7rem' }} />
            </Stack>
            <Slider
              value={temperature}
              min={0}
              max={2}
              step={0.1}
              onChange={(_, v) => setTemperature(v)}
              disabled={loading}
              sx={{ color: '#8e24aa' }}
              marks={[{ value: 0, label: '0' }, { value: 1, label: '1' }, { value: 2, label: '2' }]}
            />
            <Typography variant="caption" color="text.secondary">
              {temperature < 0.5
                ? t('aiLab.playground.tempHintFocused', { defaultValue: 'More focused & deterministic' })
                : temperature > 1.2
                  ? t('aiLab.playground.tempHintCreative', { defaultValue: 'More creative & random' })
                  : t('aiLab.playground.tempHintBalanced', { defaultValue: 'Balanced' })}
            </Typography>
          </Box>

          <Divider />

          {/* Max tokens */}
          <Box>
            <Typography variant="caption" sx={{ fontWeight: 600, mb: 1, display: 'block' }}>
              {t('aiLab.playground.maxTokens', { defaultValue: 'Max Tokens' })}
            </Typography>
            <TextField
              fullWidth
              size="small"
              type="number"
              value={maxTokens}
              onChange={(e) => setMaxTokens(Math.max(1, Math.min(8192, parseInt(e.target.value) || 1024)))}
              disabled={loading}
              inputProps={{ min: 1, max: 8192 }}
              helperText="1 – 8 192"
            />
          </Box>
        </Stack>
      </Paper>

      {/* ── RIGHT: Response / History ──────────────────────────────── */}
      <Box sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <Box sx={{ borderBottom: '1px solid #e2e8f0', bgcolor: '#fff' }}>
          <Tabs
            value={activeTab}
            onChange={(_, v) => setActiveTab(v)}
            sx={{ px: 2 }}
            TabIndicatorProps={{ sx: { bgcolor: '#8e24aa' } }}
          >
            <Tab
              label={t('aiLab.playground.tabs.response', { defaultValue: 'Response' })}
              sx={{ textTransform: 'none', fontWeight: 600 }}
            />
            <Tab
              label={
                <Badge badgeContent={history.length} color="secondary" max={20}>
                  {t('aiLab.playground.tabs.history', { defaultValue: 'History' })}
                </Badge>
              }
              sx={{ textTransform: 'none', fontWeight: 600 }}
            />
          </Tabs>
        </Box>

        <Box sx={{ flexGrow: 1, overflowY: 'auto', p: 3 }}>
          {/* ── Response tab ── */}
          {activeTab === 0 && (
            <>
              {error && (
                <Alert severity="error" icon={<ErrorOutlined />} sx={{ mb: 3 }}>
                  {error}
                </Alert>
              )}

              {!response && !loading && !error && (
                <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', color: '#94a3b8', py: 8 }}>
                  <AutoAwesome sx={{ fontSize: 48, mb: 2, opacity: 0.4 }} />
                  <Typography variant="h6">
                    {t('aiLab.playground.emptyTitle', { defaultValue: 'Ready to run' })}
                  </Typography>
                  <Typography variant="body2">
                    {t('aiLab.playground.emptyBody', {
                      defaultValue: 'Write your prompts on the left, then click Run Prompt.',
                    })}
                  </Typography>
                </Box>
              )}

              {loading && (
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, py: 4 }}>
                  <CircularProgress size={24} sx={{ color: '#8e24aa' }} />
                  <Typography variant="body2" color="text.secondary">
                    {t('aiLab.playground.waiting', { defaultValue: 'Waiting for AI Gateway…' })}
                  </Typography>
                </Box>
              )}

              {response && !loading && (
                <Paper
                  elevation={0}
                  ref={responseRef}
                  sx={{ border: '1px solid #e2e8f0', borderRadius: 3, overflow: 'hidden' }}
                >
                  {/* Response header */}
                  <Box sx={{ px: 2.5, py: 1.5, borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', bgcolor: '#f8fafc' }}>
                    <Stack direction="row" spacing={1.5} alignItems="center">
                      <CheckCircleOutlined sx={{ color: '#10b981', fontSize: 18 }} />
                      <Typography variant="caption" sx={{ fontWeight: 600 }}>
                        {response.model}
                      </Typography>
                      <Chip
                        label={`${response.latency_ms} ms`}
                        size="small"
                        sx={{ height: 18, fontSize: '0.65rem', bgcolor: '#f1f5f9' }}
                      />
                    </Stack>
                    <Tooltip title={t('aiLab.playground.copyResponse', { defaultValue: 'Copy response' })}>
                      <IconButton size="small" onClick={handleCopyResponse}>
                        <ContentCopy fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  </Box>

                  {/* Response body */}
                  <Box sx={{ p: 2.5 }}>
                    <Typography
                      variant="body2"
                      sx={{
                        whiteSpace: 'pre-wrap',
                        fontFamily: 'monospace',
                        fontSize: '0.875rem',
                        lineHeight: 1.7,
                        color: '#1e293b',
                      }}
                    >
                      {response.content}
                    </Typography>
                  </Box>

                  {/* Token usage */}
                  {response.usage && (
                    <Box sx={{ px: 2.5, py: 1.5, borderTop: '1px solid #e2e8f0', bgcolor: '#f8fafc' }}>
                      <TokenBadge usage={response.usage} />
                    </Box>
                  )}
                </Paper>
              )}
            </>
          )}

          {/* ── History tab ── */}
          {activeTab === 1 && (
            <>
              {history.length === 0 ? (
                <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', py: 8, color: '#94a3b8' }}>
                  <History sx={{ fontSize: 48, mb: 2, opacity: 0.4 }} />
                  <Typography variant="body2">
                    {t('aiLab.playground.noHistory', { defaultValue: 'No runs yet in this session.' })}
                  </Typography>
                </Box>
              ) : (
                <Stack spacing={2}>
                  {history.map((entry, i) => (
                    <Paper
                      key={entry.id}
                      elevation={0}
                      sx={{ border: '1px solid #e2e8f0', borderRadius: 2, overflow: 'hidden' }}
                    >
                      <Box sx={{ px: 2, py: 1, bgcolor: '#f8fafc', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <Stack direction="row" spacing={1} alignItems="center">
                          <Typography variant="caption" sx={{ fontWeight: 600 }}>
                            #{history.length - i}
                          </Typography>
                          <Chip label={entry.model} size="small" sx={{ height: 18, fontSize: '0.65rem' }} />
                          <Typography variant="caption" color="text.secondary">{entry.timestamp}</Typography>
                        </Stack>
                        <Button
                          size="small"
                          variant="outlined"
                          onClick={() => handleRestoreHistory(entry)}
                          sx={{ textTransform: 'none', fontSize: '0.75rem' }}
                        >
                          {t('aiLab.playground.restore', { defaultValue: 'Restore' })}
                        </Button>
                      </Box>
                      <Box sx={{ p: 2 }}>
                        <Typography
                          variant="caption"
                          sx={{
                            display: '-webkit-box',
                            WebkitLineClamp: 3,
                            WebkitBoxOrient: 'vertical',
                            overflow: 'hidden',
                            whiteSpace: 'pre-wrap',
                            fontFamily: 'monospace',
                            color: '#475569',
                          }}
                        >
                          {entry.content}
                        </Typography>
                        {entry.usage && (
                          <Box sx={{ mt: 1 }}>
                            <TokenBadge usage={entry.usage} />
                          </Box>
                        )}
                      </Box>
                    </Paper>
                  ))}
                </Stack>
              )}
            </>
          )}
        </Box>
      </Box>
    </Box>
  );
}

