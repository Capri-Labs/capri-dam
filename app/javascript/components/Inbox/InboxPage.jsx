import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Alert,
  Avatar,
  Badge,
  Box,
  Button,
  Chip,
  CircularProgress,
  Divider,
  IconButton,
  InputAdornment,
  List,
  ListItemButton,
  ListItemText,
  Paper,
  Stack,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import {
  Archive,
  Circle,
  Delete,
  DoneAll,
  Inbox as InboxIcon,
  MarkEmailRead,
  Refresh,
  Search,
  Star,
  StarBorder,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import ComposeDialog from './ComposeDialog';

const FOLDERS = [
  { id: 'all', labelKey: 'inbox.all' },
  { id: 'unread', labelKey: 'inbox.unread' },
  { id: 'starred', labelKey: 'inbox.starred' },
  { id: 'mention', labelKey: 'inbox.mentions' },
  { id: 'workflow', labelKey: 'inbox.workflow' },
  { id: 'system', labelKey: 'inbox.system' },
];

function formatTimestamp(value) {
  if (!value) return '';
  try {
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(value));
  } catch {
    return value;
  }
}

export default function InboxPage() {
  const { t } = useTranslation();
  const [folder, setFolder] = useState('all');
  const [messages, setMessages] = useState([]);
  const [pagination, setPagination] = useState({ page: 1, total_pages: 1 });
  const [selectedMessage, setSelectedMessage] = useState(null);
  const [selectedId, setSelectedId] = useState(null);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [unreadCount, setUnreadCount] = useState(0);
  const [composeOpen, setComposeOpen] = useState(false);

  const fetchUnreadCount = useCallback(() => {
    fetch('/api/v1/inbox/unread_count')
      .then(async response => {
        if (!response.ok) throw new Error('count_failed');
        return response.json();
      })
      .then(data => setUnreadCount(data.unread_count || 0))
      .catch(() => {});
  }, []);

  const fetchMessages = useCallback(async ({ page = 1, append = false, currentFolder = folder } = {}) => {
    const params = new URLSearchParams({ page: String(page), per_page: '25' });
    if (currentFolder === 'unread') params.set('unread_only', 'true');
    if (currentFolder === 'starred') params.set('starred_only', 'true');
    if (['mention', 'workflow', 'system'].includes(currentFolder)) params.set('type', currentFolder);

    setError('');
    if (append) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }

    try {
      const response = await fetch(`/api/v1/inbox?${params.toString()}`);
      if (!response.ok) throw new Error('messages_failed');
      const data = await response.json();
      const nextMessages = data.messages || [];
      setMessages(prev => (append ? [ ...prev, ...nextMessages ] : nextMessages));
      setPagination(data.pagination || { page: 1, total_pages: 1 });
      setUnreadCount(data.unread_count || 0);
      if (!append) {
        const first = nextMessages[0] || null;
        setSelectedId(first?.id || null);
        setSelectedMessage(first);
      }
    } catch {
      setError(t('common.error', { defaultValue: 'Error' }));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [folder, t]);

  useEffect(() => {
    fetchMessages({ currentFolder: folder });
  }, [folder, fetchMessages]);

  useEffect(() => {
    fetchUnreadCount();
    const interval = window.setInterval(fetchUnreadCount, 30000);
    return () => window.clearInterval(interval);
  }, [fetchUnreadCount]);

  const filteredMessages = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return messages;

    return messages.filter(message => {
      const haystack = [message.subject, message.snippet, message.sender?.name, message.sender?.email]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();
      return haystack.includes(query);
    });
  }, [messages, search]);

  const folderCounts = useMemo(() => {
    const counts = {
      all: messages.length,
      unread: messages.filter(message => !message.read).length,
      starred: messages.filter(message => message.starred).length,
      mention: messages.filter(message => message.message_type === 'mention').length,
      workflow: messages.filter(message => message.message_type === 'workflow').length,
      system: messages.filter(message => message.message_type === 'system').length,
    };
    counts.all = Math.max(counts.all, unreadCount);
    counts.unread = Math.max(counts.unread, unreadCount);
    return counts;
  }, [messages, unreadCount]);

  const selectMessage = async message => {
    setSelectedId(message.id);
    setSelectedMessage(message);

    try {
      const response = await fetch(`/api/v1/inbox/${message.id}`);
      if (!response.ok) throw new Error('show_failed');
      const data = await response.json();
      setSelectedMessage(data.message);
      setMessages(prev => prev.map(item => (item.id === message.id ? { ...item, ...data.message, read: true } : item)));
      fetchUnreadCount();
    } catch {
      setError(t('common.error', { defaultValue: 'Error' }));
    }
  };

  const mutateMessage = async (id, action, options = {}) => {
    const response = await fetch(`/api/v1/inbox/${id}/${action}`, {
      method: options.method || 'PATCH',
      headers: { 'Content-Type': 'application/json' },
    });
    if (!response.ok) throw new Error('message_action_failed');
    return response.json();
  };

  const toggleStar = async message => {
    try {
      const data = await mutateMessage(message.id, 'star');
      setMessages(prev => prev.map(item => (item.id === message.id ? { ...item, starred: data.starred } : item)));
      setSelectedMessage(prev => prev ? { ...prev, starred: data.starred } : prev);
    } catch {
      setError(t('common.error', { defaultValue: 'Error' }));
    }
  };

  const archiveMessage = async message => {
    try {
      await mutateMessage(message.id, 'archive');
      const remaining = messages.filter(item => item.id !== message.id);
      setMessages(remaining);
      setSelectedId(remaining[0]?.id || null);
      setSelectedMessage(remaining[0] || null);
      fetchUnreadCount();
    } catch {
      setError(t('common.error', { defaultValue: 'Error' }));
    }
  };

  const deleteMessage = async message => {
    try {
      const response = await fetch(`/api/v1/inbox/${message.id}`, { method: 'DELETE' });
      if (!response.ok) throw new Error('delete_failed');
      const remaining = messages.filter(item => item.id !== message.id);
      setMessages(remaining);
      setSelectedId(remaining[0]?.id || null);
      setSelectedMessage(remaining[0] || null);
      fetchUnreadCount();
    } catch {
      setError(t('common.error', { defaultValue: 'Error' }));
    }
  };

  const markAllRead = async () => {
    try {
      await fetch('/api/v1/inbox/mark_all_read', { method: 'PATCH' });
      setMessages(prev => prev.map(message => ({ ...message, read: true })));
      setSelectedMessage(prev => prev ? { ...prev, read: true } : prev);
      setUnreadCount(0);
    } catch {
      setError(t('common.error', { defaultValue: 'Error' }));
    }
  };

  const toggleRead = async message => {
    const action = message.read ? 'mark_unread' : 'mark_read';
    try {
      const data = await mutateMessage(message.id, action);
      const read = action === 'mark_read';
      setMessages(prev => prev.map(item => (item.id === message.id ? { ...item, read } : item)));
      setSelectedMessage(prev => prev ? { ...prev, read } : prev);
      setUnreadCount(data.unread_count ?? unreadCount);
    } catch {
      setError(t('common.error', { defaultValue: 'Error' }));
    }
  };

  const loadMore = () => {
    if (pagination.page < pagination.total_pages) {
      fetchMessages({ page: pagination.page + 1, append: true, currentFolder: folder });
    }
  };

  return (
    <Box sx={{ p: 3, height: '100%', minHeight: 'calc(100vh - 120px)' }}>
      <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ mb: 3 }}>
        <Box>
          <Typography variant="h4" sx={{ fontWeight: 700 }}>
            {t('inbox.title', { defaultValue: 'Inbox' })}
          </Typography>
          <Typography variant="body2" color="text.secondary">
            {t('inbox.emptySubtitle', { defaultValue: 'Messages and mentions will appear here' })}
          </Typography>
        </Box>
        <Stack direction="row" spacing={1}>
          <Button variant="outlined" onClick={() => setComposeOpen(true)}>
            {t('inbox.compose', { defaultValue: 'Compose' })}
          </Button>
          <Button startIcon={<DoneAll />} variant="outlined" onClick={markAllRead}>
            {t('inbox.markAllRead', { defaultValue: 'Mark all read' })}
          </Button>
          <Button startIcon={refreshing ? <CircularProgress size={16} /> : <Refresh />} variant="contained" onClick={() => fetchMessages({ currentFolder: folder })}>
            {t('inbox.refresh', { defaultValue: 'Refresh' })}
          </Button>
        </Stack>
      </Stack>

      {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

      <Paper variant="outlined" sx={{ display: 'grid', gridTemplateColumns: '240px minmax(320px, 420px) 1fr', minHeight: 680, overflow: 'hidden' }}>
        <Box sx={{ borderRight: '1px solid', borderColor: 'divider', p: 2, bgcolor: 'grey.50' }}>
          <Stack spacing={1}>
            {FOLDERS.map(item => (
              <Button
                key={item.id}
                onClick={() => setFolder(item.id)}
                variant={folder === item.id ? 'contained' : 'text'}
                sx={{ justifyContent: 'space-between' }}
                endIcon={folderCounts[item.id] > 0 ? <Badge badgeContent={folderCounts[item.id]} color="error" /> : null}
              >
                {t(item.labelKey)}
              </Button>
            ))}
          </Stack>
        </Box>

        <Box sx={{ borderRight: '1px solid', borderColor: 'divider', display: 'flex', flexDirection: 'column' }}>
          <Box sx={{ p: 2 }}>
            <TextField
              fullWidth
              placeholder={t('common.search', { defaultValue: 'Search' })}
              value={search}
              onChange={event => setSearch(event.target.value)}
              slotProps={{
                input: {
                  startAdornment: (
                    <InputAdornment position="start">
                      <Search fontSize="small" />
                    </InputAdornment>
                  ),
                },
              }}
            />
          </Box>
          <Divider />
          {loading ? (
            <Stack alignItems="center" justifyContent="center" sx={{ flexGrow: 1 }}>
              <CircularProgress />
            </Stack>
          ) : filteredMessages.length === 0 ? (
            <Stack alignItems="center" justifyContent="center" spacing={1} sx={{ flexGrow: 1, p: 4 }}>
              <InboxIcon sx={{ fontSize: 48, color: 'text.disabled' }} />
              <Typography variant="h6">{t('inbox.empty', { defaultValue: 'Your inbox is empty' })}</Typography>
              <Typography variant="body2" color="text.secondary">{t('inbox.emptySubtitle')}</Typography>
            </Stack>
          ) : (
            <>
              <List sx={{ flexGrow: 1, overflowY: 'auto', p: 0 }}>
                {filteredMessages.map(message => (
                  <ListItemButton
                    key={message.id}
                    selected={selectedId === message.id}
                    onClick={() => selectMessage(message)}
                    sx={{ px: 2, py: 1.5, borderBottom: '1px solid', borderColor: 'divider', alignItems: 'flex-start' }}
                  >
                    <Stack direction="row" spacing={1.5} sx={{ width: '100%' }}>
                      <Avatar>{(message.sender?.name || 'S').charAt(0).toUpperCase()}</Avatar>
                      <Box sx={{ flexGrow: 1, minWidth: 0 }}>
                        <Stack direction="row" justifyContent="space-between" spacing={1}>
                          <Typography variant="subtitle2" sx={{ fontWeight: message.read ? 500 : 700 }} noWrap>
                            {message.subject}
                          </Typography>
                          <Typography variant="caption" color="text.secondary" sx={{ whiteSpace: 'nowrap' }}>
                            {formatTimestamp(message.created_at)}
                          </Typography>
                        </Stack>
                        <Typography variant="body2" color="text.secondary" noWrap>
                          {message.sender?.name || message.sender?.email || 'System'}
                        </Typography>
                        <Typography variant="body2" color="text.secondary" noWrap>
                          {message.snippet}
                        </Typography>
                        <Stack direction="row" spacing={1} alignItems="center" sx={{ mt: 1 }}>
                          {!message.read && <Circle sx={{ fontSize: 10, color: 'primary.main' }} />}
                          <Chip size="small" label={t(`inbox.types.${message.message_type}`, { defaultValue: message.message_type })} />
                          <IconButton size="small" onClick={event => { event.stopPropagation(); toggleStar(message); }}>
                            {message.starred ? <Star color="warning" fontSize="small" /> : <StarBorder fontSize="small" />}
                          </IconButton>
                        </Stack>
                      </Box>
                    </Stack>
                  </ListItemButton>
                ))}
              </List>
              {pagination.page < pagination.total_pages && (
                <Box sx={{ p: 2 }}>
                  <Button fullWidth variant="outlined" onClick={loadMore} disabled={refreshing}>
                    {refreshing ? <CircularProgress size={18} /> : t('common.loading', { defaultValue: 'Loading…' })}
                  </Button>
                </Box>
              )}
            </>
          )}
        </Box>

        <Box sx={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
          {selectedMessage ? (
            <>
              <Stack direction="row" justifyContent="space-between" alignItems="center" sx={{ px: 3, py: 2 }}>
                <Box>
                  <Typography variant="h5" sx={{ fontWeight: 700 }}>{selectedMessage.subject}</Typography>
                  <Typography variant="body2" color="text.secondary">
                    {selectedMessage.sender?.name || selectedMessage.sender?.email || 'System'}
                  </Typography>
                </Box>
                <Stack direction="row" spacing={1}>
                  <Tooltip title={t('inbox.archive')}>
                    <IconButton onClick={() => archiveMessage(selectedMessage)}><Archive /></IconButton>
                  </Tooltip>
                  <Tooltip title={selectedMessage.starred ? t('inbox.unstar', { defaultValue: 'Unstar' }) : t('inbox.star')}>
                    <IconButton onClick={() => toggleStar(selectedMessage)}>
                      {selectedMessage.starred ? <Star color="warning" /> : <StarBorder />}
                    </IconButton>
                  </Tooltip>
                  <Tooltip title={selectedMessage.read ? t('inbox.markUnread', { defaultValue: 'Mark as unread' }) : t('inbox.markRead')}>
                    <IconButton onClick={() => toggleRead(selectedMessage)}><MarkEmailRead /></IconButton>
                  </Tooltip>
                  <Tooltip title={t('inbox.delete')}>
                    <IconButton onClick={() => deleteMessage(selectedMessage)}><Delete /></IconButton>
                  </Tooltip>
                </Stack>
              </Stack>
              <Divider />
              <Box sx={{ p: 3, overflowY: 'auto' }}>
                {selectedMessage.body_html ? (
                  <Box dangerouslySetInnerHTML={{ __html: selectedMessage.body_html }} />
                ) : (
                  <Typography variant="body1" sx={{ whiteSpace: 'pre-wrap' }}>
                    {selectedMessage.body_text}
                  </Typography>
                )}
              </Box>
            </>
          ) : (
            <Stack alignItems="center" justifyContent="center" spacing={2} sx={{ flexGrow: 1 }}>
              <InboxIcon sx={{ fontSize: 48, color: 'text.disabled' }} />
              <Typography variant="h6">{t('inbox.noUnread', { defaultValue: 'No unread messages' })}</Typography>
            </Stack>
          )}
        </Box>
      </Paper>

      <ComposeDialog open={composeOpen} onClose={() => setComposeOpen(false)} />
    </Box>
  );
}
