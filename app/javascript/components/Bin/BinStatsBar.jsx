import React from 'react';
import { Box, Typography, Skeleton } from '@mui/material';
import {
    DeleteForeverOutlined, FolderOutlined, InsertDriveFileOutlined, StorageOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const StatCard = ({ icon, label, value, color, loading }) => (
    <Box sx={{
        flex: '1 1 180px', display: 'flex', alignItems: 'center', gap: 1.5,
        bgcolor: '#fff', border: '1px solid #e2e8f0', borderRadius: 2,
        px: 2.5, py: 1.5, minWidth: 140
    }}>
        <Box sx={{ p: 1, bgcolor: `${color}18`, borderRadius: 1.5, display: 'flex' }}>
            {React.cloneElement(icon, { sx: { color, fontSize: 20 } })}
        </Box>
        <Box>
            {loading ? (
                <Skeleton width={48} height={24} />
            ) : (
                <Typography variant="h6" sx={{ fontWeight: 800, color: '#1e293b', lineHeight: 1.2 }}>
                    {value ?? '—'}
                </Typography>
            )}
            <Typography variant="caption" sx={{ color: '#64748b', fontWeight: 500 }}>
                {label}
            </Typography>
        </Box>
    </Box>
);

const formatBytes = (bytes) => {
    if (!bytes || bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const exp   = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    return `${(bytes / 1024 ** exp).toFixed(1)} ${units[exp]}`;
};

export default function BinStatsBar({ stats, loading }) {
    const { t } = useTranslation();

    return (
        <Box sx={{
            display: 'flex', gap: 2, flexWrap: 'wrap',
            px: 4, py: 2, bgcolor: '#f8fafc',
            borderBottom: '1px solid #e2e8f0'
        }}>
            <StatCard
                icon={<DeleteForeverOutlined />}
                label={t('bin.stats.totalItems')}
                value={stats?.total_items}
                color="#ef4444"
                loading={loading}
            />
            <StatCard
                icon={<InsertDriveFileOutlined />}
                label={t('bin.stats.assets')}
                value={stats?.total_assets}
                color="#6366f1"
                loading={loading}
            />
            <StatCard
                icon={<FolderOutlined />}
                label={t('bin.stats.folders')}
                value={stats?.total_folders}
                color="#f59e0b"
                loading={loading}
            />
            <StatCard
                icon={<StorageOutlined />}
                label={t('bin.stats.storageUsed')}
                value={stats ? formatBytes(stats.total_size_bytes) : null}
                color="#10b981"
                loading={loading}
            />
        </Box>
    );
}

