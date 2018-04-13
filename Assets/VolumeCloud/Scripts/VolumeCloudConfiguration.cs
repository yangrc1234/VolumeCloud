using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[CreateAssetMenu]
public class VolumeCloudConfiguration : ScriptableObject {
    public float overallDensity;
    public float overallSize;

    public Vector2 windDirection;
    public float windSpeed;

    public float baseshapeTile;
    public float detailTile;
    public float curlTile;

    public float detailStrength;
    public float curlStrength;

    public float beerLawStrength;

    public float silverIntensity;
    public float silverSpread;

    public Color ambientColor;

    public Color atmosphereColor;
    public float atmosphereSaturateDistance;

    public void ApplyToMaterial(Material mat) {

    }
}
