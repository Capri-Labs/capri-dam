/**
 * GroupSearch — Autocomplete for selecting an existing group.
 *
 * Props:
 *  groups       - array of group objects (already loaded)
 *  onSelect     - called with the selected group
 *  placeholder
 *  excludeIds   - group IDs to exclude (e.g. the current group, system groups)
 */
import React, { useState } from 'react';
import { Autocomplete, TextField, Box, Typography, Chip } from '@mui/material';
import { GroupWorkOutlined } from '@mui/icons-material';
import { SYSTEM_SLUGS, isSystemGroup } from '../../utils/adminUtils';

export default function GroupSearch({ groups = [], onSelect, placeholder = 'Search groups…', excludeIds = [] }) {
  const [value, setValue] = useState(null);

  const options = groups.filter(g =>
    !excludeIds.includes(g.id) &&
    g.slug !== SYSTEM_SLUGS.EVERYONE  // don't allow nesting inside 'everyone'
  );

  const handleChange = (_, group) => {
    if (group) {
      onSelect(group);
      setValue(null);
    }
  };

  return (
    <Autocomplete
      size="small"
      fullWidth
      options={options}
      value={value}
      onChange={handleChange}
      getOptionLabel={g => g.name}
      isOptionEqualToValue={(a, b) => a.id === b.id}
      noOptionsText="No groups available"
      renderOption={(props, group) => (
        <Box component="li" {...props} key={group.id} sx={{ gap: 1 }}>
          <GroupWorkOutlined fontSize="small" color={isSystemGroup(group) ? 'warning' : 'primary'} />
          <Box>
            <Typography variant="body2" fontWeight={600}>{group.name}</Typography>
            {group.description && (
              <Typography variant="caption" color="text.secondary" noWrap>
                {group.description}
              </Typography>
            )}
          </Box>
          {isSystemGroup(group) && (
            <Chip label="system" size="small" color="warning" variant="outlined"
              sx={{ ml: 'auto', height: 16, fontSize: '0.6rem' }} />
          )}
        </Box>
      )}
      renderInput={params => (
        <TextField {...params} placeholder={placeholder} />
      )}
    />
  );
}

