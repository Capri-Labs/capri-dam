import React from 'react';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import i18n from 'i18next';
import en from '../../../../../app/javascript/i18n/locales/en.json';
import QueryBuilder from '../../../../../app/javascript/components/Search/QueryBuilder/QueryBuilder';

i18n.addResourceBundle('en', 'translation', en, true, true);

const FIELDS = [
    {
        name: 'title', label: 'Title', type: 'string', group: 'core',
        operators: [ 'eq', 'contains', 'in', 'present', 'blank' ],
    },
    {
        name: 'status', label: 'Status', type: 'enum', group: 'core',
        operators: [ 'eq', 'in' ], values: [ 'draft', 'approved' ],
    },
    {
        name: 'file_size', label: 'File size', type: 'number', group: 'file',
        operators: [ 'gt', 'between' ],
    },
    {
        name: 'created_at', label: 'Created at', type: 'datetime', group: 'core',
        operators: [ 'before', 'after' ],
    },
];

const LIMITS = { max_depth: 3, max_nodes: 6, max_list_values: 50 };

let countCalls;

function mockFetch({ count = 42, countStatus = 200, countBody = null, fieldsOk = true } = {}) {
    countCalls = [];
    global.fetch = jest.fn((url, opts = {}) => {
        if (url === '/api/v1/search/fields') {
            if (!fieldsOk) return Promise.resolve({ ok: false, status: 500, json: async () => ({}) });
            return Promise.resolve({ ok: true, json: async () => ({ fields: FIELDS, limits: LIMITS }) });
        }
        if (url === '/api/v1/search/count') {
            countCalls.push(JSON.parse(opts.body));
            return Promise.resolve({
                ok: countStatus === 200,
                status: countStatus,
                json: async () => countBody || { count },
            });
        }
        return Promise.resolve({ ok: true, json: async () => ({}) });
    });
}

// The value/operator selects are MUI `TextField select`s, which render a button
// rather than a native <select>, so a choice is made by opening the listbox.
async function choose(label, optionText) {
    fireEvent.mouseDown(screen.getAllByLabelText(label)[0]);
    const listbox = await screen.findByRole('listbox');
    fireEvent.click(within(listbox).getByText(optionText));
    await waitFor(() => expect(screen.queryByRole('listbox')).not.toBeInTheDocument());
}

describe('QueryBuilder', () => {
    beforeEach(() => { jest.useFakeTimers({ doNotFake: [ 'nextTick' ] }); });
    afterEach(() => { jest.runOnlyPendingTimers(); jest.useRealTimers(); jest.resetAllMocks(); });

    const flushCount = async () => {
        await waitFor(() => expect(screen.getByTestId('query-builder')).toBeInTheDocument());
        jest.advanceTimersByTime(500);
    };

    it('drives its field pick-list from the server rather than a hardcoded list', async () => {
        mockFetch();
        render(<QueryBuilder />);

        await screen.findByTestId('query-builder');
        fireEvent.mouseDown(screen.getAllByLabelText(en.queryBuilder.field)[0]);
        const listbox = await screen.findByRole('listbox');

        expect(within(listbox).getByText('Title')).toBeInTheDocument();
        expect(within(listbox).getByText('File size')).toBeInTheDocument();
        expect(global.fetch).toHaveBeenCalledWith('/api/v1/search/fields', expect.anything());
    });

    it('offers only the operators the chosen field declares', async () => {
        mockFetch();
        render(<QueryBuilder />);
        await screen.findByTestId('query-builder');

        await choose(en.queryBuilder.field, 'Created at');
        fireEvent.mouseDown(screen.getAllByLabelText(en.queryBuilder.operator)[0]);
        const listbox = await screen.findByRole('listbox');

        expect(within(listbox).getByText(en.queryBuilder.operators.before)).toBeInTheDocument();
        expect(within(listbox).queryByText(en.queryBuilder.operators.contains)).not.toBeInTheDocument();
    });

    it('renders a closed option set as a pick-list, not a free-text box', async () => {
        mockFetch();
        render(<QueryBuilder />);
        await screen.findByTestId('query-builder');

        await choose(en.queryBuilder.field, 'Status');
        fireEvent.mouseDown(screen.getAllByLabelText(en.queryBuilder.value)[0]);
        const listbox = await screen.findByRole('listbox');

        expect(within(listbox).getByText('approved')).toBeInTheDocument();
    });

    it('hides the value input for an operator that takes no operand', async () => {
        mockFetch();
        render(<QueryBuilder />);
        await screen.findByTestId('query-builder');

        await choose(en.queryBuilder.field, 'Title');
        await choose(en.queryBuilder.operator, en.queryBuilder.operators.blank);

        expect(screen.queryByLabelText(en.queryBuilder.value)).not.toBeInTheDocument();
    });

    it('shows two bounds for a range operator', async () => {
        mockFetch();
        render(<QueryBuilder />);
        await screen.findByTestId('query-builder');

        await choose(en.queryBuilder.field, 'File size');
        await choose(en.queryBuilder.operator, en.queryBuilder.operators.between);

        expect(screen.getByLabelText(en.queryBuilder.from)).toBeInTheDocument();
        expect(screen.getByLabelText(en.queryBuilder.to)).toBeInTheDocument();
    });

    it('resets an operator that the newly chosen field does not support', async () => {
        mockFetch();
        render(<QueryBuilder />);
        await screen.findByTestId('query-builder');

        await choose(en.queryBuilder.field, 'Title');
        await choose(en.queryBuilder.operator, en.queryBuilder.operators.contains);
        await choose(en.queryBuilder.field, 'Created at');

        // Keeping `contains` would leave a row that looks complete and is
        // rejected on submit.
        expect(screen.getAllByLabelText(en.queryBuilder.operator)[0]).toHaveTextContent(
            en.queryBuilder.operators.before,
        );
    });

    it('reports a live match count for the query as it stands', async () => {
        mockFetch({ count: 42 });
        render(<QueryBuilder />);
        await screen.findByTestId('query-builder');

        await choose(en.queryBuilder.field, 'Title');
        await choose(en.queryBuilder.operator, en.queryBuilder.operators.blank);
        jest.advanceTimersByTime(500);

        expect(await screen.findByTestId('query-builder-count')).toHaveTextContent('42');
    });

    it('does not ask the server to count a condition with no field chosen', async () => {
        mockFetch();
        render(<QueryBuilder />);
        await flushCount();

        await waitFor(() => expect(countCalls.length).toBeGreaterThan(0));
        expect(countCalls[countCalls.length - 1].query).toBeNull();
    });

    it('adds and removes nested groups', async () => {
        mockFetch();
        render(<QueryBuilder />);
        await screen.findByTestId('query-builder');

        expect(screen.getAllByTestId('condition-group')).toHaveLength(1);
        fireEvent.click(screen.getByRole('button', { name: en.queryBuilder.addGroup }));
        expect(screen.getAllByTestId('condition-group')).toHaveLength(2);

        fireEvent.click(screen.getByLabelText(en.queryBuilder.removeGroup));
        expect(screen.getAllByTestId('condition-group')).toHaveLength(1);
    });

    it('stops the user nesting past the server depth limit', async () => {
        mockFetch();
        render(<QueryBuilder />);
        await screen.findByTestId('query-builder');

        for (let i = 0; i < LIMITS.max_depth; i += 1) {
            const buttons = screen.getAllByRole('button', { name: en.queryBuilder.addGroup });
            const enabled = buttons.filter((b) => !b.disabled);
            if (enabled.length === 0) break;
            fireEvent.click(enabled[enabled.length - 1]);
        }

        const buttons = screen.getAllByRole('button', { name: en.queryBuilder.addGroup });
        expect(buttons.some((b) => b.disabled)).toBe(true);
    });

    it('refuses to let a NOT group hold more than one condition', async () => {
        mockFetch();
        render(<QueryBuilder />);
        await screen.findByTestId('query-builder');

        fireEvent.click(screen.getByRole('button', { name: en.queryBuilder.addCondition }));

        // NOT cannot represent two conditions, so it is disabled rather than
        // silently discarding the second one.
        expect(screen.getByRole('button', { name: en.queryBuilder.ops.not })).toBeDisabled();
    });

    it('hands the applied AST to its parent', async () => {
        mockFetch();
        const onApply = jest.fn();
        render(<QueryBuilder onApply={onApply} />);
        await screen.findByTestId('query-builder');

        await choose(en.queryBuilder.field, 'Title');
        await choose(en.queryBuilder.operator, en.queryBuilder.operators.blank);
        fireEvent.click(screen.getByRole('button', { name: en.queryBuilder.apply }));

        expect(onApply).toHaveBeenCalledWith({
            op: 'and', children: [ { field: 'title', operator: 'blank' } ],
        });
    });

    it('will not apply an empty query', async () => {
        mockFetch();
        render(<QueryBuilder onApply={jest.fn()} />);
        await screen.findByTestId('query-builder');

        expect(screen.getByRole('button', { name: en.queryBuilder.apply })).toBeDisabled();
    });

    it('renders an AST it was given rather than an empty tree', async () => {
        mockFetch();
        render(<QueryBuilder initialAst={{
            op: 'or',
            children: [
                { field: 'title', operator: 'contains', value: 'sunset' },
                { field: 'status', operator: 'eq', value: 'approved' },
            ],
        }} />);
        await screen.findByTestId('query-builder');

        expect(screen.getAllByTestId('condition-row')).toHaveLength(2);
        expect(screen.getByDisplayValue('sunset')).toBeInTheDocument();
    });

    it('surfaces a rejected query instead of showing a stale count', async () => {
        mockFetch({ countStatus: 422, countBody: { error: 'Unknown field', path: [ 'children', '0' ] } });
        render(<QueryBuilder />);
        await screen.findByTestId('query-builder');

        await choose(en.queryBuilder.field, 'Title');
        await choose(en.queryBuilder.operator, en.queryBuilder.operators.blank);
        jest.advanceTimersByTime(500);

        expect(await screen.findByTestId('query-builder-error')).toHaveTextContent('Unknown field');
    });

    it('disables itself when the field list cannot be loaded', async () => {
        mockFetch({ fieldsOk: false });
        render(<QueryBuilder />);

        expect(await screen.findByText(en.queryBuilder.fieldsUnavailable)).toBeInTheDocument();
    });
});
