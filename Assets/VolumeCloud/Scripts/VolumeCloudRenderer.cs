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
    [RequireComponent(typeof(Camera))]
    [ImageEffectAllowedInSceneView]
    [ExecuteInEditMode]
    [ImageEffectOpaque]
        public class VolumeCloudRenderer : EffectBase {
        [Header("Config")]
        public VolumeCloudConfiguration configuration;
        [Header("Render Settings")]
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
        private RenderTexture downsampledDepth;
        private CommandBuffer downsampleDepthCommandBuffer;
        private Matrix4x4 prevV;
        private Camera mcam;
        private HaltonSequence sequence = new HaltonSequence() { radix = 3 };

        [Header("Hi-Height")]
        [SerializeField]
        private bool useHierarchicalHeightMap;
        private Vector2Int hiHeightLevelRange = new Vector2Int(0, 9);
        private Vector2Int heightLutTextureSize = new Vector2Int(512, 512);
        private RenderTexture heightLutTexture;
        private RenderTexture hiHeightTexture;
        private RenderTexture[] hiHeightTempTextures;

        [Header("Cloud shadow")]
        [SerializeField]
        private bool enableCloudShadow;
        [SerializeField]
        private Light sun;
        private CommandBuffer cloudShadowCmdBuffer1;
        private CommandBuffer cloudShadowCmdBuffer2;
        private RenderTexture cloudShadowBuffer;

        [Header("Shader references(DONT EDIT)")]
        [SerializeField]
        private Shader cloudShader;
        [SerializeField]
        private ComputeShader heightPreprocessShader;
        [SerializeField]
        private Shader cloudHeightProcessShader;


        void EnsureMaterial(bool force = false) {
            if (mat == null || force) {
                mat = new Material(cloudShader);
            }
            if (heightDownsampleMat == null || force){
                heightDownsampleMat = new Material(cloudHeightProcessShader);
            }
        }
        
        private void OnPreCull() {
            PrepareRender();
        }

        private void PrepareRender() {
            mcam = GetComponent<Camera>();
            var width = mcam.pixelWidth >> downSample;
            var height = mcam.pixelHeight >> downSample;
            EnsureMaterial(false);

            if (useHierarchicalHeightMap) {
                if (EnsureRenderTarget(ref heightLutTexture, heightLutTextureSize.x, heightLutTextureSize.y, RenderTextureFormat.RFloat, FilterMode.Point, randomWrite: true)) {
                    var kernal = heightPreprocessShader.FindKernel("CSMain");
                    heightPreprocessShader.SetTexture(kernal, "heightDensityMap", configuration.heightDensityMap);
                    heightPreprocessShader.SetTexture(kernal, "heightLutResult", this.heightLutTexture);
                    heightPreprocessShader.Dispatch(kernal, heightLutTextureSize.x / 32, heightLutTextureSize.y / 32, 1);
                }

                EnsureRenderTarget(ref hiHeightTexture, 512, 512, RenderTextureFormat.RFloat, FilterMode.Point, wrapMode: configuration.weatherTex.wrapMode, randomWrite: true, useMipmap: true);

                EnsureArray(ref hiHeightTempTextures, 10);
                for (int i = 0; i <= 9; i++) {
                    EnsureRenderTarget(ref hiHeightTempTextures[i], 512 >> i, 512 >> i, RenderTextureFormat.RFloat, FilterMode.Point);
                }
            }

            EnsureArray(ref fullBuffer, 2);
            EnsureRenderTarget(ref fullBuffer[0], width, height, RenderTextureFormat.ARGBFloat, FilterMode.Bilinear);
            EnsureRenderTarget(ref fullBuffer[1], width, height, RenderTextureFormat.ARGBFloat, FilterMode.Bilinear);
            EnsureRenderTarget(ref undersampleBuffer, width, height, RenderTextureFormat.ARGBFloat, FilterMode.Bilinear);

            if (enableCloudShadow && sun != null) 
                EnsureRenderTarget(ref cloudShadowBuffer, mcam.pixelWidth, mcam.pixelHeight, RenderTextureFormat.RFloat, FilterMode.Point, TextureWrapMode.Clamp);
            EnsureRenderTarget(ref downsampledDepth, mcam.pixelWidth >> downSample, mcam.pixelHeight >> downSample, RenderTextureFormat.RFloat, FilterMode.Point);
            /* Command buffer*/
            {
                /* Cloud shadow cmd buffer*/
                if (enableCloudShadow && sun != null) {
                    if (this.cloudShadowCmdBuffer1 == null) {
                        this.cloudShadowCmdBuffer1 = new CommandBuffer();
                        this.cloudShadowCmdBuffer1.name = "Cloud shadow evaluate";
                    }
                    if (this.cloudShadowCmdBuffer2 == null) {
                        this.cloudShadowCmdBuffer2 = new CommandBuffer();
                        this.cloudShadowCmdBuffer2.name = "Cloud shadow composite";
                    }
                    cloudShadowCmdBuffer1.Clear();
                    cloudShadowCmdBuffer2.Clear();
                    this.cloudShadowCmdBuffer1.Blit(null, cloudShadowBuffer, mat, 5);       //Evaluate cloud shadow.
                    this.cloudShadowCmdBuffer2.Blit(cloudShadowBuffer, BuiltinRenderTextureType.CurrentActive, mat, 6); //Blit cloud shadow to screen space shadow mask.

                    sun.AddCommandBuffer(LightEvent.AfterScreenspaceMask, this.cloudShadowCmdBuffer1);
                    sun.AddCommandBuffer(LightEvent.AfterScreenspaceMask, this.cloudShadowCmdBuffer2);
                }

                /* downsample depth */

                if (this.downsampleDepthCommandBuffer == null) {
                    this.downsampleDepthCommandBuffer = new CommandBuffer();
                    this.downsampleDepthCommandBuffer.name = "Depth downsample for cloud";
                }
                downsampleDepthCommandBuffer.Clear();

                if (downSample > 0) {
                    this.downsampleDepthCommandBuffer.Blit(BuiltinRenderTextureType.CurrentActive, downsampledDepth, mat, 3);  //Downsample the texture.
                } else {
                    this.downsampleDepthCommandBuffer.Blit(BuiltinRenderTextureType.CurrentActive, downsampledDepth, mat, 4);  //Just copy it.
                }

                mcam.AddCommandBuffer(CameraEvent.AfterDepthTexture, this.downsampleDepthCommandBuffer);
            }

            UpdateMaterial();
        }

        private void OnRenderImage(RenderTexture source, RenderTexture destination) {

            if (useHierarchicalHeightMap) {
                RenderTexture defaultTarget = RenderTexture.active;
                Graphics.Blit(null, hiHeightTempTextures[0], this.heightDownsampleMat, 0);   //The first pass convert weather tex into height map.
                Graphics.CopyTexture(hiHeightTempTextures[0], 0, 0, hiHeightTexture, 0, 0);   //Copy first level into target texture.

                for (int i = 1; i <= Mathf.Min(9, hiHeightLevelRange.y); i++) {
                    Graphics.Blit(hiHeightTempTextures[i - 1], hiHeightTempTextures[i], this.heightDownsampleMat, 1);
                    Graphics.CopyTexture(hiHeightTempTextures[i], 0, 0, hiHeightTexture, 0, i);
                }
                RenderTexture.active = defaultTarget;
            }

            //1. Pass1, render the cloud tex.
            Graphics.Blit(null, undersampleBuffer, mat, 0);

            //2. Pass 2, blend undersampled image with history buffer to new buffer.
            mat.SetTexture("_UndersampleCloudTex", undersampleBuffer);
            mat.SetMatrix("_PrevVP", GL.GetGPUProjectionMatrix(mcam.projectionMatrix, false) * prevV);
            mat.SetVector("_ProjectionExtents", mcam.GetProjectionExtents());

            Graphics.Blit(fullBuffer[fullBufferIndex], fullBuffer[fullBufferIndex ^ 1], mat, 1);

            //3. Pass3, Calculate lighting, blend final cloud image with final image.
            mat.SetTexture("_CloudTex", fullBuffer[fullBufferIndex ^ 1]);
            Graphics.Blit(source, destination, mat, 2);

            //4. Cleanup
            prevV = mcam.worldToCameraMatrix;
            fullBufferIndex ^= 1;
        }

        private void LateUpdate() {
            /* If we use command buffer normally(build it and keep it), the scene view will be bugged once exit from playmode(The tab bar above scene view will be black, don't know why)
            * According to comments in https://github.com/keijiro/ContactShadows/blob/master/Assets/ContactShadows/ContactShadows.cs 
            * We could remove the command buffer in OnPreRender while keeping its commands(Add it back in next frame).
            * Using this method solves the bugged scene view.
            * 
            * Also, if we call this in OnPreRender, the downsample depth cmd buffer can't work. So we do it here.
            */
            if (this.cloudShadowCmdBuffer1 != null) {
                if (sun != null)
                    sun.RemoveCommandBuffer(LightEvent.AfterScreenspaceMask, this.cloudShadowCmdBuffer1);
                this.cloudShadowCmdBuffer1.Clear();
            }

            if (this.cloudShadowCmdBuffer2 != null) {
                if (sun != null)
                    sun.RemoveCommandBuffer(LightEvent.AfterScreenspaceMask, this.cloudShadowCmdBuffer2);
                this.cloudShadowCmdBuffer2.Clear();
            }

            if (this.downsampleDepthCommandBuffer != null) {
                GetComponent<Camera>().RemoveCommandBuffer(CameraEvent.AfterDepthTexture, this.downsampleDepthCommandBuffer);
                this.downsampleDepthCommandBuffer.Clear();
            }
        }

        private void UpdateMaterial() {
            mat.SetTexture("_DownsampledDepth", downsampledDepth);
            this.configuration.ApplyToMaterial(this.mat);

            if (useHierarchicalHeightMap) {
                mat.EnableKeyword("USE_HI_HEIGHT");
                mat.SetTexture("_HiHeightMap", this.hiHeightTexture);
                mat.SetInt("_HeightMapSize", this.hiHeightTexture.width);
                mat.SetInt("_HiHeightMinLevel", this.hiHeightLevelRange.x);
                mat.SetInt("_HiHeightMaxLevel", this.hiHeightLevelRange.y);
            } else {
                mat.DisableKeyword("USE_HI_HEIGHT");
            }

            if (quality == Quality.High) {
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

            if (useHierarchicalHeightMap) {
                this.heightDownsampleMat.SetTexture("_WeatherTex", this.configuration.weatherTex);
                this.heightDownsampleMat.SetTexture("_HeightLut", this.heightLutTexture);
            }
        }
        
        private void OnDestroy() {

            if (this.fullBuffer != null) {
                for (int i = 0; i < fullBuffer.Length; i++) {
                    if (fullBuffer[i] != null) {
                        fullBuffer[i].Release();
                        fullBuffer[i] = null;
                    }
                }
                this.fullBuffer = null;
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
            if (downsampledDepth != null) {
                downsampledDepth.Release();
                downsampledDepth = null;
            }
            if (this.cloudShadowCmdBuffer1 != null) {
                this.cloudShadowCmdBuffer1.Release();
                this.cloudShadowCmdBuffer1 = null;
            }
            if (this.cloudShadowCmdBuffer2 != null) {
                this.cloudShadowCmdBuffer2.Release();
                this.cloudShadowCmdBuffer2 = null;
            }
            if (this.downsampleDepthCommandBuffer != null) {
                this.downsampleDepthCommandBuffer.Release();
                this.downsampleDepthCommandBuffer = null;
            }
        }
    }
}
 