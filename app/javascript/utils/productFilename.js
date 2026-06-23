/**
 * Parses a product asset filename using the DAM naming convention:
 *   ProductID-LanguageCode-AssetTypeCode.(ext)
 *   e.g.  012993112028-en-FR01.jpg
 *
 * @param {string} filename
 * @returns {{ productId, langCode, assetTypeCode, isProductNaming } | null}
 */
export function parseProductFilename(filename) {
    if (!filename) return null;
    const withoutExt = filename.replace(/\.[^/.]+$/, '');
    const parts      = withoutExt.split('-');

    // Need at least 3 parts: productId - lang - assetType
    if (parts.length < 3) return null;

    const assetTypeCode = parts[parts.length - 1];
    const langCode      = parts[parts.length - 2];
    const productId     = parts.slice(0, parts.length - 2).join('-');

    // Asset type code must match e.g. FR01, BK02, SD01, TQ01, TP01, DT03
    const isProductNaming = /^[A-Z]{2}\d{2}$/.test(assetTypeCode);

    return { productId, langCode, assetTypeCode, isProductNaming };
}

/**
 * Returns a human-readable description for a view-angle prefix.
 */
const ANGLE_DESCRIPTIONS = {
    FR: 'Front',
    BK: 'Back',
    SD: 'Side / Profile',
    TQ: 'Three-Quarter / 45°',
    TP: 'Top-Down / Flat Lay',
    DT: 'Detail / Macro Shot'
};

export function getAngleDescription(assetTypeCode) {
    if (!assetTypeCode) return '';
    const prefix = assetTypeCode.substring(0, 2).toUpperCase();
    return ANGLE_DESCRIPTIONS[prefix] ?? prefix;
}

/**
 * Determines the default schema slug for a given MIME type.
 * Returns 'product-images' for images, 'default' for everything else.
 */
export function defaultSchemaSlugForMime(mimeType) {
    if (!mimeType) return 'default';
    if (mimeType.startsWith('image/')) return 'product-images';
    return 'default';
}

