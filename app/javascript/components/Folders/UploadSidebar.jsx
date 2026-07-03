import React from 'react';
import {
    Box, Typography, Button, TextField, Checkbox, FormControlLabel,
    Select, MenuItem, Chip, Stack, CircularProgress, Divider, Autocomplete, IconButton,
    LinearProgress
} from '@mui/material';
import { Close, AutoAwesome, CollectionsBookmark, CategoryOutlined, AutoFixHigh, ContentCut, CloudUpload, SchemaOutlined } from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const IMAGE_TYPES = [
    { value: 'Product Image', labelKey: 'uploadSidebar.imageTypes.productImage' },
    { value: 'Lifestyle', labelKey: 'uploadSidebar.imageTypes.lifestyle' },
    { value: 'Banner / Hero', labelKey: 'uploadSidebar.imageTypes.bannerHero' },
    { value: 'Headshot', labelKey: 'uploadSidebar.imageTypes.headshot' },
    { value: 'Document', labelKey: 'uploadSidebar.imageTypes.document' }
];

export default function UploadSidebar({
    globalMeta,
    setGlobalMeta,
    handleGlobalSchemaChange,
    schemaOptions,
    collectionOptions = [],
    handleAiGlobalAction,
    isAiProcessing,
    filesData,
    handleUploadAll,
    isUploading,
    uploadProgress = { done: 0, total: 0 },
    selectedCount,
    onClose
}) {
    const { t } = useTranslation();
    const tr = (key, defaultValue, options = {}) => {
        const value = t(key, { defaultValue, ...options });
        if (value === key || (options.count != null && value === `${key}:${options.count}`)) {
            return defaultValue.replace(/\{\{(\w+)\}\}/g, (_, token) => options[token] ?? '');
        }
        return value;
    };
    // Normalize collection options to plain names for the Autocomplete
    const collectionNames = (collectionOptions || [])
        .map(c => (typeof c === 'string' ? c : c?.name))
        .filter(Boolean);

    return (
        <Box sx={{ width: 340, bgcolor: '#ffffff', borderRight: '1px solid #e2e8f0', display: 'flex', flexDirection: 'column', boxShadow: '1px 0 10px rgba(0,0,0,0.03)', zIndex: 10 }}>
            <Box sx={{ p: 3, borderBottom: '1px solid #e2e8f0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Typography variant="h6" fontWeight="700">{tr('uploadSidebar.title', 'Upload & Enrich')}</Typography>
                <IconButton size="small" onClick={onClose} sx={{ color: '#64748b' }}><Close /></IconButton>
            </Box>

            <Box sx={{ p: 3, flexGrow: 1, overflowY: 'auto' }}>
                <Typography variant="subtitle2" fontWeight="700" sx={{ mb: 2, display: 'flex', alignItems: 'center' }}>
                    <CollectionsBookmark fontSize="small" sx={{ mr: 1, color: '#64748b' }}/>{tr('uploadSidebar.sections.assignment', 'Assignment')}
                </Typography>
                <Autocomplete
                    size="small" options={collectionNames} value={globalMeta.collection}
                    onChange={(e, val) => setGlobalMeta({ ...globalMeta, collection: val })}
                    noOptionsText={tr('uploadSidebar.noCollectionsFound', 'No collections found')}
                    renderInput={(params) => <TextField {...params} placeholder={tr('uploadSidebar.placeholders.selectExistingCollection', 'Select existing collection...')} sx={{ mb: 2, bgcolor: '#f8fafc' }} />}
                />

                <Select
                    variant="outlined"
                    fullWidth size="small" value={globalMeta.imageType} displayEmpty
                    onChange={(e) => setGlobalMeta({ ...globalMeta, imageType: e.target.value })}
                    sx={{ mb: 2, bgcolor: '#f8fafc' }}
                >
                    <MenuItem value="" disabled>{tr('uploadSidebar.placeholders.selectGlobalAssetType', 'Select global asset type')}</MenuItem>
                    {IMAGE_TYPES.map((imageType) => <MenuItem key={imageType.value} value={imageType.value}>{tr(imageType.labelKey, imageType.value)}</MenuItem>)}
                </Select>

                <Divider sx={{ mb: 3, mt: 2 }} />

                <Typography variant="subtitle2" fontWeight="700" sx={{ mb: 1.5, display: 'flex', alignItems: 'center' }}>
                    <SchemaOutlined fontSize="small" sx={{ mr: 1, color: '#64748b' }}/>{tr('uploadSidebar.sections.metadataSchema', 'Metadata Schema')}
                </Typography>
                <Select
                    variant="outlined"
                    fullWidth size="small"
                    value={globalMeta.schemaId || ''}
                    displayEmpty
                    onChange={(e) => handleGlobalSchemaChange(e.target.value ? Number(e.target.value) : null)}
                    sx={{ mb: 1.5, bgcolor: '#f8fafc' }}
                >
                    <MenuItem value="" disabled>{tr('uploadSidebar.placeholders.selectGlobalSchema', 'Select global schema')}</MenuItem>
                    {schemaOptions.map(s => (
                        <MenuItem key={s.id} value={s.id}>{s.name}</MenuItem>
                    ))}
                </Select>
                <Typography variant="caption" sx={{ color: '#64748b', display: 'block', mb: 2 }}>
                    {tr('uploadSidebar.schemaHelp', 'This schema is applied to all staged files by default. Per-file override is available in each card.')}
                </Typography>

                <Typography variant="caption" sx={{ color: '#64748b', display: 'block', mb: 3 }}>
                    {tr('uploadSidebar.filenamePatternPrefix', 'For Product Images: filename pattern supported:')} <strong>ProductID-LanguageCode-AssetTypeCode.ext</strong>
                    {' '}{tr('uploadSidebar.filenamePatternExample', 'e.g. 012993112028-en-FR01.jpg')}
                </Typography>

                <Divider sx={{ mb: 3 }} />

                <Typography variant="subtitle2" fontWeight="700" sx={{ mb: 2, display: 'flex', alignItems: 'center' }}>
                    <CategoryOutlined fontSize="small" sx={{ mr: 1, color: '#64748b' }}/>{tr('uploadSidebar.sections.tags', 'Tags')}
                </Typography>
                <Autocomplete multiple freeSolo size="small" options={[]} value={globalMeta.manualTags} onChange={(e, val) => setGlobalMeta({
  ...globalMeta,
  manualTags: val
})} renderValue={(value, getTagProps) => value.map((option, index) => {
  const { key, ...tagProps } = getTagProps({ index });
  return <Chip key={key} variant="outlined" label={option} {...tagProps} size="small" />;
})} renderInput={params => <TextField {...params} placeholder={tr('uploadSidebar.placeholders.typeAndPressEnter', 'Type and press enter')} sx={{
  mb: 2,
  bgcolor: '#f8fafc'
}} />} />
                <FormControlLabel
                    control={<Checkbox checked={globalMeta.aiTagsEnabled} onChange={(e) => setGlobalMeta({ ...globalMeta, aiTagsEnabled: e.target.checked })} size="small" sx={{ color: '#4f46e5' }} />}
                    label={<Typography variant="body2" fontWeight="600">{tr('uploadSidebar.aiTagsOnUpload', 'Generate AI Tags on Upload')}</Typography>}
                    sx={{ mb: 2.5 }}
                />

                <Divider sx={{ mb: 3 }} />

                <Typography variant="subtitle2" fontWeight="700" sx={{ mb: 2, display: 'flex', alignItems: 'center', color: '#6d28d9' }}>
                    <AutoFixHigh fontSize="small" sx={{ mr: 1 }}/>{tr('uploadSidebar.sections.aiAgenticActions', 'AI Agentic Actions')}
                </Typography>
                <Stack spacing={1.5}>
                    <Button variant="outlined" startIcon={<AutoAwesome />} onClick={() => handleAiGlobalAction('tag')} disabled={isAiProcessing || filesData.length === 0} sx={{ justifyContent: 'flex-start', color: '#6d28d9', borderColor: '#ddd6fe', bgcolor: '#f5f3ff' }}>{tr('uploadSidebar.buttons.smartDescribeSelected', 'Smart Describe Selected')}</Button>
                    <Button variant="outlined" startIcon={<ContentCut />} onClick={() => handleAiGlobalAction('bg')} disabled={isAiProcessing || filesData.length === 0} sx={{ justifyContent: 'flex-start', color: '#6d28d9', borderColor: '#ddd6fe', bgcolor: '#f5f3ff' }}>{tr('uploadSidebar.buttons.autoRemoveBackgrounds', 'Auto-Remove Backgrounds')}</Button>
                </Stack>
            </Box>

            <Box sx={{ p: 3, borderTop: '1px solid #e2e8f0', bgcolor: '#f8fafc' }}>
                {isUploading && uploadProgress.total > 0 && (
                    <Box sx={{ mb: 2 }} data-testid="upload-progress">
                        <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
                            <Typography variant="caption" fontWeight="600" color="#475569">{tr('uploadSidebar.progress.uploading', 'Uploading…')}</Typography>
                            <Typography variant="caption" fontWeight="700" color="#4f46e5">
                                {tr('uploadSidebar.progress.count', '{{done}} of {{total}}', { done: uploadProgress.done, total: uploadProgress.total })}
                            </Typography>
                        </Box>
                        <LinearProgress
                            variant="determinate"
                            value={uploadProgress.total ? Math.round((uploadProgress.done / uploadProgress.total) * 100) : 0}
                            sx={{ height: 8, borderRadius: 4 }}
                        />
                    </Box>
                )}
                <Button variant="outlined" startIcon={<CloudUpload />} fullWidth onClick={handleUploadAll} disabled={isUploading || selectedCount === 0} sx={{ py: 1.5, '&:hover': { bgcolor: '#4338ca' }, textTransform: 'none', fontWeight: 700 }}>
                    {isUploading ? <CircularProgress size={24} color="inherit" /> : tr('uploadSidebar.buttons.uploadCount', 'Upload ({{selectedCount}})', { selectedCount })}
                </Button>
            </Box>
        </Box>
    );
}