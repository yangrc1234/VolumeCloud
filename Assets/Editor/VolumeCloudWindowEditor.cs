using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System;

public class VolumeCloudWindowEditor : EditorWindow {
    private VolumeCloudWindowConfigurations config {
        get {
            if (_config == null) {
                _config = AssetDatabase.LoadAssetAtPath<VolumeCloudWindowConfigurations>("Assets/VolumeCloud/Editor/Config.asset");
                if (_config == null) {
                    var newConfig = ScriptableObject.CreateInstance<VolumeCloudWindowConfigurations>();
                    AssetDatabase.CreateAsset(newConfig, "Assets/VolumeCloud/Editor/Config.asset");
              //      AssetDatabase.IsValidFolder(
                    this._config = newConfig;
                }
            }
            return _config;
        }
    }
    private VolumeCloudWindowConfigurations _config;
    private SerializedObject configSO {
        get {
            return _configSO ?? (_configSO = new SerializedObject(config));
        }
    }
    private SerializedObject _configSO;


    private Texture2D testTexPreview;
    private Texture2D firstTexPreview;
    private Texture2D secondTexPreview;

    private Vector2 scrollPos;

    // Add menu named "My Window" to the Window menu
    [MenuItem("Window/VolumeCloud")]
    static void Init() {
        // Get existing open window or if none, make a new one:
        VolumeCloudWindowEditor window = (VolumeCloudWindowEditor)EditorWindow.GetWindow(typeof(VolumeCloudWindowEditor));
        window.Show();
    }

    private void OnGUI() {
        
        EditorGUI.BeginChangeCheck();
        scrollPos = EditorGUILayout.BeginScrollView(scrollPos,GUILayout.Width(position.width),GUILayout.Height(position.height));
        //Test only.
        EditorGUILayout.BeginHorizontal();//Second 3d tex.
        {
            EditorGUILayout.BeginVertical();
            {   //Config area.
                EditorGUILayout.PropertyField(configSO.FindProperty("testGenerator"), true);
                if (GUILayout.Button("Save tex")) {
                    var texture = Utils.GetTex(new NoiseTextureAdapter(config.testGenerator), 128, TextureFormat.RGB24);
                    AssetDatabase.CreateAsset(texture, "Assets/VolumeCloud/" + "TestTex" + ".asset");
                    AssetDatabase.SaveAssets();
                }
            }
            EditorGUILayout.EndVertical();
            if (configSO.FindProperty("testGenerator").isExpanded) {
                EditorGUILayout.BeginVertical(GUILayout.Width(256.0f)); //Preview Area
                {
                    if (GUILayout.Button("Preview")) {
                        testTexPreview = Utils.GetPreviewTex(new NoiseTextureAdapter(config.testGenerator), 128);
                    }
                    if (testTexPreview != null) {
                        GUI.DrawTexture(EditorGUILayout.GetControlRect(false, GUILayout.Width(256.0f),GUILayout.Height(256.0f)), testTexPreview);
                    }
                }
                EditorGUILayout.EndVertical();
            }
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginHorizontal();// First 3d texture.
        {   
            EditorGUILayout.BeginVertical();
            {   //Config area.
                EditorGUILayout.PropertyField(configSO.FindProperty("first3DTexGenerator"), true);
                if (configSO.FindProperty("first3DTexGenerator").isExpanded) {
                    EditorGUILayout.PropertyField(configSO.FindProperty("first3DTexSaveName"));
                    if (GUILayout.Button("Save tex")) {
                        var texture = Utils.GetTex(config.first3DTexGenerator, config.first3DTexGenerator.texResolution);
                        AssetDatabase.CreateAsset(texture, "Assets/VolumeCloud/" + config.first3DTexSaveName + ".asset");
                        AssetDatabase.SaveAssets();
                    }
                }
            }
            EditorGUILayout.EndVertical();
            EditorGUILayout.BeginVertical(GUILayout.Width(256.0f)); ;
            {
                if (GUILayout.Button("Preview"))
                    firstTexPreview = Utils.GetPreviewTex(config.first3DTexGenerator, config.first3DTexGenerator.texResolution);
                if (firstTexPreview != null)
                    GUI.DrawTexture(EditorGUILayout.GetControlRect(false, GUILayout.Width(256.0f), GUILayout.Height(256.0f)), firstTexPreview);
            }
            EditorGUILayout.EndVertical();
        }
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginHorizontal();//Second 3d tex.
        {   
            EditorGUILayout.BeginVertical();
            {   //Config area.
                EditorGUILayout.PropertyField(configSO.FindProperty("second3DTexGenerator"), true);
                if (configSO.FindProperty("second3DTexGenerator").isExpanded) {
                    EditorGUILayout.PropertyField(configSO.FindProperty("second3DTexSaveName"));
                    if (GUILayout.Button("Save tex")) {
                        var texture = Utils.GetTex(config.second3DTexGenerator, config.second3DTexGenerator.texResolution, TextureFormat.RGB24);
                        AssetDatabase.CreateAsset(texture, "Assets/VolumeCloud/"+ config.second3DTexSaveName + ".asset");
                        AssetDatabase.SaveAssets();
                    }
                }
            }
            EditorGUILayout.EndVertical();
            EditorGUILayout.BeginVertical(GUILayout.Width(256.0f)); //Preview Area
            {   
                if (GUILayout.Button("Preview")) {
                    secondTexPreview = Utils.GetPreviewTex(config.second3DTexGenerator, config.second3DTexGenerator.texResolution);
                }
                if (secondTexPreview != null) {
                    GUI.DrawTexture(EditorGUILayout.GetControlRect(false, GUILayout.Width(256.0f), GUILayout.Height(256.0f)), secondTexPreview);
                }
            }
            EditorGUILayout.EndVertical();
        }
        EditorGUILayout.EndHorizontal();
        EditorGUILayout.EndScrollView();
        if (EditorGUI.EndChangeCheck()) {
            configSO.ApplyModifiedProperties();
        }
    }
}
