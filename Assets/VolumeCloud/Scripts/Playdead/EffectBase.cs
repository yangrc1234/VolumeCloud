// Copyright (c) <2015> <Playdead>
// This file is subject to the MIT License as seen in the root of this folder structure (LICENSE.TXT)
// AUTHOR: Lasse Jon Fuglsang Pedersen <lasse@playdead.com>

using UnityEngine;

public abstract class EffectBase : MonoBehaviour
{
    public void EnsureArray<T>(ref T[] array, int size, T initialValue = default(T))
    {
        if (array == null || array.Length != size)
        {
            array = new T[size];
            for (int i = 0; i != size; i++)
                array[i] = initialValue;
        }
    }

    public void EnsureArray<T>(ref T[,] array, int size0, int size1, T defaultValue = default(T))
    {
        if (array == null || array.Length != size0 * size1)
        {
            array = new T[size0, size1];
            for (int i = 0; i != size0; i++)
            {
                for (int j = 0; j != size1; j++)
                    array[i, j] = defaultValue;
            }
        }
    }

    public void EnsureMaterial(ref Material material, Shader shader)
    {
        if (shader != null)
        {
            if (material == null || material.shader != shader)
                material = new Material(shader);
            if (material != null)
                material.hideFlags = HideFlags.DontSave;
        }
        else
        {
            Debug.LogWarning("missing shader", this);
        }
    }

    public void EnsureDepthTexture(Camera camera)
    {
        if ((camera.depthTextureMode & DepthTextureMode.Depth) == 0)
            camera.depthTextureMode |= DepthTextureMode.Depth;
    }

    public void EnsureKeyword(Material material, string name, bool enabled)
    {
        if (enabled != material.IsKeywordEnabled(name))
        {
            if (enabled)
                material.EnableKeyword(name);
            else
                material.DisableKeyword(name);
        }
    }

    public bool EnsureRenderTarget(ref RenderTexture rt, int width, int height, RenderTextureFormat format, FilterMode filterMode, int depthBits = 0, int antiAliasing = 1)
    {
        if (rt != null && (rt.width != width || rt.height != height || rt.format != format || rt.filterMode != filterMode || rt.antiAliasing != antiAliasing))
        {
            RenderTexture.ReleaseTemporary(rt);
            rt = null;
        }
        if (rt == null)
        {
            rt = RenderTexture.GetTemporary(width, height, depthBits, format, RenderTextureReadWrite.Default, antiAliasing);
            rt.filterMode = filterMode;
            rt.wrapMode = TextureWrapMode.Clamp;
            return true;// new target
        }
        return false;// same target
    }

    public void ReleaseRenderTarget(ref RenderTexture rt)
    {
        if (rt != null)
        {
            RenderTexture.ReleaseTemporary(rt);
            rt = null;
        }
    }

    public void DrawFullscreenQuad()
    {
        GL.PushMatrix();
        GL.LoadOrtho();
        GL.Begin(GL.QUADS);
        {
            GL.MultiTexCoord2(0, 0.0f, 0.0f);
            GL.Vertex3(0.0f, 0.0f, 0.0f); // BL

            GL.MultiTexCoord2(0, 1.0f, 0.0f);
            GL.Vertex3(1.0f, 0.0f, 0.0f); // BR

            GL.MultiTexCoord2(0, 1.0f, 1.0f);
            GL.Vertex3(1.0f, 1.0f, 0.0f); // TR

            GL.MultiTexCoord2(0, 0.0f, 1.0f);
            GL.Vertex3(0.0f, 1.0f, 0.0f); // TL
        }
        GL.End();
        GL.PopMatrix();
    }
}