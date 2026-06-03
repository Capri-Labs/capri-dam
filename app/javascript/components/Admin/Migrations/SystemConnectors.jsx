import React, { useState, useEffect } from 'react';
import { Box, Grid, CircularProgress } from '@mui/material';
import { useNotify } from '../../../context/NotificationContext';
import ConnectorsTopBar from './ConnectorsTopBar';
import ConnectorCard from './ConnectorCard';
import ConnectorDialog from './ConnectorDialog';

export default function SystemConnectors() {
    const notify = useNotify();
    const [connectors, setConnectors] = useState([]);
    const [loading, setLoading] = useState(true);

    const [openDialog, setOpenDialog] = useState(false);
    const [isSaving, setIsSaving] = useState(false);
    const [isTesting, setIsTesting] = useState(false);
    const [testResult, setTestResult] = useState(null);

    const initialFormState = { id: null, provider_type: 'AEM', name: '', endpoint: '', auth_token: '', tdm_sanitation: true, status: 'idle' };
    const [formData, setFormData] = useState(initialFormState);

    useEffect(() => { fetchConnectors(); }, []);

    const fetchConnectors = async () => {
        setLoading(true);
        try {
            const res = await fetch('/api/v1/system_connectors');
            const data = await res.json();
            setConnectors(data);
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
        setFormData({ ...connector, auth_token: '' });
        setTestResult(null);
        setOpenDialog(true);
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

    const isFormValid = formData.name && formData.endpoint && (formData.id || formData.auth_token);

    return (
        <Box sx={{ p: 4, bgcolor: '#f8fafc', minHeight: '100vh' }}>
            <ConnectorsTopBar
                onAddClick={() => setOpenDialog(true)}
                onRefresh={fetchConnectors}
            />

            {loading ? (
                <CircularProgress sx={{ display: 'block', mx: 'auto', mt: 10 }} />
            ) : (
                <Grid container spacing={4}>
                    {connectors.map((conn) => (
                        <Grid item xs={12} md={6} lg={4} key={conn.id}>
                            <ConnectorCard
                                conn={conn}
                                onEdit={handleOpenEdit}
                                onToggleStatus={handleToggleStatus}
                            />
                        </Grid>
                    ))}
                </Grid>
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
            />
        </Box>
    );
}