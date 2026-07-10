import {
  is3DModel, isModelViewerRenderable, isThreeJsRenderable, is3DRenderable,
  MODEL_VIEWER_MIME_TYPES, THREE_JS_MIME_TYPES, UNRENDERABLE_3D_MIME_TYPES, THREE_D_MIME_TYPES,
} from '../../../app/javascript/utils/threeDMimeTypes';

describe('threeDMimeTypes', () => {
  it('recognises all six supported 3D MIME types as 3D models', () => {
    THREE_D_MIME_TYPES.forEach((mime) => expect(is3DModel(mime)).toBe(true));
    expect(THREE_D_MIME_TYPES).toHaveLength(6);
  });

  it('does not classify unrelated MIME types as 3D models', () => {
    expect(is3DModel('image/png')).toBe(false);
    expect(is3DModel('application/pdf')).toBe(false);
    expect(is3DModel(undefined)).toBe(false);
  });

  it('flags only GLB/GLTF as model-viewer renderable', () => {
    MODEL_VIEWER_MIME_TYPES.forEach((mime) => expect(isModelViewerRenderable(mime)).toBe(true));
    THREE_JS_MIME_TYPES.forEach((mime) => expect(isModelViewerRenderable(mime)).toBe(false));
    UNRENDERABLE_3D_MIME_TYPES.forEach((mime) => expect(isModelViewerRenderable(mime)).toBe(false));
  });

  it('flags only OBJ/STL as three.js renderable', () => {
    THREE_JS_MIME_TYPES.forEach((mime) => expect(isThreeJsRenderable(mime)).toBe(true));
    MODEL_VIEWER_MIME_TYPES.forEach((mime) => expect(isThreeJsRenderable(mime)).toBe(false));
    UNRENDERABLE_3D_MIME_TYPES.forEach((mime) => expect(isThreeJsRenderable(mime)).toBe(false));
  });

  it('flags USDZ and Adobe Dimension as 3D but not renderable in-page', () => {
    UNRENDERABLE_3D_MIME_TYPES.forEach((mime) => {
      expect(is3DModel(mime)).toBe(true);
      expect(is3DRenderable(mime)).toBe(false);
    });
  });

  it('is3DRenderable is true for every model-viewer or three.js format', () => {
    [...MODEL_VIEWER_MIME_TYPES, ...THREE_JS_MIME_TYPES].forEach((mime) => {
      expect(is3DRenderable(mime)).toBe(true);
    });
  });
});
