using System;
using System.Linq;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Yangrc.VolumeCloud {

    /// <summary>
    /// Generate halton sequence.
    /// code from unity post-processing stack.
    /// </summary>
    [System.Serializable]
    public class HaltonSequence {
        public int radix = 3;
        private int storedIndex = 0;
        public float Get() {
            float result = 0f;
            float fraction = 1f / (float)radix;
            int index = storedIndex;
            while (index > 0) {
                result += (float)(index % radix) * fraction;

                index /= radix;
                fraction /= (float)radix;
            }
            storedIndex++;
            return result;
        }
    }
    
    /// <summary>
    /// Cloud renderer post processing.
    /// </summary>
    [ImageEffectAllowedInSceneView]
    [ExecuteInEditMode,RequireComponent(typeof(Camera))]
    [ImageEffectOpaque]
        public class VolumeCloudRenderer : EffectBase {
        public VolumeCloudConfiguration configuration;
        private Material mat;

        private RenderTexture[] fullBuffer;
        private int fullBufferIndex;
        private RenderTexture undersampleBuffer;
        private Matrix4x4 prevV;
        private Camera mcam;
        [SerializeField]
        private HaltonSequence sequence;

        // The index of 4x4 pixels.
        private int frameIndex = 0;
        private float bayerOffsetIndex = 0;


        void EnsureMaterial(bool force = false) {
            if (mat == null || force) {
                var shader = Resources.Load<Shader>("VolumeCloud/Shaders/CloudShader");
                var baseTex = Resources.Load<Texture3D>("VolumeCloud/Textures/BaseNoise");
                var detailTex = Resources.Load<Texture3D>("VolumeCloud/Textures/DetailNoise");
                var curlTex = Resources.Load<Texture2D>("VolumeCloud/Textures/CurlNoise");
                var blurTex = Resources.Load<Texture2D>("VolumeCloud/Textures/BlueNoise");
                mat = new Material(shader);
                mat.SetTexture("_BaseTex", baseTex);
                mat.SetTexture("_DetailTex", detailTex);
                mat.SetTexture("_CurlNoise", curlTex);
                mat.SetTexture("_BlueNoise", blurTex);
            }
        }
        [Range(0,2)]
        public int downSample = 1;

        private void Start() {
            this.EnsureMaterial(true);
        }

        private void OnRenderImage(RenderTexture source, RenderTexture destination) {
            if (this.configuration == null) {
                Graphics.Blit(source, destination);
                return;
            }

            mcam = GetComponent<Camera>();
            var width = mcam.pixelWidth >> downSample;
            var height = mcam.pixelHeight >> downSample;

            this.EnsureMaterial();
            this.configuration.ApplyToMaterial(this.mat);

            EnsureArray(ref fullBuffer, 2);
            EnsureRenderTarget(ref fullBuffer[0], width, height, RenderTextureFormat.ARGBHalf, FilterMode.Bilinear);
            EnsureRenderTarget(ref fullBuffer[1], width, height, RenderTextureFormat.ARGBHalf, FilterMode.Bilinear);
            EnsureRenderTarget(ref undersampleBuffer, width , height, RenderTextureFormat.ARGBHalf, FilterMode.Bilinear);

            frameIndex = (frameIndex + 1)% 16;
            fullBufferIndex = (fullBufferIndex + 1) % 2;

            /* Some code is from playdead TAA. */

            //1. Pass1, Render a undersampled buffer. The buffer is dithered using bayer matrix(every 3x3 pixel) and halton sequence.
            mat.SetVector("_ProjectionExtents", mcam.GetProjectionExtents());
            mat.SetFloat("_RaymarchOffset", sequence.Get());
            mat.SetVector("_TexelSize", undersampleBuffer.texelSize);

            Graphics.Blit(null, undersampleBuffer, mat, 0);

            //2. Pass 2, blend undersampled image with history buffer to new buffer.
            mat.SetTexture("_UndersampleCloudTex", undersampleBuffer);
            mat.SetMatrix("_PrevVP", GL.GetGPUProjectionMatrix(mcam.projectionMatrix,false) * prevV);
            mat.SetVector("_ProjectionExtents", mcam.GetProjectionExtents()); 
            Graphics.Blit(fullBuffer[fullBufferIndex], fullBuffer[fullBufferIndex ^ 1], mat, 1);

            //3. Pass3, Calculate lighting, blend final cloud image with final image.
            mat.SetTexture("_CloudTex", fullBuffer[fullBufferIndex ^ 1]);
            Graphics.Blit(source, destination, mat, 2);

            //4. Cleanup
            prevV = mcam.worldToCameraMatrix;
        }
    }
}