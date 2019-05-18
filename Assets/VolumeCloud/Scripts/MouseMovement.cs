using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Yangrc.VolumeCloud.Sample {
    public class MouseMovement: MonoBehaviour {
        private void Update() {
            float yaw = Input.GetAxis("Mouse X");
            float pitch = -Input.GetAxis("Mouse Y");
            var currAngle = transform.rotation.eulerAngles;
            currAngle.x += pitch;
            currAngle.y += yaw;
            transform.rotation = Quaternion.Euler(currAngle);
        }
    }
}