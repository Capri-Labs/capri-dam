import React from 'react';
import { Box, CssBaseline, Typography } from '@mui/material';
import { useTranslation } from 'react-i18next';
import Sidebar from '../Sidebar';
import AssetExplorer from './AssetExplorer';
import { navigateTo } from "../../utils/globalutils";

export default function FoldersManager(props) {
    const { t } = useTranslation();

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />

            <Box component="main" sx={{ flexGrow: 1 }}>
                <Box sx={{ px: 3, pt: 3, pb: 1 }}>
                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                        {t('foldersManager.title')}
                    </Typography>
                </Box>
                {/* Mount your existing AssetExplorer here */}
                <AssetExplorer {...props} />
            </Box>
        </Box>
    );
}