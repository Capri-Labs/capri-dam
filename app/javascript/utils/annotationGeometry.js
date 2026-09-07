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
 * @param {object} [options]
 * @param {string} [options.mediaType='image'] `image`, `video` or `document`
 * @param {object} [options.video] temporal position, see {@link buildTemporal}
 * @returns {object|null} null when the gesture was too small to be intentional
 */
export function buildAnnotation(shape, points, sourceSize = {}, strokeColor = DEFAULT_STROKE_COLOR, options = {}) {
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
        media_type: options.mediaType || 'image',
        shape,
        bbox,
        svg_path: svgPath,
        // Omitted entirely for stills: the API treats a null `video` as "not
        // time-based", and AnnotationTarget rejects a frame without an fps.
        video: buildTemporal(options.video) || undefined,
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

/**
 * Normalises a temporal position into the `video` block the API accepts.
 *
 * Returns null unless both a frame and a frame rate are present, because the
 * server rejects a frame number it cannot interpret (see
 * AnnotationTarget#video_targets_declare_a_frame_rate). An `end_frame` equal to
 * the start is dropped so a zero-length "range" is stored as an instant.
 *
 * @param {{startFrame:number, endFrame:number|null, fps:number, dropFrame:boolean}} [position]
 * @returns {object|null}
 */
export function buildTemporal(position) {
    if (!position) return null;

    const { startFrame, endFrame, fps, dropFrame } = position;
    if (startFrame == null || !fps) return null;

    const start = Math.max(0, Math.trunc(startFrame));
    const end = endFrame == null ? null : Math.max(0, Math.trunc(endFrame));

    return {
        start_frame: start,
        end_frame: end != null && end > start ? end : null,
        fps,
        drop_frame: Boolean(dropFrame),
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

// ---------------------------------------------------------------------------
// Time <-> frame conversion
//
// The <video> element only ever reports `currentTime` in floating-point
// seconds, but annotations are stored as frame integers (see AnnotationTarget).
// Everything below is the bridge between those two worlds, and it is
// deliberately asymmetric: seconds -> frames floors (the frame *being
// displayed* at time t), while frames -> seconds returns the frame's start
// time. Round-tripping therefore lands back on the same frame instead of
// drifting a frame earlier each time.
// ---------------------------------------------------------------------------

/** NTSC rationals that use SMPTE drop-frame timecode. Mirrors the worker. */
export const NTSC_DROP_FRAME_RATIOS = ['30000/1001', '60000/1001'];

/**
 * Parses an ffprobe frame-rate rational ("30000/1001", "25/1", "24") into a
 * float. Returns null for the `0/0` placeholder ffprobe emits for streams with
 * no meaningful rate.
 *
 * @param {string|number|null} ratio
 * @returns {number|null}
 */
export function frameRateFromRatio(ratio) {
    if (ratio == null || ratio === '') return null;
    if (typeof ratio === 'number') return ratio > 0 ? ratio : null;

    const [numerator, denominator = '1'] = String(ratio).split('/');
    const n = parseFloat(numerator);
    const d = parseFloat(denominator);
    if (!Number.isFinite(n) || !Number.isFinite(d) || d === 0 || n <= 0) return null;

    return n / d;
}

/**
 * The frame displayed at a given playback time.
 *
 * Floors rather than rounds: at t = 1.999s in a 30fps clip the viewer is
 * looking at frame 59, not frame 60, and an annotation must attach to the
 * frame they can actually see.
 *
 * @param {number} seconds
 * @param {number} fps
 * @returns {number|null}
 */
export function secondsToFrames(seconds, fps) {
    if (seconds == null || !fps || !Number.isFinite(seconds)) return null;
    return Math.max(0, Math.floor(seconds * fps));
}

/**
 * The playback time at which a frame begins.
 *
 * Half a frame is added so that seeking lands *inside* the target frame rather
 * than exactly on its boundary, where floating-point error in the browser's
 * seek implementation can leave the previous frame on screen.
 *
 * @param {number} frame
 * @param {number} fps
 * @returns {number|null}
 */
export function framesToSeconds(frame, fps) {
    if (frame == null || !fps) return null;
    return (Math.max(0, Math.trunc(frame)) + 0.5) / fps;
}

/**
 * True when this annotation carries a video position rather than being a
 * still-image markup.
 */
export function isTemporal(annotation) {
    return annotation?.video?.start_frame != null;
}

/**
 * Whether a temporal annotation should be visible at the given frame.
 *
 * A range annotation is shown for its whole span; an instant annotation is
 * shown for a short window around its frame, because a single frame at 30fps
 * is on screen for 33ms and a marker that flickers past is useless. Non-video
 * annotations are always visible.
 *
 * @param {object} annotation
 * @param {number|null} frame current playhead frame
 * @param {number} [tolerance] half-window in frames for instant annotations
 * @returns {boolean}
 */
export function isVisibleAtFrame(annotation, frame, tolerance = 15) {
    if (!isTemporal(annotation)) return true;
    if (frame == null) return true;

    const { start_frame: start, end_frame: end } = annotation.video;
    if (end != null && end > start) return frame >= start && frame <= end;

    return Math.abs(frame - start) <= tolerance;
}

/**
 * Formats a frame position as a compact `m:ss` label for dense UI (chips,
 * marker tooltips) where a full SMPTE timecode is too wide.
 *
 * @param {number} frame
 * @param {number} fps
 * @returns {string|null}
 */
export function framesToClock(frame, fps) {
    if (frame == null || !fps) return null;

    const total = Math.max(0, Math.trunc(frame)) / fps;
    const minutes = Math.floor(total / 60);
    const seconds = Math.floor(total % 60);
    const hours = Math.floor(minutes / 60);

    const body = `${hours > 0 ? minutes % 60 : minutes}:${String(seconds).padStart(2, '0')}`;
    return hours > 0 ? `${hours}:${String(minutes % 60).padStart(2, '0')}:${String(seconds).padStart(2, '0')}` : body;
}

/**
 * Reads the frame-rate context off an asset's `properties`, falling back to a
 * sane default so the annotation tools still work on a video that predates
 * frame-rate extraction (or was ingested without FFmpeg installed).
 *
 * @param {object} properties asset.properties
 * @returns {{fps: number, dropFrame: boolean, exact: boolean}}
 */
export function frameRateContext(properties = {}) {
    const ratio = properties?.video_frame_rate_ratio;
    const fromRatio = frameRateFromRatio(ratio);
    const fromFloat = frameRateFromRatio(properties?.video_frame_rate);
    const fps = fromRatio || fromFloat;

    if (!fps) {
        // 25fps is a deliberate, documented guess rather than a silent 0: it
        // keeps the frame arithmetic self-consistent, and `exact: false` lets
        // the UI warn that stepping is approximate.
        return { fps: 25, dropFrame: false, exact: false };
    }

    return {
        fps,
        dropFrame: ratio
            ? NTSC_DROP_FRAME_RATIOS.includes(String(ratio))
            : Boolean(properties?.video_drop_frame),
        exact: true,
    };
}
