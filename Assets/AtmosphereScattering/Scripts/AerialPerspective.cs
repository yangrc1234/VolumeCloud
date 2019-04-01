using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Yangrc.AtmosphereScattering {

    public class AerialPerspective : MonoBehaviour {
        private new Camera camera;
        private void Start() {
            camera = GetComponent<Camera>();
            if ((camera.depthTextureMode & DepthTextureMode.Depth) == 0)
                camera.depthTextureMode |= DepthTextureMode.Depth;
            material = new Material(Shader.Find("Hidden/Yangrc/AerialPerspective"));
        }

        private Material material;

        [ImageEffectOpaque]
        private void OnRenderImage(RenderTexture source, RenderTexture destination) {
            material.SetVector("_ProjectionExtents", camera.GetProjectionExtents());
            Graphics.Blit(source, destination, material, 0);
        }

        private void Update() {
            //Control sun intensity.
        }

        private RenderTexture transmittanceVolume;
        private RenderTexture scatteringVolume;
        public Vector3Int volumeTexSize = new Vector3Int(128, 128, 32);

        Vector3[] _FrustumCorners = new Vector3[4];
        //Generate camera volume texture.
        private void OnPreRender() {
            if (RenderSettings.sun == null)
                return;
            // get four corners of camera frustom in world space
            // bottom left
            _FrustumCorners[0] = camera.ViewportToWorldPoint(new Vector3(0, 0, camera.farClipPlane));
            // bottom right
            _FrustumCorners[1] = camera.ViewportToWorldPoint(new Vector3(1, 0, camera.farClipPlane));
            // top left
            _FrustumCorners[2] = camera.ViewportToWorldPoint(new Vector3(0, 1, camera.farClipPlane));
            // top right
            _FrustumCorners[3] = camera.ViewportToWorldPoint(new Vector3(1, 1, camera.farClipPlane));
            
            //Render camera volume texture.
            var projection_matrix = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false);
            AtmLutHelper.CreateCameraAlignedVolumeTexture(ref transmittanceVolume, ref scatteringVolume, volumeTexSize);
            AtmLutHelper.UpdateCameraVolume(
                transmittanceVolume, 
                scatteringVolume, 
                volumeTexSize,
                transform.position, 
                -RenderSettings.sun.transform.forward,
                _FrustumCorners,
                new Vector2(camera.nearClipPlane, camera.farClipPlane)
                );
            
            //Set it.
            Shader.SetGlobalTexture("_CameraVolumeTransmittance", transmittanceVolume);
            Shader.SetGlobalTexture("_CameraVolumeScattering", scatteringVolume);
            var vp_matrix = projection_matrix * camera.worldToCameraMatrix;
            Shader.SetGlobalMatrix("_Camera_VP", vp_matrix);
        }

        private void OnDisable() {
            Shader.SetGlobalTexture("_CameraVolumeTransmittance", null);
            Shader.SetGlobalTexture("_CameraVolumeScattering", null);
        }
    }

    public static class CameraExtension {
        public static Vector4 GetProjectionExtents(this Camera camera, float texelOffsetX, float texelOffsetY) {
            if (camera == null)
                return Vector4.zero;

            float oneExtentY = camera.orthographic ? camera.orthographicSize : Mathf.Tan(0.5f * Mathf.Deg2Rad * camera.fieldOfView);
            float oneExtentX = oneExtentY * camera.aspect;
            float texelSizeX = oneExtentX / (0.5f * camera.pixelWidth);
            float texelSizeY = oneExtentY / (0.5f * camera.pixelHeight);
            float oneJitterX = texelSizeX * texelOffsetX;
            float oneJitterY = texelSizeY * texelOffsetY;

            return new Vector4(oneExtentX, oneExtentY, oneJitterX, oneJitterY);// xy = frustum extents at distance 1, zw = jitter at distance 1
        }

        public static Vector4 GetProjectionExtents(this Camera camera) {
            return GetProjectionExtents(camera, 0.0f, 0.0f);
        }
    }
}