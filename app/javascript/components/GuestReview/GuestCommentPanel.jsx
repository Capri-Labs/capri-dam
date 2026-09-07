import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Alert, Avatar, Box, Button, Chip, Divider, Stack, TextField, Typography,
} from '@mui/material';

/**
 * Colour for an author chip, derived from the display name so the same person
 * keeps the same colour across a session without the server having to assign
 * one.
 */
function avatarColor(name) {
    const palette = ['#2563eb', '#7c3aed', '#db2777', '#ea580c', '#059669', '#0891b2'];
    const hash = String(name || '?').split('').reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
    return palette[hash % palette.length];
}

function initials(name) {
    return String(name || '?').trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
}

function Comment({ comment }) {
    const { t } = useTranslation();
    const author = comment.author || {};

    return (
        <Stack direction="row" spacing={1.5} sx={{ py: 1.25 }}>
            <Avatar sx={{ width: 28, height: 28, fontSize: '0.7rem', bgcolor: avatarColor(author.display_name) }}>
                {initials(author.display_name)}
            </Avatar>
            <Box sx={{ minWidth: 0, flex: 1 }}>
                <Stack direction="row" spacing={0.75} alignItems="center" sx={{ mb: 0.25 }}>
                    <Typography variant="body2" fontWeight={600} noWrap>
                        {author.display_name}
                    </Typography>
                    {/* Tells the reviewer at a glance which remarks are their
                        own side's and which came back from the agency. */}
                    {author.kind === 'team' && (
                        <Chip label={t('guestReview.comment.team')} size="small" variant="outlined"
                              sx={{ height: 18, fontSize: '0.65rem' }} />
                    )}
                    {comment.edited && (
                        <Typography variant="caption" color="text.disabled">
                            {t('guestReview.comment.edited')}
                        </Typography>
                    )}
                </Stack>
                <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
                    {comment.body}
                </Typography>
                {(comment.replies || []).map((reply) => (
                    <Box key={reply.id} sx={{ mt: 1, pl: 1.5, borderLeft: '2px solid', borderColor: 'divider' }}>
                        <Comment comment={reply} />
                    </Box>
                ))}
            </Box>
        </Stack>
    );
}

function Thread({ thread, selected, canComment, onSelect, onHover, onReply }) {
    const { t } = useTranslation();
    const [replying, setReplying] = useState(false);
    const [body, setBody] = useState('');
    const [busy, setBusy] = useState(false);

    const submit = async () => {
        if (!body.trim()) return;
        setBusy(true);
        try {
            await onReply(thread.id, { body: body.trim() });
            setBody('');
            setReplying(false);
        } finally {
            setBusy(false);
        }
    };

    return (
        <Box
            onClick={() => onSelect(thread.id)}
            onMouseEnter={() => onHover(thread.id)}
            onMouseLeave={() => onHover(null)}
            sx={{
                p: 1.5,
                borderRadius: 2,
                cursor: 'pointer',
                border: '1px solid',
                borderColor: selected ? 'primary.main' : 'divider',
                bgcolor: selected ? 'action.hover' : 'background.paper',
                mb: 1,
            }}
        >
            {/* `closed` is the only status detail a guest gets. The internal
                open/addressed/verified/resolved ladder is an internal working
                state and would invite a client to chase each transition. */}
            {thread.closed && (
                <Chip label={t('guestReview.thread.resolved')} size="small" color="success"
                      sx={{ height: 20, fontSize: '0.68rem', mb: 0.5 }} />
            )}

            {(thread.comments || []).map((comment, index) => (
                <React.Fragment key={comment.id}>
                    {index > 0 && <Divider sx={{ my: 0.5 }} />}
                    <Comment comment={comment} />
                </React.Fragment>
            ))}

            {canComment && !thread.closed && (
                replying ? (
                    <Stack spacing={1} sx={{ mt: 1 }} onClick={(e) => e.stopPropagation()}>
                        <TextField
                            autoFocus multiline minRows={2} size="small" fullWidth
                            placeholder={t('guestReview.thread.replyPlaceholder')}
                            value={body}
                            onChange={(e) => setBody(e.target.value)}
                        />
                        <Stack direction="row" spacing={1} justifyContent="flex-end">
                            <Button size="small" color="inherit" onClick={() => setReplying(false)}>
                                {t('common.cancel')}
                            </Button>
                            <Button size="small" variant="contained" disabled={busy || !body.trim()} onClick={submit}>
                                {t('guestReview.thread.reply')}
                            </Button>
                        </Stack>
                    </Stack>
                ) : (
                    <Button
                        size="small" sx={{ mt: 0.5 }}
                        onClick={(e) => { e.stopPropagation(); setReplying(true); }}
                    >
                        {t('guestReview.thread.reply')}
                    </Button>
                )
            )}
        </Box>
    );
}

/**
 * The review conversation beside the asset.
 *
 * Guests can open threads and reply, and nothing else. Resolve, verify,
 * reopen, edit and delete are absent by construction rather than disabled —
 * an affordance that is present but greyed out invites a support request,
 * and closing feedback belongs to the people accountable for the asset.
 */
export default function GuestCommentPanel({
    threads, canComment, draftCount, selectedThreadId, onSelectThread, onHoverThread,
    onCreateThread, onReply, onClearDraft, requiresIdentity, onIdentify,
}) {
    const { t } = useTranslation();
    const [body, setBody] = useState('');
    const [busy, setBusy] = useState(false);
    const [error, setError] = useState(null);

    const submit = async () => {
        if (!body.trim()) return;
        setBusy(true);
        setError(null);
        try {
            await onCreateThread({ body: body.trim() });
            setBody('');
        } catch (e) {
            setError(e.message);
        } finally {
            setBusy(false);
        }
    };

    return (
        <Stack sx={{ height: '100%', minHeight: 0 }}>
            <Box sx={{ px: 2, py: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
                <Typography variant="subtitle2" fontWeight={700}>
                    {t('guestReview.panel.title')}
                </Typography>
                <Typography variant="caption" color="text.secondary">
                    {t('guestReview.panel.count', { count: threads.length })}
                </Typography>
            </Box>

            <Box sx={{ flex: 1, overflowY: 'auto', p: 1.5, minHeight: 0 }}>
                {threads.length === 0 && (
                    <Typography variant="body2" color="text.secondary" sx={{ textAlign: 'center', mt: 4 }}>
                        {t('guestReview.panel.empty')}
                    </Typography>
                )}
                {threads.map((thread) => (
                    <Thread
                        key={thread.id}
                        thread={thread}
                        selected={thread.id === selectedThreadId}
                        canComment={canComment}
                        onSelect={onSelectThread}
                        onHover={onHoverThread}
                        onReply={onReply}
                    />
                ))}
            </Box>

            <Box sx={{ p: 1.5, borderTop: '1px solid', borderColor: 'divider' }}>
                {requiresIdentity ? (
                    // The link wants a name against the feedback. Say so here
                    // rather than letting the reviewer type a paragraph and
                    // only then discover it will be rejected.
                    <Stack spacing={1}>
                        <Alert severity="info" sx={{ py: 0.5 }}>
                            {t('guestReview.panel.identifyPrompt')}
                        </Alert>
                        <Button variant="contained" size="small" onClick={onIdentify}>
                            {t('guestReview.panel.identifyAction')}
                        </Button>
                    </Stack>
                ) : canComment ? (
                    <Stack spacing={1}>
                        {error && <Alert severity="error" sx={{ py: 0.25 }}>{error}</Alert>}
                        {draftCount > 0 && (
                            <Stack direction="row" spacing={1} alignItems="center">
                                <Chip
                                    size="small" color="primary"
                                    label={t('guestReview.panel.draftMarks', { count: draftCount })}
                                />
                                <Button size="small" color="inherit" onClick={onClearDraft}>
                                    {t('guestReview.panel.clearMarks')}
                                </Button>
                            </Stack>
                        )}
                        <TextField
                            multiline minRows={2} size="small" fullWidth
                            placeholder={t('guestReview.panel.placeholder')}
                            value={body}
                            onChange={(e) => setBody(e.target.value)}
                        />
                        <Button
                            variant="contained" size="small"
                            disabled={busy || !body.trim()}
                            onClick={submit}
                        >
                            {t('guestReview.panel.send')}
                        </Button>
                    </Stack>
                ) : (
                    <Alert severity="info" sx={{ py: 0.5 }}>
                        {t('guestReview.panel.readOnly')}
                    </Alert>
                )}
            </Box>
        </Stack>
    );
}
