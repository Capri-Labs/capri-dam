import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import i18n from 'i18next';
import en from '../../../../app/javascript/i18n/locales/en.json';
import AiTagSuggestionsPanel from '../../../../app/javascript/components/Folders/AiTagSuggestionsPanel';

i18n.addResourceBundle('en', 'translation', en, true, true);

const asset = { id: 'asset-1' };

const suggestion = (over = {}) => ({
    id: 'sug-1', label: 'sunset', confidence: 0.91, state: 'pending', ...over,
});

function mockFetch({ suggestions = [], runs = [], overrides = {} } = {}) {
    global.fetch = jest.fn((url, opts = {}) => {
        const method = opts.method || 'GET';
        const key = `${method} ${url}`;
        if (overrides[key]) return Promise.resolve(overrides[key]);
        if (url.includes('/ai_tag_suggestions') && method === 'GET') {
            return Promise.resolve({ ok: true, json: async () => ({ suggestions }) });
        }
        if (url.includes('/ai_tagging_runs') && method === 'GET') {
            return Promise.resolve({ ok: true, json: async () => ({ runs }) });
        }
        if (url.includes('/ai_tagging_runs') && method === 'POST') {
            return Promise.resolve({ ok: true, json: async () => ({ id: 'run-1', status: 'queued' }) });
        }
        return Promise.resolve({ ok: true, json: async () => ({ id: 'sug-1', state: 'accepted' }) });
    });
}

describe('AiTagSuggestionsPanel', () => {
    afterEach(() => { jest.resetAllMocks(); });

    it('renders pending suggestions with their confidence', async () => {
        mockFetch({ suggestions: [ suggestion() ] });
        render(<AiTagSuggestionsPanel asset={asset} />);

        expect(await screen.findByText('sunset')).toBeInTheDocument();
        expect(screen.getByText('91%')).toBeInTheDocument();
    });

    it('shows the empty state when nothing is awaiting review', async () => {
        mockFetch();
        render(<AiTagSuggestionsPanel asset={asset} />);

        expect(await screen.findByText(en.aiTagging.empty)).toBeInTheDocument();
    });

    it('omits confidence when the model did not report one', async () => {
        mockFetch({ suggestions: [ suggestion({ confidence: null }) ] });
        render(<AiTagSuggestionsPanel asset={asset} />);

        await screen.findByText('sunset');
        expect(screen.queryByText(/%$/)).not.toBeInTheDocument();
    });

    it('accepts a suggestion, removes it from the queue and notifies the parent', async () => {
        mockFetch({ suggestions: [ suggestion() ] });
        const onTagsChanged = jest.fn();
        render(<AiTagSuggestionsPanel asset={asset} onTagsChanged={onTagsChanged} />);

        fireEvent.click(await screen.findByLabelText(en.aiTagging.action.accept));

        await waitFor(() => expect(screen.queryByText('sunset')).not.toBeInTheDocument());
        expect(global.fetch).toHaveBeenCalledWith(
            '/api/v1/ai_tag_suggestions/sug-1/accept',
            expect.objectContaining({ method: 'POST' }),
        );
        expect(onTagsChanged).toHaveBeenCalled();
    });

    it('dismisses a suggestion without touching the asset tags', async () => {
        mockFetch({ suggestions: [ suggestion() ] });
        const onTagsChanged = jest.fn();
        render(<AiTagSuggestionsPanel asset={asset} onTagsChanged={onTagsChanged} />);

        fireEvent.click(await screen.findByLabelText(en.aiTagging.action.dismiss));

        await waitFor(() => expect(screen.queryByText('sunset')).not.toBeInTheDocument());
        expect(global.fetch).toHaveBeenCalledWith(
            '/api/v1/ai_tag_suggestions/sug-1/dismiss',
            expect.objectContaining({ method: 'POST' }),
        );
        expect(onTagsChanged).not.toHaveBeenCalled();
    });

    it('requests a run and reflects that work is in flight', async () => {
        mockFetch();
        render(<AiTagSuggestionsPanel asset={asset} />);

        fireEvent.click(await screen.findByRole('button', { name: en.aiTagging.action.suggest }));

        expect(await screen.findByText(en.aiTagging.status.running)).toBeInTheDocument();
        expect(global.fetch).toHaveBeenCalledWith(
            '/api/v1/assets/asset-1/ai_tagging_runs',
            expect.objectContaining({ method: 'POST', body: JSON.stringify({ profile: 'general_subject' }) }),
        );
    });

    it('surfaces a rejected run request instead of failing silently', async () => {
        mockFetch({
            overrides: {
                'POST /api/v1/assets/asset-1/ai_tagging_runs': {
                    ok: false, status: 409,
                    json: async () => ({ error: 'A tagging run is already in progress for this asset.' }),
                },
            },
        });
        render(<AiTagSuggestionsPanel asset={asset} />);

        fireEvent.click(await screen.findByRole('button', { name: en.aiTagging.action.suggest }));

        expect(await screen.findByText('A tagging run is already in progress for this asset.')).toBeInTheDocument();
    });

    it('makes a failed run visible rather than indistinguishable from no results', async () => {
        mockFetch({ runs: [ { id: 'run-1', status: 'failed', error_message: 'gateway timeout' } ] });
        render(<AiTagSuggestionsPanel asset={asset} />);

        expect(await screen.findByText(/gateway timeout/)).toBeInTheDocument();
    });

    it('hides the accept and dismiss controls for read-only users', async () => {
        mockFetch({ suggestions: [ suggestion() ] });
        render(<AiTagSuggestionsPanel asset={asset} canModify={false} />);

        await screen.findByText('sunset');
        expect(screen.queryByLabelText(en.aiTagging.action.accept)).not.toBeInTheDocument();
        expect(screen.queryByRole('button', { name: en.aiTagging.action.suggest })).not.toBeInTheDocument();
    });
});
