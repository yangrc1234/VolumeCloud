using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
[ExecuteInEditMode,RequireComponent(typeof(Camera))]
    public class CloudVolumeRenderer : EffectBase {
    public Material mat;
    private RenderTexture[] fullBuffer;
    private int fullBufferIndex;
    private RenderTexture lowresBuffer;
    private Matrix4x4 lastFrameVP;
    private new Camera mcam;
    // The index of 4x4 pixels.
    private int frameIndex = 0;

    private static int[,] offset = new int[16, 2];

    private void OnEnable() {
        SetupOffsets();
        ChangeResolution();
    }

    void SetupOffsets() {
        int index = 0;
        for (int i = 0; i < 4; i++) {
            for (int j = 0; j < 4; j++) {
                offset[index, 0] = i;
                offset[index++, 1] = j;
            }
        }
    }

    void ChangeResolution() {
        
    }

    private void OnRenderImage(RenderTexture source, RenderTexture destination) {
        mcam = GetComponent<Camera>();
        var width = mcam.pixelWidth;
        var height = mcam.pixelHeight;

        EnsureArray(ref fullBuffer, 2);
        EnsureRenderTarget(ref fullBuffer[0], width, height, RenderTextureFormat.ARGBHalf, FilterMode.Bilinear);
        EnsureRenderTarget(ref fullBuffer[1], width, height, RenderTextureFormat.ARGBHalf, FilterMode.Bilinear);
        EnsureRenderTarget(ref lowresBuffer, width /4 , height/4, RenderTextureFormat.ARGBHalf, FilterMode.Point);

        frameIndex = (frameIndex + 1)% 16;
        fullBufferIndex = (fullBufferIndex + 1) % 2;

        //1. Render low-res buffer.
        float offsetX = (float)offset[frameIndex, 0] ;
        float offsetY = (float)offset[frameIndex, 1] ;
        var jitteredProjectionMatrix = mcam.GetProjectionMatrix(offsetX, offsetY);
        mat.SetMatrix("_ProjectionToWorld", mcam.cameraToWorldMatrix * jitteredProjectionMatrix.inverse);
        Graphics.Blit(null, lowresBuffer, mat, 0);
        
        //2. Blit low-res buffer with previous image to make full-res result.
        mat.SetVector("_Jitter", new Vector2(offsetX, offsetY));
        mat.SetTexture("_LowresCloudTex", lowresBuffer);
        //No reprojection is done here. see static first.
        Graphics.Blit(fullBuffer[fullBufferIndex], fullBuffer[fullBufferIndex ^ 1], mat, 1);

        //3. blit full-res result with final image.
    }
}