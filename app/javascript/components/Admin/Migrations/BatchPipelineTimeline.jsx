import React from 'react';
import {
    Stepper, Step, StepLabel, Box, Typography, useTheme, useMediaQuery
} from '@mui/material';
import {
    Settings, CloudDownload, AutoAwesome, RateReview, CheckCircle, ErrorOutlined, HourglassEmpty
} from '@mui/icons-material';
import { CircularProgress } from '@mui/material';

// ─────────────────────────────────────────────────────────────────────────────
// Pipeline phase definitions — ordered to match the IngestionBatch state machine
// ─────────────────────────────────────────────────────────────────────────────
const PIPELINE_STEPS = [
    {
        status:  'initializing',
        label:   'Initializing',
        icon:    <Settings fontSize="small" />,
        desc:    'Setting up pipeline & credentials',
        color:   '#64748b',
    },
    {
        status:  'extracting',
        label:   'Extracting Files',
        icon:    <CloudDownload fontSize="small" />,
        desc:    'Pulling assets from legacy source',
        color:   '#0ea5e9',
    },
    {
        status:  'transforming',
        label:   'AI Transforming',
        icon:    <AutoAwesome fontSize="small" />,
        desc:    'Normalizing metadata via AI Gateway',
        color:   '#8b5cf6',
    },
    {
        status:  'review_needed',
        label:   'Awaiting Review',
        icon:    <RateReview fontSize="small" />,
        desc:    'Human approval required',
        color:   '#f59e0b',
    },
    {
        status:  'committed',
        label:   'Committed',
        icon:    <CheckCircle fontSize="small" />,
        desc:    'Assets live in DAM',
        color:   '#16a34a',
    },
];

const STATUS_TO_STEP_IDX = Object.fromEntries(
    PIPELINE_STEPS.map((s, i) => [ s.status, i ])
);

// Custom icon rendered inside each Step
function PipelineStepIcon({ status, stepStatus, stepIndex, isFailed }) {
    const step = PIPELINE_STEPS[stepIndex];

    if (isFailed && stepStatus === 'active') {
        return (
            <Box sx={{ width: 28, height: 28, borderRadius: '50%', bgcolor: '#fee2e2', border: '2px solid #dc2626', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <ErrorOutlined sx={{ fontSize: 16, color: '#dc2626' }} />
            </Box>
        );
    }
    if (stepStatus === 'completed') {
        return (
            <Box sx={{ width: 28, height: 28, borderRadius: '50%', bgcolor: '#dcfce7', border: '2px solid #16a34a', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <CheckCircle sx={{ fontSize: 16, color: '#16a34a' }} />
            </Box>
        );
    }
    if (stepStatus === 'active') {
        // Show spinner for extracting / transforming; hold icon for review_needed
        const showSpinner = [ 'initializing', 'extracting', 'transforming' ].includes(status);
        return (
            <Box sx={{ width: 28, height: 28, borderRadius: '50%', bgcolor: '#eff6ff', border: `2px solid ${step.color}`, display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'relative' }}>
                {showSpinner ? (
                    <CircularProgress size={14} sx={{ color: step.color }} />
                ) : (
                    React.cloneElement(step.icon, { sx: { fontSize: 14, color: step.color } })
                )}
            </Box>
        );
    }
    return (
        <Box sx={{ width: 28, height: 28, borderRadius: '50%', bgcolor: '#f8fafc', border: '2px solid #e2e8f0', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <HourglassEmpty sx={{ fontSize: 14, color: '#94a3b8' }} />
        </Box>
    );
}

/**
 * Renders a horizontal (or vertical on small screens) Stepper showing
 * the 5 pipeline phases and the batch's current position.
 *
 * @param {string} status — current IngestionBatch status
 */
export default function BatchPipelineTimeline({ status }) {
    const theme       = useTheme();
    const isSmall     = useMediaQuery(theme.breakpoints.down('sm'));
    const isFailed    = status === 'failed';
    const currentIdx  = STATUS_TO_STEP_IDX[status] ?? 0;
    const activeStep  = isFailed ? currentIdx : currentIdx;

    return (
        <Box sx={{ width: '100%', py: 1 }}>
            <Stepper
                activeStep={activeStep}
                orientation={isSmall ? 'vertical' : 'horizontal'}
                sx={{
                    '& .MuiStepConnector-line': {
                        borderTopWidth: 2,
                        borderColor: '#e2e8f0',
                    },
                    '& .MuiStepConnector-root.Mui-completed .MuiStepConnector-line': {
                        borderColor: '#16a34a',
                    },
                    '& .MuiStepConnector-root.Mui-active .MuiStepConnector-line': {
                        borderColor: '#0ea5e9',
                    },
                }}
            >
                {PIPELINE_STEPS.map((step, i) => {
                    let stepStatus;
                    if (i < currentIdx)         stepStatus = 'completed';
                    else if (i === currentIdx)  stepStatus = 'active';
                    else                        stepStatus = 'pending';

                    return (
                        <Step key={step.status} completed={stepStatus === 'completed'}>
                            <StepLabel
                                error={isFailed && i === currentIdx}
                                StepIconComponent={() => (
                                    <PipelineStepIcon
                                        status={status}
                                        stepStatus={stepStatus}
                                        stepIndex={i}
                                        isFailed={isFailed}
                                    />
                                )}
                                sx={{
                                    '& .MuiStepLabel-label': {
                                        fontSize: '0.72rem',
                                        fontWeight: stepStatus === 'active' ? 700 : 500,
                                        color: stepStatus === 'active'
                                            ? step.color
                                            : stepStatus === 'completed'
                                            ? '#16a34a'
                                            : '#94a3b8',
                                    },
                                }}
                            >
                                <Typography variant="caption" component="span" display="block" sx={{ fontWeight: 'inherit', color: 'inherit' }}>
                                    {step.label}
                                </Typography>
                                {!isSmall && (
                                    <Typography variant="caption" component="span" display="block" sx={{ fontSize: '0.65rem', color: '#94a3b8', fontWeight: 400 }}>
                                        {step.desc}
                                    </Typography>
                                )}
                            </StepLabel>
                        </Step>
                    );
                })}
            </Stepper>
        </Box>
    );
}

