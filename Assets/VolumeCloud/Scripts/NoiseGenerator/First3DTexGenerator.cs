using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Yangrc.VolumeCloud {
    [System.Serializable]
    public class First3DTexGenerator : ITextureGenerator {
        public int texResolution = 32;
        public int perlinOctaves = 4;
        public int channel1PerlinPeriod = 16;
        public int channel2WorleyPeriod = 16;
        public int channel3WorleyPeriod = 32;
        public int channel4WorleyPeriod = 64;

        public Color Sample(Vector3 pos) {
            Color res = new Color();
            res.r = PerlinNoiseGenerator.OctaveNoise(pos, channel1PerlinPeriod, perlinOctaves);
            res.g = WorleyNoiseGenerator.OctaveNoise(pos, channel2WorleyPeriod, 3);
            res.b = WorleyNoiseGenerator.OctaveNoise(pos, channel3WorleyPeriod, 3);
            res.a = WorleyNoiseGenerator.OctaveNoise(pos, channel4WorleyPeriod, 3);
            return res;
        }
    }

    [System.Serializable]
    public class Second3DTexGenerator : ITextureGenerator {
        public int texResolution = 32;
        public int channel1WorleyFreq = 16;
        public int channel2WorleyFreq = 32;
        public int channel3WorleyFreq = 64;
        public Color Noise(Vector3 pos) {
            Color res = new Color();
            res.r = WorleyNoiseGenerator.OctaveNoise(pos, channel1WorleyFreq, 3);
            res.g = WorleyNoiseGenerator.OctaveNoise(pos, channel2WorleyFreq, 3);
            res.b = WorleyNoiseGenerator.OctaveNoise(pos, channel3WorleyFreq, 3);
            res.a = 1.0f;
            return res;
        }

        public Color Sample(Vector3 pos) {
            return Noise(pos);
        }
    }
}