using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class CameraControl : MonoBehaviour {
    public float distance = 10.0f;
    public Vector3 center;

    private Vector2 lastFrameMouse;

    public float scale = 1.0f;

    public float distanceSpeed = .1f;
    public float rotationSpeed = .1f;

    private void Update() {
        var mouseDelta = (Vector2)Input.mousePosition - lastFrameMouse;
        lastFrameMouse = Input.mousePosition;

        if (Input.GetMouseButton(2)) {
            //Translate.
            center += ((transform.right * mouseDelta.x) + (transform.up * mouseDelta.y)) * scale * distance;
        }

        if (Input.GetMouseButton(1)) {
            distance += mouseDelta.x * distanceSpeed * Mathf.Max(1.0f, 0.1f * distance);
        }

        if (Input.GetMouseButton(0)) {
            //Rotate.
            var currentRotation = transform.rotation;
            var currentYaw = currentRotation.eulerAngles.y;
            var currentPitch = currentRotation.eulerAngles.x;

            currentPitch -= mouseDelta.y * rotationSpeed;
            currentYaw += mouseDelta.x * rotationSpeed;
            currentPitch = Mathf.Max(0, currentPitch);

            var newRotation = Quaternion.Euler(currentPitch, currentYaw, 0.0f);

            transform.rotation = newRotation;
        }

        transform.position = transform.rotation * Vector3.forward * -distance + center;
    }
}
