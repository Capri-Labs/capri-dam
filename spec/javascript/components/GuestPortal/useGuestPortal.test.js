import { renderHook, act, waitFor } from '@testing-library/react';
import useGuestPortal from '../../../../app/javascript/components/GuestPortal/useGuestPortal';

const jsonResponse = (status, body) => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
});

const payload = (overrides = {}) => ({
    portal: { name: 'Agency drop', accent: '#1f6feb', require_email: false },
    guest: null,
    assets: [{ id: 'a1', title: 'Hero shot', downloadable: true }],
    ...overrides,
});

describe('useGuestPortal', () => {
    beforeEach(() => {
        global.fetch = jest.fn();
        document.head.innerHTML = '<meta name="csrf-token" content="tok-csrf">';
    });

    afterEach(() => jest.resetAllMocks());

    const load = async (response) => {
        global.fetch.mockResolvedValueOnce(response);
        const view = renderHook(() => useGuestPortal('abc'));
        await waitFor(() => expect(view.result.current.loading).toBe(false));
        return view;
    };

    it('loads the portal from the token-scoped path', async () => {
        const { result } = await load(jsonResponse(200, payload()));

        expect(global.fetch).toHaveBeenCalledWith('/s/portal/abc/assets', expect.anything());
        expect(result.current.assets).toHaveLength(1);
        expect(result.current.portal.name).toBe('Agency drop');
        expect(result.current.error).toBeNull();
    });

    it('sends the session cookie and CSRF token', async () => {
        await load(jsonResponse(200, payload()));

        const [, options] = global.fetch.mock.calls[0];
        // Passphrase clearance and guest identity both live in the session.
        expect(options.credentials).toBe('same-origin');
        expect(options.headers['X-CSRF-Token']).toBe('tok-csrf');
        expect(options.headers.Accept).toBe('application/json');
    });

    it('treats a 401 as "locked", not as an error', async () => {
        const { result } = await load(jsonResponse(401, { error: 'Passphrase required' }));

        // A protected portal is a state to render, not a failure to report.
        expect(result.current.locked).toBe(true);
        expect(result.current.error).toBeNull();
    });

    it('reports a revoked or expired link as an error', async () => {
        const { result } = await load(jsonResponse(410, { error: 'This share link is not valid.' }));

        expect(result.current.locked).toBe(false);
        expect(result.current.error).toBe('This share link is not valid.');
    });

    it('falls back to a generic message when the server sends no JSON', async () => {
        const { result } = await load({
            ok: false,
            status: 500,
            json: async () => { throw new Error('not json'); },
        });

        expect(result.current.error).toBe('Something went wrong.');
    });

    it('reloads after a successful unlock so the file list appears', async () => {
        const { result } = await load(jsonResponse(401, {}));
        expect(result.current.locked).toBe(true);

        global.fetch
            .mockResolvedValueOnce(jsonResponse(200, { ok: true }))
            .mockResolvedValueOnce(jsonResponse(200, payload()));

        await act(async () => { await result.current.unlock('hunter2'); });

        expect(global.fetch).toHaveBeenCalledWith(
            '/s/portal/abc/unlock',
            expect.objectContaining({ method: 'POST', body: JSON.stringify({ passphrase: 'hunter2' }) }),
        );
        await waitFor(() => expect(result.current.locked).toBe(false));
        expect(result.current.assets).toHaveLength(1);
    });

    it('leaves the portal locked when the passphrase is wrong', async () => {
        const { result } = await load(jsonResponse(401, {}));

        global.fetch.mockResolvedValueOnce(jsonResponse(401, { error: 'That passphrase is not correct.' }));

        await expect(act(async () => { await result.current.unlock('nope'); }))
            .rejects.toThrow('That passphrase is not correct.');
        expect(result.current.locked).toBe(true);
    });

    it('refetches after identifying so identity-gated files appear', async () => {
        const { result } = await load(jsonResponse(200, payload()));
        const guest = { id: 'g1', name: 'Priya', anonymous: false };

        global.fetch
            .mockResolvedValueOnce(jsonResponse(201, { guest }))
            .mockResolvedValueOnce(jsonResponse(200, payload({ guest })));

        await act(async () => { await result.current.identify({ email: 'p@x.example', name: 'Priya' }); });

        expect(global.fetch).toHaveBeenCalledWith(
            '/s/portal/abc/identify',
            expect.objectContaining({ method: 'POST' }),
        );
        await waitFor(() => expect(result.current.guest).toEqual(guest));
    });

    it('surfaces a rejected email instead of pretending it was accepted', async () => {
        const { result } = await load(jsonResponse(200, payload()));

        global.fetch.mockResolvedValueOnce(jsonResponse(422, { error: 'Email is invalid' }));

        await expect(act(async () => { await result.current.identify({ email: 'bad' }); }))
            .rejects.toThrow('Email is invalid');
        expect(result.current.guest).toBeNull();
    });

    it('defaults assets to an empty list when the payload omits them', async () => {
        const { result } = await load(jsonResponse(200, { portal: {}, guest: null }));

        expect(result.current.assets).toEqual([]);
    });
});
