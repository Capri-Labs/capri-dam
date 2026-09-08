import React from 'react';
import { useTranslation } from 'react-i18next';
import {
    Stack, TextField, MenuItem, IconButton, Tooltip, Autocomplete, Chip,
} from '@mui/material';
import { DeleteOutlined } from '@mui/icons-material';
import { operatorArity, toList } from './queryTree';

/**
 * One leaf of the query: field, operator, and whatever operand that operator
 * needs.
 *
 * The operator list comes from the field definition rather than a fixed set,
 * because the operators that make sense are a property of the type: `contains`
 * is meaningless on a date, and `has_all` is meaningless on anything that is not
 * a list. Offering all of them and rejecting most server-side would teach the
 * user nothing until after they had already built the query.
 */
export default function ConditionRow({ node, fields, fieldsByName, onChange, onRemove, disableRemove }) {
    const { t } = useTranslation();
    const definition = fieldsByName[node.field];
    const operators = definition?.operators || [];
    const arity = operatorArity(node.operator);

    const handleFieldChange = (name) => {
        const next = fieldsByName[name];
        // Changing the field can invalidate the operator — `contains` does not
        // survive a move from title to created_at. Keeping it would leave a row
        // that looks complete and is rejected on submit, so it is reset to the
        // new type's first operator instead.
        const keepOperator = next?.operators?.includes(node.operator);
        onChange({
            ...node,
            field: name,
            operator: keepOperator ? node.operator : (next?.operators?.[0] || ''),
            value: keepOperator ? node.value : '',
        });
    };

    const handleOperatorChange = (operator) => {
        const wasArity = operatorArity(node.operator);
        const nowArity = operatorArity(operator);
        onChange({
            ...node,
            operator,
            value: wasArity === nowArity ? node.value : defaultValueFor(nowArity),
        });
    };

    return (
        <Stack direction="row" spacing={1} sx={{ alignItems: 'flex-start' }} data-testid="condition-row">
            <TextField
                select
                size="small"
                label={t('queryBuilder.field')}
                value={node.field}
                onChange={(e) => handleFieldChange(e.target.value)}
                sx={{ minWidth: 180 }}
            >
                {fields.map((f) => (
                    <MenuItem key={f.name} value={f.name}>{f.label}</MenuItem>
                ))}
            </TextField>

            <TextField
                select
                size="small"
                label={t('queryBuilder.operator')}
                value={operators.includes(node.operator) ? node.operator : ''}
                onChange={(e) => handleOperatorChange(e.target.value)}
                disabled={!definition}
                sx={{ minWidth: 160 }}
            >
                {operators.map((op) => (
                    <MenuItem key={op} value={op}>{t(`queryBuilder.operators.${op}`)}</MenuItem>
                ))}
            </TextField>

            <ValueInput
                node={node}
                definition={definition}
                arity={arity}
                onChange={onChange}
                label={t('queryBuilder.value')}
            />

            <Tooltip title={t('queryBuilder.removeCondition')}>
                <span>
                    <IconButton
                        size="small"
                        aria-label={t('queryBuilder.removeCondition')}
                        onClick={onRemove}
                        disabled={disableRemove}
                    >
                        <DeleteOutlined fontSize="small" />
                    </IconButton>
                </span>
            </Tooltip>
        </Stack>
    );
}

function defaultValueFor(arity) {
    if (arity === 'range') return [ '', '' ];
    if (arity === 'list') return [];
    return '';
}

function ValueInput({ node, definition, arity, onChange, label }) {
    const { t } = useTranslation();

    // `present`/`blank` ask about the absence of a value, so rendering a value
    // box would invite the user to type something that is then ignored.
    if (arity === 'none') return null;

    if (arity === 'range') {
        const [ from, to ] = Array.isArray(node.value) ? node.value : [ '', '' ];
        const type = definition?.type === 'datetime' ? 'date' : 'number';
        return (
            <Stack direction="row" spacing={1}>
                <TextField
                    size="small" type={type} label={t('queryBuilder.from')}
                    InputLabelProps={{ shrink: true }}
                    value={from}
                    onChange={(e) => onChange({ ...node, value: [ e.target.value, to ] })}
                    sx={{ width: 150 }}
                />
                <TextField
                    size="small" type={type} label={t('queryBuilder.to')}
                    InputLabelProps={{ shrink: true }}
                    value={to}
                    onChange={(e) => onChange({ ...node, value: [ from, e.target.value ] })}
                    sx={{ width: 150 }}
                />
            </Stack>
        );
    }

    if (arity === 'list') {
        return (
            <Autocomplete
                multiple
                freeSolo
                size="small"
                options={definition?.values || []}
                value={toList(node.value)}
                onChange={(_e, values) => onChange({ ...node, value: values })}
                renderTags={(values, getTagProps) => values.map((value, index) => (
                    <Chip size="small" label={value} {...getTagProps({ index })} key={value} />
                ))}
                renderInput={(params) => (
                    <TextField {...params} label={label} placeholder={t('queryBuilder.addValue')} />
                )}
                sx={{ minWidth: 240 }}
            />
        );
    }

    // A closed option set is a pick-list, not a text box: typing "aproved" into
    // a status filter returns nothing and gives no hint why.
    if (definition?.values?.length) {
        return (
            <TextField
                select size="small" label={label} value={node.value ?? ''}
                onChange={(e) => onChange({ ...node, value: e.target.value })}
                sx={{ minWidth: 180 }}
            >
                {definition.values.map((v) => (
                    <MenuItem key={v} value={v}>{v}</MenuItem>
                ))}
            </TextField>
        );
    }

    const type = definition?.type === 'number' ? 'number'
        : definition?.type === 'datetime' ? 'date' : 'text';

    return (
        <TextField
            size="small"
            type={type}
            label={label}
            InputLabelProps={type === 'date' ? { shrink: true } : undefined}
            value={node.value ?? ''}
            onChange={(e) => onChange({ ...node, value: e.target.value })}
            sx={{ minWidth: 200 }}
        />
    );
}
