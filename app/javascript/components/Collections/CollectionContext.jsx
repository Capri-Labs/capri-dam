import React, { createContext, useContext, useState, useCallback } from 'react';
import { useNotify } from '../../context/NotificationContext'; // Assuming this exists

const CollectionContext = createContext();

export function CollectionProvider({ children }) {
    const notify = useNotify();
    const [collections, setCollections] = useState([]);
    const [loadingCollections, setLoadingCollections] = useState(false);

    // Fetch all active collections for the Board
    const fetchCollections = useCallback(async () => {
        setLoadingCollections(true);
        try {
            const res = await fetch('/api/v1/collections');
            const data = await res.json();
            setCollections(data);
        } catch (error) {
            notify("Failed to load collections.", "error");
        } finally {
            setLoadingCollections(false);
        }
    }, [notify]);

    const createCollection = async (payload) => {
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch('/api/v1/collections', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ collection: payload })
            });
            const data = await res.json();

            if (res.ok) {
                notify("Collection created successfully.", "success");
                // Prepend the new collection to the board instantly
                setCollections(prev => [data, ...prev]);
                return data;
            } else {
                notify(data.errors?.join(", ") || "Creation failed", "error");
                return null;
            }
        } catch (error) {
            notify("Network error occurred.", "error");
            return null;
        }
    };

    const deleteCollection = async (slug) => {
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/collections/${slug}`, {
                method: 'DELETE',
                headers: { 'X-CSRF-Token': csrfToken }
            });
            if (res.ok) {
                notify("Workspace archived.", "success");
                // Remove from local state instantly
                setCollections(prev => prev.filter(c => c.slug !== slug));
                return true;
            }
            return false;
        } catch (error) {
            notify("Network error during deletion.", "error");
            return false;
        }
    };

    const bulkDeleteCollections = async (ids) => {
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch('/api/v1/collections/bulk_delete', {
                method: 'DELETE',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ ids })
            });
            const data = await res.json();

            if (res.ok) {
                notify(data.message, "success");
                // Filter out all deleted IDs
                setCollections(prev => prev.filter(c => !ids.includes(c.id)));
                return true;
            }
            return false;
        } catch (error) {
            notify("Network error during bulk deletion.", "error");
            return false;
        }
    };

    const purgeCdnCache = async (slug) => {
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/collections/${slug}/purge_cdn`, {
                method: 'POST',
                headers: { 'X-CSRF-Token': csrfToken }
            });
            const data = await res.json();
            if (res.ok) notify(data.message, "info");
        } catch (error) {
            notify("Failed to initiate CDN purge.", "error");
        }
    };

    // Update the Semantic AI Rule for a Smart Collection
    const updateSmartRule = async (slug, rulePayload) => {
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/collections/${slug}/rule`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify(rulePayload)
            });
            const data = await res.json();
            if (res.ok) {
                notify("Smart routing rules updated.", "success");
                return data.collection;
            } else {
                notify(data.errors?.join(", ") || "Update failed", "error");
                return null;
            }
        } catch (error) {
            notify("Network error occurred.", "error");
            return null;
        }
    };

    // Toggle the "Pin" status of an asset to prevent AI from removing it
    const toggleAssetPin = async (slug, assetId) => {
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/collections/${slug}/assets/${assetId}/pin`, {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken }
            });
            const data = await res.json();
            if (res.ok) {
                notify(data.message, "info");
                return data.pinned;
            }
            return null;
        } catch (error) {
            notify("Failed to pin asset.", "error");
            return null;
        }
    };

    const updateCollection = async (slug, payload) => {
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch(`/api/v1/collections/${slug}`, {
                method: 'PATCH', // or PUT
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ collection: payload })
            });
            const data = await res.json();
            if (res.ok) {
                notify("Workspace updated.", "success");
                // Update local state
                setCollections(prev => prev.map(c => c.slug === slug ? { ...c, ...data } : c));
                return true;
            } else {
                notify(data.errors?.join(", ") || "Update failed", "error");
                return false;
            }
        } catch (error) {
            notify("Network error during update.", "error");
            return false;
        }
    };

    const bulkUpdateCollections = async (ids, payload) => {
        try {
            const csrfToken = document.querySelector('[name="csrf-token"]').content;
            const res = await fetch('/api/v1/collections/bulk_update', {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken },
                body: JSON.stringify({ ids, collection: payload })
            });
            const data = await res.json();
            if (res.ok) {
                notify(data.message || "Workspaces updated.", "success");
                fetchCollections(); // Refresh the board to get new states
                return true;
            }
            return false;
        } catch (error) {
            notify("Network error during bulk update.", "error");
            return false;
        }
    };

    return (
        <CollectionContext.Provider value={{
            collections,
            loadingCollections,
            fetchCollections,
            updateSmartRule,
            toggleAssetPin,
            createCollection,
            deleteCollection,
            bulkDeleteCollections,
            purgeCdnCache,
            updateCollection, bulkUpdateCollections
        }}>
            {children}
        </CollectionContext.Provider>
    );
}

export const useCollections = () => useContext(CollectionContext);