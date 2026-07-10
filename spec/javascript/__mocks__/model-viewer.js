// Jest mock for '@google/model-viewer'.
//
// The real package is a side-effect-only import that registers the
// <model-viewer> custom element and initializes WebGL via three.js
// internally. jsdom has no WebGL/canvas rendering support, and the
// package ships raw ESM that our Jest/Babel config doesn't transform,
// so tests mock it out entirely. Asset3DViewer only needs the
// <model-viewer> tag to exist as a valid (inert) custom element so it
// can render without throwing "unknown custom element" warnings.
if (typeof window !== 'undefined' && window.customElements && !window.customElements.get('model-viewer')) {
    class MockModelViewer extends HTMLElement {}
    window.customElements.define('model-viewer', MockModelViewer);
}
