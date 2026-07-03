// MIME types a browser can decode natively in an <img> tag (JPEG/PNG/GIF/WebP/
// SVG/AVIF). Mirrors the backend `AssetProcessorWorker::WEB_RENDERABLE_MIME_TYPES`
// constant — kept in sync manually, same as `embeddedMetadataMapper.js`.
//
// Formats outside this list (PSD, TIFF, HEIC, RAW, PDF, AI, EPS, …) only have a
// flattened PNG *preview* generated server-side; the interactive Image Editor's
// live preview needs to render the *original* file directly, so editing is
// disabled for those formats rather than silently baking adjustments onto a
// flattened copy that doesn't match what the user would see.
export const WEB_RENDERABLE_MIME_TYPES = [
  'image/jpeg',
  'image/jpg',
  'image/pjpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/svg+xml',
  'image/avif',
];

export function isWebRenderableImage(contentType) {
  return WEB_RENDERABLE_MIME_TYPES.includes(contentType);
}

export default isWebRenderableImage;
