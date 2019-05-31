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
        [SerializeField]
        private Shader cloudShader;
        public VolumeCloudConfiguration configuration;
        [Range(0, 2)]
        public int downSample = 1;
        public Quality quality;
        public bool allowCloudFrontObject;
        [SerializeField]
        [Tooltip("Enable ap calculation using ap system. Do not enable if ap system is not present")]
        private bool useApSystem;

        private Material mat;
        private Material heightDownsampleMat;
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

        [Header("Hi-Height")]
        [SerializeField]
        private ComputeShader heightPreprocessShader;
        [SerializeField]
        private bool useHierarchicalHeightMap;
        [SerializeField]
        private Shader cloudHeightProcessShader;
        [SerializeField]
        private Vector2Int hiHeightLevelRange = new Vector2Int(0, 9);
        [SerializeField]
        private Vector2Int heightLutTextureSize = new Vector2Int(512, 512);
        public RenderTexture heightLutTexture;
        public RenderTexture hiHeightTexture;
        public RenderTexture[] hiHeightTempTextures;

        void EnsureMaterial(bool force = false) {
            if (mat == null || force) {
                mat = new Material(cloudShader);
            }
            if (heightDownsampleMat == null || force){
                heightDownsampleMat = new Material(cloudHeightProcessShader);
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
            if (hiHeightTexture != null) {
                hiHeightTexture.Release();
                hiHeightTexture = null;
            }
            if (heightLutTexture != null) {
                heightLutTexture.Release();
                heightLutTexture = null;
            }
        }

        private void Start() {
            this.EnsureMaterial(true);
        }

        private void GenerateHierarchicalHeightMap() {
            RenderTexture defaultTarget = RenderTexture.active;

            if (this.configuration.weatherTex.width != 512 || this.configuration.weatherTex.height != 512) {
                throw new UnityException("Hierarchical height map mode only supports weather tex of size 512*512!");
            }

            EnsureRenderTarget(ref heightLutTexture, heightLutTextureSize.x, heightLutTextureSize.y, RenderTextureFormat.RFloat, FilterMode.Point, randomWrite:true);
            var kernal = heightPreprocessShader.FindKernel("CSMain");
            heightPreprocessShader.SetTexture(kernal, "heightDensityMap", configuration.heightDensityMap);
            heightPreprocessShader.SetTexture(kernal, "heightLutResult", this.heightLutTexture);
            heightPreprocessShader.Dispatch(kernal, heightLutTextureSize.x, heightLutTextureSize.y, 1);

            EnsureRenderTarget(ref hiHeightTexture, 512, 512, RenderTextureFormat.RFloat, FilterMode.Point, wrapMode: TextureWrapMode.Repeat, randomWrite: true, useMipmap:true);

            EnsureArray(ref hiHeightTempTextures, 10);
            for (int i = 0; i <= 9; i++) {
                EnsureRenderTarget(ref hiHeightTempTextures[i], 512 >> i, 512 >> i, RenderTextureFormat.RFloat, FilterMode.Point);
            }

            //RenderTexture previousLevel = null;//Previous level hi-height map.
            //EnsureRenderTarget(ref previousLevel, 512, 512, RenderTextureFormat.RFloat, FilterMode.Point, randomWrite: true);  //The first level is same size as weather tex.
            this.heightDownsampleMat.SetTexture("_WeatherTex", this.configuration.weatherTex);
            this.heightDownsampleMat.SetTexture("_HeightLut", this.heightLutTexture);
            Graphics.Blit(null, hiHeightTempTextures[0], this.heightDownsampleMat, 0);   //The first pass convert weather tex into height map.
            Graphics.CopyTexture(hiHeightTempTextures[0], 0, 0, hiHeightTexture, 0, 0);   //Copy first level into target texture.

            for (int i = 1; i <= Mathf.Min(9, hiHeightLevelRange.y); i++) {
                Graphics.Blit(hiHeightTempTextures[i - 1], hiHeightTempTextures[i], this.heightDownsampleMat, 1);
                Graphics.CopyTexture(hiHeightTempTextures[i], 0, 0, hiHeightTexture, 0, i);
            }
            RenderTexture.active = defaultTarget;
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

            if (useHierarchicalHeightMap) {
                GenerateHierarchicalHeightMap();
                mat.EnableKeyword("USE_HI_HEIGHT");
                mat.SetTexture("_HiHeightMap", this.hiHeightTexture);
                mat.SetInt("_HeightMapSize", this.hiHeightTexture.width);
                mat.SetInt("_HiHeightMinLevel", this.hiHeightLevelRange.x);
                mat.SetInt("_HiHeightMaxLevel", this.hiHeightLevelRange.y);
            } else {
                mat.DisableKeyword("USE_HI_HEIGHT");
            }

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