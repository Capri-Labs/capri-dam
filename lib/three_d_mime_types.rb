# Central registry of 3D model file formats supported for interactive preview
# in the asset viewer, mirroring Adobe Experience Manager's documented 3D
# preview format matrix (GLB, GLTF, OBJ, STL, DN, USDZ).
#
# @see AssetProcessorWorker for where these tag uploaded 3D assets with a
#   +format: "3D Model"+ metadata marker (no server-side preview image is
#   generated — the browser renders the model live via `<model-viewer>` or
#   three.js instead).
# @see Api::V1::BinController#derive_media_type for the "model_3d" media-type
#   bucket used across the bin/grid/list icon logic.
# @see app/javascript/utils/threeDMimeTypes.js — the frontend mirror of this
#   list (kept in sync manually, same convention as WEB_RENDERABLE_MIME_TYPES).
module ThreeDMimeTypes
  # MIME type => canonical file extension (without dot).
  MIME_TO_EXTENSION = {
    "model/gltf-binary" => "glb",
    "model/gltf+json"   => "gltf",
    "application/x-tgif" => "obj",
    "application/vnd.ms-pki.stl" => "stl",
    "model/x-adobe-dn"  => "dn",
    "model/vnd.usdz+zip" => "usdz",
  }.freeze

  ALL = MIME_TO_EXTENSION.keys.freeze

  # Formats that `<model-viewer>` (Google's web component, backed by
  # three.js's glTF pipeline) can render directly in-page with full
  # orbit/pan/zoom camera controls.
  MODEL_VIEWER_MIME_TYPES = %w[model/gltf-binary model/gltf+json].freeze

  # Formats rendered via a custom three.js scene (OrbitControls) since
  # `<model-viewer>` only understands glTF/GLB.
  THREE_JS_MIME_TYPES = %w[application/x-tgif application/vnd.ms-pki.stl].freeze

  # USDZ has no broadly-supported in-page WebGL renderer (it's primarily an
  # iOS AR Quick Look format); Adobe Dimension (.dn) is a closed proprietary
  # format with no public parser. Both are accepted for upload/storage/
  # delivery but fall back to a "preview unavailable — download to view"
  # message in the asset viewer rather than a broken/blank viewer.
  UNRENDERABLE_MIME_TYPES = %w[model/vnd.usdz+zip model/x-adobe-dn].freeze

  # @param content_type [String, nil]
  # @return [Boolean] true when the MIME type is one of the six supported 3D formats
  def self.model_3d?(content_type)
    ALL.include?(content_type.to_s)
  end

  # @param content_type [String, nil]
  # @return [Boolean] true when an interactive in-page 3D viewer can render this format
  def self.renderable?(content_type)
    MODEL_VIEWER_MIME_TYPES.include?(content_type.to_s) || THREE_JS_MIME_TYPES.include?(content_type.to_s)
  end
end
