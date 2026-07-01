import React, { useMemo, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Stack,
  TextField,
  Typography,
} from '@mui/material';
import { useTranslation } from 'react-i18next';

export default function ComposeDialog({ open, onClose }) {
  const { t } = useTranslation();
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [search, setSearch] = useState('');
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(false);

  const mentionMatches = useMemo(() => {
    const match = body.match(/@([\w.-]{2,})$/);
    return match?.[1] || search;
  }, [body, search]);

  React.useEffect(() => {
    let ignore = false;
    if (!open || !mentionMatches) {
      setUsers([]);
      return undefined;
    }

    setLoading(true);
    fetch(`/api/v1/users?q=${encodeURIComponent(mentionMatches)}`)
      .then(async response => {
        if (!response.ok) throw new Error('request_failed');
        return response.json();
      })
      .then(data => {
        if (!ignore) setUsers(data.users || []);
      })
      .catch(() => {
        if (!ignore) setUsers([]);
      })
      .finally(() => {
        if (!ignore) setLoading(false);
      });

    return () => {
      ignore = true;
    };
  }, [mentionMatches, open]);

  const insertMention = user => {
    const handle = user.username || user.email?.split('@')[0];
    setBody(prev => prev.replace(/@[\w.-]*$/, `@${handle} `));
  };

  const handleClose = () => {
    setSubject('');
    setBody('');
    setSearch('');
    setUsers([]);
    onClose?.();
  };

  const canSend = subject.trim() && body.trim();

  return (
    <Dialog open={open} onClose={handleClose} fullWidth maxWidth="md">
      <DialogTitle>{t('inbox.compose', { defaultValue: 'Compose' })}</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt: 1 }}>
          <TextField
            label={t('emailEngine.subject', { defaultValue: 'Subject' })}
            value={subject}
            onChange={event => setSubject(event.target.value)}
            fullWidth
          />
          <TextField
            label={t('emailEngine.htmlBody', { defaultValue: 'HTML Body' })}
            value={body}
            onChange={event => setBody(event.target.value)}
            multiline
            minRows={8}
            fullWidth
            helperText="@mention autocomplete uses /api/v1/users"
          />
          <TextField
            label="Mention Search"
            value={search}
            onChange={event => setSearch(event.target.value)}
            fullWidth
          />
          {loading && <Typography variant="body2">Loading…</Typography>}
          {users.length > 0 && (
            <Box>
              <Typography variant="caption" color="text.secondary">
                Mention suggestions
              </Typography>
              <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap sx={{ mt: 1 }}>
                {users.map(user => (
                  <Chip
                    key={user.id}
                    label={`@${user.username || user.email}`}
                    onClick={() => insertMention(user)}
                    clickable
                  />
                ))}
              </Stack>
            </Box>
          )}
          <Alert severity="info">
            Internal delivery wiring can be attached to a future send endpoint; the compose dialog is ready for mention lookup.
          </Alert>
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={handleClose}>{t('common.cancel', { defaultValue: 'Cancel' })}</Button>
        <Button variant="contained" disabled={!canSend} onClick={handleClose}>
          {t('common.save', { defaultValue: 'Save' })}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
