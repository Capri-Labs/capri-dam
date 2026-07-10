import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import Asset3DViewer from '../../../../app/javascript/components/Folders/Asset3DViewer';

// `@google/model-viewer` is mocked globally (see spec/javascript/__mocks__/model-viewer.js,
// wired via jest.config moduleNameMapper) since the real package is ESM-only and
// initializes WebGL, neither of which jsdom supports.
//
// The three.js path (OBJ/STL) is loaded via dynamic `import('three')` /
// `import('three/examples/jsm/...')` at runtime inside a useEffect. Those are real
// ESM packages that our Jest config does not transform, so in jsdom the dynamic
// import rejects and Asset3DViewer's own try/catch surfaces its "Failed to load"
// error state — which is exactly the behaviour we assert below, without needing to
// mock three.js internals.

describe('Asset3DViewer', () => {
  it('renders <model-viewer> with camera-controls for GLB content', () => {
    render(<Asset3DViewer src="/models/hero.glb" contentType="model/gltf-binary" displayName="Hero Model" />);

    expect(screen.getByTestId('asset-3d-viewer')).toBeInTheDocument();
    const modelViewer = screen.getByTestId('asset-3d-model-viewer');
    expect(modelViewer).toBeInTheDocument();
    expect(modelViewer.tagName.toLowerCase()).toBe('model-viewer');
    expect(modelViewer.getAttribute('camera-controls')).toBe('true');
    expect(modelViewer.getAttribute('src')).toBe('/models/hero.glb');
    expect(screen.queryByTestId('asset-3d-threejs-canvas')).not.toBeInTheDocument();
    expect(screen.queryByTestId('asset-3d-viewer-download-fallback')).not.toBeInTheDocument();
  });

  it('renders <model-viewer> for GLTF content', () => {
    render(<Asset3DViewer src="/models/hero.gltf" contentType="model/gltf+json" displayName="Hero Model" />);

    expect(screen.getByTestId('asset-3d-model-viewer')).toBeInTheDocument();
  });

  it('renders the three.js canvas branch (not model-viewer) for OBJ content', async () => {
    const { unmount } = render(<Asset3DViewer src="/models/hero.obj" contentType="application/x-tgif" displayName="Hero Model" />);

    expect(screen.getByTestId('asset-3d-viewer')).toBeInTheDocument();
    expect(screen.queryByTestId('asset-3d-model-viewer')).not.toBeInTheDocument();

    // Let the async dynamic-import chain settle (it rejects in jsdom, since
    // there's no WebGL) before unmounting, to avoid an out-of-act warning.
    await waitFor(() => expect(screen.getByText(/Failed to load the 3D model/i)).toBeInTheDocument());
    unmount();
  });

  it('renders the three.js canvas branch (not model-viewer) for STL content', async () => {
    const { unmount } = render(<Asset3DViewer src="/models/hero.stl" contentType="application/vnd.ms-pki.stl" displayName="Hero Model" />);

    expect(screen.getByTestId('asset-3d-viewer')).toBeInTheDocument();
    expect(screen.queryByTestId('asset-3d-model-viewer')).not.toBeInTheDocument();

    await waitFor(() => expect(screen.getByText(/Failed to load the 3D model/i)).toBeInTheDocument());
    unmount();
  });

  it('falls back to a Download Original message for USDZ (no in-page WebGL renderer)', () => {
    render(<Asset3DViewer src="/models/hero.usdz" contentType="model/vnd.usdz+zip" displayName="Hero Model" />);

    expect(screen.queryByTestId('asset-3d-viewer')).not.toBeInTheDocument();
    const downloadLink = screen.getByTestId('asset-3d-viewer-download-fallback');
    expect(downloadLink).toBeInTheDocument();
    expect(downloadLink).toHaveAttribute('href', '/models/hero.usdz');
    expect(screen.getByText(/AR Quick Look/i)).toBeInTheDocument();
  });

  it('falls back to a Download Original message for Adobe Dimension (.dn) files', () => {
    render(<Asset3DViewer src="/models/hero.dn" contentType="model/x-adobe-dn" displayName="Hero Model" />);

    expect(screen.queryByTestId('asset-3d-viewer')).not.toBeInTheDocument();
    expect(screen.getByTestId('asset-3d-viewer-download-fallback')).toHaveAttribute('href', '/models/hero.dn');
    expect(screen.getByText(/Adobe Dimension/i)).toBeInTheDocument();
  });

  it('resets the model-viewer camera when the Reset button is clicked', () => {
    render(<Asset3DViewer src="/models/hero.glb" contentType="model/gltf-binary" displayName="Hero Model" />);

    const modelViewer = screen.getByTestId('asset-3d-model-viewer');
    modelViewer.jumpCameraToGoal = jest.fn();
    modelViewer.cameraOrbit = '10deg 20deg 3m';

    fireEvent.click(screen.getByTestId('asset-3d-reset-button'));

    expect(modelViewer.cameraOrbit).toBe('auto auto auto');
    expect(modelViewer.cameraTarget).toBe('auto auto auto');
    expect(modelViewer.fieldOfView).toBe('auto');
    expect(modelViewer.jumpCameraToGoal).toHaveBeenCalled();
  });

  it('toggles fullscreen via the Fullscreen button using the Fullscreen API', async () => {
    const requestFullscreen = jest.fn().mockResolvedValue(undefined);
    Element.prototype.requestFullscreen = requestFullscreen;

    render(<Asset3DViewer src="/models/hero.glb" contentType="model/gltf-binary" displayName="Hero Model" />);

    fireEvent.click(screen.getByTestId('asset-3d-fullscreen-button'));

    await waitFor(() => expect(requestFullscreen).toHaveBeenCalled());
  });
});

