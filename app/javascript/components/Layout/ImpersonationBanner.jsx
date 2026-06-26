/**
 * ImpersonationBanner — persistent danger banner shown at the very top of the
 * page whenever an admin is actively impersonating another user.
 *
 * Zero-Noise Safety: the banner is ALWAYS visible — it cannot be dismissed —
 * so the operator cannot accidentally perform a destructive action while
 * forgetting they are acting as someone else.
 *
 * Clicking "End Impersonation" sends DELETE /impersonation/stop and then
 * redirects to /admin/users.
 */
import React, { useState } from 'react';
import { Box, Typography, Button, CircularProgress, Chip } from '@mui/material';
import { WarningAmber, ExitToApp } from '@mui/icons-material';
import { apiFetch } from '../../utils/adminUtils';

export default function ImpersonationBanner({ impersonatedUser, trueUserName }) {
  const [ending, setEnding] = useState(false);

  const handleEndImpersonation = async () => {
    setEnding(true);
    try {
      await apiFetch('/impersonation/stop', { method: 'DELETE' });
      window.location.href = '/admin/users';
    } catch {
      setEnding(false);
    }
  };

  if (!impersonatedUser) return null;

  return (
    <Box
      role="alert"
      aria-live="assertive"
      sx={{
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        zIndex: 9999,
        bgcolor: '#b91c1c',
        color: '#fff',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 2,
        px: 3,
        py: 1,
        boxShadow: '0 2px 8px rgba(0,0,0,0.35)',
      }}
    >
      <WarningAmber sx={{ fontSize: 20, flexShrink: 0 }} />

      <Typography variant="body2" fontWeight={600} sx={{ flexShrink: 0 }}>
        🚨 IMPERSONATION ACTIVE
      </Typography>

      <Typography variant="body2" sx={{ opacity: 0.9 }}>
        You are acting as&nbsp;
        <strong>{impersonatedUser.display_name}</strong>
        {impersonatedUser.email && (
          <Chip
            label={impersonatedUser.email}
            size="small"
            sx={{
              ml: 1, height: 18, fontSize: '0.65rem',
              bgcolor: 'rgba(255,255,255,0.2)', color: '#fff',
            }}
          />
        )}
        . All actions will affect their real account and be logged under their name.
      </Typography>

      {trueUserName && (
        <Typography variant="caption" sx={{ opacity: 0.75, flexShrink: 0 }}>
          (You: {trueUserName})
        </Typography>
      )}

      <Button
        variant="outlined"
        size="small"
        startIcon={ending ? <CircularProgress size={14} color="inherit" /> : <ExitToApp sx={{ fontSize: 16 }} />}
        onClick={handleEndImpersonation}
        disabled={ending}
        sx={{
          ml: 2,
          flexShrink: 0,
          color: '#fff',
          borderColor: 'rgba(255,255,255,0.6)',
          fontWeight: 700,
          fontSize: '0.75rem',
          '&:hover': { borderColor: '#fff', bgcolor: 'rgba(255,255,255,0.1)' },
        }}
      >
        {ending ? 'Ending…' : 'End Impersonation'}
      </Button>
    </Box>
  );
}

