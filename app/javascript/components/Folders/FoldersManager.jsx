import React from 'react';
import { Box, CssBaseline } from '@mui/material';
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
                {/* The "All Assets" page title now renders inline with the
                    breadcrumb inside ExplorerTopBar (see `pageTitle` prop)
                    instead of its own heading row above the Explorer, so the
                    two no longer stack as separate lines. */}
                <AssetExplorer {...props} pageTitle={t('foldersManager.title')} />
            </Box>
        </Box>
    );
}
