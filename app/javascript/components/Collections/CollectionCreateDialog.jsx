import React, { useState } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Button, TextField, FormControl, FormLabel, RadioGroup, FormControlLabel, Radio,
    Select, MenuItem, Typography, Box, Stack
} from '@mui/material';
import { useCollections } from './CollectionContext';

export default function CollectionCreateDialog({ open, onClose, onSuccess }) {
    const { createCollection } = useCollections();

    // 1. Add custom_date to the state payload
    const [formData, setFormData] = useState({
        name: '',
        description: '',
        collection_type: 'manual',
        ttl_days: 'never',
        custom_date: ''
    });

    const handleSubmit = async () => {
        let expires_at = null;

        // 2. Handle the custom date logic vs preset days
        if (formData.ttl_days === 'custom' && formData.custom_date) {
            expires_at = new Date(formData.custom_date).toISOString();
        } else if (formData.ttl_days !== 'never' && formData.ttl_days !== 'custom') {
            const date = new Date();
            date.setDate(date.getDate() + parseInt(formData.ttl_days));
            expires_at = date.toISOString();
        }

        const payload = {
            name: formData.name,
            description: formData.description,
            collection_type: formData.collection_type,
            expires_at: expires_at
        };

        const newCollection = await createCollection(payload);
        if (newCollection) {
            onSuccess(newCollection.slug);
            setFormData({ name: '', description: '', collection_type: 'manual', ttl_days: 'never', custom_date: '' });
            onClose();
        }
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
            <DialogTitle sx={{ fontWeight: 700, borderBottom: '1px solid #e2e8f0', pb: 2 }}>
                Create New Workspace
            </DialogTitle>
            <DialogContent sx={{ p: 3, mt: 2 }}>
                <TextField
                    autoFocus fullWidth label="Collection Name" required
                    placeholder="e.g., Q4 Black Friday Assets"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    sx={{ mb: 3 }}
                />

                <TextField
                    fullWidth multiline rows={2} label="Description"
                    value={formData.description}
                    onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                    sx={{ mb: 4 }}
                />

                <FormControl component="fieldset" sx={{ mb: 4, width: '100%' }}>
                    <FormLabel component="legend" sx={{ fontWeight: 600, color: '#1e293b', mb: 1 }}>Routing Engine</FormLabel>
                    <RadioGroup row value={formData.collection_type} onChange={(e) => setFormData({ ...formData, collection_type: e.target.value })}>
                        <FormControlLabel value="manual" control={<Radio sx={{ color: '#5e35b1' }} />} label="Manual Curation" />
                        <FormControlLabel value="smart" control={<Radio sx={{ color: '#5e35b1' }} />} label="AI Smart Routing" />
                    </RadioGroup>
                </FormControl>

                <FormControl fullWidth sx={{ mb: 1 }}>
                    <FormLabel sx={{ fontWeight: 600, color: '#1e293b', mb: 1 }}>Time-To-Live (TTL) Policy</FormLabel>
                    <Stack direction="row" spacing={2}>
                        <Select
                            value={formData.ttl_days}
                            onChange={(e) => setFormData({ ...formData, ttl_days: e.target.value })}
                            sx={{ flexGrow: 1 }}>
                            <MenuItem value="never">Never Expire (Permanent Core Asset)</MenuItem>
                            <MenuItem value="30">30 Days (Short Campaign)</MenuItem>
                            <MenuItem value="90">90 Days (Quarterly Campaign)</MenuItem>
                            <MenuItem value="365">1 Year (Annual Campaign)</MenuItem>
                            <MenuItem value="custom">Set Custom Date...</MenuItem>
                        </Select>

                        {/* 3. Render the DatePicker conditionally */}
                        {formData.ttl_days === 'custom' && (
                            <TextField
                                type="date" slotProps={{inputLabel: { shrink: true } }}
                                value={formData.custom_date}
                                onChange={(e) => setFormData({ ...formData, custom_date: e.target.value })}
                                sx={{ width: 180 }}
                            />
                        )}
                    </Stack>
                    <Typography variant="caption" color="textSecondary" sx={{ mt: 1 }}>
                        Enforce zero-noise operations by automatically archiving this workspace when the campaign ends.
                    </Typography>
                </FormControl>
            </DialogContent>
            <DialogActions sx={{ p: 3, pt: 0 }}>
                <Button onClick={onClose} color="inherit">Cancel</Button>
                <Button
                    onClick={handleSubmit}
                    variant="contained"
                    disabled={!formData.name.trim() || (formData.ttl_days === 'custom' && !formData.custom_date)}
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                >
                    Initialize Workspace
                </Button>
            </DialogActions>
        </Dialog>
    );
}