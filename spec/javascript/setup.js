// Jest global setup — registers jest-dom matchers and stubs browser APIs that
// jsdom does not implement but MUI/React components rely on.
import '@testing-library/jest-dom';

// MUI relies on matchMedia for responsive logic.
if (!window.matchMedia) {
  window.matchMedia = (query) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false
  });
}

// Provide a default fetch stub so component mounts don't explode; individual
// tests override this with their own mock.
if (!global.fetch) {
  global.fetch = () => Promise.resolve({ ok: true, json: () => Promise.resolve([]) });
}

// jsdom does not implement scrollIntoView, but chat-style components call it on
// a ref after each render. Provide a no-op so those effects don't throw.
if (!window.HTMLElement.prototype.scrollIntoView) {
  window.HTMLElement.prototype.scrollIntoView = () => {};
}

// jsdom does not implement clipboard; some components copy URLs/responses.
if (!navigator.clipboard) {
  Object.defineProperty(navigator, 'clipboard', {
    value: { writeText: () => Promise.resolve() },
    writable: true,
  });
}

