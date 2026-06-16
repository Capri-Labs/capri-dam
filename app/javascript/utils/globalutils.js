import { Turbo } from "@hotwired/turbo-rails"

// Check environment
const isProduction = window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1';

/**
 * Global navigation helper that integrates seamlessly with Hotwire Turbo.
 * Falls back to standard window navigation if Turbo isn't initialized.
 * * @param {string} url - The target internal or external path
 * @param {object} options - Optional Turbo configuration (e.g., action: 'replace')
 */
export const navigateTo = (url, options = {}) => {
    if (!url) return;

    // Check if it's an external link or if Turbo isn't active
    if (url.startsWith('http') || !Turbo) {
        window.location.href = url;
    } else {
        // Keeps transitions ultra-fast without a full page white-flash reload
        Turbo.visit(url, options);
    }
};

/**
 * Returns the correct base URL for asset access.
 * Usage: getAssetUrl(asset.uuid)
 */
export const getAssetUrl = (uuid, params = "") => {
    if (isProduction) {
        return `https://cdn.yourdam.com/assets/${uuid}${params}`;
    }
    // In local dev, point to your Rails API's local serving endpoint
    return `/api/v1/assets/${uuid}/serve${params}`;
};

/**
 * Calculates the SHA-256 hash of a File object natively in the browser.
 * @param {File} file
 * @returns {Promise<string>} Hex string of the hash
 */
export const calculateFileHash = async (file) => {
    const buffer = await file.arrayBuffer();
    const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
};