import React, { useState, useCallback } from 'react';
import { Box } from '@mui/material';
import { useDropzone } from 'react-dropzone';
import { useNotify } from '../../context/NotificationContext';
import { calculateFileHash } from '../../utils/globalutils';

import UploadSidebar from './UploadSidebar';
import UploadGrid from './UploadGrid';
import DuplicateResolverDialog from './DuplicateResolverDialog';

export default function UploadWorkspace({ folderId, onClose, onUploadComplete }) {
    const notify = useNotify();
    const [filesData, setFilesData] = useState([]);

    // Global & UI States
    const [globalMeta, setGlobalMeta] = useState({ collection: null, imageType: '', resizePreset: 'original', manualTags: [], aiTagsEnabled: true });
    const [isUploading, setIsUploading] = useState(false);
    const [isAiProcessing, setIsAiProcessing] = useState(false);

    // Duplicate Resolver State
    const [activeDuplicateFile, setActiveDuplicateFile] = useState(null);

    const onDrop = useCallback(async (acceptedFiles) => {
        const newFilesPromises = acceptedFiles.map(async (file) => {
            const previewUrl = URL.createObjectURL(file);
            const dimensions = await new Promise((resolve) => {
                if (file.type.startsWith('image/')) {
                    const img = new Image();
                    img.onload = () => resolve(`${img.width} x ${img.height}`);
                    img.onerror = () => resolve('Unknown');
                    img.src = previewUrl;
                } else resolve('N/A');
            });

            return {
                id: Math.random().toString(36).substring(7),
                file, preview: previewUrl, status: 'hashing', hash: null,
                isDuplicate: false, duplicateData: null, selected: true,
                meta: { title: file.name, type: '', dimensions, size: `${(file.size / (1024 * 1024)).toFixed(2)} MB`, aiTags: [] }
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
    }, []);

    const { getRootProps, getInputProps, isDragActive } = useDropzone({ onDrop });

    const checkDuplicates = async (hashedFiles) => {
        try {
            const hashes = hashedFiles.map(f => f.hash);
            const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
            const res = await fetch('/api/v1/assets/check_hashes', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken }, body: JSON.stringify({ hashes }) });

            if (res.ok) {
                const data = await res.json();
                const duplicatesMap = data.duplicates || {};
                setFilesData(prev => prev.map(f => duplicatesMap[f.hash] ? { ...f, status: 'ready', isDuplicate: true, duplicateData: duplicatesMap[f.hash] } : { ...f, status: 'ready' }));
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
            setFilesData(prev => prev.map(f => !f.selected ? f : actionType === 'tag' ? { ...f, meta: { ...f.meta, type: 'Product Image', aiTags: ['Studio', 'High-Res', 'Isolated'] } } : f));
            setIsAiProcessing(false);
            notify(actionType === 'tag' ? "AI Auto-tagging complete." : "Backgrounds removed.", "success");
        }, 2000);
    };

    const handleSingleFileAi = (id) => {
        setFilesData(prev => prev.map(f => f.id === id ? { ...f, meta: { ...f.meta, aiTags: ['Enhanced', 'Web-Ready'] } } : f));
        notify("AI enhancements applied.", "success");
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

        for (let fData of filesToProcess) {
            setFilesData(prev => prev.map(f => f.id === fData.id ? { ...f, status: 'uploading' } : f));
            const formData = new FormData();
            formData.append('file', fData.file);
            formData.append('title', fData.meta.title);
            if (globalMeta.collection) formData.append('collection', globalMeta.collection);
            if (globalMeta.imageType || fData.meta.type) formData.append('image_type', fData.meta.type || globalMeta.imageType);
            if (folderId) formData.append('folder_id', folderId);

            try {
                const res = await fetch('/api/v1/assets', { method: 'POST', headers: { 'X-CSRF-Token': csrfToken }, body: formData });
                setFilesData(prev => prev.map(f => f.id === fData.id ? { ...f, status: res.ok ? 'done' : 'error', selected: !res.ok } : f));
            } catch (error) {
                setFilesData(prev => prev.map(f => f.id === fData.id ? { ...f, status: 'error' } : f));
            }
        }
        setIsUploading(false);
        notify("Upload sequence complete.", "success");
        if (onUploadComplete) onUploadComplete();
    };

    const selectedCount = filesData.filter(f => f.selected).length;

    return (
        <Box sx={{ display: 'flex', height: '100vh', bgcolor: '#f8fafc', color: '#1e293b' }}>
            <UploadSidebar
                globalMeta={globalMeta} setGlobalMeta={setGlobalMeta}
                handleAiGlobalAction={handleAiGlobalAction} isAiProcessing={isAiProcessing}
                filesData={filesData} handleUploadAll={handleUploadAll}
                isUploading={isUploading} selectedCount={selectedCount} onClose={onClose}
            />

            <UploadGrid
                filesData={filesData} setFilesData={setFilesData}
                getRootProps={getRootProps} getInputProps={getInputProps} isDragActive={isDragActive}
                handleToggleSelectAll={handleToggleSelectAll} handleToggleSelectFile={handleToggleSelectFile}
                handleRemoveFile={handleRemoveFile} allSelected={filesData.length > 0 && selectedCount === filesData.length}
                selectedCount={selectedCount} onClose={onClose} globalMeta={globalMeta}
                handleSingleFileAi={handleSingleFileAi} onOpenDuplicate={(file) => setActiveDuplicateFile(file)}
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