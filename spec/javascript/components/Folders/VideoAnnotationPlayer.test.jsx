import React from 'react';
import { render, screen, fireEvent, act } from '@testing-library/react';
import VideoAnnotationPlayer from '../../../../app/javascript/components/Folders/VideoAnnotationPlayer';

// jsdom implements no media pipeline: `duration` is NaN, `play()` is missing
// and `currentTime` never advances. These stubs give the component a media
// element that behaves enough like a real one to drive the transport.
function stubMediaElement(duration = 10) {
    Object.defineProperty(HTMLMediaElement.prototype, 'duration', {
        configurable: true,
        get() { return duration; },
    });

    let time = 0;
    Object.defineProperty(HTMLMediaElement.prototype, 'currentTime', {
        configurable: true,
        get() { return time; },
        set(value) { time = value; },
    });

    Object.defineProperty(HTMLMediaElement.prototype, 'paused', {
        configurable: true,
        get() { return true; },
    });

    HTMLMediaElement.prototype.play = jest.fn();
    HTMLMediaElement.prototype.pause = jest.fn();
}

const FPS = 25;

function renderPlayer(props = {}) {
    const onFrameChange = jest.fn();
    const utils = render(
        <VideoAnnotationPlayer
            src="/video.mp4"
            fps={FPS}
            onFrameChange={onFrameChange}
            {...props}
        />,
    );

    // The scrubber's range depends on the duration, which is only known after
    // the media element reports its metadata.
    act(() => {
        fireEvent.loadedMetadata(screen.getByTestId('asset-viewer-video-player'));
    });

    return { ...utils, onFrameChange };
}

beforeEach(() => {
    stubMediaElement(10);
    jest.clearAllMocks();
});

describe('VideoAnnotationPlayer', () => {
    it('renders its own transport rather than the native controls', () => {
        renderPlayer();

        // Native controls cannot host the marker track, which is the whole
        // point of replacing them.
        expect(screen.getByTestId('asset-viewer-video-player')).not.toHaveAttribute('controls');
        expect(screen.getByTestId('video-transport')).toBeInTheDocument();
        expect(screen.getByTestId('video-marker-track')).toBeInTheDocument();
    });

    it('reports the duration in frames to the scrubber', () => {
        renderPlayer();
        // 10s at 25fps.
        expect(screen.getByTestId('video-scrubber').querySelector('input'))
            .toHaveAttribute('max', '250');
    });

    it('shows an SMPTE timecode for the current position', () => {
        renderPlayer({ currentFrame: 30 });
        // Frame 30 at 25fps is 00:00:01:05.
        expect(screen.getByTestId('video-timecode')).toHaveTextContent('00:00:01:05');
    });

    it('uses drop-frame notation only for NTSC rates', () => {
        renderPlayer({ fps: 29.97, dropFrame: true, currentFrame: 0 });
        expect(screen.getByTestId('video-timecode')).toHaveTextContent('00:00:00;00');
    });

    it('steps one frame at a time, not one second', () => {
        const { onFrameChange } = renderPlayer({ currentFrame: 50 });

        fireEvent.click(screen.getByRole('button', { name: 'Next frame' }));
        expect(onFrameChange).toHaveBeenLastCalledWith(51);

        fireEvent.click(screen.getByRole('button', { name: 'Previous frame' }));
        expect(onFrameChange).toHaveBeenLastCalledWith(49);
    });

    it('never steps below frame zero', () => {
        const { onFrameChange } = renderPlayer({ currentFrame: 0 });
        fireEvent.click(screen.getByRole('button', { name: 'Previous frame' }));
        expect(onFrameChange).toHaveBeenLastCalledWith(0);
    });

    it('clamps a step past the end of the clip', () => {
        const { onFrameChange } = renderPlayer({ currentFrame: 250 });
        fireEvent.click(screen.getByRole('button', { name: 'Next frame' }));
        expect(onFrameChange).toHaveBeenLastCalledWith(250);
    });

    it('pauses before stepping, since stepping during playback is meaningless', () => {
        renderPlayer({ currentFrame: 10 });
        HTMLMediaElement.prototype.pause.mockClear();
        Object.defineProperty(HTMLMediaElement.prototype, 'paused', {
            configurable: true, get() { return false; },
        });

        fireEvent.click(screen.getByRole('button', { name: 'Next frame' }));
        expect(HTMLMediaElement.prototype.pause).toHaveBeenCalled();
    });

    it('seeks the media element to the middle of the target frame', () => {
        renderPlayer({ currentFrame: 0 });
        const video = screen.getByTestId('asset-viewer-video-player');

        fireEvent.click(screen.getByRole('button', { name: 'Next frame' }));
        // Frame 1 at 25fps, offset half a frame so the seek lands inside it.
        expect(video.currentTime).toBeCloseTo(1.5 / FPS, 5);
    });

    it('renders one marker per temporal annotation', () => {
        renderPlayer({
            annotations: [
                { id: 'a', thread_id: 't1', marker_label: '1', video: { start_frame: 25, end_frame: null } },
                { id: 'b', thread_id: 't2', marker_label: '2', video: { start_frame: 100, end_frame: 150 } },
            ],
        });

        expect(screen.getAllByTestId('video-marker')).toHaveLength(2);
    });

    it('draws a range marker as a bar spanning its span', () => {
        renderPlayer({
            annotations: [
                { id: 'b', thread_id: 't2', video: { start_frame: 100, end_frame: 150 } },
            ],
        });

        // 100/250 = 40%, spanning to 150/250 = 60%.
        const marker = screen.getByTestId('video-marker');
        expect(marker).toHaveStyle({ left: '40%', width: '20%' });
    });

    it('greys out a marker whose thread is resolved', () => {
        renderPlayer({
            annotations: [
                { id: 'a', thread_id: 't1', resolved: true, video: { start_frame: 25 } },
            ],
        });

        expect(screen.getByTestId('video-marker')).toHaveStyle({ backgroundColor: '#94a3b8' });
    });

    it('seeks and selects the thread when a marker is clicked', () => {
        const onSelectThread = jest.fn();
        const { onFrameChange } = renderPlayer({
            onSelectThread,
            annotations: [{ id: 'a', thread_id: 't1', video: { start_frame: 75 } }],
        });

        fireEvent.click(screen.getByTestId('video-marker'));

        expect(onFrameChange).toHaveBeenLastCalledWith(75);
        expect(onSelectThread).toHaveBeenCalledWith('t1');
    });

    it('captures in and out points at the current frame', () => {
        const onSetIn = jest.fn();
        const onSetOut = jest.fn();
        renderPlayer({ currentFrame: 60, onSetIn, onSetOut });

        fireEvent.click(screen.getByRole('button', { name: 'Set in point' }));
        fireEvent.click(screen.getByRole('button', { name: 'Set out point' }));

        expect(onSetIn).toHaveBeenCalledWith(60);
        expect(onSetOut).toHaveBeenCalledWith(60);
    });

    it('highlights the selected range on the timeline', () => {
        renderPlayer({ inPoint: 50, outPoint: 100 });

        expect(screen.getByTestId('video-range-highlight')).toHaveStyle({ left: '20%', width: '20%' });
        expect(screen.getByTestId('video-range-label')).toHaveTextContent('0:02–0:04');
    });

    it('hides the loop and clear controls until a range exists', () => {
        renderPlayer();
        expect(screen.queryByRole('button', { name: /Loop/ })).not.toBeInTheDocument();
        expect(screen.queryByTestId('video-range-highlight')).not.toBeInTheDocument();
    });

    it('toggles looping and clears the range', () => {
        const onToggleLoop = jest.fn();
        const onClearRange = jest.fn();
        renderPlayer({ inPoint: 50, outPoint: 100, onToggleLoop, onClearRange });

        fireEvent.click(screen.getByRole('button', { name: 'Loop the selected range' }));
        fireEvent.click(screen.getByRole('button', { name: 'Clear the range' }));

        expect(onToggleLoop).toHaveBeenCalledWith(true);
        expect(onClearRange).toHaveBeenCalled();
    });

    it('honours an external seek request', () => {
        const { rerender, onFrameChange } = renderPlayer({ seekRequest: null });

        rerender(
            <VideoAnnotationPlayer
                src="/video.mp4"
                fps={FPS}
                onFrameChange={onFrameChange}
                seekRequest={{ frame: 125, token: 1 }}
            />,
        );

        expect(onFrameChange).toHaveBeenLastCalledWith(125);
    });

    it('re-seeks when the same frame is requested again under a new token', () => {
        // A bare `frame` prop would not re-fire here, leaving the reviewer
        // stranded after scrubbing away and clicking the same chip.
        const { rerender, onFrameChange } = renderPlayer({ seekRequest: { frame: 40, token: 1 } });
        onFrameChange.mockClear();

        rerender(
            <VideoAnnotationPlayer
                src="/video.mp4"
                fps={FPS}
                onFrameChange={onFrameChange}
                seekRequest={{ frame: 40, token: 2 }}
            />,
        );

        expect(onFrameChange).toHaveBeenLastCalledWith(40);
    });

    it('warns when the frame rate could not be detected', () => {
        renderPlayer({ exactFrameRate: false });
        expect(screen.getByTestId('video-timecode')).toHaveStyle({ color: '#b45309' });
    });

    it('supports the standard NLE keyboard bindings', () => {
        const onSetIn = jest.fn();
        const onSetOut = jest.fn();
        const { onFrameChange } = renderPlayer({ currentFrame: 20, onSetIn, onSetOut });
        const player = screen.getByTestId('video-annotation-player');

        fireEvent.keyDown(player, { key: 'ArrowRight' });
        expect(onFrameChange).toHaveBeenLastCalledWith(21);

        fireEvent.keyDown(player, { key: 'i' });
        expect(onSetIn).toHaveBeenCalledWith(20);

        fireEvent.keyDown(player, { key: 'o' });
        expect(onSetOut).toHaveBeenCalledWith(20);

        fireEvent.keyDown(player, { key: 'k' });
        expect(HTMLMediaElement.prototype.play).toHaveBeenCalled();
    });

    it('ignores keys it does not own so they still reach the page', () => {
        renderPlayer();
        const player = screen.getByTestId('video-annotation-player');
        const event = new KeyboardEvent('keydown', { key: 'a', bubbles: true, cancelable: true });

        fireEvent(player, event);
        expect(event.defaultPrevented).toBe(false);
    });

    it('renders the annotation overlay passed as a child over the video', () => {
        renderPlayer({ children: <div data-testid="overlay-child" /> });
        expect(screen.getByTestId('overlay-child')).toBeInTheDocument();
    });

    it('reports the natural video dimensions once metadata loads', () => {
        const onLoadedMetadata = jest.fn();
        renderPlayer({ onLoadedMetadata });
        expect(onLoadedMetadata).toHaveBeenCalledWith({ width: 0, height: 0 });
    });
});
