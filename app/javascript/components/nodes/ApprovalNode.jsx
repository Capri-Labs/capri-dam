import React, { useState } from 'react';
import { Handle, Position } from '@xyflow/react';
import { useTranslation } from 'react-i18next';
import {
    Box, Typography, TextField, FormControl, InputLabel, Select, MenuItem,
    Paper, Stack, Autocomplete, Accordion, AccordionSummary, AccordionDetails, Divider
} from '@mui/material';
import { ExpandMore, Person, Shield } from '@mui/icons-material';

export default function ApprovalNode({ data, isConnectable }) {
    const { t } = useTranslation();
    const { step = {}, updateNodeData, users = [], groups = [] } = data;
    const [advancedOpen, setAdvancedOpen] = useState(false);

    const handleChange = (field, value) => {
        updateNodeData(step.id, field, value);
    };

    return (
        <Paper elevation={4} sx={{ width: 380, borderRadius: 2, borderTop: '6px solid #5e35b1', bgcolor: '#ffffff', overflow: 'hidden' }}>

            <Handle type="target" position={Position.Top} isConnectable={isConnectable} style={{ width: 14, height: 14, background: '#5e35b1' }} />

            <Box sx={{ p: 2, bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: 1 }}>
                <Person sx={{ color: '#5e35b1' }} fontSize="small" />
                <Typography variant="subtitle2" sx={{ fontWeight: 800, color: '#1e293b' }}>
                    {t('nodes.approval.title')}
                </Typography>
            </Box>

            <Stack spacing={2} sx={{ p: 2 }}>
                <TextField
                    fullWidth size="small" label={t('nodes.stepTitle')} placeholder="e.g. Legal Review"
                    value={step.title || ''}
                    onChange={(e) => handleChange('title', e.target.value)}
                    className="nodrag"
                />

                <Stack direction="row" spacing={1}>
                    <FormControl size="small" sx={{ width: 120 }} className="nodrag">
                        <InputLabel>{t('nodes.approval.assigneeType')}</InputLabel>
                        <Select
                            value={step.assigneeType || 'user'} label={t('nodes.approval.assigneeType')}
                            onChange={(e) => {
                                handleChange('assigneeType', e.target.value);
                                handleChange('assigneeId', '');
                            }}
                        >
                            <MenuItem value="user">{t('nodes.approval.typeUser')}</MenuItem>
                            <MenuItem value="group">{t('nodes.approval.typeGroup')}</MenuItem>
                        </Select>
                    </FormControl>

                    <Autocomplete
                        size="small" className="nodrag" sx={{ flexGrow: 1 }}
                        options={step.assigneeType === 'user' ? users : groups}
                        getOptionLabel={(opt) => step.assigneeType === 'user' ? (opt.display_name || opt.email || 'Unknown') : (opt.name || 'Unknown')}
                        value={(step.assigneeType === 'user' ? users : groups).find(o => String(o.id) === String(step.assigneeId)) || null}
                        onChange={(e, val) => handleChange('assigneeId', val ? val.id : '')}
                        renderInput={(params) => (
                            <TextField {...params} label={step.assigneeType === 'user' ? t('nodes.approval.searchUser') : t('nodes.approval.searchGroup')} />
                        )}
                    />
                </Stack>

                <Stack direction="row" spacing={1}>
                    <FormControl size="small" sx={{ flexGrow: 1 }} className="nodrag">
                        <InputLabel>{t('nodes.approval.logic')}</InputLabel>
                        <Select
                            value={step.logic || 'any'} label={t('nodes.approval.logic')}
                            onChange={(e) => handleChange('logic', e.target.value)}
                        >
                            <MenuItem value="any">{t('nodes.approval.logicAny')}</MenuItem>
                            <MenuItem value="all">{t('nodes.approval.logicAll')}</MenuItem>
                        </Select>
                    </FormControl>

                    <TextField
                        size="small" type="number" label={t('nodes.approval.sla')}
                        value={step.deadline_days || 2}
                        onChange={(e) => handleChange('deadline_days', e.target.value)}
                        slotProps={{ input: { endAdornment: <Typography variant="caption" sx={{ ml: 1 }}>{t('nodes.approval.slaDays')}</Typography> } }}
                        sx={{ width: 100 }}
                        className="nodrag"
                    />
                </Stack>
            </Stack>

            <Accordion expanded={advancedOpen} onChange={() => setAdvancedOpen(!advancedOpen)} disableGutters elevation={0} sx={{ '&:before': { display: 'none' }, borderTop: '1px solid #e2e8f0' }}>
                <AccordionSummary expandIcon={<ExpandMore />} sx={{ bgcolor: '#f8fafc', minHeight: '40px', '& .MuiAccordionSummary-content': { my: 1 } }}>
                    <Typography variant="caption" fontWeight="bold" color="text.secondary">{t('nodes.approval.advancedSettings')}</Typography>
                </AccordionSummary>
                <AccordionDetails sx={{ pt: 0, pb: 2, px: 2 }}>
                    <Stack spacing={2} sx={{ mt: 1 }}>
                        <TextField
                            fullWidth multiline rows={2} size="small" label={t('nodes.approval.instructions')}
                            value={step.description || ''}
                            onChange={(e) => handleChange('description', e.target.value)}
                            className="nodrag"
                        />

                        <Divider>
                            <Typography variant="caption" color="warning.main">
                                <Shield fontSize="inherit"/> {t('nodes.approval.fallback')}
                            </Typography>
                        </Divider>

                        <Stack direction="row" spacing={1}>
                            <FormControl size="small" sx={{ width: 100 }} className="nodrag">
                                <Select
                                    value={step.fallback_assignee_type || 'user'}
                                    onChange={(e) => {
                                        handleChange('fallback_assignee_type', e.target.value);
                                        handleChange('fallback_assignee_id', '');
                                    }}
                                >
                                    <MenuItem value="user">{t('nodes.approval.typeUser')}</MenuItem>
                                    <MenuItem value="group">{t('nodes.approval.typeGroup')}</MenuItem>
                                </Select>
                            </FormControl>

                            <Autocomplete
                                size="small" className="nodrag" sx={{ flexGrow: 1 }}
                                options={step.fallback_assignee_type === 'user' ? users : groups}
                                getOptionLabel={(opt) => step.fallback_assignee_type === 'user' ? (opt.display_name || opt.email || '') : (opt.name || '')}
                                value={(step.fallback_assignee_type === 'user' ? users : groups).find(o => String(o.id) === String(step.fallback_assignee_id)) || null}
                                onChange={(e, val) => handleChange('fallback_assignee_id', val ? val.id : '')}
                                renderInput={(params) => <TextField {...params} label={t('nodes.approval.escalateTo')} />}
                            />
                        </Stack>
                    </Stack>
                </AccordionDetails>
            </Accordion>

            <Handle type="source" position={Position.Bottom} id="approved" style={{ left: '25%', background: '#22c55e', width: 14, height: 14 }} isConnectable={isConnectable} />
            <Handle type="source" position={Position.Bottom} id="rejected" style={{ left: '75%', background: '#ef4444', width: 14, height: 14 }} isConnectable={isConnectable} />

            <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 0, px: 3, pb: 1, bgcolor: '#f8fafc', borderTop: '1px solid #e2e8f0' }}>
                <Typography variant="caption" sx={{ color: '#22c55e', fontWeight: 800 }}>{t('nodes.approval.onApprove')}</Typography>
                <Typography variant="caption" sx={{ color: '#ef4444', fontWeight: 800 }}>{t('nodes.approval.onDecline')}</Typography>
            </Box>
        </Paper>
    );
}
