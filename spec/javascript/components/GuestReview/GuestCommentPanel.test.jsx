import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import i18n from 'i18next';
import GuestCommentPanel from '../../../../app/javascript/components/GuestReview/GuestCommentPanel';
import en from '../../../../app/javascript/i18n/locales/en.json';

// The shared setup initialises i18next with an empty bundle. Load the real
// English strings so these assertions test the copy a reviewer actually sees
// rather than the key paths, which would pass even if a key were missing.
i18n.addResourceBundle('en', 'translation', en, true, true);

const GUEST_THREAD = {
    id: 'thread-1',
    closed: false,
    comments: [
        {
            id: 'c-1',
            body: 'The logo is clipped on the right edge.',
            author: { display_name: 'Priya', kind: 'guest' },
            edited: false,
            annotations: [],
            replies: [],
        },
    ],
};

const TEAM_THREAD = {
    id: 'thread-2',
    closed: true,
    comments: [
        {
            id: 'c-2',
            body: 'Fixed in the new master.',
            author: { display_name: 'Capri team', kind: 'team' },
            edited: true,
            annotations: [],
            replies: [
                { id: 'c-3', body: 'Confirmed.', author: { display_name: 'Priya', kind: 'guest' }, annotations: [], replies: [] },
            ],
        },
    ],
};

function renderPanel(props = {}) {
    return render(
        <GuestCommentPanel
            threads={[GUEST_THREAD, TEAM_THREAD]}
            canComment
            draftCount={0}
            selectedThreadId={null}
            onSelectThread={jest.fn()}
            onHoverThread={jest.fn()}
            onCreateThread={jest.fn()}
            onReply={jest.fn()}
            onClearDraft={jest.fn()}
            requiresIdentity={false}
            onIdentify={jest.fn()}
            {...props}
        />,
    );
}

describe('GuestCommentPanel', () => {
    it('renders threads, replies and the team badge', () => {
        renderPanel();

        expect(screen.getByText('The logo is clipped on the right edge.')).toBeInTheDocument();
        expect(screen.getByText('Fixed in the new master.')).toBeInTheDocument();
        expect(screen.getByText('Confirmed.')).toBeInTheDocument();
        expect(screen.getByText('Team')).toBeInTheDocument();
    });

    it('never offers resolve, verify, reopen, edit or delete', () => {
        renderPanel();

        ['Resolve', 'Verify', 'Reopen', 'Edit', 'Delete'].forEach((label) => {
            expect(screen.queryByRole('button', { name: new RegExp(label, 'i') })).toBeNull();
        });
    });

    it('does not offer a reply box on a closed thread', () => {
        renderPanel({ threads: [TEAM_THREAD] });

        expect(screen.getByText('Resolved')).toBeInTheDocument();
        expect(screen.queryByRole('button', { name: /reply/i })).toBeNull();
    });

    it('posts a new note and clears the box', async () => {
        const onCreateThread = jest.fn().mockResolvedValue({ id: 'thread-9' });
        renderPanel({ onCreateThread });

        const box = screen.getByPlaceholderText('Add a note…');
        fireEvent.change(box, { target: { value: 'Crop tighter please' } });
        fireEvent.click(screen.getByRole('button', { name: /post note/i }));

        await waitFor(() => expect(onCreateThread).toHaveBeenCalledWith({ body: 'Crop tighter please' }));
        await waitFor(() => expect(box.value).toBe(''));
    });

    it('shows a server error instead of losing the note', async () => {
        const onCreateThread = jest.fn().mockRejectedValue(new Error('You are commenting too quickly.'));
        renderPanel({ onCreateThread });

        fireEvent.change(screen.getByPlaceholderText('Add a note…'), { target: { value: 'Hello' } });
        fireEvent.click(screen.getByRole('button', { name: /post note/i }));

        expect(await screen.findByText('You are commenting too quickly.')).toBeInTheDocument();
        // The typed text survives the failure.
        expect(screen.getByPlaceholderText('Add a note…').value).toBe('Hello');
    });

    it('asks for a name before commenting when the link requires one', () => {
        renderPanel({ requiresIdentity: true, canComment: false });

        expect(screen.getByText(/tell us who you are/i)).toBeInTheDocument();
        expect(screen.queryByPlaceholderText('Add a note…')).toBeNull();
    });

    it('says so when the link is view-only', () => {
        renderPanel({ canComment: false, requiresIdentity: false });

        expect(screen.getByText('This link is view-only.')).toBeInTheDocument();
        expect(screen.queryByPlaceholderText('Add a note…')).toBeNull();
    });

    it('reports pending marks and can clear them', () => {
        const onClearDraft = jest.fn();
        renderPanel({ draftCount: 2, onClearDraft });

        expect(screen.getByText('2 marks ready')).toBeInTheDocument();
        fireEvent.click(screen.getByRole('button', { name: /clear/i }));
        expect(onClearDraft).toHaveBeenCalled();
    });

    it('replies into a thread', async () => {
        const onReply = jest.fn().mockResolvedValue({});
        renderPanel({ threads: [GUEST_THREAD], onReply });

        fireEvent.click(screen.getByRole('button', { name: /^reply$/i }));
        fireEvent.change(screen.getByPlaceholderText('Write a reply…'), { target: { value: 'Agreed' } });
        fireEvent.click(screen.getByRole('button', { name: /^reply$/i }));

        await waitFor(() => expect(onReply).toHaveBeenCalledWith('thread-1', { body: 'Agreed' }));
    });
});
