import React, { useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import {
    Box, Typography, Button, Table, TableHead, TableBody, TableRow, TableCell,
    Chip, IconButton, TextField, Alert, CircularProgress, Tooltip, Link,
    Dialog, DialogTitle, DialogContent, DialogContentText, DialogActions,
} from '@mui/material';
import { DeleteOutlined, UploadFileOutlined, OpenInNew } from '@mui/icons-material';
import useAssetRenditions from './useAssetRenditions';

/** Mirrors Rendition::SYSTEM_KINDS — offered as guidance, enforced by the server. */
const RESERVED_KINDS = [ 'thumbnail', 'web_preview', 'poster' ];

const KIND_PATTERN = /^[a-z0-9]+(?:_[a-z0-9]+)*$/;

function formatBytes(bytes) {
    if (!bytes && bytes !== 0) return '—';
    if (bytes < 1024) return `${bytes} B`;
    const units = [ 'KB', 'MB', 'GB' ];
    let value = bytes / 1024;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit += 1; }
    return `${value.toFixed(1)} ${units[unit]}`;
}

/**
 * The manual-rendition panel for one asset.
 *
 * Sits beside Versions rather than inside it on purpose. A version answers
 * "what did this asset look like at time T" and the newest one supersedes the
 * rest; a rendition answers "give me this asset in form X", and every one of
 * them is current at once. Filing a CMYK master as a version would make the web
 * original read as superseded history.
 */
export default function AssetRenditionsTab({ asset, canModify = true }) {
    const { t } = useTranslation();
    const assetId = asset?.id;
    const { renditions, loading, saving, error, setError, upload, remove } =
        useAssetRenditions({ assetId, enabled: Boolean(assetId) });

    const [kind, setKind] = useState('');
    const [file, setFile] = useState(null);
    const [pendingDelete, setPendingDelete] = useState(null);
    const fileInput = useRef(null);

    const trimmedKind = kind.trim().toLowerCase();
    const reserved = RESERVED_KINDS.includes(trimmedKind);
    const malformed = trimmedKind.length > 0 && !KIND_PATTERN.test(trimmedKind);
    const duplicate = renditions.some((r) => r.kind === trimmedKind);

    let kindError = null;
    if (reserved) kindError = t('renditions.error.reservedKind', { kind: trimmedKind });
    else if (malformed) kindError = t('renditions.error.malformedKind');
    else if (duplicate) kindError = t('renditions.error.duplicateKind');

    const canSubmit = Boolean(file) && trimmedKind.length > 0 && !kindError && !saving;

    const handleUpload = async () => {
        if (!canSubmit) return;
        const ok = await upload({ file, kind: trimmedKind });
        if (ok) {
            setKind('');
            setFile(null);
            if (fileInput.current) fileInput.current.value = '';
        }
    };

    const confirmDelete = async () => {
        if (!pendingDelete) return;
        await remove(pendingDelete.id);
        setPendingDelete(null);
    };

    return (
        <Box sx={{ py: 2 }} data-testid="asset-renditions-tab">
            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                {t('renditions.description')}
            </Typography>

            {error && (
                <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>
                    {error}
                </Alert>
            )}

            {canModify && (
                <Box sx={{ display: 'flex', gap: 1, alignItems: 'flex-start', mb: 3, flexWrap: 'wrap' }}>
                    <TextField
                        size="small"
                        label={t('renditions.field.kind')}
                        placeholder="print_cmyk"
                        value={kind}
                        onChange={(e) => setKind(e.target.value)}
                        error={Boolean(kindError)}
                        helperText={kindError || t('renditions.field.kindHelp')}
                        sx={{ minWidth: 200 }}
                        inputProps={{ 'aria-label': t('renditions.field.kind') }}
                    />
                    <Button
                        component="label"
                        variant="outlined"
                        size="small"
                        startIcon={<UploadFileOutlined />}
                        sx={{ mt: 0.5 }}
                    >
                        {file ? file.name : t('renditions.action.chooseFile')}
                        <input
                            hidden
                            type="file"
                            ref={fileInput}
                            data-testid="rendition-file-input"
                            onChange={(e) => setFile(e.target.files?.[0] || null)}
                        />
                    </Button>
                    <Button
                        variant="contained"
                        size="small"
                        sx={{ mt: 0.5 }}
                        disabled={!canSubmit}
                        onClick={handleUpload}
                    >
                        {saving ? <CircularProgress size={18} /> : t('renditions.action.upload')}
                    </Button>
                </Box>
            )}

            {loading && <CircularProgress size={22} />}

            {!loading && renditions.length === 0 && (
                <Typography variant="body2" color="text.secondary">
                    {t('renditions.empty')}
                </Typography>
            )}

            {!loading && renditions.length > 0 && (
                <Table size="small">
                    <TableHead>
                        <TableRow>
                            <TableCell>{t('renditions.column.kind')}</TableCell>
                            <TableCell>{t('renditions.column.type')}</TableCell>
                            <TableCell>{t('renditions.column.dimensions')}</TableCell>
                            <TableCell>{t('renditions.column.size')}</TableCell>
                            <TableCell>{t('renditions.column.source')}</TableCell>
                            <TableCell align="right">{t('renditions.column.actions')}</TableCell>
                        </TableRow>
                    </TableHead>
                    <TableBody>
                        {renditions.map((r) => (
                            <TableRow key={r.id} hover>
                                <TableCell>{r.kind}</TableCell>
                                <TableCell>{r.content_type || '—'}</TableCell>
                                <TableCell>{r.width && r.height ? `${r.width} × ${r.height}` : '—'}</TableCell>
                                <TableCell>{formatBytes(r.file_size)}</TableCell>
                                <TableCell>
                                    <Chip
                                        size="small"
                                        label={r.source === 'manual'
                                            ? t('renditions.source.manual')
                                            : t('renditions.source.generated')}
                                        color={r.source === 'manual' ? 'primary' : 'default'}
                                        variant="outlined"
                                    />
                                </TableCell>
                                <TableCell align="right">
                                    {r.url && (
                                        <Tooltip title={t('renditions.action.open')}>
                                            <IconButton
                                                size="small"
                                                component={Link}
                                                href={r.url}
                                                target="_blank"
                                                rel="noopener"
                                                aria-label={t('renditions.action.open')}
                                            >
                                                <OpenInNew fontSize="small" />
                                            </IconButton>
                                        </Tooltip>
                                    )}
                                    {canModify && (
                                        <Tooltip title={
                                            r.source === 'generated'
                                                ? t('renditions.action.generatedLocked')
                                                : t('renditions.action.delete')
                                        }>
                                            <span>
                                                <IconButton
                                                    size="small"
                                                    color="error"
                                                    disabled={r.source === 'generated'}
                                                    onClick={() => setPendingDelete(r)}
                                                    aria-label={t('renditions.action.delete')}
                                                >
                                                    <DeleteOutlined fontSize="small" />
                                                </IconButton>
                                            </span>
                                        </Tooltip>
                                    )}
                                </TableCell>
                            </TableRow>
                        ))}
                    </TableBody>
                </Table>
            )}

            <Dialog open={Boolean(pendingDelete)} onClose={() => setPendingDelete(null)}>
                <DialogTitle>{t('renditions.deleteDialog.title')}</DialogTitle>
                <DialogContent>
                    <DialogContentText>
                        {t('renditions.deleteDialog.body', { kind: pendingDelete?.kind })}
                    </DialogContentText>
                </DialogContent>
                <DialogActions>
                    <Button onClick={() => setPendingDelete(null)}>{t('common.cancel')}</Button>
                    <Button color="error" variant="contained" onClick={confirmDelete}>
                        {t('renditions.action.delete')}
                    </Button>
                </DialogActions>
            </Dialog>
        </Box>
    );
}
