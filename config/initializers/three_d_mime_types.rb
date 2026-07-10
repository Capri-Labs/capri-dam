# Marcel (the MIME-sniffing library ActiveStorage / our own upload pipeline
# uses via `Marcel::MimeType.for`) has no built-in knowledge of the 3D file
# formats supported by the interactive 3D asset viewer (see
# lib/three_d_mime_types.rb) — without this registration, uploads of these
# formats fall back to the generic `application/octet-stream`/`application/zip`
# bucket, and the 3D viewer / media-type classification never kicks in.
#
# `Marcel::MimeType.extend` teaches Marcel to recognise the file extension
# (used since `AssetProcessorWorker` calls `Marcel::MimeType.for(..., name:)`
# with the uploaded file's basename).
#
# USDZ is a special case: it's literally a ZIP archive under the hood, so
# Marcel's magic-byte sniffer detects it as `application/zip` first. Declaring
# `parents: %w[application/zip]` tells Marcel's specificity resolver that our
# USDZ type is a *more specific* child of `application/zip`, so the
# extension-derived type wins over the generic ZIP detection.
#
# Required explicitly (rather than relying on Zeitwerk) because initializers
# run before the `lib/` autoload paths are guaranteed to be resolvable for
# top-level constant references.
require Rails.root.join("lib/three_d_mime_types")

ThreeDMimeTypes::MIME_TO_EXTENSION.each do |mime_type, extension|
  Marcel::MimeType.extend(
    mime_type,
    extensions: [ extension ],
    parents: (mime_type == "model/vnd.usdz+zip" ? %w[application/zip] : [])
  )
end
