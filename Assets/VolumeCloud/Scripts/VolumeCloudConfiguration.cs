using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[CreateAssetMenu]
public class VolumeCloudConfiguration : ScriptableObject {
    [Header("Shape")]
    public float baseTile;
    public float detailTile;
    [Range(0,1)]
    public float detailStrength;
    public float curlTile;
    public float curlStrength;
    public float topOffset;

    [Range(0,1)]
    public float overallDensity;
    [Range(0,1)]
    public float cloudTypeModifier;
    [Range(0,1)]
    public float cloudCoverageModifier;
    public float overallSize;

    public Vector2 windDirection;
    public float windSpeed;
    
    [Header("Lighting")]
    public float transmittance;
    public float beerLawStrength;
    public float silverIntensity;
    public float silverSpread;

    public Color ambientColor;
    public Color atmosphereColor;
    public float atmosphereSaturateDistance;

    [Header("Weather map")]
    [Tooltip("R for coverage, G for density, B for cloud type")]
    public Texture2D weatherTex;
    public float weatherTexSize = 40000;

    private class PropertyHash {
        public static int baseTex = Shader.PropertyToID("_BaseTex");
        public static int detailTex = Shader.PropertyToID("_DetailTex");
        public static int curlNoise = Shader.PropertyToID("_CurlNoise");
        public static int blueNoise = Shader.PropertyToID("_BlueNoise");        //These are set in different scripts.

        public static int baseTile = Shader.PropertyToID("_BaseTile");
        public static int detailTile = Shader.PropertyToID("_DetailTile");
        public static int detailStrength = Shader.PropertyToID("_DetailStrength");
        public static int curlTile = Shader.PropertyToID("_CurlTile");
        public static int curlStrength = Shader.PropertyToID("_CurlStrength");
        public static int topOffset = Shader.PropertyToID("_CloudTopOffset");
        public static int cloudSize = Shader.PropertyToID("_CloudSize");
        public static int cloudDensity = Shader.PropertyToID("_CloudDensity");
        public static int cloudTypeModifier = Shader.PropertyToID("_CloudTypeModifier");
        public static int cloudCoverageModifier = Shader.PropertyToID("_CloudCoverageModifier");
        public static int windDirection = Shader.PropertyToID("_WindDirection");
        public static int weatherTex = Shader.PropertyToID("_WeatherTex");
        public static int weatherTexSize = Shader.PropertyToID("_WeatherTexSize");
        public static int beerLaw = Shader.PropertyToID("_BeerLaw");
        public static int transmittance = Shader.PropertyToID("_Transmittance");
        public static int silverIntensity = Shader.PropertyToID("_SilverIntensity");
        public static int silverSpread = Shader.PropertyToID("_SilverSpread");

        public static int atmosphereColor = Shader.PropertyToID("_AtmosphereColor");
        public static int atmosphereColorSaturateDistance = Shader.PropertyToID("_AtmosphereColorSaturateDistance");
        public static int ambientColor = Shader.PropertyToID("_AmbientColor");
    }

    public void ApplyToMaterial(Material mat) {
        mat.SetFloat(PropertyHash.baseTile, baseTile);
        mat.SetFloat(PropertyHash.detailTile, detailTile);
        mat.SetFloat(PropertyHash.detailStrength, detailStrength);
        mat.SetFloat(PropertyHash.curlTile, curlTile);
        mat.SetFloat(PropertyHash.curlStrength, curlStrength);
        mat.SetFloat(PropertyHash.topOffset, topOffset);
        mat.SetFloat(PropertyHash.cloudSize, overallSize);
        mat.SetFloat(PropertyHash.cloudDensity, overallDensity);
        mat.SetFloat(PropertyHash.cloudTypeModifier, cloudTypeModifier);
        mat.SetFloat(PropertyHash.cloudCoverageModifier, cloudCoverageModifier);

        mat.SetVector(PropertyHash.windDirection, new Vector4(windDirection.x,windDirection.y, windSpeed,-windSpeed));
        mat.SetTexture(PropertyHash.weatherTex, weatherTex);
        mat.SetFloat(PropertyHash.weatherTexSize, weatherTexSize);
        mat.SetFloat(PropertyHash.beerLaw, beerLawStrength);
        mat.SetFloat(PropertyHash.transmittance, transmittance);
        mat.SetFloat(PropertyHash.silverIntensity, silverIntensity);
        mat.SetFloat(PropertyHash.silverSpread, silverSpread);

        mat.SetColor(PropertyHash.atmosphereColor, atmosphereColor);
        mat.SetFloat(PropertyHash.atmosphereColorSaturateDistance, atmosphereSaturateDistance);
        mat.SetColor(PropertyHash.ambientColor, ambientColor);
    }
}
