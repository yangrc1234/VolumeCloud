using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Yangrc.AtmosphereScattering {
    [RequireComponent(typeof(Light))]
    public class SunIntensityController : MonoBehaviour {

        private new Light light;

        //This is the "base" position, used to sample transmittance to sun, and set a final intensity.
        //
        //In real-life, objects at different position are affected by different sun intensity.
        //But in Unity all objects share the same sun.
        //So we need to set a base position, and assume all objects are at this position when affected by sun.
        public Vector3 basePosition = new Vector3(0.0f, 50.0f, 0.0f);

        private void Awake() {
            light = GetComponent<Light>();
        }

        // Update is called once per frame
        void Update() {
            var t = AtmosphereScatteringLutManager.instance;
            if (t != null) {
                //Sun-zenith cos.
                var mu_s = Vector3.Dot(Vector3.down, transform.forward);
                var radianceAtZero = t.GetRadianceAt(mu_s, basePosition);

                light.intensity = radianceAtZero.magnitude / (2 * Mathf.PI);
                var normalized = radianceAtZero.normalized;
                light.color = new Color(normalized.x, normalized.y, normalized.z);
            }
        }
    }
}
