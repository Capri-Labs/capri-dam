import React, { useState } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Box, Typography, Button, TextField, Select, MenuItem,
    FormControl, InputLabel, IconButton, Stack, Alert
} from '@mui/material';
import { AddOutlined, CloseOutlined } from '@mui/icons-material';

export default function NewSchemaDialog({ open, onClose, onCreate, parentSchemas = [] }) {
    const [name,         setName]         = useState('');
    const [description,  setDescription]  = useState('');
    const [level,        setLevel]        = useState('root');
    const [parentId,     setParentId]     = useState('');
    const [mimeSegment,  setMimeSegment]  = useState('');
    const [saving,       setSaving]       = useState(false);
    const [error,        setError]        = useState('');

    // Flatten tree to find all non-subtype schemas (valid parents)
    const flattenSchemas = (schemas, depth = 0) => {
        const result = [];
        for (const s of schemas) {
            result.push({ ...s, depth });
            if (s.children?.length && s.level !== 'type') {
                result.push(...flattenSchemas(s.children, depth + 1));
            }
        }
        return result;
    };

    const parentOptions = level === 'root' ? [] :
        flattenSchemas(parentSchemas).filter(s =>
            level === 'type'    ? s.level === 'root' :
            level === 'subtype' ? s.level === 'type'  : false
        );

    const handleSubmit = async () => {
        if (!name.trim()) { setError('Name is required.'); return; }
        if (level !== 'root' && !parentId) { setError('Parent schema is required for type/subtype.'); return; }
        if (level !== 'root' && !mimeSegment.trim()) { setError('MIME segment is required for type/subtype.'); return; }
        setSaving(true);
        setError('');
        const payload = {
            name: name.trim(),
            description: description.trim() || null,
            level,
            parent_id:    parentId || null,
            mime_segment: mimeSegment.trim() || null,
            tabs: [],
        };
        const ok = await onCreate(payload);
        if (!ok) setSaving(false);
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth
            slotProps={{ paper: { sx: { borderRadius: 3 } } }}>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1,
                               borderBottom: '1px solid #f1f5f9', pb: 1.5 }}>
                <AddOutlined sx={{ color: '#5e35b1' }} />
                <Typography fontWeight={700} sx={{ flex: 1, color: '#1e293b' }}>
                    New Metadata Schema
                </Typography>
                <IconButton size="small" onClick={onClose}><CloseOutlined fontSize="small" /></IconButton>
            </DialogTitle>

            <DialogContent sx={{ pt: 3 }}>
                {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

                <Stack spacing={2.5}>
                    <TextField label="Name" size="small" fullWidth required
                               value={name} onChange={e => setName(e.target.value)}
                               helperText="A descriptive name, e.g. 'Magazine Assets' or 'Product Photos'" />

                    <TextField label="Description" size="small" fullWidth multiline rows={2}
                               value={description} onChange={e => setDescription(e.target.value)} />

                    <FormControl fullWidth size="small">
                        <InputLabel id="schema-level-label">Schema Level</InputLabel>
                        <Select labelId="schema-level-label" value={level} label="Schema Level"
                                onChange={e => { setLevel(e.target.value); setParentId(''); setMimeSegment(''); }}>
                            <MenuItem value="root">Root — top-level, applied to folders</MenuItem>
                            <MenuItem value="type">Type — matches a MIME type (e.g. image/*)</MenuItem>
                            <MenuItem value="subtype">Subtype — matches a specific MIME (e.g. image/jpeg)</MenuItem>
                        </Select>
                    </FormControl>

                    {level !== 'root' && (
                        <>
                            <FormControl fullWidth size="small" required>
                                <InputLabel id="parent-schema-label">Parent Schema</InputLabel>
                                <Select labelId="parent-schema-label" value={parentId} label="Parent Schema"
                                        onChange={e => setParentId(e.target.value)}>
                                    {parentOptions.map(s => (
                                        <MenuItem key={s.id} value={s.id}>
                                            {'  '.repeat(s.depth)}{s.name}
                                        </MenuItem>
                                    ))}
                                </Select>
                            </FormControl>

                            <TextField label="MIME Segment" size="small" fullWidth required
                                       value={mimeSegment}
                                       onChange={e => setMimeSegment(e.target.value.toLowerCase())}
                                       helperText={
                                           level === 'type'
                                               ? "The MIME type, e.g. 'image', 'application', 'video'"
                                               : "The MIME subtype, e.g. 'jpeg', 'pdf', 'mp4'"
                                       } />
                        </>
                    )}

                    {level === 'root' && (
                        <Box sx={{ bgcolor: '#f0fdf4', border: '1px solid #bbf7d0', borderRadius: 2, p: 1.5 }}>
                            <Typography variant="caption" sx={{ color: '#166534' }}>
                                Root schemas can be applied to asset folders. You can add type and subtype
                                sub-schemas after creation to build a MIME-based resolution hierarchy.
                            </Typography>
                        </Box>
                    )}
                </Stack>
            </DialogContent>

            <DialogActions sx={{ px: 3, py: 2, borderTop: '1px solid #f1f5f9' }}>
                <Button onClick={onClose} sx={{ textTransform: 'none', color: '#64748b' }}>
                    Cancel
                </Button>
                <Button variant="contained" onClick={handleSubmit} disabled={saving}
                        sx={{ textTransform: 'none', bgcolor: '#5e35b1', '&:hover': { bgcolor: '#4527a0' } }}>
                    {saving ? 'Creating…' : 'Create Schema'}
                </Button>
            </DialogActions>
        </Dialog>
    );
}

