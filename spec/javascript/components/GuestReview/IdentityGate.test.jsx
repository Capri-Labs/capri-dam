import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import i18n from 'i18next';
import IdentityGate from '../../../../app/javascript/components/GuestReview/IdentityGate';
import en from '../../../../app/javascript/i18n/locales/en.json';

// The shared setup initialises i18next with an empty bundle. Load the real
// English strings so these assertions test the copy a reviewer actually sees
// rather than the key paths, which would pass even if a key were missing.
i18n.addResourceBundle('en', 'translation', en, true, true);

const setup = (props = {}) => {
    const onIdentify = jest.fn().mockResolvedValue(undefined);
    const onSkip = jest.fn();
    render(
        <IdentityGate
            open
            required={false}
            onIdentify={onIdentify}
            onSkip={onSkip}
            {...props}
        />,
    );
    return { onIdentify, onSkip };
};

describe('IdentityGate', () => {
    it('asks who is reviewing and explains why', () => {
        setup();

        expect(screen.getByText("Who's reviewing?")).toBeInTheDocument();
        expect(
            screen.getByText(/shown alongside your comments/i),
        ).toBeInTheDocument();
    });

    it('submits the trimmed email and name', async () => {
        const { onIdentify } = setup();

        fireEvent.change(screen.getByLabelText(/email address/i), {
            target: { value: '  priya@client.example  ' },
        });
        fireEvent.change(screen.getByLabelText(/your name/i), {
            target: { value: '  Priya  ' },
        });
        fireEvent.click(screen.getByRole('button', { name: /continue/i }));

        await waitFor(() =>
            expect(onIdentify).toHaveBeenCalledWith({
                email: 'priya@client.example',
                name: 'Priya',
            }),
        );
    });

    it('cannot continue without an email', () => {
        setup();

        expect(screen.getByRole('button', { name: /continue/i })).toBeDisabled();
    });

    // A reviewer who only wants to read should not be gatekept, so the prompt
    // is dismissible unless the link demands identification.
    it('offers a way out when identification is optional', () => {
        const { onSkip } = setup({ required: false });

        fireEvent.click(screen.getByRole('button', { name: /not now/i }));

        expect(onSkip).toHaveBeenCalled();
    });

    // Conversely, when the link requires identity there must be no escape
    // hatch, or the guest lands in a state where every comment is rejected
    // with no visible explanation.
    it('offers no way out when identification is required', () => {
        setup({ required: true });

        expect(screen.queryByRole('button', { name: /not now/i })).toBeNull();
    });

    it('surfaces a rejection from the server against the email field', async () => {
        const onIdentify = jest
            .fn()
            .mockRejectedValue(new Error('That domain is reserved'));
        render(
            <IdentityGate open required={false} onIdentify={onIdentify} onSkip={jest.fn()} />,
        );

        fireEvent.change(screen.getByLabelText(/email address/i), {
            target: { value: 'someone@guests.invalid' },
        });
        fireEvent.click(screen.getByRole('button', { name: /continue/i }));

        expect(
            await screen.findByText('That domain is reserved'),
        ).toBeInTheDocument();
        // The reviewer must be able to correct the value and try again.
        expect(screen.getByRole('button', { name: /continue/i })).toBeEnabled();
    });
});
