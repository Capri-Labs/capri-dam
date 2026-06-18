import React, { useState } from 'react';
import { Handle, Position } from 'reactflow';
import {
    Box, Typography, TextField, FormControl, InputLabel, Select, MenuItem,
    Paper, Stack, Autocomplete, Accordion, AccordionSummary, AccordionDetails, Divider
} from '@mui/material';
import { ExpandMore, Person, Shield } from '@mui/icons-material';

export default function ApprovalNode({ data, isConnectable }) {
    //  We expect the parent canvas to pass 'users' and 'groups' into the data object!
    const { step = {}, updateNodeData, users = [], groups = [] } = data;
    const [advancedOpen, setAdvancedOpen] = useState(false);

    const handleChange = (field, value) => {
        updateNodeData(step.id, field, value);
    };

    return (
        <Paper elevation={4} sx={{ width: 380, borderRadius: 2, borderTop: '6px solid #5e35b1', bgcolor: '#ffffff', overflow: 'hidden' }}>

            {/* INCOMING CONNECTION */}
            <Handle type="target" position={Position.Top} isConnectable={isConnectable} style={{ width: 14, height: 14, background: '#5e35b1' }} />

            <Box sx={{ p: 2, bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: 1 }}>
                <Person sx={{ color: '#5e35b1' }} fontSize="small" />
                <Typography variant="subtitle2" sx={{ fontWeight: 800, color: '#1e293b' }}>
                    Approval Step
                </Typography>
            </Box>

            <Stack spacing={2} sx={{ p: 2 }}>
                {/* 1. TITLE */}
                <TextField
                    fullWidth size="small" label="Step Title" placeholder="e.g. Legal Review"
                    value={step.title || ''}
                    onChange={(e) => handleChange('title', e.target.value)}
                    className="nodrag" // Prevents the canvas from moving when typing
                />

                {/* 2. PRIMARY ASSIGNEE SETTINGS */}
                <Stack direction="row" spacing={1}>
                    <FormControl size="small" sx={{ width: 120 }} className="nodrag">
                        <InputLabel>Type</InputLabel>
                        <Select
                            value={step.assigneeType || 'user'} label="Type"
                            onChange={(e) => {
                                handleChange('assigneeType', e.target.value);
                                handleChange('assigneeId', ''); // Reset ID when switching types
                            }}
                        >
                            <MenuItem value="user">User</MenuItem>
                            <MenuItem value="group">Group</MenuItem>
                        </Select>
                    </FormControl>

                    <Autocomplete
                        size="small" className="nodrag" sx={{ flexGrow: 1 }}
                        options={step.assigneeType === 'user' ? users : groups}
                        getOptionLabel={(opt) => step.assigneeType === 'user' ? (opt.display_name || opt.email || 'Unknown') : (opt.name || 'Unknown')}
                        value={(step.assigneeType === 'user' ? users : groups).find(o => String(o.id) === String(step.assigneeId)) || null}
                        onChange={(e, val) => handleChange('assigneeId', val ? val.id : '')}
                        renderInput={(params) => <TextField {...params} label={`Search ${step.assigneeType}...`} />}
                    />
                </Stack>

                {/* 3. LOGIC & SLA */}
                <Stack direction="row" spacing={1}>
                    <FormControl size="small" sx={{ flexGrow: 1 }} className="nodrag">
                        <InputLabel>Logic</InputLabel>
                        <Select
                            value={step.logic || 'any'} label="Logic"
                            onChange={(e) => handleChange('logic', e.target.value)}
                        >
                            <MenuItem value="any">First to respond (Any)</MenuItem>
                            <MenuItem value="all">Unanimous (All)</MenuItem>
                        </Select>
                    </FormControl>

                    <TextField
                        size="small" type="number" label="SLA"
                        value={step.deadline_days || 2}
                        onChange={(e) => handleChange('deadline_days', e.target.value)}
                        InputProps={{ endAdornment: <Typography variant="caption" sx={{ ml: 1 }}>Days</Typography> }}
                        sx={{ width: 100 }}
                        className="nodrag"
                    />
                </Stack>
            </Stack>

            {/* 4. ADVANCED SETTINGS (COLLAPSIBLE) */}
            <Accordion expanded={advancedOpen} onChange={() => setAdvancedOpen(!advancedOpen)} disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, borderTop: '1px solid #e2e8f0' }}>
                <AccordionSummary expandIcon={<ExpandMore />} sx={{ bgcolor: '#f8fafc', minHeight: '40px', '& .MuiAccordionSummary-content': { my: 1 } }}>
                    <Typography variant="caption" fontWeight="bold" color="text.secondary">Advanced Settings & Escalation</Typography>
                </AccordionSummary>
                <AccordionDetails sx={{ pt: 0, pb: 2, px: 2 }}>
                    <Stack spacing={2} sx={{ mt: 1 }}>
                        <TextField
                            fullWidth multiline rows={2} size="small" label="Instructions for Reviewer"
                            value={step.description || ''}
                            onChange={(e) => handleChange('description', e.target.value)}
                            className="nodrag"
                        />

                        <Divider><Typography variant="caption" color="warning.main"><Shield fontSize="inherit"/> Fallback Assignee</Typography></Divider>

                        <Stack direction="row" spacing={1}>
                            <FormControl size="small" sx={{ width: 100 }} className="nodrag">
                                <Select
                                    value={step.fallback_assignee_type || 'user'}
                                    onChange={(e) => {
                                        handleChange('fallback_assignee_type', e.target.value);
                                        handleChange('fallback_assignee_id', '');
                                    }}
                                >
                                    <MenuItem value="user">User</MenuItem>
                                    <MenuItem value="group">Group</MenuItem>
                                </Select>
                            </FormControl>

                            <Autocomplete
                                size="small" className="nodrag" sx={{ flexGrow: 1 }}
                                options={step.fallback_assignee_type === 'user' ? users : groups}
                                getOptionLabel={(opt) => step.fallback_assignee_type === 'user' ? (opt.display_name || opt.email || '') : (opt.name || '')}
                                value={(step.fallback_assignee_type === 'user' ? users : groups).find(o => String(o.id) === String(step.fallback_assignee_id)) || null}
                                onChange={(e, val) => handleChange('fallback_assignee_id', val ? val.id : '')}
                                renderInput={(params) => <TextField {...params} label="Escalate to..." />}
                            />
                        </Stack>
                    </Stack>
                </AccordionDetails>
            </Accordion>

            {/* OUTGOING CONNECTIONS (Branches) */}
            <Handle type="source" position={Position.Bottom} id="approved" style={{ left: '25%', background: '#22c55e', width: 14, height: 14 }} isConnectable={isConnectable} />
            <Handle type="source" position={Position.Bottom} id="rejected" style={{ left: '75%', background: '#ef4444', width: 14, height: 14 }} isConnectable={isConnectable} />

            <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 0, px: 3, pb: 1, bgcolor: '#f8fafc', borderTop: '1px solid #e2e8f0' }}>
                <Typography variant="caption" sx={{ color: '#22c55e', fontWeight: 800 }}>ON APPROVE</Typography>
                <Typography variant="caption" sx={{ color: '#ef4444', fontWeight: 800 }}>ON DECLINE</Typography>
            </Box>
        </Paper>
    );
}