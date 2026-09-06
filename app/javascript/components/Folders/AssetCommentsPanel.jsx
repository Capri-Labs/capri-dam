import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
    Alert, Avatar, Box, Button, Chip, CircularProgress, Divider, IconButton,
    List, ListItemButton, ListItemText, MenuItem, Paper, Popper, Select, Stack,
    TextField, ToggleButton, ToggleButtonGroup, Tooltip, Typography,
} from '@mui/material';
import {
    CheckCircleOutlined, ChatBubbleOutlined, Close, DeleteOutlined, EditOutlined,
    Gesture, HighlightAltOutlined, NorthEast, PlaceOutlined, RadioButtonUnchecked,
    Refresh, Remove, ReplayOutlined, Send, TaskAltOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { SHAPES, framesToTimecode } from '../../utils/annotationGeometry';

const interpolate = (template, values = {}) => template.replace(/\{\{(\w+)\}\}/g, (_, key) => values[key] ?? '');

// Drawing tools offered in the composer. Order matters: the two most-used
// markups (pin for "look here", rect for "this region") come first.
const TOOLS = [
    { shape: SHAPES.PIN, icon: PlaceOutlined, key: 'pin', fallback: 'Pin' },
    { shape: SHAPES.RECT, icon: HighlightAltOutlined, key: 'rect', fallback: 'Rectangle' },
    { shape: SHAPES.ELLIPSE, icon: RadioButtonUnchecked, key: 'ellipse', fallback: 'Ellipse' },
    { shape: SHAPES.ARROW, icon: NorthEast, key: 'arrow', fallback: 'Arrow' },
    { shape: SHAPES.LINE, icon: Remove, key: 'line', fallback: 'Line' },
    { shape: SHAPES.FREEHAND, icon: Gesture, key: 'freehand', fallback: 'Freehand' },
];

const STATUS_COLORS = {
    open: 'warning',
    addressed: 'info',
    verified: 'success',
    resolved: 'success',
};

const initials = (name = '') => name.trim().split(/\s+/).slice(0, 2).map((p) => p[0]).join('').toUpperCase() || '?';

const relativeTime = (value, translate) => {
    if (!value) return '';
    const diff = Date.now() - new Date(value).getTime();
    const minute = 60000;
    if (diff < minute) return translate('assetComments.time.justNow', 'just now');
    if (diff < 60 * minute) return translate('assetComments.time.minutesAgo', '{{count}}m ago', { count: Math.floor(diff / minute) });
    if (diff < 24 * 60 * minute) return translate('assetComments.time.hoursAgo', '{{count}}h ago', { count: Math.floor(diff / (60 * minute)) });
    if (diff < 7 * 24 * 60 * minute) return translate('assetComments.time.daysAgo', '{{count}}d ago', { count: Math.floor(diff / (24 * 60 * minute)) });
    return new Date(value).toLocaleDateString();
};

/**
 * Review conversation sidebar for a single asset.
 *
 * Pairs with {@link AnnotationOverlay}: this component owns the words, the
 * overlay owns the shapes, and both read the same `comments` object (see
 * useAssetComments) so hovering a card lights up its marker and vice versa.
 *
 * The composer deliberately lets a reviewer draw *first* and type *second* —
 * drawing is how you decide what to say — so pending shapes accumulate as
 * removable chips until the comment is posted.
 */
export default function AssetCommentsPanel({ comments, asset }) {
    const { t } = useTranslation();
    const translate = useCallback((key, defaultValue, options = {}) => {
        const result = t(key, options);
        if (result === key || (options.count != null && result === `${key}:${options.count}`)) {
            return interpolate(defaultValue, options);
        }
        return result;
    }, [t]);

    const {
        threads, markerLabels, unresolvedCount, loading, saving, error, clearError, refresh,
        tool, setTool, draft, removeDraftAnnotation, clearDraft,
        selectedThreadId, setSelectedThreadId, hoveredThreadId, setHoveredThreadId,
        versionFilter, setVersionFilter, unresolvedOnly, setUnresolvedOnly,
        createThread, createReply, updateComment, deleteComment,
        resolveThread, reopenThread, deleteThread,
    } = comments;

    const [body, setBody] = useState('');
    const [versions, setVersions] = useState([]);

    // Version list is only needed for the "filter by version" control, so it is
    // fetched here rather than threaded down from the viewer — the Versions tab
    // owns its own copy and the two are read-only.
    useEffect(() => {
        let ignore = false;
        if (!asset?.id) return undefined;

        fetch(`/api/v1/assets/${asset.id}/versions`, { credentials: 'same-origin' })
            .then((response) => (response.ok ? response.json() : { versions: [] }))
            .then((data) => { if (!ignore) setVersions(data.versions || []); })
            .catch(() => { if (!ignore) setVersions([]); });

        return () => { ignore = true; };
    }, [asset?.id]);

    const canPost = body.trim().length > 0 && !saving;

    const handlePost = async () => {
        if (!canPost) return;
        // `asset_version_id` is deliberately omitted: the API defaults to the
        // asset's active version, which is exactly what the reviewer is
        // looking at, and keeps the two from drifting apart.
        const created = await createThread({ body: body.trim(), annotations: draft });
        if (created) setBody('');
    };

    const sortedThreads = useMemo(
        () => [...threads].sort((a, b) => {
            // Unresolved work floats to the top — the panel is a to-do list
            // first and a history second.
            if (a.closed !== b.closed) return a.closed ? 1 : -1;
            return new Date(b.created_at) - new Date(a.created_at);
        }),
        [threads],
    );

    return (
        <Box data-testid="asset-comments-panel" sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <Stack direction="row" sx={{ alignItems: 'center', justifyContent: 'space-between' }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
                    {translate('assetComments.title', 'Comments & Annotations')}
                </Typography>
                <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                    <Chip
                        size="small"
                        color={unresolvedCount > 0 ? 'warning' : 'default'}
                        label={translate('assetComments.unresolvedCount', '{{count}} unresolved', { count: unresolvedCount })}
                        data-testid="asset-comments-unresolved-count"
                    />
                    <Tooltip title={translate('assetComments.actions.refresh', 'Refresh')}>
                        <span>
                            <IconButton size="small" onClick={refresh} disabled={loading}>
                                <Refresh fontSize="small" />
                            </IconButton>
                        </span>
                    </Tooltip>
                </Stack>
            </Stack>

            {error && (
                <Alert severity="error" onClose={clearError}>{error}</Alert>
            )}

            <Composer
                translate={translate}
                body={body}
                onBodyChange={setBody}
                tool={tool}
                onToolChange={setTool}
                draft={draft}
                onRemoveDraft={removeDraftAnnotation}
                onClearDraft={clearDraft}
                onPost={handlePost}
                canPost={canPost}
                saving={saving}
            />

            <Divider />

            <Stack direction="row" spacing={1} sx={{ alignItems: 'center', flexWrap: 'wrap', gap: 1 }}>
                <Chip
                    size="small"
                    label={translate('assetComments.filters.unresolvedOnly', 'Unresolved only')}
                    color={unresolvedOnly ? 'primary' : 'default'}
                    variant={unresolvedOnly ? 'filled' : 'outlined'}
                    onClick={() => setUnresolvedOnly(!unresolvedOnly)}
                />
                <Select
                    size="small"
                    value={versionFilter || 'all'}
                    onChange={(e) => setVersionFilter(e.target.value === 'all' ? null : e.target.value)}
                    sx={{ minWidth: 160, '& .MuiSelect-select': { py: 0.5 } }}
                    data-testid="asset-comments-version-filter"
                >
                    <MenuItem value="all">{translate('assetComments.filters.allVersions', 'All versions')}</MenuItem>
                    {versions.map((version) => (
                        <MenuItem key={version.id} value={version.id}>
                            {translate('assetComments.filters.version', 'Version {{number}}', { number: version.version_number })}
                        </MenuItem>
                    ))}
                </Select>
            </Stack>

            {loading && threads.length === 0 ? (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}><CircularProgress size={24} /></Box>
            ) : sortedThreads.length === 0 ? (
                <Box sx={{ textAlign: 'center', py: 5, color: 'text.secondary' }}>
                    <ChatBubbleOutlined sx={{ fontSize: 40, opacity: 0.4, mb: 1 }} />
                    <Typography variant="body2">
                        {translate('assetComments.empty', 'No comments yet. Draw on the preview or type below to start a review thread.')}
                    </Typography>
                </Box>
            ) : (
                <Stack spacing={1.5}>
                    {sortedThreads.map((thread) => (
                        <ThreadCard
                            key={thread.id}
                            thread={thread}
                            markerLabel={markerLabels[thread.id]}
                            translate={translate}
                            selected={selectedThreadId === thread.id}
                            hovered={hoveredThreadId === thread.id}
                            onSelect={() => setSelectedThreadId(selectedThreadId === thread.id ? null : thread.id)}
                            onHover={setHoveredThreadId}
                            saving={saving}
                            onReply={createReply}
                            onUpdateComment={updateComment}
                            onDeleteComment={deleteComment}
                            onResolve={resolveThread}
                            onReopen={reopenThread}
                            onDeleteThread={deleteThread}
                        />
                    ))}
                </Stack>
            )}

            {asset?.id && (
                <Typography variant="caption" color="text.secondary">
                    {translate('assetComments.hint.annotationsFollowVersions', 'Threads stay with the asset across versions; each comment records the version it was written against.')}
                </Typography>
            )}
        </Box>
    );
}

/** New-thread composer: markup toolbar, pending shapes, mention-aware input. */
function Composer({
    translate, body, onBodyChange, tool, onToolChange, draft,
    onRemoveDraft, onClearDraft, onPost, canPost, saving,
}) {
    return (
        <Paper variant="outlined" sx={{ p: 1.5, borderRadius: 2 }} data-testid="asset-comments-composer">
            <ToggleButtonGroup
                exclusive
                size="small"
                value={tool}
                onChange={(_, value) => onToolChange(value)}
                sx={{ mb: 1, flexWrap: 'wrap' }}
                data-testid="annotation-tool-group"
            >
                {TOOLS.map(({ shape, icon: Icon, key, fallback }) => (
                    <ToggleButton key={shape} value={shape} sx={{ px: 1 }}>
                        <Tooltip title={translate(`assetComments.tools.${key}`, fallback)}>
                            <Icon fontSize="small" />
                        </Tooltip>
                    </ToggleButton>
                ))}
            </ToggleButtonGroup>

            {tool && (
                <Typography variant="caption" color="primary" sx={{ display: 'block', mb: 1 }}>
                    {translate('assetComments.tools.drawHint', 'Draw on the preview to place your markup.')}
                </Typography>
            )}

            {draft.length > 0 && (
                <Stack direction="row" spacing={0.5} sx={{ mb: 1, flexWrap: 'wrap', gap: 0.5 }}>
                    {draft.map((annotation, index) => (
                        <Chip
                            key={`${annotation.shape}-${index}`}
                            size="small"
                            color="primary"
                            variant="outlined"
                            label={translate(`assetComments.tools.${annotation.shape}`, annotation.shape)}
                            onDelete={() => onRemoveDraft(index)}
                            deleteIcon={<Close fontSize="small" />}
                        />
                    ))}
                    <Chip
                        size="small"
                        variant="outlined"
                        label={translate('assetComments.actions.clearMarkup', 'Clear markup')}
                        onClick={onClearDraft}
                    />
                </Stack>
            )}

            <MentionTextField
                value={body}
                onChange={onBodyChange}
                placeholder={translate('assetComments.composer.placeholder', 'Add a comment… use @ to mention someone')}
                translate={translate}
                testId="asset-comments-body"
            />

            <Stack direction="row" sx={{ justifyContent: 'flex-end', mt: 1 }}>
                <Button
                    variant="contained"
                    size="small"
                    startIcon={saving ? <CircularProgress size={14} color="inherit" /> : <Send fontSize="small" />}
                    disabled={!canPost}
                    onClick={onPost}
                    data-testid="asset-comments-submit"
                >
                    {translate('assetComments.actions.post', 'Comment')}
                </Button>
            </Stack>
        </Paper>
    );
}

/**
 * Multiline input with `@mention` autocomplete.
 *
 * The lookup hits the same `/api/v1/users` endpoint the Inbox composer uses,
 * and inserts a bare `@handle` — that exact form is what
 * MentionDetectionService::MENTION_PATTERN matches server-side, so what the
 * reviewer picks here is what actually generates the notification.
 */
function MentionTextField({ value, onChange, placeholder, translate, testId, autoFocus = false }) {
    const [users, setUsers] = useState([]);
    const anchorRef = useRef(null);

    const query = useMemo(() => value.match(/@([\w.-]{1,})$/)?.[1] ?? null, [value]);

    useEffect(() => {
        let ignore = false;
        if (query == null || query.length < 1) {
            setUsers([]);
            return undefined;
        }

        fetch(`/api/v1/users?q=${encodeURIComponent(query)}`, { credentials: 'same-origin' })
            .then((response) => (response.ok ? response.json() : { users: [] }))
            .then((data) => { if (!ignore) setUsers((data.users || []).slice(0, 6)); })
            .catch(() => { if (!ignore) setUsers([]); });

        return () => { ignore = true; };
    }, [query]);

    const insert = (user) => {
        const handle = user.username || user.email?.split('@')[0];
        onChange(value.replace(/@[\w.-]*$/, `@${handle} `));
        setUsers([]);
    };

    return (
        <Box ref={anchorRef}>
            <TextField
                fullWidth
                multiline
                minRows={2}
                maxRows={8}
                size="small"
                value={value}
                autoFocus={autoFocus}
                onChange={(e) => onChange(e.target.value)}
                placeholder={placeholder}
                slotProps={{ htmlInput: { 'data-testid': testId } }}
            />
            <Popper open={users.length > 0} anchorEl={anchorRef.current} placement="bottom-start" style={{ zIndex: 1500 }}>
                <Paper variant="outlined" sx={{ minWidth: 220, maxHeight: 220, overflowY: 'auto' }}>
                    <List dense disablePadding>
                        {users.map((user) => (
                            <ListItemButton key={user.id} onClick={() => insert(user)}>
                                <ListItemText
                                    primary={user.full_name || user.email}
                                    secondary={user.email}
                                    slotProps={{ primary: { variant: 'body2' }, secondary: { variant: 'caption' } }}
                                />
                            </ListItemButton>
                        ))}
                    </List>
                </Paper>
            </Popper>
            {query != null && users.length === 0 && (
                <Typography variant="caption" color="text.secondary">
                    {translate('assetComments.composer.mentionHint', 'Keep typing to find someone to mention.')}
                </Typography>
            )}
        </Box>
    );
}

/** One review thread: root comment, replies, lifecycle actions. */
function ThreadCard({
    thread, markerLabel, translate, selected, hovered, onSelect, onHover,
    saving, onReply, onUpdateComment, onDeleteComment,
    onResolve, onReopen, onDeleteThread,
}) {
    const [replyBody, setReplyBody] = useState('');
    const [replying, setReplying] = useState(false);

    const rootComments = thread.comments || [];

    const submitReply = async (markAddressed = false) => {
        if (!replyBody.trim()) return;
        const created = await onReply(thread.id, {
            body: replyBody.trim(),
            markAddressed,
        });
        if (created) {
            setReplyBody('');
            setReplying(false);
        }
    };

    return (
        <Paper
            variant="outlined"
            data-testid="asset-comment-thread"
            onMouseEnter={() => onHover(thread.id)}
            onMouseLeave={() => onHover(null)}
            sx={{
                p: 1.5,
                borderRadius: 2,
                borderColor: selected || hovered ? 'primary.main' : 'divider',
                bgcolor: thread.closed ? '#f8fafc' : '#ffffff',
                transition: 'border-color 120ms ease',
            }}
        >
            <Stack direction="row" spacing={1} sx={{ alignItems: 'center', mb: 1 }}>
                {markerLabel && (
                    <Tooltip title={translate('assetComments.thread.showOnPreview', 'Highlight on the preview')}>
                        <Chip
                            size="small"
                            label={markerLabel}
                            onClick={onSelect}
                            color={selected ? 'primary' : 'default'}
                            sx={{ fontWeight: 700, minWidth: 28 }}
                        />
                    </Tooltip>
                )}
                <Chip
                    size="small"
                    variant="outlined"
                    color={STATUS_COLORS[thread.status] || 'default'}
                    label={translate(`assetComments.status.${thread.status}`, thread.status)}
                />
                {thread.origin_version?.version_number != null && (
                    <Chip
                        size="small"
                        variant="outlined"
                        label={translate('assetComments.thread.openedOnVersion', 'v{{number}}', { number: thread.origin_version.version_number })}
                    />
                )}
                <Box sx={{ flexGrow: 1 }} />
                {thread.closed ? (
                    <Tooltip title={translate('assetComments.actions.reopen', 'Reopen')}>
                        <span>
                            <IconButton size="small" disabled={saving} onClick={() => onReopen(thread.id)}>
                                <ReplayOutlined fontSize="small" />
                            </IconButton>
                        </span>
                    </Tooltip>
                ) : (
                    <>
                        <Tooltip title={translate('assetComments.actions.verify', 'Mark verified — the fix is confirmed')}>
                            <span>
                                <IconButton size="small" disabled={saving} onClick={() => onResolve(thread.id, 'verified')}>
                                    <TaskAltOutlined fontSize="small" />
                                </IconButton>
                            </span>
                        </Tooltip>
                        <Tooltip title={translate('assetComments.actions.resolve', 'Resolve')}>
                            <span>
                                <IconButton size="small" disabled={saving} onClick={() => onResolve(thread.id, 'resolved')}>
                                    <CheckCircleOutlined fontSize="small" />
                                </IconButton>
                            </span>
                        </Tooltip>
                    </>
                )}
                <Tooltip title={translate('assetComments.actions.deleteThread', 'Delete thread')}>
                    <span>
                        <IconButton size="small" disabled={saving} onClick={() => onDeleteThread(thread.id)}>
                            <DeleteOutlined fontSize="small" />
                        </IconButton>
                    </span>
                </Tooltip>
            </Stack>

            <Stack spacing={1.25}>
                {rootComments.map((comment) => (
                    <CommentRow
                        key={comment.id}
                        comment={comment}
                        translate={translate}
                        saving={saving}
                        onUpdate={onUpdateComment}
                        onDelete={onDeleteComment}
                    />
                ))}
            </Stack>

            {replying ? (
                <Box sx={{ mt: 1.5 }}>
                    <MentionTextField
                        value={replyBody}
                        onChange={setReplyBody}
                        autoFocus
                        placeholder={translate('assetComments.reply.placeholder', 'Reply…')}
                        translate={translate}
                        testId="asset-comment-reply-body"
                    />
                    <Stack direction="row" spacing={1} sx={{ justifyContent: 'flex-end', mt: 1 }}>
                        <Button size="small" onClick={() => { setReplying(false); setReplyBody(''); }}>
                            {translate('assetComments.actions.cancel', 'Cancel')}
                        </Button>
                        {!thread.closed && (
                            <Button size="small" disabled={!replyBody.trim() || saving} onClick={() => submitReply(true)}>
                                {translate('assetComments.actions.replyAndMarkAddressed', 'Reply & mark addressed')}
                            </Button>
                        )}
                        <Button size="small" variant="contained" disabled={!replyBody.trim() || saving} onClick={() => submitReply(false)}>
                            {translate('assetComments.actions.reply', 'Reply')}
                        </Button>
                    </Stack>
                </Box>
            ) : (
                <Button size="small" sx={{ mt: 1 }} onClick={() => setReplying(true)}>
                    {translate('assetComments.actions.reply', 'Reply')}
                </Button>
            )}
        </Paper>
    );
}

/** A single comment plus its (single level of) replies. */
function CommentRow({ comment, translate, saving, onUpdate, onDelete, nested = false }) {
    const [editing, setEditing] = useState(false);
    const [editBody, setEditBody] = useState(comment.body);

    const submitEdit = async () => {
        if (!editBody.trim()) return;
        const updated = await onUpdate(comment.id, editBody.trim());
        if (updated) setEditing(false);
    };

    const authorName = comment.author_display_name || comment.author?.name || comment.author?.email;
    const isAgent = comment.agent_type === 'software';

    return (
        <Box sx={nested ? { pl: 3, borderLeft: '2px solid #e2e8f0' } : undefined} data-testid="asset-comment">
            <Stack direction="row" spacing={1}>
                <Avatar sx={{ width: 26, height: 26, fontSize: 11, bgcolor: isAgent ? '#7c3aed' : '#0ea5e9' }}>
                    {initials(authorName)}
                </Avatar>
                <Box sx={{ flexGrow: 1, minWidth: 0 }}>
                    <Stack direction="row" spacing={0.75} sx={{ alignItems: 'center', flexWrap: 'wrap' }}>
                        <Typography variant="body2" sx={{ fontWeight: 700 }}>{authorName}</Typography>
                        {isAgent && (
                            <Chip
                                size="small"
                                color="secondary"
                                variant="outlined"
                                sx={{ height: 18, fontSize: 10 }}
                                label={translate('assetComments.comment.aiSuggestion', 'AI')}
                            />
                        )}
                        <Typography variant="caption" color="text.secondary">{relativeTime(comment.created_at, translate)}</Typography>
                        {comment.edited && (
                            <Typography variant="caption" color="text.secondary">
                                {translate('assetComments.comment.edited', '(edited)')}
                            </Typography>
                        )}
                        {comment.asset_version?.version_number != null && (
                            <Chip
                                size="small"
                                variant="outlined"
                                sx={{ height: 18, fontSize: 10 }}
                                label={translate('assetComments.thread.openedOnVersion', 'v{{number}}', { number: comment.asset_version.version_number })}
                            />
                        )}
                    </Stack>

                    {editing ? (
                        <Box sx={{ mt: 0.5 }}>
                            <TextField
                                fullWidth
                                multiline
                                size="small"
                                value={editBody}
                                onChange={(e) => setEditBody(e.target.value)}
                            />
                            <Stack direction="row" spacing={1} sx={{ justifyContent: 'flex-end', mt: 0.5 }}>
                                <Button size="small" onClick={() => { setEditing(false); setEditBody(comment.body); }}>
                                    {translate('assetComments.actions.cancel', 'Cancel')}
                                </Button>
                                <Button size="small" variant="contained" disabled={saving} onClick={submitEdit}>
                                    {translate('assetComments.actions.save', 'Save')}
                                </Button>
                            </Stack>
                        </Box>
                    ) : (
                        <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word', mt: 0.25 }}>
                            {comment.body}
                        </Typography>
                    )}

                    <AnnotationSummary annotations={comment.annotations} translate={translate} />
                </Box>

                {!editing && (
                    <Stack direction="row">
                        <Tooltip title={translate('assetComments.actions.edit', 'Edit')}>
                            <span>
                                <IconButton size="small" disabled={saving} onClick={() => setEditing(true)}>
                                    <EditOutlined sx={{ fontSize: 15 }} />
                                </IconButton>
                            </span>
                        </Tooltip>
                        <Tooltip title={translate('assetComments.actions.delete', 'Delete')}>
                            <span>
                                <IconButton size="small" disabled={saving} onClick={() => onDelete(comment.id)}>
                                    <DeleteOutlined sx={{ fontSize: 15 }} />
                                </IconButton>
                            </span>
                        </Tooltip>
                    </Stack>
                )}
            </Stack>

            {(comment.replies || []).length > 0 && (
                <Stack spacing={1.25} sx={{ mt: 1.25 }}>
                    {comment.replies.map((reply) => (
                        <CommentRow
                            key={reply.id}
                            comment={reply}
                            translate={translate}
                            saving={saving}
                            onUpdate={onUpdate}
                            onDelete={onDelete}
                            nested
                        />
                    ))}
                </Stack>
            )}
        </Box>
    );
}

/** Compact description of what a comment is anchored to. */
function AnnotationSummary({ annotations = [], translate }) {
    if (annotations.length === 0) return null;

    return (
        <Stack direction="row" spacing={0.5} sx={{ mt: 0.5, flexWrap: 'wrap', gap: 0.5 }}>
            {annotations.map((annotation) => {
                const video = annotation.video;
                const timecode = video?.start_timecode
                    || framesToTimecode(video?.start_frame, video?.fps, video?.drop_frame);

                return (
                    <Chip
                        key={annotation.id}
                        size="small"
                        variant="outlined"
                        sx={{ height: 20, fontSize: 10 }}
                        label={timecode
                            ? `${translate(`assetComments.tools.${annotation.shape}`, annotation.shape)} · ${timecode}`
                            : translate(`assetComments.tools.${annotation.shape}`, annotation.shape)}
                    />
                );
            })}
        </Stack>
    );
}

export { MentionTextField };
