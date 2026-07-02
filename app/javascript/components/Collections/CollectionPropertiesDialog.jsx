import React, { useState, useEffect } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Button, TextField, FormControl, FormLabel, Select, MenuItem,
    Typography, Box, Stack, Autocomplete, Chip, Checkbox, FormControlLabel,
    Divider, CircularProgress, Tooltip
} from '@mui/material';
import { AutoAwesome, Security, Label } from '@mui/icons-material';
import { useCollections } from './CollectionContext';

const AVAILABLE_GROUPS = ["Global Admin", "EMEA Marketing", "APAC Marketing", "Legal & Compliance", "External Agencies"];
const SUGGESTED_TAGS = ["Q3 Campaign", "Black Friday", "Social Media", "Print Ready", "Embargoed"];

export default function CollectionPropertiesDialog({ open, onClose, selectedCollections = [] }) {
    const { updateCollection, bulkUpdateCollections } = useCollections();
    const isBulk = selectedCollections.length > 1;

    // UI State for AI operations
    const [aiGenerating, setAiGenerating] = useState(false);

    // Form State
    const [formData, setFormData] = useState({
        name: '',
        description: '',
        ttl_days: 'never',
        tags: [],
        allowed_groups: [],
        denied_groups: []
    });

    // In Bulk Mode, we only send fields the user explicitly checked to change
    const [modifyFlags, setModifyFlags] = useState({
        ttl_days: false,
        tags: false,
        access: false
    });

    useEffect(() => {
        if (open && !isBulk && selectedCollections.length === 1) {
            const col = selectedCollections[0];
            const props = col.properties || {};
            setFormData({
                name: col.name || '',
                description: col.description || '',
                ttl_days: col.expires_at ? 'custom' : 'never', // Simplified for UI
                tags: Array.isArray(props.tags) ? props.tags : [],
                allowed_groups: Array.isArray(props.allowed_groups) ? props.allowed_groups : [],
                denied_groups: Array.isArray(props.denied_groups) ? props.denied_groups : []
            });
        } else if (open && isBulk) {
            // Reset for clean bulk edit slate
            setFormData({ name: '', description: '', ttl_days: 'never', tags: [], allowed_groups: [], denied_groups: [] });
            setModifyFlags({ ttl_days: false, tags: false, access: false });
        }
    }, [open, selectedCollections, isBulk]);

    const handleAiSuggestion = () => {
        setAiGenerating(true);
        // Simulate sending collection asset vectors to LLM for taxonomy tagging
        setTimeout(() => {
            setFormData(prev => ({
                ...prev,
                tags: [...new Set([...prev.tags, "Social Media", "High-Contrast"])],
                description: isBulk ? prev.description : "Auto-generated: A curated selection of high-contrast social media assets optimized for digital engagement."
            }));
            if (isBulk) {
                setModifyFlags(prev => ({ ...prev, tags: true }));
            }
            setAiGenerating(false);
        }, 1200);
    };

    const handleSubmit = async () => {
        // Construct the payload mapping to your Rails schema
        const payload = {
            properties: {
                tags: formData.tags,
                allowed_groups: formData.allowed_groups,
                denied_groups: formData.denied_groups
            }
        };

        if (!isBulk) {
            payload.name = formData.name;
            payload.description = formData.description;

            // Handle TTL logic here...
            const success = await updateCollection(selectedCollections[0].slug, payload);
            if (success) onClose();
        } else {
            // Bulk Edit - Only include checked properties
            const bulkPayload = { properties: {} };
            if (modifyFlags.tags) bulkPayload.properties.tags = formData.tags;
            if (modifyFlags.access) {
                bulkPayload.properties.allowed_groups = formData.allowed_groups;
                bulkPayload.properties.denied_groups = formData.denied_groups;
            }
            // Add TTL if modifyFlags.ttl_days is true...

            const ids = selectedCollections.map(c => c.id);
            const success = await bulkUpdateCollections(ids, bulkPayload);
            if (success) onClose();
        }
    };

    if (!open) return null;

    return (
        <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
            <DialogTitle sx={{ fontWeight: 700, borderBottom: '1px solid #e2e8f0', pb: 2, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                {isBulk ? `Bulk Edit Properties (${selectedCollections.length} items)` : 'Workspace Properties'}

                <Button
                    variant="outlined"
                    size="small"
                    startIcon={aiGenerating ? <CircularProgress size={16} /> : <AutoAwesome />}
                    onClick={handleAiSuggestion}
                    disabled={aiGenerating}
                    sx={{ color: '#8e24aa', borderColor: '#f3e5f5', bgcolor: '#faf5ff' }}
                >
                    AI Auto-Tag
                </Button>
            </DialogTitle>

            <DialogContent sx={{ p: 3, mt: 1 }}>
                {/* Core Identity - Disabled in Bulk Mode */}
                {!isBulk && (
                    <>
                        <TextField fullWidth label="Collection Name" value={formData.name} onChange={(e) => setFormData({...formData, name: e.target.value})} sx={{ mb: 3 }} />
                        <TextField fullWidth multiline rows={2} label="Description" value={formData.description} onChange={(e) => setFormData({...formData, description: e.target.value})} sx={{ mb: 4 }} />
                    </>
                )}

                {/* Taxonomy & Metadata */}
                <Box sx={{ mb: 4 }}>
                    <Stack direction="row" spacing={1} sx={{
  mb: 2,
  alignItems: "center"
}}>
                        {isBulk && <Checkbox checked={modifyFlags.tags} onChange={(e) => setModifyFlags({...modifyFlags, tags: e.target.checked})} />}
                        <Label sx={{ color: '#64748b' }} />
                        <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Taxonomy & Tags</Typography>
                    </Stack>
                    <Box sx={{ pl: isBulk ? 5 : 0 }}>
                        <Autocomplete multiple disabled={isBulk && !modifyFlags.tags} options={SUGGESTED_TAGS} freeSolo value={formData.tags || []} onChange={(e, newValue) => setFormData({
  ...formData,
  tags: newValue || []
})} renderValue={(value, getTagProps) => value.map((option, index) => {
  const { key, ...tagProps } = getTagProps({ index });
  return <Chip key={key} variant="outlined" label={option} {...tagProps} size="small" sx={{
  borderColor: '#5e35b1',
  color: '#5e35b1'
}} />;
})} renderInput={params => <TextField {...params} placeholder="Add tags..." />} />
                    </Box>
                </Box>

                <Divider sx={{ mb: 4 }} />

                {/* Access & Security */}
                <Box sx={{ mb: 2 }}>
                    <Stack direction="row" spacing={1} sx={{
  mb: 2,
  alignItems: "center"
}}>
                        {isBulk && <Checkbox checked={modifyFlags.access} onChange={(e) => setModifyFlags({...modifyFlags, access: e.target.checked})} />}
                        <Security sx={{ color: '#059669' }} />
                        <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>Access Governance</Typography>
                    </Stack>

                    <Box sx={{ pl: isBulk ? 5 : 0 }}>
                        {formData.tags.includes("Embargoed") && (
                            <Typography variant="caption" sx={{ display: 'block', mb: 2, p: 1, bgcolor: '#fef2f2', color: '#b91c1c', borderRadius: 1 }}>
                                ⚠️ AI Warning: This collection contains 'Embargoed' tags. Restrict external access.
                            </Typography>
                        )}

                        <Autocomplete
                            multiple
                            disabled={isBulk && !modifyFlags.access}
                            options={AVAILABLE_GROUPS}
                            value={formData.allowed_groups}
                            onChange={(e, val) => setFormData({...formData, allowed_groups: val})}
                            renderInput={(params) => <TextField {...params} label="Allowed Groups (Whitelist)" sx={{ mb: 3 }}/>}
                        />

                        <Autocomplete
                            multiple
                            disabled={isBulk && !modifyFlags.access}
                            options={AVAILABLE_GROUPS}
                            value={formData.denied_groups}
                            onChange={(e, val) => setFormData({...formData, denied_groups: val})}
                            renderInput={(params) => <TextField {...params} label="Explicitly Denied Groups (Blacklist)" color="error" focused={formData.denied_groups.length > 0} />}
                        />
                    </Box>
                </Box>
            </DialogContent>

            <DialogActions sx={{ p: 3, pt: 0 }}>
                <Button onClick={onClose} color="inherit">Cancel</Button>
                <Button
                    onClick={handleSubmit}
                    variant="contained"
                    sx={{ bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}
                >
                    {isBulk ? 'Apply to Selected' : 'Save Properties'}
                </Button>
            </DialogActions>
        </Dialog>
    );
}