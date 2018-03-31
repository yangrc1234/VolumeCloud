using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Utils {
    public static Texture3D GetTex(ITextureGenerator texGen, int textureResolution, TextureFormat format = TextureFormat.RGBA32) {
        Texture3D result = new Texture3D(textureResolution, textureResolution, textureResolution, format, true);
        Color[] colors = new Color[textureResolution * textureResolution * textureResolution];
        for (int x = 0; x < textureResolution; x++) {
            for (int y = 0; y < textureResolution; y++) {
                for (int z = 0; z < textureResolution; z++) {
                    colors[x * textureResolution * textureResolution + y * textureResolution + z]
                        = texGen.Sample(new Vector3(x, y, z) / textureResolution);
                }
            }
        }
        result.SetPixels(colors);
        result.wrapMode = TextureWrapMode.Repeat;
        result.Apply();
        return result;
    }

    public static Texture2D GetPreviewTex(ITextureGenerator texGen, int textureResolution) {
        Texture2D result = new Texture2D(textureResolution, textureResolution, TextureFormat.RGB24, true);
        Color[] colors = new Color[textureResolution * textureResolution];
        for (int x = 0; x < textureResolution; x++) {
            for (int y = 0; y < textureResolution; y++) {
                colors[x * textureResolution + y]
                    = texGen.Sample(new Vector3(x, y, 0) / textureResolution);
            }
        }
        result.SetPixels(colors);
        result.wrapMode = TextureWrapMode.Repeat;
        result.Apply();
        return result;
    }
}
