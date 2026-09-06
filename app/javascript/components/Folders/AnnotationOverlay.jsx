import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Box } from '@mui/material';
import {
    SHAPES,
    DRAG_SHAPES,
    PATH_REQUIRED_SHAPES,
    DEFAULT_STROKE_COLOR,
    anchorPoint,
    buildAnnotation,
    pointFromEvent,
    pointsFromPath,
    toPixels,
} from '../../utils/annotationGeometry';

/**
 * Transparent drawing/display layer stacked over an asset preview.
 *
 * WHY SVG AND NOT <canvas>
 * ------------------------
 * Annotations are persistent, individually selectable objects, not a raster
 * scribble. SVG gives per-shape hit-testing, hover and focus for free, stays
 * crisp at any zoom or DPI, and — because the geometry is stored as an SVG
 * path in a normalised `viewBox="0 0 1 1"` space — needs no conversion step
 * between storage and render. A canvas would require re-implementing
 * hit-testing and would blur on retina displays.
 *
 * WHY PIXELS APPEAR HERE AT ALL
 * -----------------------------
 * The <svg> is sized in *pixels* from a live ResizeObserver measurement, and
 * normalised values are multiplied up at render time. Rendering directly in a
 * 0..1 viewBox would be simpler but non-uniformly scales the coordinate space,
 * turning circles into ellipses and distorting stroke widths. Stored data
 * stays normalised; only this render pass is in pixels.
 */
export default function AnnotationOverlay({
    annotations = [],
    draft = [],
    tool = null,
    onDraftAdd,
    selectedThreadId = null,
    hoveredThreadId = null,
    onSelectThread,
    onHoverThread,
    sourceSize = {},
    strokeColor = DEFAULT_STROKE_COLOR,
}) {
    const containerRef = useRef(null);
    const [size, setSize] = useState({ width: 0, height: 0 });
    const [inProgress, setInProgress] = useState(null);

    const isDrawing = Boolean(tool);

    // Track the rendered size of the media so normalised geometry can be
    // projected into pixels. ResizeObserver (rather than a window resize
    // listener) also catches the panel/tab reflows that change the preview
    // box without the window changing at all.
    useEffect(() => {
        const node = containerRef.current;
        if (!node || typeof ResizeObserver === 'undefined') return undefined;

        const observer = new ResizeObserver((entries) => {
            const rect = entries[0]?.contentRect;
            if (rect) setSize({ width: rect.width, height: rect.height });
        });
        observer.observe(node);
        setSize({ width: node.clientWidth, height: node.clientHeight });

        return () => observer.disconnect();
    }, []);

    const finishGesture = useCallback((points, shape) => {
        const annotation = buildAnnotation(shape, points, sourceSize, strokeColor);
        if (annotation && onDraftAdd) onDraftAdd(annotation);
    }, [onDraftAdd, sourceSize, strokeColor]);

    const handlePointerDown = useCallback((event) => {
        if (!isDrawing) return;
        event.preventDefault();

        const point = pointFromEvent(event, containerRef.current);

        // A pin is a single click — there is nothing to drag.
        if (!DRAG_SHAPES.includes(tool)) {
            finishGesture([point], tool);
            return;
        }

        event.currentTarget.setPointerCapture?.(event.pointerId);
        setInProgress({ shape: tool, points: [point] });
    }, [isDrawing, tool, finishGesture]);

    const handlePointerMove = useCallback((event) => {
        if (!inProgress) return;
        const point = pointFromEvent(event, containerRef.current);

        setInProgress((current) => {
            if (!current) return current;
            // Freehand accumulates every sample; the other shapes only ever
            // need their start and current point.
            const points = current.shape === SHAPES.FREEHAND
                ? [...current.points, point]
                : [current.points[0], point];
            return { ...current, points };
        });
    }, [inProgress]);

    const handlePointerUp = useCallback((event) => {
        if (!inProgress) return;
        event.currentTarget.releasePointerCapture?.(event.pointerId);
        finishGesture(inProgress.points, inProgress.shape);
        setInProgress(null);
    }, [inProgress, finishGesture]);

    // Saved annotations plus anything drawn but not yet posted.
    const renderable = useMemo(() => {
        const saved = annotations.map((a) => ({ ...a, __draft: false }));
        const pending = draft.map((a, i) => ({ ...a, id: `draft-${i}`, __draft: true }));
        return [...saved, ...pending];
    }, [annotations, draft]);

    const { width, height } = size;
    const hasSize = width > 0 && height > 0;

    return (
        <Box
            ref={containerRef}
            data-testid="annotation-overlay"
            onPointerDown={handlePointerDown}
            onPointerMove={handlePointerMove}
            onPointerUp={handlePointerUp}
            sx={{
                position: 'absolute',
                inset: 0,
                // Only intercept clicks while a tool is armed, so the asset
                // preview stays interactive (context menu, drag) otherwise.
                pointerEvents: isDrawing ? 'auto' : 'none',
                cursor: isDrawing ? 'crosshair' : 'default',
                touchAction: isDrawing ? 'none' : 'auto',
            }}
        >
            {hasSize && (
                <svg
                    width={width}
                    height={height}
                    viewBox={`0 0 ${width} ${height}`}
                    style={{ position: 'absolute', inset: 0, overflow: 'visible' }}
                >
                    <defs>
                        <marker
                            id="annotation-arrowhead"
                            markerWidth="6"
                            markerHeight="6"
                            refX="5"
                            refY="3"
                            orient="auto"
                            markerUnits="strokeWidth"
                        >
                            <path d="M0,0 L6,3 L0,6 z" fill="context-stroke" />
                        </marker>
                    </defs>

                    {renderable.map((annotation) => (
                        <AnnotationShape
                            key={annotation.id}
                            annotation={annotation}
                            width={width}
                            height={height}
                            selected={annotation.thread_id && annotation.thread_id === selectedThreadId}
                            hovered={annotation.thread_id && annotation.thread_id === hoveredThreadId}
                            interactive={!isDrawing}
                            onSelect={onSelectThread}
                            onHover={onHoverThread}
                        />
                    ))}

                    {inProgress && (
                        <AnnotationShape
                            annotation={{
                                shape: inProgress.shape,
                                bbox: previewBBox(inProgress),
                                svg_path: previewPath(inProgress),
                                style: { stroke_color: strokeColor, stroke_width: 0.004 },
                                __draft: true,
                            }}
                            width={width}
                            height={height}
                            interactive={false}
                        />
                    )}
                </svg>
            )}
        </Box>
    );
}

/** Live bounding box for the gesture currently under the pointer. */
function previewBBox({ shape, points }) {
    const first = points[0];
    const last = points[points.length - 1];
    if (shape === SHAPES.FREEHAND || PATH_REQUIRED_SHAPES.includes(shape)) {
        const xs = points.map((p) => p.x);
        const ys = points.map((p) => p.y);
        const x = Math.min(...xs);
        const y = Math.min(...ys);
        return { x, y, w: Math.max(...xs) - x, h: Math.max(...ys) - y };
    }
    return {
        x: Math.min(first.x, last.x),
        y: Math.min(first.y, last.y),
        w: Math.abs(last.x - first.x),
        h: Math.abs(last.y - first.y),
    };
}

function previewPath({ shape, points }) {
    if (!PATH_REQUIRED_SHAPES.includes(shape)) return null;
    const list = shape === SHAPES.FREEHAND ? points : [points[0], points[points.length - 1]];
    return list.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x},${p.y}`).join(' ');
}

/**
 * Renders one annotation. Kept separate so each shape is its own SVG node with
 * its own hover/click target.
 */
function AnnotationShape({
    annotation, width, height, selected, hovered, interactive, onSelect, onHover,
}) {
    const style = annotation.style || {};
    const stroke = style.stroke_color || DEFAULT_STROKE_COLOR;

    // stroke_width is stored as a fraction of the shorter source dimension, so
    // it scales with the media instead of thinning out on large previews.
    const strokeWidth = Math.max(1.5, (style.stroke_width || 0.004) * Math.min(width, height));
    const emphasised = selected || hovered;

    const box = toPixels(annotation.bbox, width, height);
    const points = pointsFromPath(annotation.svg_path);

    const interaction = interactive && annotation.thread_id ? {
        style: { cursor: 'pointer', pointerEvents: 'auto' },
        onClick: (e) => { e.stopPropagation(); onSelect?.(annotation.thread_id); },
        onMouseEnter: () => onHover?.(annotation.thread_id),
        onMouseLeave: () => onHover?.(null),
    } : { style: { pointerEvents: 'none' } };

    const common = {
        stroke,
        strokeWidth: emphasised ? strokeWidth * 1.75 : strokeWidth,
        fill: 'none',
        opacity: annotation.__draft ? 0.85 : 1,
        strokeDasharray: annotation.__draft ? `${strokeWidth * 3} ${strokeWidth * 2}` : undefined,
        vectorEffect: 'non-scaling-stroke',
    };

    switch (annotation.shape) {
        case SHAPES.RECT:
            return (
                <g {...interaction}>
                    {/* Invisible fat stroke: makes a thin outline easy to click. */}
                    <rect x={box.x} y={box.y} width={box.w} height={box.h} fill="transparent" stroke="transparent" strokeWidth={strokeWidth * 6} />
                    <rect x={box.x} y={box.y} width={box.w} height={box.h} rx={2} {...common} />
                </g>
            );

        case SHAPES.ELLIPSE:
            return (
                <g {...interaction}>
                    <ellipse cx={box.x + box.w / 2} cy={box.y + box.h / 2} rx={box.w / 2} ry={box.h / 2} fill="transparent" stroke="transparent" strokeWidth={strokeWidth * 6} />
                    <ellipse cx={box.x + box.w / 2} cy={box.y + box.h / 2} rx={box.w / 2} ry={box.h / 2} {...common} />
                </g>
            );

        case SHAPES.LINE:
        case SHAPES.ARROW: {
            if (points.length < 2) return null;
            const [from, to] = [points[0], points[points.length - 1]];
            const x1 = from.x * width; const y1 = from.y * height;
            const x2 = to.x * width; const y2 = to.y * height;
            return (
                <g {...interaction}>
                    <line x1={x1} y1={y1} x2={x2} y2={y2} stroke="transparent" strokeWidth={strokeWidth * 6} />
                    <line
                        x1={x1}
                        y1={y1}
                        x2={x2}
                        y2={y2}
                        {...common}
                        markerEnd={annotation.shape === SHAPES.ARROW ? 'url(#annotation-arrowhead)' : undefined}
                    />
                </g>
            );
        }

        case SHAPES.FREEHAND:
            return (
                <g {...interaction} transform={`scale(${width} ${height})`}>
                    {/* The path is stored in a 0..1 space, so it is scaled by a
                        transform rather than rewritten. `non-scaling-stroke`
                        stops the non-uniform scale from distorting the line. */}
                    <path d={annotation.svg_path} fill="none" stroke="transparent" strokeWidth={strokeWidth * 6} vectorEffect="non-scaling-stroke" />
                    <path d={annotation.svg_path} {...common} strokeLinecap="round" strokeLinejoin="round" />
                </g>
            );

        case SHAPES.PIN:
        case SHAPES.TEXT:
        default: {
            const anchor = anchorPoint(annotation);
            const cx = anchor.x * width;
            const cy = anchor.y * height;
            const radius = emphasised ? 13 : 10;
            return (
                <g {...interaction}>
                    <circle cx={cx} cy={cy} r={radius + 6} fill="transparent" />
                    <circle cx={cx} cy={cy} r={radius} fill={stroke} stroke="#ffffff" strokeWidth={2} opacity={annotation.__draft ? 0.85 : 1} />
                    {annotation.marker_label && (
                        <text
                            x={cx}
                            y={cy + 4}
                            textAnchor="middle"
                            fill="#ffffff"
                            fontSize={11}
                            fontWeight="700"
                            style={{ pointerEvents: 'none', userSelect: 'none' }}
                        >
                            {annotation.marker_label}
                        </text>
                    )}
                </g>
            );
        }
    }
}

export { AnnotationShape };
