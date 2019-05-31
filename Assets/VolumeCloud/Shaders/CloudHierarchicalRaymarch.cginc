#include "CloudShaderHelper.cginc"

sampler2D _HiHeightMap;    //Includes hierarchical height map. Every mip level stores max height of sub pixels.
uint _HeightMapSize;

uint _HiHeightMaxLevel;
uint _HiHeightMinLevel;

int2 GetCellIndex(float2 pos, uint level) {
	float2 uv = pos / _WeatherTexSize;
    uint currentLevelSize = _HeightMapSize >> level;
	return (int2)floor(uv * (float)currentLevelSize);
}

float IntersectWithHeightPlane(float3 origin, float3 v, float height) {
    //As suggested by https://docs.unity3d.com/Manual/SL-DataTypesAndPrecision.html and IEEE754
    //On most pc gpus, divide by zero gives a INF result.
    return (height - origin.y) / v.y;
}

float IntersectWithCellBoundary(float3 origin, float3 v, uint zlevel, int2 cellIndex) {
    //Origin is assumed to be inside cell of cellIndex

    uint currentLevelSize = _HeightMapSize >> zlevel;
    float cellSpacing = _WeatherTexSize / currentLevelSize;
    
    //x-axis plane.
    float2 xAxisPlanes = (cellIndex.x + float2(1.0, 0.0)) * cellSpacing;   //Same as float2((cellIndex.x + 0.5) * cellSpacing), (cellIndex.x - 0.5) * cellSpacing))
    float2 xAxisIntersectT = (xAxisPlanes - origin.x) / v.x;

    //z-axis planes.
    float2 zAxisPlanes = (cellIndex.y + float2(0.0, 1.0)) * cellSpacing;
    float2 zAxisIntersectT = (zAxisPlanes - origin.z) / v.z;

    //TODO: Above calculations could be combined into one float4, will that help?

    return min(max(xAxisIntersectT.x, xAxisIntersectT.y), max(zAxisIntersectT.x, zAxisIntersectT.y));
}

float HierarchicalRaymarch(float3 startPos, float3 dir, float maxSampleDistance, int max_sample_count, float raymarchOffset, out float intensity, out float depth, out int iteration_count) {
    float sampleStart, sampleEnd;
	if (!resolve_ray_start_end(startPos, dir, sampleStart, sampleEnd)) {
		intensity = 0.0;
		depth = 1e6;
		return 0;
	}
    float3 sampleStartPos = startPos + dir * sampleStart;
	if (sampleStartPos.y < -200) {	//Below horizon.
		intensity = 0.0;
	    depth = 1e6;
		return 0.0;
	}

	float sample_step = min((sampleEnd - sampleStart) / max_sample_count, 1000);
    float3 v = sample_step * dir;
    float stepSize = length(v);
    float maxStepCount = min(maxSampleDistance, sampleEnd) / stepSize;

	uint currentZLevel = 2;
    float currentStep = sampleStart / stepSize + raymarchOffset;
    
	RaymarchStatus result;
	InitRaymarchStatus(result);

	iteration_count = 0;

	[loop]
    while(currentStep < maxStepCount && iteration_count++ < 64) {
        float3 raypos = startPos + currentStep * v;
        float2 uv = (raypos.xz / _WeatherTexSize) + 0.5;
        float height = tex2Dlod(_HiHeightMap, float4(uv, 0.0, currentZLevel)) * (_CloudEndHeight - _CloudStartHeight )+ _CloudStartHeight;
        int2 oldCellIndex = GetCellIndex(raypos.xz, currentZLevel);

        float rayhitStepSize;
        bool intersected = false;
        if (raypos.y < height) {
            rayhitStepSize = 0.0f;
            intersected = true;
        } else {
			rayhitStepSize = IntersectWithHeightPlane(raypos, v, height);
            if (rayhitStepSize > 0.0f) {
                //tmpRay is the intersection point of the height plane and ray.
                float3 tmpRay = raypos + v * rayhitStepSize;
                int2 newCellIndex = GetCellIndex(tmpRay.xz, currentZLevel);
				intersected = newCellIndex.x == oldCellIndex.x && newCellIndex.y == oldCellIndex.y;
            } else {
                intersected = false;
            }
        }
         
        if (intersected) { //Current raypos is inside cloud of current level.
            //Move raypos to just beyond rayhitStepSize
            currentStep += ceil(rayhitStepSize);            
            if (currentZLevel == _HiHeightMinLevel) { //We can do raymarch now.
				IntegrateRaymarch(startPos, raypos, dir, stepSize, result);
				if (result.intTransmittance < 0.005f) {	//Save gpu, save the world.
					break;
				}
                currentStep += 1.0f;
            } else {
                currentZLevel -= 1;
            }
        } else {    //Reached bound of current cell.
            rayhitStepSize = IntersectWithCellBoundary(raypos, v, currentZLevel, oldCellIndex);
            currentStep += ceil(rayhitStepSize + 0.0001 /*Make sure we move into another cell*/);
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