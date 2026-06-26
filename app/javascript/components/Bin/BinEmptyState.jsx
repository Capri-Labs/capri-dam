import React from 'react';
import { Box, Typography } from '@mui/material';
import { DeleteForeverOutlined } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

export default function BinEmptyState() {
    const { t } = useTranslation();
    return (
        <Box sx={{
            display: 'flex', flexDirection: 'column', alignItems: 'center',
            justifyContent: 'center', py: 12, gap: 2
        }}>
            <Box sx={{ p: 3, bgcolor: '#f1f5f9', borderRadius: '50%', display: 'flex' }}>
                <DeleteForeverOutlined sx={{ fontSize: 64, color: '#cbd5e1' }} />
            </Box>
            <Typography variant="h6" sx={{ fontWeight: 700, color: '#64748b' }}>
                {t('bin.empty')}
            </Typography>
            <Typography variant="body2" sx={{ color: '#94a3b8', textAlign: 'center', maxWidth: 360 }}>
                {t('bin.emptySubtitle')}
            </Typography>
        </Box>
    );
}

