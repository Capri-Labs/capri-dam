import React, { useState } from 'react';
import {
    Box, Button, Typography, Menu, MenuItem,
    ToggleButton, ToggleButtonGroup, Divider, IconButton, Tooltip, Checkbox, ListItemText
} from '@mui/material';
import {
    KeyboardArrowDown, ViewModule, ViewList,
    FilterAltOutlined, Sort, Search, ContentCopy
} from '@mui/icons-material';

// Helper component for uniform dropdown buttons
const FilterDropdown = ({ label, options }) => {
    const [anchorEl, setAnchorEl] = useState(null);
    const [selected, setSelected] = useState([]);

    const handleClick = (event) => setAnchorEl(event.currentTarget);
    const handleClose = () => setAnchorEl(null);

    const handleToggle = (option) => {
        setSelected(prev =>
            prev.includes(option) ? prev.filter(item => item !== option) : [...prev, option]
        );
    };

    return (
        <Box>
            <Button
                color="inherit"
                onClick={handleClick}
                endIcon={<KeyboardArrowDown sx={{ color: '#94a3b8' }} />}
                sx={{
                    textTransform: 'none',
                    fontWeight: selected.length > 0 ? 600 : 500,
                    color: selected.length > 0 ? '#4f46e5' : '#475569',
                    px: 1.5,
                    minWidth: 'auto'
                }}
            >
                {label} {selected.length > 0 && `(${selected.length})`}
            </Button>
            <Menu
                anchorEl={anchorEl}
                open={Boolean(anchorEl)}
                onClose={handleClose}
                PaperProps={{ elevation: 3, sx: { mt: 1, minWidth: 200, borderRadius: 2 } }}
            >
                {options.map((option) => (
                    <MenuItem key={option} onClick={() => handleToggle(option)} sx={{ py: 0 }}>
                        <Checkbox size="small" checked={selected.includes(option)} />
                        <ListItemText primary={<Typography variant="body2">{option}</Typography>} />
                    </MenuItem>
                ))}
            </Menu>
        </Box>
    );
};

export default function AssetFilterBar({ resultCount, viewLayout, setViewLayout }) {
    const [sortAnchor, setSortAnchor] = useState(null);
    const [sortConfig, setSortConfig] = useState('Date added');

    return (
        <Box sx={{
            display: 'flex', flexDirection: 'column',
            bgcolor: '#f8fafc', borderTop: '1px solid #e2e8f0', borderBottom: '1px solid #e2e8f0',
            mb: 3
        }}>
            {/* TOP ROW: The Faceted Filters */}
            <Box sx={{
                display: 'flex', flexWrap: 'wrap', alignItems: 'center', py: 1, px: 1,
                borderBottom: '1px solid #e2e8f0'
            }}>
                <FilterDropdown label="Asset Type" options={['Images', 'Videos', 'Documents', 'Audio']} />
                <FilterDropdown label="People" options={['Internal', 'External Agency', 'Contractors']} />
                <FilterDropdown label="Campaigns" options={['Summer 2026', 'Holiday Promo', 'Brand Refresh']} />
                <FilterDropdown label="Channel" options={['Social Media', 'Print', 'Web', 'Email']} />
                <FilterDropdown label="Region" options={['EMEA', 'North America', 'APAC']} />
                <FilterDropdown label="Usage Rights" options={['Commercial', 'Editorial', 'Internal Only']} />

                <Divider orientation="vertical" flexItem sx={{ mx: 1, my: 1 }} />

                <Button
                    color="inherit"
                    startIcon={<FilterAltOutlined sx={{ color: '#94a3b8' }} />}
                    sx={{ textTransform: 'none', color: '#475569', fontWeight: 500 }}
                >
                    Advanced
                </Button>

                {/* Right Side Actions */}
                <Box sx={{ ml: 'auto', display: 'flex', alignItems: 'center', gap: 1 }}>
                    <Button color="inherit" endIcon={<KeyboardArrowDown />} sx={{ textTransform: 'none', color: '#475569' }}>
                        Saved filters
                    </Button>
                    <Checkbox size="small" sx={{ color: '#cbd5e1' }} />
                </Box>
            </Box>

            {/* BOTTOM ROW: Results & Layout Controls */}
            <Box sx={{ display: 'flex', alignItems: 'center', py: 1, px: 1, }}>
                {/* Results Badge */}
                <Box sx={{
                    border: '1px solid #cbd5e1', borderRadius: 1, px: 1.5, py: 0.5,
                    display: 'flex', alignItems: 'center', bgcolor: 'transparent'
                }}>
                    <Typography variant="body2" sx={{ fontWeight: 600, color: '#475569' }}>
                        {resultCount} <Box component="span" sx={{ fontWeight: 400 }}>Results</Box>
                    </Typography>
                </Box>

                {/* Sort Dropdown */}
                <Button
                    variant="outlined"
                    onClick={(e) => setSortAnchor(e.currentTarget)}
                    endIcon={<Sort fontSize="small" />}
                    sx={{
                        textTransform: 'none', color: '#475569', borderColor: '#cbd5e1',
                        bgcolor: 'transparent', '&:hover': { bgcolor: '#f1f5f9' }
                    }}
                >
                    Order by <Box component="span" sx={{ fontWeight: 700, ml: 0.5 }}>{sortConfig}</Box>
                </Button>
                <Menu anchorEl={sortAnchor} open={Boolean(sortAnchor)} onClose={() => setSortAnchor(null)}>
                    {['Date added', 'Name (A-Z)', 'Size (Largest first)'].map(opt => (
                        <MenuItem
                            key={opt}
                            onClick={() => { setSortConfig(opt); setSortAnchor(null); }}
                            selected={sortConfig === opt}
                        >
                            {opt}
                        </MenuItem>
                    ))}
                </Menu>

                {/* Right Side Tools */}
                <Box sx={{ ml: 'auto', display: 'flex', alignItems: 'center', gap: 2 }}>

                    <ToggleButtonGroup
                        value={viewLayout}
                        exclusive
                        onChange={(e, newVal) => newVal && setViewLayout(newVal)}
                        size="small"
                        sx={{
                            '& .MuiToggleButton-root': { border: '1px solid #cbd5e1', color: '#64748b' },
                            '& .Mui-selected': { bgcolor: '#334155 !important', color: '#fff !important' }
                        }}
                    >
                        <ToggleButton value="grid"><ViewModule fontSize="small" /></ToggleButton>
                        <ToggleButton value="list"><ViewList fontSize="small" /></ToggleButton>
                    </ToggleButtonGroup>
                </Box>
            </Box>
        </Box>
    );
}