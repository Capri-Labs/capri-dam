import React, { useState, useEffect } from 'react';
import {
    Box, Paper, Typography, Button, Stack, Divider, Grid,
    List, ListItem, ListItemText, ListItemIcon, Badge, Card, CardContent, Chip
} from '@mui/material';
import { ArrowBack, CheckCircle, Block, ErrorOutlined, AutoAwesome } from '@mui/icons-material';

export default function BatchReviewWorkspace({ batchId, onBack }) {
    const [items, setItems] = useState([]);
    const [selectedItem, setSelectedItem] = useState(null);

    useEffect(() => {
        // Simulating API fetch: GET /api/v1/ingestion_batches/:id/items
        const mockItems = [
            {
                id: "item-1",
                original_filename: "Archive/2022/Assets/Campaigns/HB_final_v2_res800.jpg",
                file_hash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                file_size: "14.2 MB",
                status: "ready_for_import",
                legacy_metadata: { xmp_creator: "A. Smith", upload_node: "Node_4B", creation_date: "2022-04-12" },
                clean_properties: { title: "Summer Campaign Hero Banner", campaign: "Summer 2022", author: "Andrew Smith", tags: ["outdoor", "lifestyle", "banner"] }
            },
            {
                id: "item-2",
                original_filename: "Unsorted/Images/Asset_Duplicate_Entry.png",
                file_hash: "8f43c0a298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852baaa",
                file_size: "4.1 MB",
                status: "flagged_duplicate", // Blocked at edge to prevent storage bills
                legacy_metadata: { folder: "Dump" },
                clean_properties: {}
            }
        ];
        setItems(mockItems);
        setSelectedItem(mockItems[0]);
    }, [batchId]);

    const handleCommitBatch = () => {
        // Trigger final execution loop to transfer staged tables into live Asset table
        alert("Batch committed successfully. Ingestion worker triggered to link assets to core structure.");
        onBack();
    };

    return (
        <Box sx={{ p: 4, bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            {/* Context Navigation bar */}
            <Paper elevation={0} sx={{ p: 2, mb: 3, borderRadius: 2, border: '1px solid #e3e8ef', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Stack direction="row" alignItems="center" spacing={2}>
                    <Button startIcon={<ArrowBack />} onClick={onBack} color="inherit">Back</Button>
                    <Typography variant="h6" sx={{ fontWeight: 600 }}>Auditing: Legacy AEM Asset Archive</Typography>
                </Stack>
                <Button
                    variant="contained"
                    color="success"
                    startIcon={<CheckCircle />}
                    onClick={handleCommitBatch}
                >
                    Approve & Commit Batch
                </Button>
            </Paper>

            <Grid container spacing={3}>
                {/* Left Sidebar: Quarantine list Queue */}
                <Grid item xs={12} md={4}>
                    <Paper elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '70vh', overflowY: 'auto' }}>
                        <List sx={{ p: 0 }}>
                            {items.map((item) => (
                                <ListItem
                                    button
                                    key={item.id}
                                    selected={selectedItem?.id === item.id}
                                    onClick={() => setSelectedItem(item)}
                                    sx={{ borderBottom: '1px solid #f1f5f9', p: 2 }}
                                >
                                    <ListItemIcon>
                                        {item.status === 'ready_for_import' && <CheckCircle color="success" />}
                                        {item.status === 'flagged_duplicate' && <Block color="error" />}
                                        {item.status === 'flagged_error' && <ErrorOutlined color="warning" />}
                                    </ListItemIcon>
                                    <ListItemText
                                        primary={item.original_filename.split('/').last || item.original_filename}
                                        secondary={`${item.file_size} • ${item.status.replace('_', ' ')}`}
                                        primaryTypographyProps={{ noWrap: true, variant: 'subtitle2', fontWeight: 600 }}
                                    />
                                </ListItem>
                            ))}
                        </List>
                    </Paper>
                </Grid>

                {/* Right Workspace Panel: Metadata Delta Split View */}
                <Grid item xs={12} md={8}>
                    {selectedItem ? (
                        <Paper elevation={0} sx={{ p: 3, border: '1px solid #e3e8ef', borderRadius: 3, minHeight: '70vh' }}>
                            <Typography variant="h6" sx={{ fontWeight: 600, mb: 1 }}>{selectedItem.original_filename}</Typography>
                            <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 3 }}>
                                Cryptographic Hash: <code>{selectedItem.file_hash}</code>
                            </Typography>

                            {selectedItem.status === 'flagged_duplicate' ? (
                                <Card elevation={0} sx={{ bgcolor: '#fdf2f2', border: '1px solid #fde2e2', mt: 4 }}>
                                    <CardContent>
                                        <Stack direction="row" spacing={2} alignItems="center">
                                            <Block color="error" />
                                            <Box>
                                                <Typography variant="subtitle2" color="error" sx={{ fontWeight: 600 }}>Deduplication Interception</Typography>
                                                <Typography variant="body2" color="textSecondary">
                                                    This asset's payload hash exactly matches an asset already live in the system. The platform will drop this duplicate upon batch commit, protecting your cloud environment from technical storage debt.
                                                </Typography>
                                            </Box>
                                        </Stack>
                                    </CardContent>
                                </Card>
                            ) : (
                                <Grid container spacing={3}>
                                    {/* Messy Source Legacy View */}
                                    <Grid item xs={12} sm={6}>
                                        <Typography variant="subtitle2" sx={{ fontWeight: 600, mb: 2, color: '#64748b' }}>Raw Legacy Attributes</Typography>
                                        <Box sx={{ p: 2, bgcolor: '#f8fafc', borderRadius: 2, border: '1px solid #e2e8f0', fontFamily: 'monospace', fontSize: '0.8rem' }}>
                                            <pre>{JSON.stringify(selectedItem.legacy_metadata, null, 2)}</pre>
                                        </Box>
                                    </Grid>

                                    {/* AI Clean Transformed View */}
                                    <Grid item xs={12} sm={6}>
                                        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
                                            <AutoAwesome sx={{ color: '#8e24aa', fontSize: 18 }} />
                                            <Typography variant="subtitle2" sx={{ fontWeight: 600, color: '#8e24aa' }}>AI Normalized Schema</Typography>
                                        </Stack>
                                        <Box sx={{ p: 2, bgcolor: '#faf5ff', borderRadius: 2, border: '1px solid #f3e8ff' }}>
                                            <Typography variant="caption" color="textSecondary">Title</Typography>
                                            <Typography variant="body2" sx={{ fontWeight: 600, mb: 1.5 }}>{selectedItem.clean_properties.title}</Typography>

                                            <Typography variant="caption" color="textSecondary">Campaign Mapping</Typography>
                                            <Typography variant="body2" sx={{ fontWeight: 600, mb: 1.5 }}>{selectedItem.clean_properties.campaign || 'N/A'}</Typography>

                                            <Typography variant="caption" color="textSecondary">Enriched Semantic Tags</Typography>
                                            <Stack direction="row" spacing={0.5} flexWrap="wrap" sx={{ mt: 0.5 }}>
                                                {selectedItem.clean_properties.tags?.map((tag, idx) => (
                                                    <Chip key={idx} label={tag} size="small" sx={{ bgcolor: '#f3e5f5', color: '#8e24aa' }} />
                                                ))}
                                            </Stack>
                                        </Box>
                                    </Grid>
                                </Grid>
                            )}
                        </Paper>
                    ) : (
                        <Paper elevation={0} sx={{ border: '1px dashed #cbd5e1', borderRadius: 3, height: '70vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                            <Typography color="textSecondary">Select an asset from the ingestion pipeline queue to audit payload integrity.</Typography>
                        </Paper>
                    )}
                </Grid>
            </Grid>
        </Box>
    );
}