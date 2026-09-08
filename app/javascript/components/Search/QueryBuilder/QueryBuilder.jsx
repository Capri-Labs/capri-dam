import React, { useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Box, Paper, Stack, Button, Typography, Alert, CircularProgress, Chip, Divider,
} from '@mui/material';
import ConditionGroup from './ConditionGroup';
import useQueryFields from './useQueryFields';
import useQueryCount from './useQueryCount';
import { newGroup, deserialize, serialize, countNodes } from './queryTree';

/**
 * Graphical builder for the nested boolean query AST.
 *
 * The tree it edits round-trips: an AST loaded from the server is rendered back
 * into the same shape it was built from, so a saved query can be reopened and
 * edited rather than only re-run. That property is what makes the builder worth
 * having over a text query language — and it is enforced by the pure functions
 * in `queryTree.js` rather than by the components, which is why it can be tested
 * directly.
 */
export default function QueryBuilder({ initialAst = null, onApply, onClear, applying = false }) {
    const { t } = useTranslation();
    const { fields, fieldsByName, limits, loading, error } = useQueryFields();
    const [tree, setTree] = useState(() => (initialAst ? deserialize(initialAst) : newGroup()));

    const ast = useMemo(() => serialize(tree), [tree]);
    const nodeCount = countNodes(tree);
    const atNodeLimit = nodeCount >= limits.max_nodes;

    const { count, loading: counting, error: countError } = useQueryCount(ast, { enabled: !loading });

    const reset = () => {
        setTree(newGroup());
        if (onClear) onClear();
    };

    if (loading) {
        return (
            <Paper variant="outlined" sx={{ p: 2 }} data-testid="query-builder-loading">
                <CircularProgress size={20} />
            </Paper>
        );
    }

    if (error) {
        return (
            <Paper variant="outlined" sx={{ p: 2 }} data-testid="query-builder-error-state">
                <Alert severity="error">{t('queryBuilder.fieldsUnavailable')}</Alert>
            </Paper>
        );
    }

    return (
        <Paper variant="outlined" sx={{ p: 2 }} data-testid="query-builder">
            <Stack direction="row" sx={{ alignItems: 'center', justifyContent: 'space-between', mb: 1 }}>
                <Typography variant="subtitle2" fontWeight="700">
                    {t('queryBuilder.title')}
                </Typography>
                {/* The count is the feedback loop: without it a user cannot tell
                    an over-narrow query from a correct one until they run it. */}
                <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                    {counting && <CircularProgress size={14} />}
                    {!counting && countError && (
                        <Chip size="small" color="warning" label={t('queryBuilder.countUnavailable')} />
                    )}
                    {!counting && !countError && count != null && (
                        <Chip
                            size="small"
                            data-testid="query-builder-count"
                            label={t('queryBuilder.matchCount', { count })}
                        />
                    )}
                </Stack>
            </Stack>

            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                {t('queryBuilder.description')}
            </Typography>

            <ConditionGroup
                node={tree}
                fields={fields}
                fieldsByName={fieldsByName}
                onChange={setTree}
                depth={0}
                maxDepth={limits.max_depth}
                atNodeLimit={atNodeLimit}
            />

            {atNodeLimit && (
                <Alert severity="info" sx={{ mt: 2 }}>
                    {t('queryBuilder.maxNodesReached', { count: limits.max_nodes })}
                </Alert>
            )}

            {countError && (
                <Alert severity="warning" sx={{ mt: 2 }} data-testid="query-builder-error">
                    {countError}
                </Alert>
            )}

            <Divider sx={{ my: 2 }} />

            <Stack direction="row" spacing={1}>
                <Button
                    variant="contained"
                    size="small"
                    disabled={!ast || applying}
                    onClick={() => onApply && onApply(ast)}
                >
                    {t('queryBuilder.apply')}
                </Button>
                <Button size="small" onClick={reset}>
                    {t('queryBuilder.clear')}
                </Button>
                <Box sx={{ flexGrow: 1 }} />
                <Typography variant="caption" color="text.secondary" sx={{ alignSelf: 'center' }}>
                    {t('queryBuilder.nodeCount', { count: nodeCount, max: limits.max_nodes })}
                </Typography>
            </Stack>
        </Paper>
    );
}
