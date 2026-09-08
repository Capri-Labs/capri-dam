import {
    newGroup, newCondition, isGroup, serialize, deserialize,
    updateNode, removeNode, addToGroup, countNodes, maxDepth,
    operatorArity, toList,
} from '../../../../../app/javascript/components/Search/QueryBuilder/queryTree';

/** Strips client ids so two working trees can be compared structurally. */
const shape = (node) => {
    if (isGroup(node)) return { op: node.op, children: node.children.map(shape) };
    return { field: node.field, operator: node.operator, value: node.value };
};

describe('queryTree', () => {
    describe('round-tripping', () => {
        it('renders a server AST back into the same tree it was built from', () => {
            const ast = {
                op: 'and',
                children: [
                    { field: 'title', operator: 'contains', value: 'sunset' },
                    {
                        op: 'or',
                        children: [
                            { field: 'status', operator: 'eq', value: 'approved' },
                            { field: 'file_size', operator: 'between', value: [ 100, 500 ] },
                        ],
                    },
                    { op: 'not', children: [ { field: 'tags', operator: 'has_any', value: [ 'draft' ] } ] },
                ],
            };

            expect(serialize(deserialize(ast))).toEqual(ast);
        });

        it('round-trips a nullary operator without inventing a value', () => {
            const ast = { field: 'alt_text', operator: 'blank' };
            expect(serialize(deserialize(ast))).toEqual(ast);
        });

        it('gives every deserialized node a distinct id so React keys are stable', () => {
            const tree = deserialize({
                op: 'and',
                children: [
                    { field: 'title', operator: 'eq', value: 'a' },
                    { field: 'title', operator: 'eq', value: 'b' },
                ],
            });
            const ids = [ tree.id, ...tree.children.map((c) => c.id) ];
            expect(new Set(ids).size).toBe(3);
        });

        it('starts from an empty group when there is no AST to load', () => {
            expect(shape(deserialize(null))).toEqual({
                op: 'and',
                children: [ { field: '', operator: '', value: '' } ],
            });
        });
    });

    describe('serialize', () => {
        it('omits a condition with no field chosen yet', () => {
            // A freshly added row is always in this state; sending it would make
            // the live count fail on every click of "Add condition".
            const tree = newGroup('and', [
                newCondition('title', 'eq', 'x'),
                newCondition(),
            ]);
            expect(serialize(tree)).toEqual({
                op: 'and', children: [ { field: 'title', operator: 'eq', value: 'x' } ],
            });
        });

        it('returns null when nothing in the tree is usable', () => {
            expect(serialize(newGroup())).toBeNull();
        });

        it('omits a condition whose value is still empty', () => {
            expect(serialize(newGroup('and', [ newCondition('title', 'eq', '') ]))).toBeNull();
        });

        it('keeps a nullary condition even though it has no value', () => {
            expect(serialize(newCondition('title', 'blank', ''))).toEqual({
                field: 'title', operator: 'blank',
            });
        });

        it('drops a range whose second bound is missing rather than sending half of it', () => {
            expect(serialize(newCondition('file_size', 'between', [ 5, '' ]))).toBeNull();
        });

        it('splits a comma-separated string into a list for list operators', () => {
            expect(serialize(newCondition('tags', 'has_any', 'red, blue ,green'))).toEqual({
                field: 'tags', operator: 'has_any', value: [ 'red', 'blue', 'green' ],
            });
        });

        it('never emits a NOT with more than one child, which the server refuses', () => {
            const tree = {
                id: 'x', op: 'not', children: [
                    newCondition('title', 'eq', 'a'),
                    newCondition('title', 'eq', 'b'),
                ],
            };
            expect(serialize(tree).children).toHaveLength(1);
        });
    });

    describe('tree editing', () => {
        it('returns a new reference only along the changed path', () => {
            const child = newCondition('title', 'eq', 'a');
            const sibling = newCondition('title', 'eq', 'b');
            const tree = newGroup('and', [ child, sibling ]);

            const next = updateNode(tree, child.id, (n) => ({ ...n, value: 'z' }));

            expect(next).not.toBe(tree);
            expect(next.children[0].value).toBe('z');
            expect(next.children[1]).toBe(sibling);
        });

        it('leaves the tree untouched when the id is not present', () => {
            const tree = newGroup();
            expect(updateNode(tree, 'missing', (n) => n)).toBe(tree);
        });

        it('removes a node at any depth', () => {
            const deep = newCondition('title', 'eq', 'a');
            const tree = newGroup('and', [ newGroup('or', [ deep ]) ]);

            expect(removeNode(tree, deep.id).children[0].children).toHaveLength(0);
        });

        it('appends to a nested group', () => {
            const inner = newGroup('or', []);
            const tree = newGroup('and', [ inner ]);
            const added = newCondition('title', 'eq', 'a');

            const next = addToGroup(tree, inner.id, added);
            expect(next.children[0].children).toEqual([ added ]);
        });
    });

    describe('limits', () => {
        it('counts every node including groups', () => {
            const tree = newGroup('and', [ newCondition(), newGroup('or', [ newCondition() ]) ]);
            expect(countNodes(tree)).toBe(4);
        });

        it('measures nesting depth', () => {
            const tree = newGroup('and', [ newGroup('or', [ newGroup('and', [ newCondition() ]) ]) ]);
            expect(maxDepth(tree)).toBe(3);
        });
    });

    describe('operatorArity', () => {
        it.each([
            [ 'present', 'none' ],
            [ 'blank', 'none' ],
            [ 'in', 'list' ],
            [ 'has_all', 'list' ],
            [ 'between', 'range' ],
            [ 'contains', 'single' ],
        ])('classifies %s as %s', (operator, arity) => {
            expect(operatorArity(operator)).toBe(arity);
        });
    });

    describe('toList', () => {
        it('trims and drops blanks', () => {
            expect(toList(' a , , b ')).toEqual([ 'a', 'b' ]);
        });

        it('passes an array through', () => {
            expect(toList([ 'a', ' b ' ])).toEqual([ 'a', 'b' ]);
        });

        it('treats null as empty', () => {
            expect(toList(null)).toEqual([]);
        });
    });
});
