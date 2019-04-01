using System;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;

namespace Yangrc.AtmosphereScattering {

    public class AtmosphereScatteringLutManager : MonoBehaviour , ProgressiveLutUpdater.ITimeLogger{
        public static AtmosphereScatteringLutManager instance {
            get {
                return _instance;
            }
        }
        private static AtmosphereScatteringLutManager _instance;

        [SerializeField]
        private ComputeShader computeShader;
        [SerializeField]
        private bool outputDebug = false;
        public AtmLutGenerateConfig lutConfig;
        public AtmosphereConfig atmosphereConfig;
        [System.NonSerialized]
        public Material skyboxMaterial;

        //We prepare 3 updater, the 0-index one is "currently updating", 1-index is "just updated", and 2-index is the oldest one.
        //During rendering, we interpolate 1 and 2, and updating 0.
        private ProgressiveLutUpdater[] pingPongUpdaters = new ProgressiveLutUpdater[3];

        public ProgressiveLutUpdater newestLut { get {
                return pingPongUpdaters[1];
            } }
        public ProgressiveLutUpdater oldLut {
            get {
                return pingPongUpdaters[2];
            }
        }

        //Shift all updater to one right.
        private void RotatePingpongUpdater() {
            var temp = pingPongUpdaters[pingPongUpdaters.Length-1];
            for (int i = pingPongUpdaters.Length - 1; i > 0; i--) {
                pingPongUpdaters[i] = pingPongUpdaters[i - 1];
            }
            pingPongUpdaters[0] = temp;
        }

        private void Start() {
            if (computeShader == null) {
                throw new System.InvalidOperationException("Compute shader not set!");
            }
            if (_instance != null) {
                throw new System.InvalidOperationException("AtmosphereScatteringLutManager already exists!");
            }
            _instance = this;
            AtmLutHelper.Init(computeShader);
            for (int i = 0; i < pingPongUpdaters.Length; i++) {
                pingPongUpdaters[i] = new ProgressiveLutUpdater(null, lutConfig, this);
                pingPongUpdaters[i].name = "Updater " + i;
            }

            //Quickly complete two set luts.
            for (int i = 1; i <= 2; i++) {
                pingPongUpdaters[i].atmConfigToUse = atmosphereConfig;
                var t = pingPongUpdaters[i].UpdateCoroutine();
                while (t.MoveNext()) ;
            }
            UpdateSkyboxMaterial(pingPongUpdaters[1], pingPongUpdaters[2]);

            KickOffUpdater(pingPongUpdaters[0]);
        }

        private void KickOffUpdater(ProgressiveLutUpdater updater) {
            updater.atmConfigToUse = atmosphereConfig;
            StartCoroutine(updater.UpdateCoroutine());
        }

        private float lerpValue = 0.0f;
        private void Update() {
            if (!pingPongUpdaters[0].working) {
                //Use the finished luts.
                UpdateSkyboxMaterial(pingPongUpdaters[0], pingPongUpdaters[1]);

                lerpValue = 0.0f;

                //Rotate to right.
                RotatePingpongUpdater();

                //Next updater.
                KickOffUpdater(pingPongUpdaters[0]);
            }
            UpdateLerpValue();
        }

        private void UpdateLerpValue() {
            //We now require 19 frames to update
            
            lerpValue += 1.0f / 19.0f;
            if (skyboxMaterial != null)
                Shader.SetGlobalFloat("_LerpValue", lerpValue);
        }

        private void OnDestroy() {
            for (int i = 0; i < pingPongUpdaters.Length; i++) {
                pingPongUpdaters[i].Cleanup();
            }
        }

        public void UpdateComputeShaderValueForLerpedAp(ComputeShader shader, int kernelId) {
            newestLut.atmConfigUsedToUpdate.Apply(shader);
            shader.SetTexture(kernelId, "_SingleRayleigh_1", oldLut.singleRayleigh);
            shader.SetTexture(kernelId, "_SingleMie_1", oldLut.singleMie);
            shader.SetTexture(kernelId, "_SingleRayleigh_2", newestLut.singleRayleigh);
            shader.SetTexture(kernelId, "_SingleMie_2", newestLut.singleMie);
            shader.SetTexture(kernelId, "_MultipleScattering_1", oldLut.multiScatteringCombine);
            shader.SetTexture(kernelId, "_MultipleScattering_2", newestLut.multiScatteringCombine);
            shader.SetTexture(kernelId, "_Transmittance_1", oldLut.transmittance);
            shader.SetTexture(kernelId, "_Transmittance_2", newestLut.transmittance);
            shader.SetTexture(kernelId, "_GroundIrradiance_1", oldLut.groundIrradianceCombine);
            shader.SetTexture(kernelId, "_GroundIrradiance_2", newestLut.groundIrradianceCombine);
            shader.SetVector("_ScatteringSize", (Vector3)lutConfig.scatteringSize);
            shader.SetVector("_GroundIrradianceSize", (Vector2)lutConfig.irradianceSize);
            shader.SetVector("_TransmittanceSize", (Vector2)lutConfig.transmittanceSize);
        }

        public void UpdateSkyboxMaterial(ProgressiveLutUpdater updater, ProgressiveLutUpdater oldUpdater) {
            if (this.skyboxMaterial==null)
                this.skyboxMaterial = new Material(Shader.Find("Skybox/AtmosphereScatteringPrecomputed"));
            updater.atmConfigUsedToUpdate.Apply(skyboxMaterial);
            Shader.SetGlobalTexture("_SingleRayleigh_1", oldUpdater.singleRayleigh);
            Shader.SetGlobalTexture("_SingleMie_1", oldUpdater.singleMie);
            Shader.SetGlobalTexture("_SingleRayleigh_2", updater.singleRayleigh);
            Shader.SetGlobalTexture("_SingleMie_2", updater.singleMie);
            Shader.SetGlobalTexture("_MultipleScattering_1", oldUpdater.multiScatteringCombine);
            Shader.SetGlobalTexture("_MultipleScattering_2", updater.multiScatteringCombine);
            Shader.SetGlobalTexture("_Transmittance_1", oldUpdater.transmittance);
            Shader.SetGlobalTexture("_Transmittance_2", updater.transmittance);
            Shader.SetGlobalTexture("_GroundIrradiance_1", oldUpdater.groundIrradianceCombine);
            Shader.SetGlobalTexture("_GroundIrradiance_2", updater.groundIrradianceCombine);
            Shader.SetGlobalVector("_ScatteringSize", (Vector3)lutConfig.scatteringSize);
            Shader.SetGlobalVector("_GroundIrradianceSize", (Vector2)lutConfig.irradianceSize);
            Shader.SetGlobalVector("_TransmittanceSize", (Vector2)lutConfig.transmittanceSize);
            RenderSettings.skybox = this.skyboxMaterial;
        }

        public void Log(string itemName) {
            if (outputDebug)
                Debug.Log(itemName);
        }

        public Vector3 GetRadianceAt(float mu_s, Vector3 basePosition) {
            var t = atmosphereConfig.SunRadianceOnAtmosphere;
            var r = basePosition + new Vector3(0.0f, atmosphereConfig.atmosphere_bot_radius, 0.0f);
            var transmittance = TransmittanceCalculate.GetTransmittanceToSun(atmosphereConfig, r.magnitude, mu_s);
            t.Scale(transmittance);
            return t;
        }
    }

    public static class TransmittanceCalculate {

        static float ClampCosine(float mu) {
            return Mathf.Clamp(mu, -1.0f, 1.0f);
        }

        static float ClampDistance(float d) {
            return Mathf.Max(d, 0.0f);
        }

        static float ClampRadius(AtmosphereConfig atmosphere, float r) {
            return Mathf.Clamp(r, atmosphere.atmosphere_bot_radius, atmosphere.atmosphere_top_radius);
        }

        static float SafeSqrt(float a) {
            return Mathf.Sqrt(Mathf.Max(a, 0.0f));
        }

        static float DistanceToTopAtmosphereBoundary(AtmosphereConfig atmosphere,
            float r, float mu) {
            float discriminant = r * r * (mu * mu - 1.0f) +
                atmosphere.atmosphere_top_radius * atmosphere.atmosphere_top_radius;
            return ClampDistance(-r * mu + SafeSqrt(discriminant));
        }

        static float GetScaleHeight(float altitude, float scale_height) {
            return Mathf.Exp(-altitude / scale_height);
        }

        static float ComputeOpticalLengthToTopAtmosphereBoundary(
            AtmosphereConfig atmosphere, float r, float mu, float scale_height) {
            // Number of intervals for the numerical integration.
            const int SAMPLE_COUNT = 500;
            // The integration step, i.e. the length of each integration interval.
            float dx =
                DistanceToTopAtmosphereBoundary(atmosphere, r, mu) / (float)SAMPLE_COUNT;
            // Integration loop.
            float result = 0.0f;
            for (int i = 0; i <= SAMPLE_COUNT; ++i) {
                float d_i = (float)i * dx;
                // Distance between the current sample point and the planet center.
                float r_i = Mathf.Sqrt(d_i * d_i + 2.0f * r * mu * d_i + r * r);
                // Number density at the current sample point (divided by the number density
                // at the bottom of the atmosphere, yielding a dimensionless number).
                float y_i = GetScaleHeight(r_i - atmosphere.atmosphere_bot_radius, scale_height);
                // Sample weight (from the trapezoidal rule).
                float weight_i = i == 0 || i == SAMPLE_COUNT ? 0.5f : 1.0f;
                result += y_i * weight_i * dx;
            }
            return result;
        }

        public static Vector3 ComputeTransmittanceToTopAtmosphereBoundary(
            AtmosphereConfig atmosphere, float r, float mu) {
            Vector3 rayleigh = atmosphere.rayleigh_scattering_spectrum *
                ComputeOpticalLengthToTopAtmosphereBoundary(
                    atmosphere, r, mu, atmosphere.rayleigh_scale_height);
            Vector3 mie = Vector3.one * atmosphere.mie_extinction_spectrum *
                ComputeOpticalLengthToTopAtmosphereBoundary(
                    atmosphere, r, mu, atmosphere.mie_scale_height);
            Vector3 ozone = atmosphere.ozone_extinction_spectrum *
                ComputeOpticalLengthToTopAtmosphereBoundary(
                    atmosphere, r, mu, atmosphere.ozone_scale_height);
            var sum = rayleigh + mie + ozone;
            return new Vector3(
                Mathf.Exp(-sum.x),
                Mathf.Exp(-sum.y),
                Mathf.Exp(-sum.z)
                );
        }

        public static Vector3 GetTransmittanceToSun(
            AtmosphereConfig atmosphere,
            float r, float mu_s) {
            float sin_theta_h = atmosphere.atmosphere_bot_radius / r;
            float cos_theta_h = -Mathf.Sqrt(Mathf.Max(1.0f - sin_theta_h * sin_theta_h, 0.0f));

            var transmittanceToCenter = ComputeTransmittanceToTopAtmosphereBoundary(
                atmosphere, r, mu_s);

            var lower_bound = -sin_theta_h * atmosphere.atmosphere_sun_angular_radius;
            var upper_bound = sin_theta_h * atmosphere.atmosphere_sun_angular_radius;

            var fraction = (mu_s - cos_theta_h - lower_bound) / (upper_bound - lower_bound);
            fraction = Mathf.Clamp01(fraction);

            return transmittanceToCenter * fraction;
        }
    }
}