import React from 'react';
import { Box, Typography, Stack, Button } from '@mui/material';
import { BackupTable, AddLink, Refresh } from '@mui/icons-material';

export default function ConnectorsTopBar({ onAddClick, onRefresh }) {
    return (
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 2, width: '100%', pb: 3, mb: 2, borderBottom: '1px solid #e2e8f0' }}>
            <Box>
                <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926', mb: 1, display: 'flex', alignItems: 'center' }}>
                    <BackupTable sx={{ mr: 1.5, color: '#0ea5e9', fontSize: 32 }} />
                    System Connectors
                </Typography>
                <Typography variant="body2" color="textSecondary" sx={{ maxWidth: 600 }}>
                    Configure secure ingestion bridges from legacy monoliths and external storage. Pipe incoming payloads through the AI Gateway to eliminate structural debt.
                </Typography>
            </Box>

            <Stack direction="row" spacing={1.5} sx={{
  alignItems: "center"
}}>
                <Button
                    variant="outlined"
                    startIcon={<Refresh />}
                    onClick={onRefresh}
                    sx={{ textTransform: 'none', borderRadius: '8px', color: '#475569', borderColor: '#cbd5e1', bgcolor: '#ffffff' }}
                >
                    Refresh Status
                </Button>
                <Button
                    variant="contained"
                    startIcon={<AddLink />}
                    onClick={onAddClick}
                    sx={{ textTransform: 'none', borderRadius: '8px', boxShadow: 'none', bgcolor: '#0ea5e9', '&:hover': { bgcolor: '#0284c7' } }}
                >
                    Add Connector
                </Button>
            </Stack>
        </Box>
    );
}