import React, { useState, useEffect } from 'react';
import { Box, Typography, Stepper, Step, StepLabel, StepContent, CircularProgress, Paper, Chip, Stack } from '@mui/material';
import { Person, AccessTime, DataObject, AspectRatio, Storage, CallSplit, Palette, TaskAlt } from '@mui/icons-material';

// Helper to make byte sizes human-readable
const formatBytes = (bytes, decimals = 1) => {
    if (!bytes || bytes === 0) return '0 Bytes';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(Math.abs(bytes)) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
};

export default function AssetAuditTab({ asset }) {
    const [auditLogs, setAuditLogs] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (!asset || !asset.id) return;

        fetch(`/api/v1/assets/${asset.id}/audit_trail`)
            .then(res => res.json())
            .then(data => {
                setAuditLogs(data.audit_trail || []);
                setLoading(false);
            })
            .catch(err => {
                console.error("Failed to fetch audit logs", err);
                setLoading(false);
            });
    }, [asset]);

    if (loading) {
        return (
            <Box sx={{ p: 4, display: 'flex', justifyContent: 'center' }}>
                <CircularProgress size={24} />
            </Box>
        );
    }

    return (
        <Box sx={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
            <Typography variant="subtitle1" fontWeight="700" sx={{ mb: 2 }}>
                Operational Ledger
            </Typography>

            <Box sx={{
                flexGrow: 1,
                maxHeight: '550px',
                overflowY: 'auto',
                pr: 2,
                '&::-webkit-scrollbar': { width: '6px' },
                '&::-webkit-scrollbar-thumb': { backgroundColor: '#cbd5e1', borderRadius: '4px' },
                '&::-webkit-scrollbar-track': { backgroundColor: 'transparent' }
            }}>
                {auditLogs.length === 0 ? (
                    <Typography variant="body2" color="textSecondary">No audit history available.</Typography>
                ) : (
                    <Stepper orientation="vertical">
                        {auditLogs.map((log, index) => {
                            const isLatest = index === 0;

                            const prevLog = auditLogs[index + 1];

                            let currentProps = {};
                            let prevProps = {};
                            try { currentProps = typeof log.properties === 'string' ? JSON.parse(log.properties) : (log.properties || {}); } catch(e) {}
                            try { prevProps = prevLog ? (typeof prevLog.properties === 'string' ? JSON.parse(prevLog.properties) : (prevLog.properties || {})) : {}; } catch(e) {}

                            const sizeDiff = prevLog ? ((currentProps.size || 0) - (prevProps.size || 0)) : 0;
                            const isSizeChanged = sizeDiff !== 0;
                            const isResolutionChanged = prevLog && currentProps.resolution && currentProps.resolution !== prevProps.resolution;
                            const isColorSpaceChanged = prevLog && currentProps.color_space && currentProps.color_space !== prevProps.color_space;

                            const actionLabel = log.action_type === 'image_edit' ? 'Image Edited' :
                                log.action_type === 'branched_edit' ? 'Branched to New Version' :
                                    log.action_type === 'cloned_edit' ? 'Cloned from Existing' :
                                        'Asset Ingested';

                            return (
                                <Step key={log.id} expanded active={isLatest}>
                                    <StepLabel
                                        icon={
                                            <Box sx={{
                                                bgcolor: isLatest ? '#4f46e5' : '#e2e8f0',
                                                color: isLatest ? '#fff' : '#64748b',
                                                borderRadius: '50%', width: 26, height: 26,
                                                display: 'flex', alignItems: 'center', justifyContent: 'center',
                                                fontSize: '0.75rem', fontWeight: 'bold',
                                                boxShadow: isLatest ? '0 0 0 4px #e0e7ff' : 'none'
                                            }}>
                                                V{log.version_number}
                                            </Box>
                                        }
                                    >
                                        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', width: '100%', pr: 1 }}>
                                            <Box>
                                                <Typography variant="body2" fontWeight={isLatest ? "700" : "600"} color={isLatest ? "textPrimary" : "textSecondary"}>
                                                    {actionLabel}
                                                </Typography>
                                                <Typography variant="caption" color="textSecondary" sx={{ display: 'flex', alignItems: 'center', mt: 0.25 }}>
                                                    <AccessTime fontSize="inherit" sx={{ mr: 0.5 }} />
                                                    {new Date(log.created_at).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })}
                                                </Typography>
                                            </Box>
                                        </Box>
                                    </StepLabel>
                                    <StepContent>
                                        <Paper elevation={0} sx={{ p: 1.5, bgcolor: isLatest ? '#f8fafc' : '#fcfcfd', border: '1px solid #e2e8f0', borderRadius: 2, mt: 1, mb: 1.5 }}>

                                            <Stack spacing={1}>
                                                {/* Actor Info */}
                                                <Typography variant="caption" sx={{ display: 'flex', alignItems: 'center', color: '#475569' }}>
                                                    <Person fontSize="inherit" sx={{ mr: 0.75, color: '#94a3b8' }} />
                                                    Actor ID:&nbsp;<strong>{log.created_by_id || 'System'}</strong>
                                                </Typography>

                                                {/* Delta Indicators */}
                                                <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1, mt: 0.5 }}>
                                                    {/* File Size Chip */}
                                                    {currentProps.size && (
                                                        <Chip
                                                            icon={<Storage fontSize="small" />}
                                                            label={
                                                                <span>
                                                                    {formatBytes(currentProps.size)}
                                                                    {isSizeChanged && (
                                                                        <span style={{ color: sizeDiff > 0 ? '#ef4444' : '#22c55e', marginLeft: '4px' }}>
                                                                            ({sizeDiff > 0 ? '+' : ''}{formatBytes(sizeDiff)})
                                                                        </span>
                                                                    )}
                                                                </span>
                                                            }
                                                            size="small"
                                                            variant="outlined"
                                                            sx={{ fontSize: '0.7rem', color: '#475569', borderColor: '#e2e8f0' }}
                                                        />
                                                    )}

                                                    {/* Resolution Chip */}
                                                    {currentProps.resolution && (
                                                        <Chip
                                                            icon={<AspectRatio fontSize="small" />}
                                                            label={
                                                                <span>
                                                                    {currentProps.resolution}
                                                                    {isResolutionChanged && <span style={{ color: '#f59e0b', marginLeft: '4px' }}>(Modified)</span>}
                                                                </span>
                                                            }
                                                            size="small"
                                                            variant="outlined"
                                                            sx={{ fontSize: '0.7rem', color: '#475569', borderColor: '#e2e8f0' }}
                                                        />
                                                    )}

                                                    {/* 🚀 NEW: Color Space Chip */}
                                                    {currentProps.color_space && (
                                                        <Chip
                                                            icon={<Palette fontSize="small" />}
                                                            label={
                                                                <span>
                                                                    {currentProps.color_space}
                                                                    {isColorSpaceChanged && <span style={{ color: '#f59e0b', marginLeft: '4px' }}>(Modified)</span>}
                                                                </span>
                                                            }
                                                            size="small"
                                                            variant="outlined"
                                                            sx={{ fontSize: '0.7rem', color: '#475569', borderColor: '#e2e8f0' }}
                                                        />
                                                    )}

                                                    {/* 🚀 NEW: Background Processing Timestamp Chip */}
                                                    {currentProps.processed_at && (
                                                        <Chip
                                                            icon={<TaskAlt fontSize="small" />}
                                                            label={`Processed: ${new Date(currentProps.processed_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}`}
                                                            size="small"
                                                            variant="outlined"
                                                            sx={{ fontSize: '0.7rem', color: '#475569', borderColor: '#e2e8f0' }}
                                                        />
                                                    )}

                                                    {/* Action Type Chip for branches/clones */}
                                                    {(log.action_type === 'branched_edit' || log.action_type === 'cloned_edit') && (
                                                        <Chip
                                                            icon={<CallSplit fontSize="small" />}
                                                            label="Timeline Forked"
                                                            size="small"
                                                            sx={{ fontSize: '0.7rem', bgcolor: '#fef3c7', color: '#b45309', border: 'none' }}
                                                        />
                                                    )}
                                                </Box>

                                            </Stack>
                                        </Paper>
                                    </StepContent>
                                </Step>
                            );
                        })}
                    </Stepper>
                )}
            </Box>
        </Box>
    );
}