import {
    CHANGED_RATIO_THRESHOLD,
    COMPARISON_RASTER,
    DIFF_THRESHOLD,
    MIN_REGION_SIZE,
    changedPixelRatio,
    compareRegion,
    createImageCache,
    cropRegion,
    expandRegion,
    isCanvasSecurityError,
    regionDataUrl,
} from '../../../app/javascript/utils/regionDiff';

/**
 * jsdom implements no canvas rendering at all, and `jest-canvas-mock` is not a
 * dependency here. Rather than add one, this harness fakes just enough of the
 * 2D context to exercise the real geometry: a "image" carries a function that
 * returns a pixel for a source coordinate, and `getImageData` samples it
 * through whatever source rectangle `drawImage` was given. That means the
 * region-mapping arithmetic under test is genuinely executed, not stubbed out.
 */
function fakeImage({ width, height, pixelAt }) {
    return { naturalWidth: width, naturalHeight: height, width, height, pixelAt };
}

function installCanvasHarness() {
    const canvases = [];
    const original = document.createElement.bind(document);

    jest.spyOn(document, 'createElement').mockImplementation((tag, ...rest) => {
        if (tag !== 'canvas') return original(tag, ...rest);

        const canvas = {
            width: 0,
            height: 0,
            _drawn: null,
            toDataURL: () => 'data:image/png;base64,STUB',
            getContext: () => ({
                drawImage: (image, sx, sy, sw, sh, dx, dy, dw, dh) => {
                    canvas._drawn = { image, sx, sy, sw, sh, dw, dh };
                },
                getImageData: (_x, _y, w, h) => {
                    const data = new Uint8ClampedArray(w * h * 4);
                    const drawn = canvas._drawn;

                    for (let py = 0; py < h; py += 1) {
                        for (let px = 0; px < w; px += 1) {
                            // Map the destination pixel back through the
                            // source rectangle drawImage was called with.
                            const sourceX = drawn.sx + ((px + 0.5) / w) * drawn.sw;
                            const sourceY = drawn.sy + ((py + 0.5) / h) * drawn.sh;
                            const [r, g, b, a] = drawn.image.pixelAt(sourceX, sourceY);
                            const index = (py * w + px) * 4;
                            data[index] = r;
                            data[index + 1] = g;
                            data[index + 2] = b;
                            data[index + 3] = a;
                        }
                    }
                    return { data, width: w, height: h };
                },
                createImageData: (w, h) => ({ data: new Uint8ClampedArray(w * h * 4), width: w, height: h }),
                clearRect: () => {},
                putImageData: () => {},
            }),
        };
        canvases.push(canvas);
        return canvas;
    });

    return canvases;
}

const WHITE = [255, 255, 255, 255];
const BLACK = [0, 0, 0, 255];

afterEach(() => {
    jest.restoreAllMocks();
});

describe('expandRegion', () => {
    it('leaves a region that is already big enough alone', () => {
        const region = expandRegion({ x: 0.2, y: 0.2, w: 0.4, h: 0.3 });

        // Re-centring round-trips through floating point, so compare loosely.
        expect(region.x).toBeCloseTo(0.2, 10);
        expect(region.y).toBeCloseTo(0.2, 10);
        expect(region.w).toBeCloseTo(0.4, 10);
        expect(region.h).toBeCloseTo(0.3, 10);
    });

    it('gives a zero-area pin a neighbourhood to compare', () => {
        // A pin has no width or height, so there would be nothing to diff.
        const region = expandRegion({ x: 0.5, y: 0.5, w: 0, h: 0 });

        expect(region.w).toBe(MIN_REGION_SIZE);
        expect(region.h).toBe(MIN_REGION_SIZE);
    });

    it('keeps the expanded region centred on the original point', () => {
        const region = expandRegion({ x: 0.5, y: 0.5, w: 0, h: 0 });

        expect(region.x + region.w / 2).toBeCloseTo(0.5, 6);
        expect(region.y + region.h / 2).toBeCloseTo(0.5, 6);
    });

    it('slides the region back inside the frame at the edges', () => {
        const topLeft = expandRegion({ x: 0, y: 0, w: 0, h: 0 });
        expect(topLeft.x).toBe(0);
        expect(topLeft.y).toBe(0);

        const bottomRight = expandRegion({ x: 1, y: 1, w: 0, h: 0 });
        expect(bottomRight.x + bottomRight.w).toBeCloseTo(1, 6);
        expect(bottomRight.y + bottomRight.h).toBeCloseTo(1, 6);
    });

    it('never produces a region larger than the frame', () => {
        const region = expandRegion({ x: 0, y: 0, w: 2, h: 2 });
        expect(region.w).toBeLessThanOrEqual(1);
        expect(region.h).toBeLessThanOrEqual(1);
    });

    it('tolerates a missing bbox', () => {
        expect(expandRegion(null).w).toBe(MIN_REGION_SIZE);
    });
});

describe('cropRegion', () => {
    beforeEach(installCanvasHarness);

    it('maps a normalised region onto the image own pixel dimensions', () => {
        const image = fakeImage({ width: 1000, height: 500, pixelAt: () => WHITE });
        const canvas = cropRegion(image, { x: 0.1, y: 0.2, w: 0.5, h: 0.25 });

        expect(canvas._drawn).toMatchObject({ sx: 100, sy: 100, sw: 500, sh: 125 });
    });

    it('resamples onto a fixed raster so cost does not scale with resolution', () => {
        const image = fakeImage({ width: 6000, height: 4000, pixelAt: () => WHITE });
        const canvas = cropRegion(image, { x: 0, y: 0, w: 1, h: 1 });

        expect(canvas.width).toBe(COMPARISON_RASTER);
        expect(canvas.height).toBe(COMPARISON_RASTER);
    });

    it('locates the same proportional region on differently sized versions', () => {
        // This is the whole point of storing geometry normalised: a pixel box
        // captured on the small version would miss on the large one.
        const region = { x: 0.25, y: 0.25, w: 0.5, h: 0.5 };
        const small = cropRegion(fakeImage({ width: 400, height: 400, pixelAt: () => WHITE }), region);
        const large = cropRegion(fakeImage({ width: 4000, height: 4000, pixelAt: () => WHITE }), region);

        expect(small._drawn).toMatchObject({ sx: 100, sy: 100, sw: 200, sh: 200 });
        expect(large._drawn).toMatchObject({ sx: 1000, sy: 1000, sw: 2000, sh: 2000 });
    });

    it('never produces a degenerate source rectangle', () => {
        // drawImage throws on a zero-width source rect.
        const image = fakeImage({ width: 100, height: 100, pixelAt: () => WHITE });
        const canvas = cropRegion(image, { x: 1, y: 1, w: 0, h: 0 });

        expect(canvas._drawn.sw).toBeGreaterThanOrEqual(1);
        expect(canvas._drawn.sh).toBeGreaterThanOrEqual(1);
    });
});

describe('changedPixelRatio', () => {
    beforeEach(installCanvasHarness);

    const cropOf = (pixelAt) => cropRegion(
        fakeImage({ width: 100, height: 100, pixelAt }),
        { x: 0, y: 0, w: 1, h: 1 },
    );

    it('reports zero for identical regions', () => {
        expect(changedPixelRatio(cropOf(() => WHITE), cropOf(() => WHITE))).toBe(0);
    });

    it('reports one when every pixel differs', () => {
        expect(changedPixelRatio(cropOf(() => WHITE), cropOf(() => BLACK))).toBe(1);
    });

    it('ignores differences below the threshold, so re-compression is not a change', () => {
        const nudge = Math.floor(DIFF_THRESHOLD / 4) - 1;
        const noisy = () => [255 - nudge, 255 - nudge, 255 - nudge, 255];

        expect(changedPixelRatio(cropOf(() => WHITE), cropOf(noisy))).toBe(0);
    });

    it('counts a partially changed region proportionally', () => {
        // Left half turns black.
        const half = (x) => (x < 50 ? BLACK : WHITE);

        expect(changedPixelRatio(cropOf(() => WHITE), cropOf(half))).toBeCloseTo(0.5, 1);
    });
});

describe('compareRegion', () => {
    beforeEach(installCanvasHarness);

    const region = { x: 0.25, y: 0.25, w: 0.5, h: 0.5 };

    it('calls an edited region changed', () => {
        const before = fakeImage({ width: 200, height: 200, pixelAt: () => WHITE });
        const after = fakeImage({ width: 200, height: 200, pixelAt: () => BLACK });

        const result = compareRegion(before, after, region);
        expect(result.status).toBe('changed');
        expect(result.ratio).toBe(1);
    });

    it('calls an untouched region unchanged', () => {
        const image = () => fakeImage({ width: 200, height: 200, pixelAt: () => WHITE });

        expect(compareRegion(image(), image(), region).status).toBe('unchanged');
    });

    it('ignores an edit that happened outside the annotated region', () => {
        // The point of a region-scoped diff: a change elsewhere in the image
        // must not be reported against this thread.
        const before = fakeImage({ width: 200, height: 200, pixelAt: () => WHITE });
        const after = fakeImage({
            width: 200,
            height: 200,
            // Only the far-left strip changes; the region starts at x = 50.
            pixelAt: (x) => (x < 20 ? BLACK : WHITE),
        });

        expect(compareRegion(before, after, region).status).toBe('unchanged');
    });

    it('detects an edit confined to the annotated region', () => {
        const before = fakeImage({ width: 200, height: 200, pixelAt: () => WHITE });
        const after = fakeImage({
            width: 200,
            height: 200,
            pixelAt: (x, y) => ((x >= 50 && x < 150 && y >= 50 && y < 150) ? BLACK : WHITE),
        });

        expect(compareRegion(before, after, region).status).toBe('changed');
    });

    it('compares correctly when the versions differ in resolution', () => {
        const before = fakeImage({ width: 400, height: 400, pixelAt: () => WHITE });
        // Same content, exported at 4x — a pixel-space box would misalign.
        const after = fakeImage({ width: 1600, height: 1600, pixelAt: () => WHITE });

        expect(compareRegion(before, after, region).status).toBe('unchanged');
    });

    it('stays below the changed threshold for trivial pixel noise', () => {
        const before = fakeImage({ width: 200, height: 200, pixelAt: () => WHITE });
        const after = fakeImage({
            width: 200,
            height: 200,
            // About one raster row's worth of the crop — roughly 1%, under
            // CHANGED_RATIO_THRESHOLD, so it must not be called changed.
            pixelAt: (_x, y) => (y >= 100 && y < 101.5 ? BLACK : WHITE),
        });

        const result = compareRegion(before, after, region);
        expect(result.ratio).toBeGreaterThan(0);
        expect(result.ratio).toBeLessThan(CHANGED_RATIO_THRESHOLD);
        expect(result.status).toBe('unchanged');
    });

    it('reports the expanded region it actually compared', () => {
        const image = () => fakeImage({ width: 200, height: 200, pixelAt: () => WHITE });
        const result = compareRegion(image(), image(), { x: 0.5, y: 0.5, w: 0, h: 0 });

        expect(result.region.w).toBe(MIN_REGION_SIZE);
    });
});

describe('regionDataUrl', () => {
    it('preserves aspect ratio, unlike the square comparison raster', () => {
        const canvases = installCanvasHarness();
        const image = fakeImage({ width: 1000, height: 1000, pixelAt: () => WHITE });

        const url = regionDataUrl(image, { x: 0, y: 0, w: 0.4, h: 0.2 }, 200);

        // 400x200 source region scaled to fit 200px: 200x100, not a square.
        expect(canvases[0].width).toBe(200);
        expect(canvases[0].height).toBe(100);
        expect(url).toBe('data:image/png;base64,STUB');
    });

    it('never upscales past the source region', () => {
        const canvases = installCanvasHarness();
        const image = fakeImage({ width: 100, height: 100, pixelAt: () => WHITE });

        regionDataUrl(image, { x: 0, y: 0, w: 0.1, h: 0.1 }, 240);

        expect(canvases[0].width).toBe(10);
    });

    it('returns null rather than throwing when the canvas is tainted', () => {
        jest.spyOn(document, 'createElement').mockImplementation(() => ({
            width: 0,
            height: 0,
            getContext: () => ({ drawImage: () => {} }),
            toDataURL: () => {
                const error = new Error('Tainted canvases may not be exported.');
                error.name = 'SecurityError';
                throw error;
            },
        }));

        const image = fakeImage({ width: 100, height: 100, pixelAt: () => WHITE });
        expect(regionDataUrl(image, { x: 0, y: 0, w: 1, h: 1 })).toBeNull();
    });
});

describe('isCanvasSecurityError', () => {
    it('recognises a tainted-canvas failure by name or message', () => {
        expect(isCanvasSecurityError({ name: 'SecurityError' })).toBe(true);
        expect(isCanvasSecurityError(new Error('Tainted canvases may not be exported'))).toBe(true);
        expect(isCanvasSecurityError(new Error('cross-origin data'))).toBe(true);
    });

    it('does not misclassify an ordinary failure', () => {
        expect(isCanvasSecurityError(new Error('Failed to load image: /x.png'))).toBe(false);
        expect(isCanvasSecurityError(null)).toBe(false);
    });
});

describe('createImageCache', () => {
    let created;

    beforeEach(() => {
        created = 0;
        // A minimal Image that resolves on the next tick.
        global.Image = class {
            constructor() {
                created += 1;
                setTimeout(() => this.onload?.(), 0);
            }

            set src(_value) { /* triggers the queued onload */ }
        };
    });

    it('loads each preview at most once across many threads', async () => {
        const load = createImageCache();

        await Promise.all([
            load('/v2.png'), load('/v3.png'), load('/v2.png'), load('/v3.png'), load('/v2.png'),
        ]);

        // Twelve annotations against the same two versions must still cost
        // two image loads, not twenty-four.
        expect(created).toBe(2);
    });

    it('shares one in-flight request between concurrent callers', async () => {
        const load = createImageCache();
        const [a, b] = await Promise.all([load('/same.png'), load('/same.png')]);

        expect(created).toBe(1);
        expect(a).toBe(b);
    });
});
