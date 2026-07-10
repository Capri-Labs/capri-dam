// Central registry of 3D model file formats supported for interactive
// preview in the asset viewer. Mirrors `lib/three_d_mime_types.rb` on the
// backend — kept in sync manually, same convention as
// `webRenderableMimeTypes.js` (editable-image whitelist).
//
// Supported formats (matches Adobe Experience Manager's documented 3D
// preview matrix):
//   GLB   model/gltf-binary      — rendered via <model-viewer> (native orbit/pan/zoom)
//   GLTF  model/gltf+json        — rendered via <model-viewer>
//   OBJ   application/x-tgif     — rendered via a custom three.js scene
//   STL   application/vnd.ms-pki.stl — rendered via a custom three.js scene
//   USDZ  model/vnd.usdz+zip     — accepted for upload/delivery, but no
//                                  in-page WebGL renderer exists (it's an
//                                  iOS AR Quick Look format) — shows a
//                                  "download to view" fallback instead.
//   DN    model/x-adobe-dn       — Adobe Dimension; closed proprietary
//                                  format with no public parser — same
//                                  "download to view" fallback as USDZ.
export const MODEL_VIEWER_MIME_TYPES = [
  'model/gltf-binary',
  'model/gltf+json',
];

export const THREE_JS_MIME_TYPES = [
  'application/x-tgif',
  'application/vnd.ms-pki.stl',
];

export const UNRENDERABLE_3D_MIME_TYPES = [
  'model/vnd.usdz+zip',
  'model/x-adobe-dn',
];

export const THREE_D_MIME_TYPES = [
  ...MODEL_VIEWER_MIME_TYPES,
  ...THREE_JS_MIME_TYPES,
  ...UNRENDERABLE_3D_MIME_TYPES,
];

export function is3DModel(contentType) {
  return THREE_D_MIME_TYPES.includes(contentType);
}

export function isModelViewerRenderable(contentType) {
  return MODEL_VIEWER_MIME_TYPES.includes(contentType);
}

export function isThreeJsRenderable(contentType) {
  return THREE_JS_MIME_TYPES.includes(contentType);
}

export function is3DRenderable(contentType) {
  return isModelViewerRenderable(contentType) || isThreeJsRenderable(contentType);
}

export default is3DModel;
