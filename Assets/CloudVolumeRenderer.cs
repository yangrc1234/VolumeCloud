using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
[ExecuteInEditMode,RequireComponent(typeof(Camera))]
    public class CloudVolumeRenderer : MonoBehaviour {
    public Material mat;
    public Shader bilateralBlurShader;
    private RenderTexture halfresCloudBuffer;
    private RenderTexture fullresCloudBuffer;
    private RenderTexture cloudBuffer;
    private RenderTexture halfresDepth;
    private new Camera camera;
    private Material blurMat {
        get {
            return _blurMat == null ? _blurMat = new Material(bilateralBlurShader) : _blurMat;
        }
    }
    private Material _blurMat;
    private bool requireRefresh = true;

    private void OnEnable() {
        requireRefresh = true;
    }

    private void OnValidate() {
        requireRefresh = true;
    }

    private void Update() {
        if (halfresCloudBuffer == null || fullresCloudBuffer == null || cloudBuffer == null || halfresDepth == null) {
            requireRefresh = true;
        }
    }

    void ChangeResolution() {
        requireRefresh = false;
        var width = camera.pixelWidth;
        var height = camera.pixelHeight;

        if (halfresCloudBuffer != null) {
            halfresCloudBuffer.Release();
        }
        halfresCloudBuffer = new RenderTexture(width/2, height/2, 0, RenderTextureFormat.ARGBHalf);
        halfresCloudBuffer.Create();
        halfresCloudBuffer.name = "HalfresCloud";
        blurMat.SetTexture("_HalfResColor", halfresCloudBuffer);

        if (cloudBuffer != null) {
            cloudBuffer.Release();
        }
        cloudBuffer = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBHalf);
        cloudBuffer.Create();
        cloudBuffer.name = "CloudBuffer";
        mat.SetTexture("_CloudTex", cloudBuffer);

        if (halfresDepth != null) {
            halfresDepth.Release();
        }
        halfresDepth = new RenderTexture(width/2, height/2, 0, RenderTextureFormat.ARGBHalf);
        halfresDepth.Create();
        halfresDepth.name = "HalfresDepth";
        halfresDepth.filterMode = FilterMode.Point;
        blurMat.SetTexture("_HalfResDepthBuffer", halfresDepth);
    }

    private void OnRenderImage(RenderTexture source, RenderTexture destination) {
        if (requireRefresh) {
            ChangeResolution();
        }
        Camera cam = Camera.current;
        mat.SetMatrix("_ProjectionToWorld", cam.cameraToWorldMatrix * cam.projectionMatrix.inverse);
        var camTexture = RenderTexture.active;
        /*
                RenderTexture temp = RenderTexture.GetTemporary(cam.pixelWidth / 2, cam.pixelHeight / 2, 0, RenderTextureFormat.ARGBHalf);

                //half-res depthtex.
                Graphics.Blit(null, halfresDepth, blurMat, 4);

                //Draw cloud to temp.
                Graphics.Blit(null, halfresCloudBuffer, mat, 0);
                //Do upscale.
                Graphics.Blit(halfresCloudBuffer, temp, blurMat, 2);
                Graphics.Blit(temp, halfresCloudBuffer, blurMat, 3); 
                //upscale
                Graphics.Blit(halfresCloudBuffer, cloudBuffer, blurMat, 5);
                mat.SetTexture("_CloudTex", cloudBuffer);
                Graphics.Blit(source, destination, mat,1);
                temp.Release();
                */

        //Draw cloud to temp.
        Graphics.Blit(null, cloudBuffer, mat, 0);
        Graphics.Blit(source, destination, mat, 1);
    }
}