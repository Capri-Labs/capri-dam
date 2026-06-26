import React from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogContentText,
    DialogActions, Button
} from '@mui/material';
import { WarningAmberOutlined, DeleteForeverOutlined, RestoreFromTrashOutlined } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const VARIANTS = {
    restore: {
        icon:     <RestoreFromTrashOutlined sx={{ color: '#10b981', fontSize: 28 }} />,
        titleKey: 'bin.confirm.restore',
        bodyKey:  'bin.confirm.restoreBody',
        confirmColor: 'success',
    },
    delete: {
        icon:     <DeleteForeverOutlined sx={{ color: '#ef4444', fontSize: 28 }} />,
        titleKey: 'bin.confirm.delete',
        bodyKey:  'bin.confirm.deleteBody',
        confirmColor: 'error',
    },
    emptyBin: {
        icon:     <WarningAmberOutlined sx={{ color: '#ef4444', fontSize: 28 }} />,
        titleKey: 'bin.confirm.emptyBin',
        bodyKey:  'bin.confirm.emptyBinBody',
        confirmColor: 'error',
    },
};

export default function BinConfirmDialog({ open, variant, count, onConfirm, onClose }) {
    const { t } = useTranslation();
    const cfg   = VARIANTS[variant] || VARIANTS.delete;

    return (
        <Dialog open={open} onClose={onClose} maxWidth="xs" fullWidth>
            <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1.5, pb: 1 }}>
                {cfg.icon}
                {t(cfg.titleKey, { count })}
            </DialogTitle>
            <DialogContent>
                <DialogContentText>
                    {t(cfg.bodyKey, { count })}
                </DialogContentText>
            </DialogContent>
            <DialogActions sx={{ px: 3, pb: 2 }}>
                <Button onClick={onClose} color="inherit" sx={{ textTransform: 'none' }}>
                    {t('bin.confirm.cancel')}
                </Button>
                <Button
                    onClick={onConfirm}
                    color={cfg.confirmColor}
                    variant="contained"
                    disableElevation
                    sx={{ textTransform: 'none', fontWeight: 600 }}
                >
                    {t('bin.confirm.confirm')}
                </Button>
            </DialogActions>
        </Dialog>
    );
}

