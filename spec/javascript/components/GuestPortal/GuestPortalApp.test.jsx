import React from 'react';
import {
    render, screen, fireEvent, waitForElementToBeRemoved,
} from '@testing-library/react';
import i18n from 'i18next';
import en from '../../../../app/javascript/i18n/locales/en.json';

// The shared setup initialises i18next with an empty bundle. Load the real
// English strings so these assertions test the copy a partner actually sees
// rather than the key paths, which would pass even if a key were missing.
i18n.addResourceBundle('en', 'translation', en, true, true);

// The hook has its own spec. Mocking it keeps this file on composition — what
// renders, and when — rather than on fetch.
const mockHook = jest.fn();
jest.mock(
    '../../../../app/javascript/components/GuestPortal/useGuestPortal',
    () => ({ __esModule: true, default: (...args) => mockHook(...args) }),
);

// eslint-disable-next-line import/first
import GuestPortalApp from '../../../../app/javascript/components/GuestPortal/GuestPortalApp';

const asset = (id, title, overrides = {}) => ({
    id,
    title,
    content_type: 'image/jpeg',
    byte_size: 2048,
    preview_url: `/s/portal/tok/assets/${id}/preview`,
    downloadable: true,
    download_url: `/s/portal/tok/assets/${id}/download`,
    ...overrides,
});

const hookState = (overrides = {}) => ({
    portal: {
        name: 'Agency drop',
        headline: 'Autumn campaign assets',
        message: null,
        accent: '#1f6feb',
        require_email: false,
        identified: false,
    },
    guest: null,
    assets: [asset('a1', 'Hero shot')],
    loading: false,
    error: null,
    locked: false,
    unlock: jest.fn(),
    identify: jest.fn(),
    reload: jest.fn(),
    ...overrides,
});

const config = { token: 'tok', headline: 'Shared files', accent: '#2563eb' };

const renderApp = (overrides = {}) => {
    mockHook.mockReturnValue(hookState(overrides));
    return render(<GuestPortalApp config={config} />);
};

describe('GuestPortalApp', () => {
    beforeEach(() => jest.clearAllMocks());

    it('renders the branded headline over the page default', () => {
        renderApp();

        expect(screen.getByTestId('portal-headline')).toHaveTextContent('Autumn campaign assets');
    });

    it('falls back to the page headline when the portal has no branding', () => {
        renderApp({ portal: { headline: null, accent: '#1f6feb', require_email: false } });

        expect(screen.getByTestId('portal-headline')).toHaveTextContent('Shared files');
    });

    it('shows the passphrase gate instead of the files when locked', () => {
        renderApp({ locked: true, assets: [] });

        expect(screen.getByLabelText(/passphrase/i)).toBeInTheDocument();
        // A locked portal must not leak the file list behind the gate.
        expect(screen.queryAllByTestId('portal-asset-card')).toHaveLength(0);
    });

    it('prefers the passphrase gate over an error so a lock never reads as a failure', () => {
        renderApp({ locked: true, error: 'Something went wrong.' });

        expect(screen.getByLabelText(/passphrase/i)).toBeInTheDocument();
        expect(screen.queryByTestId('portal-error')).not.toBeInTheDocument();
    });

    it('reports a real error', () => {
        renderApp({ error: 'This share link is no longer available.' });

        expect(screen.getByTestId('portal-error'))
            .toHaveTextContent('This share link is no longer available.');
    });

    it('renders a card per granted asset with a pluralised count', () => {
        renderApp({ assets: [asset('a1', 'Hero shot'), asset('a2', 'Logo')] });

        expect(screen.getAllByTestId('portal-asset-card')).toHaveLength(2);
        expect(screen.getByTestId('portal-file-count')).toHaveTextContent('2 files');
    });

    it('uses the singular for one file', () => {
        renderApp();

        expect(screen.getByTestId('portal-file-count')).toHaveTextContent('1 file');
    });

    it('explains an empty portal rather than rendering a bare page', () => {
        renderApp({ assets: [] });

        expect(screen.getByTestId('portal-empty')).toBeInTheDocument();
    });

    it('asks who is collecting when the link requires an email', () => {
        renderApp({
            portal: { headline: 'Autumn', accent: '#1f6feb', require_email: true },
            guest: null,
        });

        expect(screen.getByRole('dialog')).toHaveTextContent(/who is collecting/i);
    });

    it('does not ask again once the guest has identified themselves', () => {
        renderApp({
            portal: { headline: 'Autumn', accent: '#1f6feb', require_email: true },
            guest: { id: 'g1', name: 'Priya', anonymous: false },
        });

        expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
        expect(screen.getByText('Priya')).toBeInTheDocument();
    });

    it('stops asking for the rest of the visit once declined', async () => {
        renderApp({
            portal: { headline: 'Autumn', accent: '#1f6feb', require_email: true },
            guest: null,
        });

        fireEvent.click(screen.getByRole('button', { name: /not now/i }));

        // Re-prompting on every render would make the portal unusable for
        // someone who has chosen not to say who they are. The dialog lingers
        // through its exit transition, so wait it out rather than asserting
        // against a frame that has not unmounted yet.
        await waitForElementToBeRemoved(() => screen.queryByRole('dialog'));
        expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });

    it('does not label an anonymous guest by their reserved name', () => {
        renderApp({ guest: { id: 'g1', name: 'Guest reviewer', anonymous: true } });

        expect(screen.queryByText('Guest reviewer')).not.toBeInTheDocument();
    });

    it('shows a spinner and no file list while loading', () => {
        renderApp({ loading: true, assets: [asset('a1', 'Hero shot')] });

        expect(screen.getByRole('progressbar')).toBeInTheDocument();
        expect(screen.queryAllByTestId('portal-asset-card')).toHaveLength(0);
    });
});
