import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import '@testing-library/jest-dom';
import { renderHook } from '@testing-library/react';

import useRegionChangeDetection from '../../../../app/javascript/components/Folders/useRegionChangeDetection';
import { LineageBadge } from '../../../../app/javascript/components/Folders/AssetCommentsPanel';

// Simple interpolating stand-in for i18next so assertions read naturally.
const translate = (_key, fallback, vars = {}) => Object.entries(vars)
    .reduce((text, [name, value]) => text.replace(`{{${name}}}`, value), fallback);

let loadedUrls;
let failUrls;

// Captured before any spy is installed; re-reading document.createElement
// inside a stub would capture the previous spy and recurse forever.
const nativeCreateElement = document.createElement.bind(document);

/** Images whose pixel content is decided by the URL, so a "version" can differ. */
function installImageStub() {
    loadedUrls = [];
    failUrls = new Set();

    global.Image = class {
        constructor() {
            this.naturalWidth = 200;
            this.naturalHeight = 200;
        }

        set src(value) {
            loadedUrls.push(value);
            this._src = value;
            setTimeout(() => {
                if (failUrls.has(value)) this.onerror?.(new Error('boom'));
                else this.onload?.();
            }, 0);
        }

        get src() { return this._src; }
    };
}

function installCanvasStub() {
    jest.spyOn(document, 'createElement').mockImplementation((tag, ...rest) => {
        if (tag !== 'canvas') return nativeCreateElement(tag, ...rest);

        const canvas = {
            width: 0,
            height: 0,
            _source: null,
            toDataURL: () => `data:image/png;stub-${canvas._source}`,
            getContext: () => ({
                drawImage: (image) => { canvas._source = image.src; },
                getImageData: (_x, _y, w, h) => {
                    // Every pixel encodes the URL's first character, so two
                    // different previews diff fully and the same preview twice
                    // diffs not at all.
                    const data = new Uint8ClampedArray(w * h * 4);
                    const tone = (canvas._source || '').includes('changed') ? 0 : 255;
                    data.fill(tone);
                    return { data, width: w, height: h };
                },
            }),
        };
        return canvas;
    });
}

const thread = (id, versionId, overrides = {}) => ({
    id,
    origin_version: { id: versionId, version_number: 2 },
    comments: [{ id: `c-${id}`, annotations: [{ bbox: { x: 0.2, y: 0.2, w: 0.3, h: 0.3 }, media_type: 'image' }] }],
    ...overrides,
});

const VERSIONS = [
    { id: 'v2', version_number: 2, is_active: false, preview_url: '/previews/v2.png' },
    { id: 'v3', version_number: 3, is_active: true, preview_url: '/previews/v3-changed.png' },
];

beforeEach(() => {
    installImageStub();
    installCanvasStub();
});

afterEach(() => {
    jest.restoreAllMocks();
});

describe('useRegionChangeDetection', () => {
    it('reports a region that differs between the two versions as changed', async () => {
        const { result } = renderHook(() => useRegionChangeDetection({
            threads: [thread('t1', 'v2')],
            versions: VERSIONS,
        }));

        await waitFor(() => expect(result.current.t1).toBeDefined());

        expect(result.current.t1.status).toBe('changed');
        expect(result.current.t1.fromVersion).toBe(2);
        expect(result.current.t1.toVersion).toBe(3);
    });

    it('reports an identical region as unchanged', async () => {
        const versions = [
            { id: 'v2', version_number: 2, is_active: false, preview_url: '/previews/v2.png' },
            { id: 'v3', version_number: 3, is_active: true, preview_url: '/previews/v3.png' },
        ];

        const { result } = renderHook(() => useRegionChangeDetection({
            threads: [thread('t1', 'v2')],
            versions,
        }));

        await waitFor(() => expect(result.current.t1).toBeDefined());
        expect(result.current.t1.status).toBe('unchanged');
    });

    it('skips a thread written against the version being viewed', async () => {
        // There is no "before" to compare against, only a "now".
        const { result } = renderHook(() => useRegionChangeDetection({
            threads: [thread('t1', 'v3')],
            versions: VERSIONS,
        }));

        await waitFor(() => expect(loadedUrls.length).toBe(0));
        expect(result.current.t1).toBeUndefined();
    });

    it('skips threads with no spatial anchor', async () => {
        const plain = { id: 't1', origin_version: { id: 'v2', version_number: 2 }, comments: [{ id: 'c1', annotations: [] }] };

        const { result } = renderHook(() => useRegionChangeDetection({ threads: [plain], versions: VERSIONS }));

        await waitFor(() => expect(loadedUrls.length).toBe(0));
        expect(result.current.t1).toBeUndefined();
    });

    it('skips video annotations, where a still comparison is meaningless', async () => {
        const video = thread('t1', 'v2', {
            comments: [{ id: 'c1', annotations: [{ bbox: { x: 0.2, y: 0.2, w: 0.3, h: 0.3 }, media_type: 'video', start_frame: 120 }] }],
        });

        const { result } = renderHook(() => useRegionChangeDetection({ threads: [video], versions: VERSIONS }));

        await waitFor(() => expect(loadedUrls.length).toBe(0));
        expect(result.current.t1).toBeUndefined();
    });

    it('does no work at all when disabled', async () => {
        renderHook(() => useRegionChangeDetection({
            threads: [thread('t1', 'v2')],
            versions: VERSIONS,
            enabled: false,
        }));

        await waitFor(() => expect(loadedUrls.length).toBe(0));
    });

    it('loads each preview once no matter how many threads share it', async () => {
        const threads = ['t1', 't2', 't3', 't4'].map((id) => thread(id, 'v2'));

        const { result } = renderHook(() => useRegionChangeDetection({ threads, versions: VERSIONS }));

        await waitFor(() => expect(Object.keys(result.current)).toHaveLength(4));
        // Four threads, two versions: two loads, not eight.
        expect(new Set(loadedUrls).size).toBe(2);
        expect(loadedUrls).toHaveLength(2);
    });

    it('degrades to unavailable when a preview cannot be loaded', async () => {
        failUrls.add('/previews/v2.png');

        const { result } = renderHook(() => useRegionChangeDetection({
            threads: [thread('t1', 'v2')],
            versions: VERSIONS,
        }));

        await waitFor(() => expect(result.current.t1).toBeDefined());
        expect(result.current.t1).toMatchObject({ status: 'unavailable', reason: 'load-failed' });
    });

    it('reports cross-origin taint distinctly, since that is a deployment fact', async () => {
        jest.spyOn(document, 'createElement').mockImplementation((tag, ...rest) => {
            if (tag !== 'canvas') return nativeCreateElement(tag, ...rest);

            return {
                width: 0,
                height: 0,
                getContext: () => ({
                    drawImage: () => {},
                    getImageData: () => {
                        const error = new Error('The canvas has been tainted by cross-origin data.');
                        error.name = 'SecurityError';
                        throw error;
                    },
                }),
            };
        });

        const { result } = renderHook(() => useRegionChangeDetection({
            threads: [thread('t1', 'v2')],
            versions: VERSIONS,
        }));

        await waitFor(() => expect(result.current.t1).toBeDefined());
        expect(result.current.t1).toMatchObject({ status: 'unavailable', reason: 'cross-origin' });
    });

    it('yields nothing when there is no active version to compare against', async () => {
        const { result } = renderHook(() => useRegionChangeDetection({
            threads: [thread('t1', 'v2')],
            versions: [{ id: 'v2', version_number: 2, is_active: false, preview_url: '/previews/v2.png' }],
        }));

        await waitFor(() => expect(loadedUrls.length).toBe(0));
        expect(result.current).toEqual({});
    });

    it('tolerates missing threads and versions', () => {
        const { result } = renderHook(() => useRegionChangeDetection({ threads: null, versions: null }));
        expect(result.current).toEqual({});
    });
});

describe('LineageBadge', () => {
    it('renders nothing when there is no comparison for the thread', () => {
        const { container } = render(<LineageBadge lineage={null} translate={translate} />);
        expect(container).toBeEmptyDOMElement();
    });

    it('names the version the region changed in', () => {
        render(<LineageBadge translate={translate} lineage={{ status: 'changed', ratio: 0.42, fromVersion: 2, toVersion: 3 }} />);

        expect(screen.getByTestId('thread-lineage-badge')).toHaveTextContent('Changed in v3');
    });

    it('names the version a region has been unchanged since', () => {
        render(<LineageBadge translate={translate} lineage={{ status: 'unchanged', ratio: 0, fromVersion: 2, toVersion: 3 }} />);

        expect(screen.getByTestId('thread-lineage-badge')).toHaveTextContent('Unchanged since v2');
    });

    it('says "changed", never "fixed" — the human verification still stands', () => {
        render(<LineageBadge translate={translate} lineage={{ status: 'changed', ratio: 0.42, fromVersion: 2, toVersion: 3 }} />);

        expect(screen.getByTestId('thread-lineage-badge')).not.toHaveTextContent(/fixed|resolved/i);
    });

    it('shows a neutral badge when the comparison could not run', () => {
        render(<LineageBadge translate={translate} lineage={{ status: 'unavailable', reason: 'cross-origin' }} />);

        expect(screen.getByTestId('thread-lineage-badge')).toHaveTextContent('Not compared');
    });

    it('reveals before and after crops on click', () => {
        render(<LineageBadge
            translate={translate}
            lineage={{
                status: 'changed', ratio: 0.4, fromVersion: 2, toVersion: 3, beforeCrop: 'data:image/png;a', afterCrop: 'data:image/png;b',
            }}
        />);

        expect(screen.queryByTestId('thread-lineage-crops')).not.toBeInTheDocument();

        fireEvent.click(screen.getByTestId('thread-lineage-badge'));

        const crops = screen.getByTestId('thread-lineage-crops');
        expect(crops).toBeInTheDocument();
        expect(screen.getByAltText('Before (v2)')).toHaveAttribute('src', 'data:image/png;a');
        expect(screen.getByAltText('After (v3)')).toHaveAttribute('src', 'data:image/png;b');
    });

    it('does not toggle the surrounding thread when the crops are opened', () => {
        const onSelect = jest.fn();

        render(
            <div onClick={onSelect} role="presentation">
                <LineageBadge
                    translate={translate}
                    lineage={{
                        status: 'changed', ratio: 0.4, fromVersion: 2, toVersion: 3, beforeCrop: 'a', afterCrop: 'b',
                    }}
                />
            </div>,
        );

        fireEvent.click(screen.getByTestId('thread-lineage-badge'));

        expect(screen.getByTestId('thread-lineage-crops')).toBeInTheDocument();
        expect(onSelect).not.toHaveBeenCalled();
    });

    it('is not clickable when no crops are available', () => {
        render(<LineageBadge translate={translate} lineage={{ status: 'changed', ratio: 0.4, fromVersion: 2, toVersion: 3 }} />);

        fireEvent.click(screen.getByTestId('thread-lineage-badge'));

        expect(screen.queryByTestId('thread-lineage-crops')).not.toBeInTheDocument();
    });
});
