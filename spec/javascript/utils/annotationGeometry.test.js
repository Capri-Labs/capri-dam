import {
    SHAPES,
    anchorPoint,
    bboxFromPointList,
    bboxFromPoints,
    buildAnnotation,
    clamp01,
    framesToTimecode,
    pathFromPoints,
    pointFromEvent,
    pointsFromPath,
    round4,
    toPixels,
} from '../../../app/javascript/utils/annotationGeometry';

describe('clamp01 / round4', () => {
    it('clamps into the normalised range', () => {
        expect(clamp01(-0.4)).toBe(0);
        expect(clamp01(1.7)).toBe(1);
        expect(clamp01(0.42)).toBe(0.42);
    });

    it('rounds to four decimal places', () => {
        expect(round4(0.123456)).toBe(0.1235);
        expect(round4(1)).toBe(1);
    });
});

describe('pointFromEvent', () => {
    const element = (rect) => ({ getBoundingClientRect: () => rect });

    it('normalises a pointer position against the element box', () => {
        const el = element({ left: 100, top: 50, width: 400, height: 200 });

        expect(pointFromEvent({ clientX: 300, clientY: 150 }, el)).toEqual({ x: 0.5, y: 0.5 });
    });

    it('clamps a pointer that leaves the element', () => {
        const el = element({ left: 0, top: 0, width: 100, height: 100 });

        expect(pointFromEvent({ clientX: -20, clientY: 250 }, el)).toEqual({ x: 0, y: 1 });
    });

    it('degrades safely when the element has no size or does not exist', () => {
        expect(pointFromEvent({ clientX: 5, clientY: 5 }, null)).toEqual({ x: 0, y: 0 });
        expect(pointFromEvent({ clientX: 5, clientY: 5 }, element({ left: 0, top: 0, width: 0, height: 0 })))
            .toEqual({ x: 0, y: 0 });
    });
});

describe('bounding boxes', () => {
    it('spans two points regardless of drag direction', () => {
        const topLeftFirst = bboxFromPoints({ x: 0.2, y: 0.3 }, { x: 0.6, y: 0.8 });
        const bottomRightFirst = bboxFromPoints({ x: 0.6, y: 0.8 }, { x: 0.2, y: 0.3 });

        expect(topLeftFirst).toEqual({ x: 0.2, y: 0.3, w: 0.4, h: 0.5 });
        expect(bottomRightFirst).toEqual(topLeftFirst);
    });

    it('encloses an arbitrary list of points', () => {
        const bbox = bboxFromPointList([
            { x: 0.4, y: 0.1 }, { x: 0.1, y: 0.9 }, { x: 0.7, y: 0.5 },
        ]);

        expect(bbox).toEqual({ x: 0.1, y: 0.1, w: 0.6, h: 0.8 });
    });

    it('returns an empty box for no points', () => {
        expect(bboxFromPointList([])).toEqual({ x: 0, y: 0, w: 0, h: 0 });
    });
});

describe('path serialisation', () => {
    it('round-trips points through an SVG path', () => {
        const points = [{ x: 0.1, y: 0.2 }, { x: 0.35, y: 0.4 }, { x: 0.5, y: 0.9 }];

        const path = pathFromPoints(points);

        expect(path).toBe('M0.1,0.2 L0.35,0.4 L0.5,0.9');
        expect(pointsFromPath(path)).toEqual(points);
    });

    it('returns null/empty for missing input', () => {
        expect(pathFromPoints([])).toBeNull();
        expect(pointsFromPath(null)).toEqual([]);
    });
});

describe('toPixels', () => {
    it('projects a normalised box onto a rendered size', () => {
        expect(toPixels({ x: 0.25, y: 0.5, w: 0.5, h: 0.25 }, 800, 400))
            .toEqual({ x: 200, y: 200, w: 400, h: 100 });
    });

    it('treats a missing box as the origin', () => {
        expect(toPixels(undefined, 800, 400)).toEqual({ x: 0, y: 0, w: 0, h: 0 });
    });
});

describe('buildAnnotation', () => {
    const source = { width: 4000, height: 3000 };

    it('builds a zero-size box for a pin', () => {
        const annotation = buildAnnotation(SHAPES.PIN, [{ x: 0.5, y: 0.25 }], source);

        expect(annotation.shape).toBe('pin');
        expect(annotation.bbox).toEqual({ x: 0.5, y: 0.25, w: 0, h: 0 });
        expect(annotation.svg_path).toBeNull();
        expect(annotation.source).toEqual({ width: 4000, height: 3000, rotation: 0 });
        // Stroke width is a fraction of the source, never a pixel value.
        expect(annotation.style.stroke_width).toBeLessThan(1);
    });

    it('stores a path for an arrow so its direction survives', () => {
        const forward = buildAnnotation(SHAPES.ARROW, [{ x: 0.1, y: 0.1 }, { x: 0.6, y: 0.4 }], source);
        const backward = buildAnnotation(SHAPES.ARROW, [{ x: 0.6, y: 0.4 }, { x: 0.1, y: 0.1 }], source);

        // Same bounding box …
        expect(forward.bbox).toEqual(backward.bbox);
        // … but distinguishable paths, which is exactly why the path is stored.
        expect(forward.svg_path).toBe('M0.1,0.1 L0.6,0.4');
        expect(backward.svg_path).toBe('M0.6,0.4 L0.1,0.1');
    });

    it('keeps every sampled point for freehand', () => {
        const points = [{ x: 0.1, y: 0.1 }, { x: 0.2, y: 0.3 }, { x: 0.4, y: 0.2 }];

        const annotation = buildAnnotation(SHAPES.FREEHAND, points, source);

        expect(pointsFromPath(annotation.svg_path)).toEqual(points);
        expect(annotation.bbox).toEqual({ x: 0.1, y: 0.1, w: 0.3, h: 0.2 });
    });

    it('rejects gestures too small to be intentional', () => {
        expect(buildAnnotation(SHAPES.RECT, [{ x: 0.5, y: 0.5 }, { x: 0.5005, y: 0.5005 }], source)).toBeNull();
        expect(buildAnnotation(SHAPES.LINE, [{ x: 0.5, y: 0.5 }, { x: 0.501, y: 0.5 }], source)).toBeNull();
        expect(buildAnnotation(SHAPES.FREEHAND, [{ x: 0.5, y: 0.5 }], source)).toBeNull();
        expect(buildAnnotation(SHAPES.RECT, [], source)).toBeNull();
    });
});

describe('anchorPoint', () => {
    it('uses the start of a directional shape', () => {
        expect(anchorPoint({
            shape: SHAPES.ARROW,
            bbox: { x: 0.1, y: 0.1, w: 0.5, h: 0.3 },
            svg_path: 'M0.6,0.4 L0.1,0.1',
        })).toEqual({ x: 0.6, y: 0.4 });
    });

    it('uses the centre of a box-shaped annotation', () => {
        expect(anchorPoint({ shape: SHAPES.RECT, bbox: { x: 0.2, y: 0.2, w: 0.4, h: 0.2 } }))
            .toEqual({ x: 0.4, y: 0.30000000000000004 });
    });
});

describe('framesToTimecode', () => {
    it('formats a non-drop-frame timebase', () => {
        expect(framesToTimecode(1511, 25, false)).toBe('00:01:00:11');
        expect(framesToTimecode(0, 25, false)).toBe('00:00:00:00');
    });

    it('applies NTSC drop-frame correction', () => {
        // The canonical drop-frame check: at 29.97 fps, frame 17982 is exactly
        // ten minutes of wall-clock time.
        expect(framesToTimecode(17982, 29.97, true)).toBe('00:10:00;00');
        expect(framesToTimecode(1500, 29.97, true)).toBe('00:00:50;00');
    });

    it('returns null when the timebase is unknown', () => {
        expect(framesToTimecode(null, 25)).toBeNull();
        expect(framesToTimecode(100, null)).toBeNull();
        expect(framesToTimecode(100, 0)).toBeNull();
    });
});
