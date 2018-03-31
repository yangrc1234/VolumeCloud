using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
[ExecuteInEditMode,RequireComponent(typeof(Camera))]
public class CloudVolumeRenderer : MonoBehaviour {
    public Material mat;

    private void OnRenderImage(RenderTexture source, RenderTexture destination) {
        Camera cam = Camera.current;
        RenderTexture temp = RenderTexture.GetTemporary(cam.pixelWidth, cam.pixelHeight, 0, RenderTextureFormat.ARGB32);
        mat.SetMatrix("_ProjectionToWorld", cam.cameraToWorldMatrix);
        Graphics.Blit(null, temp, mat);
        Graphics.Blit(temp, dest:null);
        temp.Release();
    }
}