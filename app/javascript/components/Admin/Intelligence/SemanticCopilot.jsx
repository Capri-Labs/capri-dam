import React, { useState, useRef, useEffect, useCallback } from 'react';
import {
  Box, Paper, Typography, TextField, IconButton, Stack,
  Card, CardMedia, CardContent, CardActions, Button, Chip,
  CircularProgress, Avatar, Divider, Tooltip, LinearProgress,
  ToggleButtonGroup, ToggleButton, Alert,
} from '@mui/material';
import {
  Send, AutoAwesome, ContentCopy, OpenInNew,
  ImageSearch, SmartToy, Person, Image, VideoFile,
  Description, AudioFile, InsertDriveFile,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

// ─── constants ────────────────────────────────────────────────────────────────

const CONTENT_FILTERS = [
  { value: null,       label: 'copilot.filter.all',       icon: null },
  { value: 'image',    label: 'copilot.filter.images',    icon: <Image fontSize="small" /> },
  { value: 'video',    label: 'copilot.filter.videos',    icon: <VideoFile fontSize="small" /> },
  { value: 'document', label: 'copilot.filter.documents', icon: <Description fontSize="small" /> },
  { value: 'audio',    label: 'copilot.filter.audio',     icon: <AudioFile fontSize="small" /> },
];

const SESSION_KEY = 'capri:copilot:messages';

// ─── helpers ──────────────────────────────────────────────────────────────────

function assetTypeIcon(contentType) {
  if (!contentType) return <InsertDriveFile fontSize="small" />;
  if (contentType.startsWith('image/'))    return <Image fontSize="small" />;
  if (contentType.startsWith('video/'))    return <VideoFile fontSize="small" />;
  if (contentType.startsWith('audio/'))    return <AudioFile fontSize="small" />;
  return <Description fontSize="small" />;
}

function SimilarityBar({ score }) {
  if (score == null) return null;
  const pct   = Math.round(score * 100);
  const color = pct >= 80 ? '#10b981' : pct >= 60 ? '#f59e0b' : '#94a3b8';
  return (
    <Tooltip title={`${pct}% match`}>
      <Box sx={{ mt: 0.5 }}>
        <LinearProgress
          variant="determinate"
          value={pct}
          sx={{ height: 3, borderRadius: 2, bgcolor: '#f1f5f9', '& .MuiLinearProgress-bar': { bgcolor: color } }}
        />
      </Box>
    </Tooltip>
  );
}

function SuggestedPrompts({ onSelect, t }) {
  const suggestions = [
    t('copilot.suggestions.0', { defaultValue: 'Summer campaign visuals with bright colours' }),
    t('copilot.suggestions.1', { defaultValue: 'Product shots on white background' }),
    t('copilot.suggestions.2', { defaultValue: 'Team headshots for about pages' }),
    t('copilot.suggestions.3', { defaultValue: 'Urban architecture wide shots' }),
  ];
  return (
    <Box sx={{ px: 2.5, pb: 2 }}>
      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 1 }}>
        {t('copilot.suggestionsLabel', { defaultValue: 'Try asking:' })}
      </Typography>
      <Stack spacing={0.75}>
        {suggestions.map((s) => (
          <Button
            key={s}
            size="small"
            variant="outlined"
            onClick={() => onSelect(s)}
            sx={{
              justifyContent: 'flex-start',
              textTransform: 'none',
              fontSize: '0.8rem',
              borderColor: '#e2e8f0',
              color: '#475569',
              '&:hover': { borderColor: '#8e24aa', color: '#8e24aa' },
            }}
          >
            {s}
          </Button>
        ))}
      </Stack>
    </Box>
  );
}

// ─── main component ───────────────────────────────────────────────────────────

export default function SemanticCopilot() {
  const { t } = useTranslation();

  const [messages, setMessages] = useState(() => {
    try {
      const saved = sessionStorage.getItem(SESSION_KEY);
      return saved ? JSON.parse(saved) : [
        { sender: 'ai', text: t('copilot.greeting', { defaultValue: 'Hello. I am your Semantic Copilot. Describe the visual assets you need, or ask me to find media based on a conceptual theme.' }) },
      ];
    } catch {
      return [{ sender: 'ai', text: t('copilot.greeting', { defaultValue: 'Hello. I am your Semantic Copilot.' }) }];
    }
  });
  const [input, setInput]                 = useState('');
  const [isSearching, setIsSearching]     = useState(false);
  const [results, setResults]             = useState([]);
  const [contentFilter, setContentFilter] = useState(null);
  const [error, setError]                 = useState(null);
  const [activeQuery, setActiveQuery]     = useState('');
  const chatEndRef                        = useRef(null);
  const inputRef                          = useRef(null);
  const csrfToken                         = document.querySelector('[name="csrf-token"]')?.content;

  // Persist chat history to sessionStorage
  useEffect(() => {
    try { sessionStorage.setItem(SESSION_KEY, JSON.stringify(messages)); } catch { /* quota exceeded */ }
  }, [messages]);

  // Auto-scroll chat
  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const pushMessage = useCallback((sender, text) => {
    setMessages((prev) => [...prev, { sender, text }]);
  }, []);

  const handleSearch = async (queryOverride) => {
    const query = (queryOverride ?? input).trim();
    if (!query) return;

    setInput('');
    setError(null);
    setActiveQuery(query);
    pushMessage('user', query);
    setIsSearching(true);

    try {
      const res = await fetch('/api/v1/copilot/search', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token':  csrfToken,
          Accept:          'application/json',
        },
        body: JSON.stringify({
          query,
          limit:        20,
          content_type: contentFilter,
        }),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error || t('copilot.error.generic', { defaultValue: 'Search failed.' }));
        pushMessage('ai', data.error || t('copilot.error.generic', { defaultValue: 'Search failed.' }));
        return;
      }

      const found = data.results ?? [];
      setResults(found);

      const aiText = found.length > 0
        ? t('copilot.foundAssets', {
            count: found.length,
            defaultValue: `Found ${found.length} asset${found.length === 1 ? '' : 's'} matching your query.`,
          })
        : t('copilot.noAssets', { defaultValue: 'No assets matched that query. Try different keywords.' });

      pushMessage('ai', aiText);
    } catch (err) {
      const msg = t('copilot.error.connection', { defaultValue: 'Error connecting to the vector database.' });
      setError(msg);
      pushMessage('ai', msg);
    } finally {
      setIsSearching(false);
      inputRef.current?.focus();
    }
  };

  const handleClearSession = () => {
    const greeting = t('copilot.greeting', { defaultValue: 'Hello. I am your Semantic Copilot. Describe the visual assets you need.' });
    setMessages([{ sender: 'ai', text: greeting }]);
    setResults([]);
    setError(null);
    setActiveQuery('');
    try { sessionStorage.removeItem(SESSION_KEY); } catch { /* ignore */ }
  };

  return (
    <Box sx={{ display: 'flex', height: 'calc(100vh - 64px)', overflow: 'hidden', bgcolor: '#f8fafc' }}>

      {/* ── LEFT: Chat panel ──────────────────────────────────────────── */}
      <Paper
        elevation={0}
        sx={{
          width: 380,
          flexShrink: 0,
          display: 'flex',
          flexDirection: 'column',
          borderRight: '1px solid #e2e8f0',
          borderRadius: 0,
          bgcolor: '#ffffff',
        }}
      >
        {/* Header */}
        <Box sx={{ p: 2.5, borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: 1.5 }}>
          <AutoAwesome sx={{ color: '#8e24aa' }} />
          <Box sx={{ flexGrow: 1 }}>
            <Typography variant="subtitle1" sx={{ fontWeight: 700, lineHeight: 1.2 }}>
              {t('copilot.title', { defaultValue: 'Semantic Copilot' })}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              {t('copilot.poweredBy', { defaultValue: 'Powered by pgvector + HuggingFace MiniLM' })}
            </Typography>
          </Box>
          <Tooltip title={t('copilot.clearSession', { defaultValue: 'Clear conversation' })}>
            <IconButton size="small" onClick={handleClearSession} aria-label={t('copilot.clearSession', { defaultValue: 'Clear conversation' })}>
              <ContentCopy fontSize="small" sx={{ transform: 'scaleX(-1)' }} />
            </IconButton>
          </Tooltip>
        </Box>

        {/* Content-type filter */}
        <Box sx={{ px: 2, pt: 1.5, pb: 1, borderBottom: '1px solid #f1f5f9' }}>
          <ToggleButtonGroup
            value={contentFilter}
            exclusive
            onChange={(_, v) => setContentFilter(v)}
            size="small"
            aria-label={t('copilot.filter.label', { defaultValue: 'Filter by type' })}
            sx={{ flexWrap: 'wrap', gap: 0.5 }}
          >
            {CONTENT_FILTERS.map((f) => (
              <ToggleButton
                key={f.value ?? 'all'}
                value={f.value}
                aria-label={t(f.label)}
                sx={{
                  border: '1px solid #e2e8f0 !important',
                  borderRadius: '16px !important',
                  px: 1.5,
                  py: 0.25,
                  fontSize: '0.72rem',
                  textTransform: 'none',
                  '&.Mui-selected': { bgcolor: '#f3e8ff', color: '#8e24aa', borderColor: '#c084fc !important' },
                }}
              >
                {f.icon && <Box component="span" sx={{ mr: 0.5, display: 'flex', alignItems: 'center' }}>{f.icon}</Box>}
                {t(f.label, { defaultValue: f.label.split('.').pop() })}
              </ToggleButton>
            ))}
          </ToggleButtonGroup>
        </Box>

        {/* Chat history */}
        <Box sx={{ flexGrow: 1, overflowY: 'auto', p: 2, display: 'flex', flexDirection: 'column', gap: 2 }}>
          {messages.map((msg, i) => (
            <Box key={i} sx={{ display: 'flex', gap: 1.5, flexDirection: msg.sender === 'user' ? 'row-reverse' : 'row' }}>
              <Avatar
                sx={{ width: 30, height: 30, flexShrink: 0, bgcolor: msg.sender === 'user' ? '#1e293b' : '#f3e8ff', color: msg.sender === 'user' ? '#fff' : '#8e24aa' }}
                aria-hidden="true"
              >
                {msg.sender === 'user' ? <Person sx={{ fontSize: 16 }} /> : <SmartToy sx={{ fontSize: 16 }} />}
              </Avatar>
              <Box
                sx={{
                  maxWidth: '80%',
                  px: 2,
                  py: 1.25,
                  borderRadius: msg.sender === 'user' ? '12px 2px 12px 12px' : '2px 12px 12px 12px',
                  bgcolor: msg.sender === 'user' ? '#f1f5f9' : '#faf5ff',
                  border: '1px solid',
                  borderColor: msg.sender === 'user' ? '#e2e8f0' : '#f3e8ff',
                }}
              >
                <Typography variant="body2" sx={{ color: '#1e293b', lineHeight: 1.5, fontSize: '0.875rem' }}>
                  {msg.text}
                </Typography>
              </Box>
            </Box>
          ))}

          {isSearching && (
            <Box sx={{ display: 'flex', gap: 1.5, alignItems: 'center' }}>
              <Avatar sx={{ width: 30, height: 30, bgcolor: '#f3e8ff', color: '#8e24aa' }} aria-hidden="true">
                <SmartToy sx={{ fontSize: 16 }} />
              </Avatar>
              <Box sx={{ px: 2, py: 1.25, borderRadius: '2px 12px 12px 12px', bgcolor: '#faf5ff', border: '1px solid #f3e8ff', display: 'flex', alignItems: 'center', gap: 1 }}>
                <CircularProgress size={14} sx={{ color: '#8e24aa' }} />
                <Typography variant="body2" color="text.secondary" sx={{ fontSize: '0.875rem' }}>
                  {t('copilot.searching', { defaultValue: 'Traversing vector space…' })}
                </Typography>
              </Box>
            </Box>
          )}

          {/* Show suggestions when no messages beyond the greeting */}
          {messages.length === 1 && !isSearching && (
            <SuggestedPrompts onSelect={(s) => handleSearch(s)} t={t} />
          )}

          <div ref={chatEndRef} />
        </Box>

        {/* Input */}
        <Box sx={{ p: 2, borderTop: '1px solid #e2e8f0' }}>
          {error && (
            <Alert severity="error" sx={{ mb: 1.5, py: 0.5 }} onClose={() => setError(null)}>
              {error}
            </Alert>
          )}
          <Paper
            elevation={0}
            component="form"
            onSubmit={(e) => { e.preventDefault(); handleSearch(); }}
            role="search"
            sx={{
              display: 'flex',
              alignItems: 'center',
              border: '1px solid #cbd5e1',
              borderRadius: 6,
              '&:focus-within': { borderColor: '#8e24aa', boxShadow: '0 0 0 2px rgba(142,36,170,0.15)' },
            }}
          >
            <Tooltip title={t('copilot.imageSearch', { defaultValue: 'Reverse image search (coming soon)' })}>
              <span>
                <IconButton sx={{ p: '10px' }} aria-label={t('copilot.imageSearch', { defaultValue: 'Image search' })} disabled>
                  <ImageSearch fontSize="small" />
                </IconButton>
              </span>
            </Tooltip>
            <TextField
              inputRef={inputRef}
              fullWidth
              variant="standard"
              placeholder={t('copilot.inputPlaceholder', { defaultValue: 'e.g. Wide shots of urban architecture at night…' })}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              slotProps={{ input: { disableUnderline: true, sx: { fontSize: '0.875rem' }, 'aria-label': t('copilot.inputAriaLabel', { defaultValue: 'Search query' }) } }}
              disabled={isSearching}
            />
            <Divider orientation="vertical" sx={{ height: 24, mx: 0.5 }} />
            <IconButton
              type="submit"
              aria-label={t('copilot.send', { defaultValue: 'Send' })}
              disabled={!input.trim() || isSearching}
              sx={{ p: '10px', color: '#8e24aa', '&:disabled': { color: '#cbd5e1' } }}
            >
              <Send fontSize="small" />
            </IconButton>
          </Paper>
        </Box>
      </Paper>

      {/* ── RIGHT: Results canvas ─────────────────────────────────────── */}
      <Box sx={{ flexGrow: 1, overflowY: 'auto', p: 3 }}>
        {results.length === 0 && !isSearching ? (
          <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', color: '#94a3b8', py: 8 }}>
            <AutoAwesome sx={{ fontSize: 56, mb: 2, opacity: 0.3 }} />
            <Typography variant="h6" sx={{ fontWeight: 600, color: '#64748b' }}>
              {t('copilot.emptyCanvas', { defaultValue: 'The canvas is empty' })}
            </Typography>
            <Typography variant="body2" sx={{ mt: 0.5 }}>
              {t('copilot.emptyCanvasHint', { defaultValue: 'Ask the Copilot to retrieve assets to begin.' })}
            </Typography>
          </Box>
        ) : (
          <>
            {/* Results header */}
            {results.length > 0 && (
              <Stack direction="row" sx={{
  mb: 2.5,
  alignItems: "center"
}} spacing={1.5}>
                <Typography variant="body2" sx={{ fontWeight: 600, color: '#475569' }}>
                  {t('copilot.resultsHeader', {
                    count:       results.length,
                    query:       activeQuery,
                    defaultValue: `${results.length} result${results.length === 1 ? '' : 's'} for "${activeQuery}"`,
                  })}
                </Typography>
                {contentFilter && (
                  <Chip
                    label={contentFilter}
                    size="small"
                    onDelete={() => setContentFilter(null)}
                    sx={{ height: 20, fontSize: '0.7rem', bgcolor: '#f3e8ff', color: '#8e24aa' }}
                  />
                )}
              </Stack>
            )}

            {/* Cards grid */}
            <Box
              sx={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))',
                gap: 2,
              }}
            >
              {results.map((asset) => (
                <Card
                  key={asset.id}
                  elevation={0}
                  sx={{
                    border: '1px solid #e2e8f0',
                    borderRadius: 3,
                    transition: 'all 0.18s ease',
                    '&:hover': { borderColor: '#c084fc', transform: 'translateY(-2px)', boxShadow: '0 6px 16px rgba(142,36,170,0.08)' },
                  }}
                >
                  {/* Thumbnail */}
                  <Box sx={{ position: 'relative', bgcolor: '#f8fafc' }}>
                    {asset.url && asset.content_type?.startsWith('image/') ? (
                      <CardMedia
                        component="img"
                        height="160"
                        image={asset.url}
                        alt={asset.title}
                        loading="lazy"
                        sx={{ objectFit: 'cover' }}
                      />
                    ) : (
                      <Box sx={{ height: 160, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#94a3b8' }}>
                        {assetTypeIcon(asset.content_type)}
                      </Box>
                    )}
                    {/* Asset type badge */}
                    <Box
                      sx={{
                        position: 'absolute',
                        top: 8,
                        left: 8,
                        bgcolor: 'rgba(255,255,255,0.9)',
                        borderRadius: 1,
                        px: 0.75,
                        py: 0.25,
                        display: 'flex',
                        alignItems: 'center',
                        gap: 0.5,
                        backdropFilter: 'blur(4px)',
                      }}
                    >
                      {assetTypeIcon(asset.content_type)}
                      <Typography variant="caption" sx={{ fontSize: '0.65rem', fontWeight: 600, color: '#475569' }}>
                        {asset.content_type?.split('/')[0]?.toUpperCase() ?? 'FILE'}
                      </Typography>
                    </Box>
                  </Box>

                  <CardContent sx={{ p: 1.5, pb: '8px !important' }}>
                    <Typography
                      variant="subtitle2"
                      sx={{ fontWeight: 600, fontSize: '0.82rem', lineHeight: 1.3, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}
                    >
                      {asset.title}
                    </Typography>

                    {asset.folder_name && (
                      <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.25 }}>
                        📁 {asset.folder_name}
                      </Typography>
                    )}

                    {/* Tags */}
                    {asset.tags?.length > 0 && (
                      <Stack direction="row" spacing={0.5} sx={{ mt: 0.75, flexWrap: 'wrap', gap: 0.5 }}>
                        {asset.tags.slice(0, 3).map((tag, idx) => (
                          <Chip key={idx} label={tag} size="small" sx={{ height: 18, fontSize: '0.65rem', bgcolor: '#f1f5f9' }} />
                        ))}
                      </Stack>
                    )}

                    {/* Similarity score */}
                    <SimilarityBar score={asset.similarity_score} />
                  </CardContent>

                  <CardActions sx={{ px: 1.5, py: 1, pt: 0, gap: 0.5 }}>
                    <Tooltip title={t('copilot.viewInDam', { defaultValue: 'View in DAM' })}>
                      <IconButton
                        size="small"
                        component="a"
                        href={`/assets?id=${asset.id}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        aria-label={t('copilot.viewInDam', { defaultValue: 'View in DAM' })}
                      >
                        <OpenInNew sx={{ fontSize: 16 }} />
                      </IconButton>
                    </Tooltip>
                    <Tooltip title={t('copilot.copyUrl', { defaultValue: 'Copy URL' })}>
                      <IconButton
                        size="small"
                        onClick={() => asset.url && navigator.clipboard.writeText(asset.url)}
                        aria-label={t('copilot.copyUrl', { defaultValue: 'Copy URL' })}
                      >
                        <ContentCopy sx={{ fontSize: 16 }} />
                      </IconButton>
                    </Tooltip>
                    <Box sx={{ flexGrow: 1 }} />
                    {asset.similarity_score != null && (
                      <Chip
                        label={`${Math.round(asset.similarity_score * 100)}%`}
                        size="small"
                        sx={{ height: 18, fontSize: '0.65rem', bgcolor: '#f0fdf4', color: '#16a34a', fontWeight: 700 }}
                        aria-label={`${Math.round(asset.similarity_score * 100)}% match`}
                      />
                    )}
                  </CardActions>
                </Card>
              ))}
            </Box>
          </>
        )}
      </Box>
    </Box>
  );
}
