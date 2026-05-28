import React, { useState, useEffect } from 'react';
import { Card, CardContent, Typography, Button, Box, Chip, IconButton, Tooltip } from '@mui/material';
import { DataGrid } from '@mui/x-data-grid';
import {Download, Autorenew, ErrorOutlined} from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

export default function ReportExportTable({ refreshTrigger }) {
    const notify = useNotify();
    const [snapshots, setSnapshots] = useState([]);
    const [loading, setLoading] = useState(true);

    const fetchSnapshots = () => {
        setLoading(true);
        fetch('/admin/report_snapshots.json')
            .then(res => res.json())
            .then(data => {
                setSnapshots(data.snapshots || []);
                setLoading(false);
            })
            .catch(() => {
                notify("Failed to load export history.", "error");
                setLoading(false);
            });
    };

    // Re-fetch whenever the component mounts, or when the Drawer creates a new export
    useEffect(() => {
        fetchSnapshots();
    }, [refreshTrigger]);

    // Status formatting helper
    const getStatusChip = (status, errorMessage) => {
        const config = {
            completed: { color: 'success', label: 'Ready' },
            pending: { color: 'default', label: 'Queued' },
            processing: { color: 'info', label: 'Generating...' },
            failed: { color: 'error', label: 'Failed' }
        };

        const current = config[status] || config.pending;

        if (status === 'failed') {
            return (
                <Tooltip title={errorMessage || "Unknown error occurred"}>
                    <Chip size="small" color={current.color} label={current.label} icon={<ErrorOutlined />} />
                </Tooltip>
            );
        }

        return <Chip size="small" color={current.color} label={current.label} />;
    };

    const columns = [
        { field: 'created_at', headerName: 'Date Requested', width: 180 },
        { field: 'report_name', headerName: 'Report Name', flex: 1, minWidth: 200 },
        {
            field: 'format', headerName: 'Format', width: 100,
            renderCell: (p) => <Typography variant="body2" fontWeight="600">{p.value}</Typography>
        },
        {
            field: 'status', headerName: 'Status', width: 130,
            renderCell: (p) => getStatusChip(p.value, p.row.error_message)
        },
        {
            field: 'actions', headerName: 'Download', width: 150, sortable: false, align: 'center',
            renderCell: (params) => {
                if (params.row.status === 'completed' && params.row.download_url) {
                    return (
                        <Button
                            variant="outlined"
                            size="small"
                            startIcon={<Download />}
                            href={params.row.download_url}
                            // Using standard href bypasses React Router so the browser downloads the file
                        >
                            Save
                        </Button>
                    );
                }
                return null;
            }
        }
    ];

    return (
        <Card variant="outlined" sx={{ borderRadius: 2, bgcolor: 'white' }}>
            <CardContent>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                    <Typography variant="h6" sx={{ fontWeight: 600 }}>Download Center (Recent Exports)</Typography>
                    <IconButton size="small" onClick={fetchSnapshots} title="Refresh Table">
                        <Autorenew />
                    </IconButton>
                </Box>

                <Box sx={{ height: 400, width: '100%' }}>
                    <DataGrid
                        rows={snapshots}
                        columns={columns}
                        loading={loading}
                        disableRowSelectionOnClick
                        sx={{ border: 'none' }}
                        initialState={{
                            pagination: { paginationModel: { pageSize: 5 } },
                        }}
                        pageSizeOptions={[5, 10, 25]}
                    />
                </Box>
            </CardContent>
        </Card>
    );
}