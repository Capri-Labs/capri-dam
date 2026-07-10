import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
    Box, InputBase, Select, MenuItem, styled, Divider, Tooltip,
    Paper, List, ListItemButton, ListItemIcon, ListItemText, Typography,
    CircularProgress, ClickAwayListener,
} from '@mui/material';
import {
    Search as SearchIcon,
    Image as ImageIcon,
    InsertDriveFile as FileIcon,
    Folder as FolderIcon,
    AutoAwesome as AiIcon,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

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
    position: 'relative',
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

// 5. Suggestions dropdown — floats below the search bar
const SuggestionsPanel = styled(Paper)(() => ({
    position: 'absolute',
    top: 'calc(100% + 8px)',
    left: 0,
    right: 0,
    zIndex: 1300,
    borderRadius: '12px',
    overflow: 'hidden',
    maxHeight: '360px',
    overflowY: 'auto',
}));

const SUGGESTIONS_DEBOUNCE_MS = 200;
const MIN_QUERY_LENGTH = 2;

function suggestionIcon(type) {
    if (type === 'folder') return <FolderIcon fontSize="small" sx={{ color: '#f59e0b' }} />;
    return <FileIcon fontSize="small" sx={{ color: '#64748b' }} />;
}

export default function GlobalSearchBar() {
    const { t } = useTranslation();
    const [searchQuery, setSearchQuery] = useState('');
    const [searchMode, setSearchMode] = useState('images');
    const [isFocused, setIsFocused] = useState(false); // Drives the animation
    const [suggestions, setSuggestions] = useState([]);
    const [suggestionsOpen, setSuggestionsOpen] = useState(false);
    const [suggestionsLoading, setSuggestionsLoading] = useState(false);
    const [highlightedIndex, setHighlightedIndex] = useState(-1);

    const inputRef = useRef(null);
    const debounceRef = useRef(null);
    const abortRef = useRef(null);

    // Read initial state from URL
    useEffect(() => {
        const params = new URLSearchParams(window.location.search);
        if (params.get('q')) setSearchQuery(params.get('q'));
        if (params.get('mode')) setSearchMode(params.get('mode'));
    }, []);

    // ⌘K / Ctrl+K focuses the search bar from anywhere in the app
    useEffect(() => {
        const handleShortcut = (event) => {
            if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
                event.preventDefault();
                inputRef.current?.focus();
            }
        };
        window.addEventListener('keydown', handleShortcut);
        return () => window.removeEventListener('keydown', handleShortcut);
    }, []);

    const fetchSuggestions = useCallback((value, mode) => {
        if (abortRef.current) abortRef.current.abort();
        const controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
        abortRef.current = controller;

        setSuggestionsLoading(true);
        const qs = new URLSearchParams({ q: value, mode }).toString();
        fetch(`/api/v1/search/suggestions?${qs}`, {
            headers: { 'Content-Type': 'application/json' },
            credentials: 'same-origin',
            signal: controller?.signal,
        })
            .then((response) => response.json())
            .then((data) => {
                setSuggestions(data.results || []);
                setSuggestionsOpen(true);
                setHighlightedIndex(-1);
            })
            .catch(() => {})
            .finally(() => setSuggestionsLoading(false));
    }, []);

    useEffect(() => {
        if (debounceRef.current) clearTimeout(debounceRef.current);

        if (!isFocused || searchQuery.trim().length < MIN_QUERY_LENGTH || searchMode === 'visual') {
            setSuggestionsOpen(false);
            return undefined;
        }

        debounceRef.current = setTimeout(() => {
            fetchSuggestions(searchQuery.trim(), searchMode);
        }, SUGGESTIONS_DEBOUNCE_MS);

        return () => clearTimeout(debounceRef.current);
    }, [searchQuery, searchMode, isFocused, fetchSuggestions]);

    const goToSearchPage = () => {
        window.location.href = `/search?q=${encodeURIComponent(searchQuery)}&mode=${searchMode}`;
    };

    // Suggestions come from the search API — never trust `item.href` as a
    // navigation target as-is. Only same-origin, root-relative paths
    // (e.g. "/assets/123") are allowed; anything else (an absolute URL,
    // a protocol-relative "//host" URL, or a "javascript:"/"data:" URI)
    // falls back to the plain search results page instead of being
    // assigned to `window.location.href` directly.
    const isSafeInternalPath = (href) =>
        typeof href === 'string' && /^\/(?!\/)/.test(href);

    const goToSuggestion = (item) => {
        const fallback = `/search?q=${encodeURIComponent(searchQuery)}&mode=${searchMode}`;
        window.location.href = isSafeInternalPath(item.href) ? item.href : fallback;
    };

    const handleSearchSubmit = (e) => {
        if (e.key === 'Escape') {
            setSuggestionsOpen(false);
            return;
        }
        if (e.key === 'ArrowDown' && suggestionsOpen && suggestions.length > 0) {
            e.preventDefault();
            setHighlightedIndex((prev) => Math.min(prev + 1, suggestions.length - 1));
            return;
        }
        if (e.key === 'ArrowUp' && suggestionsOpen && suggestions.length > 0) {
            e.preventDefault();
            setHighlightedIndex((prev) => Math.max(prev - 1, -1));
            return;
        }
        if (e.key === 'Enter' && searchQuery.trim() !== '') {
            if (suggestionsOpen && highlightedIndex >= 0 && suggestions[highlightedIndex]) {
                goToSuggestion(suggestions[highlightedIndex]);
            } else {
                goToSearchPage();
            }
        }
    };

    const placeholderKey = searchMode === 'visual' ? 'visual' : searchMode === 'agentic' ? 'agentic' : 'default';
    const tooltipKey = searchMode === 'agentic' ? 'agentic' : 'default';

    return (
        <ClickAwayListener onClickAway={() => setSuggestionsOpen(false)}>
            <SearchContainer isFocused={isFocused}>
                {/* The Context Dropdown */}
                <ModeSelect
                    variant="standard"
                    value={searchMode}
                    onChange={(e) => setSearchMode(e.target.value)}
                    disableUnderline
                    MenuProps={{ slotProps: { paper: { elevation: 4, sx: { mt: 1, borderRadius: 2 } } } }}
                >
                    <MenuItem value="images">
                        <ImageIcon fontSize="small" sx={{ color: '#64748b', mr: 1 }} /> {t('globalSearchBar.modes.images')}
                    </MenuItem>
                    <MenuItem value="visual">
                        <AiIcon fontSize="small" sx={{ color: '#8b5cf6', mr: 1 }} /> {t('globalSearchBar.modes.visual')}
                    </MenuItem>
                    <MenuItem value="files">
                        <FileIcon fontSize="small" sx={{ color: '#64748b', mr: 1 }} /> {t('globalSearchBar.modes.files')}
                    </MenuItem>
                    <MenuItem value="folders">
                        <FolderIcon fontSize="small" sx={{ color: '#64748b', mr: 1 }} /> {t('globalSearchBar.modes.folders')}
                    </MenuItem>
                    <Divider sx={{ my: 0.5 }} />
                    <MenuItem value="agentic">
                        <AiIcon fontSize="small" sx={{ color: '#10b981', mr: 1 }} /> {t('globalSearchBar.modes.agentic')}
                    </MenuItem>
                </ModeSelect>

                <Divider orientation="vertical" flexItem sx={{ my: 1, borderColor: '#e2e8f0' }} />

                {/* Dynamic Search Icon (Changes color on focus) */}
                <Box sx={{ pl: 2, display: 'flex', alignItems: 'center', color: isFocused ? '#8b5cf6' : '#94a3b8', transition: 'color 0.3s ease' }}>
                    <SearchIcon fontSize="small" />
                </Box>

                {/* Text Input */}
                <Tooltip title={t(`globalSearchBar.tooltip.${tooltipKey}`)} placement="bottom-start" arrow disableInteractive>
                    <StyledInputBase
                        inputRef={inputRef}
                        placeholder={t(`globalSearchBar.placeholder.${placeholderKey}`)}
                        value={searchQuery}
                        onChange={e => setSearchQuery(e.target.value)}
                        onKeyDown={handleSearchSubmit}
                        onFocus={() => setIsFocused(true)}
                        onBlur={() => setIsFocused(false)}
                        slotProps={{
                            input: {
                                'aria-label': t('globalSearchBar.ariaLabel')
                            }
                        }}
                    />
                </Tooltip>

                {/* Keyboard Shortcut Hint (Hides on smaller screens) */}
                <Box sx={{ display: { xs: 'none', md: 'block' } }}>
                    <ShortcutBadge>{t('globalSearchBar.shortcutHint')}</ShortcutBadge>
                </Box>

                {suggestionsOpen && (
                    <SuggestionsPanel elevation={6}>
                        {suggestionsLoading && (
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, p: 2 }}>
                                <CircularProgress size={16} />
                                <Typography variant="body2" color="text.secondary">
                                    {t('globalSearchBar.suggestions.loading')}
                                </Typography>
                            </Box>
                        )}

                        {!suggestionsLoading && suggestions.length === 0 && (
                            <Box sx={{ p: 2 }}>
                                <Typography variant="body2" color="text.secondary">
                                    {t('globalSearchBar.suggestions.noResults')}
                                </Typography>
                            </Box>
                        )}

                        {!suggestionsLoading && suggestions.length > 0 && (
                            <List dense disablePadding>
                                {suggestions.map((item, index) => (
                                    <ListItemButton
                                        key={`${item.type}-${item.id}`}
                                        selected={index === highlightedIndex}
                                        onMouseDown={() => goToSuggestion(item)}
                                    >
                                        <ListItemIcon sx={{ minWidth: 32 }}>{suggestionIcon(item.type)}</ListItemIcon>
                                        <ListItemText
                                            primary={item.title}
                                            secondary={item.type === 'folder' ? t('globalSearchBar.suggestions.folderLabel') : item.subtitle}
                                        />
                                    </ListItemButton>
                                ))}
                                <Divider />
                                <ListItemButton onMouseDown={goToSearchPage}>
                                    <ListItemText
                                        primary={t('globalSearchBar.suggestions.viewAll', { query: searchQuery })}
                                        slotProps={{ primary: { color: 'primary', fontWeight: 600 } }}
                                    />
                                </ListItemButton>
                            </List>
                        )}
                    </SuggestionsPanel>
                )}
            </SearchContainer>
        </ClickAwayListener>
    );
}
