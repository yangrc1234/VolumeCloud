using System;
using UnityEngine;

public class NoiseTextureAdapter  : ITextureGenerator{
    private INoiseGenerator noiseGen;
    public NoiseTextureAdapter(INoiseGenerator noiseGen) {
        this.noiseGen = noiseGen;
    }

    public Color Sample(Vector3 pos) {
        return noiseGen.Noise(pos) * Color.white;
    }
}

public interface ITextureGenerator {
    Color Sample(Vector3 pos);
}

public interface INoiseGenerator {
    float Noise(Vector3 pos);
}