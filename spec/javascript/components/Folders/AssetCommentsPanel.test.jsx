import React from 'react';
import { render, screen, waitFor, fireEvent, act } from '@testing-library/react';
import AssetCommentsPanel from '../../../../app/javascript/components/Folders/AssetCommentsPanel';

const ASSET = { id: 'asset-uuid', title: 'Hero shot' };

const THREAD = {
    id: 'thread-1',
    asset_id: ASSET.id,
    status: 'open',
    visibility: 'internal',
    closed: false,
    origin_version: { id: 'v1', version_number: 1, action_type: 'upload' },
    created_by: { id: 1, email: 'ana@example.com', name: 'Ana Reviewer' },
    comment_count: 1,
    created_at: '2026-09-01T10:00:00Z',
    comments: [
        {
            id: 'comment-1',
            comment_thread_id: 'thread-1',
            body: 'The logo is clipped on the right edge.',
            author: { id: 1, email: 'ana@example.com', name: 'Ana Reviewer' },
            author_display_name: 'Ana Reviewer',
            asset_version: { id: 'v1', version_number: 1 },
            agent_type: 'person',
            edited: false,
            created_at: '2026-09-01T10:00:00Z',
            annotations: [{ id: 'ann-1', thread_id: 'thread-1', shape: 'rect', bbox: { x: 0.1, y: 0.1, w: 0.2, h: 0.2 } }],
            replies: [],
        },
    ],
};

const RESOLVED_THREAD = {
    ...THREAD,
    id: 'thread-2',
    status: 'resolved',
    closed: true,
    created_at: '2026-08-01T10:00:00Z',
    comments: [{ ...THREAD.comments[0], id: 'comment-2', comment_thread_id: 'thread-2', annotations: [] }],
};

/** Minimal stand-in for the useAssetComments contract. */
function buildComments(overrides = {}) {
    return {
        threads: [THREAD],
        annotations: [],
        markerLabels: { 'thread-1': '1', 'thread-2': '2' },
        unresolvedCount: 1,
        loading: false,
        saving: false,
        error: null,
        clearError: jest.fn(),
        refresh: jest.fn(),
        tool: null,
        setTool: jest.fn(),
        draft: [],
        addDraftAnnotation: jest.fn(),
        removeDraftAnnotation: jest.fn(),
        clearDraft: jest.fn(),
        selectedThreadId: null,
        setSelectedThreadId: jest.fn(),
        hoveredThreadId: null,
        setHoveredThreadId: jest.fn(),
        threadAnchor: jest.fn(),
        versionFilter: null,
        setVersionFilter: jest.fn(),
        unresolvedOnly: false,
        setUnresolvedOnly: jest.fn(),
        createThread: jest.fn().mockResolvedValue({ id: 'thread-new' }),
        createReply: jest.fn().mockResolvedValue({ id: 'comment-new' }),
        updateComment: jest.fn().mockResolvedValue({ id: 'comment-1' }),
        deleteComment: jest.fn().mockResolvedValue(null),
        resolveThread: jest.fn().mockResolvedValue({ id: 'thread-1' }),
        reopenThread: jest.fn().mockResolvedValue({ id: 'thread-2' }),
        deleteThread: jest.fn().mockResolvedValue(null),
        ...overrides,
    };
}

beforeEach(() => {
    // The panel fetches the version list for its filter, and /api/v1/users for
    // mention autocomplete. Everything else comes in through the `comments` prop.
    global.fetch = jest.fn((url) => {
        if (String(url).includes('/versions')) {
            return Promise.resolve({
                ok: true,
                json: () => Promise.resolve({ versions: [{ id: 'v1', version_number: 1 }, { id: 'v2', version_number: 2 }] }),
            });
        }
        if (String(url).includes('/api/v1/users')) {
            return Promise.resolve({
                ok: true,
                json: () => Promise.resolve({ users: [{ id: 7, username: 'jane', email: 'jane@example.com', full_name: 'Jane Doe' }] }),
            });
        }
        return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
    });
});

afterEach(() => {
    jest.resetAllMocks();
});

const renderPanel = async (comments = buildComments()) => {
    const result = render(<AssetCommentsPanel comments={comments} asset={ASSET} />);
    await waitFor(() => expect(global.fetch).toHaveBeenCalled());
    return { ...result, comments };
};

describe('AssetCommentsPanel', () => {
    it('renders existing threads with their status, version and author', async () => {
        await renderPanel();

        expect(screen.getByText('The logo is clipped on the right edge.')).toBeInTheDocument();
        expect(screen.getByText('Ana Reviewer')).toBeInTheDocument();
        expect(screen.getByText('Open')).toBeInTheDocument();
        expect(screen.getByTestId('asset-comments-unresolved-count')).toHaveTextContent('1 unresolved');
    });

    it('shows an empty state when there is nothing to review', async () => {
        await renderPanel(buildComments({ threads: [], unresolvedCount: 0 }));

        expect(screen.getByText(/No comments yet/i)).toBeInTheDocument();
    });

    it('sorts unresolved threads above closed ones', async () => {
        await renderPanel(buildComments({ threads: [RESOLVED_THREAD, THREAD] }));

        const cards = screen.getAllByTestId('asset-comment-thread');
        expect(cards[0]).toHaveTextContent('Open');
        expect(cards[1]).toHaveTextContent('Resolved');
    });

    it('disables the post button until there is something to say', async () => {
        const { comments } = await renderPanel();
        const submit = screen.getByTestId('asset-comments-submit');

        expect(submit).toBeDisabled();

        fireEvent.change(screen.getByTestId('asset-comments-body'), { target: { value: 'Looks good' } });
        expect(submit).toBeEnabled();

        await act(async () => { fireEvent.click(submit); });

        // asset_version_id is intentionally omitted so the API applies the
        // asset's active version.
        expect(comments.createThread).toHaveBeenCalledWith({ body: 'Looks good', annotations: [] });
    });

    it('arms a drawing tool and lists pending markup as removable chips', async () => {
        const comments = buildComments({ tool: 'rect', draft: [{ shape: 'rect', bbox: { x: 0, y: 0, w: 0.2, h: 0.2 } }] });
        await renderPanel(comments);

        expect(screen.getByText(/Draw on the preview/i)).toBeInTheDocument();

        fireEvent.click(screen.getByText('Clear markup'));
        expect(comments.clearDraft).toHaveBeenCalled();
    });

    it('posts pending annotations together with the comment', async () => {
        const draft = [{ shape: 'pin', bbox: { x: 0.5, y: 0.5, w: 0, h: 0 } }];
        const comments = buildComments({ draft });
        await renderPanel(comments);

        fireEvent.change(screen.getByTestId('asset-comments-body'), { target: { value: 'Here' } });
        await act(async () => { fireEvent.click(screen.getByTestId('asset-comments-submit')); });

        expect(comments.createThread).toHaveBeenCalledWith({ body: 'Here', annotations: draft });
    });

    it('offers resolve and verify on an open thread, and reopen on a closed one', async () => {
        const comments = buildComments({ threads: [THREAD, RESOLVED_THREAD] });
        await renderPanel(comments);

        await act(async () => { fireEvent.click(screen.getByRole('button', { name: /Mark verified/i })); });
        expect(comments.resolveThread).toHaveBeenCalledWith('thread-1', 'verified');

        await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Resolve' })); });
        expect(comments.resolveThread).toHaveBeenCalledWith('thread-1', 'resolved');

        await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Reopen' })); });
        expect(comments.reopenThread).toHaveBeenCalledWith('thread-2');
    });

    it('replies, optionally marking the thread addressed', async () => {
        const comments = buildComments();
        await renderPanel(comments);

        fireEvent.click(screen.getByRole('button', { name: 'Reply' }));
        fireEvent.change(screen.getByTestId('asset-comment-reply-body'), { target: { value: 'Fixed in v2' } });

        await act(async () => { fireEvent.click(screen.getByRole('button', { name: /mark addressed/i })); });

        expect(comments.createReply).toHaveBeenCalledWith('thread-1', { body: 'Fixed in v2', markAddressed: true });
    });

    it('edits a comment in place', async () => {
        const comments = buildComments();
        await renderPanel(comments);

        fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
        const field = screen.getByDisplayValue('The logo is clipped on the right edge.');
        fireEvent.change(field, { target: { value: 'The logo is clipped.' } });

        await act(async () => { fireEvent.click(screen.getByRole('button', { name: 'Save' })); });

        expect(comments.updateComment).toHaveBeenCalledWith('comment-1', 'The logo is clipped.');
    });

    it('toggles the unresolved-only filter', async () => {
        const comments = buildComments();
        await renderPanel(comments);

        fireEvent.click(screen.getByText('Unresolved only'));

        expect(comments.setUnresolvedOnly).toHaveBeenCalledWith(true);
    });

    it('surfaces an error and lets it be dismissed', async () => {
        const comments = buildComments({ error: 'You can only modify your own comments.' });
        await renderPanel(comments);

        expect(screen.getByText('You can only modify your own comments.')).toBeInTheDocument();
    });

    it('offers mention autocomplete backed by /api/v1/users', async () => {
        await renderPanel();

        fireEvent.change(screen.getByTestId('asset-comments-body'), { target: { value: 'ping @jan' } });

        await waitFor(() => expect(screen.getByText('Jane Doe')).toBeInTheDocument());

        fireEvent.click(screen.getByText('Jane Doe'));

        // A bare @handle is what MentionDetectionService matches server-side.
        expect(screen.getByTestId('asset-comments-body')).toHaveValue('ping @jane ');
    });
});
