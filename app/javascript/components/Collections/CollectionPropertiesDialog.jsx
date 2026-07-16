import React, { useState, useEffect, useCallback } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Button, TextField, FormControl, FormLabel, Select, MenuItem,
    Typography, Box, Stack, Autocomplete, Chip, Checkbox, FormControlLabel,
    Divider, CircularProgress, Tooltip, Table, TableHead, TableBody, TableRow, TableCell, IconButton
} from '@mui/material';
import { AutoAwesome, Security, Label, DeleteOutlineOutlined, AdminPanelSettings } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { useCollections } from './CollectionContext';

const SUGGESTED_TAGS = ["Q3 Campaign", "Black Friday", "Social Media", "Print Ready", "Embargoed"];

export default function CollectionPropertiesDialog({ open, onClose, selectedCollections = [] }) {
    const { t } = useTranslation();
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

    // Real user groups (replaces the previous hardcoded AVAILABLE_GROUPS list)
    const [availableGroups, setAvailableGroups] = useState([]);
    const [groupsLoading, setGroupsLoading] = useState(false);

    // Access Governance: group-scoped view/edit/admin policies (single-collection mode only)
    const [policies, setPolicies] = useState([]);
    const [policiesLoading, setPoliciesLoading] = useState(false);
    const [addGroupSelection, setAddGroupSelection] = useState(null);

    const availableGroupNames = availableGroups.map((g) => g.name);

    const fetchAvailableGroups = useCallback(async () => {
        setGroupsLoading(true);
        try {
            const res = await fetch('/api/v1/user_groups?limit=50');
            const data = await res.json();
            setAvailableGroups(Array.isArray(data) ? data : []);
        } catch (error) {
            setAvailableGroups([]);
        } finally {
            setGroupsLoading(false);
        }
    }, []);

    const fetchPolicies = useCallback(async (slug) => {
        setPoliciesLoading(true);
        try {
            const res = await fetch(`/api/v1/collections/${slug}/policies`);
            const data = await res.json();
            setPolicies(Array.isArray(data.policies) ? data.policies : []);
        } catch (error) {
            setPolicies([]);
        } finally {
            setPoliciesLoading(false);
        }
    }, []);

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
            fetchAvailableGroups();
            fetchPolicies(col.slug);
        } else if (open && isBulk) {
            // Reset for clean bulk edit slate
            setFormData({ name: '', description: '', ttl_days: 'never', tags: [], allowed_groups: [], denied_groups: [] });
            setModifyFlags({ ttl_days: false, tags: false, access: false });
            setPolicies([]);
            fetchAvailableGroups();
        }
    }, [open, selectedCollections, isBulk, fetchAvailableGroups, fetchPolicies]);

    const csrfToken = () => document.querySelector('[name="csrf-token"]')?.content;

    // Immediately persists a policy tier change for a group — Access
    // Governance is intentionally saved live rather than batched with the
    // rest of the form, since it directly controls who can reach this dialog.
    const upsertPolicy = async (group, patch) => {
        const slug = selectedCollections[0].slug;
        const existing = policies.find((p) => p.group_id === group.id) || {
            group_id: group.id, group_name: group.name,
            view_access: false, edit_access: false, admin_access: false, explicit_deny: false,
        };
        const payload = { group_id: group.id, ...existing, ...patch };

        try {
            const res = await fetch(`/api/v1/collections/${slug}/policies`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
                body: JSON.stringify(payload),
            });
            const data = await res.json();
            if (res.ok) {
                setPolicies((prev) => {
                    const others = prev.filter((p) => p.group_id !== group.id);
                    return [...others, data.policy];
                });
            }
        } catch (error) {
            // no-op — the row simply won't reflect the change
        }
    };

    const removePolicy = async (groupId) => {
        const slug = selectedCollections[0].slug;
        try {
            const res = await fetch(`/api/v1/collections/${slug}/policies/${groupId}`, {
                method: 'DELETE',
                headers: { 'X-CSRF-Token': csrfToken() },
            });
            if (res.ok) {
                setPolicies((prev) => prev.filter((p) => p.group_id !== groupId));
            }
        } catch (error) {
            // no-op
        }
    };

    const handleAddPolicyGroup = () => {
        if (!addGroupSelection) return;
        upsertPolicy(addGroupSelection, { view_access: true });
        setAddGroupSelection(null);
    };

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
                            loading={groupsLoading}
                            options={availableGroupNames}
                            value={formData.allowed_groups}
                            onChange={(e, val) => setFormData({...formData, allowed_groups: val})}
                            renderInput={(params) => <TextField {...params} label="Allowed Groups (Whitelist)" sx={{ mb: 3 }}/>}
                        />

                        <Autocomplete
                            multiple
                            disabled={isBulk && !modifyFlags.access}
                            loading={groupsLoading}
                            options={availableGroupNames}
                            value={formData.denied_groups}
                            onChange={(e, val) => setFormData({...formData, denied_groups: val})}
                            renderInput={(params) => <TextField {...params} label="Explicitly Denied Groups (Blacklist)" color="error" focused={formData.denied_groups.length > 0} />}
                        />

                        {/* Group-scoped access policy matrix (viewer/editor/collection-admin tiers) */}
                        {!isBulk && (
                            <Box sx={{ mt: 3 }}>
                                <Stack direction="row" spacing={1} sx={{ mb: 1, alignItems: 'center' }}>
                                    <AdminPanelSettings sx={{ color: '#5e35b1', fontSize: 20 }} />
                                    <Typography variant="subtitle2" sx={{ fontWeight: 600 }}>
                                        {t('collectionProperties.accessPolicies.title', 'Group Access Policies')}
                                    </Typography>
                                </Stack>
                                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 1.5 }}>
                                    {t('collectionProperties.accessPolicies.description',
                                        'Configuring even one group here switches this workspace to strict, group-governed access. Collection Admins may configure rules, manage policies, and delete the workspace.')}
                                </Typography>

                                <Stack direction="row" spacing={1} sx={{ mb: 2 }}>
                                    <Autocomplete
                                        size="small"
                                        sx={{ flexGrow: 1 }}
                                        options={availableGroups.filter((g) => !policies.some((p) => p.group_id === g.id))}
                                        getOptionLabel={(g) => g.name}
                                        value={addGroupSelection}
                                        onChange={(e, val) => setAddGroupSelection(val)}
                                        renderInput={(params) => <TextField {...params} label={t('collectionProperties.accessPolicies.addGroup', 'Add group')} />}
                                    />
                                    <Button variant="outlined" onClick={handleAddPolicyGroup} disabled={!addGroupSelection}>
                                        {t('collectionProperties.accessPolicies.add', 'Add')}
                                    </Button>
                                </Stack>

                                {policiesLoading ? (
                                    <CircularProgress size={20} />
                                ) : policies.length === 0 ? (
                                    <Typography variant="caption" color="textSecondary">
                                        {t('collectionProperties.accessPolicies.empty', 'No group policies configured — this workspace uses legacy allow/deny-list access above.')}
                                    </Typography>
                                ) : (
                                    <Table size="small">
                                        <TableHead>
                                            <TableRow>
                                                <TableCell>{t('collectionProperties.accessPolicies.group', 'Group')}</TableCell>
                                                <TableCell align="center">{t('collectionProperties.accessPolicies.viewer', 'Viewer')}</TableCell>
                                                <TableCell align="center">{t('collectionProperties.accessPolicies.editor', 'Editor')}</TableCell>
                                                <TableCell align="center">{t('collectionProperties.accessPolicies.admin', 'Collection Admin')}</TableCell>
                                                <TableCell align="center">{t('collectionProperties.accessPolicies.deny', 'Deny')}</TableCell>
                                                <TableCell align="center" />
                                            </TableRow>
                                        </TableHead>
                                        <TableBody>
                                            {policies.map((policy) => (
                                                <TableRow key={policy.group_id} data-testid={`policy-row-${policy.group_id}`}>
                                                    <TableCell>{policy.group_name}</TableCell>
                                                    <TableCell align="center">
                                                        <Checkbox
                                                            size="small"
                                                            checked={!!policy.view_access}
                                                            onChange={(e) => upsertPolicy({ id: policy.group_id, name: policy.group_name }, { view_access: e.target.checked })}
                                                        />
                                                    </TableCell>
                                                    <TableCell align="center">
                                                        <Checkbox
                                                            size="small"
                                                            checked={!!policy.edit_access}
                                                            onChange={(e) => upsertPolicy({ id: policy.group_id, name: policy.group_name }, { edit_access: e.target.checked })}
                                                        />
                                                    </TableCell>
                                                    <TableCell align="center">
                                                        <Checkbox
                                                            size="small"
                                                            checked={!!policy.admin_access}
                                                            onChange={(e) => upsertPolicy({ id: policy.group_id, name: policy.group_name }, { admin_access: e.target.checked })}
                                                        />
                                                    </TableCell>
                                                    <TableCell align="center">
                                                        <Checkbox
                                                            size="small"
                                                            checked={!!policy.explicit_deny}
                                                            onChange={(e) => upsertPolicy({ id: policy.group_id, name: policy.group_name }, { explicit_deny: e.target.checked })}
                                                        />
                                                    </TableCell>
                                                    <TableCell align="center">
                                                        <Tooltip title={t('collectionProperties.accessPolicies.remove', 'Remove policy')}>
                                                            <IconButton size="small" onClick={() => removePolicy(policy.group_id)}>
                                                                <DeleteOutlineOutlined fontSize="small" />
                                                            </IconButton>
                                                        </Tooltip>
                                                    </TableCell>
                                                </TableRow>
                                            ))}
                                        </TableBody>
                                    </Table>
                                )}
                            </Box>
                        )}
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
