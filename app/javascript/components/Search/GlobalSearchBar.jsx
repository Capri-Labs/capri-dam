import React, { useState, useEffect } from 'react';
import { Box, InputBase, Select, MenuItem, styled, Divider, Tooltip, Typography } from '@mui/material';
import {
    Search as SearchIcon,
    Image as ImageIcon,
    InsertDriveFile as FileIcon,
    Folder as FolderIcon,
    AutoAwesome as AiIcon
} from '@mui/icons-material';

// 1. The Animated "Hero" Container
// Uses a cubic-bezier transition for a very smooth, Apple-like expansion snap
const SearchContainer = styled(Box, {
    shouldForwardProp: (prop) => prop !== 'isFocused',
})(({ theme, isFocused }) => ({
    display: 'flex',
    alignItems: 'center',
    borderRadius: '12px', // Softer, more modern corners
    height: '48px', // Noticeably taller and easier to click
    backgroundColor: isFocused ? '#ffffff' : '#f8fafc', // Slate 50 to pure white
    border: `1px solid ${isFocused ? '#8b5cf6' : '#e2e8f0'}`, // Indigo/Purple accent border on focus
    boxShadow: isFocused
        ? '0 10px 25px -5px rgba(139, 92, 246, 0.15), 0 8px 10px -6px rgba(139, 92, 246, 0.1)'
        : '0 1px 2px 0 rgba(0, 0, 0, 0.05)',
    transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
    width: '100%',
    [theme.breakpoints.up('md')]: {
        // The magic width expansion
        width: isFocused ? '720px' : '550px',
    },
}));

// 2. Upgraded Dropdown
const ModeSelect = styled(Select)(({ theme }) => ({
    '& .MuiSelect-select': {
        padding: theme.spacing(1, 1.5, 1, 2),
        display: 'flex',
        alignItems: 'center',
        gap: '8px',
        color: '#334155', // Slate 700
        fontSize: '0.9rem',
        fontWeight: 600, // slightly bolder to establish hierarchy
    },
    '&::before, &::after': { display: 'none' },
    '& .MuiOutlinedInput-notchedOutline': { border: 'none' }
}));

// 3. Upgraded Input
const StyledInputBase = styled(InputBase)(({ theme }) => ({
    flex: 1,
    color: '#0f172a', // Slate 900
    fontSize: '0.95rem',
    fontWeight: 500,
    '& .MuiInputBase-input': {
        padding: theme.spacing(1.5, 2, 1.5, 1),
        width: '100%',
        '&::placeholder': {
            color: '#94a3b8',
            opacity: 1,
            transition: 'color 0.2s ease',
        }
    },
}));

// 4. Keyboard Shortcut Badge
const ShortcutBadge = styled(Box)(({ theme }) => ({
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    padding: '2px 6px',
    marginRight: '12px',
    borderRadius: '4px',
    backgroundColor: '#f1f5f9',
    border: '1px solid #e2e8f0',
    color: '#64748b',
    fontSize: '0.75rem',
    fontWeight: 700,
    fontFamily: 'monospace',
    pointerEvents: 'none',
}));

export default function GlobalSearchBar() {
    const [searchQuery, setSearchQuery] = useState('');
    const [searchMode, setSearchMode] = useState('images');
    const [isFocused, setIsFocused] = useState(false); // Drives the animation

    // Read initial state from URL
    useEffect(() => {
        const params = new URLSearchParams(window.location.search);
        if (params.get('q')) setSearchQuery(params.get('q'));
        if (params.get('mode')) setSearchMode(params.get('mode'));
    }, []);

    const handleSearchSubmit = (e) => {
        if (e.key === 'Enter' && searchQuery.trim() !== '') {
            window.location.href = `/search?q=${encodeURIComponent(searchQuery)}&mode=${searchMode}`;
        }
    };

    return (
        <SearchContainer isFocused={isFocused}>
            {/* The Context Dropdown */}
            <ModeSelect
                variant="standard"
                value={searchMode}
                onChange={(e) => setSearchMode(e.target.value)}
                disableUnderline
                MenuProps={{ PaperProps: { elevation: 4, sx: { mt: 1, borderRadius: 2 } } }}
            >
                <MenuItem value="images">
                    <ImageIcon fontSize="small" sx={{ color: '#64748b', mr: 1 }} /> Images
                </MenuItem>
                <MenuItem value="visual">
                    <AiIcon fontSize="small" sx={{ color: '#8b5cf6', mr: 1 }} /> Visual Match
                </MenuItem>
                <MenuItem value="files">
                    <FileIcon fontSize="small" sx={{ color: '#64748b', mr: 1 }} /> Files
                </MenuItem>
                <MenuItem value="folders">
                    <FolderIcon fontSize="small" sx={{ color: '#64748b', mr: 1 }} /> Folders
                </MenuItem>
                <Divider sx={{ my: 0.5 }} />
                <MenuItem value="agentic">
                    <AiIcon fontSize="small" sx={{ color: '#10b981', mr: 1 }} /> Ask AI Agent
                </MenuItem>
            </ModeSelect>

            <Divider orientation="vertical" flexItem sx={{ my: 1, borderColor: '#e2e8f0' }} />

            {/* Dynamic Search Icon (Changes color on focus) */}
            <Box sx={{ pl: 2, display: 'flex', alignItems: 'center', color: isFocused ? '#8b5cf6' : '#94a3b8', transition: 'color 0.3s ease' }}>
                <SearchIcon fontSize="small" />
            </Box>

            {/* Text Input */}
            <Tooltip title={searchMode === 'agentic' ? "Type a natural language command..." : "Press Enter to search"} placement="bottom-start" arrow disableInteractive>
                <StyledInputBase
                    placeholder={
                        searchMode === 'visual' ? "Drop an image or paste a URL..." :
                            searchMode === 'agentic' ? "E.g., Find summer photos without logos..." :
                                "Search assets, folders, or tags..."
                    }
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    onKeyDown={handleSearchSubmit}
                    onFocus={() => setIsFocused(true)}
                    onBlur={() => setIsFocused(false)}
                    inputProps={{ 'aria-label': 'global search' }}
                />
            </Tooltip>

            {/* Keyboard Shortcut Hint (Hides on smaller screens) */}
            <Box sx={{ display: { xs: 'none', md: 'block' } }}>
                <ShortcutBadge>⌘K</ShortcutBadge>
            </Box>
        </SearchContainer>
    );
}