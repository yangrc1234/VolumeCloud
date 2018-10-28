using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Yangrc.VolumeCloud {
    [System.Serializable]
    public class CurlNoiseGenerator : ITextureGenerator {
        public Texture2D perlinNoise;
        public float brightness = 10.0f;
        public float scale = 10.0f;
        public PerlinNoiseGenerator perlin;
        private float noise(float x, float y) {
            return perlin.Noise(new Vector3(x, y));
        }
        public Color Sample(float x, float y) {
            float eps = 1.0f / 128.0f;
            float n1, n2, a, b;

            n1 = noise(x, y + eps);
            n2 = noise(x, y - eps);
            a = (n1 - n2) / (2);
            n1 = noise(x + eps, y);
            n2 = noise(x - eps, y);
            b = (n1 - n2) / (2);

            Vector2 curl = new Vector2(a, -b);
            return new Color(curl.x, curl.y, 0);
        }

        public Color Sample(Vector3 pos) {
            return Sample(pos.x, pos.y);
        }
    }
}