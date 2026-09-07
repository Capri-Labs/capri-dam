import {
    NTSC_DROP_FRAME_RATIOS,
    buildAnnotation,
    buildTemporal,
    frameRateContext,
    frameRateFromRatio,
    framesToClock,
    framesToSeconds,
    isTemporal,
    isVisibleAtFrame,
    secondsToFrames,
} from '../../../app/javascript/utils/annotationGeometry';

describe('frameRateFromRatio', () => {
    it('parses an ffprobe rational', () => {
        expect(frameRateFromRatio('30000/1001')).toBeCloseTo(29.97, 2);
        expect(frameRateFromRatio('25/1')).toBe(25);
    });

    it('accepts a bare integer rate', () => {
        expect(frameRateFromRatio('24')).toBe(24);
        expect(frameRateFromRatio(60)).toBe(60);
    });

    it('rejects the 0/0 placeholder ffprobe emits for rate-less streams', () => {
        expect(frameRateFromRatio('0/0')).toBeNull();
        expect(frameRateFromRatio('25/0')).toBeNull();
    });

    it('rejects blank and nonsense input', () => {
        expect(frameRateFromRatio(null)).toBeNull();
        expect(frameRateFromRatio('')).toBeNull();
        expect(frameRateFromRatio('abc')).toBeNull();
        expect(frameRateFromRatio(0)).toBeNull();
    });
});

describe('secondsToFrames / framesToSeconds', () => {
    it('floors to the frame actually on screen', () => {
        // At 1.999s of a 30fps clip the viewer sees frame 59, not frame 60.
        expect(secondsToFrames(1.999, 30)).toBe(59);
        expect(secondsToFrames(2.0, 30)).toBe(60);
    });

    it('never returns a negative frame', () => {
        expect(secondsToFrames(-1, 30)).toBe(0);
    });

    it('round-trips without drifting a frame earlier', () => {
        for (const frame of [0, 1, 59, 60, 1000]) {
            expect(secondsToFrames(framesToSeconds(frame, 30), 30)).toBe(frame);
        }
    });

    it('seeks into the middle of the frame, not onto its boundary', () => {
        // Landing exactly on the boundary leaves the previous frame on screen
        // in some browsers, so half a frame is added.
        expect(framesToSeconds(0, 30)).toBeCloseTo(0.5 / 30, 6);
    });

    it('returns null without a usable input', () => {
        expect(secondsToFrames(null, 30)).toBeNull();
        expect(secondsToFrames(1, 0)).toBeNull();
        expect(framesToSeconds(10, null)).toBeNull();
    });
});

describe('framesToClock', () => {
    it('formats sub-hour positions as m:ss', () => {
        expect(framesToClock(0, 30)).toBe('0:00');
        expect(framesToClock(45, 30)).toBe('0:01');
        expect(framesToClock(30 * 75, 30)).toBe('1:15');
    });

    it('adds an hours segment past the hour', () => {
        expect(framesToClock(30 * 3600, 30)).toBe('1:00:00');
        expect(framesToClock(30 * 3725, 30)).toBe('1:02:05');
    });

    it('returns null without a frame rate', () => {
        expect(framesToClock(10, null)).toBeNull();
    });
});

describe('frameRateContext', () => {
    it('prefers the exact rational over the rounded float', () => {
        const context = frameRateContext({
            video_frame_rate_ratio: '30000/1001',
            video_frame_rate: 29.97,
        });

        expect(context.fps).toBeCloseTo(29.97, 2);
        expect(context.exact).toBe(true);
    });

    it('flags NTSC rates as drop-frame', () => {
        for (const ratio of NTSC_DROP_FRAME_RATIOS) {
            expect(frameRateContext({ video_frame_rate_ratio: ratio }).dropFrame).toBe(true);
        }
    });

    it('does not treat a true 30 as drop-frame', () => {
        expect(frameRateContext({ video_frame_rate_ratio: '30/1' }).dropFrame).toBe(false);
    });

    it('falls back to a flagged approximation when no rate was extracted', () => {
        // Videos ingested before frame-rate extraction (or without FFmpeg)
        // must still be annotatable — just marked inexact.
        const context = frameRateContext({});
        expect(context.fps).toBe(25);
        expect(context.exact).toBe(false);
    });

    it('uses the stored float when only that is present', () => {
        const context = frameRateContext({ video_frame_rate: 48, video_drop_frame: false });
        expect(context.fps).toBe(48);
        expect(context.exact).toBe(true);
    });
});

describe('buildTemporal', () => {
    it('normalises a point in time', () => {
        expect(buildTemporal({ startFrame: 12.9, fps: 25, dropFrame: false })).toEqual({
            start_frame: 12,
            end_frame: null,
            fps: 25,
            drop_frame: false,
        });
    });

    it('keeps a genuine range', () => {
        expect(buildTemporal({ startFrame: 10, endFrame: 40, fps: 25 }).end_frame).toBe(40);
    });

    it('collapses a zero-length range to an instant', () => {
        expect(buildTemporal({ startFrame: 10, endFrame: 10, fps: 25 }).end_frame).toBeNull();
    });

    it('drops an inverted range rather than sending one the API rejects', () => {
        expect(buildTemporal({ startFrame: 40, endFrame: 10, fps: 25 }).end_frame).toBeNull();
    });

    it('refuses a frame with no frame rate, which the server would reject', () => {
        expect(buildTemporal({ startFrame: 10 })).toBeNull();
        expect(buildTemporal({ fps: 25 })).toBeNull();
        expect(buildTemporal(null)).toBeNull();
    });
});

describe('buildAnnotation with a video position', () => {
    const points = [{ x: 0.1, y: 0.1 }, { x: 0.5, y: 0.6 }];

    it('stamps drawn markup with the current frame', () => {
        const annotation = buildAnnotation('rect', points, { width: 1920, height: 1080 }, '#ef4444', {
            mediaType: 'video',
            video: { startFrame: 300, fps: 25, dropFrame: false },
        });

        expect(annotation.media_type).toBe('video');
        expect(annotation.video).toEqual({
            start_frame: 300, end_frame: null, fps: 25, drop_frame: false,
        });
    });

    it('omits the video block entirely for stills', () => {
        const annotation = buildAnnotation('rect', points, {}, '#ef4444');
        expect(annotation.media_type).toBe('image');
        expect(annotation.video).toBeUndefined();
    });

    it('still rejects a micro-drag on video', () => {
        const tiny = [{ x: 0.2, y: 0.2 }, { x: 0.2001, y: 0.2001 }];
        expect(buildAnnotation('rect', tiny, {}, '#ef4444', {
            mediaType: 'video',
            video: { startFrame: 10, fps: 25 },
        })).toBeNull();
    });
});

describe('isTemporal / isVisibleAtFrame', () => {
    const instant = { video: { start_frame: 100, end_frame: null } };
    const range = { video: { start_frame: 100, end_frame: 200 } };
    const still = { shape: 'rect' };

    it('identifies annotations that carry a frame', () => {
        expect(isTemporal(instant)).toBe(true);
        expect(isTemporal(still)).toBe(false);
        expect(isTemporal({ video: null })).toBe(false);
    });

    it('shows a range annotation for its whole span only', () => {
        expect(isVisibleAtFrame(range, 100)).toBe(true);
        expect(isVisibleAtFrame(range, 150)).toBe(true);
        expect(isVisibleAtFrame(range, 200)).toBe(true);
        expect(isVisibleAtFrame(range, 99)).toBe(false);
        expect(isVisibleAtFrame(range, 201)).toBe(false);
    });

    it('gives an instant annotation a visible window rather than one frame', () => {
        // A single frame at 30fps is on screen for 33ms; a marker that
        // flickers past that fast is useless.
        expect(isVisibleAtFrame(instant, 100)).toBe(true);
        expect(isVisibleAtFrame(instant, 110)).toBe(true);
        expect(isVisibleAtFrame(instant, 90)).toBe(true);
        expect(isVisibleAtFrame(instant, 130)).toBe(false);
    });

    it('always shows non-temporal annotations', () => {
        expect(isVisibleAtFrame(still, 5000)).toBe(true);
    });

    it('shows everything when there is no play head yet', () => {
        expect(isVisibleAtFrame(range, null)).toBe(true);
    });
});
