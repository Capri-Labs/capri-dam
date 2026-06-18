import React, { useState, useEffect } from 'react';
import {
    Box, Typography, CircularProgress, List, ListItem,
    Avatar, Chip, Divider, Button
} from '@mui/material';
import { Restore, FolderZip } from '@mui/icons-material';
import { useNotify } from '../../context/NotificationContext';

//  Removed isVisible from props
export default function AssetVersionsTab({ asset, onAssetUpdated }) {
    const notify = useNotify();
    const [versions, setVersions] = useState([]);
    const [isLoadingVersions, setIsLoadingVersions] = useState(false);

    //  Fetch versions automatically when the component mounts
    useEffect(() => {
        if (asset) {
            fetchVersions();
        }
    }, [asset]);

    const fetchVersions = async () => {
        setIsLoadingVersions(true);
        try {
            const res = await fetch(`/api/v1/assets/${asset.id}/versions`);
            if (res.ok) {
                const data = await res.json();
                setVersions(data.versions);
            } else {
                throw new Error('Failed to fetch');
            }
        } catch (error) {
            notify("Failed to load version history.", "error");
        } finally {
            setIsLoadingVersions(false);
        }
    };

    const handleRestoreVersion = async (versionId) => {
        const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
        try {
            const res = await fetch(`/api/v1/assets/${asset.id}/versions/${versionId}/restore`, {
                method: 'POST',
                headers: { 'X-CSRF-Token': csrfToken }
            });

            if (res.ok) {
                notify("Asset successfully rolled back to selected version.", "success");
                fetchVersions();
                if (onAssetUpdated) onAssetUpdated();
            } else {
                throw new Error('Restore failed');
            }
        } catch (error) {
            notify("Failed to restore version.", "error");
        }
    };

    //  Removed the early return for isVisible

    return (
        <Box sx={{ p: 4 }}>
            <Typography variant="h6" sx={{ fontWeight: 700, mb: 1 }}>Version Timeline</Typography>
            <Typography variant="body2" color="textSecondary" sx={{ mb: 4 }}>
                View previous iterations of this asset. Restoring a version makes it the active file without deleting newer edits.
            </Typography>

            {isLoadingVersions ? (
                <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
                    <CircularProgress />
                </Box>
            ) : (
                <List sx={{ bgcolor: '#fff', border: '1px solid #e2e8f0', borderRadius: 2, p: 0 }}>
                    {versions.map((version, index) => (
                        <React.Fragment key={version.id}>
                            <ListItem sx={{ p: 3, display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>

                                <Box sx={{ display: 'flex', gap: 2 }}>
                                    <Avatar sx={{ bgcolor: version.is_active ? '#4f46e5' : '#f1f5f9', color: version.is_active ? '#fff' : '#64748b', fontWeight: 700, width: 48, height: 48 }}>
                                        v{version.version_number}
                                    </Avatar>

                                    <Box>
                                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 0.5 }}>
                                            <Typography variant="subtitle1" sx={{ fontWeight: 700, color: '#1e293b' }}>
                                                {version.action_type}
                                            </Typography>
                                            {version.is_active && (
                                                <Chip label="Current Active" size="small" sx={{ bgcolor: '#eef2ff', color: '#4f46e5', fontWeight: 700, height: 20 }} />
                                            )}
                                        </Box>

                                        <Typography variant="body2" color="textSecondary" sx={{ mb: 0.5 }}>
                                            Saved on {version.created_at} by <strong>{version.created_by}</strong>
                                        </Typography>

                                        <Typography variant="caption" sx={{ color: '#64748b', display: 'flex', alignItems: 'center', gap: 0.5 }}>
                                            <FolderZip fontSize="small" sx={{ fontSize: 14 }} /> File Size: {version.size}
                                        </Typography>
                                    </Box>
                                </Box>

                                {!version.is_active && (
                                    <Button
                                        variant="outlined"
                                        startIcon={<Restore />}
                                        onClick={() => handleRestoreVersion(version.id)}
                                        sx={{ color: '#4f46e5', borderColor: '#c7d2fe', '&:hover': { bgcolor: '#eef2ff' }, textTransform: 'none' }}
                                    >
                                        Restore
                                    </Button>
                                )}
                            </ListItem>

                            {index < versions.length - 1 && <Divider component="li" />}
                        </React.Fragment>
                    ))}
                </List>
            )}
        </Box>
    );
}