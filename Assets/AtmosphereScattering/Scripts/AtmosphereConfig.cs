using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Yangrc.AtmosphereScattering {
    [CreateAssetMenu]
    public class AtmosphereConfig : ScriptableObject {

        static readonly Vector3 OZoneConst = 6e-7f * new Vector3(3.426f, 8.298f, 0.356f);
        static readonly Vector3 RayleighScatteringConst = 1e-6f * new Vector3(5.8f, 13.5f, 33.1f);
        static readonly float MieScatteringConst = 2e-6f;

        private static class Keys {
            public static int atmosphere_top_radius = Shader.PropertyToID("atmosphere_top_radius");
            public static int atmosphere_bot_radius = Shader.PropertyToID("atmosphere_bot_radius");
            public static int atmosphere_sun_angular_radius = Shader.PropertyToID("atmosphere_sun_angular_radius");
            public static int rayleigh_scattering = Shader.PropertyToID("rayleigh_scattering");
            public static int rayleigh_scale_height = Shader.PropertyToID("rayleigh_scale_height");
            public static int mie_scattering = Shader.PropertyToID("mie_scattering");
            public static int mie_extinction = Shader.PropertyToID("mie_extinction");
            public static int mie_scale_height = Shader.PropertyToID("mie_scale_height");
            public static int mie_phase_function_g = Shader.PropertyToID("mie_phase_function_g");
            public static int absorption_extinction = Shader.PropertyToID("absorption_extinction");
            public static int absorption_extinction_scale_height = Shader.PropertyToID("absorption_extinction_scale_height");
            public static int lightingScale = Shader.PropertyToID("_LightScale");
            public static int sunRadianceOnAtm = Shader.PropertyToID("_SunRadianceOnAtm");
        }

        public void Apply(Material mat) {
            Shader.SetGlobalFloat(Keys.atmosphere_top_radius, atmosphere_top_radius);
            Shader.SetGlobalFloat(Keys.atmosphere_bot_radius, atmosphere_bot_radius);
            Shader.SetGlobalFloat(Keys.atmosphere_sun_angular_radius, atmosphere_sun_angular_radius);
            Shader.SetGlobalVector(Keys.rayleigh_scattering, rayleigh_scattering_spectrum);
            Shader.SetGlobalFloat(Keys.rayleigh_scale_height, rayleigh_scale_height);
            Shader.SetGlobalFloat(Keys.mie_scattering, AtmosphereDensity  * mie_scattering * MieScatteringConst);
            Shader.SetGlobalFloat(Keys.mie_extinction, mie_extinction_spectrum);
            Shader.SetGlobalFloat(Keys.mie_scale_height, mie_scale_height);
            Shader.SetGlobalFloat(Keys.mie_phase_function_g, mie_phase_function_g);
            Shader.SetGlobalVector(Keys.absorption_extinction, ozone_extinction_spectrum);
            Shader.SetGlobalFloat(Keys.absorption_extinction_scale_height, ozone_scale_height);
            Shader.SetGlobalFloat(Keys.lightingScale, LightingScale);
            Shader.SetGlobalVector(Keys.sunRadianceOnAtm, SunRadianceOnAtmosphere);
        }

        public void Apply(ComputeShader shader) {
            shader.SetFloat(Keys.atmosphere_top_radius, atmosphere_top_radius);
            shader.SetFloat(Keys.atmosphere_bot_radius, atmosphere_bot_radius);
            shader.SetFloat(Keys.atmosphere_sun_angular_radius, atmosphere_sun_angular_radius);
            shader.SetVector(Keys.rayleigh_scattering, rayleigh_scattering_spectrum);
            shader.SetFloat(Keys.rayleigh_scale_height, rayleigh_scale_height);
            shader.SetFloat(Keys.mie_scattering, AtmosphereDensity * mie_scattering * MieScatteringConst);
            shader.SetFloat(Keys.mie_extinction, mie_extinction_spectrum);
            shader.SetFloat(Keys.mie_scale_height, mie_scale_height);
            shader.SetFloat(Keys.mie_phase_function_g, mie_phase_function_g);
            shader.SetVector(Keys.absorption_extinction, ozone_extinction_spectrum);
            shader.SetFloat(Keys.absorption_extinction_scale_height, ozone_scale_height);
            shader.SetVector(Keys.sunRadianceOnAtm, SunRadianceOnAtmosphere);
        }

        public float AtmosphereDensity = 1.0f;
        public Vector3 SunRadianceOnAtmosphere = new Vector3(1.0f, 1.0f, 1.0f);
        public float LightingScale = 2.0f * 3.1415926f;
        public float atmosphere_top_radius = 6.36e6f + 6e4f;
        public float atmosphere_bot_radius = 6.36e6f;
        public float atmosphere_sun_angular_radius = 0.0087f;
        public float rayleigh_scattering = 1.0f;
        public float rayleigh_scale_height = 8000.0f;
        public Vector3 rayleigh_scattering_spectrum {
            get {
                return AtmosphereDensity * rayleigh_scattering * RayleighScatteringConst;
            }
        }
        public Vector3 ozone_extinction_spectrum {
            get {
                return AtmosphereDensity * OZoneConst * ozone_extinction;
            }
        }
        public float mie_scattering = 1.0f;
        public float mie_extinction {
            get {
                return mie_scattering * 1.1f;
            }
        }
        public float mie_extinction_spectrum {
            get {
                return AtmosphereDensity * mie_extinction * MieScatteringConst;
            }
        }
        public float mie_scale_height = 1200.0f;
        public float mie_phase_function_g = 0.8f;
        public float ozone_extinction = 1.0f;
        public float ozone_scale_height = 1000.0f;

        public void CopyDataFrom(AtmosphereConfig config) {
            this.AtmosphereDensity = config.AtmosphereDensity;
            this.LightingScale = config.LightingScale;
            this.SunRadianceOnAtmosphere = config.SunRadianceOnAtmosphere;
            this.atmosphere_top_radius = config.atmosphere_top_radius;
            this.atmosphere_bot_radius = config.atmosphere_bot_radius;
            this.atmosphere_sun_angular_radius = config.atmosphere_sun_angular_radius;
            this.rayleigh_scattering = config.rayleigh_scattering;
            this.rayleigh_scale_height = config.rayleigh_scale_height;
            this.mie_scattering = config.mie_scattering;
            this.mie_scale_height = config.mie_scale_height;
            this.mie_phase_function_g = config.mie_phase_function_g;
            this.ozone_extinction = config.ozone_extinction;
            this.ozone_scale_height = config.ozone_scale_height;

    }
}
}
