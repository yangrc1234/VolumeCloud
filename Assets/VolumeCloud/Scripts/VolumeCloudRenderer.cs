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

    public enum Quality {
        Low,
        Normal,    //Low sample count
        High,       //High sample count and high shadow sample count.
    }
    
    /// <summary>
    /// Cloud renderer post processing.
    /// </summary>
    [ImageEffectAllowedInSceneView]
    [ExecuteInEditMode,RequireComponent(typeof(Camera))]
    [ImageEffectOpaque]
        public class VolumeCloudRenderer : EffectBase {
        public Shader cloudShader;
        public VolumeCloudConfiguration configuration;
        [Range(0, 2)]
        public int downSample = 1;
        public Quality quality;
        public bool allowCloudFrontObject;
        [SerializeField]
        [Tooltip("Enable ap calculation using ap system. Do not enable if ap system is not present")]
        private bool useApSystem;

        private Material mat;
        private RenderTexture[] fullBuffer;
        private int fullBufferIndex;
        private RenderTexture undersampleBuffer;
        private Matrix4x4 prevV;
        private Camera mcam;
        private HaltonSequence sequence = new HaltonSequence() { radix = 3 };
        // The index of 4x4 pixels.
        private int frameIndex = 0;
        private float bayerOffsetIndex = 0;
        private bool firstFrame = true;

        void EnsureMaterial(bool force = false) {
            if (mat == null || force) {
                mat = new Material(cloudShader);
            }
        }

        private void OnDestroy() {
            if (this.fullBuffer != null) {
                for (int i = 0; i < fullBuffer.Length; i++) {
                    fullBuffer[i].Release();
                    fullBuffer[i] = null;
                }
            }
            if (this.undersampleBuffer != null) {
                this.undersampleBuffer.Release();
                this.undersampleBuffer = null;
            }
        }

        private void Start() {
            this.EnsureMaterial(true);
        }

        private void OnRenderImage(RenderTexture source, RenderTexture destination) {
            if (this.configuration == null || cloudShader == null) {
                Graphics.Blit(source, destination);
                return;
            }

            mcam = GetComponent<Camera>();
            var width = mcam.pixelWidth >> downSample;
            var height = mcam.pixelHeight >> downSample;

            this.EnsureMaterial();
            this.configuration.ApplyToMaterial(this.mat);

            EnsureArray(ref fullBuffer, 2);
            firstFrame |= EnsureRenderTarget(ref fullBuffer[0], width, height, RenderTextureFormat.ARGBFloat, FilterMode.Bilinear);
            firstFrame |= EnsureRenderTarget(ref fullBuffer[1], width, height, RenderTextureFormat.ARGBFloat, FilterMode.Bilinear);
            firstFrame |= EnsureRenderTarget(ref undersampleBuffer, width , height, RenderTextureFormat.ARGBFloat, FilterMode.Bilinear);

            frameIndex = (frameIndex + 1)% 16;
            fullBufferIndex = (fullBufferIndex + 1) % 2;

            /* Some code is from playdead TAA. */

            //1. Pass1, Render a undersampled buffer. The buffer is dithered using bayer matrix(every 3x3 pixel) and halton sequence.
            //If it's first frame, force a high quality sample to make the initial history buffer good enough.
            if (firstFrame || quality == Quality.High) {
                mat.EnableKeyword("HIGH_QUALITY");
                mat.DisableKeyword("MEDIUM_QUALITY");
                mat.DisableKeyword("LOW_QUALITY");
            } else if (quality == Quality.Normal) {
                mat.DisableKeyword("HIGH_QUALITY");
                mat.EnableKeyword("MEDIUM_QUALITY");
                mat.DisableKeyword("LOW_QUALITY");
            } else if (quality == Quality.Low) {
                mat.DisableKeyword("HIGH_QUALITY");
                mat.DisableKeyword("MEDIUM_QUALITY");
                mat.EnableKeyword("LOW_QUALITY");
            }
            if (useApSystem) {
                mat.EnableKeyword("USE_YANGRC_AP");
            } else {
                mat.DisableKeyword("USE_YANGRC_AP");
            }
            if (allowCloudFrontObject) {
                mat.EnableKeyword("ALLOW_CLOUD_FRONT_OBJECT");
            } else {
                mat.DisableKeyword("ALLOW_CLOUD_FRONT_OBJECT");
            }

            mat.SetVector("_ProjectionExtents", mcam.GetProjectionExtents());
            mat.SetFloat("_RaymarchOffset", sequence.Get());
            mat.SetVector("_TexelSize", undersampleBuffer.texelSize);

            Graphics.Blit(null, undersampleBuffer, mat, 0);

            //2. Pass 2, blend undersampled image with history buffer to new buffer.
            mat.SetTexture("_UndersampleCloudTex", undersampleBuffer);
            mat.SetMatrix("_PrevVP", GL.GetGPUProjectionMatrix(mcam.projectionMatrix,false) * prevV);
            mat.SetVector("_ProjectionExtents", mcam.GetProjectionExtents());

            if (firstFrame) {   //Wait, is this the first frame? If it is, the history buffer is empty yet. It will cause glitch if we use it directly. Fill it using the undersample buffer.
                Graphics.Blit(undersampleBuffer, fullBuffer[fullBufferIndex]);
            }
            Graphics.Blit(fullBuffer[fullBufferIndex], fullBuffer[fullBufferIndex ^ 1], mat, 1);

            //3. Pass3, Calculate lighting, blend final cloud image with final image.
            mat.SetTexture("_CloudTex", fullBuffer[fullBufferIndex ^ 1]);
            Graphics.Blit(source, destination, mat, 2);

            //4. Cleanup
            prevV = mcam.worldToCameraMatrix;
            firstFrame = false;
        }
    }
}