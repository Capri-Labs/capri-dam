import React from 'react';
import { Box, Typography, Stepper, Step, StepLabel, StepContent, Paper } from '@mui/material';

export default function AssetAuditTab({ asset }) {
    return (
        <Box>
            <Typography variant="subtitle1" fontWeight="700" sx={{ mb: 2 }}>Audit Trail</Typography>
            <Stepper orientation="vertical" activeStep={2} sx={{ mt: 2 }}>
                <Step expanded>
                    <StepLabel>
                        <Typography variant="body2" fontWeight="600">Asset Ingested</Typography>
                        <Typography variant="caption" color="textSecondary">{new Date(asset.created_at).toLocaleString()}</Typography>
                    </StepLabel>
                    <StepContent>
                        <Typography variant="caption" color="textSecondary">Uploaded and metadata extracted by system.</Typography>
                    </StepContent>
                </Step>
                <Step expanded>
                    <StepLabel>
                        <Typography variant="body2" fontWeight="600">Smart Routing Triggered</Typography>
                    </StepLabel>
                    <StepContent>
                        <Typography variant="caption" color="textSecondary">AI matched embeddings to existing workspaces.</Typography>
                    </StepContent>
                </Step>
                {asset.properties?.editor_state && (
                    <Step expanded>
                        <StepLabel>
                            <Typography variant="body2" fontWeight="600">Non-Destructive Edits Applied</Typography>
                        </StepLabel>
                        <StepContent>
                            <Typography variant="caption" color="textSecondary">Color and geometry properties modified.</Typography>
                        </StepContent>
                    </Step>
                )}
            </Stepper>
        </Box>
    );
}