import React, { useState, useEffect } from 'react';
import { Box, Grid, CircularProgress, Stack, Button, Typography } from '@mui/material';
import { useNotify } from '../../../context/NotificationContext';
import ConnectorsTopBar from './ConnectorsTopBar';
import ConnectorCard from './ConnectorCard';
import ConnectorDialog, { DAM_PROVIDERS } from './ConnectorDialog';

const DEFAULT_PAGINATION = { page: 1, per_page: 12, total: 0, total_pages: 1 };

export default function SystemConnectors() {
    const notify = useNotify();
    const [connectors, setConnectors] = useState([]);
    const [loading, setLoading] = useState(true);
    const [pagination, setPagination] = useState(DEFAULT_PAGINATION);

    const [openDialog, setOpenDialog] = useState(false);
    const [isSaving, setIsSaving] = useState(false);
    const [isTesting, setIsTesting] = useState(false);
    const [testResult, setTestResult] = useState(null);
    const [isRefreshingToken, setIsRefreshingToken] = useState(false);

    const initialFormState = { id: null, provider_type: 'AEM', name: '', endpoint: '', auth_token: '', credential_type: 'token', default_source_path: '', tdm_sanitation: true, status: 'idle' };
    const [formData, setFormData] = useState(initialFormState);

    useEffect(() => { fetchConnectors(1); }, []);

    const fetchConnectors = async (page = pagination.page) => {
        setLoading(true);
        try {
            const res = await fetch(`/api/v1/system_connectors?page=${page}`);
            const data = await res.json();
            setConnectors(data.connectors || []);
            setPagination(data.pagination || DEFAULT_PAGINATION);
        } catch (error) {
            notify("Failed to load connectors.", "error");
        } finally {
            setLoading(false);
        }
    };

    const handleCloseDialog = () => {
        setOpenDialog(false);
        setFormData(initialFormState);
        setTestResult(null);
    };

    const handleOpenEdit = (connector) => {
        setFormData({ ...connector, auth_token: '', integration_json: '' });
        setTestResult(null);
        setOpenDialog(true);
    };

    const handleRefreshToken = async () => {
        if (!formData.id) return;
        setIsRefreshingToken(true);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/system_connectors/${formData.id}/refresh_token`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken }
            });
            const data = await res.json();
            if (res.ok) {
                setFormData(prev => ({ ...prev, token_status: data.token_status, access_token_expires_at: data.access_token_expires_at }));
                notify('Access token refreshed.', 'success');
            } else {
                notify(data.error || 'Failed to refresh token.', 'error');
            }
        } catch {
            notify('Network error.', 'error');
        } finally {
            setIsRefreshingToken(false);
        }
    };

    const handleRevokeToken = async () => {
        if (!formData.id) return;
        if (!window.confirm('Revoke the cached access token? Note: full revocation requires rotating the client secret in the Adobe Developer Console.')) return;
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/system_connectors/${formData.id}/revoke_token`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken }
            });
            const data = await res.json();
            if (res.ok) {
                setFormData(prev => ({ ...prev, token_status: data.token_status, access_token_expires_at: null }));
                notify('Token revoked locally.', 'info');
            }
        } catch {
            notify('Network error.', 'error');
        }
    };

    const handleToggleStatus = async (connector) => {
        const newStatus = connector.status === 'active' ? 'disabled' : 'active';
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/system_connectors/${connector.id}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ system_connector: { status: newStatus } })
            });
            if (res.ok) {
                notify(`Connector ${newStatus === 'active' ? 'resumed' : 'paused'}.`, "info");
                fetchConnectors();
            }
        } catch (error) {
            notify("Failed to toggle connector status.", "error");
        }
    };

    const handleTestConnection = async () => {
        setIsTesting(true);
        setTestResult(null);
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch('/api/v1/system_connectors/test_connection', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(formData)
            });
            const data = await res.json();
            setTestResult({ type: data.success ? 'success' : 'error', message: data.message });
        } catch (error) {
            setTestResult({ type: 'error', message: "Failed to reach server." });
        } finally {
            setIsTesting(false);
        }
    };

    const handleSaveConnector = async () => {
        setIsSaving(true);
        const isEditing = !!formData.id;
        const url = isEditing ? `/api/v1/system_connectors/${formData.id}` : '/api/v1/system_connectors';
        const method = isEditing ? 'PUT' : 'POST';

        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(url, {
                method: method,
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ system_connector: formData })
            });

            if (res.ok) {
                notify(isEditing ? "Connector updated." : "Connector established.", "success");
                fetchConnectors();
                handleCloseDialog();
            } else {
                notify("Failed to save connector.", "error");
            }
        } catch (error) {
            notify("Network error occurred.", "error");
        } finally {
            setIsSaving(false);
        }
    };

    const handleStartMigration = async (connector) => {
        const sourcePath = window.prompt(
            'Which DAM folder should this migration import? Leave blank to use the connector default / whole root.',
            connector.default_source_path || ''
        );
        if (sourcePath === null) return; // cancelled

        if (!window.confirm(`Start migration from ${connector.name}${sourcePath ? ` (folder: ${sourcePath})` : ''}? This will pull assets from the source system.`)) return;
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/system_connectors/${connector.id}/start_migration`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ source_path: sourcePath || undefined })
            });
            const data = await res.json();
            if (res.ok) {
                notify(`Migration started: ${data.batch?.name}. Track progress in the Pipeline tab.`, 'success');
            } else {
                notify(data.error || 'Failed to start migration.', 'error');
            }
        } catch {
            notify('Network error.', 'error');
        }
    };

    // Required fields are driven by the selected provider's own field definitions
    // (e.g. Cloudinary/FTP have no `endpoint` field at all), not a fixed endpoint+auth_token pair.
    const providerDef = DAM_PROVIDERS[formData.provider_type?.toLowerCase()];
    const isJwt = providerDef?.supportsJwt && (formData.credential_type || 'token') === 'jwt_service_account';
    const isFormValid = Boolean(formData.name) && Boolean(providerDef) && (
        isJwt
            ? Boolean(formData.endpoint) && Boolean(formData.id || formData.integration_json)
            : providerDef.fields.every(field => !field.required || Boolean(formData[field.key]) || (field.type === 'password' && formData.id))
    );

    return (
        <Box sx={{ p: 4, bgcolor: '#f8fafc', minHeight: '100vh' }}>
            <ConnectorsTopBar
                onAddClick={() => setOpenDialog(true)}
                onRefresh={() => fetchConnectors(pagination.page)}
            />

            {loading ? (
                <CircularProgress sx={{ display: 'block', mx: 'auto', mt: 10 }} />
            ) : (
                <>
                <Grid container spacing={4}>
                    {connectors.map((conn) => (
                        <Grid size={{ xs: 12, md: 6, lg: 4 }} key={conn.id}>
                            <ConnectorCard
                                conn={conn}
                                onEdit={handleOpenEdit}
                                onToggleStatus={handleToggleStatus}
                                onStartMigration={handleStartMigration}
                            />
                        </Grid>
                    ))}
                </Grid>

                {pagination.total_pages > 1 && (
                    <Stack direction="row" spacing={1} sx={{ mt: 3, justifyContent: 'center' }}>
                        <Button
                            size="small"
                            disabled={pagination.page <= 1}
                            onClick={() => fetchConnectors(pagination.page - 1)}
                        >
                            ← Prev
                        </Button>
                        <Typography variant="caption" sx={{ alignSelf: 'center', px: 1 }}>
                            Page {pagination.page} of {pagination.total_pages}
                        </Typography>
                        <Button
                            size="small"
                            disabled={pagination.page >= pagination.total_pages}
                            onClick={() => fetchConnectors(pagination.page + 1)}
                        >
                            Next →
                        </Button>
                    </Stack>
                )}
                </>
            )}

            <ConnectorDialog
                open={openDialog}
                onClose={handleCloseDialog}
                formData={formData}
                setFormData={setFormData}
                onSave={handleSaveConnector}
                onTest={handleTestConnection}
                isSaving={isSaving}
                isTesting={isTesting}
                testResult={testResult}
                isFormValid={isFormValid}
                onRefreshToken={handleRefreshToken}
                onRevokeToken={handleRevokeToken}
                isRefreshingToken={isRefreshingToken}
            />
        </Box>
    );
}