import React from 'react';
import {
    Box, Grid, Typography, Button, TextField, Checkbox, FormControlLabel,
    Select, MenuItem, Paper, IconButton, Chip, Tooltip, Divider
} from '@mui/material';
import { Close, Sync, WarningAmber, AddPhotoAlternate, AutoAwesome, Cancel, InsertDriveFile } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const IMAGE_TYPES = [
    { value: 'Product Image', labelKey: 'uploadGrid.image_types.product_image' },
    { value: 'Lifestyle', labelKey: 'uploadGrid.image_types.lifestyle' },
    { value: 'Banner / Hero', labelKey: 'uploadGrid.image_types.banner_hero' },
    { value: 'Headshot', labelKey: 'uploadGrid.image_types.headshot' },
    { value: 'Document', labelKey: 'uploadGrid.image_types.document' }
];
const ASSET_TYPE_CODES = ['FR01', 'FR02', 'FR03', 'BK01', 'BK02', 'SD01', 'SD02', 'TQ01', 'TQ02', 'TP01', 'TP02', 'DT01', 'DT02', 'DT03'];
const AI_TAG_LABEL_KEYS = {
    Studio: 'uploadGrid.ai_tags.studio',
    'High-Res': 'uploadGrid.ai_tags.high_res',
    Isolated: 'uploadGrid.ai_tags.isolated',
    Enhanced: 'uploadGrid.ai_tags.enhanced',
    'Web-Ready': 'uploadGrid.ai_tags.web_ready'
};

export default function UploadGrid({
    filesData,
    setFilesData,
    getRootProps,
    getInputProps,
    isDragActive,
    handleToggleSelectAll,
    handleToggleSelectFile,
    handleRemoveFile,
    allSelected,
    selectedCount,
    onClose,
    globalMeta,
    schemaOptions,
    handleSingleFileAi,
    onOpenDuplicate
}) {
    const { t } = useTranslation();
    const translate = (key, fallback, options) => {
        const value = t(key, options);
        return value === key ? fallback : value;
    };
    const updateFileMeta = (id, patch) => {
        setFilesData(prev => prev.map(f => f.id === id ? { ...f, meta: { ...f.meta, ...patch } } : f));
    };

    return (
        <Box sx={{ flexGrow: 1, minWidth: 0, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
            <Box sx={{ p: 2, px: 4, borderBottom: '1px solid #e2e8f0', display: 'flex', justifyContent: 'space-between', alignItems: 'center', bgcolor: '#ffffff' }}>
                <Box sx={{ display: 'flex', alignItems: 'center' }}>
                    <Typography variant="h6" fontWeight="700" sx={{ mr: 3 }}>{translate('uploadGrid.staging_area', 'Staging Area')}</Typography>
                    <Chip label={translate('uploadGrid.selection_count', `${selectedCount} of ${filesData.length} selected`, { selected: selectedCount, total: filesData.length })} size="small" sx={{ bgcolor: '#eef2ff', color: '#4f46e5', fontWeight: 600 }} />
                </Box>

                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    {filesData.length > 0 && (
                        <FormControlLabel control={<Checkbox checked={allSelected} onChange={handleToggleSelectAll} size="small" />} label={<Typography variant="body2" fontWeight="600">{translate('uploadGrid.select_all', 'Select All')}</Typography>} sx={{ m: 0 }} />
                    )}
                    <Button variant="outlined" startIcon={<Cancel />} size="small" onClick={onClose} sx={{ textTransform: 'none' }}>{translate('common.cancel', 'Cancel')}</Button>
                </Box>
            </Box>

            <Box sx={{ flexGrow: 1, p: 4, overflowY: 'auto' }}>
                <Paper {...getRootProps()} elevation={0} sx={{ p: 4, mb: 4, textAlign: 'center', bgcolor: isDragActive ? '#eef2ff' : '#ffffff', border: '2px dashed', borderColor: isDragActive ? '#4f46e5' : '#cbd5e1', cursor: 'pointer', borderRadius: 3, '&:hover': { borderColor: '#4f46e5', bgcolor: '#f8fafc' } }}>
                    <input {...getInputProps()} />
                    <AddPhotoAlternate sx={{ fontSize: 48, color: '#94a3b8', mb: 2 }} />
                    <Typography variant="h6" color="#1e293b" fontWeight="600">{translate('uploadGrid.dropzone.drag_drop', 'Drag & drop new assets here')}</Typography>
                    <Typography variant="body2" color="#64748b">{translate('uploadGrid.dropzone.browse', 'or click to browse local files')}</Typography>
                </Paper>

                <Grid container spacing={3}>
                    {filesData.map((fData) => {
                        const resolvedSchemaId = fData.meta.schemaId || globalMeta.schemaId || '';
                        const isProductSchema = schemaOptions.find(s => s.id === Number(resolvedSchemaId))?.slug === 'product-images';

                        return (
                            <Grid size={{ xs: 12, sm: 6, md: 4, lg: 3 }} key={fData.id}>
                                <Paper elevation={fData.selected ? 3 : 0} sx={{ bgcolor: '#ffffff', borderRadius: 2, overflow: 'hidden', border: '1px solid', borderColor: fData.isDuplicate ? '#f59e0b' : fData.selected ? '#4f46e5' : '#e2e8f0', transition: 'all 0.2s' }}>
                                    <Box sx={{ display: 'flex', justifyContent: 'space-between', p: 1, position: 'absolute', width: '100%', zIndex: 10, bgcolor: 'linear-gradient(to bottom, rgba(0,0,0,0.4) 0%, rgba(0,0,0,0) 100%)' }}>
                                        <Checkbox checked={fData.selected} onChange={() => handleToggleSelectFile(fData.id)} sx={{ color: '#fff', '&.Mui-checked': { color: '#4f46e5', bgcolor: '#fff', borderRadius: 1, p: 0.5 } }} />
                                        <IconButton size="small" onClick={() => handleRemoveFile(fData.id)} sx={{ bgcolor: 'rgba(255,255,255,0.9)', '&:hover': { bgcolor: '#fee2e2', color: '#ef4444' } }}><Close fontSize="small" /></IconButton>
                                    </Box>

                                    <Box sx={{ height: 180, position: 'relative', bgcolor: '#f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                                        {fData.preview ? (
                                            <img src={fData.preview} alt={translate('uploadGrid.preview_alt', 'preview')} style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }} />
                                        ) : (
                                            <Box sx={{ textAlign: 'center', px: 1 }}>
                                                <InsertDriveFile sx={{ fontSize: 40, color: '#94a3b8' }} />
                                                <Typography variant="caption" sx={{ display: 'block', color: '#64748b', fontWeight: 700, textTransform: 'uppercase' }}>
                                                    {(fData.file?.name?.split('.').pop() || translate('uploadGrid.file_fallback_extension', 'file'))}
                                                </Typography>
                                                <Typography variant="caption" sx={{ display: 'block', color: '#94a3b8' }}>
                                                    {translate('uploadGrid.preview_generated_after_upload', 'Preview generated after upload')}
                                                </Typography>
                                            </Box>
                                        )}
                                        {['hashing', 'checking', 'uploading'].includes(fData.status) && (
                                            <Box sx={{ position: 'absolute', inset: 0, bgcolor: 'rgba(255,255,255,0.85)', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
                                                <Sync sx={{ animation: 'spin 2s linear infinite', color: '#4f46e5', mb: 1 }} />
                                                <Typography variant="caption" fontWeight="700" color="#4f46e5">{fData.status === 'hashing' ? translate('uploadGrid.status.calculating_hash', 'Calculating Hash...') : fData.status === 'checking' ? translate('uploadGrid.status.checking_dam', 'Checking DAM...') : translate('uploadGrid.status.uploading', 'Uploading...')}</Typography>
                                                <style>{`@keyframes spin { 100% { transform: rotate(360deg); } }`}</style>
                                            </Box>
                                        )}
                                    </Box>

                                    <Box sx={{ p: 2 }}>
                                        {fData.isDuplicate && (
                                            <Chip
                                                icon={<WarningAmber fontSize="small" />}
                                                label={translate('uploadGrid.duplicate_found', 'Duplicate Found')}
                                                size="small"
                                                onClick={() => onOpenDuplicate(fData)}
                                                sx={{ bgcolor: '#fef3c7', color: '#d97706', fontWeight: 700, mb: 1.5, cursor: 'pointer', '&:hover': { bgcolor: '#fde68a' } }}
                                            />
                                        )}

                                        <TextField
                                            fullWidth
                                            size="small"
                                            variant="standard"
                                            value={fData.meta.title}
                                            onChange={(e) => updateFileMeta(fData.id, { title: e.target.value })} slotProps={{input: { disableUnderline: true, sx: { fontSize: '0.875rem', fontWeight: 700, color: '#1e293b' } } }}
                                        />
                                        <Typography variant="caption" sx={{ display: 'block', color: '#64748b', mb: 1.5, mt: 0.5 }}>{fData.meta.size} • {fData.meta.dimensions === 'Unknown' ? translate('uploadGrid.dimensions.unknown', 'Unknown') : fData.meta.dimensions === 'N/A' ? translate('uploadGrid.dimensions.not_applicable', 'N/A') : fData.meta.dimensions}</Typography>
                                        <Divider sx={{ my: 1.5 }} />

                                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1.2 }}>
                                            <Select size="small" value={fData.meta.type || globalMeta.imageType} displayEmpty onChange={(e) => updateFileMeta(fData.id, { type: e.target.value })} sx={{ flexGrow: 1, fontSize: '0.75rem', height: 32 }}>
                                                <MenuItem value="" disabled>{translate('uploadGrid.type_placeholder', 'Type')}</MenuItem>
                                                {IMAGE_TYPES.map(({ value, labelKey }) => <MenuItem key={value} value={value}>{translate(labelKey, value)}</MenuItem>)}
                                            </Select>
                                            <Tooltip title={translate('uploadGrid.run_ai_enhance', 'Run AI enhance on this file')}>
                                                <IconButton size="small" onClick={() => handleSingleFileAi(fData.id)} sx={{ border: '1px solid #ddd6fe', color: '#6d28d9', borderRadius: 1, height: 32, width: 32 }}><AutoAwesome fontSize="small" /></IconButton>
                                            </Tooltip>
                                        </Box>

                                        {/* Per-file schema override */}
                                        <Select
                                            fullWidth
                                            size="small"
                                            value={resolvedSchemaId}
                                            displayEmpty
                                            onChange={(e) => updateFileMeta(fData.id, { schemaId: e.target.value ? Number(e.target.value) : null })}
                                            sx={{ mb: 1.2, fontSize: '0.75rem', height: 32 }}
                                        >
                                            <MenuItem value="" disabled>{translate('uploadGrid.select_schema', 'Select schema')}</MenuItem>
                                            {schemaOptions.map(s => <MenuItem key={s.id} value={s.id}>{s.name}</MenuItem>)}
                                        </Select>

                                        {/* Product schema fields */}
                                        {isProductSchema && (
                                            <Box sx={{ mb: 0.5 }}>
                                                <TextField
                                                    fullWidth
                                                    size="small"
                                                    label={translate('uploadGrid.product_id', 'Product ID')}
                                                    value={fData.meta.productId || ''}
                                                    onChange={(e) => updateFileMeta(fData.id, { productId: e.target.value })}
                                                    sx={{ mb: 1.2 }}
                                                />
                                                <TextField
                                                    fullWidth
                                                    size="small"
                                                    label={translate('uploadGrid.language_code', 'Language Code')}
                                                    value={fData.meta.languageCode || ''}
                                                    onChange={(e) => updateFileMeta(fData.id, { languageCode: e.target.value })}
                                                    sx={{ mb: 1.2 }}
                                                />
                                                <Select
                                                    fullWidth
                                                    size="small"
                                                    value={fData.meta.assetTypeCode || ''}
                                                    displayEmpty
                                                    onChange={(e) => updateFileMeta(fData.id, { assetTypeCode: e.target.value })}
                                                >
                                                    <MenuItem value="" disabled>{translate('uploadGrid.select_asset_type', 'Select Asset Type (dam:asset_type)')}</MenuItem>
                                                    {ASSET_TYPE_CODES.map(code => <MenuItem key={code} value={code}>{code}</MenuItem>)}
                                                </Select>
                                            </Box>
                                        )}

                                        {fData.meta.aiTags.length > 0 && (
                                            <Box sx={{ mt: 1.5, display: 'flex', gap: 0.5, flexWrap: 'wrap' }}>
                                                {fData.meta.aiTags.map(tag => <Chip key={tag} label={AI_TAG_LABEL_KEYS[tag] ? translate(AI_TAG_LABEL_KEYS[tag], tag) : tag} size="small" sx={{ height: 20, fontSize: '0.65rem', bgcolor: '#f3e8ff', color: '#6d28d9' }} />)}
                                            </Box>
                                        )}
                                    </Box>
                                </Paper>
                            </Grid>
                        );
                    })}
                </Grid>
            </Box>
        </Box>
    );
}