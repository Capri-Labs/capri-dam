import React from 'react';
import {
    Table, TableHead, TableRow, TableCell, TableBody, TableContainer,
    Checkbox, IconButton, Tooltip, Typography, Box, Chip, Paper,
    TableSortLabel, Skeleton
} from '@mui/material';
import {
    FolderOutlined, InsertDriveFile, PictureAsPdf, VideoFile, AudioFile,
    ImageOutlined, RestoreFromTrashOutlined, DeleteForeverOutlined, TimerOffOutlined
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const getIcon = (mediaType) => {
    if (mediaType === 'folder')   return <FolderOutlined sx={{ color: '#f59e0b', fontSize: 20 }} />;
    if (mediaType === 'image')    return <ImageOutlined sx={{ color: '#10b981', fontSize: 20 }} />;
    if (mediaType === 'video')    return <VideoFile sx={{ color: '#3b82f6', fontSize: 20 }} />;
    if (mediaType === 'audio')    return <AudioFile sx={{ color: '#8b5cf6', fontSize: 20 }} />;
    if (mediaType === 'document') return <PictureAsPdf sx={{ color: '#ef4444', fontSize: 20 }} />;
    return <InsertDriveFile sx={{ color: '#64748b', fontSize: 20 }} />;
};

const SortableHeader = ({ fieldKey, label, sort, onSortChange }) => {
    const active = sort?.field === fieldKey;
    return (
        <TableCell sx={{ fontWeight: 700, color: '#475569', bgcolor: '#f8fafc' }}>
            <TableSortLabel
                active={active}
                direction={active ? sort.direction : 'asc'}
                onClick={() => onSortChange({
                    field: fieldKey,
                    direction: active && sort.direction === 'asc' ? 'desc' : 'asc',
                })}
            >
                {label}
            </TableSortLabel>
        </TableCell>
    );
};

export default function BinList({ items, isSelected, onToggleSelect, onRestore, onDelete, loading, sort, onSortChange }) {
    const { t } = useTranslation();

    if (loading && items.length === 0) {
        return (
            <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', borderRadius: 2 }}>
                <Table size="small">
                    <TableBody>
                        {[...Array(8)].map((_, i) => (
                            <TableRow key={i}><TableCell colSpan={6}><Skeleton height={40} /></TableCell></TableRow>
                        ))}
                    </TableBody>
                </Table>
            </TableContainer>
        );
    }

    return (
        <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0', borderRadius: 2 }}>
            <Table size="small">
                <TableHead>
                    <TableRow>
                        <TableCell padding="checkbox" sx={{ bgcolor: '#f8fafc' }} />
                        <TableCell sx={{ fontWeight: 700, color: '#475569', bgcolor: '#f8fafc', width: 48 }}>
                            {t('bin.item.type')}
                        </TableCell>
                        <SortableHeader fieldKey="name"       label={t('bin.item.name')}       sort={sort} onSortChange={onSortChange} />
                        <TableCell sx={{ fontWeight: 700, color: '#475569', bgcolor: '#f8fafc' }}>{t('bin.item.originalPath')}</TableCell>
                        <SortableHeader fieldKey="size"       label={t('bin.item.size')}       sort={sort} onSortChange={onSortChange} />
                        <SortableHeader fieldKey="deleted_at" label={t('bin.item.deletedAt')} sort={sort} onSortChange={onSortChange} />
                        <TableCell sx={{ fontWeight: 700, color: '#475569', bgcolor: '#f8fafc' }}>{t('bin.item.expires')}</TableCell>
                        <TableCell align="right" sx={{ fontWeight: 700, color: '#475569', bgcolor: '#f8fafc' }}>{t('bin.item.actions')}</TableCell>
                    </TableRow>
                </TableHead>
                <TableBody>
                    {items.map((item) => {
                        const sel      = isSelected(item.grid_id);
                        const daysLeft = item.expires_at
                            ? Math.max(0, Math.ceil((new Date(item.expires_at) - Date.now()) / 86400000))
                            : null;

                        return (
                            <TableRow
                                key={item.grid_id} hover selected={sel}
                                sx={{ '&.Mui-selected': { bgcolor: '#eef2ff' }, cursor: 'default' }}
                            >
                                <TableCell padding="checkbox">
                                    <Checkbox size="small" checked={sel}
                                        onChange={() => onToggleSelect(item.grid_id)} />
                                </TableCell>
                                <TableCell>
                                    {getIcon(item.media_type)}
                                </TableCell>
                                <TableCell>
                                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                                        <Typography variant="body2" sx={{ fontWeight: 500, color: '#1e293b' }}>
                                            {item.name}
                                        </Typography>
                                    </Box>
                                </TableCell>
                                <TableCell>
                                    <Typography variant="body2" sx={{ color: '#64748b' }}>
                                        {item.original_path || '—'}
                                    </Typography>
                                </TableCell>
                                <TableCell>
                                    <Typography variant="body2" sx={{ color: '#64748b' }}>
                                        {item.size_human || '—'}
                                    </Typography>
                                </TableCell>
                                <TableCell>
                                    <Typography variant="body2" sx={{ color: '#64748b' }}>
                                        {item.deleted_at ? new Date(item.deleted_at).toLocaleString() : '—'}
                                    </Typography>
                                </TableCell>
                                <TableCell>
                                    {daysLeft !== null ? (
                                        <Chip
                                            icon={<TimerOffOutlined />}
                                            label={daysLeft <= 0 ? t('bin.retention.expired') : t('bin.retention.expires', { days: daysLeft })}
                                            size="small"
                                            color={daysLeft <= 0 ? 'error' : daysLeft <= 7 ? 'warning' : 'default'}
                                            variant="outlined"
                                            sx={{ fontWeight: 600, fontSize: '0.7rem' }}
                                        />
                                    ) : '—'}
                                </TableCell>
                                <TableCell align="right">
                                    <Box sx={{ display: 'flex', gap: 0.5, justifyContent: 'flex-end' }}>
                                        <Tooltip title={t('bin.item.restore')}>
                                            <IconButton size="small" color="success" onClick={() => onRestore(item)}>
                                                <RestoreFromTrashOutlined fontSize="small" />
                                            </IconButton>
                                        </Tooltip>
                                        <Tooltip title={t('bin.item.deletePermanently')}>
                                            <IconButton size="small" color="error" onClick={() => onDelete(item)}>
                                                <DeleteForeverOutlined fontSize="small" />
                                            </IconButton>
                                        </Tooltip>
                                    </Box>
                                </TableCell>
                            </TableRow>
                        );
                    })}
                </TableBody>
            </Table>
        </TableContainer>
    );
}
