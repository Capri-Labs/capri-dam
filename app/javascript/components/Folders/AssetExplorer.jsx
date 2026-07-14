import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { Box, Divider, Typography, Dialog, DialogTitle, DialogContent, DialogActions, TextField, Button, Pagination, Backdrop, CircularProgress } from '@mui/material';
import { useTranslation } from 'react-i18next';
import { useNotify } from '../../context/NotificationContext';
import AssetViewer from './AssetViewer';
import AssetFilterBar, { PER_PAGE_OPTIONS } from './AssetFilterBar';
import ExplorerTopBar from './ExplorerTopBar';
import FolderGrid from './FolderGrid';
import AssetGrid from './AssetGrid';
import AssetList from './AssetList';
import PinToCollectionDialog from './PinToCollectionDialog';
import FolderInfoPanel from './FolderInfoPanel';
import DuplicateFinderDialog from './DuplicateResolverDialog';
import AiAnalysisDialog from './AiAnalysisDialog';

const matchesQuery = (value, query) => value.toLowerCase().includes(query.toLowerCase());
const isDocumentType = (contentType) => contentType.startsWith('application/') || contentType.startsWith('text/');

// ── URL param helpers ──────────────────────────────────────────────────────────
function readUrlFilters() {
  const p = new URLSearchParams(window.location.search);
  return {
    folderId:      p.get('folder') || 'root',
    query:         p.get('q') || '',
    typeFilters:   p.get('types') ? p.get('types').split(',') : [],
    statusFilters: p.get('statuses') ? p.get('statuses').split(',') : [],
    sort: {
      field:     p.get('sort_field') || 'name',
      direction: p.get('sort_dir') || 'asc',
    },
    perPage: Number(p.get('per_page')) || PER_PAGE_OPTIONS[0],
    page:    Number(p.get('page')) || 1,
    assetId: p.get('id') || null,
  };
}

function buildFilterUrl(folderId, { query, typeFilters, statusFilters, sort, perPage, page, assetId }) {
  const p = new URLSearchParams();
  if (folderId && folderId !== 'root') p.set('folder', folderId);
  if (query) p.set('q', query);
  if (typeFilters.length > 0) p.set('types', typeFilters.join(','));
  if (statusFilters.length > 0) p.set('statuses', statusFilters.join(','));
  if (sort.field !== 'name') p.set('sort_field', sort.field);
  if (sort.direction !== 'asc') p.set('sort_dir', sort.direction);
  if (perPage !== PER_PAGE_OPTIONS[0]) p.set('per_page', perPage);
  if (page > 1) p.set('page', page);
  // Preserve the open asset (AssetViewer) as `?id=` so deep-links such as
  // /assets?id=UUID (used by search results, the Duplicate Manager, and the
  // global search bar) survive the filter-sync effect below instead of being
  // silently stripped, and so "Copy Link"/"Share" always reflect the
  // currently-open asset.
  if (assetId) p.set('id', assetId);
  const qs = p.toString();
  return `${window.location.pathname}${qs ? `?${qs}` : ''}`;
}

export default function AssetExplorer({ initialTargetAssetId, pageTitle }) {
  const notify = useNotify();
  const { t } = useTranslation();
  const [viewData, setViewData] = useState({ folders: [], assets: [], breadcrumbs: [] });
  const [viewLayout, setViewLayout] = useState('grid');
  const [viewMode, setViewMode] = useState('active');

  // Initialise all filter state from URL on mount
  const initFilters = useMemo(() => readUrlFilters(), []); // eslint-disable-line react-hooks/exhaustive-deps
  const [gridSize, setGridSize] = useState('medium');
  const [query, setQuery] = useState(initFilters.query);
  const [typeFilters, setTypeFilters] = useState(initFilters.typeFilters);
  const [statusFilters, setStatusFilters] = useState(initFilters.statusFilters);
  const [perPage, setPerPage] = useState(initFilters.perPage);
  const [page, setPage] = useState(initFilters.page);
  const [sort, setSort] = useState(initFilters.sort);

  const [currentId, setCurrentId] = useState(initFilters.folderId);

  const [selectedAsset, setSelectedAsset] = useState(null);
  const [openFolderDialog, setOpenFolderDialog] = useState(false);
  const [newFolderName, setNewFolderName] = useState('');
  const [selectedItems, setSelectedItems] = useState({ folders: [], assets: [] });
  const [pinDialogOpen, setPinDialogOpen] = useState(false);
  const [assetToPin, setAssetToPin] = useState(null);
  const [duplicateFinderOpen, setDuplicateFinderOpen] = useState(false);
  const [duplicateFinderAsset, setDuplicateFinderAsset] = useState(null);
  const [aiAnalysisOpen, setAiAnalysisOpen] = useState(false);
  const [aiAnalysisAsset, setAiAnalysisAsset] = useState(null);
  const [infoFolder, setInfoFolder] = useState(null);
  const [infoPanelOpen, setInfoPanelOpen] = useState(false);

  const deepLinkProcessed = useRef(false);
  // Shows a full-screen loading spinner while a deep-linked asset
  // (`/folders?id=` or `/assets?id=`) is being fetched, so the user gets
  // immediate feedback instead of staring at the folder grid for the
  // duration of the request.
  const [deepLinkLoading, setDeepLinkLoading] = useState(Boolean(initialTargetAssetId));

  const handleFolderInfo = (folder) => {
    setInfoFolder(folder);
    setInfoPanelOpen(true);
  };

  const handlePinClick = (asset, event) => {
    if (event) event.stopPropagation();
    setAssetToPin(asset);
    setPinDialogOpen(true);
  };

  const handleOpenDuplicateFinder = (asset) => {
    setDuplicateFinderAsset(asset);
    setDuplicateFinderOpen(true);
  };

  const handleOpenAiAnalysis = (asset) => {
    setAiAnalysisAsset(asset);
    setAiAnalysisOpen(true);
  };

  const handleNavigate = (folderId) => {
    setCurrentId(folderId);
    // Reset filters when navigating into a different folder
    setPage(1);
    const url = buildFilterUrl(folderId, { query, typeFilters, statusFilters, sort, perPage, page: 1 });
    window.history.pushState({ folderId }, '', url);
  };

  // Keep URL in sync when filters change (replace, not push, to avoid polluting history).
  // Preserves the open asset's id in `?id=` so deep-links (from search, the
  // Duplicate Manager, or the global search bar) aren't wiped out by this
  // effect the moment the shell mounts.
  useEffect(() => {
    if (viewMode !== 'active') return;
    // Don't touch the URL until the initial deep-link (e.g. /assets?id=UUID
    // from search or the Duplicate Manager) has had a chance to resolve —
    // otherwise this effect fires on mount (before the async asset fetch
    // below completes) and strips `?id=` before it's ever used.
    if (initialTargetAssetId && !deepLinkProcessed.current) return;
    const assetId = selectedAsset?.uuid || selectedAsset?.id || null;
    const url = buildFilterUrl(currentId, { query, typeFilters, statusFilters, sort, perPage, page, assetId });
    window.history.replaceState({ folderId: currentId, assetId }, '', url);
  }, [currentId, query, typeFilters, statusFilters, sort, perPage, page, viewMode, selectedAsset, initialTargetAssetId]);

  useEffect(() => {
    const handlePopState = () => {
      const f = readUrlFilters();
      setCurrentId(f.folderId);
      setQuery(f.query);
      setTypeFilters(f.typeFilters);
      setStatusFilters(f.statusFilters);
      setSort(f.sort);
      setPerPage(f.perPage);
      setPage(f.page);
      // Close the AssetViewer when the back/forward navigation lands on a URL
      // with no `?id=` param; re-opening a specific asset via back/forward is
      // handled by the initial-deep-link effect re-running when needed.
      if (!f.assetId) setSelectedAsset(null);
    };
    window.addEventListener('popstate', handlePopState);
    return () => window.removeEventListener('popstate', handlePopState);
  }, []);

  const loadContent = useCallback(() => {
    const sortQuery = `sort=${sort.field}&direction=${sort.direction}`;
    const endpoint = viewMode === 'bin'
      ? '/api/v1/bin'
      : `/api/v1/folders/${encodeURIComponent(currentId)}?${sortQuery}`;

    fetch(endpoint)
      .then((response) => response.json())
      .then((data) => {
        setViewData(data);
        setSelectedItems({ folders: [], assets: [] });
      });
  }, [currentId, viewMode, sort]);

  useEffect(() => { loadContent(); }, [loadContent]);

  useEffect(() => {
    if (!initialTargetAssetId || deepLinkProcessed.current) return;

    const inView = viewData.assets?.find(
      (asset) => asset.id === initialTargetAssetId || asset.uuid === initialTargetAssetId
    );
    if (inView) {
      setSelectedAsset(inView);
      deepLinkProcessed.current = true;
      setDeepLinkLoading(false);
      return;
    }

    fetch(`/api/v1/assets/${initialTargetAssetId}`)
      .then((response) => {
        if (!response.ok) throw new Error(t('folders.explorer.assetNotFound', { status: response.status }));
        return response.json();
      })
      .then((data) => {
        setSelectedAsset(data);
        deepLinkProcessed.current = true;
      })
      .catch((error) => {
        notify(t('folders.explorer.couldNotOpenAsset', { message: error.message }), 'error');
        deepLinkProcessed.current = true;
      })
      .finally(() => setDeepLinkLoading(false));
  }, [initialTargetAssetId, notify, t, viewData.assets]);

  const handleCopyPath = () => {
    navigator.clipboard.writeText(window.location.href)
      .then(() => notify(t('folders.explorer.folderLocationCopiedToClipboard'), 'success'))
      .catch(() => notify(t('folders.explorer.failedToCopyLink'), 'error'));
  };

  const handleShareLink = () => {
    navigator.clipboard.writeText(window.location.href)
      .then(() => notify(t('folders.explorer.shareableLinkCopiedToClipboard'), 'success'))
      .catch(() => notify(t('folders.explorer.failedToCopyLink'), 'error'));
  };

  const handleRestoreSelected = async () => {
    const headers = requestHeaders();
    const assetPromises = selectedItems.assets.map((id) => fetch(`/api/v1/assets/${id}/restore`, { method: 'POST', headers }));
    const folderPromises = selectedItems.folders.map((id) => fetch(`/api/v1/folders/${id}/restore`, { method: 'POST', headers }));
    await Promise.all([...assetPromises, ...folderPromises]);
    loadContent();
  };

  const handlePermanentDelete = async () => {
    if (!window.confirm(t('folders.explorer.permanentDeleteWarning'))) return;
    const headers = requestHeaders();
    const assetPromises = selectedItems.assets.map((id) => fetch(`/api/v1/assets/${id}/permanent`, { method: 'DELETE', headers }));
    const folderPromises = selectedItems.folders.map((id) => fetch(`/api/v1/folders/${id}/permanent`, { method: 'DELETE', headers }));
    await Promise.all([...assetPromises, ...folderPromises]);
    loadContent();
  };

  const handleDeleteSelected = async () => {
    const totalCount = selectedItems.folders.length + selectedItems.assets.length;
    if (!window.confirm(t('folders.explorer.deleteSelectedConfirm', { count: totalCount }))) return;

    try {
      const headers = requestHeaders();
      const assetPromises = selectedItems.assets.map((id) => fetch(`/api/v1/assets/${id}`, { method: 'DELETE', headers }));
      const folderPromises = selectedItems.folders.map((id) => fetch(`/api/v1/folders/${id}`, { method: 'DELETE', headers }));
      await Promise.all([...assetPromises, ...folderPromises]);
      loadContent();
    } catch {
      notify(t('folders.explorer.deletionError'), 'error');
    }
  };

  // Publish/Unpublish is asset-only (see Api::V1::AssetsController#publish/
  // #unpublish) — the "Manage Publish" menu is only offered for an
  // all-assets selection, so `selectedItems.assets` is the whole set here.
  // Immediate actions (as opposed to "…Later", which opens PublishDialog to
  // pick a schedule) fire straight away, mirroring handleDeleteSelected.
  const handlePublishSelected = async () => {
    try {
      const headers = requestHeaders();
      const responses = await Promise.all(
        selectedItems.assets.map((id) => fetch(`/api/v1/assets/${id}/publish`, { method: 'POST', headers }))
      );
      const failed = responses.filter((r) => !r.ok).length;
      if (failed > 0) {
        notify(t('publishDialog.someItemsFailed', { count: failed }), 'warning');
      } else {
        notify(t('publishDialog.publishedNow', { count: selectedItems.assets.length }), 'success');
      }
      loadContent();
    } catch {
      notify(t('publishDialog.scheduleError'), 'error');
    }
  };

  const handleUnpublishSelected = async () => {
    try {
      const headers = requestHeaders();
      const responses = await Promise.all(
        selectedItems.assets.map((id) => fetch(`/api/v1/assets/${id}/unpublish`, { method: 'POST', headers }))
      );
      const failed = responses.filter((r) => !r.ok).length;
      if (failed > 0) {
        notify(t('publishDialog.someItemsFailed', { count: failed }), 'warning');
      } else {
        notify(t('publishDialog.unpublishedNow', { count: selectedItems.assets.length }), 'success');
      }
      loadContent();
    } catch {
      notify(t('publishDialog.scheduleError'), 'error');
    }
  };

  const toggleSelection = (type, id, event) => {
    event.stopPropagation();
    setSelectedItems((previous) => {
      const list = previous[type];
      return list.includes(id)
        ? { ...previous, [type]: list.filter((itemId) => itemId !== id) }
        : { ...previous, [type]: [...list, id] };
    });
  };

  const handleCreateFolder = async () => {
    const response = await fetch('/api/v1/folders', {
      method: 'POST',
      headers: requestHeaders(),
      body: JSON.stringify({ folder: { name: newFolderName, parent_id: currentId === 'root' ? null : currentId } })
    });
    if (response.ok) {
      setOpenFolderDialog(false);
      setNewFolderName('');
      loadContent();
    }
  };

  const handleFileUpload = async (event) => {
    const file = event.target.files[0];
    if (!file) return;
    const formData = new FormData();
    formData.append('file', file);
    formData.append('title', file.name);
    formData.append('folder_id', currentId === 'root' ? '' : currentId);

    try {
      const response = await fetch('/api/v1/assets', {
        method: 'POST',
        headers: { Accept: 'application/json', 'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content || '' },
        body: formData
      });
      if (response.ok) loadContent();
    } catch {
      notify(t('folders.explorer.uploadFailed'), 'error');
    } finally {
      event.target.value = null;
    }
  };

  const filteredFolders = useMemo(() => {
    const folders = viewData.folders || [];
    if (viewMode !== 'active') return folders;

    // If type filters are set and 'folders' is not among them, hide all folders
    if (typeFilters.length > 0 && !typeFilters.includes('folders')) return [];

    return folders.filter((folder) => !query || matchesQuery(folder.name || '', query));
  }, [query, typeFilters, viewData.folders, viewMode]);

  const filteredAssets = useMemo(() => {
    const assets = viewData.assets || [];
    if (viewMode !== 'active') return assets;

    return assets.filter((asset) => {
      const contentType = asset.content_type || asset.properties?.content_type || '';
      const title = asset.name || asset.title || '';
      const normalizedStatus = asset.status === 'ready' ? 'published' : asset.status;

      // Type filter:
      // - No type filters active → show all assets
      // - Only 'folders' selected → hide all assets (user wants folders only)
      // - Asset type keys selected → show matching assets
      const assetTypeFilters = typeFilters.filter((k) => k !== 'folders');
      let matchesType;
      if (typeFilters.length === 0) {
        matchesType = true; // no filter
      } else if (assetTypeFilters.length === 0) {
        matchesType = false; // only 'folders' selected → hide assets
      } else {
        matchesType = assetTypeFilters.some((key) => {
          switch (key) {
            case 'images':    return contentType.startsWith('image/');
            case 'videos':    return contentType.startsWith('video/');
            case 'documents': return isDocumentType(contentType);
            case 'audio':     return contentType.startsWith('audio/');
            default:          return true;
          }
        });
      }

      const matchesStatus = statusFilters.length === 0 || statusFilters.includes(normalizedStatus);
      const matchesSearch = !query || matchesQuery(title, query);

      return matchesType && matchesStatus && matchesSearch;
    });
  }, [query, statusFilters, typeFilters, viewData.assets, viewMode]);

  // Reset to page 1 whenever filters change
  const resetPage = () => setPage(1);

  const handleTypeFiltersChange = (val) => { setTypeFilters(val); resetPage(); };
  const handleStatusFiltersChange = (val) => { setStatusFilters(val); resetPage(); };
  const handleQueryChange = (val) => { setQuery(val); resetPage(); };
  const handlePerPageChange = (val) => { setPerPage(val); resetPage(); };

  // Pagination — combine folders + assets into a single virtual list, page them together
  const allItems = useMemo(() => [
    ...filteredFolders.map((f) => ({ kind: 'folder', data: f })),
    ...filteredAssets.map((a) => ({ kind: 'asset', data: a })),
  ], [filteredFolders, filteredAssets]);

  const totalPages = Math.max(1, Math.ceil(allItems.length / perPage));
  const safePage = Math.min(page, totalPages);
  const pagedItems = allItems.slice((safePage - 1) * perPage, safePage * perPage);

  const visibleFolders = pagedItems.filter((i) => i.kind === 'folder').map((i) => i.data);
  const visibleAssets  = pagedItems.filter((i) => i.kind === 'asset').map((i) => i.data);

  const isAllSelected = (visibleFolders.length > 0 || visibleAssets.length > 0)
    && visibleFolders.every((folder) => selectedItems.folders.includes(folder.id))
    && visibleAssets.every((asset) => selectedItems.assets.includes(asset.id));

  // Toggles between select-all and deselect-all — previously this always
  // (re-)selected everything, so unchecking "Select All" after checking it
  // had no effect (bug: the checkbox visually unchecked but the selection
  // itself never cleared, since nothing here read `isAllSelected`).
  const handleSelectAll = () => {
    if (isAllSelected) {
      handleDeselectAll();
    } else {
      setSelectedItems({
        folders: visibleFolders.map((folder) => folder.id),
        assets: visibleAssets.map((asset) => asset.id),
      });
    }
  };

  const handleDeselectAll = () => {
    setSelectedItems({ folders: [], assets: [] });
  };

  const hasSelection = selectedItems.folders.length > 0 || selectedItems.assets.length > 0;

  return (
    <Box sx={{ width: '100%', p: 4, bgcolor: '#f8fafc', minHeight: '100vh' }}>
      <ExplorerTopBar
        pageTitle={pageTitle}
        currentId={currentId}
        viewData={viewData}
        viewMode={viewMode}
        setViewMode={setViewMode}
        handleNavigate={handleNavigate}
        handleCopyPath={handleCopyPath}
        isAllSelected={isAllSelected}
        handleSelectAll={handleSelectAll}
        hasSelection={hasSelection}
        handleDeleteSelected={handleDeleteSelected}
        handleRestoreSelected={handleRestoreSelected}
        handlePermanentDelete={handlePermanentDelete}
        handlePublishSelected={handlePublishSelected}
        handleUnpublishSelected={handleUnpublishSelected}
        setOpenFolderDialog={setOpenFolderDialog}
        handleFileUpload={handleFileUpload}
        selectedItems={selectedItems}
        onSchemaApplied={() => loadContent()}
        onUploadSuccess={() => loadContent()}
      />

      {viewMode === 'active' && (
        <AssetFilterBar
          query={query}
          onQueryChange={handleQueryChange}
          typeFilters={typeFilters}
          onTypeFiltersChange={handleTypeFiltersChange}
          statusFilters={statusFilters}
          onStatusFiltersChange={handleStatusFiltersChange}
          sort={sort}
          onSortChange={setSort}
          viewLayout={viewLayout}
          onViewLayoutChange={setViewLayout}
          gridSize={gridSize}
          onGridSizeChange={setGridSize}
          resultCount={allItems.length}
          perPage={perPage}
          onPerPageChange={handlePerPageChange}
          onShareLink={handleShareLink}
        />
      )}

      <FolderGrid
        folders={visibleFolders}
        viewMode={viewMode}
        selectedItems={selectedItems}
        toggleSelection={toggleSelection}
        handleNavigate={handleNavigate}
        onFolderInfo={handleFolderInfo}
        gridSize={gridSize}
      />

      {visibleFolders.length > 0 && visibleAssets.length > 0 && <Divider sx={{ my: 4, borderColor: '#e2e8f0' }} />}

      {visibleAssets.length > 0 && (
        <Box>
          <Typography variant="subtitle2" sx={{ fontWeight: 700, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.05em', mb: 2 }}>
            {t('folders.explorer.mediaFiles')}
          </Typography>

          {viewLayout === 'grid' ? (
            <AssetGrid
              assets={visibleAssets}
              viewMode={viewMode}
              selectedItems={selectedItems}
              toggleSelection={toggleSelection}
              setSelectedAsset={setSelectedAsset}
              onPinClick={handlePinClick}
              onFindDuplicates={handleOpenDuplicateFinder}
              onAiAnalysis={handleOpenAiAnalysis}
              gridSize={gridSize}
            />
          ) : (
            <AssetList
              assets={visibleAssets}
              viewMode={viewMode}
              selectedItems={selectedItems}
              toggleSelection={toggleSelection}
              setSelectedAsset={setSelectedAsset}
              onPinClick={handlePinClick}
            />
          )}
        </Box>
      )}

      {/* Pagination */}
      {totalPages > 1 && (
        <Box sx={{ display: 'flex', justifyContent: 'center', mt: 4, mb: 2 }}>
          <Pagination
            count={totalPages}
            page={safePage}
            onChange={(_, newPage) => setPage(newPage)}
            color="primary"
            shape="rounded"
            showFirstButton
            showLastButton
          />
        </Box>
      )}

      <Dialog open={openFolderDialog} onClose={() => setOpenFolderDialog(false)}>
        <DialogTitle>{t('folders.explorer.createNewFolder')}</DialogTitle>
        <DialogContent>
          <TextField autoFocus margin="dense" label={t('folders.explorer.folderName')} fullWidth variant="standard" value={newFolderName} onChange={(event) => setNewFolderName(event.target.value)} />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenFolderDialog(false)}>{t('common.cancel')}</Button>
          <Button onClick={handleCreateFolder} variant="contained" disabled={!newFolderName.trim()}>{t('common.create')}</Button>
        </DialogActions>
      </Dialog>

      <Backdrop
        open={deepLinkLoading}
        sx={{ color: '#fff', zIndex: (theme) => theme.zIndex.drawer + 1 }}
        data-testid="deep-link-loading-backdrop"
      >
        <CircularProgress color="inherit" />
      </Backdrop>

      <AssetViewer
        asset={selectedAsset}
        open={Boolean(selectedAsset)}
        onClose={() => setSelectedAsset(null)}
        onAssetUpdated={(updatedAsset) => {
          setSelectedAsset(updatedAsset);
          loadContent();
        }}
      />

      <PinToCollectionDialog
        open={pinDialogOpen}
        onClose={() => setPinDialogOpen(false)}
        asset={assetToPin}
      />

      <DuplicateFinderDialog
        open={duplicateFinderOpen}
        onClose={() => {
          setDuplicateFinderOpen(false);
          setDuplicateFinderAsset(null);
          loadContent();
        }}
        asset={duplicateFinderAsset}
      />

      <AiAnalysisDialog
        open={aiAnalysisOpen}
        onClose={() => {
          setAiAnalysisOpen(false);
          setAiAnalysisAsset(null);
          loadContent();
        }}
        asset={aiAnalysisAsset}
      />

      <FolderInfoPanel
        folder={infoFolder}
        open={infoPanelOpen}
        onClose={() => setInfoPanelOpen(false)}
        onFolderUpdated={(updated) => {
          loadContent();
          setInfoFolder((previous) => (previous ? { ...previous, ...updated } : previous));
        }}
      />
    </Box>
  );
}

function requestHeaders() {
  return {
    'Content-Type': 'application/json',
    'X-CSRF-Token': document.querySelector('[name="csrf-token"]')?.content || ''
  };
}
