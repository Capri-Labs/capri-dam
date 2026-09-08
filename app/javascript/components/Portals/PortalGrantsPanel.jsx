import React, { useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Box, Typography, Table, TableHead, TableRow, TableCell, TableBody,
    Select, MenuItem, Chip, Stack, Button, Tooltip, Alert,
} from '@mui/material';
import { WarningAmberOutlined } from '@mui/icons-material';

const PERMISSIONS = ['none', 'view', 'download'];

/**
 * The per-asset pick list.
 *
 * Shows every asset in the portal's target, not only the granted ones —
 * "nothing here" and "everything withheld" look identical otherwise, and the
 * grant set is declarative, so the absent entries are the withheld ones.
 *
 * Assets that rights will not let out are marked as such *while configuring*.
 * A download grant on an internal-only asset is recorded and then quietly
 * ignored at delivery, so the only useful place to say so is here.
 */
export default function PortalGrantsPanel({ assets, value, onChange, disabled }) {
    const { t } = useTranslation();

    const stats = useMemo(() => {
        const entries = Object.entries(value || {}).filter(([, p]) => p && p !== 'none');
        const blocked = entries.filter(([id]) => {
            const asset = (assets || []).find((a) => String(a.id) === String(id));
            return asset && !asset.externally_distributable;
        });
        return { granted: entries.length, blocked: blocked.length };
    }, [value, assets]);

    const setAll = (permission) => {
        const next = {};
        (assets || []).forEach((asset) => { next[String(asset.id)] = permission; });
        onChange(next);
    };

    const setOne = (assetId, permission) => {
        onChange({ ...(value || {}), [String(assetId)]: permission });
    };

    if (!assets || assets.length === 0) {
        return (
            <Typography variant="body2" color="text.secondary" sx={{ py: 2 }}>
                {t('portalManager.grants.none')}
            </Typography>
        );
    }

    return (
        <Box>
            <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
                <Typography variant="subtitle2" sx={{ flexGrow: 1 }}>
                    {t('portalManager.grants.summary', { granted: stats.granted, total: assets.length })}
                </Typography>
                <Button size="small" onClick={() => setAll('view')} disabled={disabled}>
                    {t('portalManager.grants.selectAll')}
                </Button>
                <Button size="small" onClick={() => setAll('none')} disabled={disabled}>
                    {t('portalManager.grants.clearAll')}
                </Button>
            </Stack>

            <Typography variant="caption" color="text.secondary" display="block" sx={{ mb: 1 }}>
                {t('portalManager.grants.help')}
            </Typography>

            {stats.blocked > 0 && (
                <Alert severity="info" sx={{ mb: 1 }}>
                    {t('portalManager.grants.blockedNotice', { count: stats.blocked })}
                </Alert>
            )}

            <Table size="small">
                <TableHead>
                    <TableRow>
                        <TableCell>{t('portalManager.grants.asset')}</TableCell>
                        <TableCell>{t('portalManager.grants.rights')}</TableCell>
                        <TableCell width={200}>{t('portalManager.grants.permission')}</TableCell>
                    </TableRow>
                </TableHead>
                <TableBody>
                    {assets.map((asset) => {
                        const permission = (value || {})[String(asset.id)] || 'none';
                        return (
                            <TableRow key={asset.id}>
                                <TableCell>{asset.title || asset.id}</TableCell>
                                <TableCell>
                                    {asset.externally_distributable ? (
                                        <Chip size="small" label={t('portalManager.grants.distributable')} color="success" variant="outlined" />
                                    ) : (
                                        <Tooltip title={t('portalManager.grants.notDistributableHelp')}>
                                            <Chip
                                                size="small"
                                                icon={<WarningAmberOutlined sx={{ fontSize: 14 }} />}
                                                label={t('portalManager.grants.notDistributable')}
                                                color="warning"
                                                variant="outlined"
                                            />
                                        </Tooltip>
                                    )}
                                </TableCell>
                                <TableCell>
                                    <Select
                                        size="small"
                                        fullWidth
                                        value={permission}
                                        disabled={disabled}
                                        onChange={(e) => setOne(asset.id, e.target.value)}
                                        inputProps={{ 'aria-label': t('portalManager.grants.permissionFor', { name: asset.title || asset.id }) }}
                                    >
                                        {PERMISSIONS.map((p) => (
                                            <MenuItem key={p} value={p}>{t(`portalManager.grants.option.${p}`)}</MenuItem>
                                        ))}
                                    </Select>
                                </TableCell>
                            </TableRow>
                        );
                    })}
                </TableBody>
            </Table>
        </Box>
    );
}
