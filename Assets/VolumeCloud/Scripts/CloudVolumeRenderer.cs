using System;
using System.Linq;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
[ImageEffectAllowedInSceneView]
[ExecuteInEditMode,RequireComponent(typeof(Camera))]
    public class CloudVolumeRenderer : EffectBase {
    public VolumeCloudConfiguration configuration;
    private Material mat;

    private RenderTexture[] fullBuffer;
    private int fullBufferIndex;
    private RenderTexture lowresBuffer;
    private Matrix4x4 prevV;
    private Camera mcam;
    
    // The index of 4x4 pixels.
    private int frameIndex = 0;

    private static int[,] offset = new int[16, 2]; 

    private void OnEnable() {
        SetupOffsets();
    }

    void SetupOffsets() {
        List<int> tempList = new List<int>();
        for (int i = 0; i < 16; i++) {
            tempList.Add(i);
        }
        var t = new System.Random(114514);
        tempList = tempList.OrderBy(e => t.Next()).ToList();

        for (int i = 0; i < 4; i++) {
            for (int j = 0; j < 4; j++) {
                var index = tempList[i * 4 + j];
                offset[index, 0] = i;
                offset[index, 1] = j;
            }
        }
    }

    void EnsureMaterial() {
        if (mat == null) {
            var shader = Resources.Load<Shader>("VolumeCloud/Shaders/CloudShader");
            var baseTex = Resources.Load<Texture3D>("VolumeCloud/Textures/BaseNoise");
            var detailTex = Resources.Load<Texture3D>("VolumeCloud/Textures/DetailNoise");
            var curlTex = Resources.Load<Texture2D>("VolumeCloud/Textures/CurlNoise");
            var blurTex = Resources.Load<Texture2D>("VolumeCloud/Textures/BlueNoise");
            mat = new Material(shader);
            mat.SetTexture("_BaseTex", baseTex);
            mat.SetTexture("_DetailTex", detailTex);
            mat.SetTexture("_CurlNoise", curlTex);
            mat.SetTexture("_BlueNoise", blurTex);
        }
    }

    private void OnRenderImage(RenderTexture source, RenderTexture destination) {
        if (this.configuration == null) {
            Graphics.Blit(source, destination);
            return;
        }

        mcam = GetComponent<Camera>();
        var width = mcam.pixelWidth;
        var height = mcam.pixelHeight;

        this.EnsureMaterial();
        this.configuration.ApplyToMaterial(this.mat);

        EnsureArray(ref fullBuffer, 2);
        EnsureRenderTarget(ref fullBuffer[0], width, height, RenderTextureFormat.ARGBHalf, FilterMode.Bilinear);
        EnsureRenderTarget(ref fullBuffer[1], width, height, RenderTextureFormat.ARGBHalf, FilterMode.Bilinear);
        EnsureRenderTarget(ref lowresBuffer, width /4 , height/4, RenderTextureFormat.ARGBFloat, FilterMode.Bilinear);

        frameIndex = (frameIndex + 1)% 16;
        fullBufferIndex = (fullBufferIndex + 1) % 2;

        /* Some code is from playdead TAA. */

        //1. Render low-res buffer.
        float offsetX = (float)offset[frameIndex, 0] ;
        float offsetY = (float)offset[frameIndex, 1] ;
        mat.SetVector("_ProjectionExtents", mcam.GetProjectionExtents(offsetX,offsetY));
        Graphics.Blit(null, lowresBuffer, mat, 0);
        
        //2. Blit low-res buffer with previous image to make full-res result.
        mat.SetVector("_Jitter", new Vector2(offsetX, offsetY));
        mat.SetTexture("_LowresCloudTex", lowresBuffer);
        mat.SetMatrix("_PrevVP", GL.GetGPUProjectionMatrix(mcam.projectionMatrix,false) * prevV);
        mat.SetVector("_ProjectionExtents", mcam.GetProjectionExtents()); 
        Graphics.Blit(fullBuffer[fullBufferIndex], fullBuffer[fullBufferIndex ^ 1], mat, 1);

        //3. blit full-res result with final image.
        mat.SetTexture("_CloudTex", fullBuffer[fullBufferIndex ^ 1]);
        Graphics.Blit(source, destination, mat, 2);

        //4. Cleanup
        prevV = mcam.worldToCameraMatrix;
    }
}