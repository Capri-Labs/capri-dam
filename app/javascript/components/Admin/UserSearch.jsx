/**
 * UserSearch — debounced MUI Autocomplete that searches the users API.
 *
 * Props:
 *  onSelect(user) - called when a user is chosen from results
 *  placeholder    - input placeholder text
 *  excludeIds     - array of user IDs to exclude from results
 */
import React, { useState, useCallback } from 'react';
import { Autocomplete, TextField, Avatar, Box, Typography, CircularProgress } from '@mui/material';
import { apiFetch } from '../../utils/adminUtils';

export default function UserSearch({ onSelect, placeholder = 'Search by name or email…', excludeIds = [] }) {
  const [options, setOptions]   = useState([]);
  const [loading, setLoading]   = useState(false);
  const [inputValue, setInput]  = useState('');
  const [value, setValue]       = useState(null);

  // Debounce helper
  let debounceTimer = null;

  const handleInputChange = useCallback((_, newInput) => {
    setInput(newInput);
    if (debounceTimer) clearTimeout(debounceTimer);

    if (!newInput || newInput.length < 2) {
      setOptions([]);
      return;
    }

    debounceTimer = setTimeout(async () => {
      setLoading(true);
      try {
        const data = await apiFetch(`/admin/users.json?search=${encodeURIComponent(newInput)}`);
        const users = (data.users || []).filter(u => !excludeIds.includes(u.id));
        setOptions(users);
      } finally {
        setLoading(false);
      }
    }, 250);
  }, [excludeIds]);

  const handleChange = (_, user) => {
    if (user) {
      onSelect(user);
      setValue(null);
      setInput('');
      setOptions([]);
    }
  };

  return (
    <Autocomplete
      size="small"
      fullWidth
      options={options}
      loading={loading}
      value={value}
      inputValue={inputValue}
      onInputChange={handleInputChange}
      onChange={handleChange}
      filterOptions={x => x}   // server-side filtering
      getOptionLabel={u => `${u.display_name} (${u.email})`}
      isOptionEqualToValue={(opt, val) => opt.id === val.id}
      noOptionsText={inputValue.length < 2 ? 'Type to search…' : 'No users found'}
      renderOption={(props, user) => (
        <Box component="li" {...props} key={user.id} sx={{ gap: 1.5 }}>
          <Avatar src={user.avatar_url}
            sx={{ width: 28, height: 28, fontSize: '0.75rem', flexShrink: 0, bgcolor: 'primary.main' }}>
            {user.display_name?.[0]?.toUpperCase()}
          </Avatar>
          <Box sx={{ minWidth: 0 }}>
            <Typography variant="body2" fontWeight={600} noWrap>{user.display_name}</Typography>
            <Typography variant="caption" color="text.secondary" noWrap>{user.email}</Typography>
          </Box>
        </Box>
      )}
      renderInput={params => (
        <TextField
          {...params}
          placeholder={placeholder}
          InputProps={{
            ...params.InputProps,
            endAdornment: (
              <>
                {loading && <CircularProgress size={14} sx={{ mr: 1 }} />}
                {params.InputProps.endAdornment}
              </>
            )
          }}
        />
      )}
    />
  );
}

