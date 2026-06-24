import React, { useState } from 'react';
import { Box, Typography, Chip } from '@mui/material';
import { SettingsOutlined, SecurityOutlined, BlockOutlined, ImageOutlined } from '@mui/icons-material';
import UploadRestrictionsPanel from './UploadRestrictions';
import ImageProfilesManager from './ImageProfiles';

const NAV_ITEMS = [
    {
        id: 'upload_restrictions',
        label: 'Upload Restrictions',
        icon: <BlockOutlined sx={{ fontSize: 18 }} />,
        description: 'Control which MIME types can be uploaded',
    },
    {
        id: 'image_profiles',
        label: 'Image Profiles',
        icon: <ImageOutlined sx={{ fontSize: 18 }} />,
        description: 'Automatic crop & sharpening on upload',
    },
];

export default function AssetConfigurationsManager() {
    const [activeSection, setActiveSection] = useState('upload_restrictions');


    return (
        <Box sx={{ display: 'flex', height: '100%', bgcolor: '#f8fafc' }}>
            {/* Left navigation panel */}
            <Box sx={{ width: '22%', flexShrink: 0, bgcolor: '#fff', borderRight: '1px solid #e2e8f0',
                       display: 'flex', flexDirection: 'column' }}>
                <Box sx={{ p: 2, borderBottom: '1px solid #f1f5f9' }}>
                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>
                        Asset Configurations
                    </Typography>
                    <Typography variant="caption" sx={{ color: '#94a3b8' }}>Tools › Assets</Typography>
                </Box>

                <Box sx={{ py: 1 }}>
                    {NAV_ITEMS.map(item => (
                        <Box
                            key={item.id}
                            onClick={() => setActiveSection(item.id)}
                            sx={{
                                display: 'flex', alignItems: 'center', gap: 1.5,
                                px: 2, py: 1.5, mx: 0.5, borderRadius: '8px', cursor: 'pointer',
                                bgcolor: activeSection === item.id ? '#ede7f6' : 'transparent',
                                color: activeSection === item.id ? '#5e35b1' : '#475569',
                                '&:hover': { bgcolor: activeSection === item.id ? '#ede7f6' : '#f5f3ff' },
                            }}
                        >
                            {item.icon}
                            <Box>
                                <Typography variant="body2"
                                            fontWeight={activeSection === item.id ? 600 : 400}
                                            sx={{ lineHeight: 1.3 }}>
                                    {item.label}
                                </Typography>
                                <Typography variant="caption" sx={{ color: '#94a3b8', fontSize: '0.68rem' }}>
                                    {item.description}
                                </Typography>
                            </Box>
                        </Box>
                    ))}
                </Box>
            </Box>

            {/* Right content panel */}
            <Box sx={{ flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
                {/* Top bar — only shown for upload_restrictions; image_profiles has its own */}
                {activeSection === 'upload_restrictions' && (
                    <Box sx={{ px: 3, py: 2, bgcolor: '#fff', borderBottom: '1px solid #e2e8f0',
                               display: 'flex', alignItems: 'center', gap: 2 }}>
                        <SettingsOutlined sx={{ color: '#5e35b1', fontSize: 22 }} />
                        <Box sx={{ flex: 1 }}>
                            <Typography variant="h6" fontWeight={700} sx={{ color: '#1e293b', lineHeight: 1.2 }}>
                                Upload Restrictions
                            </Typography>
                            <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                Tools › Assets › Asset Configurations › Upload Restrictions
                            </Typography>
                        </Box>
                        <Chip icon={<SecurityOutlined sx={{ fontSize: '14px !important' }} />}
                              label="Admin only" size="small"
                              sx={{ bgcolor: '#fef3c7', color: '#92400e', fontSize: '0.7rem', border: '1px solid #fde68a' }} />
                    </Box>
                )}

                <Box sx={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
                    {activeSection === 'upload_restrictions' && <UploadRestrictionsPanel />}
                    {activeSection === 'image_profiles'      && <ImageProfilesManager />}
                </Box>
            </Box>
        </Box>
    );
}
