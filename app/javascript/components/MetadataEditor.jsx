import React, { useState } from 'react';
import { Drawer, Box, Typography, Tabs, Tab, TextField, Button, Stack, Divider } from '@mui/material';
import { Save, Image as ImageIcon, Info as InfoIcon } from '@mui/icons-material';

export default function MetadataEditor({ asset, onClose }) {
    const [tab, setTab] = useState(0);

    if (!asset) return null;

    return (
        <Drawer anchor="right" open={!!asset} onClose={onClose} PaperProps={{ sx: { width: 400 } }}>
            <Box sx={{ borderBottom: 1, borderColor: 'divider' }}>
                <Tabs value={tab} onChange={(e, v) => setTab(v)} variant="fullWidth">
                    <Tab icon={<InfoIcon />} label="Metadata" />
                    <Tab icon={<ImageIcon />} label="Editor" disabled={asset.file_type !== 'image'} />
                </Tabs>
            </Box>

            <Box sx={{ p: 3 }}>
                {tab === 0 && (
                    <Stack spacing={3}>
                        <Typography variant="h6">Asset Details</Typography>
                        <TextField label="Name" fullWidth defaultValue={asset.name} variant="outlined" />

                        <Divider>Governance Metadata</Divider>
                        <TextField
                            label="Description"
                            fullWidth
                            multiline
                            rows={3}
                            defaultValue={asset.metadata?.description}
                        />
                        <TextField label="Copyright / Usage" fullWidth defaultValue={asset.metadata?.usage} />
                        <TextField label="Tags" placeholder="Separate with commas" fullWidth />

                        <Button variant="contained" startIcon={<Save />} size="large" fullWidth>
                            Save Changes
                        </Button>
                    </Stack>
                )}

                {tab === 1 && (
                    <Box sx={{ textAlign: 'center', py: 10 }}>
                        <Typography color="text.secondary">
                            Image Editing Module will be initialized here.
                        </Typography>
                    </Box>
                )}
            </Box>
        </Drawer>
    );
}