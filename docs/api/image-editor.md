# Image Editor Component Documentation

## Overview
The Image Editor is a comprehensive, full-featured image processing component for Capri DAM that allows users to adjust, transform, and export images with complete backend support for all modifications.

## Architecture

### Frontend
- **Component**: `app/javascript/components/Folders/ImageEditorDialog.jsx` (648 lines)
- **Framework**: React 19 with MUI v9
- **State Management**: React hooks (useState, useRef, useEffect)
- **i18n Support**: `useTranslation()` from react-i18next

### Backend
- **API Endpoint**: `POST /api/v1/assets/:id/process_image`
- **Controller**: `app/controllers/api/v1/assets_controller.rb`
- **Service Layer**: `app/services/image_processing_service.rb`
- **Processing Engine**: MiniMagick (ImageMagick wrapper)
- **Background Jobs**: Sidekiq (AssetProcessorWorker, CdnInvalidationWorker)

## Image Adjustment Capabilities

### Geometric Transformations
- **Rotation**: 0°, ±90°, ±180°, ±270° (any multiple of 90°)
- **Flip Horizontal**: Mirror image left-right
- **Flip Vertical**: Mirror image top-bottom
- **Focal Point**: Define crop center for responsive images (0-100% X & Y)
- **Crop Aspect Ratios**: Freeform, 1:1, 16:9, 4:3, 3:2, 21:9

### Lighting Adjustments
- **Brightness**: -100 to +100 (darker to brighter)
- **Contrast**: -100 to +100 (flatter to more defined)
- **Ultra HDR**: 0 to 100 (enhance mid-tone contrast)
- **White Point**: -100 to +100 (affect highlights)
- **Black Point**: -100 to +100 (affect shadows)
- **Highlights**: -100 to +100 (brighten/darken bright areas)
- **Shadows**: -100 to +100 (brighten/darken dark areas)

### Color Adjustments
- **Saturation**: -100 to +100 (grayscale to oversaturated)
- **Warmth/Temperature**: -100 to +100 (cool/blue to warm/yellow)
- **Tint/Hue**: -100 to +100 (hue rotation)
- **Skin Tone**: -100 to +100 (enhance warm face tones)
- **Blue Tone**: -100 to +100 (enhance cool/blue tones)

### Effects
- **Vignette**: 0 to 100 (darkened edges effect)

### Filters (LUT-based)
- **None** (identity)
- **Vivid** (high saturation)
- **West** (warm, vintage)
- **Palma** (film-like)
- **Metro** (urban)
- **Eiffel** (cool, moody)
- **Blush** (soft, romantic)
- **Modena** (vintage sepia)
- **Vogue** (high-contrast B&W)

### Advanced
- **Custom ImageMagick CLI**: Inject raw ImageMagick operators (e.g., `-blur 0x8`)

## Save Modes

### 1. **Version** (Default)
- Creates a new immutable version of the asset
- Preserves full version history
- Original active version remains unchanged
- Can optionally move to a different folder

### 2. **Overwrite** (Destructive)
- Replaces the current active version in-place
- **Warning**: Cannot be undone
- Useful for corrections and quick fixes

### 3. **New** (Fork)
- Creates a completely new independent asset
- Title appended with " (Copy)"
- Original asset remains unchanged
- Can be placed in a different folder

## API Reference

### Endpoint
```
POST /api/v1/assets/:id/process_image
```

### Request Payload
```json
{
  "save_mode": "version",
  "target_folder_id": null,
  "adjustments": {
    "brightness": 20,
    "contrast": -10,
    "saturation": 30,
    "warmth": 15,
    "tint": 5,
    "skin_tone": 0,
    "blue_tone": 0,
    "hdr": 0,
    "white_point": 0,
    "highlights": 0,
    "shadows": 0,
    "black_point": 0,
    "vignette": 0
  },
  "crop_aspect": "free",
  "filter": "None",
  "geometry": {
    "rotate": 0,
    "flip_horizontal": false,
    "flip_vertical": false,
    "focal_point": { "x": 50, "y": 50 }
  },
  "custom_cli": ""
}
```

### Response (Success)
```json
{
  "id": 123,
  "uuid": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Product Image v2",
  "version": 2,
  "metadata": {
    "storage_path": "/path/to/processed/image.jpg",
    "file_size": 245760,
    "editor_state": { ... }
  },
  "url": "https://cdn.example.com/assets/image-v2.jpg"
}
```

### Response (Error)
```json
{
  "error": "Invalid image parameters: brightness must be between -100 and 100"
}
```

### Status Codes
- **200 OK**: Image processed successfully (version/overwrite)
- **201 Created**: New asset created (save_mode: new)
- **400 Bad Request**: Invalid parameters
- **404 Not Found**: Asset not found
- **422 Unprocessable Entity**: File missing or processing failed

## Testing

### Running Tests
```bash
# Backend service tests
bundle exec rspec spec/services/image_processing_service_spec.rb

# Controller integration tests
bundle exec rspec spec/requests/api/v1/assets_spec.rb -k process_image

# Frontend component tests
yarn test ImageEditorDialog

# E2E tests
yarn playwright test spec/system/image_editor_spec.rb
```

## References

- [MiniMagick Documentation](https://github.com/minimagick/minimagick)
- [ImageMagick Documentation](https://imagemagick.org/)
