import React, { useEffect, useRef, useState } from 'react';
import { Box, IconButton, Tooltip, Typography, Button, CircularProgress } from '@mui/material';
import {
    RestartAltOutlined, FullscreenOutlined, FullscreenExitOutlined,
    ViewInArOutlined, DownloadOutlined,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import '@google/model-viewer';
import {
    isModelViewerRenderable, isThreeJsRenderable,
} from '../../utils/threeDMimeTypes';

// Interactive 3D asset viewer.
//
// Two rendering strategies, matching what each format actually supports:
//   * GLB / GLTF — `<model-viewer>` (Google's web component, backed by
//     three.js internally) which ships built-in orbit/pan/zoom camera
//     controls, a "reset camera" API, and native fullscreen support.
//   * OBJ / STL — a lightweight custom three.js scene (OrbitControls),
//     since `<model-viewer>` only understands glTF/GLB.
//   * USDZ / Adobe Dimension (.dn) — no in-page WebGL renderer exists for
//     either format (USDZ is primarily an iOS AR Quick Look format; .dn is
//     Adobe's closed proprietary format with no public parser), so we show
//     an explanatory fallback with a "Download Original" call to action
//     instead of a broken/blank viewer.
//
// Camera controls (mouse / touch), matching the documented AEM 3D preview
// interaction model:
//   Orbit    — left-click + drag        / single-finger drag
//   Pan      — right-click + drag       / two-finger drag
//   Zoom     — scroll wheel             / two-finger pinch
//   Recenter — double-click             / double-tap
//   Reset    — dedicated Reset button (bottom-right)
//   Fullscreen — dedicated Fullscreen button (bottom-right)
export default function Asset3DViewer({ src, contentType, displayName }) {
    const { t } = useTranslation();
    const translate = (key, fallback) => {
        const value = t(key);
        return value === key ? fallback : value;
    };

    const containerRef = useRef(null);
    const modelViewerRef = useRef(null);
    const [isFullscreen, setIsFullscreen] = useState(false);

    const useModelViewer = isModelViewerRenderable(contentType);
    const useThreeJs = isThreeJsRenderable(contentType);
    const isRenderable = useModelViewer || useThreeJs;

    useEffect(() => {
        const handleFullscreenChange = () => {
            setIsFullscreen(Boolean(document.fullscreenElement));
        };
        document.addEventListener('fullscreenchange', handleFullscreenChange);
        return () => document.removeEventListener('fullscreenchange', handleFullscreenChange);
    }, []);

    const handleToggleFullscreen = async () => {
        if (!containerRef.current) return;
        try {
            if (document.fullscreenElement) {
                await document.exitFullscreen();
            } else {
                await containerRef.current.requestFullscreen();
            }
        } catch (_) { /* fullscreen API unsupported/blocked — non-critical */ }
    };

    const handleReset = () => {
        if (useModelViewer && modelViewerRef.current) {
            modelViewerRef.current.cameraOrbit = 'auto auto auto';
            modelViewerRef.current.cameraTarget = 'auto auto auto';
            modelViewerRef.current.fieldOfView = 'auto';
            modelViewerRef.current.jumpCameraToGoal?.();
        }
        // The three.js viewer listens for this custom event and restores its
        // own initial camera position/target (see ThreeJsModelCanvas below).
        containerRef.current?.dispatchEvent(new CustomEvent('reset-3d-camera'));
    };

    if (!isRenderable) {
        return (
            <Box sx={{
                display: 'flex', flexDirection: 'column', alignItems: 'center',
                justifyContent: 'center', gap: 2, p: 4, textAlign: 'center',
            }}>
                <ViewInArOutlined sx={{ fontSize: 64, color: '#94a3b8' }} />
                <Typography variant="body1" fontWeight={600} color="text.secondary">
                    {translate(
                        'assetViewer.viewer3d.unsupportedFormatTitle',
                        'Interactive 3D preview isn\u2019t available for this format.',
                    )}
                </Typography>
                <Typography variant="body2" color="text.secondary" sx={{ maxWidth: 420 }}>
                    {contentType === 'model/x-adobe-dn'
                        ? translate(
                            'assetViewer.viewer3d.unsupportedDnHint',
                            'Adobe Dimension (.dn) files can only be opened in Adobe Dimension. Download the original to view it.',
                        )
                        : translate(
                            'assetViewer.viewer3d.unsupportedUsdzHint',
                            'USDZ files are best viewed via AR Quick Look on a supported iOS device. Download the original to view it.',
                        )}
                </Typography>
                <Button
                    variant="outlined" startIcon={<DownloadOutlined />}
                    href={src} download
                    sx={{ textTransform: 'none' }}
                    data-testid="asset-3d-viewer-download-fallback"
                >
                    {translate('assetViewer.viewer3d.downloadOriginal', 'Download Original')}
                </Button>
            </Box>
        );
    }

    return (
        <Box
            ref={containerRef}
            data-testid="asset-3d-viewer"
            sx={{
                position: 'relative', width: '100%', height: '100%',
                bgcolor: isFullscreen ? '#0f172a' : 'transparent',
            }}
        >
            {useModelViewer ? (
                // eslint-disable-next-line react/no-unknown-property
                <model-viewer
                    ref={modelViewerRef}
                    data-testid="asset-3d-model-viewer"
                    src={src}
                    alt={displayName}
                    camera-controls="true"
                    touch-action="pan-y"
                    shadow-intensity="1"
                    exposure="1"
                    style={{ width: '100%', height: '100%', '--poster-color': 'transparent' }}
                >
                    <div slot="progress-bar" />
                </model-viewer>
            ) : (
                <ThreeJsModelCanvas src={src} contentType={contentType} containerRef={containerRef} />
            )}

            <Box sx={{
                position: 'absolute', bottom: 12, right: 12, display: 'flex', gap: 1,
                bgcolor: 'rgba(15, 23, 42, 0.55)', borderRadius: 2, p: 0.5,
            }}>
                <Tooltip title={translate('assetViewer.viewer3d.reset', 'Reset view')}>
                    <IconButton size="small" onClick={handleReset} sx={{ color: '#fff' }} data-testid="asset-3d-reset-button">
                        <RestartAltOutlined fontSize="small" />
                    </IconButton>
                </Tooltip>
                <Tooltip title={isFullscreen
                    ? translate('assetViewer.viewer3d.exitFullscreen', 'Exit fullscreen')
                    : translate('assetViewer.viewer3d.fullscreen', 'Fullscreen')}>
                    <IconButton size="small" onClick={handleToggleFullscreen} sx={{ color: '#fff' }} data-testid="asset-3d-fullscreen-button">
                        {isFullscreen ? <FullscreenExitOutlined fontSize="small" /> : <FullscreenOutlined fontSize="small" />}
                    </IconButton>
                </Tooltip>
            </Box>
        </Box>
    );
}

// Lightweight three.js scene for OBJ/STL — lazily loads `three` + the
// relevant loader (OBJLoader/STLLoader) + OrbitControls, mirroring the
// camera interaction model documented for the AEM 3D viewer (orbit via
// left-drag, pan via right-drag, zoom via wheel, all provided natively by
// OrbitControls).
function ThreeJsModelCanvas({ src, contentType, containerRef }) {
    const { t } = useTranslation();
    const translate = (key, fallback) => {
        const value = t(key);
        return value === key ? fallback : value;
    };
    const mountRef = useRef(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(false);

    useEffect(() => {
        let renderer;
        let animationFrameId;
        let controls;
        let camera;
        let resizeObserver;
        let cancelled = false;
        const initialState = { position: null, target: null };

        const handleReset = () => {
            if (!controls || !camera || !initialState.position) return;
            camera.position.copy(initialState.position);
            controls.target.copy(initialState.target);
            controls.update();
        };

        (async () => {
            try {
                const THREE = await import('three');
                const { OrbitControls } = await import('three/examples/jsm/controls/OrbitControls.js');

                if (cancelled || !mountRef.current) return;

                const mount = mountRef.current;
                const scene = new THREE.Scene();
                scene.background = new THREE.Color(0xf1f5f9);

                camera = new THREE.PerspectiveCamera(45, mount.clientWidth / mount.clientHeight, 0.1, 2000);
                camera.position.set(0, 0, 5);

                renderer = new THREE.WebGLRenderer({ antialias: true });
                renderer.setSize(mount.clientWidth, mount.clientHeight);
                mount.appendChild(renderer.domElement);

                scene.add(new THREE.AmbientLight(0xffffff, 0.7));
                const dirLight = new THREE.DirectionalLight(0xffffff, 0.8);
                dirLight.position.set(5, 10, 7.5);
                scene.add(dirLight);

                controls = new OrbitControls(camera, renderer.domElement);
                controls.enableDamping = true;

                let object;
                if (contentType === 'application/x-tgif') {
                    const { OBJLoader } = await import('three/examples/jsm/loaders/OBJLoader.js');
                    object = await new OBJLoader().loadAsync(src);
                } else {
                    const { STLLoader } = await import('three/examples/jsm/loaders/STLLoader.js');
                    const geometry = await new STLLoader().loadAsync(src);
                    const material = new THREE.MeshStandardMaterial({ color: 0x8899aa });
                    object = new THREE.Mesh(geometry, material);
                }

                if (cancelled) return;

                scene.add(object);

                // Frame the camera to the loaded object's bounding box so
                // arbitrarily-scaled models always appear centered and
                // reasonably sized (mirrors the AEM "Reset" behaviour).
                const box = new THREE.Box3().setFromObject(object);
                const size = box.getSize(new THREE.Vector3());
                const center = box.getCenter(new THREE.Vector3());
                const maxDim = Math.max(size.x, size.y, size.z) || 1;
                const distance = maxDim * 2;

                camera.position.set(center.x, center.y, center.z + distance);
                camera.near = distance / 100;
                camera.far = distance * 100;
                camera.updateProjectionMatrix();
                controls.target.copy(center);
                controls.update();

                initialState.position = camera.position.clone();
                initialState.target = center.clone();

                resizeObserver = new ResizeObserver(() => {
                    if (!mount || !renderer || !camera) return;
                    camera.aspect = mount.clientWidth / mount.clientHeight;
                    camera.updateProjectionMatrix();
                    renderer.setSize(mount.clientWidth, mount.clientHeight);
                });
                resizeObserver.observe(mount);

                const animate = () => {
                    animationFrameId = requestAnimationFrame(animate);
                    controls.update();
                    renderer.render(scene, camera);
                };
                animate();

                setLoading(false);
            } catch (e) {
                if (!cancelled) { setError(true); setLoading(false); }
            }
        })();

        const container = containerRef.current;
        container?.addEventListener('reset-3d-camera', handleReset);

        return () => {
            cancelled = true;
            container?.removeEventListener('reset-3d-camera', handleReset);
            resizeObserver?.disconnect();
            if (animationFrameId) cancelAnimationFrame(animationFrameId);
            if (renderer) {
                renderer.dispose();
                renderer.domElement?.remove();
            }
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [src, contentType]);

    if (error) {
        return (
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }}>
                <Typography color="error" variant="body2">
                    {translate('assetViewer.viewer3d.loadError', 'Failed to load the 3D model.')}
                </Typography>
            </Box>
        );
    }

    return (
        <Box sx={{ position: 'relative', width: '100%', height: '100%' }}>
            {loading && (
                <Box sx={{
                    position: 'absolute', inset: 0, display: 'flex',
                    alignItems: 'center', justifyContent: 'center', zIndex: 1,
                }}>
                    <CircularProgress size={32} />
                </Box>
            )}
            <Box ref={mountRef} data-testid="asset-3d-threejs-canvas" sx={{ width: '100%', height: '100%' }} />
        </Box>
    );
}
