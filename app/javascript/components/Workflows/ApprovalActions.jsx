import React, { useState } from 'react';
import { Box, Button, TextField, Stack, Typography, Paper } from '@mui/material';
import { CheckCircle, Cancel } from '@mui/icons-material';

export default function ApprovalActions({ assetId, currentStep, onActionComplete }) {
    const [note, setNote] = useState('');

    const handleAction = (status) => {
        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        fetch(`/assets/${assetId}/workflow_action`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
            body: JSON.stringify({ action: status, note: note })
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) onActionComplete(data);
            });
    };

    return (
        <Paper sx={{ p: 2, border: '1px solid #e3e8ef', bgcolor: '#f8f9fa' }}>
            <Typography variant="subtitle2" gutterBottom>Reviewer Actions</Typography>
            <TextField
                fullWidth multiline rows={2}
                placeholder="Add a reason for approval or decline..."
                value={note}
                onChange={(e) => setNote(e.target.value)}
                sx={{ mb: 2, bgcolor: 'white' }}
            />
            <Stack direction="row" spacing={2}>
                <Button
                    fullWidth variant="contained" color="success"
                    startIcon={<CheckCircle />}
                    onClick={() => handleAction('approve')}
                >
                    Approve
                </Button>
                <Button
                    fullWidth variant="outlined" color="error"
                    startIcon={<Cancel />}
                    onClick={() => handleAction('decline')}
                >
                    Decline
                </Button>
            </Stack>
        </Paper>
    );
}