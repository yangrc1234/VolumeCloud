using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Yangrc.VolumeCloud {
    [CreateAssetMenu]
    public class VolumeCloudConfiguration : ScriptableObject {

        [Header("Weather map")]
        [Tooltip("R for coverage, G for density, B for cloud type")]
        public Texture2D weatherTex;
        public float weatherTexSize = 40000;

        [Header("Shape")]
        public Texture3D baseTexture;
        [Range(0, 5)]
        public float baseTile = 2.0f;
        public Texture2D heightDensityMap;
        public float overallSize = 50000;
        public float topOffset = 0.0f;

        [Header("Shape - Detail")]
        public Texture3D detailTexture;
        [Range(0, 80)]
        public float detailTile = 36.0f;
        [Range(.01f, .5f)]
        public float detailStrength = 0.2f;

        [Header("Shape - Curl")]
        public Texture2D curlNoise;
        [Range(0.001f, 1.0f)]
        public float curlTile = 0.01f;
        public float curlStrength = 5.0f;

        [Header("Shape - Modifiers")]
        [Range(0, 1)]
        public float overallDensity = 1.0f;
        [Range(0, 1)]
        public float cloudTypeModifier = 1.0f;
        [Range(0, 1)]
        public float cloudCoverageModifier = 1.0f;

        [Header("Shape - Wind")]
        public Vector2 windDirection;
        public float windSpeed;

        [Header("Lighting")]
        public Color ambientColor = new Color(214, 37, 154);
        public const float COEFFICIENT_SCALE = 1e-2f;
        [Range(0.1f, 2.0f)]
        public float scatteringCoefficient = .5f;
        [Range(0.1f, 2.0f)]
        public float extinctionCoefficient = .52f;  

        [Header("Lighting - Multi Scattering Approximation")]
        [Range(0.01f, 1)]
        [Tooltip("Value used in multi-scattering approximation, higher causes more light be scattered. Must be lower than multiScatteringExtinction.")]
        public float multiScatteringScattering = .5f;
        [Range(0.01f, 1)]
        [Tooltip("Value used in multi-scattering approximation, higher causes more light be extincted. Must be higher than multiScatteringScattering.")]
        public float multiScatteringExtinction = .5f;
        [Range(0.01f, 1)]
        [Tooltip("Value used in multi-scattering approximation, phase function is p(g * pow(multiScatteringEC, octave), theta)")]
        public float multiScatteringEC = .5f;

        [Header("Lighting - Silver")]
        public float silverSpread = 0.1f;

        [Header("Lighting - Atmosphere")]
        public float atmosphereSaturateDistance = 100000.0f;

        private class PropertyHash {
            public static int baseTex = Shader.PropertyToID("_BaseTex");
            public static int baseTile = Shader.PropertyToID("_BaseTile");

            public static int detailTex = Shader.PropertyToID("_DetailTex");
            public static int detailTile = Shader.PropertyToID("_DetailTile");
            public static int detailStrength = Shader.PropertyToID("_DetailStrength");

            public static int curlNoise = Shader.PropertyToID("_CurlNoise");
            public static int curlTile = Shader.PropertyToID("_CurlTile");
            public static int curlStrength = Shader.PropertyToID("_CurlStrength");

            public static int heightDensity = Shader.PropertyToID("_HeightDensity");

            public static int topOffset = Shader.PropertyToID("_CloudTopOffset");
            public static int cloudSize = Shader.PropertyToID("_CloudSize");

            public static int cloudOverallDensity = Shader.PropertyToID("_CloudOverallDensity");
            public static int cloudTypeModifier = Shader.PropertyToID("_CloudTypeModifier");
            public static int cloudCoverageModifier = Shader.PropertyToID("_CloudCoverageModifier");

            public static int windDirection = Shader.PropertyToID("_WindDirection");
            public static int weatherTex = Shader.PropertyToID("_WeatherTex");
            public static int weatherTexSize = Shader.PropertyToID("_WeatherTexSize");
            public static int scatteringCoefficient = Shader.PropertyToID("_ScatteringCoefficient");
            public static int extinctionCoefficient = Shader.PropertyToID("_ExtinctionCoefficient");
            public static int multiScatteringA = Shader.PropertyToID("_MultiScatteringA");
            public static int multiScatteringB = Shader.PropertyToID("_MultiScatteringB");
            public static int multiScatteringC = Shader.PropertyToID("_MultiScatteringC");
            public static int silverSpread = Shader.PropertyToID("_SilverSpread");

            public static int atmosphereColorSaturateDistance = Shader.PropertyToID("_AtmosphereColorSaturateDistance");
            public static int ambientColor = Shader.PropertyToID("_AmbientColor");
        }

        public void ApplyToMaterial(Material mat) {
            mat.SetTexture(PropertyHash.baseTex, baseTexture);
            mat.SetTexture(PropertyHash.detailTex, detailTexture);
            mat.SetTexture(PropertyHash.curlNoise, curlNoise);

            mat.SetFloat(PropertyHash.baseTile, baseTile);
            mat.SetTexture(PropertyHash.heightDensity, heightDensityMap);
            mat.SetFloat(PropertyHash.detailTile, detailTile);

            mat.SetFloat(PropertyHash.detailStrength, detailStrength);
            mat.SetFloat(PropertyHash.curlTile, curlTile);
            mat.SetFloat(PropertyHash.curlStrength, curlStrength);
            mat.SetFloat(PropertyHash.topOffset, topOffset);
            mat.SetFloat(PropertyHash.cloudSize, overallSize);
            mat.SetFloat(PropertyHash.cloudOverallDensity, overallDensity);
            mat.SetFloat(PropertyHash.cloudTypeModifier, cloudTypeModifier);
            mat.SetFloat(PropertyHash.cloudCoverageModifier, cloudCoverageModifier);

            mat.SetVector(PropertyHash.windDirection, new Vector4(windDirection.x, windDirection.y, windSpeed, -windSpeed));
            mat.SetTexture(PropertyHash.weatherTex, weatherTex);
            mat.SetFloat(PropertyHash.weatherTexSize, weatherTexSize);
            mat.SetFloat(PropertyHash.scatteringCoefficient, scatteringCoefficient * COEFFICIENT_SCALE);
            mat.SetFloat(PropertyHash.extinctionCoefficient, extinctionCoefficient * COEFFICIENT_SCALE);
            mat.SetFloat(PropertyHash.multiScatteringA, multiScatteringScattering );
            mat.SetFloat(PropertyHash.multiScatteringB, multiScatteringExtinction );
            mat.SetFloat(PropertyHash.multiScatteringC, multiScatteringEC );
            mat.SetFloat(PropertyHash.silverSpread, silverSpread);

            mat.SetFloat(PropertyHash.atmosphereColorSaturateDistance, atmosphereSaturateDistance);
            mat.SetColor(PropertyHash.ambientColor, ambientColor);
        }
    }
}