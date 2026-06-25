/**
 * GroupSearch — Autocomplete for selecting an existing group.
 *
 * Props:
 *  groups       - array of group objects (already loaded)
 *  onSelect     - called with the selected group
 *  placeholder
 *  excludeIds   - group IDs to hide entirely (e.g. self, system groups)
 *  disabledIds  - group IDs to show but disable/gray out (already added)
 */
import React, { useState } from 'react';
import { Autocomplete, TextField, Box, Typography, Chip } from '@mui/material';
import { GroupWorkOutlined, CheckCircleOutlined } from '@mui/icons-material';
import { SYSTEM_SLUGS, isSystemGroup } from '../../utils/adminUtils';

export default function GroupSearch({
  groups = [],
  onSelect,
  placeholder = 'Search groups…',
  excludeIds = [],
  disabledIds = [],
}) {
  const [value, setValue] = useState(null);

  // Show all groups except the hard-excluded ones (self, everyone system group)
  const options = groups.filter(g =>
    !excludeIds.includes(g.id) &&
    g.slug !== SYSTEM_SLUGS.EVERYONE
  );

  const handleChange = (_, group) => {
    if (group && !disabledIds.includes(group.id)) {
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
      getOptionDisabled={g => disabledIds.includes(g.id)}
      noOptionsText="No groups available"
      renderOption={(props, group) => {
        const alreadyAdded = disabledIds.includes(group.id);
        return (
          <Box
            component="li"
            {...props}
            key={group.id}
            sx={{
              gap: 1,
              opacity: alreadyAdded ? 0.5 : 1,
              cursor: alreadyAdded ? 'not-allowed' : 'pointer',
            }}
          >
            <GroupWorkOutlined fontSize="small" color={isSystemGroup(group) ? 'warning' : 'primary'} />
            <Box sx={{ flexGrow: 1 }}>
              <Typography variant="body2" fontWeight={600}>{group.name}</Typography>
              {group.description && (
                <Typography variant="caption" color="text.secondary" noWrap>
                  {group.description}
                </Typography>
              )}
            </Box>
            {alreadyAdded && (
              <Chip
                label="Already added"
                size="small"
                icon={<CheckCircleOutlined sx={{ fontSize: '0.7rem !important' }} />}
                sx={{ ml: 'auto', height: 18, fontSize: '0.6rem', bgcolor: 'action.selected' }}
              />
            )}
            {!alreadyAdded && isSystemGroup(group) && (
              <Chip label="system" size="small" color="warning" variant="outlined"
                sx={{ ml: 'auto', height: 16, fontSize: '0.6rem' }} />
            )}
          </Box>
        );
      }}
      renderInput={params => (
        <TextField {...params} placeholder={placeholder} />
      )}
    />
  );
}
