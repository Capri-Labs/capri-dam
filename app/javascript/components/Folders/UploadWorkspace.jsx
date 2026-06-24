import React, { useState, useCallback, useEffect } from 'react';
import { Box } from '@mui/material';
import { useDropzone } from 'react-dropzone';
import { useNotify } from '../../context/NotificationContext';
import { calculateFileHash } from '../../utils/globalutils';
import { parseProductFilename, defaultSchemaSlugForMime } from '../../utils/productFilename';

import UploadSidebar from './UploadSidebar';
import UploadGrid from './UploadGrid';
import DuplicateResolverDialog from './DuplicateResolverDialog';

/**
 * Returns true if the given MIME type is permitted by the allowedMimes list.
 * Supports exact matches (e.g. "image/jpeg") and wildcard type patterns (e.g. "image/*").
 * If allowedMimes is empty the function returns true (no restrictions).
 */
function isMimeAllowed(mimeType, allowedMimes) {
    if (!allowedMimes || allowedMimes.length === 0) return true;
    const mime = (mimeType || '').toLowerCase();
    return allowedMimes.some(pattern => {
        const p = pattern.trim().toLowerCase();
        if (p.endsWith('/*')) {
            // wildcard: "image/*" matches "image/jpeg", "image/png", etc.
            const prefix = p.slice(0, -1); // "image/"
            return mime.startsWith(prefix);
        }
        return mime === p;
    });
}

export default function UploadWorkspace({ folderId, onClose, onUploadComplete }) {
    const notify = useNotify();
    const [filesData, setFilesData] = useState([]);

    // Available schemas for upload-time assignment
    const [schemaOptions, setSchemaOptions] = useState([]);

    // Available collections for upload-time assignment
    const [collectionOptions, setCollectionOptions] = useState([]);

    // Allowed MIME types (empty = allow all)
    const [allowedMimes, setAllowedMimes] = useState([]);

    // Global & UI States
    const [globalMeta, setGlobalMeta] = useState({
        collection: null,
        imageType: '',
        resizePreset: 'original',
        manualTags: [],
        aiTagsEnabled: true,
        schemaId: null
    });
    const [isUploading, setIsUploading] = useState(false);
    const [isAiProcessing, setIsAiProcessing] = useState(false);

    // Duplicate Resolver State
    const [activeDuplicateFile, setActiveDuplicateFile] = useState(null);

    // Load schema options once
    useEffect(() => {
        const loadSchemas = async () => {
            try {
                const res = await fetch('/api/v1/metadata_schemas');
                if (!res.ok) return;
                const data = await res.json();
                // Upload can only assign root schemas
                const roots = data.filter(s => s.level === 'root');
                setSchemaOptions(roots);
            } catch (_) {
                // non-blocking
            }
        };
        loadSchemas();
    }, []);

    // Load upload restrictions once
    useEffect(() => {
        const loadRestrictions = async () => {
            try {
                const res = await fetch('/api/v1/upload_restrictions');
                if (!res.ok) return;
                const data = await res.json();
                setAllowedMimes(Array.isArray(data.allowed_mime_types) ? data.allowed_mime_types : []);
            } catch (_) {
                // non-blocking — if the request fails, default to allowing all
            }
        };
        loadRestrictions();
    }, []);

    // Load existing collections once
    useEffect(() => {
        const loadCollections = async () => {
            try {
                const res = await fetch('/api/v1/collections');
                if (!res.ok) return;
                const data = await res.json();
                // Normalize into { id, name, slug } shape for the sidebar Autocomplete
                const options = (Array.isArray(data) ? data : [])
                    .filter(c => c && c.name)
                    .map(c => ({ id: c.id, name: c.name, slug: c.slug }));
                setCollectionOptions(options);
            } catch (_) {
                // non-blocking
            }
        };
        loadCollections();
    }, []);

    const findDefaultSchemaForMime = (mimeType) => {
        const slug = defaultSchemaSlugForMime(mimeType);
        return schemaOptions.find(s => s.slug === slug) || null;
    };

    // If files were added before schema list finished loading, backfill defaults now.
    useEffect(() => {
        if (!schemaOptions.length || !filesData.length) return;
        setFilesData(prev => prev.map(f => {
            if (f.meta.schemaId) return f;
            const fallback = findDefaultSchemaForMime(f.file?.type);
            return fallback
                ? { ...f, meta: { ...f.meta, schemaId: fallback.id, schemaSlug: fallback.slug } }
                : f;
        }));
    }, [schemaOptions]);

    const onDrop = useCallback(async (acceptedFiles) => {
        // ── MIME restriction check ──────────────────────────────────────────────
        const rejected = acceptedFiles.filter(f => !isMimeAllowed(f.type, allowedMimes));
        const permitted = acceptedFiles.filter(f => isMimeAllowed(f.type, allowedMimes));

        if (rejected.length > 0) {
            const names = rejected.map(f => `"${f.name}" (${f.type || 'unknown type'})`).join(', ');
            notify(
                `Upload not allowed: ${names}. Only the following MIME types are permitted: ${allowedMimes.join(', ')}.`,
                'error'
            );
        }

        if (permitted.length === 0) return;
        // ───────────────────────────────────────────────────────────────────────

        const newFilesPromises = permitted.map(async (file) => {
            const previewUrl = URL.createObjectURL(file);
            const dimensions = await new Promise((resolve) => {
                if (file.type.startsWith('image/')) {
                    const img = new Image();
                    img.onload = () => resolve(`${img.width} x ${img.height}`);
                    img.onerror = () => resolve('Unknown');
                    img.src = previewUrl;
                } else resolve('N/A');
            });

            const parsedName = parseProductFilename(file.name);
            const defaultSchema = findDefaultSchemaForMime(file.type);

            return {
                id: Math.random().toString(36).substring(7),
                file,
                preview: previewUrl,
                status: 'hashing',
                hash: null,
                isDuplicate: false,
                duplicateData: null,
                selected: true,
                meta: {
                    title: file.name,
                    type: '',
                    dimensions,
                    size: `${(file.size / (1024 * 1024)).toFixed(2)} MB`,
                    aiTags: [],
                    schemaId: defaultSchema?.id || null,
                    schemaSlug: defaultSchema?.slug || null,
                    // Product naming-derived metadata
                    productId: parsedName?.isProductNaming ? parsedName.productId : '',
                    languageCode: parsedName?.isProductNaming ? parsedName.langCode : '',
                    assetTypeCode: parsedName?.isProductNaming ? parsedName.assetTypeCode : ''
                }
            };
        });

        const newFiles = await Promise.all(newFilesPromises);
        setFilesData(prev => [...prev, ...newFiles]);

        const hashedFiles = await Promise.all(newFiles.map(async (fData) => {
            const hash = await calculateFileHash(fData.file);
            return { ...fData, hash };
        }));

        setFilesData(prev => prev.map(p => {
            const hFile = hashedFiles.find(hf => hf.id === p.id);
            return hFile ? { ...p, hash: hFile.hash, status: 'checking' } : p;
        }));

        checkDuplicates(hashedFiles);
    }, [schemaOptions, allowedMimes]);

    const { getRootProps, getInputProps, isDragActive } = useDropzone({ onDrop });

    const checkDuplicates = async (hashedFiles) => {
        try {
            const hashes = hashedFiles.map(f => f.hash);
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch('/api/v1/assets/check_hashes', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ hashes })
            });

            if (res.ok) {
                const data = await res.json();
                const duplicatesMap = data.duplicates || {};
                setFilesData(prev => prev.map(f => duplicatesMap[f.hash]
                    ? { ...f, status: 'ready', isDuplicate: true, duplicateData: duplicatesMap[f.hash] }
                    : { ...f, status: 'ready' }
                ));
            }
        } catch (error) {
            setFilesData(prev => prev.map(f => f.status === 'checking' ? { ...f, status: 'ready' } : f));
        }
    };

    // Handlers passed to children
    const handleToggleSelectAll = (event) => setFilesData(prev => prev.map(f => ({ ...f, selected: event.target.checked })));
    const handleToggleSelectFile = (id) => setFilesData(prev => prev.map(f => f.id === id ? { ...f, selected: !f.selected } : f));

    const handleRemoveFile = (id) => setFilesData(prev => {
        const target = prev.find(f => f.id === id);
        if (target?.preview) URL.revokeObjectURL(target.preview);
        return prev.filter(f => f.id !== id);
    });

    const handleAiGlobalAction = (actionType) => {
        setIsAiProcessing(true);
        setTimeout(() => {
            setFilesData(prev => prev.map(f => !f.selected
                ? f
                : actionType === 'tag'
                    ? { ...f, meta: { ...f.meta, type: 'Product Image', aiTags: ['Studio', 'High-Res', 'Isolated'] } }
                    : f
            ));
            setIsAiProcessing(false);
            notify(actionType === 'tag' ? 'AI Auto-tagging complete.' : 'Backgrounds removed.', 'success');
        }, 2000);
    };

    const handleSingleFileAi = (id) => {
        setFilesData(prev => prev.map(f => f.id === id
            ? { ...f, meta: { ...f.meta, aiTags: ['Enhanced', 'Web-Ready'] } }
            : f
        ));
        notify('AI enhancements applied.', 'success');
    };

    // Global schema change can apply to all staged files (left-panel behavior)
    const handleGlobalSchemaChange = (schemaId) => {
        setGlobalMeta(prev => ({ ...prev, schemaId }));
        setFilesData(prev => prev.map(f => ({
            ...f,
            meta: {
                ...f.meta,
                schemaId: schemaId || f.meta.schemaId
            }
        })));
    };

    // Handle resolution from the Duplicate Overlay
    const handleDuplicateResolution = (fileId, action) => {
        if (action === 'skip') {
            handleRemoveFile(fileId);
        } else if (action === 'upload') {
            setFilesData(prev => prev.map(f => f.id === fileId ? { ...f, isDuplicate: false } : f));
        }
        setActiveDuplicateFile(null);
    };

    const handleUploadAll = async () => {
        setIsUploading(true);
        const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
        const filesToProcess = filesData.filter(f => f.selected && f.status !== 'done');

        for (const fData of filesToProcess) {
            setFilesData(prev => prev.map(f => f.id === fData.id ? { ...f, status: 'uploading' } : f));
            const formData = new FormData();
            formData.append('file', fData.file);
            formData.append('title', fData.meta.title);
            if (globalMeta.collection) formData.append('collection', globalMeta.collection);
            if (globalMeta.imageType || fData.meta.type) formData.append('image_type', fData.meta.type || globalMeta.imageType);
            if (folderId) formData.append('folder_id', folderId);

            // Upload-time schema choice (file-level overrides global)
            const schemaIdToUse = fData.meta.schemaId || globalMeta.schemaId;
            if (schemaIdToUse) formData.append('schema_id', String(schemaIdToUse));

            // Upload-time metadata payload
            const metadataPayload = {
                'dam:product_id': fData.meta.productId || undefined,
                'dam:language_code': fData.meta.languageCode || undefined,
                'dam:asset_type': fData.meta.assetTypeCode || undefined,
                'tags': globalMeta.manualTags || undefined
            };
            formData.append('metadata', JSON.stringify(metadataPayload));

            try {
                const res = await fetch('/api/v1/assets', {
                    method: 'POST',
                    headers: { 'X-CSRF-Token': csrfToken },
                    body: formData
                });
                setFilesData(prev => prev.map(f => f.id === fData.id
                    ? { ...f, status: res.ok ? 'done' : 'error', selected: !res.ok }
                    : f
                ));
            } catch (error) {
                setFilesData(prev => prev.map(f => f.id === fData.id ? { ...f, status: 'error' } : f));
            }
        }

        setIsUploading(false);
        notify('Upload sequence complete.', 'success');
        if (onUploadComplete) onUploadComplete();
    };

    const selectedCount = filesData.filter(f => f.selected).length;

    return (
        <Box sx={{ display: 'flex', height: '100vh', bgcolor: '#f8fafc', color: '#1e293b' }}>
            <UploadSidebar
                globalMeta={globalMeta}
                setGlobalMeta={setGlobalMeta}
                handleGlobalSchemaChange={handleGlobalSchemaChange}
                schemaOptions={schemaOptions}
                collectionOptions={collectionOptions}
                handleAiGlobalAction={handleAiGlobalAction}
                isAiProcessing={isAiProcessing}
                filesData={filesData}
                handleUploadAll={handleUploadAll}
                isUploading={isUploading}
                selectedCount={selectedCount}
                onClose={onClose}
            />

            <UploadGrid
                filesData={filesData}
                setFilesData={setFilesData}
                getRootProps={getRootProps}
                getInputProps={getInputProps}
                isDragActive={isDragActive}
                handleToggleSelectAll={handleToggleSelectAll}
                handleToggleSelectFile={handleToggleSelectFile}
                handleRemoveFile={handleRemoveFile}
                allSelected={filesData.length > 0 && selectedCount === filesData.length}
                selectedCount={selectedCount}
                onClose={onClose}
                globalMeta={globalMeta}
                schemaOptions={schemaOptions}
                handleSingleFileAi={handleSingleFileAi}
                onOpenDuplicate={(file) => setActiveDuplicateFile(file)}
            />

            <DuplicateResolverDialog
                open={Boolean(activeDuplicateFile)}
                onClose={() => setActiveDuplicateFile(null)}
                fileData={activeDuplicateFile}
                onResolve={handleDuplicateResolution}
            />
        </Box>
    );
}