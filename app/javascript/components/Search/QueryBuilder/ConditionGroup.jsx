import React from 'react';
import { useTranslation } from 'react-i18next';
import {
    Box, Stack, Button, ToggleButton, ToggleButtonGroup, Typography, Tooltip, IconButton,
} from '@mui/material';
import { AddOutlined, DeleteOutlined } from '@mui/icons-material';
import ConditionRow from './ConditionRow';
import { isGroup, newCondition, newGroup } from './queryTree';

/**
 * A group of conditions joined by AND, OR, or NOT — rendered recursively, since
 * the structure it represents is recursive and any flattened rendering would
 * have to reinvent nesting with indentation anyway.
 *
 * The left border and indent are load-bearing rather than decorative: with
 * nested boolean logic, "which group does this condition belong to" is the one
 * question the user must be able to answer at a glance, and operator precedence
 * is otherwise invisible.
 */
export default function ConditionGroup({
    node, fields, fieldsByName, onChange, onRemove, depth = 0, maxDepth, atNodeLimit,
}) {
    const { t } = useTranslation();

    // NOT holds exactly one child — the server refuses any other shape rather
    // than guessing between "not all of these" and "none of these".
    const isNot = node.op === 'not';
    const canNest = depth + 1 < maxDepth;

    const replaceChild = (child) => onChange({
        ...node,
        children: node.children.map((c) => (c.id === child.id ? child : c)),
    });

    const removeChild = (id) => onChange({
        ...node,
        children: node.children.filter((c) => c.id !== id),
    });

    const append = (child) => onChange({ ...node, children: [ ...node.children, child ] });

    const changeOp = (op) => {
        if (!op || op === node.op) return;
        // Switching to NOT discards all but the first condition, because NOT
        // cannot hold more than one. Doing it silently would lose the user's
        // work without saying so, so the button is disabled instead when it
        // would destroy something — see `disableNot` below.
        onChange({ ...node, op, children: op === 'not' ? node.children.slice(0, 1) : node.children });
    };

    const disableNot = node.children.length > 1;

    return (
        <Box
            data-testid="condition-group"
            sx={{
                borderLeft: depth > 0 ? 2 : 0,
                borderColor: node.op === 'or' ? 'secondary.main' : 'primary.main',
                pl: depth > 0 ? 2 : 0,
                py: depth > 0 ? 1 : 0,
            }}
        >
            <Stack direction="row" spacing={1} sx={{ alignItems: 'center', mb: 1 }}>
                <ToggleButtonGroup
                    size="small"
                    exclusive
                    value={node.op}
                    onChange={(_e, op) => changeOp(op)}
                    aria-label={t('queryBuilder.groupOperator')}
                >
                    <ToggleButton value="and" aria-label={t('queryBuilder.ops.and')}>
                        {t('queryBuilder.ops.and')}
                    </ToggleButton>
                    <ToggleButton value="or" aria-label={t('queryBuilder.ops.or')}>
                        {t('queryBuilder.ops.or')}
                    </ToggleButton>
                    <ToggleButton value="not" aria-label={t('queryBuilder.ops.not')} disabled={disableNot}>
                        {t('queryBuilder.ops.not')}
                    </ToggleButton>
                </ToggleButtonGroup>

                {isNot && (
                    <Typography variant="caption" color="text.secondary">
                        {t('queryBuilder.notHint')}
                    </Typography>
                )}

                <Box sx={{ flexGrow: 1 }} />

                {onRemove && (
                    <Tooltip title={t('queryBuilder.removeGroup')}>
                        <IconButton size="small" aria-label={t('queryBuilder.removeGroup')} onClick={onRemove}>
                            <DeleteOutlined fontSize="small" />
                        </IconButton>
                    </Tooltip>
                )}
            </Stack>

            <Stack spacing={1}>
                {node.children.map((child) => (
                    isGroup(child) ? (
                        <ConditionGroup
                            key={child.id}
                            node={child}
                            fields={fields}
                            fieldsByName={fieldsByName}
                            onChange={replaceChild}
                            onRemove={() => removeChild(child.id)}
                            depth={depth + 1}
                            maxDepth={maxDepth}
                            atNodeLimit={atNodeLimit}
                        />
                    ) : (
                        <ConditionRow
                            key={child.id}
                            node={child}
                            fields={fields}
                            fieldsByName={fieldsByName}
                            onChange={replaceChild}
                            onRemove={() => removeChild(child.id)}
                            disableRemove={depth === 0 && node.children.length === 1}
                        />
                    )
                ))}
            </Stack>

            {!isNot && (
                <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
                    <Button
                        size="small"
                        startIcon={<AddOutlined />}
                        onClick={() => append(newCondition())}
                        disabled={atNodeLimit}
                    >
                        {t('queryBuilder.addCondition')}
                    </Button>
                    <Tooltip title={canNest ? '' : t('queryBuilder.maxDepthReached')}>
                        <span>
                            <Button
                                size="small"
                                startIcon={<AddOutlined />}
                                onClick={() => append(newGroup())}
                                disabled={!canNest || atNodeLimit}
                            >
                                {t('queryBuilder.addGroup')}
                            </Button>
                        </span>
                    </Tooltip>
                </Stack>
            )}
        </Box>
    );
}
