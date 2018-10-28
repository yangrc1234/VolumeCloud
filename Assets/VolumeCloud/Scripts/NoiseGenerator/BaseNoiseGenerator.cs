using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Yangrc.VolumeCloud {
    public abstract class BaseNoiseGenerator : INoiseGenerator {
        public int period = 16;
        public abstract float Noise(Vector3 pos);
    }
}