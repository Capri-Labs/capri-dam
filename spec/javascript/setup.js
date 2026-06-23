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

