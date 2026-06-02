import React from 'react';
import { Box, Typography, Checkbox, FormControlLabel, FormGroup, Divider } from '@mui/material';
import { FilterAlt } from '@mui/icons-material';

export default function AssetFilterBar({ facets, onFilterChange }) {
    // Read the current URL parameters to determine what is already checked
    const params = new URLSearchParams(window.location.search);

    const isChecked = (category, value) => {
        const currentVals = params.get(category);
        if (!currentVals) return false;
        return currentVals.split(',').includes(value);
    };

    const handleToggle = (category, value) => {
        const currentVals = params.get(category) ? params.get(category).split(',') : [];
        let newVals;

        if (currentVals.includes(value)) {
            // Remove it
            newVals = currentVals.filter(v => v !== value);
        } else {
            // Add it
            newVals = [...currentVals, value];
        }

        onFilterChange(category, newVals.join(','));
    };

    return (
        <Box sx={{ width: 280, flexShrink: 0, borderRight: '1px solid #e2e8f0', bgcolor: '#ffffff', overflowY: 'auto', p: 3, display: { xs: 'none', md: 'block' } }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 3 }}>
                <FilterAlt sx={{ color: '#64748b' }} />
                <Typography variant="subtitle1" fontWeight="600" color="#1e293b">
                    Filters
                </Typography>
            </Box>
            <Divider sx={{ mb: 3 }} />

            {/* Dynamically render facet groups based on API response */}
            {Object.keys(facets || {}).map(category => (
                <Box key={category} sx={{ mb: 4 }}>
                    <Typography variant="overline" sx={{ fontWeight: 700, color: '#64748b', display: 'block', mb: 1 }}>
                        {category.replace('_', ' ')}
                    </Typography>
                    <FormGroup>
                        {facets[category].map(option => (
                            <FormControlLabel
                                key={option}
                                control={
                                    <Checkbox
                                        size="small"
                                        checked={isChecked(category, option)}
                                        onChange={() => handleToggle(category, option)}
                                        sx={{ color: '#cbd5e1', '&.Mui-checked': { color: '#8b5cf6' } }}
                                    />
                                }
                                label={<Typography variant="body2" sx={{ color: '#334155' }}>{option}</Typography>}
                            />
                        ))}
                    </FormGroup>
                </Box>
            ))}
        </Box>
    );
}