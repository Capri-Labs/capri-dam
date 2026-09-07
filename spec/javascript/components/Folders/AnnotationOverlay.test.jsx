import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import AnnotationOverlay from '../../../../app/javascript/components/Folders/AnnotationOverlay';

// The overlay projects normalised 0..1 geometry onto whatever size the media is
// actually rendered at, so every test has to give jsdom (which reports 0×0 for
// everything) a believable box to measure.
const RENDERED = { left: 0, top: 0, width: 800, height: 400 };

let boundingRectSpy;

beforeEach(() => {
    boundingRectSpy = jest
        .spyOn(window.HTMLElement.prototype, 'getBoundingClientRect')
        .mockReturnValue({ ...RENDERED, right: 800, bottom: 400, x: 0, y: 0, toJSON: () => {} });
});

afterEach(() => {
    boundingRectSpy.mockRestore();
});

const rectAnnotation = {
    id: 'a1',
    thread_id: 't1',
    shape: 'rect',
    bbox: { x: 0.25, y: 0.5, w: 0.5, h: 0.25 },
    style: { stroke_color: '#ef4444', stroke_width: 0.004 },
};

describe('AnnotationOverlay rendering', () => {
    it('projects a normalised bbox onto the rendered pixel size', () => {
        const { container } = render(<AnnotationOverlay annotations={[rectAnnotation]} />);

        // 0.25 * 800 = 200, 0.5 * 400 = 200, 0.5 * 800 = 400, 0.25 * 400 = 100
        const drawn = container.querySelectorAll('rect[rx="2"]')[0];
        expect(drawn).toHaveAttribute('x', '200');
        expect(drawn).toHaveAttribute('y', '200');
        expect(drawn).toHaveAttribute('width', '400');
        expect(drawn).toHaveAttribute('height', '100');
    });

    it('renders a freehand path in its stored 0..1 space and scales it with a transform', () => {
        const { container } = render(
            <AnnotationOverlay
                annotations={[{
                    id: 'a2',
                    thread_id: 't2',
                    shape: 'freehand',
                    bbox: { x: 0.1, y: 0.1, w: 0.3, h: 0.2 },
                    svg_path: 'M0.1,0.1 L0.4,0.3',
                }]}
            />,
        );

        const group = container.querySelector('g[transform="scale(800 400)"]');
        expect(group).toBeInTheDocument();

        const path = group.querySelectorAll('path')[1];
        // The path itself is untouched — only the transform changes.
        expect(path).toHaveAttribute('d', 'M0.1,0.1 L0.4,0.3');
        expect(path).toHaveAttribute('vector-effect', 'non-scaling-stroke');
    });

    it('draws a marker label on a pin', () => {
        render(
            <AnnotationOverlay
                annotations={[{
                    id: 'a3', thread_id: 't3', shape: 'pin', marker_label: '2',
                    bbox: { x: 0.5, y: 0.5, w: 0, h: 0 },
                }]}
            />,
        );

        expect(screen.getByText('2')).toBeInTheDocument();
    });

    it('renders pending draft annotations alongside saved ones, dashed', () => {
        const { container } = render(
            <AnnotationOverlay
                annotations={[rectAnnotation]}
                draft={[{ shape: 'rect', bbox: { x: 0, y: 0, w: 0.1, h: 0.1 } }]}
            />,
        );

        const outlines = container.querySelectorAll('rect[rx="2"]');
        expect(outlines).toHaveLength(2);
        expect(outlines[1]).toHaveAttribute('stroke-dasharray');
    });
});

describe('AnnotationOverlay interaction', () => {
    it('stays click-through until a tool is armed', () => {
        const { rerender } = render(<AnnotationOverlay annotations={[rectAnnotation]} />);
        expect(screen.getByTestId('annotation-overlay')).toHaveStyle({ pointerEvents: 'none' });

        rerender(<AnnotationOverlay annotations={[rectAnnotation]} tool="rect" />);
        expect(screen.getByTestId('annotation-overlay')).toHaveStyle({ pointerEvents: 'auto' });
    });

    it('emits a pin from a single click', () => {
        const onDraftAdd = jest.fn();
        render(<AnnotationOverlay tool="pin" onDraftAdd={onDraftAdd} sourceSize={{ width: 4000, height: 3000 }} />);

        fireEvent.pointerDown(screen.getByTestId('annotation-overlay'), { clientX: 400, clientY: 100 });

        expect(onDraftAdd).toHaveBeenCalledTimes(1);
        expect(onDraftAdd.mock.calls[0][0]).toMatchObject({
            shape: 'pin',
            bbox: { x: 0.5, y: 0.25, w: 0, h: 0 },
            source: { width: 4000, height: 3000, rotation: 0 },
        });
    });

    it('emits a normalised rectangle from a drag', () => {
        const onDraftAdd = jest.fn();
        render(<AnnotationOverlay tool="rect" onDraftAdd={onDraftAdd} />);
        const overlay = screen.getByTestId('annotation-overlay');

        fireEvent.pointerDown(overlay, { clientX: 200, clientY: 100, pointerId: 1 });
        fireEvent.pointerMove(overlay, { clientX: 600, clientY: 300, pointerId: 1 });
        fireEvent.pointerUp(overlay, { clientX: 600, clientY: 300, pointerId: 1 });

        expect(onDraftAdd).toHaveBeenCalledWith(expect.objectContaining({
            shape: 'rect',
            bbox: { x: 0.25, y: 0.25, w: 0.5, h: 0.5 },
        }));
    });

    it('does not emit an accidental micro-drag', () => {
        const onDraftAdd = jest.fn();
        render(<AnnotationOverlay tool="rect" onDraftAdd={onDraftAdd} />);
        const overlay = screen.getByTestId('annotation-overlay');

        fireEvent.pointerDown(overlay, { clientX: 200, clientY: 100, pointerId: 1 });
        fireEvent.pointerUp(overlay, { clientX: 200, clientY: 100, pointerId: 1 });

        expect(onDraftAdd).not.toHaveBeenCalled();
    });

    it('selects the owning thread when a marker is clicked', () => {
        const onSelectThread = jest.fn();
        const { container } = render(
            <AnnotationOverlay annotations={[rectAnnotation]} onSelectThread={onSelectThread} />,
        );

        fireEvent.click(container.querySelector('rect[rx="2"]'));

        expect(onSelectThread).toHaveBeenCalledWith('t1');
    });

    it('does not hijack marker clicks while drawing', () => {
        const onSelectThread = jest.fn();
        const { container } = render(
            <AnnotationOverlay annotations={[rectAnnotation]} tool="rect" onSelectThread={onSelectThread} />,
        );

        fireEvent.click(container.querySelector('rect[rx="2"]'));

        expect(onSelectThread).not.toHaveBeenCalled();
    });
});
