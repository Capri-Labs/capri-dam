import React, { useState } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Button, Box, Typography, Stack, Radio, RadioGroup,
    FormControlLabel, FormControl, Divider
} from '@mui/material';
import { Crop, RotateRight, CheckCircle } from '@mui/icons-material';

export default function ImageEditorDialog({ asset, open, onClose, onSave }) {
    const [saveMode, setSaveMode] = useState('version'); // 'version' or 'new'
    const [isSaving, setIsSaving] = useState(false);

    const handleSave = async () => {
        setIsSaving(true);

        // FUTURE: Extract the cropped Canvas blob here using react-image-crop
        // const croppedBlob = await getCroppedImg(imageRef, crop);

        const payload = {
            save_mode: saveMode,
            // crop_data: { x, y, width, height } <-- Send to Rails if doing backend cropping
        };

        // Example API Call
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const response = await fetch(`/api/v1/assets/${asset.id}/process_image`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken
                },
                body: JSON.stringify(payload)
            });

            if (response.ok) {
                const updatedAsset = await response.json();
                onSave(updatedAsset);
            } else {
                alert("Failed to save image.");
            }
        } catch (error) {
            console.error(error);
        } finally {
            setIsSaving(false);
        }
    };

    return (
        <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
            <DialogTitle sx={{ fontWeight: 700 }}>Edit Image</DialogTitle>

            <DialogContent dividers sx={{ bgcolor: '#1e293b', p: 4, display: 'flex', justifyContent: 'center' }}>
                {/* FUTURE: Wrap this image in <ReactCrop> component here
                */}
                <Box
                    component="img"
                    src={asset.url}
                    sx={{ maxWidth: '100%', maxHeight: '50vh', objectFit: 'contain' }}
                />
            </DialogContent>

            <Box sx={{ px: 3, py: 2, bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0' }}>
                <Stack direction="row" spacing={2}>
                    <Button startIcon={<Crop />} variant="outlined">Crop</Button>
                    <Button startIcon={<RotateRight />} variant="outlined">Rotate</Button>
                </Stack>
            </Box>

            <DialogContent>
                <Typography variant="subtitle2" sx={{ mb: 2, fontWeight: 700 }}>Save Options</Typography>
                <FormControl component="fieldset">
                    <RadioGroup value={saveMode} onChange={(e) => setSaveMode(e.target.value)}>
                        <FormControlLabel
                            value="version"
                            control={<Radio />}
                            label={
                                <Box>
                                    <Typography variant="body2" fontWeight="bold">Save as New Version</Typography>
                                    <Typography variant="caption" color="textSecondary">Overwrites the current asset. The old version will be kept in history.</Typography>
                                </Box>
                            }
                            sx={{ mb: 1 }}
                        />
                        <Divider sx={{ my: 1 }} />
                        <FormControlLabel
                            value="new"
                            control={<Radio />}
                            label={
                                <Box>
                                    <Typography variant="body2" fontWeight="bold">Save as New Asset</Typography>
                                    <Typography variant="caption" color="textSecondary">Creates a brand new file in the current folder.</Typography>
                                </Box>
                            }
                        />
                    </RadioGroup>
                </FormControl>
            </DialogContent>

            <DialogActions sx={{ p: 3, pt: 0 }}>
                <Button onClick={onClose} disabled={isSaving}>Cancel</Button>
                <Button
                    onClick={handleSave}
                    variant="contained"
                    color="primary"
                    startIcon={<CheckCircle />}
                    disabled={isSaving}
                >
                    {isSaving ? "Processing..." : "Confirm & Save"}
                </Button>
            </DialogActions>
        </Dialog>
    );
}