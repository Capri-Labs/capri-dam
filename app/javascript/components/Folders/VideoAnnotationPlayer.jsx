import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Box, IconButton, Slider, Tooltip, Typography } from '@mui/material';
import PlayArrow from '@mui/icons-material/PlayArrow';
import Pause from '@mui/icons-material/Pause';
import SkipPrevious from '@mui/icons-material/SkipPrevious';
import SkipNext from '@mui/icons-material/SkipNext';
import VolumeUp from '@mui/icons-material/VolumeUp';
import VolumeOff from '@mui/icons-material/VolumeOff';
import LoopIcon from '@mui/icons-material/Loop';
import ClearIcon from '@mui/icons-material/Clear';
import { useTranslation } from 'react-i18next';
import {
    framesToClock,
    framesToSeconds,
    framesToTimecode,
    isTemporal,
    secondsToFrames,
} from '../../utils/annotationGeometry';

/**
 * A frame-accurate video player for review and annotation.
 *
 * WHY NOT THE NATIVE `controls`
 * -----------------------------
 * The browser's built-in transport reports time in seconds, cannot be stepped
 * a frame at a time, and — decisively — offers nowhere to render the marker
 * track. Comment markers have to sit *on* the timeline: a reviewer needs to
 * see at a glance that there are three notes clustered at 0:14 without
 * scrubbing to find them. So the transport is rebuilt here, in frames.
 *
 * WHY FRAMES ARE THE UNIT
 * -----------------------
 * `HTMLMediaElement.currentTime` is a float in seconds and is the only clock
 * the browser exposes, but "the third frame of the logo animation" is not
 * expressible as a rounded float — and rounding it once destroys the
 * information permanently. Every position in this component is therefore an
 * integer frame, converted to seconds only at the moment it is handed to the
 * media element (see annotationGeometry).
 *
 * WHY requestAnimationFrame RATHER THAN `timeupdate`
 * --------------------------------------------------
 * `timeupdate` fires roughly 4x/second, so a frame counter driven by it would
 * visibly stutter and jump ~7 frames at a time. A rAF loop samples once per
 * repaint while playing, which is at least as often as the frame rate, and is
 * torn down as soon as playback stops so it costs nothing when idle.
 */
export default function VideoAnnotationPlayer({
    src,
    poster,
    fps,
    dropFrame = false,
    exactFrameRate = true,
    annotations = [],
    currentFrame = 0,
    onFrameChange,
    seekRequest = null,
    inPoint = null,
    outPoint = null,
    onSetIn,
    onSetOut,
    onClearRange,
    loop = false,
    onToggleLoop,
    onLoadedMetadata,
    onSelectThread,
    hoveredThreadId = null,
    children,
}) {
    const { t } = useTranslation();
    const translate = useCallback((key, fallback) => {
        const value = t(key);
        return value === key ? fallback : value;
    }, [t]);

    const videoRef = useRef(null);
    const frameRef = useRef(null);
    const [playing, setPlaying] = useState(false);
    const [muted, setMuted] = useState(false);
    const [durationFrames, setDurationFrames] = useState(0);
    // Suppresses the rAF/timeupdate feedback loop while the user drags the
    // scrubber, which would otherwise fight the thumb back to the play head.
    const [scrubbing, setScrubbing] = useState(false);

    const totalFrames = Math.max(0, durationFrames);

    const emitFrame = useCallback((frame) => {
        onFrameChange?.(Math.max(0, Math.min(frame, totalFrames)));
    }, [onFrameChange, totalFrames]);

    const seekToFrame = useCallback((frame) => {
        const video = videoRef.current;
        if (!video || !fps) return;

        const clamped = Math.max(0, Math.min(Math.trunc(frame), totalFrames));
        const seconds = framesToSeconds(clamped, fps);
        if (seconds != null && Number.isFinite(seconds)) video.currentTime = seconds;
        emitFrame(clamped);
    }, [fps, totalFrames, emitFrame]);

    // Honour an external seek (clicking a comment's timecode chip). A plain
    // `frame` prop would not re-fire when the user seeks away and then clicks
    // the same chip again, so the request carries a monotonic token.
    useEffect(() => {
        if (seekRequest?.frame == null) return;
        seekToFrame(seekRequest.frame);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [seekRequest?.token]);

    // Sample the play head once per repaint while playing, and enforce the
    // loop range here rather than on `timeupdate` so the jump back happens
    // within a frame of the out point instead of up to 250ms late.
    useEffect(() => {
        if (!playing || !fps) return undefined;

        let raf;
        const tick = () => {
            const video = videoRef.current;
            if (video) {
                const frame = secondsToFrames(video.currentTime, fps);

                if (loop && inPoint != null && outPoint != null && frame != null && frame >= outPoint) {
                    video.currentTime = framesToSeconds(inPoint, fps);
                    emitFrame(inPoint);
                } else if (frame != null && !scrubbing) {
                    emitFrame(frame);
                }
            }
            raf = requestAnimationFrame(tick);
        };

        raf = requestAnimationFrame(tick);
        return () => cancelAnimationFrame(raf);
    }, [playing, fps, loop, inPoint, outPoint, scrubbing, emitFrame]);

    const handleLoadedMetadata = useCallback((event) => {
        const video = event.currentTarget;
        setDurationFrames(secondsToFrames(video.duration, fps) || 0);
        onLoadedMetadata?.({ width: video.videoWidth, height: video.videoHeight });
    }, [fps, onLoadedMetadata]);

    const togglePlay = useCallback(() => {
        const video = videoRef.current;
        if (!video) return;
        if (video.paused) video.play?.(); else video.pause?.();
    }, []);

    const step = useCallback((delta) => {
        const video = videoRef.current;
        // Stepping while playing is meaningless — the play head would move on
        // immediately — so pause first, matching every NLE.
        if (video && !video.paused) video.pause?.();
        seekToFrame((currentFrame || 0) + delta);
    }, [currentFrame, seekToFrame]);

    // Keyboard transport, scoped to the player so it never hijacks typing in
    // the comment composer. J/K/L and , / . are the standard NLE bindings.
    const handleKeyDown = useCallback((event) => {
        const handlers = {
            ' ': () => togglePlay(),
            k: () => togglePlay(),
            ArrowLeft: () => step(-1),
            ArrowRight: () => step(1),
            ',': () => step(-1),
            '.': () => step(1),
            i: () => onSetIn?.(currentFrame),
            o: () => onSetOut?.(currentFrame),
        };

        const handler = handlers[event.key];
        if (!handler) return;
        event.preventDefault();
        handler();
    }, [togglePlay, step, onSetIn, onSetOut, currentFrame]);

    // Only annotations that actually carry a frame belong on the timeline.
    const markers = useMemo(() => annotations.filter(isTemporal), [annotations]);

    const percent = useCallback(
        (frame) => (totalFrames > 0 ? (Math.max(0, Math.min(frame, totalFrames)) / totalFrames) * 100 : 0),
        [totalFrames],
    );

    const timecode = framesToTimecode(currentFrame || 0, fps, dropFrame);
    const durationTimecode = framesToTimecode(totalFrames, fps, dropFrame);
    const hasRange = inPoint != null && outPoint != null && outPoint > inPoint;

    return (
        <Box
            data-testid="video-annotation-player"
            tabIndex={0}
            onKeyDown={handleKeyDown}
            sx={{ display: 'flex', flexDirection: 'column', maxWidth: '100%', maxHeight: '100%', outline: 'none' }}
        >
            {/* The overlay must align with the rendered video box, not the
                padded pane, so both share a shrink-wrapping relative container
                — the same arrangement the still-image preview uses. */}
            <Box sx={{ position: 'relative', display: 'inline-flex', minHeight: 0, justifyContent: 'center' }}>
                <Box
                    component="video"
                    ref={videoRef}
                    src={src}
                    poster={poster}
                    data-testid="asset-viewer-video-player"
                    onLoadedMetadata={handleLoadedMetadata}
                    onPlay={() => setPlaying(true)}
                    onPause={() => setPlaying(false)}
                    onEnded={() => setPlaying(false)}
                    onTimeUpdate={(event) => {
                        // Covers seeking and paused scrubbing, when no rAF loop
                        // is running to report the new position.
                        if (playing || scrubbing) return;
                        const frame = secondsToFrames(event.currentTarget.currentTime, fps);
                        if (frame != null) emitFrame(frame);
                    }}
                    sx={{
                        maxWidth: '100%',
                        maxHeight: '100%',
                        display: 'block',
                        boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.1)',
                    }}
                />
                {children}
            </Box>

            <Box
                data-testid="video-transport"
                sx={{ mt: 1.5, px: 1, py: 0.5, bgcolor: '#ffffff', border: '1px solid #e2e8f0', borderRadius: 1 }}
            >
                <Box ref={frameRef} sx={{ position: 'relative', px: 1 }}>
                    {/* Marker track. Sits above the scrubber rather than on it
                        so a dense cluster of notes never blocks the thumb. */}
                    <Box
                        data-testid="video-marker-track"
                        sx={{ position: 'relative', height: 14, mb: -0.5 }}
                    >
                        {hasRange && (
                            <Box
                                data-testid="video-range-highlight"
                                sx={{
                                    position: 'absolute',
                                    left: `${percent(inPoint)}%`,
                                    width: `${percent(outPoint) - percent(inPoint)}%`,
                                    top: 4,
                                    height: 6,
                                    bgcolor: 'rgba(37, 99, 235, 0.25)',
                                    border: '1px solid #2563eb',
                                    borderRadius: 0.5,
                                }}
                            />
                        )}

                        {markers.map((annotation) => {
                            const start = annotation.video.start_frame;
                            const end = annotation.video.end_frame;
                            const isRange = end != null && end > start;
                            const emphasised = annotation.thread_id === hoveredThreadId;

                            return (
                                <Tooltip
                                    key={annotation.id}
                                    title={`${annotation.marker_label ? `#${annotation.marker_label} · ` : ''}${framesToClock(start, fps)}${isRange ? `–${framesToClock(end, fps)}` : ''}`}
                                >
                                    <Box
                                        role="button"
                                        tabIndex={0}
                                        aria-label={translate('assetComments.video.jumpToMarker', 'Jump to annotation')}
                                        data-testid="video-marker"
                                        data-thread-id={annotation.thread_id}
                                        onClick={() => {
                                            seekToFrame(start);
                                            onSelectThread?.(annotation.thread_id);
                                        }}
                                        sx={{
                                            position: 'absolute',
                                            left: `${percent(start)}%`,
                                            width: isRange ? `${Math.max(percent(end) - percent(start), 0.6)}%` : 6,
                                            top: 2,
                                            height: 10,
                                            minWidth: 6,
                                            bgcolor: annotation.resolved ? '#94a3b8' : (annotation.style?.stroke_color || '#ef4444'),
                                            border: emphasised ? '2px solid #0f172a' : 'none',
                                            borderRadius: 0.5,
                                            cursor: 'pointer',
                                            transform: 'translateX(-50%)',
                                        }}
                                    />
                                </Tooltip>
                            );
                        })}
                    </Box>

                    <Slider
                        size="small"
                        min={0}
                        max={Math.max(totalFrames, 1)}
                        value={Math.min(currentFrame || 0, totalFrames)}
                        aria-label={translate('assetComments.video.scrubber', 'Video position')}
                        data-testid="video-scrubber"
                        onChange={(_event, value) => {
                            setScrubbing(true);
                            seekToFrame(value);
                        }}
                        onChangeCommitted={() => setScrubbing(false)}
                        sx={{ py: 1 }}
                    />
                </Box>

                <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, flexWrap: 'wrap' }}>
                    <Tooltip title={playing ? translate('assetComments.video.pause', 'Pause') : translate('assetComments.video.play', 'Play')}>
                        <IconButton
                            size="small"
                            onClick={togglePlay}
                            aria-label={playing ? translate('assetComments.video.pause', 'Pause') : translate('assetComments.video.play', 'Play')}
                        >
                            {playing ? <Pause fontSize="small" /> : <PlayArrow fontSize="small" />}
                        </IconButton>
                    </Tooltip>

                    <Tooltip title={translate('assetComments.video.previousFrame', 'Previous frame')}>
                        <IconButton
                            size="small"
                            onClick={() => step(-1)}
                            aria-label={translate('assetComments.video.previousFrame', 'Previous frame')}
                        >
                            <SkipPrevious fontSize="small" />
                        </IconButton>
                    </Tooltip>

                    <Tooltip title={translate('assetComments.video.nextFrame', 'Next frame')}>
                        <IconButton
                            size="small"
                            onClick={() => step(1)}
                            aria-label={translate('assetComments.video.nextFrame', 'Next frame')}
                        >
                            <SkipNext fontSize="small" />
                        </IconButton>
                    </Tooltip>

                    <Tooltip title={exactFrameRate
                        ? ''
                        : translate('assetComments.video.approximateRate', 'No frame rate was detected for this video, so frame stepping is approximate.')}>
                        <Typography
                            variant="caption"
                            data-testid="video-timecode"
                            sx={{
                                fontFamily: 'monospace',
                                fontSize: '0.75rem',
                                ml: 1,
                                color: exactFrameRate ? '#0f172a' : '#b45309',
                                whiteSpace: 'nowrap',
                            }}
                        >
                            {timecode} / {durationTimecode}
                        </Typography>
                    </Tooltip>

                    <Box sx={{ flexGrow: 1 }} />

                    <Tooltip title={translate('assetComments.video.setInHint', 'Set the in point of a range comment at the current frame')}>
                        <IconButton
                            size="small"
                            onClick={() => onSetIn?.(currentFrame || 0)}
                            aria-label={translate('assetComments.video.setIn', 'Set in point')}
                            sx={{ fontSize: '0.7rem', fontWeight: 700, color: inPoint != null ? '#2563eb' : undefined }}
                        >
                            {translate('assetComments.video.inShort', 'IN')}
                        </IconButton>
                    </Tooltip>

                    <Tooltip title={translate('assetComments.video.setOutHint', 'Set the out point of a range comment at the current frame')}>
                        <IconButton
                            size="small"
                            onClick={() => onSetOut?.(currentFrame || 0)}
                            aria-label={translate('assetComments.video.setOut', 'Set out point')}
                            sx={{ fontSize: '0.7rem', fontWeight: 700, color: outPoint != null ? '#2563eb' : undefined }}
                        >
                            {translate('assetComments.video.outShort', 'OUT')}
                        </IconButton>
                    </Tooltip>

                    {(inPoint != null || outPoint != null) && (
                        <>
                            <Typography variant="caption" data-testid="video-range-label" sx={{ fontFamily: 'monospace', color: '#2563eb' }}>
                                {framesToClock(inPoint ?? 0, fps)}–{outPoint != null ? framesToClock(outPoint, fps) : '…'}
                            </Typography>

                            <Tooltip title={translate('assetComments.video.loop', 'Loop the selected range')}>
                                <IconButton
                                    size="small"
                                    onClick={() => onToggleLoop?.(!loop)}
                                    aria-label={translate('assetComments.video.loop', 'Loop the selected range')}
                                    sx={{ color: loop ? '#2563eb' : undefined }}
                                >
                                    <LoopIcon fontSize="small" />
                                </IconButton>
                            </Tooltip>

                            <Tooltip title={translate('assetComments.video.clearRange', 'Clear the range')}>
                                <IconButton
                                    size="small"
                                    onClick={() => onClearRange?.()}
                                    aria-label={translate('assetComments.video.clearRange', 'Clear the range')}
                                >
                                    <ClearIcon fontSize="small" />
                                </IconButton>
                            </Tooltip>
                        </>
                    )}

                    <Tooltip title={muted ? translate('assetComments.video.unmute', 'Unmute') : translate('assetComments.video.mute', 'Mute')}>
                        <IconButton
                            size="small"
                            onClick={() => {
                                const next = !muted;
                                setMuted(next);
                                if (videoRef.current) videoRef.current.muted = next;
                            }}
                            aria-label={muted ? translate('assetComments.video.unmute', 'Unmute') : translate('assetComments.video.mute', 'Mute')}
                        >
                            {muted ? <VolumeOff fontSize="small" /> : <VolumeUp fontSize="small" />}
                        </IconButton>
                    </Tooltip>
                </Box>
            </Box>
        </Box>
    );
}
