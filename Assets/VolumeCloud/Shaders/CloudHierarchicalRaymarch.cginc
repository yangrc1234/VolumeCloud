#include "CloudShaderHelper.cginc"

sampler2D _HiHeightMap;    //Includes hierarchical height map. Every mip level stores max height of sub pixels.
uint HeightMapSize;
float HeightMapWorldSize;

uint _HiHeightMaxLevel;
uint _HiHeightMinLevel;

float2 GetCellUV(float2 pos){
    return (pos / HeightMapWorldSize) + 0.5;
}

uint2 GetCellIndex(float2 pos, uint level) {
    float2 uv = GetCellUV(pos);
    uint currentLevelSize = HeightMapSize << level;
    return (uint2)(uv * (float)currentLevelSize)
}

float IntersectWithHeightPlane(float3 origin, float3 v, float height, float t) {
    //As suggested by https://docs.unity3d.com/Manual/SL-DataTypesAndPrecision.html and IEEE754
    //On most pc gpus, divide by zero gives a INF result.
    return (height - origin.y) / v.y;
}

float IntersectWithCellBoundary(float3 origin, float3 v, uint zlevel, uint2 cellIndex) {
    //Origin is assumed to be inside cell of cellIndex

    uint currentLevelSize = HeightMapSize << level;
    float2 cellSpacing = HeightMapWorldSize / currentLevelSize;
    
    //x-axis plane.
    float2 xAxisPlanes = (cellIndex.x + float2(0.5, -0.5)) * cellSpacing;   //Same as float2((cellIndex.x + 0.5) * cellSpacing), (cellIndex.x - 0.5) * cellSpacing))
    float2 xAxisIntersectT = (xAxisPlanes - origin.x) / v.x;

    //y-axis planes.
    float2 zAxisPlanes = (cellIndex.y + float2(0.5, -0.5)) * cellSpacing;
    float2 zAxisIntersectT = (zAxisPlanes - origin.z) / v.z;

    //TODO: Above calculations could be combined into one float4, will that help?

    return min(max(xAxisIntersectT.x, xAxisIntersectT.y), max(zAxisIntersectT.x, zAxisIntersectT.y));
}

float HierarchicalRaymarch(float3 startpos, float3 dir, float maxSampleDistance, int max_sample_count, float raymarchOffset, out float intensity, out float depth) {
    float sampleStart, sampleEnd;
	if (!resolve_ray_start_end(startPos, dir, sampleStart, sampleEnd)) {
		intensity = 0.0;
		depth = 1e6;
		return 0;
	}

    float3 sampleStart = startPos + dir * sampleStart;
	if (sampleStart.y < -200) {	//Below horizon.
		intensity = 0.0;
	    depth = 1e6;
		return 0.0;
	}

	float sample_step = min((sampleEnd - sampleStart) / max_sample_count, 1000);
    float3 v = sample_step * dir;
    float stepSize = length(v);
    float stepEnd = min(maxSampleDistance, sampleEnd) / stepSize;
    
	int currentZLevel = 0;
    float currentStep = sampleStart / stepSize;
    
	RaymarchStatus result;
	InitRaymarchStatus(result);

    while(currentStep < stepEnd) {
        float3 raypos = startpos + currentStep * v;
        float2 uv = GetCellUV(raypos);
        float height = tex2Dlod(_HiHeightMap, float4(uv, 0.0, currentZLevel));
        uint2 oldCellIndex = GetCellIndex(raypos.xz, currentZLevel);

        float rayhitStepSize;
        bool intersected = false;
        if (raypos.y < height) {
            rayhitStepSize = 0.0f;
            intersected = true;
        } else {
            rayhitStepSize = IntersectWithHeightPlane(raypos, v, height) 
            if (rayhitStepSize > 0.0f) {
                //tmpRay is the intersection point of the height plane and ray.
                float3 tmpRay = raypos + v * rayhitStepSize;
                uint2 newCellIndex = GetCellIndex(tmpRay.xz, currentZLevel);
                intersected = newCellIndex == oldCellIndex;
            } else {
                intersected = false;
            }
        }
         
        if (intersected) { //Current raypos is inside cloud of current level.
            //Move raypos to just beyond rayhitStepSize
            currentStep += ceil(rayhitStepSize);            
            if (currentZLevel == _HiHeightMinLevel) { //We can do raymarch now.
				IntegrateRaymarch(startPos, rayPos, dir, stepSize, result);
                currentStep += 1.0f;
            } else { 
                currentZLevel -= 1;
            }
        } else {    //Reached bound of current cell.
            rayhitStepSize = IntersectWithCellBoundary(startpos, v, currentZLevel, oldCellIndex);
            currentStep += ceil(rayhitStepSize + 0.00001 /*Make sure we move into another cell*/);
            currentZLevel = min(currentZLevel + 1, _HiHeightMaxLevel);
        }
    }
    
	depth = result.depth / result.depthweightsum;
	if (depth == 0.0f) {
		depth = sampleEnd;
	}
	intensity = result.intensity;
	return (1.0f - result.intTransmittance);	
}