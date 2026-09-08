import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import i18n from 'i18next';
import en from '../../../../app/javascript/i18n/locales/en.json';
import PortalFormDialog from '../../../../app/javascript/components/Portals/PortalFormDialog';

i18n.addResourceBundle('en', 'translation', en, true, true);

const asset = (id, title, overrides = {}) => ({
    id,
    title,
    usage_terms: 'external_ok',
    permission: null,
    granted: false,
    externally_distributable: true,
    ...overrides,
});

const existing = {
    id: 3,
    name: 'Agency drop',
    target_label: 'Autumn campaign',
    collection_id: 7,
    branding: { accent: '#1f6feb', headline: 'Hello' },
    expires_at: '2030-01-01T00:00:00Z',
    require_email: true,
    passphrase_required: true,
};

const renderEdit = (assets, onSubmit = jest.fn()) => {
    const fetchPortal = jest.fn().mockResolvedValue({ ...existing, assets });
    render(
        <PortalFormDialog
            open
            portal={existing}
            collections={[]}
            fetchPortal={fetchPortal}
            onClose={jest.fn()}
            onSubmit={onSubmit}
        />,
    );
    return { fetchPortal, onSubmit };
};

describe('PortalFormDialog (editing)', () => {
    it('loads the pick list and pre-selects existing grants', async () => {
        renderEdit([
            asset('a1', 'Hero shot', { granted: true, permission: 'download' }),
            asset('a2', 'Outtake'),
        ]);

        expect(await screen.findByText('Hero shot')).toBeInTheDocument();
        expect(screen.getByText('1 of 2 assets shared')).toBeInTheDocument();
        expect(screen.getByLabelText('Permission for Hero shot')).toHaveTextContent('View and download');
        expect(screen.getByLabelText('Permission for Outtake')).toHaveTextContent('No access');
    });

    // Rights outrank intent: a grant on an internal-only asset is recorded and
    // then ignored at delivery, so the only useful place to say so is here.
    it('marks assets that rights will not let out', async () => {
        renderEdit([
            asset('a1', 'Internal deck', { externally_distributable: false, usage_terms: 'internal_only' }),
        ]);

        expect(await screen.findByText('Not distributable')).toBeInTheDocument();
    });

    it('warns when a shared asset cannot actually leave', async () => {
        renderEdit([
            asset('a1', 'Internal deck', {
                externally_distributable: false, granted: true, permission: 'view',
            }),
        ]);

        expect(await screen.findByText(/1 of the assets you have shared cannot leave/))
            .toBeInTheDocument();
    });

    // The grant set is declarative — what is sent replaces everything. An asset
    // switched to "no access" must be absent, not present-and-ignored.
    it('submits the full grant set, omitting withheld assets', async () => {
        const onSubmit = jest.fn().mockResolvedValue(undefined);
        renderEdit([
            asset('a1', 'Hero shot', { granted: true, permission: 'download' }),
            asset('a2', 'Outtake', { granted: true, permission: 'view' }),
        ], onSubmit);

        await screen.findByText('Hero shot');

        fireEvent.mouseDown(screen.getByLabelText('Permission for Outtake'));
        fireEvent.click(await screen.findByRole('option', { name: 'No access' }));

        fireEvent.click(screen.getByRole('button', { name: 'Save changes' }));

        await waitFor(() => expect(onSubmit).toHaveBeenCalled());
        expect(onSubmit.mock.calls[0][0].grants).toEqual([
            { asset_id: 'a1', permission: 'download' },
        ]);
    });

    // Sending an empty passphrase would clear the one already set, which is not
    // what leaving a password field alone means.
    it('omits the passphrase when it is left blank', async () => {
        const onSubmit = jest.fn().mockResolvedValue(undefined);
        renderEdit([asset('a1', 'Hero shot')], onSubmit);

        await screen.findByText('Hero shot');
        fireEvent.click(screen.getByRole('button', { name: 'Save changes' }));

        await waitFor(() => expect(onSubmit).toHaveBeenCalled());
        expect(onSubmit.mock.calls[0][0]).not.toHaveProperty('passphrase');
    });

    // Re-pointing a live portal would hand an outsider material they were never
    // shown, while the URL in their inbox looks unchanged.
    it('does not allow the target to be changed', async () => {
        renderEdit([asset('a1', 'Hero shot')]);

        await screen.findByText('Hero shot');
        expect(screen.queryByLabelText('Collection to share')).not.toBeInTheDocument();
        expect(screen.getByText(/The target cannot be changed after creation/)).toBeInTheDocument();
    });

    it('shares or withholds every asset at once', async () => {
        const onSubmit = jest.fn().mockResolvedValue(undefined);
        renderEdit([asset('a1', 'Hero shot'), asset('a2', 'Outtake')], onSubmit);

        await screen.findByText('Hero shot');
        fireEvent.click(screen.getByRole('button', { name: 'Share all' }));

        expect(screen.getByText('2 of 2 assets shared')).toBeInTheDocument();

        fireEvent.click(screen.getByRole('button', { name: 'Withhold all' }));
        expect(screen.getByText('0 of 2 assets shared')).toBeInTheDocument();
    });

    it('reports a save failure without closing', async () => {
        const onSubmit = jest.fn().mockRejectedValue(new Error('Name is too long'));
        renderEdit([asset('a1', 'Hero shot')], onSubmit);

        await screen.findByText('Hero shot');
        fireEvent.click(screen.getByRole('button', { name: 'Save changes' }));

        expect(await screen.findByText('Name is too long')).toBeInTheDocument();
    });
});
