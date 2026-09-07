import React, { useCallback, useState } from 'react';
import {
    Alert, Box, Button, Chip, CircularProgress, Divider, IconButton, LinearProgress,
    MenuItem, Paper, Select, Stack, Tooltip, Typography,
} from '@mui/material';
import {
    AutoAwesome, CheckCircleOutlined, Close, ExpandLess, ExpandMore, Refresh,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const interpolate = (template, values = {}) => template.replace(/\{\{(\w+)\}\}/g, (_, key) => values[key] ?? '');

// The assistant's colour. Matches the stroke the server stamps on machine
// annotations, so a card and its marker on the image read as the same object.
const AI_COLOR = '#a855f7';

// Kept in step with AiReview::PROFILES. The API validates against its own
// allow-list, so an out-of-date entry here is rejected rather than run.
const PROFILES = [
    { value: 'brand_guidelines', fallback: 'Brand guidelines' },
    { value: 'accessibility', fallback: 'Accessibility' },
    { value: 'safe_area', fallback: 'Safe area' },
    { value: 'composition', fallback: 'Composition' },
];

const SHAPE_FALLBACKS = {
    pin: 'Pin', rect: 'Rectangle', ellipse: 'Ellipse', arrow: 'Arrow',
    line: 'Line', freehand: 'Freehand', text: 'Text', time: 'Timecode',
};

/**
 * The triage queue for AI-suggested findings.
 *
 * WHY EVERY FINDING NEEDS AN EXPLICIT DECISION
 * -------------------------------------------
 * A suggestion is stored as a real comment thread but withheld from every
 * listing until a human accepts it. There is deliberately no "accept all" and
 * no auto-accept: the value of the assistant is that somebody looked at each
 * claim, and a bulk button would quietly turn it into an unreviewed bot
 * posting into the client's review.
 *
 * Dismissing keeps the finding (it is the only evidence available for tuning
 * the model) rather than deleting it, so the card disappears from the queue
 * but the record does not disappear from the system.
 */
export default function AiSuggestionsPanel({ review, canModify = false }) {
    const { t } = useTranslation();
    const translate = useCallback((key, defaultValue, options = {}) => {
        const result = t(key, options);
        return result === key ? interpolate(defaultValue, options) : result;
    }, [t]);

    const [profile, setProfile] = useState('brand_guidelines');
    const [expanded, setExpanded] = useState(true);

    const {
        suggestions, latestReview, running, loading, busy, error, clearError,
        pendingCount, runReview, acceptSuggestion, dismissSuggestion,
        selectedThreadId, setSelectedThreadId, setHoveredThreadId, refresh,
    } = review;

    const failed = latestReview?.status === 'failed';
    // A completed run with nothing left to triage is a real, reportable result
    // ("we looked and found nothing"), not the same as never having run.
    const cleanRun = latestReview?.status === 'completed' && pendingCount === 0;

    return (
        <Paper
            variant="outlined"
            data-testid="ai-suggestions-panel"
            sx={{ mb: 2, borderColor: pendingCount > 0 ? AI_COLOR : '#e2e8f0', borderRadius: 2 }}
        >
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, p: 1.5 }}>
                <AutoAwesome fontSize="small" sx={{ color: AI_COLOR }} />
                <Typography variant="subtitle2" fontWeight={700} sx={{ flexGrow: 1 }}>
                    {translate('aiReview.title', 'AI review assistant')}
                </Typography>

                {pendingCount > 0 && (
                    <Chip
                        size="small"
                        label={translate('aiReview.pendingCount', '{{count}} to review', { count: pendingCount })}
                        sx={{ bgcolor: AI_COLOR, color: '#fff', fontWeight: 700 }}
                    />
                )}

                <Tooltip title={translate('aiReview.actions.refresh', 'Refresh')}>
                    <span>
                        <IconButton
                            size="small"
                            onClick={refresh}
                            disabled={loading || busy}
                            aria-label={translate('aiReview.actions.refresh', 'Refresh')}
                        >
                            <Refresh fontSize="small" />
                        </IconButton>
                    </span>
                </Tooltip>

                <IconButton
                    size="small"
                    onClick={() => setExpanded((v) => !v)}
                    aria-label={expanded
                        ? translate('aiReview.actions.collapse', 'Collapse')
                        : translate('aiReview.actions.expand', 'Expand')}
                >
                    {expanded ? <ExpandLess fontSize="small" /> : <ExpandMore fontSize="small" />}
                </IconButton>
            </Box>

            {running && <LinearProgress sx={{ '& .MuiLinearProgress-bar': { bgcolor: AI_COLOR } }} />}

            {expanded && (
                <>
                    <Divider />
                    <Box sx={{ p: 1.5 }}>
                        {error && (
                            <Alert severity="error" onClose={clearError} sx={{ mb: 1.5 }}>{error}</Alert>
                        )}

                        {canModify && (
                            <Stack direction="row" spacing={1} sx={{ mb: 1.5 }}>
                                <Select
                                    size="small"
                                    value={profile}
                                    onChange={(e) => setProfile(e.target.value)}
                                    disabled={running || busy}
                                    sx={{ flexGrow: 1 }}
                                    inputProps={{ 'aria-label': translate('aiReview.profileLabel', 'Review profile') }}
                                >
                                    {PROFILES.map((p) => (
                                        <MenuItem key={p.value} value={p.value}>
                                            {translate(`aiReview.profiles.${p.value}`, p.fallback)}
                                        </MenuItem>
                                    ))}
                                </Select>
                                <Button
                                    variant="contained"
                                    size="small"
                                    disableElevation
                                    onClick={() => runReview(profile)}
                                    disabled={running || busy}
                                    startIcon={running
                                        ? <CircularProgress size={14} color="inherit" />
                                        : <AutoAwesome fontSize="small" />}
                                    sx={{ bgcolor: AI_COLOR, whiteSpace: 'nowrap', '&:hover': { bgcolor: '#9333ea' } }}
                                >
                                    {running
                                        ? translate('aiReview.actions.running', 'Reviewing…')
                                        : translate('aiReview.actions.run', 'Run review')}
                                </Button>
                            </Stack>
                        )}

                        {failed && (
                            <Alert severity="warning" sx={{ mb: 1.5 }}>
                                {latestReview.error_message
                                    || translate('aiReview.failed', 'The review could not be completed.')}
                            </Alert>
                        )}

                        {cleanRun && (
                            <Stack direction="row" spacing={1} sx={{ alignItems: 'center', py: 1 }}>
                                <CheckCircleOutlined fontSize="small" color="success" />
                                <Typography variant="body2" color="textSecondary">
                                    {translate('aiReview.noFindings', 'No issues found in the last review.')}
                                </Typography>
                            </Stack>
                        )}

                        {!latestReview && !loading && (
                            <Typography variant="body2" color="textSecondary" sx={{ py: 1 }}>
                                {canModify
                                    ? translate('aiReview.empty', 'Run a review to have the assistant check this asset.')
                                    : translate('aiReview.emptyReadOnly', 'No AI review has been run for this asset.')}
                            </Typography>
                        )}

                        <Stack spacing={1}>
                            {suggestions.map((thread) => (
                                <SuggestionCard
                                    key={thread.id}
                                    thread={thread}
                                    translate={translate}
                                    canModify={canModify}
                                    busy={busy}
                                    selected={selectedThreadId === thread.id}
                                    onSelect={() => setSelectedThreadId(thread.id)}
                                    onHover={setHoveredThreadId}
                                    onAccept={() => acceptSuggestion(thread.id)}
                                    onDismiss={() => dismissSuggestion(thread.id)}
                                />
                            ))}
                        </Stack>

                        {latestReview?.model_name && (
                            <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 1.5 }}>
                                {translate('aiReview.modelCredit', 'Suggested by {{model}}', {
                                    model: latestReview.model_name,
                                })}
                            </Typography>
                        )}
                    </Box>
                </>
            )}
        </Paper>
    );
}

function SuggestionCard({
    thread, translate, canModify, busy, selected, onSelect, onHover, onAccept, onDismiss,
}) {
    const comment = (thread.comments || [])[0] || {};
    const annotations = comment.annotations || [];
    const confidence = comment.confidence;

    return (
        <Paper
            variant="outlined"
            data-testid="ai-suggestion-card"
            onClick={onSelect}
            onMouseEnter={() => onHover(thread.id)}
            onMouseLeave={() => onHover(null)}
            sx={{
                p: 1.25,
                cursor: 'pointer',
                borderColor: selected ? AI_COLOR : '#e2e8f0',
                borderWidth: selected ? 2 : 1,
                bgcolor: selected ? 'rgba(168,85,247,0.06)' : 'transparent',
            }}
        >
            <Typography variant="body2" sx={{ mb: 0.75, whiteSpace: 'pre-wrap' }}>
                {comment.body}
            </Typography>

            <Stack
                direction="row"
                spacing={0.5}
                useFlexGap
                sx={{ flexWrap: 'wrap', mb: canModify ? 1 : 0 }}
            >
                {annotations.map((annotation) => (
                    <Chip
                        key={annotation.id}
                        size="small"
                        variant="outlined"
                        label={translate(`assetComments.tools.${annotation.shape}`,
                            SHAPE_FALLBACKS[annotation.shape] || annotation.shape)}
                    />
                ))}
                {confidence != null && (
                    <Chip
                        size="small"
                        variant="outlined"
                        label={translate('aiReview.confidence', '{{percent}}% confident', {
                            percent: Math.round(confidence * 100),
                        })}
                        sx={{ borderColor: AI_COLOR, color: AI_COLOR }}
                    />
                )}
            </Stack>

            {canModify && (
                <Stack direction="row" spacing={1}>
                    <Button
                        size="small"
                        variant="contained"
                        disableElevation
                        disabled={busy}
                        startIcon={<CheckCircleOutlined fontSize="small" />}
                        onClick={(e) => { e.stopPropagation(); onAccept(); }}
                        sx={{ bgcolor: AI_COLOR, '&:hover': { bgcolor: '#9333ea' } }}
                    >
                        {translate('aiReview.actions.accept', 'Accept')}
                    </Button>
                    <Button
                        size="small"
                        color="inherit"
                        disabled={busy}
                        startIcon={<Close fontSize="small" />}
                        onClick={(e) => { e.stopPropagation(); onDismiss(); }}
                    >
                        {translate('aiReview.actions.dismiss', 'Dismiss')}
                    </Button>
                </Stack>
            )}
        </Paper>
    );
}
