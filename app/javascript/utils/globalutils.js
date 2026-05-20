import { Turbo } from "@hotwired/turbo-rails"

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