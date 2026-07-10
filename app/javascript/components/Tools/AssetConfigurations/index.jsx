import React, { useState } from 'react';
import { Box, Typography, Chip } from '@mui/material';
import { SettingsOutlined, SecurityOutlined, BlockOutlined, ImageOutlined, VideoFileOutlined, ContentCopyOutlined, DeleteForeverOutlined, CollectionsBookmark, CloudUploadOutlined } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import UploadRestrictionsPanel from './UploadRestrictions';
import ImageProfilesManager from './ImageProfiles';
import VideoProfilesManager from './VideoProfiles';
import DuplicateManagerSettings from './DuplicateManagerSettings';
import BinPurgeSettings from './BinPurgeSettings';
import CollectionSettingsPanel from './CollectionSettings';
import UploadLimitsPanel from './UploadLimits';

const NAV_ITEMS = [
    {
        id: 'upload_restrictions',
        labelKey: 'tools.assetConfigurations.uploadRestrictions',
        labelFallback: 'Upload Restrictions',
        icon: <BlockOutlined sx={{ fontSize: 18 }} />,
        descriptionKey: 'tools.assetConfigurations.uploadRestrictionsDesc',
        descriptionFallback: 'Control which MIME types can be uploaded',
    },
    {
        id: 'upload_limits',
        labelKey: 'tools.assetConfigurations.uploadLimits',
        labelFallback: 'Upload Limits',
        icon: <CloudUploadOutlined sx={{ fontSize: 18 }} />,
        descriptionKey: 'tools.assetConfigurations.uploadLimitsDesc',
        descriptionFallback: 'Configure the maximum file size allowed for asset uploads',
        badge: 'New',
    },
    {
        id: 'image_profiles',
        labelKey: 'tools.assetConfigurations.imageProfiles',
        labelFallback: 'Image Profiles',
        icon: <ImageOutlined sx={{ fontSize: 18 }} />,
        descriptionKey: 'tools.assetConfigurations.imageProfilesDesc',
        descriptionFallback: 'Automatic crop & sharpening on upload',
    },
    {
        id: 'video_profiles',
        labelKey: 'tools.assetConfigurations.videoProfiles',
        labelFallback: 'Video Profiles',
        icon: <VideoFileOutlined sx={{ fontSize: 18 }} />,
        descriptionKey: 'tools.assetConfigurations.videoProfilesDesc',
        descriptionFallback: 'Adaptive & progressive video encoding',
    },
    {
        id: 'duplicate_manager',
        labelKey: 'duplicateManager.settings.title',
        labelFallback: 'Duplicate Manager Settings',
        icon: <ContentCopyOutlined sx={{ fontSize: 18 }} />,
        descriptionKey: 'duplicateManager.settings.subtitle',
        descriptionFallback: 'SHA-256 based duplicate detection on upload',
        badge: 'New',
    },
    {
        id: 'bin_purge',
        labelKey: 'bin.settings.title',
        labelFallback: 'Recycle Bin & Purge',
        icon: <DeleteForeverOutlined sx={{ fontSize: 18 }} />,
        descriptionKey: 'bin.settings.subtitle',
        descriptionFallback: 'Auto-purge policy & retention for deleted assets',
        badge: 'New',
    },
    {
        id: 'collection_settings',
        labelKey: 'tools.collectionSettings.title',
        labelFallback: 'Collection Settings',
        icon: <CollectionsBookmark sx={{ fontSize: 18 }} />,
        descriptionKey: 'tools.collectionSettings.subtitle',
        descriptionFallback: 'Smart rules, TTL, CDN & workspace defaults',
        badge: 'New',
    },
];

export default function AssetConfigurationsManager() {
    const { t } = useTranslation();
    const [activeSection, setActiveSection] = useState('upload_restrictions');

    return (
        <Box sx={{ display: 'flex', height: '100%', bgcolor: '#f8fafc' }}>
            {/* Left navigation panel */}
            <Box sx={{ width: '22%', flexShrink: 0, bgcolor: '#fff', borderRight: '1px solid #e2e8f0',
                       display: 'flex', flexDirection: 'column' }}>
                <Box sx={{ p: 2, borderBottom: '1px solid #f1f5f9' }}>
                    <Typography variant="subtitle2" fontWeight={700} sx={{ color: '#1e293b' }}>
                        {t('menu.item.AssetConfigurations', 'Asset Configurations')}
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
                            <Box sx={{ flex: 1 }}>
                                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                    <Typography variant="body2"
                                                fontWeight={activeSection === item.id ? 600 : 400}
                                                sx={{ lineHeight: 1.3 }}>
                                        {t(item.labelKey, item.labelFallback)}
                                    </Typography>
                                    {item.badge && (
                                        <Chip label={item.badge} size="small"
                                              sx={{ height: 16, fontSize: '0.6rem', bgcolor: '#dbeafe', color: '#1d4ed8' }} />
                                    )}
                                </Box>
                                <Typography variant="caption" sx={{ color: '#94a3b8', fontSize: '0.68rem' }}>
                                    {t(item.descriptionKey, item.descriptionFallback)}
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
                                {t('tools.assetConfigurations.uploadRestrictions', 'Upload Restrictions')}
                            </Typography>
                            <Typography variant="caption" sx={{ color: '#94a3b8' }}>
                                Tools › Assets › Asset Configurations › Upload Restrictions
                            </Typography>
                        </Box>
                        <Chip icon={<SecurityOutlined sx={{ fontSize: '14px !important' }} />}
                              label={t('duplicateManager.settings.adminOnly', 'Admin only')} size="small"
                              sx={{ bgcolor: '#fef3c7', color: '#92400e', fontSize: '0.7rem', border: '1px solid #fde68a' }} />
                    </Box>
                )}

                <Box sx={{ flex: 1, overflow: 'auto', display: 'flex', flexDirection: 'column' }}>
                    {activeSection === 'upload_restrictions' && <UploadRestrictionsPanel />}
                    {activeSection === 'upload_limits'       && <UploadLimitsPanel />}
                    {activeSection === 'image_profiles'      && <ImageProfilesManager />}
                    {activeSection === 'video_profiles'      && <VideoProfilesManager />}
                    {activeSection === 'duplicate_manager'   && <DuplicateManagerSettings />}
                    {activeSection === 'bin_purge'           && <BinPurgeSettings />}
                    {activeSection === 'collection_settings' && <CollectionSettingsPanel />}
                </Box>
            </Box>
        </Box>
    );
}
