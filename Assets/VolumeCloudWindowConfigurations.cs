using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class VolumeCloudWindowConfigurations : ScriptableObject {
    public CustomTexGenerator testGenerator;

    public First3DTexGenerator first3DTexGenerator;
    public string first3DTexSaveName = "First3DTex";
    public Second3DTexGenerator second3DTexGenerator;
    public string second3DTexSaveName = "Second3DTex";
}
