import React from 'react';
import { Box, CssBaseline, Typography } from '@mui/material';
import Sidebar from '../Sidebar';
import AssetExplorer from '../AssetExplorer';
import { navigateTo } from "../../utils/globalutils";

export default function FoldersManager(props) {
    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            <Sidebar activeView="Collections" onNavigate={(v) => navigateTo(v)} />

            <Box component="main" sx={{ flexGrow: 1 }}>
                <Box sx={{ px: 3, pt: 3, pb: 1 }}>
                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>
                        All Assets
                    </Typography>
                </Box>
                {/* Mount your existing AssetExplorer here */}
                <AssetExplorer {...props} />
            </Box>
        </Box>
    );
}