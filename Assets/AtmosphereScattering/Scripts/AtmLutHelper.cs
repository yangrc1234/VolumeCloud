using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;
namespace Yangrc.AtmosphereScattering {

    public static class HighResolutionDateTime {
        public static bool IsAvailable { get; private set; }

        [DllImport("Kernel32.dll", CallingConvention = CallingConvention.Winapi)]
        private static extern void GetSystemTimePreciseAsFileTime(out long filetime);

        public static DateTime UtcNow {
            get {
                if (!IsAvailable) {
                    throw new InvalidOperationException(
                        "High resolution clock isn't available.");
                }

                long filetime;
                GetSystemTimePreciseAsFileTime(out filetime);

                return DateTime.FromFileTimeUtc(filetime);
            }
        }

        static HighResolutionDateTime() {
            try {
                long filetime;
                GetSystemTimePreciseAsFileTime(out filetime);
                IsAvailable = true;
            } catch (EntryPointNotFoundException) {
                // Not running Windows 8 or higher.
                IsAvailable = false;
            }
        }
    }

    public class ProgressiveLutUpdater {

        public void Cleanup() {
            var allTextures = new List<RenderTexture> {
                this.groundIrradianceCombine,
                this.multiScatteringCombine,
                this.multiScatteringDensity,

                this.singleMie,
                this.singleRayleigh,
                this.transmittance,
            };
            allTextures.AddRange(
                this.groundIrradianceTemp);
            allTextures.AddRange(
                this.multiScatteringTemp);

            for (int i = 0; i < allTextures.Count; i++) {
                if (allTextures[i] != null && allTextures[i].IsCreated())
                    allTextures[i].Release();
            }
        }

        public interface ITimeLogger {
            void Log(string itemName);
        }

        public AtmosphereConfig atmConfigToUse { get; set; }
        public AtmosphereConfig atmConfigUsedToUpdate { get; private set; }
        public AtmLutGenerateConfig lutConfig { get; set; }
        ITimeLogger logger;
        public ProgressiveLutUpdater(AtmosphereConfig atmConfig, AtmLutGenerateConfig lutConfig, ITimeLogger logger = null) {
            this.atmConfigToUse = atmConfig;
            this.lutConfig = lutConfig;
            this.logger = logger;
            working = false;
            atmConfigUsedToUpdate = ScriptableObject.CreateInstance<AtmosphereConfig>();
        }
        public const int k_MultiScatteringOrderDepth = 4;

        public RenderTexture[] groundIrradianceTemp = new RenderTexture[k_MultiScatteringOrderDepth + 1];
        public RenderTexture multiScatteringDensity;
        public RenderTexture[] multiScatteringTemp = new RenderTexture[k_MultiScatteringOrderDepth + 1];

        public RenderTexture transmittance;
        public RenderTexture singleRayleigh, singleMie;
        public RenderTexture multiScatteringCombine, groundIrradianceCombine;
        internal string name;

        public bool working { get; private set; }

        private void Log(string t) {
            if (this.logger != null)
                logger.Log(t);
        }

        public IEnumerator UpdateCoroutine() {
            working = true;
            atmConfigUsedToUpdate.CopyDataFrom(atmConfigToUse);
            AtmLutHelper.CreateTransmittanceTexture(ref transmittance, lutConfig);
            using (new ConvenientStopwatch("Complete Lut update timecost", Log)) {
                //Update transmittance.
                AtmLutHelper.ApplyComputeShaderParams(lutConfig, atmConfigUsedToUpdate);
                using (new ConvenientStopwatch("Transmittance ", Log)) {
                    AtmLutHelper.UpdateTransmittance(
                        transmittance,
                        lutConfig,
                        0.0f,
                        1.0f
                        );
                    yield return null;
                }

                //Update GroundDirect
                using (new ConvenientStopwatch("GroundDirect", Log)) {
                    AtmLutHelper.ApplyComputeShaderParams(lutConfig, atmConfigUsedToUpdate);
                    AtmLutHelper.CreateGroundIrradianceTexture(ref groundIrradianceTemp[0], 0, lutConfig);
                    AtmLutHelper.UpdateGroundDirectIrradiance(groundIrradianceTemp[0], transmittance, lutConfig, 0.0f, 1.0f);
                    yield return null;
                }

                //Update SingleRayleigh/Mie
                using (new ConvenientStopwatch("Single Rayleigh/Mie", Log)) {
                    AtmLutHelper.ApplyComputeShaderParams(lutConfig, atmConfigUsedToUpdate);
                    AtmLutHelper.CreateSingleRayleighMieTexture(ref singleRayleigh, ref singleMie, lutConfig);
                    AtmLutHelper.UpdateSingleRayleighMie(singleRayleigh, singleMie, transmittance, lutConfig);
                    yield return null;
                }

                AtmLutHelper.CreateMultiScatteringTexture(ref multiScatteringTemp[1], 1, lutConfig);    //This texture is not "Meaningful"(Since the 1-st order should be SingleRayleigh and SingleMie, and this tex won't be used in actual computation either), but we need to make an empty one to avoid shader error.

                using (new ConvenientStopwatch("GroundIrradiance 1", Log)) {
                    //Ground irradiance of 1-st order scattering.
                    AtmLutHelper.ApplyComputeShaderParams(lutConfig, atmConfigUsedToUpdate);
                    AtmLutHelper.CreateGroundIrradianceTexture(ref groundIrradianceTemp[1], 1, lutConfig);
                    AtmLutHelper.UpdateGroundIrradiance(groundIrradianceTemp[1], singleRayleigh, singleMie, multiScatteringTemp[1], 1, lutConfig, 0.0f, 1.0f);
                    yield return null;
                }

                //Real game start.
                AtmLutHelper.CreateMultiScatteringDensityTexture(ref multiScatteringDensity, lutConfig);

                for (int i = 2; i <= k_MultiScatteringOrderDepth; i++) {
                    using (new ConvenientStopwatch("Multi Scattering Density" + i, Log)) {
                        AtmLutHelper.ApplyComputeShaderParams(lutConfig, atmConfigUsedToUpdate);
                        AtmLutHelper.UpdateMultiScatteringDensity(multiScatteringDensity, transmittance, singleRayleigh, singleMie, multiScatteringTemp[i - 1], groundIrradianceTemp[i - 2], i, lutConfig);
                        yield return null;
                    }

                    AtmLutHelper.CreateGroundIrradianceTexture(ref groundIrradianceTemp[i], i, lutConfig);
                    using (new ConvenientStopwatch("Ground Irradiance" + i, Log)) {
                        AtmLutHelper.ApplyComputeShaderParams(lutConfig, atmConfigUsedToUpdate);
                        AtmLutHelper.UpdateGroundIrradiance(groundIrradianceTemp[i], singleRayleigh, singleMie, multiScatteringTemp[i - 1], i - 1, lutConfig);
                        yield return null;
                    }

                    AtmLutHelper.CreateMultiScatteringTexture(ref multiScatteringTemp[i], i, lutConfig);
                    using (new ConvenientStopwatch("Multi Scattering " + i, Log)) {
                        AtmLutHelper.ApplyComputeShaderParams(lutConfig, atmConfigUsedToUpdate);
                        AtmLutHelper.UpdateMultiScatteringCombineDensity(multiScatteringTemp[i], transmittance, multiScatteringDensity, lutConfig);
                        yield return null;
                    }
                }

                //Combine our multiscattering texture.
                AtmLutHelper.CreateFinalCombinedTexture(ref multiScatteringCombine, ref groundIrradianceCombine, lutConfig);
                AtmLutHelper.ClearFinalCombinedMultiScatter(multiScatteringCombine, lutConfig);
                AtmLutHelper.ClearFinalCombinedIrradiance(groundIrradianceCombine, lutConfig);

                AtmLutHelper.ApplyComputeShaderParams(lutConfig, atmConfigUsedToUpdate);
                for (int i = 2; i <= k_MultiScatteringOrderDepth; i++) {
                    AtmLutHelper.UpdateFinalCombinedMultiScatter(multiScatteringCombine, multiScatteringTemp[i], lutConfig);
                }

                for (int i = 1; i <= k_MultiScatteringOrderDepth; i++) {
                    AtmLutHelper.UpdateFinalCombinedIrradiance(groundIrradianceCombine, groundIrradianceTemp[i], lutConfig);
                }
            }
            //All calculations are done.

            /*  DON"T RELEASE TEMP TEXTURES HERE, IT WILL CAUSE GRAPHICS GLITCH(FLASHING) WHEN RENDERING SKYBOX. I DON'T KNOW WHY.(2017.4.11f1)    */
            /*  AND THAT GLITCH COST ME 4 HOURS TO FIND OUT, THANK YOU UNITY */
            /*  I guess that after combine dispatch call, the process isn't finished immediately, if we release the textures right now, it will blow up. */
            /*  but I tried to wait for a few frame(yield return null), still doesn't work. */
            ////Release all temp textures. They won't be used in the future.
            //for (int i = 0; i < groundIrradianceTemp.Length; i++) {
            //    if (groundIrradianceTemp[i] != null) {
            //        groundIrradianceTemp[i].Release();
            //        groundIrradianceTemp[i] = null;
            //    }
            //}
            //for (int i = 0; i < multiScatteringTemp.Length; i++) {
            //    if (multiScatteringTemp[i] != null) {
            //        multiScatteringTemp[i].Release();
            //        multiScatteringTemp[i] = null;
            //    }
            //}

            //Done!
            working = false;
            yield break;
        }
    }

    [System.Serializable]
    public class AtmLutGenerateConfig {
        public Vector2Int transmittanceSize = new Vector2Int(512, 512);
        public Vector3Int scatteringSize = new Vector3Int(32, 32, 128);
        public Vector2Int irradianceSize = new Vector2Int(32, 32);
        public Vector3Int cameraVolumeSize = new Vector3Int(128, 128, 32);
        private static class Keys {
            private static readonly int transmittanceSize = Shader.PropertyToID("TransmittanceSize");
            private static readonly int scatteringSize = Shader.PropertyToID("ScatteringSize");
            private static readonly int irradianceSize = Shader.PropertyToID("IrradianceSize");
        }
        public void Apply(ComputeShader shader) {
            shader.SetInts("TransmittanceSize", transmittanceSize.x, transmittanceSize.y);
            shader.SetInts("ScatteringSize", scatteringSize.x, scatteringSize.y, scatteringSize.z);
            shader.SetInts("IrradianceSize", irradianceSize.x, irradianceSize.y);
        }
    }

    public class ConvenientStopwatch : System.IDisposable {
        public ConvenientStopwatch(string name, System.Action<string> Log = null) {
            this.name = name;
            start = HighResolutionDateTime.UtcNow;
            this.Log = Log;
        }
        System.Action<string> Log;
        DateTime start;
        string name;
        public void Dispose() {
            var timeSpan = HighResolutionDateTime.UtcNow - start;
            if (Log != null)
                Log(name + ":" + timeSpan.TotalMilliseconds);
        }
    }

    public static class AtmLutHelper {

        public static void Init(ComputeShader shader) {
            if (computeShader == null) {
                AtmLutHelper.computeShader = shader;
                SetupKernals(computeShader);
            }
        }

        public static ComputeShader computeShader;
        private static int CalculateTransmittanceLUT;
        private static int CalculateSingleScatteringLUT;
        private static int CalculateGroundDirectIrradianceLUT;
        private static int CalculateGroundIndirectIrradianceLUT;
        private static int CalculateMultipleScatteringDensityLUT;
        private static int CalculateMultipleScatteringLUT;
        private static int SumGroundIrradianceLUT;
        private static int SumMultipleScatteringLUT;
        private static int ClearCombineGroundIrradianceLUT;
        private static int ClearCombineMultipleScatteringLUT;

        private static int CalculateCameraScatteringVolume;

        /// <summary>
        /// These functions help do all the "SetXXX" stuff.
        /// So we can focus on how to generate Luts.
        /// </summary>

        private static void SetupKernals(ComputeShader computeShader) {
            CalculateTransmittanceLUT = computeShader.FindKernel("CalculateTransmittanceLUT");
            CalculateSingleScatteringLUT = computeShader.FindKernel("CalculateSingleScatteringLUT");
            CalculateGroundDirectIrradianceLUT = computeShader.FindKernel("CalculateGroundDirectIrradianceLUT");
            CalculateGroundIndirectIrradianceLUT = computeShader.FindKernel("CalculateGroundIndirectIrradianceLUT");
            CalculateMultipleScatteringDensityLUT = computeShader.FindKernel("CalculateMultipleScatteringDensityLUT");
            CalculateMultipleScatteringLUT = computeShader.FindKernel("CalculateMultipleScatteringLUT");
            SumGroundIrradianceLUT = computeShader.FindKernel("CombineGroundIrradianceLUT");
            SumMultipleScatteringLUT = computeShader.FindKernel("CombineMultipleScatteringLUT");
            ClearCombineGroundIrradianceLUT = computeShader.FindKernel("ClearCombineGroundIrradianceLUT");
            ClearCombineMultipleScatteringLUT = computeShader.FindKernel("ClearCombineMultipleScatteringLUT");

            CalculateCameraScatteringVolume = computeShader.FindKernel("CalculateCameraScatteringVolume");
        }

        public static void ApplyComputeShaderParams(AtmLutGenerateConfig lutConfig, AtmosphereConfig atmConfig) {
            lutConfig.Apply(computeShader);
            atmConfig.Apply(computeShader);
        }

        private static void CreateLUT(ref RenderTexture result, string name, int width, int height, int zsize, RenderTextureFormat format, bool forceReplace = false) {
            if (result != null) {
                if (!forceReplace && result.name == name && result.width == width && result.height == height && result.volumeDepth == zsize && result.format == format)
                    return;
                result.Release();
            }
            result = new RenderTexture(width, height, 0, format, RenderTextureReadWrite.Linear);
            result.name = name;
            result.enableRandomWrite = true;
            if (zsize > 0) {
                result.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
                result.volumeDepth = zsize;
            } else {
                result.dimension = UnityEngine.Rendering.TextureDimension.Tex2D;
            }
            result.filterMode = FilterMode.Bilinear;
            result.wrapMode = TextureWrapMode.Clamp;
            result.Create();
        }

        private static void NormalizeProgressPointer(float start, float end, int length, out int startInt, out int endInt) {
            if (end < start) {
                var t = start;
                start = end;
                end = t;
            }

            start = Mathf.Clamp01(start);
            end = Mathf.Clamp01(end);
            startInt = Mathf.RoundToInt(length * start);
            endInt = Mathf.RoundToInt(length * end);
        }

        public static void CreateTransmittanceTexture(
            ref RenderTexture target,
            AtmLutGenerateConfig lutconfig) {
            CreateLUT(ref target, "Transmittance", lutconfig.transmittanceSize.x, lutconfig.transmittanceSize.y, 0, RenderTextureFormat.ARGBFloat);
        }

        public static void CreateSingleRayleighMieTexture(ref RenderTexture rayleigh, ref RenderTexture mie, AtmLutGenerateConfig lutconfig) {
            CreateLUT(ref rayleigh, "SingleMie", lutconfig.scatteringSize.x, lutconfig.scatteringSize.y, lutconfig.scatteringSize.z, RenderTextureFormat.ARGBFloat);
            CreateLUT(ref mie, "SingleRayleigh", lutconfig.scatteringSize.x, lutconfig.scatteringSize.y, lutconfig.scatteringSize.z, RenderTextureFormat.ARGBFloat);
        }

        public static void CreateGroundIrradianceTexture(ref RenderTexture target, int order, AtmLutGenerateConfig lutconfig) {
            CreateLUT(ref target, "Ground Irrdiance Order " + order, lutconfig.irradianceSize.x, lutconfig.irradianceSize.y, 0, RenderTextureFormat.ARGBFloat);
        }

        public static void CreateMultiScatteringDensityTexture(
            ref RenderTexture result,
            AtmLutGenerateConfig lutConfig
            ) {
            CreateLUT(ref result, "MultiScatteringDensity", lutConfig.scatteringSize.x, lutConfig.scatteringSize.y, lutConfig.scatteringSize.z, RenderTextureFormat.ARGBFloat);
        }

        public static void CreateMultiScatteringTexture(
            ref RenderTexture result,
            int order,
            AtmLutGenerateConfig lutConfig
            ) {
            CreateLUT(ref result, "MultiScattering " + order, lutConfig.scatteringSize.x, lutConfig.scatteringSize.y, lutConfig.scatteringSize.z, RenderTextureFormat.ARGBFloat);
        }

        public static void CreateFinalCombinedTexture(
            ref RenderTexture MultipleScatteringLUT,
            ref RenderTexture IrradianceLUT,
            AtmLutGenerateConfig lutConfig
            ) {
            CreateLUT(ref MultipleScatteringLUT, "Multiple Scattering Combined Final", lutConfig.scatteringSize.x, lutConfig.scatteringSize.y, lutConfig.scatteringSize.z, RenderTextureFormat.ARGBFloat, true);
            CreateLUT(ref IrradianceLUT, "Irradiance Combined Final", lutConfig.irradianceSize.x, lutConfig.irradianceSize.y, 0, RenderTextureFormat.ARGBFloat, true);
        }

        public static void CreateCameraAlignedVolumeTexture(
                    ref RenderTexture transmittance,
                    ref RenderTexture scattering,
                    Vector3Int volumeTexSize
                    ) {
            CreateLUT(ref transmittance,
                "CameraVolumeTransmittance",
                volumeTexSize.x,
                volumeTexSize.y,
                volumeTexSize.z,
                RenderTextureFormat.ARGBFloat,
                false);
            CreateLUT(ref scattering,
                "CameraVolumeScattering",
                volumeTexSize.x,
                volumeTexSize.y,
                volumeTexSize.z,
                RenderTextureFormat.ARGBFloat,
                false);
        }

        public static void UpdateTransmittance(
            RenderTexture target,
            AtmLutGenerateConfig lutConfig,
            float start = 0.0f,
            float end = 1.0f
            ) {
            int xStart, xEnd;
            NormalizeProgressPointer(start, end, lutConfig.transmittanceSize.x / 32, out xStart, out xEnd);
            computeShader.SetInts("_ThreadOffset", xStart, 0, 0);
            computeShader.SetTexture(CalculateTransmittanceLUT, "TransmittanceLUTResult", target);
            computeShader.Dispatch(CalculateTransmittanceLUT, xEnd - xStart, lutConfig.transmittanceSize.y / 32, 1);
        }

        public static void UpdateSingleRayleighMie(
            RenderTexture rayleightarget,
            RenderTexture mietarget,
            RenderTexture TransmittanceLUT,
            AtmLutGenerateConfig lutConfig,
            float start = 0.0f,
            float end = 1.0f
            ) {

            int xStart, xEnd;
            NormalizeProgressPointer(start, end, lutConfig.scatteringSize.x / 8, out xStart, out xEnd);
            computeShader.SetInts("_ThreadOffset", xStart, 0, 0);

            computeShader.SetTexture(CalculateSingleScatteringLUT, "TransmittanceLUT", TransmittanceLUT);
            computeShader.SetTexture(CalculateSingleScatteringLUT, "SingleScatteringMieLUTResult", mietarget);
            computeShader.SetTexture(CalculateSingleScatteringLUT, "SingleScatteringRayleighLUTResult", rayleightarget);

            computeShader.Dispatch(CalculateSingleScatteringLUT, xEnd - xStart, lutConfig.scatteringSize.y / 8, lutConfig.scatteringSize.z / 8);
        }

        public static void UpdateGroundDirectIrradiance(
            RenderTexture target,
            RenderTexture TransmittanceLUT,
            AtmLutGenerateConfig lutConfig,
            float start = 0.0f,
            float end = 1.0f
            ) {
            int xStart, xEnd;
            NormalizeProgressPointer(start, end, lutConfig.irradianceSize.x / 32, out xStart, out xEnd);
            computeShader.SetInts("_ThreadOffset", xStart, 0, 0);

            computeShader.SetTexture(CalculateGroundDirectIrradianceLUT, "TransmittanceLUT", TransmittanceLUT);
            computeShader.SetTexture(CalculateGroundDirectIrradianceLUT, "GroundDirectIrradianceResult", target);
            computeShader.Dispatch(CalculateGroundDirectIrradianceLUT, xEnd - xStart, lutConfig.irradianceSize.y / 32, 1);
        }

        public static void UpdateGroundIrradiance(
            RenderTexture target,
            RenderTexture singleRayleigh,
            RenderTexture singleMie,
            RenderTexture multiScattering,
            int scatteringOrder,
            AtmLutGenerateConfig lutConfig,
            float start = 0.0f,
            float end = 1.0f
            ) {
            int xStart, xEnd;
            NormalizeProgressPointer(start, end, lutConfig.irradianceSize.x / 32, out xStart, out xEnd);
            computeShader.SetInts("_ThreadOffset", xStart, 0, 0);

            computeShader.SetInt("ScatteringOrder", scatteringOrder);
            computeShader.SetTexture(CalculateGroundIndirectIrradianceLUT, "SingleRayleighScatteringLUT", singleRayleigh);
            computeShader.SetTexture(CalculateGroundIndirectIrradianceLUT, "SingleMieScatteringLUT", singleMie);
            computeShader.SetTexture(CalculateGroundIndirectIrradianceLUT, "MultipleScatteringLUT", multiScattering);
            computeShader.SetTexture(CalculateGroundIndirectIrradianceLUT, "GroundIndirectIrradianceResult", target);
            computeShader.Dispatch(CalculateGroundIndirectIrradianceLUT, xEnd - xStart, lutConfig.irradianceSize.y / 32, 1);
        }

        public static void UpdateMultiScatteringDensity(
            RenderTexture target,
            RenderTexture TransmittanceLUT,
            RenderTexture SingleScatteringLUTRayleigh,
            RenderTexture SingleScatteringLUTMie,
            RenderTexture MultiScatteringOfLastOrder,
            RenderTexture GroundDirectIrradianceLUT,
            int scatteringOrder,
            AtmLutGenerateConfig lutConfig,
            float start = 0.0f,
            float end = 1.0f
            ) {
            int xStart, xEnd;
            NormalizeProgressPointer(start, end, lutConfig.scatteringSize.x / 8, out xStart, out xEnd);
            computeShader.SetInts("_ThreadOffset", xStart, 0, 0);

            computeShader.SetTexture(CalculateMultipleScatteringDensityLUT, "TransmittanceLUT", TransmittanceLUT);
            computeShader.SetTexture(CalculateMultipleScatteringDensityLUT, "SingleRayleighScatteringLUT", SingleScatteringLUTRayleigh);
            computeShader.SetTexture(CalculateMultipleScatteringDensityLUT, "SingleMieScatteringLUT", SingleScatteringLUTMie);
            computeShader.SetTexture(CalculateMultipleScatteringDensityLUT, "IrradianceLUT", GroundDirectIrradianceLUT);
            computeShader.SetTexture(CalculateMultipleScatteringDensityLUT, "MultipleScatteringLUT", MultiScatteringOfLastOrder);
            computeShader.SetInt("ScatteringOrder", scatteringOrder);
            computeShader.SetTexture(CalculateMultipleScatteringDensityLUT, "MultipleScatteringDensityResult", target);
            computeShader.Dispatch(CalculateMultipleScatteringDensityLUT, xEnd - xStart, lutConfig.scatteringSize.y / 8, lutConfig.scatteringSize.z / 8);
        }


        public static void UpdateMultiScatteringCombineDensity(
            RenderTexture target,
            RenderTexture TransmittanceLUT,
            RenderTexture multipleScatteringDensity,
            AtmLutGenerateConfig lutConfig,
            float start = 0.0f,
            float end = 1.0f
            ) {
            int xStart, xEnd;
            NormalizeProgressPointer(start, end, lutConfig.scatteringSize.x / 8, out xStart, out xEnd);
            computeShader.SetInts("_ThreadOffset", xStart, 0, 0);

            computeShader.SetTexture(CalculateMultipleScatteringLUT, "TransmittanceLUT", TransmittanceLUT);
            computeShader.SetTexture(CalculateMultipleScatteringLUT, "MultipleScatteringDensityLUT", multipleScatteringDensity);
            computeShader.SetTexture(CalculateMultipleScatteringLUT, "MultipleScatteringResult", target);
            computeShader.Dispatch(CalculateMultipleScatteringLUT, xEnd - xStart, lutConfig.scatteringSize.y / 8, lutConfig.scatteringSize.z / 8);
        }

        public static void ClearFinalCombinedMultiScatter(
            RenderTexture multiScatteringTarget,
            AtmLutGenerateConfig lutConfig
            ) {
            computeShader.SetTexture(ClearCombineMultipleScatteringLUT, "ScatteringSumTarget", multiScatteringTarget);
            computeShader.Dispatch(ClearCombineMultipleScatteringLUT, lutConfig.scatteringSize.x / 8, lutConfig.scatteringSize.y / 8, lutConfig.scatteringSize.z / 8);
        }

        public static void UpdateFinalCombinedMultiScatter(
            RenderTexture multiScatteringTarget,
            RenderTexture multiScatteringOfSingleOrder,
            AtmLutGenerateConfig lutConfig
            ) {
            computeShader.SetTexture(SumMultipleScatteringLUT, "ScatteringSumTarget", multiScatteringTarget);
            computeShader.SetTexture(SumMultipleScatteringLUT, "ScatteringSumAdd", multiScatteringOfSingleOrder);
            computeShader.Dispatch(SumMultipleScatteringLUT, lutConfig.scatteringSize.x / 8, lutConfig.scatteringSize.y / 8, lutConfig.scatteringSize.z / 8);
        }

        public static void ClearFinalCombinedIrradiance(
            RenderTexture target,
            AtmLutGenerateConfig lutConfig
            ) {
            computeShader.SetTexture(ClearCombineGroundIrradianceLUT, "GroundIrradianceSumTarget", target);
            computeShader.Dispatch(ClearCombineGroundIrradianceLUT, lutConfig.irradianceSize.x / 32, lutConfig.irradianceSize.y / 32, 1);
        }

        public static void UpdateFinalCombinedIrradiance(
            RenderTexture target,
            RenderTexture irradianceOfSingleOrder,
            AtmLutGenerateConfig lutConfig
            ) {
            computeShader.SetTexture(SumGroundIrradianceLUT, "GroundIrradianceSumTarget", target);
            computeShader.SetTexture(SumGroundIrradianceLUT, "GroundIrradianceSumAdder", irradianceOfSingleOrder);
            computeShader.Dispatch(SumGroundIrradianceLUT, lutConfig.irradianceSize.x / 32, lutConfig.irradianceSize.y / 32, 1);
        }

        /// <summary>
        /// Calculate camera frustrum aligned volume.
        /// See frostbite slider for more.
        /// </summary>
        /// <param name="transmittanceTarget">Target to store transmittance</param>
        /// <param name="scatteringTarget">Target to store scattering</param>
        /// <param name="volumeSize">Volume tex size, used to determine dispatch call params</param>
        /// <param name="cameraPos">Camera world pos</param>
        /// <param name="sunDirection">Sun direction(pointing towards sun)</param>
        /// <param name="frustrumCorners">four corners of camera frustrum(bl, br, tl, tr). We can't use projection matrix since we divide depth equal range, so we manually interpolate uvw using these corners and near/far plane</param>
        /// <param name="nearFarPlane">Near and far plane distance</param>
        public static void UpdateCameraVolume(
            RenderTexture transmittanceTarget,
            RenderTexture scatteringTarget,
            Vector3Int volumeSize,
            Vector3 cameraPos,
            Vector3 sunDirection,
            Vector3[] frustrumCorners,
            Vector2 nearFarPlane
            ) {
            //Here we need calculated lerpable luts. This kinda break the code sepration. Any better idea?
            AtmosphereScatteringLutManager.instance.UpdateComputeShaderValueForLerpedAp(computeShader, CalculateCameraScatteringVolume);

            computeShader.SetTexture(CalculateCameraScatteringVolume, "CameraVolumeTransmittance", transmittanceTarget);
            computeShader.SetTexture(CalculateCameraScatteringVolume, "CameraVolumeScattering", scatteringTarget);
            computeShader.SetVector("_CameraPos", cameraPos);
            computeShader.SetVector("_SunDir", sunDirection);

            computeShader.SetVector("_CamBotLeft", frustrumCorners[0]);
            computeShader.SetVector("_CamBotRight", frustrumCorners[1]);
            computeShader.SetVector("_CamTopLeft", frustrumCorners[2]);
            computeShader.SetVector("_CamTopRight", frustrumCorners[3]);
            computeShader.SetVector("_NearFarPlane", nearFarPlane);
            computeShader.Dispatch(CalculateCameraScatteringVolume, volumeSize.x / 8, volumeSize.y / 8, volumeSize.z / 8);
        }
    }

}