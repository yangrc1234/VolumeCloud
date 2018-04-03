using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[System.Serializable]
public class WorleyNoiseGenerator : BaseNoiseGenerator {
    public float brightness = 1.0f;
    public float contrast = 1.0f;
    public int octaves = 4;

    public override float Noise(Vector3 pos) {
        return Mathf.Clamp01(((OctaveNoise(pos, period, octaves)) + (brightness - 1.0f)) * contrast);
    }

    private static int wrap(int n, int period) {
        return n >= 0 ? n % period : period + n;
    }

    public static float Noise(Vector3 pos, int period) {
        pos *= period;
        var x = Mathf.FloorToInt(pos.x);
        var y = Mathf.FloorToInt(pos.y);
        var z = Mathf.FloorToInt(pos.z);
        Vector3Int boxPos = new Vector3Int(x, y, z);
        float minDistance = float.MaxValue;

        for (int xoffset = -1; xoffset <= 1; xoffset++) {
            for (int yoffset = -1; yoffset <= 1; yoffset++) {
                for (int zoffset = -1; zoffset <= 1; zoffset++) {
                    var newboxPos = boxPos + new Vector3Int(xoffset, yoffset, zoffset);
                    var hashValue = (wrap(newboxPos.x,period) + wrap(newboxPos.y,period) * 131 + wrap(newboxPos.z,period) * 17161) % int.MaxValue;
                    UnityEngine.Random.InitState(hashValue);
                    var featurePoint = new Vector3(UnityEngine.Random.value + newboxPos.x, UnityEngine.Random.value + newboxPos.y, UnityEngine.Random.value + newboxPos.z);
                    minDistance = Mathf.Min(minDistance, Vector3.Distance(pos, featurePoint));
                }
            }
        }
        return 1.0f - minDistance;
    }

    public static float OctaveNoise(Vector3 pos, int period, int octaves, float persistence = 0.5f) {
        float result = 0.0f;
        float amp = .5f;
        float freq = 1.0f;
        float totalAmp = 0.0f;
        for (int i = 0; i < octaves; i++) {
            totalAmp += amp;
            result += Noise(pos, Mathf.RoundToInt(freq * period)) * amp;
            amp *= persistence;
            freq /= persistence;
        }
        if (octaves == 0)
            return 0.0f;
        return result / totalAmp;
    }
}
