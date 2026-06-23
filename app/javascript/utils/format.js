// Small, framework-agnostic helpers shared across the React screens.
// Kept pure so they are trivially unit-testable under Jest.

/**
 * Format a byte count into a human-readable string (e.g. 2048 -> "2 KB").
 * @param {number} bytes
 * @returns {string}
 */
export function humanFileSize(bytes) {
  if (bytes === null || bytes === undefined || Number.isNaN(bytes)) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i += 1;
  }
  return `${value.toFixed(value < 10 && i > 0 ? 1 : 0)} ${units[i]}`;
}

/**
 * Read the Rails CSRF token from the document head, if present.
 * @returns {string|undefined}
 */
export function csrfToken() {
  if (typeof document === 'undefined') return undefined;
  return document.querySelector('meta[name="csrf-token"]')?.content;
}

/**
 * Split a CSV header line into trimmed, de-quoted, non-empty column names.
 * @param {string} line
 * @param {string} separator
 * @returns {string[]}
 */
export function parseCsvHeader(line, separator = ',') {
  if (!line) return [];
  return line
    .split(separator)
    .map((c) => c.trim().replace(/^"|"$/g, ''))
    .filter(Boolean);
}

