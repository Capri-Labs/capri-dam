import React, { useState } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions, Button,
    TextField, Autocomplete, Typography,
    Box, Grid, Avatar, List, ListItem, ListItemAvatar,
    ListItemText, Stack
} from '@mui/material';
import { Person, Group, WarningAmber, History } from '@mui/icons-material';

export default function BulkReassignModal({ open, onClose, selectedWorkflows, onConfirm, users, groups }) {
    const [assigneeType, setAssigneeType] = useState('user');
    const [targetEntity, setTargetEntity] = useState(null);
    const [reason, setReason] = useState('');

    // Pre-calculate summary to show "Before & After" logic
    const handleSave = () => {
        onConfirm({
            assigneeType,
            assigneeId: targetEntity?.id,
            reason
        });
        onClose();
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
            <DialogTitle sx={{ borderBottom: '1px solid #e2e8f0', bgcolor: '#f8fafc' }}>
                Bulk Re-assignment
            </DialogTitle>

            <DialogContent sx={{ p: 0 }}>
                <Grid container>
                    {/* LEFT SIDE: IMPACT CONTEXT */}
                    <Grid size={5} sx={{ p: 3, borderRight: '1px solid #e2e8f0', bgcolor: '#fdfdfd' }}>
                        <Typography variant="subtitle2" sx={{ mb: 2, fontWeight: 700, display: 'flex', alignItems: 'center', gap: 1 }}>
                            <History fontSize="small" /> Affected Workflows ({selectedWorkflows.length})
                        </Typography>

                        <List sx={{ maxHeight: 300, overflowY: 'auto' }}>
                            {selectedWorkflows.map((w) => (
                                <ListItem key={w.instance_id} sx={{ px: 0 }}>
                                    <ListItemAvatar>
                                        <Avatar variant="rounded" src={w.asset_thumb} />
                                    </ListItemAvatar>
                                    <ListItemText
                                        primary={w.asset_name}
                                        secondary={`Step: ${w.current_step}`}
                                        slotProps={{ primary: { variant: 'body2', fontWeight: 600 } }}
                                    />
                                </ListItem>
                            ))}
                        </List>
                    </Grid>

                    {/* RIGHT SIDE: CONTROL PANEL */}
                    <Grid size={7} sx={{ p: 3 }}>
                        <Typography variant="subtitle2" sx={{ mb: 2, fontWeight: 700 }}>Assignment Details</Typography>

                        <Stack direction="row" spacing={1} sx={{ mb: 3 }}>
                            <Button
                                variant={assigneeType === 'user' ? 'contained' : 'outlined'}
                                onClick={() => { setAssigneeType('user'); setTargetEntity(null); }}
                                startIcon={<Person />}
                            >User</Button>
                            <Button
                                variant={assigneeType === 'group' ? 'contained' : 'outlined'}
                                onClick={() => { setAssigneeType('group'); setTargetEntity(null); }}
                                startIcon={<Group />}
                            >Group</Button>
                        </Stack>

                        <Autocomplete
                            options={assigneeType === 'user' ? users : groups}
                            getOptionLabel={(o) => o.name || o.email}
                            onChange={(e, val) => setTargetEntity(val)}
                            renderInput={(params) => <TextField {...params} label={`Search ${assigneeType}s...`} />}
                        />

                        <TextField
                            fullWidth multiline rows={3} label="Reason for re-assignment"
                            placeholder="e.g., Covering for colleague on leave"
                            value={reason} onChange={(e) => setReason(e.target.value)}
                            sx={{ mt: 3 }}
                        />

                        {/* Audit Log Preview */}
                        <Box sx={{ mt: 3, p: 2, bgcolor: '#fff9c4', borderRadius: 1, border: '1px solid #fff59d' }}>
                            <Typography variant="caption" sx={{ display: 'flex', alignItems: 'center', gap: 1, color: '#856404' }}>
                                <WarningAmber fontSize="small" />
                                All pending tasks will be reassigned to the selected entity.
                            </Typography>
                        </Box>
                    </Grid>
                </Grid>
            </DialogContent>

            <DialogActions sx={{ p: 2 }}>
                <Button onClick={onClose}>Cancel</Button>
                <Button
                    variant="contained"
                    onClick={handleSave}
                    disabled={!targetEntity || !reason}
                    sx={{ px: 4 }}
                >
                    Execute Re-assignment
                </Button>
            </DialogActions>
        </Dialog>
    );
}
