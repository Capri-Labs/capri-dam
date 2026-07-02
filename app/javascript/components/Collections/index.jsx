import React, { useState } from 'react';
import { BrowserRouter, Routes, Route, useNavigate, useParams, useLocation } from 'react-router-dom';
import {
    Box,
    Typography,
    Button,
    CssBaseline,
    Breadcrumbs,
    Link,
    Menu,
    MenuItem,
    Divider,
    Checkbox,
    TextField,
    Tooltip
} from '@mui/material';
import {
    Add,
    CollectionsBookmark,
    AutoAwesome,
    SettingsSuggest,
    RuleFolder,
    HistoryToggleOff
} from '@mui/icons-material';
import CollectionsBoard from './CollectionsBoard';
import CollectionDetail from './CollectionDetail';
import CollectionCreateDialog from './CollectionCreateDialog';
import { CollectionProvider, useCollections } from './CollectionContext';

// Helper component to extract the slug from the URL
function CollectionDetailWrapper() {
    const { slug } = useParams();
    const navigate = useNavigate();
    return <CollectionDetail slug={slug} onBack={() => navigate('/')} />;
}

// The main application logic containing the router hooks
function WorkspaceApp() {
    const navigate = useNavigate();
    const location = useLocation();
    const { collections, temporalDate, setTemporalDate } = useCollections(); // Now accessible because Provider is higher up

    // Application States
    const [isCreateOpen, setIsCreateOpen] = useState(false);
    const [aiMenuAnchor, setAiMenuAnchor] = useState(null);

    // Lifted Selection State for the Board
    const [selectedIds, setSelectedIds] = useState([]);

    // With basename="/collections", the root path is just "/"
    const isDetailView = location.pathname !== '/';
    const activeSlug = isDetailView ? location.pathname.split('/').pop() : null;

    // Handle Global Select All
    const handleSelectAll = (event) => {
        if (event.target.checked) {
            setSelectedIds(collections.map(c => c.id));
        } else {
            setSelectedIds([]);
        }
    };

    const isAllSelected = collections.length > 0 && selectedIds.length === collections.length;
    const isIndeterminate = selectedIds.length > 0 && selectedIds.length < collections.length;

    // Helper to clear the temporal filter
    const clearTemporalFilter = () => setTemporalDate('');

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            {/* Temporal Audit Banner */}
            {temporalDate && (
                <Box sx={{ mb: 3, p: 1.5, bgcolor: '#fef2f2', border: '1px solid #fca5a5', borderRadius: 2, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <HistoryToggleOff sx={{ color: '#ef4444', mr: 1 }} />
                    <Typography variant="body2" sx={{ color: '#b91c1c', fontWeight: 600 }}>
                        Audit Mode Active: Viewing workspace state exactly as it was on {temporalDate}.
                    </Typography>
                    <Button size="small" onClick={clearTemporalFilter} sx={{ ml: 2, textTransform: 'none', color: '#b91c1c', border: '1px solid #fca5a5' }}>
                        Return to Present
                    </Button>
                </Box>
            )}
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 4 }}>
                <Box>
                    <Breadcrumbs aria-label="breadcrumb" sx={{ mb: 1 }}>
                        <Link
                            underline="hover" color="inherit" component="button"
                            onClick={() => { navigate('/'); setSelectedIds([]); }}
                            sx={{ display: 'flex', alignItems: 'center', fontSize: '0.875rem' }}
                        >
                            <CollectionsBookmark sx={{ mr: 0.5, fontSize: '1rem' }} />
                            Workspace
                        </Link>
                        {isDetailView && activeSlug && (
                            <Typography color="text.primary" sx={{ fontSize: '0.875rem' }}>
                                {activeSlug}
                            </Typography>
                        )}
                    </Breadcrumbs>
                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                        {isDetailView ? 'Collection Details' : 'My Collections'}
                    </Typography>
                    <Typography variant="body2" color="textSecondary">
                        Curate, manage, and share digital asset campaigns.
                    </Typography>
                </Box>

                {!isDetailView && (
                    <Box sx={{ display: 'flex', gap: 2, alignItems: 'center' }}>

                        {/* Lifted Select All Checkbox */}
                        <Box sx={{ display: 'flex', alignItems: 'center', mr: 1, bgcolor: '#fff', px: 1.5, py: 0.5, borderRadius: 2, border: '1px solid #e3e8ef' }}>
                            <Checkbox
                                checked={isAllSelected}
                                indeterminate={isIndeterminate}
                                onChange={handleSelectAll}
                                size="small"
                                sx={{ color: '#cbd5e1', '&.Mui-checked': { color: '#5e35b1' }, p: 0.5, mr: 0.5 }}
                            />
                            <Typography variant="body2" sx={{ fontWeight: 600, color: '#475569' }}>
                                Select All
                            </Typography>
                        </Box>

                        {/*  Temporal Time-Travel Picker */}
                        <Tooltip title="Time-Travel Audit Viewer: See workspace exactly as it was on this date">
                            <TextField
                                type="date"
                                size="small"
                                value={temporalDate}
                                onChange={(e) => setTemporalDate(e.target.value)}
                                slotProps={{
                                    inputLabel: { shrink: true },
                                    input: {
                                        startAdornment: <HistoryToggleOff sx={{ color: temporalDate ? '#ef4444' : '#94a3b8', mr: 1, fontSize: 20 }} />
                                    }
                                }}
                                sx={{
                                    width: 170, // Force a width so it doesn't disappear
                                    bgcolor: temporalDate ? '#fff1f2' : '#fff',
                                    borderRadius: 1,
                                    '& .MuiOutlinedInput-root': { height: 40 }
                                }}
                            />
                        </Tooltip>

                        <Button variant="outlined" startIcon={<AutoAwesome />} onClick={(e) => setAiMenuAnchor(e.currentTarget)} sx={{ borderColor: '#e3e8ef', color: '#5e35b1', bgcolor: '#fff' }}>
                            AI Operations
                        </Button>
                        <Button variant="contained" startIcon={<Add />} onClick={() => setIsCreateOpen(true)} sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                            Create Collection
                        </Button>
                    </Box>
                )}
            </Box>

            {/* AI Menu */}
            <Menu anchorEl={aiMenuAnchor} open={Boolean(aiMenuAnchor)} onClose={() => setAiMenuAnchor(null)} elevation={3} slotProps={{paper: { sx: { mt: 1, minWidth: 220, borderRadius: 2, border: '1px solid #e3e8ef' } } }}>
                <MenuItem onClick={() => setAiMenuAnchor(null)}>
                    <RuleFolder fontSize="small" sx={{ mr: 1.5, color: '#475569' }} /> Re-evaluate Smart Rules
                </MenuItem>
                <MenuItem onClick={() => setAiMenuAnchor(null)}>
                    <SettingsSuggest fontSize="small" sx={{ mr: 1.5, color: '#475569' }} /> Global TDM Health Scan
                </MenuItem>
                <Divider />
                <MenuItem onClick={() => setAiMenuAnchor(null)} sx={{ color: '#d32f2f' }}>
                    Purge Expired TTL Collections
                </MenuItem>
            </Menu>

            <Routes>
                <Route path="/" element={<CollectionsBoard selectedIds={selectedIds} setSelectedIds={setSelectedIds} onSelectCollection={(slug) => navigate(`/${slug}`)} />} />
                <Route path="/:slug" element={<CollectionDetailWrapper />} />
            </Routes>

            <CollectionCreateDialog
                open={isCreateOpen}
                onClose={() => setIsCreateOpen(false)}
                onSuccess={(newSlug) => navigate(`/${newSlug}`)}
            />
        </Box>
    );
}

// The top-level export that provides the routing and data context to the app
export default function CollectionsWorkspace() {
    return (
        <BrowserRouter basename="/collections">
            <CollectionProvider>
                <WorkspaceApp />
            </CollectionProvider>
        </BrowserRouter>
    );
}