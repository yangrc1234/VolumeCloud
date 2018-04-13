using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[System.Serializable]
public class First3DTexGenerator : ITextureGenerator{
    public int texResolution = 32;
    public int worleyOcataves = 4;
    public int perlinOctaves = 4;
    public int channel1WorleyPeriod = 16;
    public int channel1PerlinPeriod = 16;
    [Range(0, 1)]
    public float channel1WorleyPercent = 0.5f;
    public int channel2WorleyPeriod = 16;
    public int channel3WorleyPeriod = 32;
    public int channel4WorleyPeriod = 64;

    public Color Sample(Vector3 pos) {
        Color res = new Color();
        res.r = channel1WorleyPercent * WorleyNoiseGenerator.OctaveNoise(pos, channel1WorleyPeriod, worleyOcataves)
            + (1 - channel1WorleyPercent) * PerlinNoiseGenerator.OctaveNoise(pos, channel1PerlinPeriod,perlinOctaves);
     //   res.g = WorleyNoiseGenerator.OctaveNoise(pos, channel2WorleyPeriod, worleyOcataves);
     //   res.b = WorleyNoiseGenerator.OctaveNoise(pos, channel3WorleyPeriod, worleyOcataves);
     //   res.a = WorleyNoiseGenerator.OctaveNoise(pos, channel4WorleyPeriod, worleyOcataves);
        return res;
    }
}

[System.Serializable]
public class Second3DTexGenerator : ITextureGenerator {
    public int texResolution = 32;
    public int worleyOcataves = 4;
    public int channel1WorleyFreq = 16;
    public int channel2WorleyFreq = 32;
    public int channel3WorleyFreq = 64;
    public Color Noise(Vector3 pos) {
        Color res = new Color();
        res.r = WorleyNoiseGenerator.OctaveNoise(pos, channel1WorleyFreq, worleyOcataves);
        res.g = WorleyNoiseGenerator.OctaveNoise(pos, channel2WorleyFreq, worleyOcataves);
        res.b = WorleyNoiseGenerator.OctaveNoise(pos, channel3WorleyFreq, worleyOcataves);
        return res;
    }

    public Color Sample(Vector3 pos) {
        return Noise(pos);
    }
}
