import React from 'react';
import { useTranslation } from 'react-i18next';
import {
    Box, Typography, Button, Chip, Stack, Alert, CircularProgress,
    IconButton, Tooltip, LinearProgress,
} from '@mui/material';
import { CheckCircleOutlined, CancelOutlined, AutoAwesome } from '@mui/icons-material';
import useAiTagSuggestions from './useAiTagSuggestions';

/** Below this a suggestion is shown as low-confidence rather than hidden. */
const LOW_CONFIDENCE = 0.7;

/**
 * The triage queue for machine-proposed tags.
 *
 * Every label here is a proposal, never a fact. Accepting is the only action
 * that writes into the asset's tags; dismissing records a judgement so the same
 * label is not offered again on the next run.
 *
 * Confidence is shown rather than hidden because the decision it informs is the
 * user's, not ours: a 0.58 "vintage" is worth a glance from someone who knows
 * the collection, even though it would be wrong to apply it automatically.
 */
export default function AiTagSuggestionsPanel({ asset, canModify = true, onTagsChanged }) {
    const { t } = useTranslation();
    const {
        suggestions, latestRun, loading, requesting, error, setError,
        requestRun, accept, dismiss,
    } = useAiTagSuggestions({ assetId: asset?.id, enabled: Boolean(asset?.id) });

    const running = latestRun && [ 'queued', 'running' ].includes(latestRun.status);

    return (
        <Box data-testid="ai-tag-suggestions-panel">
            <Stack direction="row" sx={{ alignItems: 'center', justifyContent: 'space-between', mb: 1 }}>
                <Typography variant="subtitle2" fontWeight="700">
                    {t('aiTagging.title')}
                </Typography>
                {canModify && (
                    <Button
                        size="small"
                        variant="outlined"
                        startIcon={requesting ? <CircularProgress size={14} /> : <AutoAwesome />}
                        disabled={requesting || running}
                        onClick={() => requestRun()}
                    >
                        {t('aiTagging.action.suggest')}
                    </Button>
                )}
            </Stack>

            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                {t('aiTagging.description')}
            </Typography>

            {error && (
                <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>
                    {error}
                </Alert>
            )}

            {/* A queued run is invisible work; without this the button looks broken. */}
            {running && (
                <Box sx={{ mb: 2 }}>
                    <Typography variant="caption" color="text.secondary">
                        {t('aiTagging.status.running')}
                    </Typography>
                    <LinearProgress sx={{ mt: 0.5 }} />
                </Box>
            )}

            {/* A failed run must be visible, or it looks identical to a model
                that simply found nothing to say. */}
            {latestRun?.status === 'failed' && (
                <Alert severity="warning" sx={{ mb: 2 }}>
                    {t('aiTagging.status.failed', { message: latestRun.error_message || '' })}
                </Alert>
            )}

            {loading && <CircularProgress size={20} />}

            {!loading && suggestions.length === 0 && !running && (
                <Typography variant="body2" color="text.secondary">
                    {t('aiTagging.empty')}
                </Typography>
            )}

            {!loading && suggestions.length > 0 && (
                <Stack spacing={1}>
                    {suggestions.map((s) => (
                        <Stack
                            key={s.id}
                            direction="row"
                            spacing={1}
                            sx={{ alignItems: 'center', border: 1, borderColor: 'divider', borderRadius: 1, px: 1, py: 0.5 }}
                        >
                            <Chip size="small" label={s.label} />
                            {s.confidence != null && (
                                <Typography
                                    variant="caption"
                                    color={s.confidence < LOW_CONFIDENCE ? 'warning.main' : 'text.secondary'}
                                >
                                    {`${Math.round(s.confidence * 100)}%`}
                                </Typography>
                            )}
                            <Box sx={{ flexGrow: 1 }} />
                            {canModify && (
                                <>
                                    <Tooltip title={t('aiTagging.action.accept')}>
                                        <IconButton
                                            size="small"
                                            color="success"
                                            aria-label={t('aiTagging.action.accept')}
                                            onClick={async () => {
                                                const result = await accept(s.id);
                                                // Accepting mutates the asset's tags, so the
                                                // rest of the viewer is now stale.
                                                if (result && onTagsChanged) onTagsChanged();
                                            }}
                                        >
                                            <CheckCircleOutlined fontSize="small" />
                                        </IconButton>
                                    </Tooltip>
                                    <Tooltip title={t('aiTagging.action.dismiss')}>
                                        <IconButton
                                            size="small"
                                            color="error"
                                            aria-label={t('aiTagging.action.dismiss')}
                                            onClick={() => dismiss(s.id)}
                                        >
                                            <CancelOutlined fontSize="small" />
                                        </IconButton>
                                    </Tooltip>
                                </>
                            )}
                        </Stack>
                    ))}
                </Stack>
            )}
        </Box>
    );
}
