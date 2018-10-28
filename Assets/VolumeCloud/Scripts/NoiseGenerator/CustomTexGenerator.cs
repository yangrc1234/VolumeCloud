using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Yangrc.VolumeCloud {
    [System.Serializable]
    public class CustomTexGenerator : INoiseGenerator {
        public float channel1WorleyPercent = 0.5f;
        public int channel1WorleyPeriod = 4;
        public int channel1PerlinPeriod = 4;
        public int worleyOcataves = 4;
        public int perlinOctaves = 4;

        public float Noise(Vector3 pos) {
            return channel1WorleyPercent * WorleyNoiseGenerator.OctaveNoise(pos, channel1WorleyPeriod, worleyOcataves)
                + (1 - channel1WorleyPercent) * PerlinNoiseGenerator.OctaveNoise(pos, channel1PerlinPeriod, perlinOctaves);
        }
    }
}