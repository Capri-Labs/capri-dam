/**
 * Geometry helpers for asset annotations.
 *
 * COORDINATES ARE ALWAYS NORMALISED (0..1, upper-left origin) in everything
 * that crosses the API boundary. Pixels only ever exist inside a render pass,
 * derived from the element's *current* measured size. That is what lets one
 * stored annotation land correctly on a thumbnail, a 4K preview, a CDN
 * transform and a zoomed viewport alike.
 *
 * The stored `svg_path` uses a `viewBox="0 0 1 1"` space, mirroring the W3C
 * Web Annotation Data Model's SvgSelector requirement that shape dimensions be
 * relative to the source resource. Rendering scales it back up with a
 * transform rather than rewriting the path.
 */

export const SHAPES = {
    PIN: 'pin',
    RECT: 'rect',
    ELLIPSE: 'ellipse',
    ARROW: 'arrow',
    LINE: 'line',
    FREEHAND: 'freehand',
    TEXT: 'text',
};

// Shapes whose geometry cannot be rebuilt from a bounding box alone, so they
// must carry an svg_path. Mirrors AnnotationTarget::PATH_REQUIRED_SHAPES.
export const PATH_REQUIRED_SHAPES = [SHAPES.ARROW, SHAPES.LINE, SHAPES.FREEHAND];

// Shapes drawn by dragging rather than by a single click.
export const DRAG_SHAPES = [SHAPES.RECT, SHAPES.ELLIPSE, SHAPES.ARROW, SHAPES.LINE, SHAPES.FREEHAND];

export const DEFAULT_STROKE_COLOR = '#ef4444';

/** Clamps a number into the 0..1 normalised range. */
export const clamp01 = (value) => Math.max(0, Math.min(1, value));

/**
 * Rounds to 4 decimal places (~1/10000 of the image's width). Keeps stored
 * geometry compact and stable, and is still sub-pixel accurate up to 10000px.
 */
export const round4 = (value) => Math.round(value * 10000) / 10000;

/**
 * Converts a pointer event into normalised coordinates relative to an element.
 *
 * @param {PointerEvent|MouseEvent} event
 * @param {HTMLElement} element the element the annotation space maps onto
 * @returns {{x: number, y: number}} clamped to 0..1
 */
export function pointFromEvent(event, element) {
    if (!element) return { x: 0, y: 0 };
    const rect = element.getBoundingClientRect();
    if (!rect.width || !rect.height) return { x: 0, y: 0 };

    return {
        x: clamp01((event.clientX - rect.left) / rect.width),
        y: clamp01((event.clientY - rect.top) / rect.height),
    };
}

/** Axis-aligned bounding box spanning two normalised points. */
export function bboxFromPoints(a, b) {
    return {
        x: round4(Math.min(a.x, b.x)),
        y: round4(Math.min(a.y, b.y)),
        w: round4(Math.abs(b.x - a.x)),
        h: round4(Math.abs(b.y - a.y)),
    };
}

/** Bounding box enclosing an arbitrary list of normalised points. */
export function bboxFromPointList(points) {
    if (!points || points.length === 0) return { x: 0, y: 0, w: 0, h: 0 };
    const xs = points.map((p) => p.x);
    const ys = points.map((p) => p.y);
    const minX = Math.min(...xs);
    const minY = Math.min(...ys);
    return {
        x: round4(minX),
        y: round4(minY),
        w: round4(Math.max(...xs) - minX),
        h: round4(Math.max(...ys) - minY),
    };
}

/** Serialises normalised points into an SVG path in a `viewBox="0 0 1 1"` space. */
export function pathFromPoints(points) {
    if (!points || points.length === 0) return null;
    return points
        .map((p, i) => `${i === 0 ? 'M' : 'L'}${round4(p.x)},${round4(p.y)}`)
        .join(' ');
}

/**
 * Parses a normalised `M x,y L x,y …` path back into points, so renderers can
 * compute arrowheads and hit targets without re-deriving them from the bbox
 * (which would lose direction — an arrow drawn right-to-left has the same bbox
 * as one drawn left-to-right).
 */
export function pointsFromPath(path) {
    if (!path) return [];
    const matches = path.match(/[-\d.]+\s*,\s*[-\d.]+/g) || [];
    return matches.map((pair) => {
        const [x, y] = pair.split(',').map((n) => parseFloat(n));
        return { x, y };
    });
}

/** Scales a normalised bbox into pixel space for rendering. */
export function toPixels(bbox, width, height) {
    return {
        x: (bbox?.x || 0) * width,
        y: (bbox?.y || 0) * height,
        w: (bbox?.w || 0) * width,
        h: (bbox?.h || 0) * height,
    };
}

/**
 * Builds the annotation payload for a freshly drawn shape, in exactly the
 * shape the API expects (nested `bbox`, `source`, `style`).
 *
 * @param {string} shape one of SHAPES
 * @param {Array<{x:number,y:number}>} points the drawn points, normalised
 * @param {{width:number, height:number}} sourceSize natural media dimensions
 * @param {string} strokeColor
 * @returns {object|null} null when the gesture was too small to be intentional
 */
export function buildAnnotation(shape, points, sourceSize = {}, strokeColor = DEFAULT_STROKE_COLOR) {
    if (!points || points.length === 0) return null;

    const first = points[0];
    const last = points[points.length - 1];

    let bbox;
    let svgPath = null;

    if (shape === SHAPES.PIN || shape === SHAPES.TEXT) {
        bbox = { x: round4(first.x), y: round4(first.y), w: 0, h: 0 };
    } else if (shape === SHAPES.FREEHAND) {
        // A stray click should not become an invisible one-point scribble.
        if (points.length < 2) return null;
        bbox = bboxFromPointList(points);
        svgPath = pathFromPoints(points);
    } else if (shape === SHAPES.ARROW || shape === SHAPES.LINE) {
        // Direction matters, so the path (not the bbox) is authoritative.
        if (Math.hypot(last.x - first.x, last.y - first.y) < 0.005) return null;
        bbox = bboxFromPoints(first, last);
        svgPath = pathFromPoints([first, last]);
    } else {
        bbox = bboxFromPoints(first, last);
        // Ignore accidental micro-drags that would be impossible to click again.
        if (bbox.w < 0.005 && bbox.h < 0.005) return null;
    }

    return {
        media_type: 'image',
        shape,
        bbox,
        svg_path: svgPath,
        source: {
            width: sourceSize.width || null,
            height: sourceSize.height || null,
            rotation: 0,
        },
        style: {
            stroke_color: strokeColor,
            // Fraction of the shorter source dimension, never pixels — so the
            // stroke keeps its visual weight at any display size.
            stroke_width: 0.004,
            fill: 'none',
            opacity: 1,
        },
    };
}

/** The point a marker/badge should be pinned to for a given annotation. */
export function anchorPoint(annotation) {
    const bbox = annotation?.bbox || {};
    const points = pointsFromPath(annotation?.svg_path);

    // For directional shapes the start point is the meaningful anchor.
    if (points.length > 0 && PATH_REQUIRED_SHAPES.includes(annotation?.shape)) {
        return points[0];
    }

    return {
        x: (bbox.x || 0) + (bbox.w || 0) / 2,
        y: (bbox.y || 0) + (bbox.h || 0) / 2,
    };
}

/**
 * Converts a frame number to SMPTE timecode. Mirrors
 * AnnotationTarget#frames_to_timecode so client-side drafts (which have no
 * server round-trip yet) display identically to saved annotations.
 *
 * Handles NTSC drop-frame timebases (29.97/59.94), where two frame *numbers*
 * are skipped at every minute boundary except every tenth minute.
 */
export function framesToTimecode(frame, fps, dropFrame = false) {
    if (frame == null || !fps) return null;

    const nominal = Math.round(fps);
    if (!nominal) return null;

    let adjusted = Math.trunc(frame);

    if (dropFrame) {
        const droppedPerMinute = Math.round(fps * 0.066666);
        if (droppedPerMinute > 0) {
            const framesPer10Min = Math.round(fps * 600);
            const framesPerMin = nominal * 60 - droppedPerMinute;
            const tenMinuteBlocks = Math.trunc(adjusted / framesPer10Min);
            const remainder = adjusted % framesPer10Min;

            let correction = droppedPerMinute * 9 * tenMinuteBlocks;
            if (remainder > droppedPerMinute) {
                correction += droppedPerMinute * Math.trunc((remainder - droppedPerMinute) / framesPerMin);
            }
            adjusted += correction;
        }
    }

    const frames = adjusted % nominal;
    const totalSeconds = Math.trunc(adjusted / nominal);
    const pad = (n) => String(n).padStart(2, '0');

    return [
        pad(Math.trunc(totalSeconds / 3600)),
        pad(Math.trunc(totalSeconds / 60) % 60),
        pad(totalSeconds % 60),
    ].join(':') + (dropFrame ? ';' : ':') + pad(frames);
}
