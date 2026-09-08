import React from 'react';
import {
    render, screen, fireEvent, waitFor, within,
} from '@testing-library/react';
import i18n from 'i18next';
import en from '../../../../app/javascript/i18n/locales/en.json';

// The shared setup initialises i18next with an empty bundle. Loading the real
// English strings means these assertions test the copy a person configuring an
// external share actually reads, not the key paths.
i18n.addResourceBundle('en', 'translation', en, true, true);

const mockNotify = jest.fn();
jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
    __esModule: true,
    useNotify: () => mockNotify,
}));

const mockHook = jest.fn();
jest.mock(
    '../../../../app/javascript/components/Portals/usePortals',
    () => ({ __esModule: true, default: (...args) => mockHook(...args) }),
);

// eslint-disable-next-line import/first
import PortalsManager from '../../../../app/javascript/components/Portals/PortalsManager';

const portal = (overrides = {}) => ({
    id: 1,
    name: 'Agency drop',
    status: 'active',
    target_label: 'Autumn campaign',
    collection_id: 7,
    branding: {},
    expires_at: '2030-01-01T00:00:00Z',
    require_email: false,
    passphrase_required: false,
    granted_count: 12,
    downloadable_count: 4,
    distributable_count: 3,
    download_count: 5,
    ...overrides,
});

const hookState = (overrides = {}) => ({
    portals: [portal()],
    loading: false,
    error: null,
    reload: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
    revoke: jest.fn().mockResolvedValue(undefined),
    fetchPortal: jest.fn().mockResolvedValue({ assets: [] }),
    fetchDownloads: jest.fn().mockResolvedValue({ downloads: [], meta: { total: 0 } }),
    ...overrides,
});

beforeEach(() => {
    jest.clearAllMocks();
    mockHook.mockReturnValue(hookState());
    global.fetch = jest.fn().mockResolvedValue({ ok: true, json: async () => [] });
});

describe('PortalsManager', () => {
    it('lists portals with their status', () => {
        render(<PortalsManager />);

        expect(screen.getByText('Agency drop')).toBeInTheDocument();
        expect(screen.getByText('Autumn campaign')).toBeInTheDocument();
        // Scoped to the table: "Active" is also a status filter button.
        expect(within(screen.getByRole('table')).getByText('Active')).toBeInTheDocument();
    });

    // The whole point of showing both numbers: twelve picks and three
    // deliverable files is not an error, but the sender must be able to see it
    // before the recipient writes to say files are missing.
    it('shows granted and deliverable counts side by side', () => {
        render(<PortalsManager />);

        expect(screen.getByText('12 granted / 3 deliverable')).toBeInTheDocument();
    });

    it('renders an empty state when there are no portals', () => {
        mockHook.mockReturnValue(hookState({ portals: [] }));
        render(<PortalsManager />);

        expect(screen.getByText('No portals yet.')).toBeInTheDocument();
    });

    it('filters the list by status', () => {
        mockHook.mockReturnValue(hookState({
            portals: [portal(), portal({ id: 2, name: 'Old drop', status: 'revoked' })],
        }));
        render(<PortalsManager />);

        expect(screen.getByText('Old drop')).toBeInTheDocument();

        fireEvent.click(screen.getByRole('button', { name: 'Active' }));

        expect(screen.queryByText('Old drop')).not.toBeInTheDocument();
        expect(screen.getByText('Agency drop')).toBeInTheDocument();
    });

    it('surfaces a load error', () => {
        mockHook.mockReturnValue(hookState({ error: 'Boom', portals: [] }));
        render(<PortalsManager />);

        expect(screen.getByText('Boom')).toBeInTheDocument();
    });

    // Revoking is irreversible, so it must never be one click away.
    it('asks for confirmation before revoking', async () => {
        const revoke = jest.fn().mockResolvedValue(undefined);
        mockHook.mockReturnValue(hookState({ revoke }));
        render(<PortalsManager />);

        fireEvent.click(screen.getByRole('button', { name: 'Revoke' }));

        expect(await screen.findByText('Revoke this portal?')).toBeInTheDocument();
        expect(revoke).not.toHaveBeenCalled();

        const dialog = screen.getByRole('dialog');
        fireEvent.click(within(dialog).getByRole('button', { name: 'Revoke' }));

        await waitFor(() => expect(revoke).toHaveBeenCalledWith(1));
        await waitFor(() => expect(mockNotify).toHaveBeenCalledWith('Portal revoked.', 'success'));
    });

    it('does not offer edit or revoke on an already revoked portal', () => {
        mockHook.mockReturnValue(hookState({ portals: [portal({ status: 'revoked' })] }));
        render(<PortalsManager />);

        expect(screen.getByRole('button', { name: 'Revoke' })).toBeDisabled();
        expect(screen.getByRole('button', { name: 'Edit portal' })).toBeDisabled();
        // The download log stays reachable: revocation ends the credential, not
        // the obligation to say what already left.
        expect(screen.getByRole('button', { name: 'Download log' })).toBeEnabled();
    });

    it('opens the download log for a portal', async () => {
        const fetchDownloads = jest.fn().mockResolvedValue({
            downloads: [{
                id: 9,
                asset_id: 'a1',
                asset_title: 'Hero shot',
                guest: 'Dana',
                guest_email: 'dana@agency.test',
                ip_address: '203.0.113.4',
                downloaded_at: '2026-01-02T10:00:00Z',
            }],
            meta: { total: 1 },
        });
        mockHook.mockReturnValue(hookState({ fetchDownloads }));
        render(<PortalsManager />);

        fireEvent.click(screen.getByRole('button', { name: 'Download log' }));

        expect(await screen.findByText('Hero shot')).toBeInTheDocument();
        expect(screen.getByText('dana@agency.test')).toBeInTheDocument();
        expect(screen.getByText('203.0.113.4')).toBeInTheDocument();
        expect(fetchDownloads).toHaveBeenCalledWith(1);
    });

    // The token exists in readable form exactly once. If creation did not put
    // it in front of the user, it would be lost.
    it('reveals the one-time link after creating a portal', async () => {
        const create = jest.fn().mockResolvedValue({
            ...portal({ id: 2, name: 'Partner drop' }),
            token: 'sekrit',
            url: 'https://dam.test/s/portal/sekrit',
        });
        mockHook.mockReturnValue(hookState({ create }));
        global.fetch = jest.fn().mockResolvedValue({
            ok: true,
            json: async () => [{ id: 7, name: 'Autumn campaign' }],
        });

        render(<PortalsManager />);
        fireEvent.click(screen.getByRole('button', { name: 'New portal' }));

        expect(await screen.findByText('New distribution portal')).toBeInTheDocument();

        fireEvent.mouseDown(screen.getByLabelText('Collection to share'));
        fireEvent.click(await screen.findByRole('option', { name: 'Autumn campaign' }));

        fireEvent.change(screen.getByLabelText('Portal name'), { target: { value: 'Partner drop' } });
        fireEvent.click(screen.getByRole('button', { name: 'Create portal' }));

        expect(await screen.findByText('Portal created')).toBeInTheDocument();
        expect(screen.getByDisplayValue('https://dam.test/s/portal/sekrit')).toBeInTheDocument();
        expect(screen.getByText(/cannot be recovered/)).toBeInTheDocument();

        expect(create).toHaveBeenCalledWith(expect.objectContaining({
            name: 'Partner drop',
            collection_id: '7',
        }));
    });

    it('refuses to create a portal with no target', async () => {
        const create = jest.fn();
        mockHook.mockReturnValue(hookState({ create }));
        render(<PortalsManager />);

        fireEvent.click(screen.getByRole('button', { name: 'New portal' }));
        fireEvent.click(await screen.findByRole('button', { name: 'Create portal' }));

        expect(await screen.findByText('Choose a collection to share.')).toBeInTheDocument();
        expect(create).not.toHaveBeenCalled();
    });
});
