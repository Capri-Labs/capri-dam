import React, { useEffect, useState } from 'react';
import {
    Autocomplete, TextField, Checkbox, Box, Chip,
} from '@mui/material';
import {
    CheckBoxOutlineBlank, CheckBox, FolderOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';

const UNCHECKED_ICON = <CheckBoxOutlineBlank fontSize="small" />;
const CHECKED_ICON = <CheckBox fontSize="small" />;

/**
 * Folder search + multi-select filter for the Reports/Analytics toolbar.
 *
 * Renders as a searchable combobox (an MUI `Autocomplete` — the dropdown IS
 * the "overlay" the user picks folders from) so multiple, non-contiguous
 * folder paths can be selected at once. Selecting a parent folder implicitly
 * scopes to its sub-folders too (resolved server-side in
 * `Reports::AnalyticsService`); this component only deals with the ids the
 * user explicitly picked.
 *
 * Folder options are fetched once from `GET /api/v1/folders`, which already
 * returns each folder's full breadcrumb path (e.g. "/Marketing/2026/Assets")
 * — reused as-is so folders are easy to disambiguate when multiple paths
 * share the same leaf name.
 */
export default function ReportFolderFilter({ value, onChange }) {
    const { t } = useTranslation();
    const [options, setOptions] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let cancelled = false;
        fetch('/api/v1/folders', { headers: { Accept: 'application/json' } })
            .then((res) => (res.ok ? res.json() : Promise.reject(new Error(`HTTP ${res.status}`))))
            .then((data) => {
                if (!cancelled) setOptions(data.folders ?? []);
            })
            .catch(() => {
                if (!cancelled) setOptions([]);
            })
            .finally(() => {
                if (!cancelled) setLoading(false);
            });
        return () => { cancelled = true; };
    }, []);

    const selected = options.filter((f) => value.includes(String(f.id)));

    return (
        <Autocomplete
            multiple
            size="small"
            disableCloseOnSelect
            loading={loading}
            options={options}
            value={selected}
            onChange={(_, newValue) => onChange(newValue.map((f) => String(f.id)))}
            getOptionLabel={(option) => option.name}
            isOptionEqualToValue={(a, b) => String(a.id) === String(b.id)}
            data-testid="report-folder-filter"
            renderOption={(props, option, { selected: isSelected }) => (
                <Box component="li" {...props} key={option.id} data-testid={`report-folder-option-${option.id}`}>
                    <Checkbox
                        icon={UNCHECKED_ICON}
                        checkedIcon={CHECKED_ICON}
                        checked={isSelected}
                        sx={{ mr: 1 }}
                    />
                    <FolderOutlined fontSize="small" sx={{ mr: 1, color: '#94a3b8' }} />
                    {option.name}
                </Box>
            )}
            renderTags={(tagValue, getTagProps) => tagValue.map((option, index) => {
                const { key, ...tagProps } = getTagProps({ index });
                return (
                    <Chip
                        key={option.id}
                        label={option.name.split('/').pop() || option.name}
                        size="small"
                        {...tagProps}
                    />
                );
            })}
            renderInput={(params) => (
                <TextField
                    {...params}
                    placeholder={value.length === 0 ? t('reportsFolderFilter.placeholder') : ''}
                    label={t('reportsFolderFilter.label')}
                    sx={{ bgcolor: 'white' }}
                />
            )}
            sx={{ minWidth: 240, maxWidth: 360 }}
        />
    );
}
