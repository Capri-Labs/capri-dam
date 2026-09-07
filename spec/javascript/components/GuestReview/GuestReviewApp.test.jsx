import React from 'react';
import {
    render, screen, fireEvent, waitForElementToBeRemoved,
} from '@testing-library/react';
import i18n from 'i18next';
import en from '../../../../app/javascript/i18n/locales/en.json';

// The shared setup initialises i18next with an empty bundle. Load the real
// English strings so these assertions test the copy a reviewer actually sees
// rather than the key paths, which would pass even if a key were missing.
i18n.addResourceBundle('en', 'translation', en, true, true);

// The hook is covered by its own spec. Mocking it here keeps this test on the
// app's composition logic — what renders, when — rather than on fetch.
const mockHook = jest.fn();
jest.mock(
    '../../../../app/javascript/components/GuestReview/useGuestReview',
    () => ({ __esModule: true, default: (...args) => mockHook(...args) }),
);

// eslint-disable-next-line import/first
import GuestReviewApp from '../../../../app/javascript/components/GuestReview/GuestReviewApp';

const asset = (id, title) => ({
    id,
    title,
    content_type: 'image/jpeg',
    preview_url: `/s/reviews/tok/assets/${id}/preview`,
});

const hookState = (overrides = {}) => ({
    review: {
        name: 'Autumn campaign review',
        target_label: 'Autumn campaign',
        allow_comments: true,
        require_email: false,
        expires_at: null,
    },
    guest: null,
    assets: [asset('a1', 'Hero shot')],
    selectedAsset: asset('a1', 'Hero shot'),
    selectedAssetId: 'a1',
    setSelectedAssetId: jest.fn(),
    threads: [],
    annotations: [],
    canComment: true,
    loading: false,
    threadsLoading: false,
    error: null,
    identify: jest.fn().mockResolvedValue(undefined),
    createThread: jest.fn().mockResolvedValue({ id: 't1' }),
    createReply: jest.fn().mockResolvedValue({}),
    reload: jest.fn(),
    ...overrides,
});

const renderApp = (overrides = {}) => {
    const state = hookState(overrides);
    mockHook.mockReturnValue(state);
    render(<GuestReviewApp config={{ token: 'tok' }} />);
    return state;
};

beforeEach(() => {
    mockHook.mockReset();
});

describe('GuestReviewApp', () => {
    it('passes the token from the page config to the data layer', () => {
        renderApp();

        expect(mockHook).toHaveBeenCalledWith('tok');
    });

    it('shows a spinner while loading and nothing else', () => {
        renderApp({ loading: true });

        expect(screen.getByRole('progressbar')).toBeInTheDocument();
        expect(screen.queryByText('Autumn campaign review')).toBeNull();
    });

    // A revoked or expired link must state why rather than render an empty shell.
    it('shows the failure reason when the link cannot be opened', () => {
        renderApp({
            loading: false,
            review: null,
            error: 'This review link has been revoked.',
        });

        expect(screen.getByRole('alert')).toHaveTextContent(
            'This review link has been revoked.',
        );
    });

    it('names the review and its target in the header', () => {
        renderApp();

        expect(screen.getByText('Autumn campaign review')).toBeInTheDocument();
        expect(screen.getByText('Autumn campaign')).toBeInTheDocument();
    });

    it('identifies the reviewer once they have given a name', () => {
        renderApp({ guest: { display_name: 'Priya' } });

        expect(screen.getByText('Reviewing as Priya')).toBeInTheDocument();
    });

    it('tells the reviewer when their access ends', () => {
        renderApp({
            review: { ...hookState().review, expires_at: '2026-01-15T00:00:00Z' },
        });

        expect(screen.getByText(/Access ends/)).toBeInTheDocument();
    });

    // The rail is pure overhead for a single-asset link.
    it('hides the asset rail when the link covers one asset', () => {
        renderApp();

        // The viewer renders the selected asset too, so the rail's absence
        // means exactly one image bears this asset's name, not zero.
        expect(screen.getAllByRole('img', { name: 'Hero shot' })).toHaveLength(1);
    });

    it('shows the asset rail and switches assets when the link covers several', () => {
        const state = renderApp({
            assets: [asset('a1', 'Hero shot'), asset('a2', 'Packshot')],
        });

        // The unselected asset can only be coming from the rail.
        expect(screen.getByRole('img', { name: 'Packshot' })).toBeInTheDocument();

        fireEvent.click(screen.getByRole('img', { name: 'Packshot' }));
        expect(state.setSelectedAssetId).toHaveBeenCalledWith('a2');
    });

    // Asking for a name up front is the difference between actionable notes
    // and a list of unattributable complaints.
    it('asks who is reviewing when the link requires it', () => {
        renderApp({
            review: { ...hookState().review, require_email: true },
            guest: null,
        });

        expect(screen.getByText("Who's reviewing?")).toBeInTheDocument();
    });

    it('does not ask again once the reviewer has declined', async () => {
        renderApp({
            review: { ...hookState().review, require_email: true },
            guest: null,
        });

        fireEvent.click(screen.getByRole('button', { name: /not now/i }));

        // The dialog fades out, so it lingers in the DOM for a tick after the
        // click.
        await waitForElementToBeRemoved(() => screen.queryByText("Who's reviewing?"));
    });

    it('does not ask a reviewer who is already known', () => {
        renderApp({
            review: { ...hookState().review, require_email: true },
            guest: { display_name: 'Priya' },
        });

        expect(screen.queryByText("Who's reviewing?")).toBeNull();
    });

    // A read-only link has nobody to attribute, so the prompt is noise.
    it('does not ask for identity on a read-only link', () => {
        renderApp({
            review: {
                ...hookState().review,
                require_email: true,
                allow_comments: false,
            },
            canComment: false,
            guest: null,
        });

        expect(screen.queryByText("Who's reviewing?")).toBeNull();
    });
});
