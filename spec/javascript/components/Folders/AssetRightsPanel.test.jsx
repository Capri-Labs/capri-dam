import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import i18n from 'i18next';
import AssetRightsPanel from '../../../../app/javascript/components/Folders/AssetRightsPanel';
import en from '../../../../app/javascript/i18n/locales/en.json';

// The shared setup initialises i18next with an empty bundle. Load the real
// English strings so these assertions test the copy a user actually sees rather
// than the key paths, which would pass even if a key were missing.
i18n.addResourceBundle('en', 'translation', en, true, true);

// Prefixed `mock` so jest's hoisting of jest.mock() allows the reference.
const mockNotify = jest.fn();
jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
    useNotify: () => mockNotify,
}));

const USAGE_TERMS = {
    usage_terms: [
        { code: 'internal_only', label: 'Internal Use Only', external: false },
        { code: 'royalty_free', label: 'Royalty Free', external: true },
    ],
    default: 'internal_only',
};

const asset = (rights = {}) => ({
    id: 'abc-123',
    title: 'Hero shot',
    rights: {
        usage_terms: 'internal_only',
        usage_terms_label: 'Internal Use Only',
        license_expires_at: null,
        license_expired: false,
        externally_distributable: false,
        ...rights,
    },
});

const mockFetch = (overrides = {}) => {
    global.fetch = jest.fn((url, opts = {}) => {
        if (String(url).includes('/rights/usage_terms')) {
            return Promise.resolve({ ok: true, json: () => Promise.resolve(USAGE_TERMS) });
        }
        if (opts.method === 'PATCH') {
            return Promise.resolve(
                overrides.patch ?? { ok: true, json: () => Promise.resolve(asset()) },
            );
        }
        return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
    });
};

beforeEach(() => {
    mockNotify.mockClear();
    mockFetch();
});

describe('AssetRightsPanel', () => {
    it('loads the usage-terms vocabulary from the server rather than hard-coding it', async () => {
        render(<AssetRightsPanel asset={asset()} />);

        await waitFor(() =>
            expect(global.fetch).toHaveBeenCalledWith(
                '/api/v1/rights/usage_terms',
                expect.anything(),
            ),
        );
    });

    it('warns that an asset is not cleared for external release', async () => {
        render(<AssetRightsPanel asset={asset()} />);

        expect(await screen.findByTestId('asset-rights-internal')).toHaveTextContent(
            'Not for external release',
        );
    });

    it('flags an expired licence instead of the internal-only warning', async () => {
        render(
            <AssetRightsPanel
                asset={asset({
                    usage_terms: 'royalty_free',
                    externally_distributable: false,
                    license_expired: true,
                    license_expires_at: '2020-01-01T23:59:59Z',
                })}
            />,
        );

        expect(await screen.findByTestId('asset-rights-expired')).toHaveTextContent('Licence expired');
        expect(screen.queryByTestId('asset-rights-internal')).not.toBeInTheDocument();
    });

    it('shows no warning when the asset is distributable and current', async () => {
        render(
            <AssetRightsPanel
                asset={asset({ usage_terms: 'royalty_free', externally_distributable: true })}
            />,
        );

        expect(await screen.findByTestId('asset-rights-panel')).toBeInTheDocument();
        expect(screen.queryByTestId('asset-rights-internal')).not.toBeInTheDocument();
        expect(screen.queryByTestId('asset-rights-expired')).not.toBeInTheDocument();
    });

    it('keeps save disabled until something actually changes', async () => {
        render(<AssetRightsPanel asset={asset()} />);

        expect(await screen.findByTestId('asset-rights-save')).toBeDisabled();
    });

    it('sends a cleared expiry as null so it can be removed, not just changed', async () => {
        // An empty string would be indistinguishable from "not editing this
        // field" once the server compacts blank values, so clearing the date
        // has to be expressed explicitly.
        const onAssetUpdated = jest.fn();
        render(
            <AssetRightsPanel
                asset={asset({ license_expires_at: '2030-06-30T23:59:59Z' })}
                onAssetUpdated={onAssetUpdated}
            />,
        );

        fireEvent.change(screen.getByTestId('asset-rights-expires-at'), {
            target: { value: '' },
        });
        fireEvent.click(screen.getByTestId('asset-rights-save'));

        await waitFor(() => expect(onAssetUpdated).toHaveBeenCalled());

        const patch = global.fetch.mock.calls.find(([, o]) => o?.method === 'PATCH');
        expect(JSON.parse(patch[1].body)).toEqual({
            usage_terms: 'internal_only',
            license_expires_at: null,
        });
    });

    it('surfaces a rejection from the server instead of appearing to succeed', async () => {
        mockFetch({
            patch: {
                ok: false,
                json: () => Promise.resolve({ error: 'License expiry must be an ISO 8601 date' }),
            },
        });
        render(<AssetRightsPanel asset={asset()} />);

        fireEvent.change(screen.getByTestId('asset-rights-expires-at'), {
            target: { value: '2030-06-30' },
        });
        fireEvent.click(screen.getByTestId('asset-rights-save'));

        await waitFor(() =>
            expect(screen.getByText(/ISO 8601/)).toBeInTheDocument(),
        );
        expect(mockNotify).toHaveBeenCalledWith(expect.stringMatching(/ISO 8601/), 'error');
    });

    it('reports a failed vocabulary lookup rather than showing an empty dropdown', async () => {
        global.fetch = jest.fn(() => Promise.resolve({ ok: false, json: () => Promise.resolve({}) }));
        render(<AssetRightsPanel asset={asset()} />);

        await waitFor(() =>
            expect(screen.getByText(/Could not load the list of usage terms/)).toBeInTheDocument(),
        );
    });

    it('renders nothing without an asset', async () => {
        const { container } = render(<AssetRightsPanel asset={null} />);

        expect(container).toBeEmptyDOMElement();
    });
});
