import React, { useState, useRef, useEffect } from 'react';
import {
    Box, Grid, Paper, Typography, TextField, IconButton, Stack,
    Card, CardMedia, CardContent, CardActions, Button, Chip,
    CircularProgress, Avatar, Divider, Tooltip
} from '@mui/material';
import {
    Send, AutoAwesome, ContentCopy, Download, AutoGraph,
    ImageSearch, SmartToy, Person
} from '@mui/icons-material';

export default function SemanticCopilot() {
    const [messages, setMessages] = useState([
        { sender: 'ai', text: 'Hello. I am your Semantic Copilot. Describe the visual assets you need, or ask me to find media based on a conceptual theme.' }
    ]);
    const [input, setInput] = useState('');
    const [isSearching, setIsSearching] = useState(false);
    const [results, setResults] = useState([]);
    const chatEndRef = useRef(null);

    // Auto-scroll chat to bottom
    useEffect(() => {
        chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [messages]);

    const handleSearch = async (e) => {
        e.preventDefault();
        if (!input.trim()) return;

        const userQuery = input;
        setMessages(prev => [...prev, { sender: 'user', text: userQuery }]);
        setInput('');
        setIsSearching(true);

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;

            // 🚀 WIRED TO RAILS BACKEND
            const response = await fetch('/api/v1/copilot/search', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken
                },
                body: JSON.stringify({ query: userQuery })
            });

            const data = await response.json();

            if (response.ok) {
                setResults(data.results || []);
                setMessages(prev => [...prev, {
                    sender: 'ai',
                    text: `I found ${data.results.length} highly relevant assets traversing the local vector space.`
                }]);
            } else {
                throw new Error(data.error || 'Search failed');
            }
        } catch (error) {
            setMessages(prev => [...prev, { sender: 'ai', text: 'Error connecting to the local vector database.' }]);
        } finally {
            setIsSearching(false);
        }
    };

    return (
        <Box sx={{ display: 'flex', height: 'calc(100vh - 64px)', overflow: 'hidden', bgcolor: '#f8fafc' }}>

            {/* LEFT PANE: Conversational UI */}
            <Paper elevation={0} sx={{ width: 400, flexShrink: 0, display: 'flex', flexDirection: 'column', borderRight: '1px solid #e2e8f0', borderRadius: 0, bgcolor: '#ffffff' }}>
                <Box sx={{ p: 2.5, borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center' }}>
                    <AutoAwesome sx={{ color: '#8e24aa', mr: 1.5 }} />
                    <Box>
                        <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>Semantic Copilot</Typography>
                        {/* 🚀 UPDATED MODEL LABEL */}
                        <Typography variant="caption" color="textSecondary">Powered by HuggingFace all-MiniLM-L6-v2</Typography>
                    </Box>
                </Box>

                {/* Chat History */}
                <Box sx={{ flexGrow: 1, overflowY: 'auto', p: 2.5, display: 'flex', flexDirection: 'column', gap: 2 }}>
                    {messages.map((msg, index) => (
                        <Box key={index} sx={{ display: 'flex', gap: 1.5, flexDirection: msg.sender === 'user' ? 'row-reverse' : 'row' }}>
                            <Avatar sx={{ width: 32, height: 32, bgcolor: msg.sender === 'user' ? '#121926' : '#f3e8ff', color: msg.sender === 'user' ? '#fff' : '#8e24aa' }}>
                                {msg.sender === 'user' ? <Person fontSize="small" /> : <SmartToy fontSize="small" />}
                            </Avatar>
                            <Box sx={{ maxWidth: '75%', p: 2, borderRadius: 2, bgcolor: msg.sender === 'user' ? '#f1f5f9' : '#faf5ff', border: '1px solid', borderColor: msg.sender === 'user' ? '#e2e8f0' : '#f3e8ff' }}>
                                <Typography variant="body2" sx={{ color: '#1e293b', lineHeight: 1.5 }}>
                                    {msg.text}
                                </Typography>
                            </Box>
                        </Box>
                    ))}
                    {isSearching && (
                        <Box sx={{ display: 'flex', gap: 1.5 }}>
                            <Avatar sx={{ width: 32, height: 32, bgcolor: '#f3e8ff', color: '#8e24aa' }}><SmartToy fontSize="small" /></Avatar>
                            <Box sx={{ p: 2, borderRadius: 2, bgcolor: '#faf5ff', display: 'flex', alignItems: 'center' }}>
                                <CircularProgress size={16} sx={{ color: '#8e24aa', mr: 1.5 }} />
                                <Typography variant="body2" color="textSecondary">Traversing vector space...</Typography>
                            </Box>
                        </Box>
                    )}
                    <div ref={chatEndRef} />
                </Box>

                {/* Input Area */}
                <Box sx={{ p: 2, borderTop: '1px solid #e2e8f0', bgcolor: '#ffffff' }}>
                    <form onSubmit={handleSearch}>
                        <Paper elevation={0} sx={{ p: '2px 4px', display: 'flex', alignItems: 'center', border: '1px solid #cbd5e1', borderRadius: 6, '&:focus-within': { borderColor: '#8e24aa', boxShadow: '0 0 0 2px rgba(142, 36, 170, 0.2)' } }}>
                            <Tooltip title="Reverse Image Search (Coming Soon)">
                                <IconButton sx={{ p: '10px' }} aria-label="menu">
                                    <ImageSearch fontSize="small" />
                                </IconButton>
                            </Tooltip>
                            <TextField
                                fullWidth
                                variant="standard"
                                placeholder="e.g., Wide shots of urban architecture..."
                                value={input}
                                onChange={(e) => setInput(e.target.value)}
                                InputProps={{ disableUnderline: true, sx: { fontSize: '0.9rem' } }}
                                disabled={isSearching}
                            />
                            <Divider sx={{ height: 28, m: 0.5 }} orientation="vertical" />
                            <IconButton color="primary" type="submit" sx={{ p: '10px', color: '#8e24aa' }} disabled={!input.trim() || isSearching}>
                                <Send fontSize="small" />
                            </IconButton>
                        </Paper>
                    </form>
                </Box>
            </Paper>

            {/* RIGHT PANE: Dynamic Results Canvas */}
            <Box sx={{ flexGrow: 1, p: 4, overflowY: 'auto' }}>
                {results.length === 0 ? (
                    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', color: '#94a3b8' }}>
                        <AutoAwesome sx={{ fontSize: 48, mb: 2, opacity: 0.5 }} />
                        <Typography variant="h6">The Canvas is Empty</Typography>
                        <Typography variant="body2">Ask the Copilot to retrieve assets to begin.</Typography>
                    </Box>
                ) : (
                    <Grid container spacing={3}>
                        {results.map((asset) => (
                            <Grid item xs={12} sm={6} md={4} xl={3} key={asset.id}>
                                <Card elevation={0} sx={{ border: '1px solid #e2e8f0', borderRadius: 3, transition: 'all 0.2s', '&:hover': { borderColor: '#8e24aa', transform: 'translateY(-2px)', boxShadow: '0 4px 12px rgba(0,0,0,0.05)' } }}>
                                    <Box sx={{ position: 'relative' }}>
                                        {/* 🚀 WIRED TO RAILS file_url */}
                                        <CardMedia component="img" height="180" image={asset.file_url} alt={asset.properties?.title || asset.original_filename} sx={{ objectFit: 'cover' }} />
                                    </Box>
                                    <CardContent sx={{ p: 2, pb: 1 }}>
                                        <Typography variant="subtitle2" sx={{ fontWeight: 600, noWrap: true }}>{asset.properties?.title || asset.original_filename}</Typography>
                                        <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 1.5 }}>
                                            {asset.properties?.campaign ? `Campaign: ${asset.properties.campaign}` : 'Unassigned Campaign'}
                                        </Typography>
                                        <Stack direction="row" spacing={0.5} flexWrap="wrap" sx={{ gap: 0.5 }}>
                                            {asset.properties?.tags?.slice(0, 3).map((tag, idx) => (
                                                <Chip key={idx} label={tag} size="small" sx={{ height: 20, fontSize: '0.7rem', bgcolor: '#f1f5f9' }} />
                                            ))}
                                        </Stack>
                                    </CardContent>
                                    <CardActions sx={{ p: 2, pt: 0, justifyContent: 'space-between' }}>
                                        <Tooltip title="Copy Public URL">
                                            <IconButton size="small" onClick={() => navigator.clipboard.writeText(asset.file_url)}><ContentCopy fontSize="small" /></IconButton>
                                        </Tooltip>
                                        <Button size="small" variant="outlined" startIcon={<AutoGraph />} sx={{ borderColor: '#cbd5e1', color: '#475569', textTransform: 'none' }}>
                                            Reuse in Workspace
                                        </Button>
                                    </CardActions>
                                </Card>
                            </Grid>
                        ))}
                    </Grid>
                )}
            </Box>
        </Box>
    );
}