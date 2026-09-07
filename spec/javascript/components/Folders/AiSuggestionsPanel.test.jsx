import React from 'react';
import { render, screen, fireEvent, within } from '@testing-library/react';
import i18n from 'i18next';
import AiSuggestionsPanel from '../../../../app/javascript/components/Folders/AiSuggestionsPanel';
import en from '../../../../app/javascript/i18n/locales/en.json';

// Load the real English bundle so the assertions below fail if a key is
// renamed or deleted, rather than passing against a raw key path.
i18n.addResourceBundle('en', 'translation', en, true, true);

const SUGGESTION = {
    id: 'thread-ai-1',
    suggestion: { state: 'pending', model_name: 'gpt-vision' },
    comments: [{
        id: 'c1',
        body: 'Logo overlaps the safe area on the right edge.',
        confidence: 0.82,
        annotations: [{ id: 'ann-1', shape: 'rect' }],
    }],
};

const SECOND_SUGGESTION = {
    id: 'thread-ai-2',
    suggestion: { state: 'pending', model_name: 'gpt-vision' },
    comments: [{ id: 'c2', body: 'Body copy contrast is below 4.5:1.', confidence: 0.61, annotations: [] }],
};

const baseReview = (overrides = {}) => ({
    suggestions: [],
    reviews: [],
    latestReview: null,
    annotations: [],
    pendingCount: 0,
    running: false,
    loading: false,
    busy: false,
    error: null,
    clearError: jest.fn(),
    refresh: jest.fn(),
    runReview: jest.fn(),
    acceptSuggestion: jest.fn(),
    dismissSuggestion: jest.fn(),
    selectedThreadId: null,
    setSelectedThreadId: jest.fn(),
    hoveredThreadId: null,
    setHoveredThreadId: jest.fn(),
    ...overrides,
});

const renderPanel = (overrides = {}, props = {}) => {
    const review = baseReview(overrides);
    render(<AiSuggestionsPanel review={review} canModify {...props} />);
    return review;
};

describe('AiSuggestionsPanel', () => {
    it('prompts the user to run a review when none has run', () => {
        renderPanel();

        expect(screen.getByText('Run a review to have the assistant check this asset.')).toBeInTheDocument();
    });

    it('renders a suggestion with its body, shape and confidence', () => {
        renderPanel({ suggestions: [SUGGESTION], pendingCount: 1 });

        expect(screen.getByText('Logo overlaps the safe area on the right edge.')).toBeInTheDocument();
        expect(screen.getByText('Rectangle')).toBeInTheDocument();
        expect(screen.getByText('82% confident')).toBeInTheDocument();
    });

    it('shows how many suggestions are waiting', () => {
        renderPanel({ suggestions: [SUGGESTION, SECOND_SUGGESTION], pendingCount: 2 });

        expect(screen.getByText('2 to review')).toBeInTheDocument();
        expect(screen.getAllByTestId('ai-suggestion-card')).toHaveLength(2);
    });

    it('runs a review with the chosen profile', () => {
        const review = renderPanel();

        fireEvent.click(screen.getByRole('button', { name: 'Run review' }));

        expect(review.runReview).toHaveBeenCalledWith('brand_guidelines');
    });

    it('accepts an individual suggestion', () => {
        const review = renderPanel({ suggestions: [SUGGESTION], pendingCount: 1 });

        fireEvent.click(screen.getByRole('button', { name: 'Accept' }));

        expect(review.acceptSuggestion).toHaveBeenCalledWith('thread-ai-1');
    });

    it('dismisses an individual suggestion', () => {
        const review = renderPanel({ suggestions: [SUGGESTION], pendingCount: 1 });

        fireEvent.click(screen.getByRole('button', { name: 'Dismiss' }));

        expect(review.dismissSuggestion).toHaveBeenCalledWith('thread-ai-1');
    });

    it('offers no bulk accept control', () => {
        renderPanel({ suggestions: [SUGGESTION, SECOND_SUGGESTION], pendingCount: 2 });

        // Each finding must be judged on its own; a bulk button would turn the
        // assistant into an unreviewed bot posting into the team's review.
        expect(screen.getAllByRole('button', { name: 'Accept' })).toHaveLength(2);
        expect(screen.queryByRole('button', { name: /accept all/i })).not.toBeInTheDocument();
    });

    it('hides every triage control from a user without modify rights', () => {
        renderPanel({ suggestions: [SUGGESTION], pendingCount: 1 }, { canModify: false });

        expect(screen.getByText('Logo overlaps the safe area on the right edge.')).toBeInTheDocument();
        expect(screen.queryByRole('button', { name: 'Accept' })).not.toBeInTheDocument();
        expect(screen.queryByRole('button', { name: 'Dismiss' })).not.toBeInTheDocument();
        expect(screen.queryByRole('button', { name: 'Run review' })).not.toBeInTheDocument();
    });

    it('selects a suggestion when its card is clicked', () => {
        const review = renderPanel({ suggestions: [SUGGESTION], pendingCount: 1 });

        fireEvent.click(screen.getByText('Logo overlaps the safe area on the right edge.'));

        expect(review.setSelectedThreadId).toHaveBeenCalledWith('thread-ai-1');
    });

    it('highlights the marker while the pointer is over a card', () => {
        const review = renderPanel({ suggestions: [SUGGESTION], pendingCount: 1 });
        const card = screen.getByTestId('ai-suggestion-card');

        fireEvent.mouseEnter(card);
        expect(review.setHoveredThreadId).toHaveBeenCalledWith('thread-ai-1');

        fireEvent.mouseLeave(card);
        expect(review.setHoveredThreadId).toHaveBeenLastCalledWith(null);
    });

    it('does not select the card when a triage button is pressed', () => {
        const review = renderPanel({ suggestions: [SUGGESTION], pendingCount: 1 });

        fireEvent.click(screen.getByRole('button', { name: 'Accept' }));

        // The button sits inside the clickable card; without stopPropagation
        // accepting would also fire a selection.
        expect(review.setSelectedThreadId).not.toHaveBeenCalled();
    });

    it('disables running while a review is already in flight', () => {
        renderPanel({ running: true, latestReview: { id: 'r1', status: 'running' } });

        expect(screen.getByRole('button', { name: /Reviewing/ })).toBeDisabled();
    });

    it('disables triage buttons while a decision is in flight', () => {
        renderPanel({ suggestions: [SUGGESTION], pendingCount: 1, busy: true });

        expect(screen.getByRole('button', { name: 'Accept' })).toBeDisabled();
        expect(screen.getByRole('button', { name: 'Dismiss' })).toBeDisabled();
    });

    it('distinguishes a clean run from never having run', () => {
        renderPanel({
            latestReview: { id: 'r1', status: 'completed', findings_count: 0 },
            pendingCount: 0,
        });

        expect(screen.getByText('No issues found in the last review.')).toBeInTheDocument();
        expect(screen.queryByText('Run a review to have the assistant check this asset.')).not.toBeInTheDocument();
    });

    it('reports why a failed run failed', () => {
        renderPanel({
            latestReview: { id: 'r1', status: 'failed', error_message: 'Gateway timed out' },
        });

        expect(screen.getByText('Gateway timed out')).toBeInTheDocument();
    });

    it('falls back to a generic message when a failure carries no detail', () => {
        renderPanel({ latestReview: { id: 'r1', status: 'failed', error_message: null } });

        expect(screen.getByText('The review could not be completed.')).toBeInTheDocument();
    });

    it('surfaces and can clear an API error', () => {
        const review = renderPanel({ error: 'A review is already running for this asset.' });

        const alert = screen.getByRole('alert');
        expect(within(alert).getByText('A review is already running for this asset.')).toBeInTheDocument();

        fireEvent.click(within(alert).getByRole('button'));
        expect(review.clearError).toHaveBeenCalled();
    });

    it('attributes suggestions to the model that made them', () => {
        renderPanel({
            suggestions: [SUGGESTION],
            pendingCount: 1,
            latestReview: { id: 'r1', status: 'completed', model_name: 'gpt-vision' },
        });

        // Attribution is the point of the audit trail: a reader must be able to
        // tell which model produced the claim.
        expect(screen.getByText('Suggested by gpt-vision')).toBeInTheDocument();
    });

    it('collapses and restores the queue', () => {
        renderPanel({ suggestions: [SUGGESTION], pendingCount: 1 });

        fireEvent.click(screen.getByRole('button', { name: 'Collapse' }));
        expect(screen.queryByTestId('ai-suggestion-card')).not.toBeInTheDocument();

        fireEvent.click(screen.getByRole('button', { name: 'Expand' }));
        expect(screen.getByTestId('ai-suggestion-card')).toBeInTheDocument();
    });

    it('refreshes the queue on demand', () => {
        const review = renderPanel();

        fireEvent.click(screen.getByRole('button', { name: 'Refresh' }));

        expect(review.refresh).toHaveBeenCalled();
    });
});
