/**
 * Region-scoped pixel comparison between two versions of an asset.
 *
 * WHAT THIS ANSWERS
 * -----------------
 * "Was this feedback actually addressed?" A reviewer draws a box around a logo
 * on v2 and says *make this bigger*. Someone uploads v3. Today the only way to
 * check is to eyeball both files. Because the annotation's bounding box is
 * stored **normalised** (0..1), it can be re-projected onto v3 and the pixels
 * inside just that region compared — turning an open question into a
 * "changed" / "unchanged" fact.
 *
 * WHY NORMALISED GEOMETRY MAKES THIS POSSIBLE AT ALL
 * --------------------------------------------------
 * The two versions frequently differ in pixel dimensions (a re-export at
 * another resolution, a different crop). A pixel bounding box captured on v2
 * would point at the wrong place on v3. A 0..1 box points at the same
 * *proportional* region of both, so each crop is taken at its own version's
 * native resolution and only then resampled onto a common raster for
 * comparison. This is the payoff of the storage decision documented in
 * AnnotationTarget.
 *
 * This runs on the client, reusing the canvas approach `AssetVersionsTab.jsx`
 * already uses for whole-image diffing, so no new server-side image pipeline
 * is needed.
 */

/**
 * Per-channel delta above which a pixel counts as changed. Matches
 * AssetVersionsTab's whole-image diff so the two features never disagree about
 * what "different" means. Set well above zero to absorb JPEG re-compression
 * noise, which would otherwise mark every re-exported file as changed.
 */
export const DIFF_THRESHOLD = 72;

/**
 * Fraction of a region's pixels that must change before the region is called
 * changed. A handful of stray pixels is re-compression, not a design edit;
 * 2% is roughly "something visible happened here".
 */
export const CHANGED_RATIO_THRESHOLD = 0.02;

/**
 * Edge length the two crops are resampled to before comparison. Fixed so the
 * cost of comparing a region is constant regardless of source resolution — a
 * 6000px-wide master would otherwise make this unusably slow — and so that two
 * differently-sized versions are compared like for like.
 */
export const COMPARISON_RASTER = 96;

/**
 * Minimum normalised size given to a zero-area annotation. A pin marks a point
 * and has no width or height, so there would be nothing to compare; it is
 * treated as a small neighbourhood around the point instead.
 */
export const MIN_REGION_SIZE = 0.06;

const isCrossOriginUrl = (url) => {
    try {
        return new URL(url, window.location.origin).origin !== window.location.origin;
    } catch {
        return false;
    }
};

/** True when a canvas read failed because the bitmap is cross-origin tainted. */
export const isCanvasSecurityError = (error) => error?.name === 'SecurityError'
    || /cross-origin|tainted|insecure/i.test(error?.message || '');

/**
 * Loads an image for canvas use.
 *
 * `crossOrigin` is set only for genuinely cross-origin URLs. Setting it
 * unconditionally makes the browser omit session cookies, so a same-origin,
 * cookie-authenticated preview URL would 401 and silently fail to load — the
 * same trap `AssetVersionsTab.jsx` documents.
 *
 * @param {string} url
 * @returns {Promise<HTMLImageElement>}
 */
export function loadImage(url) {
    return new Promise((resolve, reject) => {
        if (!url) {
            reject(new Error('No preview URL'));
            return;
        }

        const image = new Image();
        if (!url.startsWith('data:') && isCrossOriginUrl(url)) {
            image.crossOrigin = 'anonymous';
        }
        image.onload = () => resolve(image);
        image.onerror = () => reject(new Error(`Failed to load image: ${url}`));
        image.src = url;
    });
}

/**
 * Expands a normalised bbox to at least {@link MIN_REGION_SIZE}, keeping it
 * centred and inside the 0..1 bounds.
 *
 * @param {{x:number,y:number,w:number,h:number}} bbox
 * @param {number} [minimum]
 * @returns {{x:number,y:number,w:number,h:number}}
 */
export function expandRegion(bbox, minimum = MIN_REGION_SIZE) {
    const source = bbox || {};
    const grow = (start, length) => {
        const size = Math.min(1, Math.max(length || 0, minimum));
        // Centre the enlarged box on the original, then slide it back inside
        // the frame if that pushed it over an edge.
        const centre = (start || 0) + (length || 0) / 2;
        const origin = Math.min(Math.max(centre - size / 2, 0), 1 - size);
        return [origin, size];
    };

    const [x, w] = grow(source.x, source.w);
    const [y, h] = grow(source.y, source.h);

    return { x, y, w, h };
}

/**
 * Draws the normalised region of an image onto a canvas of the given size.
 *
 * The source rectangle is computed from *this* image's own dimensions, which
 * is what lets two differently-sized versions be compared.
 *
 * @param {HTMLImageElement|HTMLCanvasElement} image
 * @param {{x:number,y:number,w:number,h:number}} region normalised
 * @param {number} size output edge length in pixels
 * @returns {HTMLCanvasElement}
 */
export function cropRegion(image, region, size = COMPARISON_RASTER) {
    const sourceWidth = image.naturalWidth || image.width;
    const sourceHeight = image.naturalHeight || image.height;

    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;

    const context = canvas.getContext('2d');
    if (!context) throw new Error('Canvas 2D context unavailable');

    // At least one pixel each way: a degenerate source rect makes drawImage
    // throw rather than produce an empty crop.
    const sx = Math.max(0, Math.min(region.x * sourceWidth, sourceWidth - 1));
    const sy = Math.max(0, Math.min(region.y * sourceHeight, sourceHeight - 1));
    const sw = Math.max(1, Math.min(region.w * sourceWidth, sourceWidth - sx));
    const sh = Math.max(1, Math.min(region.h * sourceHeight, sourceHeight - sy));

    context.drawImage(image, sx, sy, sw, sh, 0, 0, size, size);
    return canvas;
}

/**
 * Fraction of pixels that differ between two equally-sized canvases.
 *
 * @param {HTMLCanvasElement} before
 * @param {HTMLCanvasElement} after
 * @returns {number} 0..1
 * @throws {Error} when either canvas is cross-origin tainted
 */
export function changedPixelRatio(before, after) {
    const width = before.width;
    const height = before.height;

    const beforeData = before.getContext('2d').getImageData(0, 0, width, height).data;
    const afterData = after.getContext('2d').getImageData(0, 0, width, height).data;

    let changed = 0;
    const total = width * height;

    for (let i = 0; i < beforeData.length; i += 4) {
        const delta = Math.abs(beforeData[i] - afterData[i])
            + Math.abs(beforeData[i + 1] - afterData[i + 1])
            + Math.abs(beforeData[i + 2] - afterData[i + 2])
            + Math.abs(beforeData[i + 3] - afterData[i + 3]);

        if (delta > DIFF_THRESHOLD) changed += 1;
    }

    return total === 0 ? 0 : changed / total;
}

/**
 * Renders a display crop of a region, wide enough to give the reviewer
 * context, as a data URL.
 *
 * Aspect ratio is preserved here (unlike the square comparison raster, which
 * only ever feeds arithmetic) because this one is actually looked at.
 *
 * @param {HTMLImageElement} image
 * @param {{x:number,y:number,w:number,h:number}} region normalised
 * @param {number} [maxEdge]
 * @returns {string|null} data URL, or null if the canvas is tainted
 */
export function regionDataUrl(image, region, maxEdge = 240) {
    const sourceWidth = image.naturalWidth || image.width;
    const sourceHeight = image.naturalHeight || image.height;

    const sw = Math.max(1, region.w * sourceWidth);
    const sh = Math.max(1, region.h * sourceHeight);
    const scale = Math.min(maxEdge / sw, maxEdge / sh, 1);

    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(sw * scale));
    canvas.height = Math.max(1, Math.round(sh * scale));

    const context = canvas.getContext('2d');
    if (!context) return null;

    context.drawImage(
        image,
        Math.max(0, region.x * sourceWidth),
        Math.max(0, region.y * sourceHeight),
        sw,
        sh,
        0, 0, canvas.width, canvas.height,
    );

    try {
        return canvas.toDataURL('image/png');
    } catch (error) {
        // Tainted canvas — the caller falls back to "unavailable".
        if (isCanvasSecurityError(error)) return null;
        throw error;
    }
}

/**
 * Compares one normalised region across two loaded images.
 *
 * @param {HTMLImageElement} beforeImage
 * @param {HTMLImageElement} afterImage
 * @param {{x:number,y:number,w:number,h:number}} bbox normalised
 * @returns {{status: 'changed'|'unchanged', ratio: number, region: object}}
 */
export function compareRegion(beforeImage, afterImage, bbox) {
    const region = expandRegion(bbox);
    const ratio = changedPixelRatio(
        cropRegion(beforeImage, region),
        cropRegion(afterImage, region),
    );

    return {
        status: ratio > CHANGED_RATIO_THRESHOLD ? 'changed' : 'unchanged',
        ratio,
        region,
    };
}

/**
 * Creates a loader that fetches each preview URL at most once.
 *
 * A thread list routinely holds a dozen annotations against the same pair of
 * versions. Without this, each one would re-download and re-decode the same
 * two previews — the difference between two image loads and twenty-four.
 *
 * @returns {(url: string) => Promise<HTMLImageElement>}
 */
export function createImageCache() {
    const cache = new Map();

    return (url) => {
        if (!cache.has(url)) {
            // The *promise* is cached, not the resolved image, so concurrent
            // callers during the initial load share one request too.
            cache.set(url, loadImage(url));
        }
        return cache.get(url);
    };
}
