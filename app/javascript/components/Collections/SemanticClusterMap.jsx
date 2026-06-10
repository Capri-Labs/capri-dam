import React, { useState, useEffect } from 'react';
import { Dialog, DialogTitle, DialogContent, Box, Typography, CircularProgress, IconButton, Tooltip } from '@mui/material';
import { Close, AutoFixHigh } from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

export default function SemanticClusterMap({ open, onClose, slug }) {
    const notify = useNotify();
    const [loading, setLoading] = useState(true);
    const [nodes, setNodes] = useState([]);
    const [hoveredNode, setHoveredNode] = useState(null);

    useEffect(() => {
        if (open) fetchMapData();
    }, [open, slug]);

    const fetchMapData = async () => {
        setLoading(true);
        try {
            const res = await fetch(`/api/v1/collections/${slug}/cluster_map`);
            if (res.ok) {
                const data = await res.json();
                setNodes(data.nodes || []);
            }
        } catch (error) {
            notify("Failed to load semantic map.", "error");
        } finally {
            setLoading(false);
        }
    };

    if (!open) return null;

    return (
        <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth PaperProps={{ sx: { borderRadius: 3 } }}>
            <DialogTitle sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', pb: 1 }}>
                <Box sx={{ display: 'flex', alignItems: 'center' }}>
                    <AutoFixHigh sx={{ color: '#0ea5e9', mr: 1.5 }} />
                    <Typography variant="h6" sx={{ fontWeight: 700 }}>Semantic Cluster Map</Typography>
                </Box>
                <IconButton onClick={onClose} size="small"><Close /></IconButton>
            </DialogTitle>

            <DialogContent sx={{ p: 3 }}>
                <Typography variant="body2" color="textSecondary" sx={{ mb: 3 }}>
                    Assets are mapped based on their high-dimensional vector embeddings. Proximity indicates semantic similarity. Use this to identify visual clustering and coverage gaps.
                </Typography>

                <Box sx={{ position: 'relative', width: '100%', height: 450, bgcolor: '#f8fafc', border: '1px solid #e2e8f0', borderRadius: 2, overflow: 'hidden' }}>
                    {loading ? (
                        <Box sx={{ display: 'flex', height: '100%', alignItems: 'center', justifyContent: 'center' }}>
                            <CircularProgress sx={{ color: '#0ea5e9' }} />
                        </Box>
                    ) : (
                        <>
                            {/* Radar Grid Lines */}
                            <Box sx={{ position: 'absolute', top: '50%', left: 0, right: 0, height: '1px', bgcolor: '#e2e8f0' }} />
                            <Box sx={{ position: 'absolute', left: '50%', top: 0, bottom: 0, width: '1px', bgcolor: '#e2e8f0' }} />

                            {/* Render Nodes */}
                            {nodes.map(node => (
                                <Box
                                    key={node.id}
                                    onMouseEnter={() => setHoveredNode(node)}
                                    onMouseLeave={() => setHoveredNode(null)}
                                    sx={{
                                        position: 'absolute',
                                        left: `${node.x}%`,
                                        top: `${node.y}%`,
                                        width: 14, height: 14,
                                        bgcolor: '#3b82f6',
                                        borderRadius: '50%',
                                        transform: 'translate(-50%, -50%)',
                                        cursor: 'pointer',
                                        boxShadow: '0 0 0 2px #fff',
                                        transition: 'all 0.2s',
                                        zIndex: hoveredNode?.id === node.id ? 10 : 1,
                                        '&:hover': { transform: 'translate(-50%, -50%) scale(1.5)', bgcolor: '#6366f1' }
                                    }}
                                />
                            ))}

                            {/* Hover Tooltip Overlay */}
                            {hoveredNode && (
                                <Box sx={{
                                    position: 'absolute',
                                    left: hoveredNode.x > 50 ? `calc(${hoveredNode.x}% - 160px)` : `calc(${hoveredNode.x}% + 20px)`,
                                    top: hoveredNode.y > 50 ? `calc(${hoveredNode.y}% - 100px)` : `calc(${hoveredNode.y}% + 20px)`,
                                    width: 140, bgcolor: 'rgba(15, 23, 42, 0.9)', color: '#fff',
                                    borderRadius: 2, p: 1, zIndex: 20, boxShadow: 3, pointerEvents: 'none'
                                }}>
                                    {hoveredNode.url && (
                                        <Box sx={{ width: '100%', height: 80, mb: 1, borderRadius: 1, overflow: 'hidden' }}>
                                            <img src={hoveredNode.url} alt={hoveredNode.title} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                        </Box>
                                    )}
                                    <Typography variant="caption" sx={{ fontWeight: 600, display: 'block', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                        {hoveredNode.title}
                                    </Typography>
                                </Box>
                            )}
                        </>
                    )}
                </Box>
            </DialogContent>
        </Dialog>
    );
}