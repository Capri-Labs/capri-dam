/**
 * Pure operations on the query tree the builder edits.
 *
 * The builder's working tree is *not* the wire AST: every node carries a client
 * `id` so React has a stable key across reorders, and a leaf may be
 * half-finished while the user is still filling it in. {@link serialize} is the
 * boundary between the two — nothing else in the UI should construct wire JSON.
 *
 * Keeping this file free of React is what makes the round-trip property
 * (deserialize → serialize is the identity on any valid AST) testable directly
 * rather than through rendered output.
 */

export const GROUP_OPS = [ 'and', 'or', 'not' ];

let counter = 0;
const nextId = () => `n${++counter}`;

export const isGroup = (node) => Boolean(node) && typeof node.op === 'string';

export function newCondition(field = '', operator = '', value = '') {
    return { id: nextId(), field, operator, value };
}

export function newGroup(op = 'and', children = null) {
    return { id: nextId(), op, children: children || [ newCondition() ] };
}

/** Operators that take no operand at all — the value input is hidden for these. */
export const NULLARY_OPERATORS = [ 'present', 'blank' ];

/** Operators whose operand is a list rather than a single value. */
export const LIST_OPERATORS = [ 'in', 'not_in', 'has_any', 'has_all', 'none_of' ];

/** Operators whose operand is a pair. */
export const RANGE_OPERATORS = [ 'between' ];

export function operatorArity(operator) {
    if (NULLARY_OPERATORS.includes(operator)) return 'none';
    if (LIST_OPERATORS.includes(operator)) return 'list';
    if (RANGE_OPERATORS.includes(operator)) return 'range';
    return 'single';
}

/**
 * Replaces the node with the given id, in place in the tree shape but returning
 * new objects along the changed path so React sees a new reference exactly where
 * something changed and nowhere else.
 */
export function updateNode(node, id, updater) {
    if (node.id === id) return updater(node);
    if (!isGroup(node)) return node;

    let changed = false;
    const children = node.children.map((child) => {
        const next = updateNode(child, id, updater);
        if (next !== child) changed = true;
        return next;
    });
    return changed ? { ...node, children } : node;
}

export function removeNode(node, id) {
    if (!isGroup(node)) return node;

    const kept = node.children.filter((child) => child.id !== id);
    const children = kept.map((child) => removeNode(child, id));
    if (kept.length === node.children.length
        && children.every((child, i) => child === node.children[i])) {
        return node;
    }
    return { ...node, children };
}

export function addToGroup(node, groupId, child) {
    return updateNode(node, groupId, (group) => ({
        ...group, children: [ ...group.children, child ],
    }));
}

/** Total node count, so the UI can stop a user before the server has to. */
export function countNodes(node) {
    if (!isGroup(node)) return 1;
    return 1 + node.children.reduce((sum, child) => sum + countNodes(child), 0);
}

export function maxDepth(node, depth = 0) {
    if (!isGroup(node) || node.children.length === 0) return depth;
    return Math.max(...node.children.map((child) => maxDepth(child, depth + 1)));
}

/**
 * Converts the working tree into the wire AST.
 *
 * A condition with no field chosen yet is omitted rather than sent. A freshly
 * added row is always in that state, and sending it would make the live count
 * fail with a validation error every single time a user clicks "Add condition"
 * — which would read as the builder being broken rather than incomplete.
 *
 * Returns null when nothing survives, which callers treat as "no constraint".
 */
export function serialize(node) {
    if (!isGroup(node)) {
        if (!node.field || !node.operator) return null;

        const arity = operatorArity(node.operator);
        if (arity === 'none') return { field: node.field, operator: node.operator };
        if (arity === 'list') {
            const values = toList(node.value);
            return values.length ? { field: node.field, operator: node.operator, value: values } : null;
        }
        if (arity === 'range') {
            const [ from, to ] = Array.isArray(node.value) ? node.value : [ '', '' ];
            if (from === '' || to === '' || from == null || to == null) return null;
            return { field: node.field, operator: node.operator, value: [ from, to ] };
        }
        if (node.value === '' || node.value == null) return null;
        return { field: node.field, operator: node.operator, value: node.value };
    }

    const children = node.children.map(serialize).filter(Boolean);
    if (children.length === 0) return null;
    // A NOT that has lost all but one meaningful child is still a NOT of one;
    // the server requires exactly one child, so an incomplete second condition
    // must not turn a valid query into a rejected one.
    if (node.op === 'not') return { op: 'not', children: [ children[0] ] };
    return { op: node.op, children };
}

/** Converts a wire AST back into a working tree, assigning fresh client ids. */
export function deserialize(ast) {
    if (!ast) return newGroup();

    if (ast.op) {
        return {
            id: nextId(),
            op: ast.op,
            children: (ast.children || []).map(deserialize),
        };
    }
    const arity = operatorArity(ast.operator);
    let value = ast.value;
    if (arity === 'none') value = '';
    else if (value === undefined) value = '';

    return { id: nextId(), field: ast.field || '', operator: ast.operator || '', value };
}

export function toList(value) {
    if (Array.isArray(value)) return value.map((v) => String(v).trim()).filter(Boolean);
    return String(value ?? '').split(',').map((v) => v.trim()).filter(Boolean);
}
